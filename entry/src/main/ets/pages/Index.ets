import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { curves, LengthMetrics, window } from '@kit.ArkUI';
import { HdsNavigation } from '@hms.hds.hdsBaseComponent';
import { hdsEffect, hdsMaterial, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { CaptureStore, CaptureItem } from '../services/CaptureStore';
import { ConnectionIndicators } from '../components/ConnectionIndicators';
import { DriveControls } from '../components/DriveControls';
import { LandscapeControlPad } from '../components/LandscapeControlPad';
import { RadarOverlay } from '../components/RadarOverlay';
import { RadarWarningHud } from '../components/RadarWarningHud';
import { RadarPresentation } from '../services/RadarPresentation';
import { CaptureGallery } from '../components/CaptureGallery';
import { PhoneApi, PhoneStatus, PhoneSession, PhoneResult } from '../services/PhoneApi';
import { LocalNetworkRoute } from '../services/LocalNetworkRoute';
import { Haptics } from '../services/Haptics';
import { image } from '@kit.ImageKit';
import { CameraStream } from '../services/CameraStream';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Entry
@Component
struct Index {
  private readonly api: PhoneApi = new PhoneApi();
  private readonly cameraStream: CameraStream = new CameraStream();
  private readonly networkRoute: LocalNetworkRoute = new LocalNetworkRoute();
  private readonly pageStack: NavPathStack = new NavPathStack();
  private readonly connectionScroller: Scroller = new Scroller();
  private captureStore: CaptureStore | null = null;
  private statusTimer: number = -1;
  private renewTimer: number = -1;
  private speedTimer: number = -1;
  private controlGeneration: number = 0;
  private screenGeneration: number = 0;
  private serial: number = 0;
  private sessionId: string = '';
  private sessionOpening: Promise<string> | null = null;
  private sessionOpeningGeneration: number = -1;
  private commandId: string = '';
  private pressedKey: string = '';
  private renewing: boolean = false;
  private speedBusy: boolean = false;
  private speedDesired: number = 40;
  private speedPending: boolean = false;
  private failures: number = 0;
  private connectionGeneration: number = 0;
  private reconnectTimer: number = -1;
  private reconnectAttempt: number = 0;
  private connectionNotice: string = '连接小车';
  private startupConnectionAttempted: boolean = false;
  private connectionPreferences: preferences.Preferences | null = null;
  private connectionOpening: Promise<void> | null = null;
  private connectionCleanup: Promise<void> = Promise.resolve();
  private statusPollingGeneration: number = -1;
  private bootId: string = '';
  private previewReady: boolean = false;
  private lastUnavailableAt: number = 0;
  private lastLandscapeSliderVibration: number = 0;
  private disposed: boolean = false;
  private homeEntranceStarted: boolean = false;
  private homeTimers: number[] = [];
  private connectionTimers: number[] = [];

  @State endpoint: string = 'http://192.168.8.204:8080';
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State connectionWanted: boolean = false;
  @State message: string = '连接小车 Wi-Fi 后输入车端地址';
  @State cameraFrame: image.PixelMap | undefined = undefined;
  @State previewFps: number = 0;
  @State cameraStatus: string = 'waiting';
  @State lidarPoints: number = 0;
  @State radarFreshness: string = '等待扫描';
  @State frontMm: number | null = null;
  @State sector90Mm: number | null = null;
  @State sector270Mm: number | null = null;
  @State speed: number = 40;
  @State sliderSpeed: number = 40;
  @State activeKey: string = '';
  @State captureBusy: boolean = false;
  @State lidarReady: boolean = false;
  @State captures: CaptureItem[] = [];
  @State showConnection: boolean = false;
  @State homeAnimStep1: number = 0;
  @State homeAnimStep2: number = 0;
  @State homeAnimStep3: number = 0;
  @State connectionAnimStep1: number = 0;
  @State connectionAnimStep2: number = 0;
  @State connectionAnimStep3: number = 0;
  @State previewPressed: boolean = false;
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  @State landscapeContentWidth: number = 0;
  @State landscapeContentHeight: number = 0;
  @State isLandscape: boolean = false;

  private updateViewport(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return; }
    const landscape: boolean = width > height;
    if (landscape !== this.isLandscape && this.pressedKey.length > 0) {
      this.endAction(this.pressedKey);
    }
    this.viewportWidth = width;
    this.viewportHeight = height;
    this.isLandscape = landscape;
  }

  // The landscape surface is the whole window: HdsNavigation's title bar is hidden in
  // landscape, so no empty band is reserved behind it. A fixed 16:9 feed is centred
  // inside that surface, which keeps symmetric bands instead of one bottom gap.
  private surfaceWidth(): number {
    return this.landscapeContentWidth || this.viewportWidth;
  }

  private surfaceHeight(): number {
    return this.landscapeContentHeight || this.viewportHeight;
  }

  private pictureWidth(): number {
    return Math.min(this.surfaceWidth(), this.surfaceHeight() * 16 / 9);
  }

  private pictureHeight(): number {
    return this.pictureWidth() * 9 / 16;
  }

  private padSize(): number {
    return Math.min(188, Math.max(132, this.pictureHeight() * 0.47));
  }

  private padInset(): number {
    return Math.min(28, Math.max(16, this.pictureHeight() * 0.045));
  }

  private messageWidth(): number {
    return Math.max(120,
      Math.min(280, this.pictureWidth() - 2 * (this.padSize() + this.padInset()) - 24));
  }

  aboutToAppear(): void {
    this.disposed = false;
    this.captureStore = new CaptureStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.refreshCaptures();
    this.startHomeEntrance();
    this.restoreLastConnection();
  }

  private restoreLastConnection(): void {
    if (this.startupConnectionAttempted) { return; }
    this.startupConnectionAttempted = true;
    try {
      this.connectionPreferences = preferences.getPreferencesSync(
        this.getUIContext().getHostContext() as common.UIAbilityContext, { name: 'car_connection' });
      const saved = this.connectionPreferences.getSync('last_endpoint', '');
      if (typeof saved !== 'string') { return; }
      const endpoint = PhoneApi.normalizeEndpoint(saved);
      if (endpoint.length === 0 || this.disposed || this.connectionWanted) { return; }
      this.endpoint = endpoint;
      this.connect(false, true);
    } catch (error) {
      hilog.warn(0xA57A, 'AstraConnection', 'Unable to load last endpoint: %{public}s', (error as Error).message);
    }
  }

  private rememberConnection(): void {
    if (this.connectionPreferences === null) { return; }
    try {
      this.connectionPreferences.putSync('last_endpoint', PhoneApi.normalizeEndpoint(this.endpoint));
      this.connectionPreferences.flush().catch((error: Error) => {
        hilog.warn(0xA57A, 'AstraConnection', 'Unable to save last endpoint: %{public}s', error.message);
      });
    } catch (error) {
      hilog.warn(0xA57A, 'AstraConnection', 'Unable to save last endpoint: %{public}s', (error as Error).message);
    }
  }

  private showConnectionToast(message: string): void {
    if (this.disposed) { return; }
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (error) {
      // A disappearing window must not affect connection cleanup.
    }
  }

  aboutToDisappear(): void {
    this.clearEntranceTimers(this.homeTimers);
    this.clearEntranceTimers(this.connectionTimers);
    this.disposed = true;
    this.disconnect();
  }

  private clearEntranceTimers(timers: number[]): void {
    timers.forEach((timer: number) => clearTimeout(timer));
    timers.length = 0;
  }

  private startHomeEntrance(): void {
    if (this.homeEntranceStarted) { return; }
    this.homeEntranceStarted = true;
    const curve = curves.springMotion(0.35, 0.75);
    this.homeTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.homeAnimStep1 = 1), 100));
    this.homeTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.homeAnimStep2 = 1), 225));
    this.homeTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.homeAnimStep3 = 1), 350));
  }

  private startConnectionEntrance(): void {
    this.clearEntranceTimers(this.connectionTimers);
    this.connectionAnimStep1 = 0;
    this.connectionAnimStep2 = 0;
    this.connectionAnimStep3 = 0;
    const curve = curves.springMotion(0.35, 0.75);
    this.connectionTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.connectionAnimStep1 = 1), 80));
    this.connectionTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.connectionAnimStep2 = 1), 205));
    this.connectionTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.connectionAnimStep3 = 1), 330));
  }

  private stopConnectionEntrance(): void {
    this.clearEntranceTimers(this.connectionTimers);
    this.connectionAnimStep1 = 0;
    this.connectionAnimStep2 = 0;
    this.connectionAnimStep3 = 0;
  }

  private openGallery(): void {
    if (this.pageStack.size() > 0) { return; }
    // The driving surface is hidden by a destination, so release any held command first.
    ++this.controlGeneration;
    this.pressedKey = '';
    this.stopCurrent();
    this.refreshCaptures();
    this.pageStack.pushPathByName('Gallery', null);
  }

  onPageHide(): void {
    this.disconnect();
  }

  private nextId(): string {
    this.serial += 1;
    return `${Date.now()}-${this.serial}`;
  }

  private clearTimers(): void {
    if (this.statusTimer >= 0) { clearInterval(this.statusTimer); this.statusTimer = -1; }
    if (this.renewTimer >= 0) { clearInterval(this.renewTimer); this.renewTimer = -1; }
    if (this.speedTimer >= 0) { clearTimeout(this.speedTimer); this.speedTimer = -1; }
  }

  private async keepPreviewAwake(enabled: boolean): Promise<void> {
    const current = ++this.screenGeneration;
    try {
      const mainWindow = await window.getLastWindow(
        this.getUIContext().getHostContext() as common.UIAbilityContext);
      if (current === this.screenGeneration) { await mainWindow.setWindowKeepScreenOn(enabled); }
    } catch (error) {
      // Window teardown must never delay disconnecting or stopping the car.
    }
  }

  private async connect(recovering: boolean = false, startup: boolean = false): Promise<void> {
    if (this.connecting || this.connected || this.disposed) { return; }
    if (recovering && (!this.connectionWanted || this.disposed)) { return; }
    this.connectionNotice = recovering ? '自动重连' : (startup ? '自动连接上次小车' : '连接小车');
    if (!this.api.setBaseUrl(this.endpoint)) {
      this.message = '车端地址无效';
      this.showConnectionToast(`${this.connectionNotice}失败：${this.message}`);
      return;
    }
    if (!recovering) { this.reconnectAttempt = 0; }
    this.connectionWanted = true;
    if (this.reconnectTimer >= 0) { clearTimeout(this.reconnectTimer); this.reconnectTimer = -1; }
    const current = ++this.connectionGeneration;
    this.connecting = true;
    this.message = recovering ? '连接恢复中…' : '正在连接…';
    const opening = this.openConnection(current);
    this.connectionOpening = opening;
    try { await opening; }
    finally { if (this.connectionOpening === opening) { this.connectionOpening = null; } }
  }

  private async openConnection(current: number): Promise<void> {
    try {
      await this.connectionCleanup;
      if (current !== this.connectionGeneration || this.disposed) { return; }
      // Pin LAN traffic before opening the long-lived stream. A successful
      // first request does not prevent later Wi-Fi/cellular network handover.
      await this.networkRoute.bind();
      if (current !== this.connectionGeneration || this.disposed) { return; }
      const status: PhoneStatus = await this.api.status();
      if (current !== this.connectionGeneration || this.disposed) { return; }
      if (status.mode !== 'phone') { throw new Error('车端未进入 phone 模式'); }
      this.bootId = status.bootId;
      this.previewReady = false;
      this.failures = 0;
      this.connected = true;
      this.keepPreviewAwake(true);
      this.connecting = false;
      this.applyStatus(status);
      this.message = '已连接，等待实时画面…';
      this.statusTimer = setInterval(() => this.pollStatus(), 250);
      this.cameraStream.start(this.api.streamUrl(30, 12),
        (frame: image.PixelMap) => {
          if (current !== this.connectionGeneration || !this.connected) { return; }
          this.cameraFrame = frame;
          if (!this.previewReady) {
            this.previewReady = true;
            this.reconnectAttempt = 0;
            this.message = '已连接 · 手机手动模式';
            this.rememberConnection();
            this.showConnectionToast(`${this.connectionNotice}成功`);
          }
        },
        (fps: number) => { if (current === this.connectionGeneration) { this.previewFps = fps; } },
        (reason: string) => {
          if (current === this.connectionGeneration) {
            this.connectionLost(`${reason}，已停止控制`);
          }
        }, true);
    } catch (error) {
      if (current !== this.connectionGeneration || this.disposed) { return; }
      // Opening is about to finish; do not make its cleanup wait on itself.
      this.connectionOpening = null;
      this.connectionLost((error as Error).message);
    }
  }

  private async pollStatus(): Promise<void> {
    if (!this.connected) { return; }
    const current = this.connectionGeneration;
    if (this.statusPollingGeneration === current) { return; }
    this.statusPollingGeneration = current;
    const serial = this.serial;
    try {
      const status = await this.api.status();
      if (!this.connected || current !== this.connectionGeneration) { return; }
      this.failures = 0;
      if (status.mode !== 'phone') { throw new Error('车端模式已改变'); }
      if (status.bootId !== this.bootId) { this.connectionLost('车端已重启，已停止控制'); return; }
      this.applyStatus(status, serial === this.serial);
      if (this.activeKey === 'z' && !status.moving) {
        ++this.controlGeneration;
        this.stopRenewTimer();
        this.activeKey = '';
        this.sessionId = '';
        this.commandId = '';
        this.message = '掉头已结束';
      }
    } catch (error) {
      if (!this.connected || current !== this.connectionGeneration) { return; }
      this.failures += 1;
      if (this.failures >= 2) { this.connectionLost('连接中断，车端将自动停车'); }
    } finally {
      if (this.statusPollingGeneration === current) { this.statusPollingGeneration = -1; }
    }
  }

  private applyStatus(status: PhoneStatus, syncSpeed: boolean = true): void {
    if (syncSpeed && !this.speedPending && this.speedTimer < 0 && !this.speedBusy) {
      this.speed = status.speed;
      this.speedDesired = status.speed;
      this.sliderSpeed = status.speed;
    }
    this.cameraStatus = status.camera.status;
    const radar = RadarPresentation.read(status.lidar);
    this.lidarPoints = radar.points;
    this.frontMm = radar.frontMm;
    this.sector90Mm = radar.rightMm;
    this.sector270Mm = radar.leftMm;
    this.lidarReady = radar.ready;
    const age = status.lidar.age_seconds;
    this.radarFreshness = !radar.ready ? '暂无新鲜扫描' :
      (typeof age === 'number' && Number.isFinite(age) && age >= 0 ?
        `最近扫描 ${age.toFixed(1)} 秒前` : '扫描已更新');
  }

  private stopRenewTimer(): void {
    if (this.renewTimer >= 0) { clearInterval(this.renewTimer); this.renewTimer = -1; }
    this.renewing = false;
  }

  private async stopCurrent(): Promise<void> {
    this.stopRenewTimer();
    const oldSession = this.sessionId;
    this.sessionId = '';
    this.commandId = '';
    this.activeKey = '';
    if (oldSession.length > 0) {
      try {
        await this.api.stop(oldSession);
      } catch (error) {
        this.message = '停车响应失败，等待车端超时停车';
      }
    }
  }

  private disconnect(): void {
    ++this.connectionGeneration;
    this.connectionWanted = false;
    this.previewReady = false;
    if (this.reconnectTimer >= 0) { clearTimeout(this.reconnectTimer); this.reconnectTimer = -1; }
    ++this.controlGeneration;
    this.pressedKey = '';
    this.clearTimers();
    this.connected = false;
    this.keepPreviewAwake(false);
    this.connecting = false;
    this.cameraStatus = 'unavailable';
    this.lidarReady = false;
    this.lidarPoints = 0;
    this.radarFreshness = '等待扫描';
    this.frontMm = null;
    this.sector90Mm = null;
    this.sector270Mm = null;
    this.cameraFrame = undefined;
    this.previewFps = 0;
    this.speedPending = false;
    this.cameraStream.stop();
    this.connectionCleanup = this.closeConnection(this.connectionOpening, this.connectionCleanup);
    if (!this.disposed) { this.message = '已断开'; }
  }

  private async closeConnection(opening: Promise<void> | null, previous: Promise<void>): Promise<void> {
    const stopping = this.stopCurrent();
    await previous;
    await stopping;
    if (opening !== null) { try { await opening; } catch (error) { /* Already cancelled. */ } }
    await this.networkRoute.release();
  }

  private connectionLost(text: string): void {
    // Only a connection that delivered live video gets one recovery attempt.
    // Failed startup/manual connections and failed recovery never retry in a loop.
    const recover = this.connectionWanted && !this.disposed && this.previewReady && this.reconnectAttempt < 1;
    const failedBeforeFrame = !this.previewReady;
    const notice = this.connectionNotice;
    this.disconnect();
    this.connectionWanted = recover;
    this.message = recover ? `${text}，正在自动重连一次…` :
      (failedBeforeFrame ? `${notice}失败：${text}，请手动连接` : text);
    this.showConnectionToast(this.message);
    if (recover) {
      const current = this.connectionGeneration;
      this.reconnectAttempt++;
      this.reconnectTimer = setTimeout(() => {
        this.reconnectTimer = -1;
        if (current === this.connectionGeneration && this.connectionWanted && !this.disposed) {
          this.connect(true);
        }
      }, 500);
    }
  }

  private async ensureSession(current: number): Promise<string> {
    // Share session creation between commands and speed changes. Serialize
    // across gesture generations so a late speed request cannot replace one.
    if (this.sessionOpening !== null) {
      if (this.sessionOpeningGeneration === current) { return await this.sessionOpening; }
      try { await this.sessionOpening; } catch (error) { /* Old gesture cancelled. */ }
    }
    if (!this.connected || current !== this.controlGeneration) { throw new Error('控制已取消'); }
    if (this.sessionId.length > 0) { return this.sessionId; }
    this.sessionOpeningGeneration = current;
    const opening = this.openSession(current);
    this.sessionOpening = opening;
    try { return await opening; }
    finally { if (this.sessionOpening === opening) { this.sessionOpening = null; } }
  }

  private async openSession(current: number): Promise<string> {
    const session: PhoneSession = await this.api.session();
    if (!this.connected || current !== this.controlGeneration) {
      await this.api.stop(session.sessionId);
      throw new Error('控制已取消');
    }
    this.sessionId = session.sessionId;
    return session.sessionId;
  }

  private async beginAction(key: string, held: boolean): Promise<void> {
    if (!this.connected || !this.previewReady) { this.showUnavailable(); return; }
    if (held && this.pressedKey.length > 0) { return; }
    const current = ++this.controlGeneration;
    this.pressedKey = held ? key : '';
    await this.stopCurrent();
    if (!this.connected || current !== this.controlGeneration) { return; }
    try {
      const session = await this.ensureSession(current);
      if (!this.connected || current !== this.controlGeneration) {
        await this.api.stop(session);
        return;
      }
      const id = this.nextId();
      const result: PhoneResult = await this.api.command(session, ++this.serial, id, key);
      if (!this.connected || current !== this.controlGeneration) {
        await this.api.stop(session);
        return;
      }
      this.speed = result.speed;
      this.activeKey = held || key === 'z' ? key : '';
      this.commandId = this.activeKey.length > 0 ? id : '';
      this.message = `已执行 ${key}`;
      if (this.activeKey.length > 0) {
        this.renewTimer = setInterval(() => this.renew(current), 150);
      }
      if (this.speedDesired !== this.speed) { this.flushSpeed(); }
    } catch (error) {
      if (current !== this.controlGeneration || !this.connected) { return; }
      this.message = `控制失败：${(error as Error).message}`;
      await this.stopCurrent();
    }
  }

  private async renew(current: number): Promise<void> {
    if (this.renewing || !this.connected || current !== this.controlGeneration || !this.commandId) { return; }
    this.renewing = true;
    try {
      await this.api.renew(this.sessionId, this.commandId);
    } catch (error) {
      if (current !== this.controlGeneration) { return; }
      if (this.activeKey === 'z') {
        try {
          const status = await this.api.status();
          if (this.connected && current === this.controlGeneration && status.mode === 'phone' && !status.moving) {
            ++this.controlGeneration;
            this.stopRenewTimer();
            this.sessionId = '';
            this.commandId = '';
            this.activeKey = '';
            this.applyStatus(status);
            this.message = '掉头已结束';
            return;
          }
        } catch (statusError) {
          // Fall through to the ordinary connection-loss stop.
        }
      }
      if (current === this.controlGeneration) { this.connectionLost('运动续期失败，已停止控制'); }
    } finally {
      this.renewing = false;
    }
  }

  private endAction(key: string): void {
    if (this.pressedKey !== key) { return; }
    this.pressedKey = '';
    ++this.controlGeneration;
    this.stopCurrent();
    this.message = '已停车';
  }

  private emergencyStop(): void {
    if (!this.connected) { this.showUnavailable(); return; }
    ++this.controlGeneration;
    this.pressedKey = '';
    this.stopCurrent();
    this.message = '已发送停车指令';
  }

  private async stepSpeed(key: string): Promise<void> {
    this.changeSpeed(Math.min(100, Math.max(0, this.sliderSpeed + (key === 'up' ? 20 : -20))));
  }

  private changeSpeed(value: number): void {
    if (!this.connected || !this.previewReady) { this.showUnavailable(); this.sliderSpeed = this.speed; return; }
    this.speedDesired = Math.round(value);
    this.speedPending = true;
    this.sliderSpeed = this.speedDesired;
    // Throttle while dragging; a debounce would wait until the finger stops.
    if (this.speedTimer < 0) {
      this.speedTimer = setTimeout(() => { this.speedTimer = -1; this.flushSpeed(); }, 120);
    }
  }

  private async flushSpeed(): Promise<void> {
    if (!this.connected || this.speedBusy) { return; }
    // Let the initial movement command establish its lease before adjusting it.
    if (this.pressedKey.length > 0 && this.commandId.length === 0) { return; }
    this.speedBusy = true;
    const current = this.controlGeneration;
    const target = this.speedDesired;
    let accepted = false;
    try {
      const session = await this.ensureSession(current);
      if (!this.connected || current !== this.controlGeneration) { return; }
      const result = await this.api.speed(session, ++this.serial, this.nextId(), target);
      if (!this.connected || current !== this.controlGeneration || session !== this.sessionId) { return; }
      this.speed = result.speed;
      accepted = true;
      this.speedPending = this.speedDesired !== target;
      if (this.speedDesired === target) { this.sliderSpeed = result.speed; }
      if (this.activeKey === 'z') {
        ++this.controlGeneration;
        this.stopRenewTimer();
        this.activeKey = '';
        this.commandId = '';
      }
    } catch (error) {
      if (current !== this.controlGeneration || !this.connected) { return; }
      this.message = `调速失败：${(error as Error).message}`;
      this.speedDesired = this.speed;
      this.speedPending = false;
      this.sliderSpeed = this.speed;
    }
    finally {
      this.speedBusy = false;
      if (this.connected && this.speedDesired !== this.speed &&
        (accepted || current !== this.controlGeneration)) { this.flushSpeed(); }
    }
  }

  private showUnavailable(): void {
    const now = Date.now();
    if (now - this.lastUnavailableAt < 1800) { return; }
    this.lastUnavailableAt = now;
    this.getUIContext().getPromptAction().showToast({ message: '小车未连接', duration: 2000 });
  }

  private refreshCaptures(): void {
    if (!this.captureStore) { return; }
    try { this.captures = this.captureStore.list(); }
    catch (error) { this.message = `读取图库失败：${(error as Error).message}`; }
  }

  private removeCapture(name: string): void {
    if (!this.captureStore) { return; }
    try {
      this.captureStore.remove(name);
      this.refreshCaptures();
      this.message = '截图已删除';
    } catch (error) { this.message = `删除失败：${(error as Error).message}`; }
  }

  private async downloadCapture(item: CaptureItem): Promise<void> {
    if (!this.captureStore) { return; }
    try {
      const saved = await this.captureStore.download(item);
      if (saved) { this.message = '已下载到系统相册'; }
    } catch (error) { this.message = `下载失败：${(error as Error).message}`; }
  }

  private async capture(): Promise<void> {
    if (!this.connected) { this.showUnavailable(); return; }
    if (this.captureBusy || !this.captureStore) { return; }
    this.captureBusy = true;
    try {
      const capture = await this.api.capture();
      this.message = `车端已保存 ${capture.captureId}，正在下载…`;
      const jpeg = await this.api.downloadCapture(capture.captureId);
      this.captureStore.save(jpeg);
      this.refreshCaptures();
      this.message = '截图已保存到车端和应用图库';
    } catch (error) { this.message = `截图保存失败：${(error as Error).message}`; }
    finally { this.captureBusy = false; }
  }

  @Builder
  private ConnectionSheet() {
    Scroll(this.connectionScroller) {
      Column({ space: 10 }) {
        Column({ space: 8 }) {
          Text('车端地址').fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).width('100%')
          TextInput({ text: this.endpoint, placeholder: 'http://192.168.8.204:8080' })
            .width('100%').height(48).backgroundColor($r('app.color.input_background')).borderRadius(13)
            .fontColor($r('app.color.text_primary')).enabled(!this.connectionWanted)
            .onChange((value: string) => this.endpoint = value)
          Text('手机与小车连接同一 Wi-Fi，填写车端 IP 和端口，例如 http://192.168.8.204:8080。')
            .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          Button(this.connectionWanted ? (this.connected ? '断开连接' : '取消连接') : '测试连接并连接')
            .width('100%').height(48).fontColor($r('app.color.white'))
            .backgroundColor(this.connectionWanted ? $r('app.color.danger') : $r('app.color.accent_green'))
            .borderRadius(14)
            .onClick(() => { Haptics.hard(); if (this.connectionWanted) { this.disconnect(); } else { this.connect(); } })
          Text(this.message).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').maxLines(2)
        }.width('100%').alignItems(HorizontalAlign.Start)
          .opacity(this.connectionAnimStep1).translate({ y: this.connectionAnimStep1 ? 0 : 12 })
        ConnectionIndicators({ connected: this.connected, cameraReady: this.cameraStatus === 'live',
          lidarReady: this.lidarReady })
          .opacity(this.connectionAnimStep2).translate({ y: this.connectionAnimStep2 ? 0 : 12 })
        Column({ space: 8 }) {
          Text('视频预览 · 16:9').fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_control')).width('100%')
          Stack({ alignContent: Alignment.Center }) {
            if (this.connected && this.cameraStatus === 'live' && this.cameraFrame !== undefined) {
              Image(this.cameraFrame).width('100%').height('100%').objectFit(ImageFit.Contain)
            } else {
              Text('暂无预览').fontSize(12).fontColor($r('app.color.camera_hint'))
            }
          }.width('100%').aspectRatio(16 / 9)
            .backgroundColor($r('app.color.camera_background')).borderRadius(14).clip(true)
          RadarOverlay({ scanning: this.lidarReady, points: this.lidarPoints,
            frontMm: this.frontMm, leftMm: this.sector270Mm, rightMm: this.sector90Mm })
          Text(`原始读数 · 左 ${RadarPresentation.rawText(this.sector270Mm)} / ` +
            `前 ${RadarPresentation.rawText(this.frontMm)} / 右 ${RadarPresentation.rawText(this.sector90Mm)}`)
            .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          Text(this.radarFreshness)
            .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
          .opacity(this.connectionAnimStep3).translate({ y: this.connectionAnimStep3 ? 0 : 12 })
      }
      .width('100%').alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start)
      .padding({ left: 16, right: 16, top: 14, bottom: 24 })
    }
    .width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.On)
    .onAppear(() => this.connectionScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false }))
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private PageMap(name: string) {
    if (name === 'Gallery') {
      CaptureGallery({ items: this.captures, onRemove: (itemName: string) => this.removeCapture(itemName),
        onDownload: (item: CaptureItem) => this.downloadCapture(item) })
    }
  }

  @Builder
  private SurfaceAction(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon).fontSize(20).fontColor([Color.White])
    }
    .width(40).height(40).backgroundColor('#66000000')
    .onClick(action)
  }

  @Builder
  private LandscapeHome() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.connected && this.cameraStatus === 'live' && this.cameraFrame !== undefined) {
          // The 16:9 feed keeps its aspect; the surrounding surface stays centred so
          // the bands above/below or left/right are symmetric instead of one-sided.
          Image(this.cameraFrame).width('100%').height('100%').objectFit(ImageFit.Contain)
        } else {
          Column({ space: 5 }) {
            Text('监看画面').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White)
            Text(this.connected ? '摄像头暂不可用' : '连接小车后显示实时画面')
              .fontSize(12).fontColor('#B8C8D2')
          }
        }
        RadarWarningHud({ scanning: this.lidarReady,
          frontMm: this.frontMm, leftMm: this.sector270Mm, rightMm: this.sector90Mm,
          pictureWidth: this.pictureWidth(), pictureHeight: this.pictureHeight(),
          ringWidth: Math.min(560, this.pictureWidth() * 0.62) })
        Row({ space: 8 }) {
          this.SurfaceAction($r('sys.symbol.connection'), () => { Haptics.hard(); this.showConnection = true; })
          this.SurfaceAction($r('sys.symbol.picture'), () => { Haptics.hard(); this.openGallery(); })
        }
        .position({ x: Math.max(12, this.pictureWidth() - 100), y: 10 })

        Row({ space: 5 }) {
          Text(`速度 ${this.sliderSpeed}`)
            .width(54).fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Slider({ value: this.sliderSpeed, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
            .layoutWeight(1).height(32).trackThickness(3).blockSize({ width: 12, height: 12 })
            .selectedColor('#CC62E6A7').blockColor('#E6FFFFFF').trackColor('#55FFFFFF')
            .onChange((value: number) => {
              if (Date.now() - this.lastLandscapeSliderVibration > 80) {
                Haptics.soft();
                this.lastLandscapeSliderVibration = Date.now();
              }
              this.changeSpeed(value);
            })
        }
        .width(220).height(32).padding({ left: 8, right: 8 })
        .backgroundColor('#55000000').borderRadius(10)
        .position({ x: 12, y: 8 })

        LandscapeControlPad({
          padDiameter: this.padSize(), drive: true, activeKey: this.activeKey,
          canStart: (key: string) => this.pressedKey.length === 0,
          onStart: (key: string) => { Haptics.soft(); this.beginAction(key, true); },
          onEnd: (key: string) => this.endAction(key),
          onStop: () => { Haptics.hard(); this.emergencyStop(); }
        })
          .position({ x: this.padInset(), y: this.pictureHeight() - this.padSize() - this.padInset() })

        LandscapeControlPad({
          padDiameter: this.padSize(), drive: false, activeKey: this.activeKey, captureBusy: this.captureBusy,
          canStart: (key: string) => this.pressedKey.length === 0,
          onStart: (key: string) => { Haptics.soft(); this.beginAction(key, true); },
          onEnd: (key: string) => this.endAction(key),
          onCapture: () => { Haptics.hard(); this.capture(); }
        })
          .position({ x: this.pictureWidth() - this.padSize() - this.padInset(),
            y: this.pictureHeight() - this.padSize() - this.padInset() })

        Text(this.message)
          .width(this.messageWidth()).textAlign(TextAlign.Center)
          .fontSize(10).fontColor(Color.White).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor('#88000000').borderRadius(8)
          .position({ x: (this.pictureWidth() - this.messageWidth()) / 2,
            y: this.pictureHeight() - 30 })
      }
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.ALL])
      .width(this.pictureWidth()).height(this.pictureHeight())
      .backgroundColor(Color.Black).clip(true)
    }
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.ALL])
    .width('100%').height('100%').backgroundColor(Color.Black)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width: number = Number(newValue.width);
      const height: number = Number(newValue.height);
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return; }
      this.landscapeContentWidth = width;
      this.landscapeContentHeight = height;
    })
  }

  build() {
    HdsNavigation(this.pageStack) {
      if (this.isLandscape) {
        this.LandscapeHome()
      } else {
      Column({ space: 4 }) {
        ConnectionIndicators({ connected: this.connected, cameraReady: this.cameraStatus === 'live',
          lidarReady: this.lidarReady, onOpen: () => this.showConnection = true })
          .opacity(this.homeAnimStep1).translate({ y: this.homeAnimStep1 ? 0 : 20 })
        Stack({ alignContent: Alignment.Center }) {
          if (this.connected && this.cameraStatus === 'live' && this.cameraFrame !== undefined) {
            Image(this.cameraFrame).width('100%').height('100%').objectFit(ImageFit.Contain)
          } else {
            Column({ space: 5 }) {
              Text('监看画面').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.camera_text'))
              Text(this.connected ? '摄像头暂不可用' : '连接小车后显示实时画面')
                .fontSize(12).fontColor($r('app.color.camera_hint'))
            }
          }
          Text(this.captureBusy ? '保存中…' : `${this.previewFps} FPS · 轻触截图`)
            .fontSize(10).fontColor($r('app.color.white')).padding(7).backgroundColor('#77000000')
            .borderRadius(10).position({ x: 10, y: 10 })
        }
        .width('100%').aspectRatio(16 / 9).backgroundColor($r('app.color.camera_background')).borderRadius(18)
        .scale({ x: this.previewPressed ? 0.985 : 1, y: this.previewPressed ? 0.985 : 1 })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pressShadow(this.previewPressed ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
          .pointLight({ sourceType: this.previewPressed ? hdsEffect.PointLightSourceType.BRIGHT :
            hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
            options: { color: '#FFFFFF', intensity: 7, height: 100 } }).buildEffect())
        .clip(true)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.previewPressed = true; }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.previewPressed = false; }
        })
        .onClick(() => { Haptics.hard(); this.capture(); })
        .opacity(this.homeAnimStep2).translate({ y: this.homeAnimStep2 ? 0 : 20 })
        RadarOverlay({ scanning: this.lidarReady, points: this.lidarPoints,
          frontMm: this.frontMm, leftMm: this.sector270Mm, rightMm: this.sector90Mm })
          .opacity(this.homeAnimStep2)
        DriveControls({ connected: this.connected, activeKey: this.activeKey, sliderSpeed: this.sliderSpeed,
          canStart: (key: string) => this.pressedKey.length === 0,
          onStart: (key: string) => this.beginAction(key, true),
          onEnd: (key: string) => this.endAction(key),
          onCapture: () => { Haptics.hard(); this.capture(); },
          onSpeedChange: (value: number) => this.changeSpeed(value),
          onUnavailable: () => this.showUnavailable() })
          .opacity(this.homeAnimStep3).translate({ y: this.homeAnimStep3 ? 0 : 20 })
        Button('停车 · 急停')
          .width('100%').height(40).fontSize(14).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.white')).backgroundColor($r('app.color.danger')).borderRadius(13)
          .onClick(() => { Haptics.hard(); this.emergencyStop(); })
          .opacity(this.homeAnimStep3)
        Text(this.message).fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          .textAlign(TextAlign.Center).padding({ top: 4, bottom: 4 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(this.homeAnimStep3).translate({ y: this.homeAnimStep3 ? 0 : 20 })
        Blank()
      }
      .width('100%').height('100%')
      .padding({ left: 14, right: 14, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.page_background'))
      }
    }
    .mode(NavigationMode.Stack)
    .navDestination(this.PageMap)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideTitleBar(this.isLandscape)
    .hideBackButton(true)
    .width(LayoutPolicy.matchParent).height(LayoutPolicy.matchParent)
    .background(this.isLandscape ? Color.Black : $r('app.color.page_background'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.updateViewport(Number(newValue.width), Number(newValue.height));
    })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.ALL])
    .titleBar({
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0), blurEffectiveEndOffset: LengthMetrics.vp(20) },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE },
        originalStyle: { backgroundStyle: { backgroundColor: $r('app.color.page_background') },
          contentStyle: { titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { backgroundColor: $r('app.color.input_background'), iconColor: $r('app.color.text_primary') } } },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: $r('app.color.page_background') },
          contentStyle: { titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { backgroundColor: $r('app.color.input_background'), iconColor: $r('app.color.text_primary') } } }
      },
      content: {
        title: { mainTitle: 'Astra Plus Drive' },
        menu: { value: [
          { content: { label: '连接', icon: $r('sys.symbol.connection'), isEnabled: true,
            action: () => { Haptics.hard(); this.showConnection = true; } } },
          { content: { label: '图库', icon: $r('sys.symbol.picture'), isEnabled: true,
            action: () => { Haptics.hard(); this.openGallery(); } } }

        ] }
      }
    })
    .bindSheet($$this.showConnection, this.ConnectionSheet(), {
      height: SheetSize.LARGE, showClose: true, title: { title: '连接小车' },
      backgroundColor: $r('app.color.page_background'),
      onAppear: () => this.startConnectionEntrance(),
      onWillDismiss: (action: DismissSheetAction) => { Haptics.hard(); action.dismiss(); },
      onDisappear: () => { this.stopConnectionEntrance(); this.showConnection = false; }
    })
  }
}
