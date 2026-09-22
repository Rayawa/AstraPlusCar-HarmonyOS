#!/usr/bin/env python3
"""HTTP bridge for the Ascend DevKit E2E Car sample.

Copy this file into the sample's ``Car/python`` directory and run it instead of
``main.py --mode manual`` while using the HarmonyOS application.
"""

import argparse
import json
import os
import signal
import threading
import time
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Optional, Type
from urllib.parse import urlparse

import cv2

from src.actions import (
    Advance,
    BackUp,
    SetServo,
    ShiftLeft,
    ShiftRight,
    SpinAntiClockwise,
    SpinClockwise,
    Stop,
    TurnLeft,
    TurnRight,
)
from src.utils import Controller


class ServerDefaults:
    API_VERSION = "1.1.0"
    HOST = "0.0.0.0"
    PORT = 8080
    CAMERA_DEVICE = 0
    CAMERA_WIDTH = 1280
    CAMERA_HEIGHT = 720
    CAMERA_FPS = 30
    JPEG_QUALITY = 82
    JPEG_INTERVAL_SECONDS = 0.1
    CAMERA_RETRY_SECONDS = 0.05
    CAMERA_REOPEN_SECONDS = 3.0
    CAMERA_MAX_READ_FAILURES = 20
    WATCHDOG_SECONDS = 0.9
    WATCHDOG_POLL_SECONDS = 0.1
    CAMERA_JOIN_SECONDS = 2
    WATCHDOG_JOIN_SECONDS = 1
    MAX_REQUEST_BYTES = 64 * 1024
    SPEED_MIN = 25
    SPEED_MAX = 60
    DEFAULT_SPEED = 35
    DEGREE_MIN = 0.1
    DEGREE_MAX = 2.0
    DEFAULT_DEGREE = 1.1
    DEFAULT_VERTICAL = 90
    DEFAULT_HORIZONTAL = 65
    SERVO_MIN = 0
    SERVO_MAX = 180


class ApiRoutes:
    HEALTH = "/api/health"
    FRAME = "/api/camera/frame"
    MOVE = "/api/control/move"
    STOP = "/api/control/stop"
    SERVO = "/api/control/servo"
    CAPTURE = "/api/camera/capture"


class ActionNames:
    FORWARD = "forward"
    BACKWARD = "backward"
    LEFT = "left"
    RIGHT = "right"
    SHIFT_LEFT = "shift_left"
    SHIFT_RIGHT = "shift_right"
    SPIN_LEFT = "spin_left"
    SPIN_RIGHT = "spin_right"


class CameraWorker:
    """Owns the camera device and always exposes the newest JPEG frame."""

    def __init__(
        self,
        device: int = ServerDefaults.CAMERA_DEVICE,
        width: int = ServerDefaults.CAMERA_WIDTH,
        height: int = ServerDefaults.CAMERA_HEIGHT,
        fps: int = ServerDefaults.CAMERA_FPS,
    ):
        self.device = device
        self.width = width
        self.height = height
        self.fps = fps
        self._frame = None
        self._jpeg: Optional[bytes] = None
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, name="camera", daemon=True)
        self._started = False
        self._last_error = ""

    def start(self) -> None:
        if not self._started:
            self._started = True
            self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._started and self._thread.is_alive():
            self._thread.join(timeout=ServerDefaults.CAMERA_JOIN_SECONDS)

    def latest_jpeg(self) -> Optional[bytes]:
        with self._lock:
            return self._jpeg

    def last_error(self) -> str:
        with self._lock:
            return self._last_error

    def capture(self, directory: str) -> Optional[str]:
        with self._lock:
            if self._frame is None:
                return None
            frame = self._frame.copy()
        try:
            os.makedirs(directory, exist_ok=True)
            filename = datetime.now().strftime("car_%Y%m%d_%H%M%S_%f.jpg")
            path = os.path.join(directory, filename)
            if not cv2.imwrite(path, frame):
                return None
        except Exception as error:
            self._record_error(f"capture_failed: {error}")
            return None
        return path

    def _loop(self) -> None:
        while not self._stop.is_set():
            capture = None
            try:
                capture = self._open_capture()
                self._capture_frames(capture)
            except Exception as error:
                self._record_error(f"camera_worker_failed: {error}")
            finally:
                if capture is not None:
                    try:
                        capture.release()
                    except Exception:
                        pass
            if not self._stop.is_set():
                self._stop.wait(ServerDefaults.CAMERA_REOPEN_SECONDS)

    def _open_capture(self):
        capture = cv2.VideoCapture()
        opened = capture.open(self.device, apiPreference=cv2.CAP_V4L2)
        if not opened or (hasattr(capture, "isOpened") and not capture.isOpened()):
            capture.release()
            raise RuntimeError("camera_open_failed")
        capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc("M", "J", "P", "G"))
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
        capture.set(cv2.CAP_PROP_FPS, self.fps)
        return capture

    def _capture_frames(self, capture) -> None:
        next_encode = 0.0
        read_failures = 0
        while not self._stop.is_set():
            ok, frame = capture.read()
            if not ok or frame is None:
                read_failures += 1
                if read_failures >= ServerDefaults.CAMERA_MAX_READ_FAILURES:
                    raise RuntimeError("camera_read_failed")
                self._stop.wait(ServerDefaults.CAMERA_RETRY_SECONDS)
                continue
            read_failures = 0
            now = time.monotonic()
            if now < next_encode:
                with self._lock:
                    self._frame = frame
                continue
            encoded, jpeg = cv2.imencode(
                ".jpg",
                frame,
                [cv2.IMWRITE_JPEG_QUALITY, ServerDefaults.JPEG_QUALITY],
            )
            if encoded:
                with self._lock:
                    self._frame = frame
                    self._jpeg = jpeg.tobytes()
                    self._last_error = ""
                next_encode = now + ServerDefaults.JPEG_INTERVAL_SECONDS

    def _record_error(self, message: str) -> None:
        with self._lock:
            self._last_error = message
            # Do not report or save a stale frame while the camera reconnects.
            self._frame = None
            self._jpeg = None


class CarRuntime:
    """Serializes motor commands and enforces a network-loss stop watchdog."""

    ACTIONS: Dict[str, Type] = {
        ActionNames.FORWARD: Advance,
        ActionNames.BACKWARD: BackUp,
        ActionNames.LEFT: TurnLeft,
        ActionNames.RIGHT: TurnRight,
        ActionNames.SHIFT_LEFT: ShiftLeft,
        ActionNames.SHIFT_RIGHT: ShiftRight,
        ActionNames.SPIN_LEFT: SpinAntiClockwise,
        ActionNames.SPIN_RIGHT: SpinClockwise,
    }

    def __init__(self, watchdog_seconds: float = ServerDefaults.WATCHDOG_SECONDS):
        self.controller = Controller()
        self.watchdog_seconds = watchdog_seconds
        self.last_move = 0.0
        self.moving = False
        self.latest_command_sequence = 0
        self.latest_servo_sequence = 0
        self._closed = False
        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._watchdog_loop, name="drive-watchdog", daemon=True)
        self._thread.start()

    def close(self) -> None:
        self._stop.set()
        try:
            with self._lock:
                if self._closed:
                    return
                try:
                    self.controller.execute(Stop())
                    self.moving = False
                finally:
                    self._closed = True
        except Exception as error:
            print(f"Failed to stop car during shutdown: {error}")
        finally:
            self._thread.join(timeout=ServerDefaults.WATCHDOG_JOIN_SECONDS)

    def move(self, name: str, speed: int, degree: float, sequence: Optional[int] = None) -> bool:
        if name not in self.ACTIONS:
            raise ValueError("unsupported action")
        speed = max(ServerDefaults.SPEED_MIN, min(ServerDefaults.SPEED_MAX, int(speed)))
        degree = max(ServerDefaults.DEGREE_MIN, min(ServerDefaults.DEGREE_MAX, float(degree)))
        action_type = self.ACTIONS[name]
        action = action_type(degree=degree) if name in (ActionNames.LEFT, ActionNames.RIGHT) else action_type()
        action.update_speed = False
        action.speed_setting = action.generate_speed_setting(speed=speed, degree=degree)
        action.fix_speed()
        with self._lock:
            self._ensure_open()
            if not self._accept_sequence(sequence):
                return False
            self.controller.execute(action)
            self.last_move = time.monotonic()
            self.moving = True
            return True

    def stop(self, sequence: Optional[int] = None) -> bool:
        with self._lock:
            self._ensure_open()
            if not self._accept_sequence(sequence):
                return False
            self.controller.execute(Stop())
            self.moving = False
            return True

    def servo(self, vertical: int, horizontal: int, sequence: Optional[int] = None) -> bool:
        vertical = max(ServerDefaults.SERVO_MIN, min(ServerDefaults.SERVO_MAX, int(vertical)))
        horizontal = max(ServerDefaults.SERVO_MIN, min(ServerDefaults.SERVO_MAX, int(horizontal)))
        with self._lock:
            self._ensure_open()
            if sequence is not None and sequence <= self.latest_servo_sequence:
                return False
            if sequence is not None:
                self.latest_servo_sequence = sequence
            self.controller.execute(SetServo(servo=[vertical, horizontal]))
            return True

    def _accept_sequence(self, sequence: Optional[int]) -> bool:
        if sequence is None:
            return True
        if sequence <= self.latest_command_sequence:
            return False
        self.latest_command_sequence = sequence
        return True

    def _ensure_open(self) -> None:
        if self._closed:
            raise RuntimeError("runtime_closed")

    def _stop_if_watchdog_expired(self, now: float) -> bool:
        with self._lock:
            if self._closed or not self.moving or now - self.last_move <= self.watchdog_seconds:
                return False
            self.controller.execute(Stop())
            self.moving = False
            return True

    def _watchdog_loop(self) -> None:
        while not self._stop.wait(ServerDefaults.WATCHDOG_POLL_SECONDS):
            try:
                self._stop_if_watchdog_expired(time.monotonic())
            except Exception as error:
                # Keep the watchdog alive so a transient serial error can be retried.
                print(f"Watchdog stop failed: {error}")


class CarApiHandler(BaseHTTPRequestHandler):
    server_version = f"AstraDrive/{ServerDefaults.API_VERSION}"
    runtime: CarRuntime
    camera: CameraWorker
    capture_dir: str

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self._cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        try:
            path = urlparse(self.path).path
            if path == ApiRoutes.HEALTH:
                self._json(
                    HTTPStatus.OK,
                    {
                        "ok": True,
                        "apiVersion": ServerDefaults.API_VERSION,
                        "cameraReady": self.camera.latest_jpeg() is not None,
                        "cameraDevice": self.camera.device,
                        "cameraError": self.camera.last_error(),
                    },
                )
                return
            if path == ApiRoutes.FRAME:
                frame = self.camera.latest_jpeg()
                if frame is None:
                    self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"ok": False, "error": "camera_not_ready"})
                    return
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(frame)))
                self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
                self._cors_headers()
                self.end_headers()
                self._write(frame)
                return
            self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not_found"})
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as error:
            print(f"GET handler failed: {error}")
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": "internal_error"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        try:
            payload = self._read_json()
            if path == ApiRoutes.MOVE:
                action = str(payload.get("action", ""))
                if action not in CarRuntime.ACTIONS:
                    raise ValueError("unsupported_action")
                speed = int(payload.get("speed", ServerDefaults.DEFAULT_SPEED))
                degree = float(payload.get("degree", ServerDefaults.DEFAULT_DEGREE))
                sequence = self._command_sequence(payload)
                try:
                    accepted = self.runtime.move(
                        action,
                        speed,
                        degree,
                        sequence,
                    )
                except Exception as error:
                    self._controller_unavailable(path, error)
                    return
                self._json(HTTPStatus.OK, {"ok": True, "accepted": accepted})
                return
            if path == ApiRoutes.STOP:
                try:
                    accepted = self.runtime.stop(self._command_sequence(payload))
                except Exception as error:
                    self._controller_unavailable(path, error)
                    return
                self._json(HTTPStatus.OK, {"ok": True, "accepted": accepted})
                return
            if path == ApiRoutes.SERVO:
                vertical = int(payload.get("vertical", ServerDefaults.DEFAULT_VERTICAL))
                horizontal = int(payload.get("horizontal", ServerDefaults.DEFAULT_HORIZONTAL))
                sequence = self._command_sequence(payload)
                try:
                    accepted = self.runtime.servo(vertical, horizontal, sequence)
                except Exception as error:
                    self._controller_unavailable(path, error)
                    return
                self._json(HTTPStatus.OK, {"ok": True, "accepted": accepted})
                return
            if path == ApiRoutes.CAPTURE:
                saved = self.camera.capture(self.capture_dir)
                if saved is None:
                    self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"ok": False, "error": "camera_not_ready"})
                else:
                    self._json(HTTPStatus.CREATED, {"ok": True, "filename": os.path.basename(saved)})
                return
            self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not_found"})
        except (BrokenPipeError, ConnectionResetError):
            return
        except (ValueError, TypeError, OverflowError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self._json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(error)})
        except Exception as error:
            print(f"POST handler failed: {type(error).__name__}: {error}")
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": "internal_error"})

    def _controller_unavailable(self, path: str, error: Exception) -> None:
        print(f"Controller operation failed for {path}: {type(error).__name__}: {error}")
        self._json(
            HTTPStatus.SERVICE_UNAVAILABLE,
            {"ok": False, "error": "controller_unavailable"},
        )

    def log_message(self, format_string: str, *args) -> None:
        print("[%s] %s" % (self.log_date_time_string(), format_string % args))

    def _read_json(self) -> dict:
        size = int(self.headers.get("Content-Length", "0"))
        if size == 0:
            return {}
        if size < 0 or size > ServerDefaults.MAX_REQUEST_BYTES:
            raise ValueError("request_too_large")
        payload = json.loads(self.rfile.read(size).decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("json_object_required")
        return payload

    def _command_sequence(self, payload: dict) -> Optional[int]:
        value = payload.get("sequence")
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
            raise ValueError("invalid_sequence")
        sequence = int(value)
        if sequence <= 0:
            raise ValueError("invalid_sequence")
        return sequence

    def _json(self, status: HTTPStatus, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors_headers()
        self.end_headers()
        self._write(body)

    def _write(self, body: bytes) -> None:
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")


class CarHttpServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Astra Drive HTTP bridge")
    parser.add_argument("--host", default=ServerDefaults.HOST)
    parser.add_argument("--port", default=ServerDefaults.PORT, type=int)
    parser.add_argument("--camera", default=ServerDefaults.CAMERA_DEVICE, type=int)
    parser.add_argument("--capture-dir", default=os.path.join(os.getcwd(), "capture"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    server = None
    runtime = None
    camera = None

    try:
        # Bind first so an occupied port cannot leave serial/camera resources open.
        server = CarHttpServer((args.host, args.port), CarApiHandler)
        runtime = CarRuntime()
        camera = CameraWorker(device=args.camera)
        CarApiHandler.camera = camera
        CarApiHandler.runtime = runtime
        CarApiHandler.capture_dir = args.capture_dir
        camera.start()

        def shutdown(_signum, _frame) -> None:
            threading.Thread(target=server.shutdown, daemon=True).start()

        signal.signal(signal.SIGINT, shutdown)
        signal.signal(signal.SIGTERM, shutdown)
        print(f"Astra Drive API listening on http://{args.host}:{args.port}")
        server.serve_forever()
    finally:
        if server is not None:
            server.server_close()
        if runtime is not None:
            runtime.close()
        if camera is not None:
            camera.stop()


if __name__ == "__main__":
    main()
