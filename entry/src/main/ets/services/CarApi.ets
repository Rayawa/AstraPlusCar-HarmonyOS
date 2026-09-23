import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiRoutes, CarDefaults, CarLimits, NetworkConfig } from '../constants/AppConstants';
import {
  ApiResult,
  ApiErrorPayload,
  CaptureListPayload,
  CarAction,
  CarCommand,
  failureResult,
  HealthPayload,
  ServoCommand,
  StopCommand,
  successResult
} from '../models/CarModels';

export class CarApi {
  private baseUrl: string = CarDefaults.ENDPOINT;

  setBaseUrl(value: string): boolean {
    const normalized = CarApi.normalizeEndpoint(value);
    if (normalized.length === 0) {
      return false;
    }
    this.baseUrl = normalized;
    return true;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  frameUrl(stamp: number): string {
    return `${this.baseUrl}${ApiRoutes.FRAME}?t=${stamp}`;
  }

  captureUrl(filename: string, stamp: number): string {
    return `${this.baseUrl}${ApiRoutes.CAPTURES}/${encodeURIComponent(filename)}?t=${stamp}`;
  }

  async health(): Promise<ApiResult> {
    return await this.request(ApiRoutes.HEALTH, http.RequestMethod.GET);
  }

  async move(action: CarAction, speed: number, sequence: number,
    degree: number = CarLimits.TURN_DEGREE): Promise<ApiResult> {
    const body: CarCommand = { action: action, speed: speed, degree: degree, sequence: sequence };
    return await this.request(ApiRoutes.MOVE, http.RequestMethod.POST, JSON.stringify(body));
  }

  async stop(sequence: number): Promise<ApiResult> {
    const body: StopCommand = { sequence: sequence };
    return await this.request(ApiRoutes.STOP, http.RequestMethod.POST, JSON.stringify(body));
  }

  async servo(vertical: number, horizontal: number, sequence: number): Promise<ApiResult> {
    const body: ServoCommand = { vertical: vertical, horizontal: horizontal, sequence: sequence };
    return await this.request(ApiRoutes.SERVO, http.RequestMethod.POST, JSON.stringify(body));
  }

  async capture(): Promise<ApiResult> {
    return await this.request(ApiRoutes.CAPTURE, http.RequestMethod.POST, '{}');
  }

  async captures(): Promise<ApiResult> {
    return await this.request(ApiRoutes.CAPTURES, http.RequestMethod.GET);
  }

  static normalizeEndpoint(value: string): string {
    let normalized = value.trim();
    if (normalized.length === 0) {
      return '';
    }
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = `http://${normalized}`;
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith(ApiRoutes.HEALTH)) {
      normalized = normalized.substring(0, normalized.length - ApiRoutes.HEALTH.length);
    }
    const schemeIndex = normalized.indexOf('://');
    const authority = schemeIndex >= 0 ? normalized.substring(schemeIndex + 3) : '';
    if (authority.length === 0 || authority.includes(' ') || authority.includes('/') ||
      authority.includes('?') || authority.includes('#')) {
      return '';
    }
    return normalized;
  }

  private async request(path: string, method: http.RequestMethod, data?: string): Promise<ApiResult> {
    const task = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: { 'Content-Type': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: NetworkConfig.CONNECT_TIMEOUT_MS,
        readTimeout: NetworkConfig.READ_TIMEOUT_MS,
        usingCache: false
      };
      if (data !== undefined) {
        options.extraData = data;
      }
      const response = await task.request(`${this.baseUrl}${path}`, options);
      if (response.responseCode >= 200 && response.responseCode < 300) {
        const result = successResult(response.responseCode);
        if (path === ApiRoutes.HEALTH) {
          const health = CarApi.parseHealthPayload(response.result.toString());
          if (health.ok !== true) {
            return failureResult('健康检查响应格式无效', response.responseCode);
          }
          result.cameraReady = health.cameraReady === true;
          result.cameraError = health.cameraError ?? '';
        } else if (path === ApiRoutes.CAPTURES) {
          const gallery = CarApi.parseCaptureList(response.result.toString());
          if (gallery.ok !== true || gallery.captures === undefined) {
            return failureResult('相册响应格式无效', response.responseCode);
          }
          result.captures = gallery.captures;
        }
        return result;
      }
      const serverError = CarApi.parseServerError(response.result.toString());
      const message = serverError.length > 0 ?
        `${CarApi.describeServerError(serverError)}（HTTP ${response.responseCode}）` :
        `HTTP ${response.responseCode}`;
      return failureResult(message, response.responseCode);
    } catch (error) {
      const code = CarApi.readBusinessErrorCode(error as BusinessError);
      return failureResult(CarApi.describeNetworkError(code), 0, code);
    } finally {
      try {
        task.destroy();
      } catch (error) {
        // Request result is already known; cleanup failures must not crash UI callbacks.
      }
    }
  }

  private static describeNetworkError(code: number): string {
    if (code === 2300007) {
      return '连接被拒绝，请确认手机与小车在同一 Wi-Fi 且端口已监听';
    }
    if (code === 2300028) {
      return '连接超时，请检查手机 Wi-Fi 与小车地址';
    }
    if (code === 2300997) {
      return '系统阻止了明文 HTTP 访问';
    }
    return code > 0 ? `网络请求失败（${code}）` : '网络请求失败';
  }

  private static parseHealthPayload(value: string): HealthPayload {
    try {
      const payload = JSON.parse(value) as HealthPayload;
      return payload === null ? {} : payload;
    } catch (error) {
      return {};
    }
  }

  private static parseCaptureList(value: string): CaptureListPayload {
    try {
      const payload = JSON.parse(value) as CaptureListPayload;
      return payload === null ? {} : payload;
    } catch (error) {
      return {};
    }
  }

  private static parseServerError(value: string): string {
    try {
      const payload = JSON.parse(value) as ApiErrorPayload;
      return payload.error ?? '';
    } catch (error) {
      return '';
    }
  }

  private static describeServerError(error: string): string {
    if (error === 'controller_unavailable') {
      return '车端控制器不可用';
    }
    if (error === 'camera_not_ready') {
      return '车端摄像头未就绪';
    }
    return error;
  }

  private static readBusinessErrorCode(error: BusinessError): number {
    try {
      return typeof error.code === 'number' ? error.code : 0;
    } catch (ignored) {
      return 0;
    }
  }
}
