import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MjpegParser } from './MjpegParser';

interface RetiredFrame {
  map: image.PixelMap;
  releaseAt: number;
}

/** One streaming connection, one decoder, and at most one pending JPEG. */
export class CameraStream {
  private task: http.HttpRequest | null = null;
  private generation: number = 0;
  private pending: ArrayBuffer | null = null;
  private decoding: boolean = false;
  private parser: MjpegParser = new MjpegParser();
  private watchdog: number = -1;
  private lastFrameAt: number = 0;
  private lastDataAt: number = 0;
  private receivedBytes: number = 0;
  private displayed: image.PixelMap | null = null;
  private retired: RetiredFrame[] = [];
  private releaseTimer: number = -1;
  private count: number = 0;
  private reportAt: number = 0;

  start(url: string, onFrame: (frame: image.PixelMap) => void,
    onRate: (fps: number) => void, onFailure: (message: string) => void): void {
    this.stop();
    const current = this.generation;
    const task = http.createHttp();
    this.task = task;
    this.lastFrameAt = this.reportAt = Date.now();
    this.lastDataAt = this.lastFrameAt;
    this.receivedBytes = 0;
    this.count = 0;
    const fail = (message: string): void => {
      if (current !== this.generation) { return; }
      hilog.warn(0x0000, 'AstraCamera',
        'stream stopped: %{public}s; bytes=%{public}s dataAge=%{public}s decoding=%{public}s',
        message, this.receivedBytes.toString(), (Date.now() - this.lastDataAt).toString(),
        this.decoding.toString());
      this.stop();
      onFailure(message);
    };
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
    this.watchdog = setInterval(() => {
      if (Date.now() - this.lastFrameAt > 2000) { fail('视频串流超时'); }
    }, 500);
    task.requestInStream(url, { method: http.RequestMethod.GET,
      header: { 'Accept': 'multipart/x-mixed-replace' }, usingCache: false,
      connectTimeout: 2000, readTimeout: 0 }).then((code: number) => {
      if (code !== 200) { fail(`视频请求失败（HTTP ${code}）`); }
    }).catch((error: Error) => fail(`视频串流连接失败：${error.message}`));
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
        this.lastFrameAt = Date.now();
        this.count++;
        const elapsed = this.lastFrameAt - this.reportAt;
        if (elapsed >= 1000) {
          const fps = Math.round(this.count * 10000 / elapsed) / 10;
          onRate(fps);
          hilog.info(0x0000, 'AstraCamera', 'decoded fps=%{public}s', fps.toString());
          this.count = 0;
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
