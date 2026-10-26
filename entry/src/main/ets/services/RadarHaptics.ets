import { Haptics } from './Haptics';

/** Obstacle alerts have their own amplitudes, independent of button feedback. */
export class RadarHaptics {
  private static readonly WARNING_INTENSITY: number = 20;
  private static readonly DANGER_INTENSITY: number = 65;

  static warning(): void {
    Haptics.playPreset('haptic.effect.soft', 1, RadarHaptics.WARNING_INTENSITY);
  }

  static danger(): void {
    Haptics.playPreset('haptic.effect.hard', 1, RadarHaptics.DANGER_INTENSITY);
  }
}
