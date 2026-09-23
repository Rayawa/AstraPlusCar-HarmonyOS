import { ConnectionScreen } from '../components/ConnectionScreen';
import { GalleryScreen } from '../components/GalleryScreen';
import { GameControlScreen } from '../components/GameControlScreen';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CarDefaults, CarLimits, LogConfig, NetworkConfig } from '../constants/AppConstants';
import { ApiResult, CarAction, GalleryItem } from '../models/CarModels';
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
  private galleryRequest: number = 0;
  private driveSession: number = 0;
  private driveRequestSession: number = -1;
  private moveFailureCount: number = 0;
  private servoRequest: number = 0;
  private commandSequence: number = 0;
  private disposed: boolean = false;

  @State currentScreen: string = 'connection';
  @State endpoint: string = CarDefaults.ENDPOINT;
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State cameraReady: boolean = false;
  @State cameraEnabled: boolean = false;
  @State captureBusy: boolean = false;
  @State frameUrl: string = '';
  @State speed: number = CarDefaults.SPEED;
  @State verticalAngle: number = CarDefaults.VERTICAL_ANGLE;
  @State horizontalAngle: number = CarDefaults.HORIZONTAL_ANGLE;
  @State activeAction: CarAction = CarAction.NONE;
  @State statusText: string = '等待连接';
  @State connectionLogs: string[] = ['[--:--:--] [INFO] 应用已启动，等待输入车端地址'];
  @State galleryItems: GalleryItem[] = [];
  @State galleryLoading: boolean = false;
  @State galleryMessage: string = '照片保存在车端 capture 目录';
  @State captureCount: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    this.connected = false;
    this.connecting = false;
    this.currentScreen = 'connection';
    this.api.setBaseUrl(this.endpoint);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.connectionAttempt += 1;
    this.galleryRequest += 1;
    this.servoRequest += 1;
    this.releaseControls();
    this.stopAndReleaseNetwork(this.connected, this.connectionAttempt);
    this.connected = false;
    this.connecting = false;
  }

  onPageHide(): void {
    if (!this.disposed && (this.connected || this.connecting)) {
      this.suspendConnection('应用进入后台，已安全断开');
    }
  }

  private addConnectionLog(message: string, level: string = 'INFO'): void {
    const now = new Date();
    const time = `${this.pad(now.getHours())}:${this.pad(now.getMinutes())}:${this.pad(now.getSeconds())}`;
    this.connectionLogs = [...this.connectionLogs, `[${time}] [${level}] ${message}`].slice(-10);
    if (level === 'ERR') {
      hilog.error(LogConfig.DOMAIN, LogConfig.TAG, '[%{public}s] %{public}s', level, message);
    } else if (level === 'WARN') {
      hilog.warn(LogConfig.DOMAIN, LogConfig.TAG, '[%{public}s] %{public}s', level, message);
    } else {
      hilog.info(LogConfig.DOMAIN, LogConfig.TAG, '[%{public}s] %{public}s', level, message);
    }
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private async connect(): Promise<void> {
    if (this.connecting) {
      return;
    }
    const normalized = CarApi.normalizeEndpoint(this.endpoint);
    if (normalized.length === 0 || !this.api.setBaseUrl(normalized)) {
      this.statusText = '车端地址格式无效';
      this.addConnectionLog('地址格式无效，请填写 IP:端口或完整 URL', 'ERR');
      return;
    }
    this.endpoint = normalized;
    const attempt = ++this.connectionAttempt;
    this.connecting = true;
    this.statusText = '正在连接小车…';
    this.addConnectionLog(`开始探测 ${normalized}/api/health`);

    let health: ApiResult = await this.api.health();
    if (!this.isCurrentAttempt(attempt)) {
      await this.releaseNetworkIfNoActiveConnection();
      return;
    }
    if (!health.ok) {
      this.statusText = '直连失败，正在通过 Wi-Fi 重试…';
      this.addConnectionLog(`直连失败：${health.message}`, 'WARN');
      this.addConnectionLog('尝试将应用流量绑定到当前 Wi-Fi');
      const routeReady = await this.localNetworkRoute.bind();
      if (!this.isCurrentAttempt(attempt)) {
        await this.releaseNetworkIfNoActiveConnection();
        return;
      }
      if (routeReady) {
        this.addConnectionLog('Wi-Fi 路由绑定成功，重新探测');
        health = await this.api.health();
        if (!this.isCurrentAttempt(attempt)) {
          await this.releaseNetworkIfNoActiveConnection();
          return;
        }
      } else {
        this.addConnectionLog('Wi-Fi 路由绑定不可用', 'WARN');
      }
    }
    if (!health.ok) {
      this.addConnectionLog(`连接失败：${health.message}`, 'ERR');
      this.finishConnectFailure(`连接失败 · ${health.message}`);
      return;
    }

    this.addConnectionLog('健康检查通过，正在初始化云台');
    const servo = await this.api.servo(
      this.verticalAngle,
      this.horizontalAngle,
      this.nextCommandSequence()
    );
    if (!this.isCurrentAttempt(attempt)) {
      await this.releaseNetworkIfNoActiveConnection();
      return;
    }

    this.cameraReady = health.cameraReady !== false;
    if (!servo.ok) {
      this.addConnectionLog(`控制器检查失败：${servo.message}`, 'ERR');
      this.finishConnectFailure(`连接失败 · 控制器不可用：${servo.message}`);
      return;
    }
    if (!this.cameraReady) {
      this.statusText = '已连接 · 控制就绪，摄像头未就绪';
      this.addConnectionLog(`摄像头不可用：${health.cameraError ?? 'camera_not_ready'}`, 'WARN');
    } else {
      this.statusText = '已连接 · 控制就绪';
      this.addConnectionLog('连接成功，进入操控界面');
    }

    this.connecting = false;
    this.connected = true;
    this.currentScreen = 'control';
    if (this.cameraReady) {
      this.startCamera();
    }
  }

  private isCurrentAttempt(attempt: number): boolean {
    return !this.disposed && attempt === this.connectionAttempt;
  }

  private finishConnectFailure(message: string): void {
    this.connecting = false;
    this.connected = false;
    this.cameraReady = false;
    this.stopCamera();
    this.statusText = message;
    this.currentScreen = 'connection';
    this.releaseNetworkWhenInactive(this.connectionAttempt);
  }

  private disconnect(): void {
    this.addConnectionLog('用户主动断开连接');
    this.suspendConnection('已断开，可重新连接');
  }

  private suspendConnection(message: string): void {
    const shouldStop = this.connected;
    const attempt = ++this.connectionAttempt;
    this.galleryRequest += 1;
    this.servoRequest += 1;
    this.releaseControls();
    this.connected = false;
    this.connecting = false;
    this.cameraReady = false;
    this.currentScreen = 'connection';
    this.statusText = message;
    this.addConnectionLog(message);
    this.stopAndReleaseNetwork(shouldStop, attempt);
  }

  private markConnectionLost(message: string): void {
    if (this.disposed) {
      return;
    }
    this.connectionAttempt += 1;
    this.galleryRequest += 1;
    this.servoRequest += 1;
    this.releaseControls();
    this.connected = false;
    this.connecting = false;
    this.cameraReady = false;
    this.currentScreen = 'connection';
    this.statusText = message;
    this.addConnectionLog(`连接错误：${message}`, 'ERR');
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
    if (!this.connected || !this.cameraReady || this.cameraEnabled || this.disposed ||
      this.currentScreen !== 'control') {
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
    if (this.cameraEnabled && this.connected && !this.disposed && this.currentScreen === 'control') {
      this.frameUrl = this.api.frameUrl(Date.now());
    }
  }

  private beginMove(action: CarAction): void {
    if (!this.connected || this.currentScreen !== 'control' || action === CarAction.NONE) {
      this.statusText = '请先连接小车';
      return;
    }
    if (this.activeAction === action) {
      return;
    }
    this.cancelPendingStop();
    this.stopDriveTimer();
    const session = ++this.driveSession;
    this.moveFailureCount = 0;
    this.activeAction = action;
    this.sendMove(action, session);
    this.driveTimer = setInterval(() => this.sendMove(action, session), NetworkConfig.DRIVE_KEEP_ALIVE_MS);
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
    return !this.disposed && this.connected && this.currentScreen === 'control' &&
      session === this.driveSession && this.activeAction === action;
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

  private stepServo(verticalDelta: number, horizontalDelta: number): void {
    const vertical = Math.max(CarLimits.VERTICAL_MIN,
      Math.min(CarLimits.VERTICAL_MAX, this.verticalAngle + verticalDelta));
    const horizontal = Math.max(CarLimits.HORIZONTAL_MIN,
      Math.min(CarLimits.HORIZONTAL_MAX, this.horizontalAngle + horizontalDelta));
    this.verticalAngle = vertical;
    this.horizontalAngle = horizontal;
    this.updateServo(vertical, horizontal);
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
      this.statusText = `截图已保存 · 本次连接第 ${this.captureCount} 张`;
      this.galleryMessage = '截图成功，已显示最新照片';
      this.refreshFrame();
      if (this.currentScreen === 'gallery') {
        this.loadGallery();
      }
    } else if (result.statusCode === 503) {
      this.statusText = '截图失败 · 摄像头尚未就绪';
      this.galleryMessage = this.statusText;
    } else {
      this.statusText = `截图失败 · ${result.message}`;
      this.galleryMessage = this.statusText;
    }
  }

  private openGallery(): void {
    if (!this.connected) {
      return;
    }
    this.stopDriveTimer();
    this.cancelPendingStop();
    this.driveSession += 1;
    this.activeAction = CarAction.NONE;
    const gallerySession = this.driveSession;
    this.sendStop('已停车，可浏览相册', gallerySession);
    this.stopCamera();
    this.currentScreen = 'gallery';
    this.loadGallery();
  }

  private closeGallery(): void {
    if (!this.connected) {
      this.currentScreen = 'connection';
      return;
    }
    this.currentScreen = 'control';
    this.startCamera();
  }

  private async loadGallery(): Promise<void> {
    if (!this.connected) {
      return;
    }
    const request = ++this.galleryRequest;
    this.galleryLoading = true;
    this.galleryMessage = '正在读取车端照片…';
    const result = await this.api.captures();
    if (this.disposed || !this.connected || request !== this.galleryRequest) {
      return;
    }
    this.galleryLoading = false;
    if (!result.ok || result.captures === undefined) {
      this.galleryMessage = `相册读取失败 · ${result.message}`;
      return;
    }
    const stamp = Date.now();
    const items: GalleryItem[] = [];
    result.captures.forEach((name: string) => {
      items.push({ name: name, url: this.api.captureUrl(name, stamp) });
    });
    this.galleryItems = items;
    this.galleryMessage = items.length > 0 ? `共 ${items.length} 张车端照片` : '车端暂时没有照片';
  }

  build() {
    if (this.currentScreen === 'connection') {
      ConnectionScreen({
        endpoint: this.endpoint,
        connecting: this.connecting,
        statusText: this.statusText,
        logs: this.connectionLogs,
        onEndpointChange: (value: string) => this.endpoint = value,
        onConnect: () => this.connect()
      })
    } else if (this.currentScreen === 'gallery') {
      GalleryScreen({
        items: this.galleryItems,
        loading: this.galleryLoading,
        captureBusy: this.captureBusy,
        message: this.galleryMessage,
        onBack: () => this.closeGallery(),
        onRefresh: () => this.loadGallery(),
        onCapture: () => this.capture()
      })
    } else {
      GameControlScreen({
        connected: this.connected,
        cameraReady: this.cameraReady,
        frameUrl: this.frameUrl,
        speed: this.speed,
        activeAction: this.activeAction,
        statusText: this.statusText,
        captureBusy: this.captureBusy,
        verticalAngle: this.verticalAngle,
        horizontalAngle: this.horizontalAngle,
        onMoveStart: (action: CarAction) => this.beginMove(action),
        onMoveEnd: (action: CarAction) => this.endMove(action),
        onEmergencyStop: () => this.emergencyStop(),
        onSpeedChange: (value: number) => this.speed = value,
        onServoStep: (verticalDelta: number, horizontalDelta: number) => {
          this.stepServo(verticalDelta, horizontalDelta);
        },
        onResetServo: () => this.resetServo(),
        onCapture: () => this.capture(),
        onOpenGallery: () => this.openGallery(),
        onDisconnect: () => this.disconnect()
      })
    }
  }
}
