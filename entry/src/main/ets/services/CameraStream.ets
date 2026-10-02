import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MjpegParser } from './MjpegParser';

interface PreviewRequest {
  task: http.HttpRequest;
  expiry: number;
}

interface RetiredFrame {
  map: image.PixelMap;
  releaseAt: number;
}

/** One decoder and one pending JPEG; short MJPEG segments have bounded overlap. */
export class CameraStream {
  private task: http.HttpRequest | null = null;
  private frameTasks: PreviewRequest[] = [];
  private frameTimer: number = -1;
  private acceptedFrame: number = -1;
  private generation: number = 0;
  private pending: ArrayBuffer | null = null;
  private decoding: boolean = false;
  private parser: MjpegParser = new MjpegParser();
  private watchdog: number = -1;
  private lastFrameAt: number = 0;
  private lastDataAt: number = 0;
  private receivedBytes: number = 0;
  private startedAt: number = 0;
  private watchdogAt: number = 0;
  private watchdogGap: number = 0;
  private displayed: image.PixelMap | null = null;
  private retired: RetiredFrame[] = [];
  private releaseTimer: number = -1;
  private count: number = 0;
  private reportAt: number = 0;
  private longestFrameGap: number = 0;
  private frameErrors: number = 0;

  start(url: string, onFrame: (frame: image.PixelMap) => void,
    onRate: (fps: number) => void, onFailure: (message: string) => void,
    segmented: boolean = false): void {
    this.stop();
    const current = this.generation;
    this.lastFrameAt = this.reportAt = Date.now();
    this.startedAt = this.watchdogAt = this.lastFrameAt;
    this.watchdogGap = 0;
    this.lastDataAt = this.lastFrameAt;
    this.receivedBytes = 0;
    this.count = 0;
    this.longestFrameGap = this.frameErrors = 0;
    const fail = (message: string): void => {
      if (current !== this.generation) { return; }
      hilog.warn(0x0000, 'AstraCamera',
        'preview stopped: %{public}s; bytes=%{public}s dataAge=%{public}s decoding=%{public}s duration=%{public}s tickGap=%{public}s',
        message, this.receivedBytes.toString(), (Date.now() - this.lastDataAt).toString(),
        this.decoding.toString(), (Date.now() - this.startedAt).toString(), this.watchdogGap.toString());
      this.stop();
      onFailure(message);
    };
    this.watchdog = setInterval(() => {
      const now = Date.now();
      this.watchdogGap = now - this.watchdogAt;
      this.watchdogAt = now;
      if (now - this.lastFrameAt > 2000) { fail('视频串流超时'); }
    }, 500);
    if (segmented) {
      hilog.info(0x0000, 'AstraCamera', 'preview mode=segments fps=30 frames=12');
      this.acceptedFrame = -1;
      const request = (): void => { this.requestSegment(url, current, onFrame, onRate, fail); };
      request();
      // A 12-frame segment lasts about 400 ms; overlap its successor so
      // connection setup and a retransmitting segment do not stop all video.
      this.frameTimer = setInterval(request, 300);
      return;
    }
    hilog.info(0x0000, 'AstraCamera', 'preview mode=mjpeg');
    const task = http.createHttp();
    this.task = task;
    task.on('dataReceive', (data: ArrayBuffer) => {
      if (current !== this.generation) { return; }
      this.lastDataAt = Date.now();
      this.receivedBytes += data.byteLength;
      try {
        const frame = this.parser.push(data);
        if (frame !== null) {
          this.pending = frame;
          this.decode(current, onFrame, onRate, fail);
        }
      } catch (error) { fail((error as Error).message); }
    });
    task.on('dataEnd', () => fail('视频串流已结束'));
    // LAN traffic must go directly to the car even when a system proxy is set.
    task.requestInStream(url, { method: http.RequestMethod.GET,
      header: { 'Accept': 'multipart/x-mixed-replace' }, usingCache: false,
      usingProxy: false, usingProtocol: http.HttpProtocol.HTTP1_1,
      connectTimeout: 2000, readTimeout: 0 }).then((code: number) => {
      if (code !== 200) { fail(`视频请求失败（HTTP ${code}）`); }
    }).catch((error: Error) => fail(`视频串流连接失败：${error.message}`));
  }

  private requestSegment(url: string, current: number,
    onFrame: (frame: image.PixelMap) => void, onRate: (fps: number) => void,
    fail: (message: string) => void): void {
    if (current !== this.generation || this.frameTasks.length >= 3) { return; }
    const task = http.createHttp();
    const parser = new MjpegParser();
    const started = Date.now();
    const request: PreviewRequest = { task: task, expiry: -1 };
    this.frameTasks.push(request);
    let closed: boolean = false;
    const finish = (): void => {
      if (closed) { return; }
      closed = true;
      if (request.expiry >= 0) { clearTimeout(request.expiry); }
      task.off('dataReceive');
      task.off('dataEnd');
      const index = this.frameTasks.indexOf(request);
      if (index >= 0) { this.frameTasks.splice(index, 1); task.destroy(); }
    };
    task.on('dataReceive', (data: ArrayBuffer) => {
      if (closed || current !== this.generation || Date.now() - started > 750) { return; }
      this.lastDataAt = Date.now();
      this.receivedBytes += data.byteLength;
      try {
        const jpeg = parser.push(data);
        if (jpeg === null) { return; }
        if (!Number.isInteger(parser.sequence) || parser.sequence < 0) {
          fail('车端视频缺少帧序号，请更新车端服务');
          return;
        }
        // Overlap repeats source frames. Only a strictly newer source frame
        // can enter the decoder or renew the fresh-frame watchdog.
        if (parser.sequence <= this.acceptedFrame) { return; }
        this.acceptedFrame = parser.sequence;
        this.pending = jpeg;
        this.decode(current, onFrame, onRate, fail);
      } catch (error) { fail((error as Error).message); }
    });
    task.on('dataEnd', finish);
    request.expiry = setTimeout(() => { this.frameErrors++; finish(); }, 900);
    task.requestInStream(url, {
      method: http.RequestMethod.GET, header: { 'Accept': 'multipart/x-mixed-replace' },
      usingCache: false, usingProxy: false, usingProtocol: http.HttpProtocol.HTTP1_1,
      connectTimeout: 800, readTimeout: 1000
    }).then((code: number) => {
      if (closed || current !== this.generation) { return; }
      if (code !== 200) { this.frameErrors++; finish(); }
    }).catch((error: Error) => {
      if (closed || current !== this.generation) { return; }
      this.frameErrors++;
      finish();
    });
  }

  private async decode(current: number, onFrame: (frame: image.PixelMap) => void,
    onRate: (fps: number) => void, fail: (message: string) => void): Promise<void> {
    if (this.decoding) { return; }
    this.decoding = true;
    try {
      while (current === this.generation && this.pending !== null) {
        const jpeg = this.pending;
        this.pending = null;
        const source = image.createImageSource(jpeg);
        let frame: image.PixelMap;
        try { frame = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 }); }
        finally { await source.release(); }
        if (current !== this.generation) { await frame.release(); break; }
        if (this.displayed !== null) {
          this.retired.push({ map: this.displayed, releaseAt: Date.now() + 120 });
        }
        this.displayed = frame;
        onFrame(frame);
        // Give ArkUI time to replace the previous image before releasing it.
        if (this.releaseTimer < 0) {
          this.releaseTimer = setTimeout(() => {
            this.releaseTimer = -1;
            this.releaseRetired();
          }, 120);
        }
        const now = Date.now();
        this.longestFrameGap = Math.max(this.longestFrameGap, now - this.lastFrameAt);
        this.lastFrameAt = now;
        this.count++;
        const elapsed = this.lastFrameAt - this.reportAt;
        if (elapsed >= 1000) {
          const fps = Math.round(this.count * 10000 / elapsed) / 10;
          onRate(fps);
          hilog.info(0x0000, 'AstraCamera', 'decoded fps=%{public}s maxGap=%{public}s frameErrors=%{public}s',
            fps.toString(), this.longestFrameGap.toString(), this.frameErrors.toString());
          this.count = 0;
          this.longestFrameGap = this.frameErrors = 0;
          this.reportAt = this.lastFrameAt;
        }
      }
    } catch (error) { fail('视频解码失败'); }
    finally {
      this.decoding = false;
      // A new connection may have received a JPEG while an old decode finished.
      // Its next packet will start decoding; never publish the old generation.
    }
  }

  private releaseRetired(): void {
    const waiting: RetiredFrame[] = [];
    this.retired.forEach((frame: RetiredFrame) => {
      if (frame.releaseAt <= Date.now()) { frame.map.release().catch(() => {}); }
      else { waiting.push(frame); }
    });
    this.retired = waiting;
    if (waiting.length > 0 && this.releaseTimer < 0) {
      this.releaseTimer = setTimeout(() => { this.releaseTimer = -1; this.releaseRetired(); }, 120);
    }
  }

  stop(): void {
    ++this.generation;
    if (this.watchdog >= 0) { clearInterval(this.watchdog); this.watchdog = -1; }
    if (this.frameTimer >= 0) { clearInterval(this.frameTimer); this.frameTimer = -1; }
    this.frameTasks.forEach((request: PreviewRequest) => {
      if (request.expiry >= 0) { clearTimeout(request.expiry); }
      request.task.off('dataReceive');
      request.task.off('dataEnd');
      request.task.destroy();
    });
    this.frameTasks = [];
    if (this.task !== null) {
      this.task.off('dataReceive');
      this.task.off('dataEnd');
      this.task.destroy();
      this.task = null;
    }
    this.pending = null;
    this.parser.reset();
    if (this.displayed !== null) {
      this.retired.push({ map: this.displayed, releaseAt: Date.now() + 120 });
      this.displayed = null;
    }
    if (this.releaseTimer >= 0) { clearTimeout(this.releaseTimer); }
    this.releaseTimer = setTimeout(() => { this.releaseTimer = -1; this.releaseRetired(); }, 120);
  }
}
