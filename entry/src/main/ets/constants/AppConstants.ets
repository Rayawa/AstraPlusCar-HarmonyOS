/** Application-wide defaults and limits. Keep device protocol values here. */
export class CarDefaults {
  static readonly ENDPOINT: string = 'http://192.168.149.1:8080';
  static readonly SPEED: number = 35;
  static readonly VERTICAL_ANGLE: number = 90;
  static readonly HORIZONTAL_ANGLE: number = 65;

  private constructor() {
  }
}

export class CarLimits {
  static readonly SPEED_MIN: number = 25;
  static readonly SPEED_MAX: number = 60;
  static readonly SPEED_STEP: number = 1;
  static readonly VERTICAL_MIN: number = 20;
  static readonly VERTICAL_MAX: number = 160;
  static readonly HORIZONTAL_MIN: number = 0;
  static readonly HORIZONTAL_MAX: number = 180;
  static readonly SERVO_STEP: number = 1;
  static readonly TURN_DEGREE: number = 1.1;

  private constructor() {
  }
}

export class NetworkConfig {
  static readonly CONNECT_TIMEOUT_MS: number = 4000;
  static readonly READ_TIMEOUT_MS: number = 5000;
  static readonly FRAME_REFRESH_MS: number = 350;
  static readonly DRIVE_KEEP_ALIVE_MS: number = 300;
  static readonly DIRECTION_SWITCH_GRACE_MS: number = 40;
  static readonly MOVE_FAILURE_LIMIT: number = 2;

  private constructor() {
  }
}

export class LayoutConfig {
  static readonly WIDE_BREAKPOINT: number = 760;

  private constructor() {
  }
}

export class LogConfig {
  static readonly DOMAIN: number = 0xA57A;
  static readonly TAG: string = 'AstraDrive';

  private constructor() {
  }
}

export class AppColors {
  static readonly BACKGROUND: string = '#071019';
  static readonly PANEL: string = '#101C27';
  static readonly PANEL_SOFT: string = '#152431';
  static readonly PRIMARY: string = '#62E6A7';
  static readonly PRIMARY_DARK: string = '#103B30';
  static readonly TEXT: string = '#F4F8FB';
  static readonly TEXT_MUTED: string = '#94A9B8';
  static readonly DANGER: string = '#FF6B6B';
  static readonly WARNING: string = '#FFC857';
  static readonly BORDER: string = '#243746';
  static readonly CAMERA_BACKGROUND: string = '#050A0F';
  static readonly LIVE_BADGE: string = '#B3071019';
  static readonly STOP_BACKGROUND: string = '#4A2025';
  static readonly PRIMARY_BLUE: string = '#0A84FF';
  static readonly SUCCESS: string = '#34C759';

  private constructor() {
  }
}

export class ApiRoutes {
  static readonly HEALTH: string = '/api/health';
  static readonly FRAME: string = '/api/camera/frame';
  static readonly MOVE: string = '/api/control/move';
  static readonly STOP: string = '/api/control/stop';
  static readonly SERVO: string = '/api/control/servo';
  static readonly CAPTURE: string = '/api/camera/capture';
  static readonly CAPTURES: string = '/api/camera/captures';

  private constructor() {
  }
}
