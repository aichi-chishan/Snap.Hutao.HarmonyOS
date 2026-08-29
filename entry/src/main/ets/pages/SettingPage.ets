/**
 * SettingPage.ets（@Entry）
 * 设置：主题、沉浸光感、每日背景、便笺自动刷新、祈愿数据管理（清空/删除归档）、账号与数据入口、退出登录。
 */
import { router, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { UserService } from '../service/UserService';
import { DailyNoteService } from '../service/DailyNoteService';
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaArchive } from '../model/GachaArchive';
import { Logger } from '../common/Logger';
import { AppBackButton } from '../components/AppBackButton';
import EntryAbility from '../entryability/EntryAbility';
import { ResourcePackService } from '../data/remote/ResourcePackService';
import { GameDataService } from '../service/GameDataService';
import { GameDataUpdater } from '../data/remote/GameDataUpdater';

const TAG: string = 'SettingPage';

/** 祈愿归档行（数据管理） */
class GachaArchiveRow {
  id: number = 0;
  uid: string = '';
  count: number = 0;
}

@Entry
@Component
export struct SettingPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State themeMode: string = 'system';
  @State autoRefresh: boolean = true;
  @State interval: number = 30;
  @State ambientLevel: number = 1;
  @State dailyBgEnabled: boolean = true;
  /** 背景图片来源（none/local/bing） */
  @StorageProp('bgType') bgType: string = 'local';
  @StorageProp('bgFolderPath') bgFolderPath: string = '';
  @StorageProp('bgCopyright') bgCopyright: string = '';
  @State resourceBusy: boolean = false;
  @State resourceDone: number = 0;
  /** 数据源管理（GitHub 元数据更新） */
  @State dataBusy: boolean = false;
  @State dataDone: number = 0;
  @State dataTotal: number = 0;
  @State dataVersion: string = '';
  @State dataHasUpdate: string = '';
  @State dataUrl: string = '';
  /** 数据源 URL 编辑弹窗 */
  @State showUrlEdit: boolean = false;
  @State urlInput: string = '';
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;
  /** 祈愿归档（数据管理） */
  @State gachaRows: GachaArchiveRow[] = [];

  aboutToAppear(): void {
    this.themeMode = PreferencesStore.getThemeMode();
    this.autoRefresh = PreferencesStore.getAutoRefreshEnabled();
    this.interval = PreferencesStore.getRefreshIntervalMinutes();
    // 三档映射：0=关，0.5/0.25=标准，1=增强
    const s: number = PreferencesStore.getAmbientStrength();
    if (s <= 0) {
      this.ambientLevel = 0;
    } else if (s >= 1) {
      this.ambientLevel = 2;
    } else {
      this.ambientLevel = 1;
    }
    this.dailyBgEnabled = PreferencesStore.getDailyBgEnabled();
    this.dataUrl = GameDataUpdater.manifestUrl();
    this.loadGachaRows();
  }

  /** 载入祈愿归档与各归档记录数 */
  async loadGachaRows(): Promise<void> {
    try {
      const archives: GachaArchive[] = await GachaRepo.getAllArchives();
      const rows: GachaArchiveRow[] = [];
      for (const a of archives) {
        const row: GachaArchiveRow = new GachaArchiveRow();
        row.id = a.id;
        row.uid = a.uid;
        row.count = await GachaRepo.countAll(a.id);
        rows.push(row);
      }
      this.gachaRows = rows;
    } catch (e) {
      Logger.warn(TAG, `load gacha rows fail: ${(e as Error).message}`);
    }
  }

  /** 删除单个祈愿归档（二次确认） */
  confirmDeleteArchive(row: GachaArchiveRow): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除祈愿数据',
      message: `确定删除 UID ${row.uid} 的 ${row.count} 条祈愿记录？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.danger') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index === 1) {
        GachaRepo.deleteArchiveByUid(row.uid).then(() => {
          this.toast('已删除');
          this.loadGachaRows();
        });
      }
    });
  }

  /** 清空全部祈愿数据（二次确认） */
  confirmClearAllGacha(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '清空全部祈愿数据',
      message: '将删除所有 UID 的全部祈愿记录，且不可恢复。确定继续？',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '清空', color: $r('app.color.danger') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index === 1) {
        GachaRepo.getAllArchives().then((archives: GachaArchive[]) => {
          const tasks: Promise<void>[] = [];
          for (const a of archives) {
            tasks.push(GachaRepo.deleteArchive(a.id));
          }
          Promise.all(tasks).then(() => {
            this.toast('已清空全部祈愿数据');
            this.loadGachaRows();
          });
        });
      }
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
  }

  /** 让自动刷新设置实时生效 */
  syncAutoTimer(): void {
    if (this.autoRefresh) {
      DailyNoteService.getInstance().startAutoRefresh(PreferencesStore.getRefreshIntervalMinutes());
    } else {
      DailyNoteService.getInstance().stopAutoRefresh();
    }
  }

  applyTheme(mode: string): void {
    PreferencesStore.setThemeMode(mode);
    this.themeMode = mode;
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    try {
      const appCtx: common.ApplicationContext = host.getApplicationContext();
      if (mode === 'light') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
      // 同步深浅色状态（驱动壁纸遮罩/状态栏图标色）
      let sysDark: boolean = false;
      let applyOk: boolean = false;
      try {
        const cfg = appCtx.resourceManager.getConfigurationSync();
        // resourceManager.ColorMode：DARK=0；仅显式为深色才判深色（浅色/未设置均非深色）
        sysDark = cfg !== undefined && cfg.colorMode === 0;
        applyOk = true;
      } catch (e) {
        Logger.warn(TAG, 'read sys colorMode fail');
      }
      const isDark: boolean = mode === 'dark' || (mode !== 'light' && sysDark);
      AppStorage.setOrCreate<boolean>('isDarkMode', isDark);
      // setColorMode 后配置异步生效：跟随系统模式延迟重读兜底，避免读到旧配置导致主题错判
      if (mode !== 'light' && mode !== 'dark') {
        setTimeout(() => {
          try {
            const lateCfg = appCtx.resourceManager.getConfigurationSync();
            if (lateCfg !== undefined) {
              const lateDark: boolean = lateCfg.colorMode === 0;
              AppStorage.setOrCreate<boolean>('isDarkMode', lateDark);
            }
          } catch (e) {
            Logger.warn(TAG, 'late read sys colorMode fail');
          }
        }, 150);
      }
      // 状态栏图标色 + 窗口根底色同步深浅色
      window.getLastWindow(host).then((win: window.Window) => {
        EntryAbility.applySystemBarColors(win);
        EntryAbility.applyWindowBackdrop(win);
      }).catch(() => {
      });
    } catch (e) {
      Logger.warn(TAG, 'applyTheme fail');
    }
  }

  @Builder
  header() {
    Row() {
      if (!this.embedMode) {
        AppBackButton()
      }
      Text('设置')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ top: 14, bottom: 6 })
  }

  @Builder
  themeSection() {
    Row({ space: 10 }) {
      this.themeChip('system', '跟随系统')
      this.themeChip('light', '浅色')
      this.themeChip('dark', '深色')
    }
    .width('100%')
  }

  @Builder
  bgTypeChip(value: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.bgType === value ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor(this.bgType === value ? $r('app.color.app_primary') : Color.Transparent)
      .border({ width: 1, color: $r('app.color.divider') })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.bgType = value;
        PreferencesStore.setBackgroundImageType(value);
        AppStorage.setOrCreate<string>('bgType', value);
        this.toast(`背景图片：${label}`);
      })
  }

  /** 选择本地背景图片文件夹（FOLDER 模式） */  /** 云端资源包：检查并下载全部大图 */
  async downloadResourcePack(): Promise<void> {
    if (this.resourceBusy) {
      return;
    }
    this.resourceBusy = true;
    this.resourceDone = 0;
    try {
      const done: number = await ResourcePackService.downloadAll((d: number, total: number, name: string) => {
        this.resourceDone = d;
      });
      this.toast(`资源包完成：${done} 项`);
    } catch (e) {
      this.toast(`下载失败：${(e as Error).message}（请确认清单地址/网络）`);
    } finally {
      this.resourceBusy = false;
    }
  }

  /** 数据源管理：检查 GitHub 最新元数据版本 */
  async checkDataUpdate(): Promise<void> {
    try {
      const has: boolean | null = await GameDataService.getInstance().checkUpdateAvailable();
      if (has === null) {
        this.dataHasUpdate = '检查失败：请确认数据源地址与网络';
      } else if (has) {
        this.dataHasUpdate = '发现新版本，点击"立即更新"获取最新数据';
      } else {
        this.dataHasUpdate = '已是最新版本';
      }
    } catch (e) {
      this.dataHasUpdate = `检查失败：${(e as Error).message}`;
    }
  }

  /** 数据源管理：全量更新（元数据 JSON） */
  async updateGameData(): Promise<void> {
    if (this.dataBusy) {
      return;
    }
    this.dataBusy = true;
    this.dataDone = 0;
    this.dataTotal = 0;
    try {
      const ver: string = await GameDataService.getInstance().updateAll((done: number, total: number, cur: string) => {
        this.dataDone = done;
        this.dataTotal = total;
      });
      this.dataVersion = ver;
      this.dataHasUpdate = `更新完成（${ver}）`;
      this.toast(`数据更新完成：${ver}`);
    } catch (e) {
      this.dataHasUpdate = `更新失败：${(e as Error).message}`;
    } finally {
      this.dataBusy = false;
    }
  }

  /** 修改数据源清单 URL（保存到 Preferences，下次更新生效） */
  applyDataUrl(): void {
    const url: string = this.urlInput.trim();
    if (url.length === 0 || !url.startsWith('http')) {
      this.toast('请输入合法的 http(s) 清单地址');
      return;
    }
    GameDataUpdater.setManifestUrl(url);
    this.dataUrl = url;
    this.showUrlEdit = false;
    this.dataHasUpdate = '';
    this.toast('数据源已更新');
  }

  /** 选择本地背景图片文件夹（FOLDER 模式） */
  async pickBgFolder(): Promise<void> {
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.selectMode = picker.DocumentSelectMode.FOLDER;
      const uris: string[] = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      // file://media/... → 转沙盒可读路径：保存选中目录 URI，由 WallpaperLayer 通过 PhotoAccessAbility 读取
      this.bgFolderPath = uris[0];
      PreferencesStore.setBackgroundFolderPath(uris[0]);
      AppStorage.setOrCreate<string>('bgFolderPath', uris[0]);
      this.toast('背景文件夹已更新');
    } catch (e) {
      this.toast(`选择文件夹失败：${(e as Error).message}`);
    }
  }

  @Builder
  themeChip(mode: string, label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.themeMode === mode ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
      .borderRadius(12)
      .backgroundColor(this.themeMode === mode ? $r('app.color.app_primary') : $r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.themeMode = mode;
        this.applyTheme(mode);
      })
  }

  @Builder
  ambientChip(level: number, label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.ambientLevel === level ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
      .borderRadius(12)
      .backgroundColor(this.ambientLevel === level ? $r('app.color.app_primary') : $r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.ambientLevel = level;
        // 三档 → 存 0/0.5/1 供 Index 映射官方材质等级
        const strength: number = level === 0 ? 0 : (level === 1 ? 0.5 : 1);
        PreferencesStore.setAmbientStrength(strength);
        this.toast(level === 0 ? '已关闭沉浸光感' : (level === 1 ? '沉浸光感：标准' : '沉浸光感：增强'));
      })
  }

  @Builder
  rowItem(title: string, subtitle: string, action: () => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(action)
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 10 }) {
          this.sectionTitle('主题')
          this.themeSection()

          this.sectionTitle('沉浸光感')
          Row({ space: 10 }) {
            this.ambientChip(0, '关闭')
            this.ambientChip(1, '标准')
            this.ambientChip(2, '增强')
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.divider') })

          this.sectionTitle('背景图片')
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              this.bgTypeChip('none', '无背景图片')
              this.bgTypeChip('local', '本地随机图片')
            }
            .width('100%')

            if (this.bgType === 'local') {
              Row() {
                Column({ space: 2 }) {
                  Text('自定义背景图片文件夹')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.bgFolderPath.length > 0 ? this.bgFolderPath : '未选择（显示主题纯色底）')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('选择')
                  .fontSize(12)
                  .fontColor($r('app.color.app_primary'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(10)
                  .backgroundColor($r('app.color.app_primary_bg'))
                  .onClick(() => {
                    this.pickBgFolder();
                  })
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }

            Text('本地目录递归扫描图片，5 分钟轮换；未选目录或目录无图片时显示主题纯色底（与无背景图片一致）')
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.divider') })

          this.sectionTitle('云资源同步（GitHub 直连失败自动走镜像加速）')
          Row() {
            Column({ space: 2 }) {
              Text('游戏数据源（GitHub）')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text('角色/武器/怪物/成就元数据与常用图标已内置安装包；此处仅同步版本更新。直连失败自动回退 ghfast/ghproxy 镜像')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.divider') })
          Row() {
            Text('数据源地址')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(GameDataService.getInstance().remoteVersion().length > 0
              ? `当前版本 ${GameDataService.getInstance().remoteVersion()}`
              : '未更新（使用内置数据）')
              .fontSize(10)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '55%' })
            Text('修改')
              .fontSize(12)
              .fontColor($r('app.color.app_primary'))
              .padding({ left: 10 })
              .onClick(() => {
                this.urlInput = this.dataUrl;
                this.showUrlEdit = true;
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 2, bottom: 4 })
          if (this.dataHasUpdate.length > 0) {
            Row() {
              Text(this.dataHasUpdate)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 2, bottom: 2 })
          }
          Row() {
            Button('检查更新')
              .fontSize(13)
              .height(34)
              .backgroundColor($r('app.color.app_primary_bg'))
              .fontColor($r('app.color.app_primary'))
              .margin({ right: 10 })
              .onClick(() => {
                this.checkDataUpdate();
              })
            Button('立即更新')
              .fontSize(13)
              .height(34)
              .backgroundColor($r('app.color.app_primary'))
              .fontColor(Color.White)
              .onClick(() => {
                this.updateGameData();
              })
            if (this.dataBusy) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.app_primary'))
                .margin({ left: 10 })
            } else if (this.dataTotal > 0) {
              Text(`${this.dataDone}/${this.dataTotal}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 10 })
            }
          }
          .width('100%')
          .padding(14)
          .alignItems(VerticalAlign.Center)

          Row() {
            Column({ space: 2 }) {
              Text('大图扩展包（角色立绘 / 名片，按需下载）')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text('同一仓库 resource_manifest.json；同一镜像加速链路。体积大故不内置安装包')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.divider') })
          Row() {
            Text('清单地址')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(ResourcePackService.getManifestUrl())
              .fontSize(10)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '62%' })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 2, bottom: 4 })
          Row() {
            Button('检查并下载')
              .fontSize(13)
              .height(34)
              .backgroundColor($r('app.color.app_primary'))
              .fontColor(Color.White)
              .onClick(() => {
                this.downloadResourcePack();
              })
            if (this.resourceDone > 0) {
              Text(`已完成 ${this.resourceDone} 项`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 10 })
            } else if (this.resourceBusy) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.app_primary'))
                .margin({ left: 10 })
            }
          }
          .width('100%')
          .padding(14)
          .alignItems(VerticalAlign.Center)

          this.sectionTitle('实时便笺')
          Row() {
            Text('自动刷新')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.autoRefresh })
              .onChange((isOn: boolean) => {
                this.autoRefresh = isOn;
                PreferencesStore.setAutoRefreshEnabled(isOn);
                this.syncAutoTimer();
                this.toast(isOn ? '已开启自动刷新' : '已关闭自动刷新');
              })
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.divider') })

          Column({ space: 8 }) {
            ForEach([5, 10, 15, 30, 60] as number[], (min: number) => {
              Row({ space: 8 }) {
                Text(this.interval === min ? '◉' : '○')
                  .fontSize(14)
                  .fontColor(this.interval === min ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
                Text(`每 ${min} 分钟`)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
              }
              .width('100%')
              .padding({ left: 4, right: 4, top: 6, bottom: 6 })
              .onClick(() => {
                this.interval = min;
                PreferencesStore.setRefreshIntervalMinutes(min);
                this.syncAutoTimer();
                this.toast(`刷新间隔已设为 ${min} 分钟`);
              })
            }, (min: number) => `${min}`)
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.divider') })

          this.sectionTitle('祈愿数据管理')
          if (this.gachaRows.length === 0) {
            Text('暂无祈愿归档（刷新或导入后生成）')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 6, bottom: 6 })
          } else {
            Column({ space: 8 }) {
              ForEach(this.gachaRows, (row: GachaArchiveRow) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(`UID ${row.uid}`)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                    Text(`${row.count} 条记录`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text('删除')
                    .fontSize(12)
                    .fontColor($r('app.color.danger'))
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(10)
                    .backgroundColor($r('app.color.card_background'))
                    .border({ width: 1, color: $r('app.color.divider') })
                    .onClick(() => {
                      this.confirmDeleteArchive(row);
                    })
                }
                .width('100%')
              }, (row: GachaArchiveRow) => `gr_${row.id}_${row.count}`)
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.divider') })
          }
          Row() {
            Column({ space: 2 }) {
              Text('清空全部祈愿数据')
                .fontSize(15)
                .fontColor($r('app.color.danger'))
              Text('删除所有 UID 的祈愿记录，不可恢复')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('清空')
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .border({ width: 1, color: $r('app.color.danger') })
              .onClick(() => {
                this.confirmClearAllGacha();
              })
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.divider') })

          this.sectionTitle('账号')
          this.rowItem('账号与数据', '多账号管理与角色绑定', () => {
            router.pushUrl({ url: 'pages/UserPage' });
          })
          if (this.isLoggedIn) {
            Row() {
              Text('退出登录')
                .fontSize(15)
                .fontColor($r('app.color.danger'))
              Blank()
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.divider') })
            .onClick(() => {
              UserService.getInstance().logout().then(() => {
                this.toast('已退出登录');
              });
            })
          }

          this.sectionTitle('关于')
          this.rowItem('胡桃工具箱（鸿蒙版）', '仅支持国服 · 本地数据存储', () => {
            this.toast('胡桃工具箱 Snap.Hutao.HarmonyOS');
          })
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)

      if (this.showUrlEdit) {
        Column() {
          Column({ space: 12 }) {
            Text('修改数据源地址')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text('填写托管 manifest 的地址（GitHub raw / jsDelivr 均可），保存后点击"立即更新"生效')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            TextInput({ placeholder: 'https://raw.githubusercontent.com/你的用户名/snap-hutao-data/main/manifest-hutao.json', text: this.urlInput })
              .fontSize(12)
              .height(40)
              .width('100%')
              .onChange((v: string) => {
                this.urlInput = v;
              })
            Row({ space: 10 }) {
              Button('取消')
                .fontSize(13)
                .height(34)
                .layoutWeight(1)
                .backgroundColor($r('app.color.card_background'))
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.showUrlEdit = false;
                })
              Button('保存')
                .fontSize(13)
                .height(34)
                .layoutWeight(1)
                .backgroundColor($r('app.color.app_primary'))
                .fontColor(Color.White)
                .onClick(() => {
                  this.applyDataUrl();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor($r('app.color.card_background'))
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showUrlEdit = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
  }
}
