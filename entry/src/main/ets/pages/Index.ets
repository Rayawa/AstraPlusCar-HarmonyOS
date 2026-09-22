import { AppHeader } from '../components/AppHeader';
import { CameraPanel } from '../components/CameraPanel';
import { ConnectionPanel } from '../components/ConnectionPanel';
import { DrivePanel } from '../components/DrivePanel';
import { ServoPanel } from '../components/ServoPanel';
import { StatusBar } from '../components/StatusBar';
import {
  AppColors,
  CarDefaults,
  LayoutConfig,
  NetworkConfig
} from '../constants/AppConstants';
import { ApiResult, CarAction } from '../models/CarModels';
import { CarApi } from '../services/CarApi';
import { LocalNetworkRoute } from '../services/LocalNetworkRoute';

@Entry
@Component
struct Index {
  private readonly api: CarApi = new CarApi();
  private readonly localNetworkRoute: LocalNetworkRoute = new LocalNetworkRoute();
  private frameTimer: number = -1;
  private driveTimer: number = -1;
  private pendingStopTimer: number = -1;
  private connectionAttempt: number = 0;
  private driveSession: number = 0;
  private driveRequestSession: number = -1;
  private moveFailureCount: number = 0;
  private servoRequest: number = 0;
  private commandSequence: number = 0;
  private disposed: boolean = false;

  @State endpoint: string = CarDefaults.ENDPOINT;
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State cameraEnabled: boolean = false;
  @State captureBusy: boolean = false;
  @State frameUrl: string = '';
  @State speed: number = CarDefaults.SPEED;
  @State verticalAngle: number = CarDefaults.VERTICAL_ANGLE;
  @State horizontalAngle: number = CarDefaults.HORIZONTAL_ANGLE;
  @State activeAction: CarAction = CarAction.NONE;
  @State statusText: string = '等待连接';
  @State isWide: boolean = false;
  @State captureCount: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    this.connected = false;
    this.connecting = false;
    this.api.setBaseUrl(this.endpoint);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.connectionAttempt += 1;
    this.servoRequest += 1;
    this.releaseControls();
    this.stopAndReleaseNetwork(this.connected, this.connectionAttempt);
    this.connected = false;
    this.connecting = false;
  }

  onPageHide(): void {
    if (!this.disposed && (this.connected || this.connecting)) {
      this.suspendConnection('应用已进入后台 · 已安全断开');
    }
  }

  private async connect(): Promise<void> {
    if (this.connecting) {
      return;
    }
    const normalized = CarApi.normalizeEndpoint(this.endpoint);
    if (normalized.length === 0 || !this.api.setBaseUrl(normalized)) {
      this.statusText = '车端地址格式无效';
      return;
    }
    this.endpoint = normalized;
    const attempt = ++this.connectionAttempt;
    this.connecting = true;
    this.statusText = '正在选择局域网…';

    const routeReady = await this.localNetworkRoute.bind();
    if (!this.isCurrentAttempt(attempt)) {
      await this.releaseNetworkIfNoActiveConnection();
      return;
    }
    if (!routeReady) {
      this.finishConnectFailure('未检测到 Wi-Fi 或有线局域网');
      return;
    }
    this.statusText = '正在连接小车…';

    const health = await this.api.health();
    if (!this.isCurrentAttempt(attempt)) {
      await this.releaseNetworkIfNoActiveConnection();
      return;
    }
    if (!health.ok) {
      this.finishConnectFailure(`连接失败 · ${health.message}`);
      return;
    }

    const servo = await this.api.servo(
      this.verticalAngle,
      this.horizontalAngle,
      this.nextCommandSequence()
    );
    if (!this.isCurrentAttempt(attempt)) {
      await this.releaseNetworkIfNoActiveConnection();
      return;
    }
    if (!servo.ok) {
      this.statusText = `已连接 · 云台初始化失败：${servo.message}`;
    } else if (health.cameraReady === false) {
      this.statusText = '已连接 · 控制就绪，摄像头未就绪';
    } else {
      this.statusText = '已连接 · 控制就绪';
    }

    this.connecting = false;
    this.connected = true;
    if (health.cameraReady !== false) {
      this.startCamera();
    }
  }

  private isCurrentAttempt(attempt: number): boolean {
    return !this.disposed && attempt === this.connectionAttempt;
  }

  private finishConnectFailure(message: string): void {
    this.connecting = false;
    this.connected = false;
    this.stopCamera();
    this.statusText = message;
    this.releaseNetworkWhenInactive(this.connectionAttempt);
  }

  private disconnect(): void {
    this.suspendConnection('已断开');
  }

  private suspendConnection(message: string): void {
    const shouldStop = this.connected;
    const attempt = ++this.connectionAttempt;
    this.servoRequest += 1;
    this.releaseControls();
    this.connected = false;
    this.connecting = false;
    this.statusText = message;
    this.stopAndReleaseNetwork(shouldStop, attempt);
  }

  private markConnectionLost(message: string): void {
    if (this.disposed) {
      return;
    }
    this.connectionAttempt += 1;
    this.servoRequest += 1;
    this.releaseControls();
    this.connected = false;
    this.connecting = false;
    this.statusText = message;
    this.releaseNetworkWhenInactive(this.connectionAttempt);
  }

  private async stopAndReleaseNetwork(shouldStop: boolean, attempt: number): Promise<void> {
    if (shouldStop) {
      await this.api.stop(this.nextCommandSequence());
    }
    if (attempt === this.connectionAttempt && !this.connected && !this.connecting) {
      await this.localNetworkRoute.release();
    }
  }

  private async releaseNetworkWhenInactive(attempt: number): Promise<void> {
    if (attempt === this.connectionAttempt && !this.connected && !this.connecting) {
      await this.localNetworkRoute.release();
    }
  }

  private async releaseNetworkIfNoActiveConnection(): Promise<void> {
    if (!this.connected && !this.connecting) {
      await this.localNetworkRoute.release();
    }
  }

  private releaseControls(): void {
    this.stopDriveTimer();
    this.cancelPendingStop();
    this.driveSession += 1;
    this.driveRequestSession = -1;
    this.moveFailureCount = 0;
    this.activeAction = CarAction.NONE;
    this.captureBusy = false;
    this.stopCamera();
  }

  private startCamera(): void {
    if (!this.connected || this.cameraEnabled || this.disposed) {
      return;
    }
    this.cameraEnabled = true;
    this.refreshFrame();
    this.frameTimer = setInterval(() => this.refreshFrame(), NetworkConfig.FRAME_REFRESH_MS);
  }

  private stopCamera(): void {
    this.cameraEnabled = false;
    if (this.frameTimer >= 0) {
      clearInterval(this.frameTimer);
      this.frameTimer = -1;
    }
  }

  private refreshFrame(): void {
    if (this.cameraEnabled && this.connected && !this.disposed) {
      this.frameUrl = this.api.frameUrl(Date.now());
    }
  }

  private beginMove(action: CarAction): void {
    if (!this.connected || action === CarAction.NONE) {
      this.statusText = '请先连接小车';
      return;
    }
    this.cancelPendingStop();
    this.stopDriveTimer();
    const session = ++this.driveSession;
    this.moveFailureCount = 0;
    this.activeAction = action;
    this.sendMove(action, session);
    this.driveTimer = setInterval(() => {
      this.sendMove(action, session);
    }, NetworkConfig.DRIVE_KEEP_ALIVE_MS);
  }

  private async sendMove(action: CarAction, session: number): Promise<void> {
    if (this.driveRequestSession === session) {
      return;
    }
    this.driveRequestSession = session;
    const result = await this.api.move(action, this.speed, this.nextCommandSequence());
    if (this.driveRequestSession === session) {
      this.driveRequestSession = -1;
    }
    if (!this.isActiveDrive(action, session)) {
      return;
    }
    if (result.ok) {
      this.moveFailureCount = 0;
      return;
    }
    this.moveFailureCount += 1;
    if (this.moveFailureCount >= NetworkConfig.MOVE_FAILURE_LIMIT) {
      this.markConnectionLost('连续移动指令失败 · 已进入安全离线状态');
    }
  }

  private isActiveDrive(action: CarAction, session: number): boolean {
    return !this.disposed && this.connected && session === this.driveSession && this.activeAction === action;
  }

  private endMove(action: CarAction): void {
    if (action !== this.activeAction) {
      return;
    }
    this.stopDriveTimer();
    this.driveSession += 1;
    this.activeAction = CarAction.NONE;
    this.cancelPendingStop();
    this.pendingStopTimer = setTimeout(() => {
      this.pendingStopTimer = -1;
      this.sendStop('已停车', this.driveSession);
    }, NetworkConfig.DIRECTION_SWITCH_GRACE_MS);
  }

  private stopDriveTimer(): void {
    if (this.driveTimer >= 0) {
      clearInterval(this.driveTimer);
      this.driveTimer = -1;
    }
  }

  private cancelPendingStop(): void {
    if (this.pendingStopTimer >= 0) {
      clearTimeout(this.pendingStopTimer);
      this.pendingStopTimer = -1;
    }
  }

  private emergencyStop(): void {
    this.stopDriveTimer();
    this.cancelPendingStop();
    this.driveSession += 1;
    this.activeAction = CarAction.NONE;
    if (!this.connected) {
      this.statusText = '当前未连接';
      return;
    }
    this.statusText = '正在发送紧急停车指令…';
    this.sendStop('紧急停车指令已发送', this.driveSession);
  }

  private async sendStop(successMessage: string, session: number): Promise<void> {
    const result = await this.api.stop(this.nextCommandSequence());
    if (this.disposed || !this.connected || session !== this.driveSession) {
      return;
    }
    if (result.ok) {
      this.statusText = successMessage;
    } else {
      this.markConnectionLost('停车响应失败 · 车端看门狗将自动停车');
    }
  }

  private nextCommandSequence(): number {
    this.commandSequence = Math.max(this.commandSequence + 1, Date.now());
    return this.commandSequence;
  }

  private onAnglesChange(vertical: number, horizontal: number, commit: boolean): void {
    this.verticalAngle = vertical;
    this.horizontalAngle = horizontal;
    if (commit) {
      this.updateServo(vertical, horizontal);
    }
  }

  private resetServo(): void {
    this.verticalAngle = CarDefaults.VERTICAL_ANGLE;
    this.horizontalAngle = CarDefaults.HORIZONTAL_ANGLE;
    this.updateServo(this.verticalAngle, this.horizontalAngle);
  }

  private async updateServo(vertical: number, horizontal: number): Promise<void> {
    if (!this.connected) {
      return;
    }
    const request = ++this.servoRequest;
    const result = await this.api.servo(vertical, horizontal, this.nextCommandSequence());
    if (this.disposed || request !== this.servoRequest || !this.connected) {
      return;
    }
    if (result.ok) {
      this.statusText = `云台已调整 · ${vertical}° / ${horizontal}°`;
    } else {
      this.statusText = `舵机指令失败 · ${result.message}`;
    }
  }

  private async capture(): Promise<void> {
    if (!this.connected) {
      this.statusText = '请先连接小车';
      return;
    }
    if (this.captureBusy) {
      return;
    }
    this.captureBusy = true;
    const attempt = this.connectionAttempt;
    const result: ApiResult = await this.api.capture();
    if (this.disposed || attempt !== this.connectionAttempt || !this.connected) {
      return;
    }
    this.captureBusy = false;
    if (result.ok) {
      this.captureCount += 1;
      this.statusText = `截图已保存至车端 capture 目录 · ${this.captureCount} 张`;
      this.refreshFrame();
    } else if (result.statusCode === 503) {
      this.statusText = '截图失败 · 摄像头尚未就绪';
    } else {
      this.statusText = '截图失败 · 请检查摄像头与连接';
    }
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          AppHeader({ connected: this.connected, isWide: this.isWide })
          ConnectionPanel({
            endpoint: this.endpoint,
            connected: this.connected,
            connecting: this.connecting,
            onEndpointChange: (value: string) => this.endpoint = value,
            onToggleConnection: () => this.connected ? this.disconnect() : this.connect()
          })
          if (this.isWide) {
            Row({ space: 16 }) {
              Column({ space: 16 }) {
                this.CameraSection()
                this.ServoSection()
              }
              .layoutWeight(3)
              DrivePanel({
                connected: this.connected,
                speed: this.speed,
                activeAction: this.activeAction,
                onMoveStart: (action: CarAction) => this.beginMove(action),
                onMoveEnd: (action: CarAction) => this.endMove(action),
                onEmergencyStop: () => this.emergencyStop(),
                onSpeedChange: (value: number) => this.speed = value
              })
              .layoutWeight(2)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .margin({ top: 16 })
          } else {
            Column({ space: 16 }) {
              this.CameraSection()
              DrivePanel({
                connected: this.connected,
                speed: this.speed,
                activeAction: this.activeAction,
                onMoveStart: (action: CarAction) => this.beginMove(action),
                onMoveEnd: (action: CarAction) => this.endMove(action),
                onEmergencyStop: () => this.emergencyStop(),
                onSpeedChange: (value: number) => this.speed = value
              })
              this.ServoSection()
            }
            .width('100%')
            .margin({ top: 16 })
          }
          StatusBar({ connected: this.connected, statusText: this.statusText })
        }
        .width('100%')
        .padding({ left: this.isWide ? 28 : 16, right: this.isWide ? 28 : 16, top: 24, bottom: 28 })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      this.isWide = !Number.isNaN(width) && width >= LayoutConfig.WIDE_BREAKPOINT;
    })
  }

  @Builder
  private CameraSection() {
    CameraPanel({
      connected: this.connected,
      cameraEnabled: this.cameraEnabled,
      frameUrl: this.frameUrl,
      captureBusy: this.captureBusy,
      onToggleCamera: () => this.cameraEnabled ? this.stopCamera() : this.startCamera(),
      onCapture: () => this.capture(),
      onResetServo: () => this.resetServo()
    })
  }

  @Builder
  private ServoSection() {
    ServoPanel({
      connected: this.connected,
      verticalAngle: this.verticalAngle,
      horizontalAngle: this.horizontalAngle,
      onAnglesChange: (vertical: number, horizontal: number, commit: boolean) => {
        this.onAnglesChange(vertical, horizontal, commit);
      }
    })
  }
}
