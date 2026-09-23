import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LogConfig } from '../constants/AppConstants';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.getMainWindow()
      .then((mainWindow: window.Window) => {
        return mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_PORTRAIT);
      })
      .catch((err: Error) => {
        hilog.error(LogConfig.DOMAIN, LogConfig.TAG,
          'Failed to set portrait orientation. Cause: %{public}s', JSON.stringify(err));
      });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(LogConfig.DOMAIN, LogConfig.TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(LogConfig.DOMAIN, LogConfig.TAG, 'Succeeded in loading content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(LogConfig.DOMAIN, LogConfig.TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, '%{public}s', 'Ability onBackground');
  }
}
