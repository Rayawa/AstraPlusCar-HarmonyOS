import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { PhoneApi, PhoneStatus, PhoneSession, PhoneResult } from '../services/PhoneApi';
import { LocalNetworkRoute } from '../services/LocalNetworkRoute';

@Entry
@Component
struct Index {
  private readonly api: PhoneApi = new PhoneApi();
  private readonly networkRoute: LocalNetworkRoute = new LocalNetworkRoute();
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
  private disposed: boolean = false;

  @State endpoint: string = 'http://192.168.149.1:8080';
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State message: string = '连接小车 Wi-Fi 后输入车端地址';
  @State frameUrl: string = '';
  @State cameraStatus: string = 'waiting';
  @State lidarText: string = '等待雷达数据';
  @State speed: number = 40;
  @State sliderSpeed: number = 40;
  @State activeKey: string = '';
  @State captureBusy: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
  }

  aboutToDisappear(): void {
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
      if (this.activeKey === 'z') { this.stopRenewTimer(); this.activeKey = ''; }
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
      if (this.activeKey === 'z') { this.stopRenewTimer(); this.activeKey = ''; }
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

  private async capture(): Promise<void> {
    if (!this.connected || this.captureBusy) { return; }
    this.captureBusy = true;
    try {
      const capture = await this.api.capture();
      this.message = `车端已保存 ${capture.captureId}，正在保存到手机…`;
      const jpeg = await this.api.downloadCapture(capture.captureId);
      const helper = photoAccessHelper.getPhotoAccessHelper(getContext(this));
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg',
        { title: `AstraPlusCar-${Date.now()}` });
      const file = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY);
      try {
        let written = 0;
        while (written < jpeg.byteLength) {
          const count = fileIo.writeSync(file.fd, jpeg.slice(written));
          if (count <= 0) { throw new Error('手机相册写入失败'); }
          written += count;
        }
      }
      finally { fileIo.closeSync(file); }
      this.message = '截图已保存到车端和手机相册';
    } catch (error) { this.message = `截图或手机保存失败：${(error as Error).message}`; }
    finally { this.captureBusy = false; }
  }

  @Builder
  private HoldKey(label: string, key: string) {
    Button(label)
      .width(74).height(52)
      .backgroundColor(this.activeKey === key ? '#1F9B72' : '#293B4A')
      .fontSize(17)
      .enabled(this.connected)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.beginAction(key, true); }
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.endAction(key); }
      })
  }

  build() {
    Scroll() {
      Column({ space: 13 }) {
        Text('AstraPlusCar · 手机手动模式').fontSize(21).fontWeight(FontWeight.Bold)
        if (!this.connected) {
          TextInput({ text: this.endpoint, placeholder: 'http://192.168.149.1:8080' })
            .onChange((value: string) => this.endpoint = value)
          Button(this.connecting ? '连接中…' : '连接小车')
            .enabled(!this.connecting).onClick(() => this.connect())
        } else {
          Button('断开连接').onClick(() => this.disconnect())
          if (this.cameraStatus === 'live') {
            Image(this.frameUrl).width('100%').height(210).objectFit(ImageFit.Contain)
              .backgroundColor('#101820')
          } else {
            Text(`相机状态：${this.cameraStatus}`).height(210)
          }
          Row({ space: 12 }) {
            SaveButton({ text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Capsule })
              .enabled(!this.captureBusy)
              .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                if (result === SaveButtonOnClickResult.SUCCESS) { this.capture(); }
                else { this.message = '未获得保存到相册的授权'; }
              })
            Text(this.captureBusy ? '保存中…' : '截图保存到车端与手机')
          }
          Text('雷达 JSON').fontSize(16).fontWeight(FontWeight.Bold)
          Text(this.lidarText).fontSize(13).width('100%')
            .padding(10).backgroundColor('#20313E')
          Text(`速度 ${this.speed}`).fontSize(17)
          Slider({ value: this.sliderSpeed, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
            .onChange((value: number) => this.changeSpeed(value))
          Row({ space: 8 }) {
            Button('↑ +20').onClick(() => this.stepSpeed('up'))
            Button('↓ -20').onClick(() => this.stepSpeed('down'))
            Button('Z 掉头').onClick(() => this.beginAction('z', false))
          }
          Row({ space: 8 }) { this.HoldKey('Q 左旋', 'q'); this.HoldKey('W 前进', 'w'); this.HoldKey('E 右旋', 'e'); }
          Row({ space: 8 }) { this.HoldKey('A 左转', 'a'); this.HoldKey('S 后退', 's'); this.HoldKey('D 右转', 'd'); }
          Row({ space: 8 }) { this.HoldKey('← 左移', 'left'); this.HoldKey('→ 右移', 'right'); }
          Button('STOP · 停车').width('100%').height(56)
            .backgroundColor('#B82F32')
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) { this.emergencyStop(); }
            })
        }
        Text(this.message).fontSize(13).width('100%')
      }
      .width('100%').padding(16).alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%').backgroundColor('#101D28')
  }
}
