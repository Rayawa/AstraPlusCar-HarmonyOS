import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { LogConfig } from '../constants/AppConstants';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, 'onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    hilog.info(LogConfig.DOMAIN, LogConfig.TAG, 'onRestore ok %{public}s', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}
