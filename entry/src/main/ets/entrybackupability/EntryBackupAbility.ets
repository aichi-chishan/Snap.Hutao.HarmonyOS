import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { BackgroundTaskService } from '../service/BackgroundTaskService';
import { DailyNoteService } from '../service/DailyNoteService';

const DOMAIN = 0x0000;

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    hilog.info(DOMAIN, 'testTag', 'onBackup ok');
    await Promise.resolve();
  }

  async onRestore(_bundleVersion: BundleVersion): Promise<void> {
    // The operational database is excluded from OS backup. Discard any local jobs before
    // restore completes; this extension never restores a login session or performs network work.
    await BackgroundTaskService.init(this.context);
    await BackgroundTaskService.reset();
    await DailyNoteService.getInstance().clearCardSnapshot();
    hilog.info(DOMAIN, 'EntryBackupAbility', 'background tasks reset after restore');
  }
}