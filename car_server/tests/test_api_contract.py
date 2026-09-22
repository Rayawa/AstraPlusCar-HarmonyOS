import importlib.util
import json
import sys
import threading
import time
import types
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def load_server_module():
    """Load the bridge without importing OpenCV or the physical car SDK."""
    fake_cv2 = types.ModuleType("cv2")
    sys.modules["cv2"] = fake_cv2

    class FakeAction:
        def __init__(self, *args, **kwargs):
            self.update_speed = True
            self.speed_setting = []

        def generate_speed_setting(self, speed, degree=0):
            return [speed, speed, speed, speed]

        def fix_speed(self):
            return None

    actions = types.ModuleType("src.actions")
    for name in (
        "Advance", "BackUp", "SetServo", "ShiftLeft", "ShiftRight",
        "SpinAntiClockwise", "SpinClockwise", "Stop", "TurnLeft", "TurnRight"
    ):
        setattr(actions, name, FakeAction)

    class FakeController:
        def __init__(self):
            self.actions = []

        def execute(self, _action):
            self.actions.append(_action)
            return 0

    utils = types.ModuleType("src.utils")
    utils.Controller = FakeController
    src = types.ModuleType("src")
    sys.modules["src"] = src
    sys.modules["src.actions"] = actions
    sys.modules["src.utils"] = utils

    path = Path(__file__).resolve().parents[1] / "car_api_server.py"
    spec = importlib.util.spec_from_file_location("car_api_server_for_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SERVER = load_server_module()


class FakeRuntime:
    def __init__(self):
        self.calls = []
        self.servo_error = None

    def move(self, action, speed, degree, sequence=None):
        self.calls.append(("move", action, speed, degree, sequence))
        return True

    def stop(self, sequence=None):
        self.calls.append(("stop", sequence))
        return True

    def servo(self, vertical, horizontal, sequence=None):
        if self.servo_error is not None:
            raise self.servo_error
        self.calls.append(("servo", vertical, horizontal, sequence))
        return True


class FakeCamera:
    device = 0

    def latest_jpeg(self):
        return b"fake-jpeg"

    def last_error(self):
        return ""

    def capture(self, _directory):
        return "/tmp/car_20260922.jpg"


class ApiContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runtime = FakeRuntime()
        SERVER.CarApiHandler.runtime = cls.runtime
        SERVER.CarApiHandler.camera = FakeCamera()
        SERVER.CarApiHandler.capture_dir = "/tmp"
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), SERVER.CarApiHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = "http://127.0.0.1:%d" % cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def post(self, path, payload):
        body = json.dumps(payload).encode("utf-8")
        request = Request(
            self.base_url + path,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=2) as response:
            return response.status, json.loads(response.read().decode("utf-8"))

    def test_health_and_frame(self):
        with urlopen(self.base_url + "/api/health", timeout=2) as response:
            payload = json.loads(response.read().decode("utf-8"))
        self.assertEqual(200, response.status)
        self.assertTrue(payload["ok"])
        self.assertEqual("1.1.0", payload["apiVersion"])
        self.assertTrue(payload["cameraReady"])

        with urlopen(self.base_url + "/api/camera/frame", timeout=2) as response:
            self.assertEqual("image/jpeg", response.headers["Content-Type"])
            self.assertEqual(b"fake-jpeg", response.read())

    def test_move_stop_and_servo(self):
        status, payload = self.post(
            "/api/control/move",
            {"action": "forward", "speed": 42, "degree": 1.1, "sequence": 100},
        )
        self.assertEqual(200, status)
        self.assertTrue(payload["ok"])
        self.assertIn(("move", "forward", 42, 1.1, 100), self.runtime.calls)

        status, _ = self.post(
            "/api/control/servo",
            {"vertical": 90, "horizontal": 65, "sequence": 102},
        )
        self.assertEqual(200, status)
        self.assertIn(("servo", 90, 65, 102), self.runtime.calls)

        status, _ = self.post("/api/control/stop", {"sequence": 101})
        self.assertEqual(200, status)
        self.assertIn(("stop", 101), self.runtime.calls)

    def test_capture(self):
        status, payload = self.post("/api/camera/capture", {})
        self.assertEqual(201, status)
        self.assertTrue(payload["ok"])
        self.assertEqual("car_20260922.jpg", payload["filename"])

    def test_non_object_json_is_rejected(self):
        request = Request(
            self.base_url + "/api/control/move",
            data=b"[]",
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(HTTPError) as context:
            urlopen(request, timeout=2)
        error = context.exception
        self.assertEqual(400, error.code)
        payload = json.loads(error.read().decode("utf-8"))
        error.close()
        self.assertEqual("json_object_required", payload["error"])

    def test_controller_failure_is_service_unavailable(self):
        self.runtime.servo_error = OSError("I/O operation on closed file.")
        try:
            with self.assertRaises(HTTPError) as context:
                self.post(
                    "/api/control/servo",
                    {"vertical": 90, "horizontal": 65, "sequence": 103},
                )
            error = context.exception
            self.assertEqual(503, error.code)
            payload = json.loads(error.read().decode("utf-8"))
            error.close()
            self.assertEqual("controller_unavailable", payload["error"])
        finally:
            self.runtime.servo_error = None

    def test_non_finite_servo_value_is_bad_request(self):
        with self.assertRaises(HTTPError) as context:
            self.post(
                "/api/control/servo",
                {"vertical": float("inf"), "horizontal": 65, "sequence": 104},
            )
        error = context.exception
        self.assertEqual(400, error.code)
        error.close()


class RuntimeSafetyTest(unittest.TestCase):
    def test_speed_clamping_and_watchdog_stop(self):
        runtime = SERVER.CarRuntime(watchdog_seconds=0.03)
        try:
            runtime.move(SERVER.ActionNames.FORWARD, 999, 1.1)
            self.assertTrue(runtime.moving)
            move_action = runtime.controller.actions[-1]
            self.assertEqual([60, 60, 60, 60], move_action.speed_setting)
            time.sleep(0.15)
            self.assertFalse(runtime.moving)
        finally:
            runtime.close()

    def test_late_drive_command_is_ignored_after_stop(self):
        runtime = SERVER.CarRuntime(watchdog_seconds=1)
        try:
            self.assertTrue(runtime.move(SERVER.ActionNames.FORWARD, 35, 1.1, 200))
            self.assertTrue(runtime.stop(202))
            action_count = len(runtime.controller.actions)
            self.assertFalse(runtime.move(SERVER.ActionNames.BACKWARD, 35, 1.1, 201))
            self.assertEqual(action_count, len(runtime.controller.actions))
            self.assertFalse(runtime.moving)
        finally:
            runtime.close()

    def test_late_servo_command_is_ignored(self):
        runtime = SERVER.CarRuntime(watchdog_seconds=1)
        try:
            self.assertTrue(runtime.servo(90, 65, 302))
            action_count = len(runtime.controller.actions)
            self.assertFalse(runtime.servo(20, 20, 301))
            self.assertEqual(action_count, len(runtime.controller.actions))
        finally:
            runtime.close()

    def test_watchdog_rechecks_latest_move_atomically(self):
        runtime = SERVER.CarRuntime(watchdog_seconds=1)
        try:
            runtime.move(SERVER.ActionNames.FORWARD, 35, 1.1)
            action_count = len(runtime.controller.actions)
            self.assertFalse(runtime._stop_if_watchdog_expired(time.monotonic()))
            self.assertEqual(action_count, len(runtime.controller.actions))
            self.assertTrue(runtime.moving)
        finally:
            runtime.close()

    def test_closed_runtime_rejects_new_commands(self):
        runtime = SERVER.CarRuntime(watchdog_seconds=1)
        runtime.close()
        with self.assertRaisesRegex(RuntimeError, "runtime_closed"):
            runtime.move(SERVER.ActionNames.FORWARD, 35, 1.1)


class CameraWorkerSafetyTest(unittest.TestCase):
    def test_camera_reopens_after_initial_failure(self):
        class FakeCapture:
            def read(self):
                return True, object()

            def release(self):
                return None

        class FakeJpeg:
            def tobytes(self):
                return b"recovered-jpeg"

        camera = SERVER.CameraWorker()
        attempts = []

        def open_capture():
            attempts.append(len(attempts) + 1)
            if len(attempts) == 1:
                raise RuntimeError("temporary_camera_failure")
            return FakeCapture()

        original_interval = SERVER.ServerDefaults.CAMERA_REOPEN_SECONDS
        original_quality_key = getattr(SERVER.cv2, "IMWRITE_JPEG_QUALITY", None)
        original_imencode = getattr(SERVER.cv2, "imencode", None)
        SERVER.ServerDefaults.CAMERA_REOPEN_SECONDS = 0.01
        SERVER.cv2.IMWRITE_JPEG_QUALITY = 1
        SERVER.cv2.imencode = lambda *_args, **_kwargs: (True, FakeJpeg())
        camera._open_capture = open_capture
        try:
            camera.start()
            deadline = time.monotonic() + 1
            while camera.latest_jpeg() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertGreaterEqual(len(attempts), 2)
            self.assertEqual(b"recovered-jpeg", camera.latest_jpeg())
            self.assertEqual("", camera.last_error())
        finally:
            camera.stop()
            SERVER.ServerDefaults.CAMERA_REOPEN_SECONDS = original_interval
            if original_quality_key is None:
                del SERVER.cv2.IMWRITE_JPEG_QUALITY
            else:
                SERVER.cv2.IMWRITE_JPEG_QUALITY = original_quality_key
            if original_imencode is None:
                del SERVER.cv2.imencode
            else:
                SERVER.cv2.imencode = original_imencode


if __name__ == "__main__":
    unittest.main()
