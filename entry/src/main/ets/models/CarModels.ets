export enum CarAction {
  NONE = '',
  FORWARD = 'forward',
  BACKWARD = 'backward',
  LEFT = 'left',
  RIGHT = 'right',
  SHIFT_LEFT = 'shift_left',
  SHIFT_RIGHT = 'shift_right',
  SPIN_LEFT = 'spin_left',
  SPIN_RIGHT = 'spin_right'
}

export interface CarCommand {
  action: string;
  speed: number;
  degree: number;
  sequence: number;
}

export interface StopCommand {
  sequence: number;
}

export interface ServoCommand {
  vertical: number;
  horizontal: number;
  sequence: number;
}

export interface ApiResult {
  ok: boolean;
  statusCode: number;
  message: string;
  errorCode: number;
  cameraReady?: boolean;
  cameraError?: string;
  captures?: string[];
}

export interface CaptureListPayload {
  ok?: boolean;
  captures?: string[];
}

export interface CommandPayload {
  ok?: boolean;
  accepted?: boolean;
}

export interface GalleryItem {
  name: string;
  url: string;
}

export interface ApiErrorPayload {
  error?: string;
}

export interface HealthPayload {
  ok?: boolean;
  cameraReady?: boolean;
  cameraError?: string;
}

export function successResult(statusCode: number): ApiResult {
  return { ok: true, statusCode: statusCode, message: '', errorCode: 0 };
}

export function failureResult(message: string, statusCode: number = 0, errorCode: number = 0): ApiResult {
  return { ok: false, statusCode: statusCode, message: message, errorCode: errorCode };
}
