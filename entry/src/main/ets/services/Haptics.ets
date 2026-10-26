import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** Preset touch feedback with cached hardware/effect support checks. */
export class Haptics {
  private static hardwareSupported: boolean | undefined = undefined;
  private static effectSupport: Map<string, boolean> = new Map();

  static soft(): void { Haptics.playPreset('haptic.effect.soft', 1, 50); }
  static hard(): void { Haptics.playPreset('haptic.effect.hard', 1, 50); }

  static isSupported(): boolean {
    if (Haptics.hardwareSupported !== undefined) { return Haptics.hardwareSupported; }
    try {
      Haptics.hardwareSupported = vibrator.getVibratorInfoSync().length > 0;
      return Haptics.hardwareSupported;
    } catch (error) {
      Haptics.logError('查询振动硬件失败', error as BusinessError);
      return false;
    }
  }

  static playPreset(effectId: string, count: number, intensity: number): void {
    if (!Haptics.isSupported()) { return; }
    let supported = Haptics.effectSupport.get(effectId);
    if (supported === undefined) {
      try {
        supported = vibrator.isSupportEffectSync(effectId);
        Haptics.effectSupport.set(effectId, supported);
      } catch (error) {
        Haptics.logError(`查询振动效果 ${effectId} 失败`, error as BusinessError);
        return;
      }
      if (!supported) {
        console.warn('[Astra][Haptics]', `设备不支持振动效果 ${effectId}`);
      }
    }
    if (!supported) { return; }
    try {
      vibrator.startVibration({ type: 'preset', effectId: effectId, count: count, intensity: intensity },
        { usage: 'touch' }, (error: BusinessError) => {
          if (error) { Haptics.logError(`启动振动效果 ${effectId} 失败`, error); }
        });
    } catch (error) {
      Haptics.logError(`启动振动效果 ${effectId} 失败`, error as BusinessError);
    }
  }

  private static logError(action: string, error: BusinessError): void {
    console.error('[Astra][Haptics]', `${action}，code: ${error.code}, message: ${error.message}`);
  }
}
