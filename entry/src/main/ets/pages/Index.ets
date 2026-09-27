import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { HdsNavigation } from '@hms.hds.hdsBaseComponent';
import { hdsMaterial, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { CaptureStore, CaptureItem } from '../services/CaptureStore';
import { ConsoleLine } from '../models/ConsoleLine';
import { ConnectionIndicators } from '../components/ConnectionIndicators';
import { DriveControls } from '../components/DriveControls';
import { ConsoleDestination } from '../components/ConsoleDestination';
import { CaptureGallery } from '../components/CaptureGallery';
import { PhoneApi, PhoneStatus, PhoneSession, PhoneResult } from '../services/PhoneApi';
import { LocalNetworkRoute } from '../services/LocalNetworkRoute';

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
  private logSequence: number = 0;
  private sessionId: string = '';
  private commandId: string = '';
  private pressedKey: string = '';
  private renewing: boolean = false;
  private speedBusy: boolean = false;
  private speedDesired: number = 40;
  private failures: number = 0;
  private disposed: boolean = false;

  @State endpoint: string = 'http://192.168.149.1:8080';
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State @Watch('recordMessage') message: string = '连接小车 Wi-Fi 后输入车端地址';
  @State frameUrl: string = '';
  @State cameraStatus: string = 'waiting';
  @State lidarText: string = '等待雷达数据';
  @State speed: number = 40;
  @State sliderSpeed: number = 40;
  @State activeKey: string = '';
  @State captureBusy: boolean = false;
  @State lidarReady: boolean = false;
  @State logs: ConsoleLine[] = [];
  @State captures: CaptureItem[] = [];
  @State showConnection: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.captureStore = new CaptureStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.refreshCaptures();
    if (this.logs.length === 0) { this.addLog('INFO', '等待小车连接'); }
  }

  aboutToDisappear(): void {
    if (this.pageStack.size() > 0) {
      // Leaving the driving surface must release movement, while diagnostics keep polling.
      ++this.controlGeneration;
      this.pressedKey = '';
      this.stopCurrent();
      return;
    }
    this.disposed = true;
    this.disconnect();
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
    this.lidarText = JSON.stringify(status.lidar, null, 2);
    this.lidarReady = status.lidar.status === 'live';
    this.addLog('RECV', `速度 ${status.speed} · 雷达 ${status.lidar.status} · 视频 ${status.camera.status}`);
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
    if (!this.connected) { return; }
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
    ++this.controlGeneration;
    this.pressedKey = '';
    this.stopCurrent();
    this.message = '已发送停车指令';
  }

  private async stepSpeed(key: string): Promise<void> {
    if (!this.connected) { return; }
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

  private addLog(type: string, content: string): void {
    const now = new Date();
    const pad = (value: number): string => value.toString().padStart(2, '0');
    const time = `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
    const line: ConsoleLine = { id: `${Date.now()}-${++this.logSequence}`, time: time, type: type, content: content };
    this.logs = [...this.logs.slice(-199), line];
  }

  private recordMessage(): void {
    this.addLog(this.message.includes('失败') || this.message.includes('中断') ? 'ERR' : 'INFO', this.message);
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

  private async capture(): Promise<void> {
    if (!this.connected || this.captureBusy || !this.captureStore) { return; }
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
    Column({ space: 12 }) {
      ConnectionIndicators({ connected: this.connected, cameraReady: this.cameraStatus === 'live',
        lidarReady: this.lidarReady })
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text('视频').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#364B60')
          Stack({ alignContent: Alignment.Center }) {
            if (this.connected && this.cameraStatus === 'live' && this.frameUrl.length > 0) {
              Image(this.frameUrl).width('100%').height('100%').objectFit(ImageFit.Contain)
            } else {
              Text('暂无预览').fontSize(12).fontColor('#8BA396')
            }
          }.width('100%').layoutWeight(1).backgroundColor('#161B26').borderRadius(14)
        }.layoutWeight(1).height(220)
        Column({ space: 6 }) {
          Text('雷达 JSON').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#364B60')
          Scroll() {
            Text(this.lidarText).fontSize(10).fontFamily('monospace').fontColor('#F2F6FA')
              .width('100%').padding(8)
          }.width('100%').layoutWeight(1).backgroundColor('#161B26').borderRadius(14)
        }.layoutWeight(1).height(220)
      }.width('100%')
      TextInput({ text: this.endpoint, placeholder: 'http://192.168.149.1:8080' })
        .width('100%').height(48).backgroundColor('#E1EDFA').borderRadius(13)
        .enabled(!this.connected && !this.connecting)
        .onChange((value: string) => this.endpoint = value)
      Button(this.connected ? '断开连接' : (this.connecting ? '连接中…' : '测试链接并连接'))
        .width('100%').height(48).fontColor('#FFFFFF')
        .backgroundColor(this.connected ? '#FF3B30' : '#41BA41').borderRadius(14)
        .enabled(!this.connecting)
        .onClick(() => { if (this.connected) { this.disconnect(); } else { this.connect(); } })
      Text(this.message).fontSize(12).fontColor('#596A7F').maxLines(2)
      Blank()
    }
    .width('100%').height('100%').padding({ left: 16, right: 16, top: 14, bottom: 16 })
    .backgroundColor('#F2F6FA')
  }

  @Builder
  private PageMap(name: string) {
    if (name === 'Console') {
      ConsoleDestination({ lines: this.logs, onBack: () => this.pageStack.pop() })
    } else if (name === 'Gallery') {
      CaptureGallery({ items: this.captures, onBack: () => this.pageStack.pop(),
        onRemove: (itemName: string) => this.removeCapture(itemName) })
    }
  }

  build() {
    HdsNavigation(this.pageStack) {
      Column({ space: 7 }) {
        ConnectionIndicators({ connected: this.connected, cameraReady: this.cameraStatus === 'live',
          lidarReady: this.lidarReady, onOpen: () => this.showConnection = true })
        Stack({ alignContent: Alignment.Center }) {
          if (this.connected && this.cameraStatus === 'live' && this.frameUrl.length > 0) {
            Image(this.frameUrl).width('100%').height('100%').objectFit(ImageFit.Contain)
          } else {
            Column({ space: 5 }) {
              Text('监看画面').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#DBE8DC')
              Text(this.connected ? '摄像头暂不可用' : '连接小车后显示实时画面')
                .fontSize(12).fontColor('#A5B9A9')
            }
          }
          Text(this.captureBusy ? '保存中…' : '轻触截图')
            .fontSize(10).fontColor('#FFFFFF').padding(7).backgroundColor('#77000000')
            .borderRadius(10).position({ x: 10, y: 10 })
        }
        .width('100%').layoutWeight(1).backgroundColor('#161B26').borderRadius(18)
        .clip(true).onClick(() => this.capture())
        DriveControls({ connected: this.connected, activeKey: this.activeKey, sliderSpeed: this.sliderSpeed,
          onStart: (key: string) => this.beginAction(key, true),
          onEnd: (key: string) => this.endAction(key),
          onStop: () => this.emergencyStop(),
          onSpeedChange: (value: number) => this.changeSpeed(value) })
        Text(this.message).fontSize(11).fontColor('#596A7F').width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').height('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor('#F2F6FA')
    }
    .mode(NavigationMode.Stack)
    .navDestination(this.PageMap)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .width('100%').height(LayoutPolicy.matchParent).background('#F2F6FA')
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .titleBar({
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0), blurEffectiveEndOffset: LengthMetrics.vp(20) },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE },
        originalStyle: { backgroundStyle: { backgroundColor: '#F2F6FA' },
          contentStyle: { titleStyle: { mainTitleColor: '#202F42' },
            menuStyle: { backgroundColor: '#E1EDFA', iconColor: '#202F42' } } },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: '#F2F6FA' },
          contentStyle: { titleStyle: { mainTitleColor: '#202F42' },
            menuStyle: { backgroundColor: '#E1EDFA', iconColor: '#202F42' } } }
      },
      content: {
        title: { mainTitle: 'Astra Plus Drive' },
        menu: { value: [
          { content: { label: '控制台', icon: $r('sys.symbol.code_square'), isEnabled: true,
            action: () => this.pageStack.pushPathByName('Console', null) } },
          { content: { label: '图库', icon: $r('sys.symbol.picture'), isEnabled: true,
            action: () => { this.refreshCaptures(); this.pageStack.pushPathByName('Gallery', null); } } }
        ] }
      }
    })
    .bindSheet($$this.showConnection, this.ConnectionSheet(), {
      height: SheetSize.LARGE, showClose: true, title: { title: '连接小车' },
      backgroundColor: '#F2F6FA', onDisappear: () => this.showConnection = false
    })
  }
}
