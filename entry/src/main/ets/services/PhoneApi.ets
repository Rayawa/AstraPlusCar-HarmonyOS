import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface PhoneCamera {
  status: string;
  frame_time: string | null;
  age_ms: number | null;
}

export interface PhoneLidar {
  status: string;
  health: string;
  points: number;
  nearest_mm: number | null;
  front_nearest_mm: number | null;
  observed_at: string | null;
  age_seconds?: number;
  error?: string;
}

export interface PhoneStatus {
  bootId: string;
  mode: string;
  speed: number;
  moving: boolean;
  controlBusy: boolean;
  camera: PhoneCamera;
  lidar: PhoneLidar;
}

export interface PhoneSession {
  sessionId: string;
  bootId: string;
  leaseMs: number;
}

export interface PhoneResult {
  accepted: boolean;
  speed: number;
  commandId: string;
}

export interface PhoneCapture {
  captureId: string;
  url: string;
}

interface ServerError {
  code?: string;
  message?: string;
}

interface RequestBody {
  sessionId?: string;
  seq?: number;
  commandId?: string;
  key?: string;
  speed?: number;
}

export class PhoneApi {
  private baseUrl: string = 'http://192.168.149.1:8080';

  static normalizeEndpoint(value: string): string {
    let result = value.trim();
    if (result.length === 0) {
      return '';
    }
    if (!result.startsWith('http://') && !result.startsWith('https://')) {
      result = `http://${result}`;
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    const authority = result.split('://')[1];
    if (!authority || authority.includes('/') || authority.includes(' ') ||
      authority.includes('?') || authority.includes('#')) {
      return '';
    }
    return result;
  }

  setBaseUrl(value: string): boolean {
    const normalized = PhoneApi.normalizeEndpoint(value);
    if (normalized.length === 0) {
      return false;
    }
    this.baseUrl = normalized;
    return true;
  }

  frameUrl(stamp: number): string {
    return `${this.baseUrl}/api/v1/camera/frame.jpg?t=${stamp}`;
  }

  async status(): Promise<PhoneStatus> {
    return await this.request<PhoneStatus>('/api/v1/status', http.RequestMethod.GET);
  }

  async session(): Promise<PhoneSession> {
    return await this.request<PhoneSession>('/api/v1/control/session', http.RequestMethod.POST, {});
  }

  async command(sessionId: string, seq: number, commandId: string, key: string): Promise<PhoneResult> {
    return await this.request<PhoneResult>('/api/v1/control/command', http.RequestMethod.POST,
      { sessionId: sessionId, seq: seq, commandId: commandId, key: key });
  }

  async renew(sessionId: string, commandId: string): Promise<PhoneResult> {
    return await this.request<PhoneResult>('/api/v1/control/renew', http.RequestMethod.POST,
      { sessionId: sessionId, commandId: commandId });
  }

  async stop(sessionId: string): Promise<PhoneResult> {
    return await this.request<PhoneResult>('/api/v1/control/stop', http.RequestMethod.POST,
      { sessionId: sessionId });
  }

  async speed(sessionId: string, seq: number, commandId: string, speed: number): Promise<PhoneResult> {
    return await this.request<PhoneResult>('/api/v1/control/speed', http.RequestMethod.POST,
      { sessionId: sessionId, seq: seq, commandId: commandId, speed: speed });
  }

  async capture(): Promise<PhoneCapture> {
    return await this.request<PhoneCapture>('/api/v1/camera/captures', http.RequestMethod.POST, {});
  }

  async downloadCapture(captureId: string): Promise<ArrayBuffer> {
    if (!/^[a-zA-Z0-9-]+\.jpg$/.test(captureId)) {
      throw new Error('截图编号无效');
    }
    const task = http.createHttp();
    try {
      const response = await task.request(
        `${this.baseUrl}/api/v1/camera/captures/${encodeURIComponent(captureId)}`,
        { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 2000, readTimeout: 8000, usingCache: false });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) {
        throw new Error(`截图下载失败（HTTP ${response.responseCode}）`);
      }
      return response.result as ArrayBuffer;
    } finally {
      task.destroy();
    }
  }

  private async request<T>(path: string, method: http.RequestMethod, body?: RequestBody): Promise<T> {
    const task = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: { 'Content-Type': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 2000,
        readTimeout: 2000,
        usingCache: false
      };
      if (body !== undefined) {
        options.extraData = JSON.stringify(body);
      }
      const response = await task.request(`${this.baseUrl}${path}`, options);
      const value = JSON.parse(response.result.toString()) as T;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const serverError = JSON.parse(response.result.toString()) as ServerError;
        throw new Error(serverError.message ?? serverError.code ?? `HTTP ${response.responseCode}`);
      }
      return value;
    } catch (error) {
      const failure = error as BusinessError;
      throw new Error(failure.message ?? '网络连接失败');
    } finally {
      task.destroy();
    }
  }
}
