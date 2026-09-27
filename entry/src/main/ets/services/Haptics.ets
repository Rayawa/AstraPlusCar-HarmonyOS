import { vibrator } from '@kit.SensorServiceKit';

/** Brief touch feedback; unsupported effects are silently ignored. */
export class Haptics {
  static soft(): void { Haptics.play('haptic.effect.soft', 35); }
  static hard(): void { Haptics.play('haptic.effect.hard', 50); }

  private static play(effectId: string, intensity: number): void {
    try {
      vibrator.startVibration({ type: 'preset', effectId: effectId, count: 1, intensity: intensity },
        { usage: 'touch' }, () => {});
    } catch (error) {
      // A device without this preset still supports the touch action.
    }
  }
}
