import { common } from '@kit.AbilityKit';
import { curves, LengthMetrics } from '@kit.ArkUI';
import { HdsNavigation } from '@hms.hds.hdsBaseComponent';
import { hdsEffect, hdsMaterial, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { CaptureStore, CaptureItem } from '../services/CaptureStore';
import { ConnectionIndicators } from '../components/ConnectionIndicators';
import { DriveControls } from '../components/DriveControls';
import { LandscapeControlPad } from '../components/LandscapeControlPad';
import { RadarOverlay } from '../components/RadarOverlay';
import { CaptureGallery } from '../components/CaptureGallery';
import { PhoneApi, PhoneStatus, PhoneSession, PhoneResult } from '../services/PhoneApi';
import { LocalNetworkRoute } from '../services/LocalNetworkRoute';
import { Haptics } from '../services/Haptics';

@Entry
@Component
struct Index {
  private readonly api: PhoneApi = new PhoneApi();
  private readonly networkRoute: LocalNetworkRoute = new LocalNetworkRoute();
  private readonly pageStack: NavPathStack = new NavPathStack();
  private captureStore: CaptureStore | null = null;
  private statusTimer: number = -1;
  private frameTimer: number = -1;
  private renewTimer: number = -1;
  private speedTimer: number = -1;
  private controlGeneration: number = 0;
  private serial: number = 0;
  private sessionId: string = '';
  private commandId: string = '';
  private pressedKey: string = '';
  private renewing: boolean = false;
  private speedBusy: boolean = false;
  private speedDesired: number = 40;
  private failures: number = 0;
  private lastUnavailableAt: number = 0;
  private lastLandscapeSliderVibration: number = 0;
  private disposed: boolean = false;
  private homeEntranceStarted: boolean = false;
  private homeTimers: number[] = [];
  private connectionTimers: number[] = [];

  @State endpoint: string = 'http://192.168.8.204:8080';
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State message: string = '连接小车 Wi-Fi 后输入车端地址';
  @State frameUrl: string = '';
  @State cameraStatus: string = 'waiting';
  @State lidarPoints: number = 0;
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

  private pictureWidth(): number {
    return Math.min(this.viewportWidth, this.viewportHeight * 16 / 9);
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
    return Math.min(280, this.pictureWidth() - 2 * (this.padSize() + this.padInset()) - 24);
  }

  aboutToAppear(): void {
    this.disposed = false;
    this.captureStore = new CaptureStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.refreshCaptures();
    this.startHomeEntrance();
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
    if (this.frameTimer >= 0) { clearInterval(this.frameTimer); this.frameTimer = -1; }
    if (this.renewTimer >= 0) { clearInterval(this.renewTimer); this.renewTimer = -1; }
    if (this.speedTimer >= 0) { clearTimeout(this.speedTimer); this.speedTimer = -1; }
  }

  private async connect(): Promise<void> {
    if (this.connecting || this.connected) { return; }
    if (!this.api.setBaseUrl(this.endpoint)) {
      this.message = '车端地址无效';
      return;
    }
    this.connecting = true;
    this.message = '正在连接…';
    try {
      let status: PhoneStatus;
      try {
        status = await this.api.status();
      } catch (directError) {
        await this.networkRoute.bind();
        status = await this.api.status();
      }
      if (this.disposed || !this.connecting) { return; }
      if (status.mode !== 'phone') { throw new Error('车端未进入 phone 模式'); }
      this.connected = true;
      this.connecting = false;
      this.applyStatus(status);
      this.message = '已连接 · 手机手动模式';
      this.statusTimer = setInterval(() => this.pollStatus(), 1000);
      this.frameTimer = setInterval(() => {
        if (this.connected && this.cameraStatus === 'live') {
          this.frameUrl = this.api.frameUrl(Date.now());
        }
      }, 180);
    } catch (error) {
      this.connecting = false;
      this.message = `连接失败：${(error as Error).message}`;
      await this.networkRoute.release();
    }
  }

  private async pollStatus(): Promise<void> {
    if (!this.connected) { return; }
    try {
      const status = await this.api.status();
      if (!this.connected) { return; }
      this.failures = 0;
      if (status.mode !== 'phone') { throw new Error('车端模式已改变'); }
      this.applyStatus(status);
      if (this.activeKey === 'z' && !status.moving) {
        ++this.controlGeneration;
        this.stopRenewTimer();
        this.activeKey = '';
        this.sessionId = '';
        this.commandId = '';
        this.message = '掉头已结束';
      }
    } catch (error) {
      this.failures += 1;
      if (this.failures >= 2) { this.connectionLost('连接中断，车端将自动停车'); }
    }
  }

  private applyStatus(status: PhoneStatus): void {
    this.speed = status.speed;
    if (this.speedTimer < 0 && !this.speedBusy) {
      this.speedDesired = status.speed;
      this.sliderSpeed = status.speed;
    }
    this.cameraStatus = status.camera.status;
    this.lidarPoints = status.lidar.points;
    this.frontMm = status.lidar.front_nearest_mm;
    this.sector90Mm = status.lidar.sector_90_mm ?? null;
    this.sector270Mm = status.lidar.sector_270_mm ?? null;
    this.lidarReady = status.lidar.status === 'scanning' && status.lidar.health === 'OK';
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
    ++this.controlGeneration;
    this.pressedKey = '';
    this.clearTimers();
    this.connected = false;
    this.connecting = false;
    this.cameraStatus = 'unavailable';
    this.lidarReady = false;
    this.lidarPoints = 0;
    this.frontMm = null;
    this.sector90Mm = null;
    this.sector270Mm = null;
    this.frameUrl = '';
    this.stopCurrent();
    this.networkRoute.release();
    if (!this.disposed) { this.message = '已断开'; }
  }

  private connectionLost(text: string): void {
    this.disconnect();
    this.message = text;
  }

  private async beginAction(key: string, held: boolean): Promise<void> {
    if (!this.connected) { this.showUnavailable(); return; }
    if (held && this.pressedKey.length > 0) { return; }
    const current = ++this.controlGeneration;
    this.pressedKey = held ? key : '';
    await this.stopCurrent();
    if (!this.connected || current !== this.controlGeneration) { return; }
    try {
      const session: PhoneSession = await this.api.session();
      if (!this.connected || current !== this.controlGeneration) {
        await this.api.stop(session.sessionId);
        return;
      }
      this.sessionId = session.sessionId;
      const id = this.nextId();
      const result: PhoneResult = await this.api.command(session.sessionId, 1, id, key);
      if (!this.connected || current !== this.controlGeneration) {
        await this.api.stop(session.sessionId);
        return;
      }
      this.speed = result.speed;
      this.activeKey = held || key === 'z' ? key : '';
      this.commandId = this.activeKey.length > 0 ? id : '';
      this.message = `已执行 ${key}`;
      if (this.activeKey.length > 0) {
        this.renewTimer = setInterval(() => this.renew(current), 150);
      }
    } catch (error) {
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
    if (!this.connected) { this.showUnavailable(); return; }
    try {
      let session = this.sessionId;
      if (!session) { session = (await this.api.session()).sessionId; this.sessionId = session; }
      const result = await this.api.command(session, ++this.serial, this.nextId(), key);
      this.speed = result.speed;
      this.speedDesired = result.speed;
      this.sliderSpeed = result.speed;
      if (this.activeKey === 'z') {
        ++this.controlGeneration;
        this.stopRenewTimer();
        this.activeKey = '';
        this.commandId = '';
      }
    } catch (error) { this.message = `调速失败：${(error as Error).message}`; }
  }

  private changeSpeed(value: number): void {
    if (!this.connected) { this.showUnavailable(); this.sliderSpeed = this.speed; return; }
    if (this.pressedKey.length > 0) { this.sliderSpeed = this.speed; return; }
    this.speedDesired = Math.round(value);
    this.sliderSpeed = this.speedDesired;
    if (this.speedTimer >= 0) { clearTimeout(this.speedTimer); }
    this.speedTimer = setTimeout(() => { this.speedTimer = -1; this.flushSpeed(); }, 120);
  }

  private async flushSpeed(): Promise<void> {
    if (!this.connected || this.speedBusy) { return; }
    this.speedBusy = true;
    const target = this.speedDesired;
    let accepted = false;
    try {
      let session = this.sessionId;
      if (!session) { session = (await this.api.session()).sessionId; this.sessionId = session; }
      const result = await this.api.speed(session, ++this.serial, this.nextId(), target);
      this.speed = result.speed;
      accepted = true;
      if (this.speedDesired === target) { this.sliderSpeed = result.speed; }
      if (this.activeKey === 'z') {
        ++this.controlGeneration;
        this.stopRenewTimer();
        this.activeKey = '';
        this.commandId = '';
      }
    } catch (error) {
      this.message = `调速失败：${(error as Error).message}`;
      this.speedDesired = this.speed;
      this.sliderSpeed = this.speed;
    }
    finally {
      this.speedBusy = false;
      if (this.connected && accepted && this.speedDesired !== target) { this.flushSpeed(); }
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
    Scroll() {
      Column({ space: 10 }) {
      ConnectionIndicators({ connected: this.connected, cameraReady: this.cameraStatus === 'live',
        lidarReady: this.lidarReady })
        .opacity(this.connectionAnimStep1).translate({ y: this.connectionAnimStep1 ? 0 : 20 })
      Column({ space: 8 }) {
        Text('视频预览 · 16:9').fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_control')).width('100%')
        Stack({ alignContent: Alignment.Center }) {
          if (this.connected && this.cameraStatus === 'live' && this.frameUrl.length > 0) {
            Image(this.frameUrl).width('100%').height('100%').objectFit(ImageFit.Contain)
          } else {
            Text('暂无预览').fontSize(12).fontColor($r('app.color.camera_hint'))
          }
        }.width('100%').aspectRatio(16 / 9)
          .backgroundColor($r('app.color.camera_background')).borderRadius(14).clip(true)
        RadarOverlay({ scanning: this.lidarReady, points: this.lidarPoints,
          frontMm: this.frontMm, leftMm: this.sector270Mm, rightMm: this.sector90Mm })
      }.width('100%')
        .opacity(this.connectionAnimStep2).translate({ y: this.connectionAnimStep2 ? 0 : 20 })
      Column({ space: 10 }) {
        Text('雷达每秒更新；左 270°、前 0°、右 90°，显示各 ±30° 扇区最近距离，数值单位为毫米。')
          .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
        TextInput({ text: this.endpoint, placeholder: 'http://192.168.8.204:8080' })
          .width('100%').height(48).backgroundColor($r('app.color.input_background')).borderRadius(13)
          .fontColor($r('app.color.text_primary')).enabled(!this.connected && !this.connecting)
          .onChange((value: string) => this.endpoint = value)
        Button(this.connected ? '断开连接' : (this.connecting ? '连接中…' : '测试链接并连接'))
          .width('100%').height(48).fontColor($r('app.color.white'))
          .backgroundColor(this.connected ? $r('app.color.danger') : $r('app.color.accent_green')).borderRadius(14)
          .enabled(!this.connecting)
          .onClick(() => { Haptics.hard(); if (this.connected) { this.disconnect(); } else { this.connect(); } })
        Text(this.message).fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(2)
      }.width('100%')
        .opacity(this.connectionAnimStep3).translate({ y: this.connectionAnimStep3 ? 0 : 20 })
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 24 })
    }
    .width('100%').height('100%').scrollBar(BarState.On)
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
  private LandscapeHome() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.connected && this.cameraStatus === 'live' && this.frameUrl.length > 0) {
          Image(this.frameUrl).width('100%').height('100%').objectFit(ImageFit.Contain)
        } else {
          Column({ space: 5 }) {
            Text('监看画面').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White)
            Text(this.connected ? '摄像头暂不可用' : '连接小车后显示实时画面')
              .fontSize(12).fontColor('#B8C8D2')
          }
        }
        RadarOverlay({ scanning: this.lidarReady, points: this.lidarPoints,
          frontMm: this.frontMm, leftMm: this.sector270Mm, rightMm: this.sector90Mm })
          .width(Math.min(340, this.pictureWidth() - 24))
          .position({ x: (this.pictureWidth() - Math.min(340, this.pictureWidth() - 24)) / 2, y: 63 })
        Row({ space: 7 }) {
          Column().width(8).height(8).borderRadius(4)
            .backgroundColor(this.connected ? '#62E6A7' : '#FF6B6B')
          Column({ space: 2 }) {
            Text(this.connected ? '车辆在线' : '车辆离线')
              .fontSize(12).fontWeight(FontWeight.Bold).fontColor(Color.White)
            Text(this.cameraStatus === 'live' ? '摄像头在线' : '摄像头离线')
              .fontSize(10).fontColor('#D9FFFFFF')
          }.alignItems(HorizontalAlign.Start)
        }
        .height(42).padding({ left: 10, right: 10 })
        .backgroundColor('#99000000').borderRadius(12)
        .position({ x: 12, y: 12 })
        .onClick(() => { Haptics.hard(); this.showConnection = true; })

        Row({ space: 5 }) {
          Text(`速度 ${this.sliderSpeed}`)
            .width(54).fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Slider({ value: this.sliderSpeed, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
            .layoutWeight(1).selectedColor('#62E6A7').blockColor(Color.White)
            .trackColor('#77FFFFFF')
            .onChange((value: number) => {
              if (Date.now() - this.lastLandscapeSliderVibration > 80) {
                Haptics.soft();
                this.lastLandscapeSliderVibration = Date.now();
              }
              this.changeSpeed(value);
            })
        }
        .width(240).height(42).padding({ left: 9, right: 9 })
        .backgroundColor('#99000000').borderRadius(12)
        .position({ x: (this.pictureWidth() - 240) / 2, y: 12 })

        Button('相册')
          .width(68).height(42).fontSize(12).fontWeight(FontWeight.Bold)
          .fontColor(Color.White).backgroundColor('#99000000').borderRadius(12)
          .position({ x: this.pictureWidth() - 80, y: 12 })
          .onClick(() => { Haptics.hard(); this.openGallery(); })

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
      .width(this.pictureWidth()).height(this.pictureHeight())
      .backgroundColor(Color.Black).clip(true)
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
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
          if (this.connected && this.cameraStatus === 'live' && this.frameUrl.length > 0) {
            Image(this.frameUrl).width('100%').height('100%').objectFit(ImageFit.Contain)
          } else {
            Column({ space: 5 }) {
              Text('监看画面').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.camera_text'))
              Text(this.connected ? '摄像头暂不可用' : '连接小车后显示实时画面')
                .fontSize(12).fontColor($r('app.color.camera_hint'))
            }
          }
          Text(this.captureBusy ? '保存中…' : '轻触截图')
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
    .width('100%').height(LayoutPolicy.matchParent)
    .background(this.isLandscape ? Color.Black : $r('app.color.page_background'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.updateViewport(Number(newValue.width), Number(newValue.height));
    })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
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
