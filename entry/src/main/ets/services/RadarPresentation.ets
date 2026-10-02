import { PhoneLidar } from './PhoneApi';

export interface RadarReadings {
  ready: boolean;
  points: number;
  frontMm: number | null;
  leftMm: number | null;
  rightMm: number | null;
}

/** All comparisons use the API's millimeters; conversion is only for display. */
export class RadarPresentation {
  static readonly DANGER_MM: number = 200;
  static readonly WARNING_MM: number = 500;
  static readonly STALE_SECONDS: number = 2.5;

  static validDistance(value: number | null | undefined): number | null {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : null;
  }

  static read(lidar: PhoneLidar): RadarReadings {
    const points = Number.isFinite(lidar.points) && lidar.points > 0 ? Math.floor(lidar.points) : 0;
    const fresh = lidar.age_seconds === undefined ||
      (Number.isFinite(lidar.age_seconds) && lidar.age_seconds >= 0 &&
        lidar.age_seconds < RadarPresentation.STALE_SECONDS);
    const ready = lidar.status === 'scanning' && lidar.health === 'OK' && points > 0 && fresh;
    return {
      ready: ready,
      points: ready ? points : 0,
      frontMm: ready ? RadarPresentation.validDistance(lidar.front_nearest_mm) : null,
      leftMm: ready ? RadarPresentation.validDistance(lidar.sector_270_mm) : null,
      rightMm: ready ? RadarPresentation.validDistance(lidar.sector_90_mm) : null
    };
  }

  static distanceText(value: number | null, scanning: boolean): string {
    if (!scanning) { return '未就绪'; }
    const mm = RadarPresentation.validDistance(value);
    if (mm === null) { return '未测得'; }
    if (mm < 10) { return '<0.01 m'; }
    return `${(mm / 1000).toFixed(2)} m`;
  }

  static rawText(value: number | null): string {
    const mm = RadarPresentation.validDistance(value);
    return mm === null ? '--' : `${Math.round(mm)} mm`;
  }

  static level(value: number | null, scanning: boolean): number {
    const mm = scanning ? RadarPresentation.validDistance(value) : null;
    if (mm === null) { return 0; }
    if (mm <= RadarPresentation.DANGER_MM) { return 3; }
    if (mm <= RadarPresentation.WARNING_MM) { return 2; }
    return 1;
  }

  static color(value: number | null, scanning: boolean): string {
    const level = RadarPresentation.level(value, scanning);
    if (level === 3) { return '#FF6B6B'; }
    if (level === 2) { return '#FFC857'; }
    if (level === 1) { return '#62E6A7'; }
    return '#A7B5BF';
  }

  static label(value: number | null, scanning: boolean): string {
    const level = RadarPresentation.level(value, scanning);
    if (level === 3) { return '过近'; }
    if (level === 2) { return '注意'; }
    if (level === 1) { return '较远'; }
    return scanning ? '未测得' : '未就绪';
  }
}
