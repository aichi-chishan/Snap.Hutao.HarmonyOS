/**
 * DailyNotePage.ets（Index 便笺 Tab 内嵌组件）
 * 工具栏提供刷新、验证、添加与通知设置。
 * 每个追踪角色一张状态卡；宽屏按 308vp 原生瀑布流排列，窄屏单列。
 * 卡片呈现任务、树脂、宝钱、派遣与刷新时间。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DailyNoteViewModel, NoteCardEntry } from '../viewmodel/DailyNoteViewModel';
import { DailyNote, Expedition } from '../model/DailyNote';
import { NotificationHelper } from '../data/local/NotificationHelper';
import { DailyNoteRefreshSummary, NotifyFlags } from '../service/DailyNoteService';
import { DailyNoteService } from '../service/DailyNoteService';
import { DailyNoteReminderService } from '../service/DailyNoteReminderService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { GeetestVerifyParams } from './GeetestVerifyPage';
import { DateUtil } from '../common/DateUtil';
import { NavIcon } from '../components/NavIcon';
import { MetaIcon } from '../components/MetaIcon';
import { PageBackdrop } from '../components/PageBackdrop';
import { PageToolbar } from '../components/PageToolbar';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, UiSurface } from '../common/UiSurface';

/** shimmer 行渲染数据（单实例传入 @Builder，保证动态渲染；进度条 Max/Value） */
class NoteRowData {
  category: string = 'ItemIcon';
  icon: string = '';
  main: string = '';
  sub: string = '';
  progress: number = 0;
  max: number = 1;
  showProgress: boolean = true;
}

/** 派遣条目渲染数据（shimmer 底衬行 + 头像 32 + 'X 时 Y 分'/'已完成'） */
class ExpRowData {
  avatar: string = '';
  /** 本地无图标时的远端回退 URL（接口 avatar_side_icon；哈希命名时用） */
  avatarUrl: string = '';
  text: string = '';
  done: boolean = false;
  passed: number = 0;
  total: number = 1;
}

@Component
export struct DailyNotePage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @StorageProp('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageProp('currentUserId') @Watch('onOwnerChanged') ownerId: number = 0;
  @State vm: DailyNoteViewModel = new DailyNoteViewModel();
  @StorageLink('dailyNoteVersion') @Watch('onNoteVersion') noteVersion: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('onLocaleChanged') localeVersion: number = 0;
  @State allowNotify: boolean = false;
  /** 顶栏「通知设置」半窗：自动刷新开关 + 间隔 */
  @State showNoteSettings: boolean = false;
  /** 每卡「通知设置」半窗：每 UID 开关位 + 树脂/宝钱阈值 */
  @State showUidSettings: boolean = false;
  @State noteAutoRefresh: boolean = PreferencesStore.getAutoRefreshEnabled();
  @State systemReminders: boolean = DailyNoteReminderService.isEnabled();
  @StorageLink('dailyNoteReminderError') reminderError: string = '';
  @State webhookInput: string = DailyNoteService.webhookUrl();
  @State noteInterval: number = PreferencesStore.getRefreshIntervalMinutes();
  /** 最近一次后台（自动）刷新失败原因：风控拦截/网络异常时给用户可见反馈 */
  @StorageLink('dailyNoteLastError') lastNoteError: string = '';
  /** 内容区 >=840 使用独立卡轨；卡内保留两列派遣所需宽度。 */
  @State isWide: boolean = false;
  /** 派遣 Grid 自身宽度（onAreaChange 读取；列数按 MinItemWidth=140 推导，不读屏幕宽） */
  @State expGridW: number = 0;

  /** 顶栏按钮槽位（@Builder 参数只放常量槽位，文案/状态渲染期读 vm） */
  private static readonly BAR_REFRESH: number = 0;
  private static readonly BAR_VERIFY: number = 1;
  private static readonly BAR_ADD: number = 2;
  private static readonly BAR_NOTIFY: number = 3;
  /** 派遣网格：对齐 Windows UniformPanel MinItemWidth=140 / Spacing=6 */
  private static readonly EXP_MIN_ITEM: number = 140;
  private static readonly EXP_GAP: number = 6;
  /** 两列派遣需 286vp，另计两侧 padding 8、边框 1，留少量取整余量。 */
  private static readonly CARD_WIDTH: number = 308;
  private static readonly CARD_PADDING: number = 8;
  private static readonly ROW_RADIUS: number = 4;
  /** 参变仪进度条上限：7 天秒数（对齐 Windows Maximum=604800） */
  private static readonly TRANSFORMER_MAX: number = 604800;
  private ownerTimer: number = -1;

  onOwnerChanged(): void {
    clearTimeout(this.ownerTimer);
    this.ownerTimer = setTimeout((): void => { this.vm.reloadFromCache(this.currentUid); }, 0);
  }

  aboutToDisappear(): void { clearTimeout(this.ownerTimer); }

  onLocaleChanged(): void {
    this.vm.loadTracked().catch((error: Error): void => { this.toast(error.message); });
  }

  /** 服务层刷新成功（自动刷新定时器 / 桌面卡片手动刷新）→ 重读本地缓存，界面数值即时同步 */
  onNoteVersion(): void {
    if (!this.isLoggedIn || this.currentUid.length === 0) {
      return;
    }
    this.vm.reloadFromCache(this.currentUid).then(() => {
    });
  }

  private async toggleSystemReminders(enabled: boolean): Promise<void> {
    try {
      if (enabled && !NotificationHelper.isEnabled()) {
        const host = this.getUIContext().getHostContext();
        if (host === undefined || !await NotificationHelper.requestPermission(host as common.UIAbilityContext)) {
          this.systemReminders = false;
          this.toast('未获得通知授权，代理提醒未启用');
          return;
        }
      }
      await DailyNoteReminderService.setEnabled(enabled);
      this.systemReminders = enabled;
      if (enabled) {
        const refreshed: boolean = await this.vm.refresh(this.currentUid);
        if (!refreshed) {
          this.toast(this.vm.message.length > 0 ? this.vm.message : '便笺刷新失败，尚未安排新的提醒');
        } else {
          this.toast(this.reminderError.length > 0 ? this.reminderError : '代理提醒已启用，将按最新便笺安排');
        }
      }
    } catch (e) {
      this.systemReminders = DailyNoteReminderService.isEnabled();
      this.reminderError = (e as Error).message;
      this.toast(this.reminderError);
    }
  }

  aboutToAppear(): void {
    this.vm.syncAutoRefresh();
    this.allowNotify = NotificationHelper.isEnabled();
    this.vm.load(this.currentUid).then(() => {
      // 无缓存且已登录 → 自动拉一次
      if (this.isLoggedIn && this.currentUid.length > 0 && this.vm.note === undefined &&
        this.currentEntries().some((entry: NoteCardEntry): boolean => entry.userId === this.ownerId && entry.uid === this.currentUid)) {
        this.vm.refresh(this.currentUid).then((ok: boolean) => {
          if (!ok) {
            this.toast(this.vm.message);
          }
        });
      }
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1800 });
  }

  /** 跳转极验人机验证页，返回后轮询 challenge 并自动重放（顶栏「验证」入口） */
  goGeetest(): void {
    const params: GeetestVerifyParams = {
      gt: this.vm.geetestGt,
      challenge: this.vm.geetestChallenge,
    };
    // 清掉旧的 challenge，避免误用
    AppStorage.setOrCreate<string>('dailyNoteChallenge', '');
    router.pushUrl({ url: 'pages/GeetestVerifyPage', params: params });
    // 轮询：验证页完成后写入 dailyNoteChallenge 并返回，此处检测到即重放
    const poll = setInterval(() => {
      const challenge: string = AppStorage.get<string>('dailyNoteChallenge') ?? '';
      if (challenge.length > 0) {
        clearInterval(poll);
        this.vm.refresh(this.currentUid, challenge).then((ok: boolean) => {
          this.toast(ok ? '验证通过，已刷新' : this.vm.message);
        });
      }
    }, 800);
    // 安全上限：2 分钟内未完成则停止轮询
    setTimeout(() => {
      clearInterval(poll);
    }, 120000);
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'DailyNote', iconSize: 60 })
      Text('需登录后查看实时便笺')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('登录并绑定 UID 后，可查看树脂/派遣/洞天宝钱等实时数据')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Button('去登录', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 顶部 CommandBar 操作卡 ====================

  private barLabel(slot: number): string {
    if (slot === DailyNotePage.BAR_REFRESH) {
      return this.vm.isRefreshing || this.vm.trackedBusy ? '刷新中...' : '立即刷新';
    }
    if (slot === DailyNotePage.BAR_VERIFY) {
      return '验证当前用户与角色';
    }
    if (slot === DailyNotePage.BAR_ADD) {
      return '添加实时便笺';
    }
    return '通知设置';
  }

  /** 顶栏图标：返回 NavIcon 可识别的系统符号名（替代 emoji，随主题色且不随字体漂移） */
  private barGlyph(slot: number): string {
    if (slot === DailyNotePage.BAR_VERIFY) {
      return 'Check';
    }
    if (slot === DailyNotePage.BAR_ADD) {
      return 'Setting';
    }
    return 'Setting';
  }

  private onBarAction(slot: number): void {
    if (slot === DailyNotePage.BAR_REFRESH) {
      this.vm.refreshTracked().then((summary: DailyNoteRefreshSummary): void => {
        if (summary.total === 0) {
          this.toast(summary.firstError || '暂无已追踪角色，请先添加实时便笺');
        } else {
          const progress: string = `已刷新 ${summary.succeeded}/${summary.total} 个角色`;
          this.toast(summary.firstError.length > 0 ? `${progress}，${summary.firstError}` : progress);
        }
      }).catch((error: Error): void => { this.toast(error.message); });
      return;
    }
    if (slot === DailyNotePage.BAR_VERIFY) {
      if (this.isLoggedIn && this.currentUid.length > 0) {
        router.pushUrl({ url: 'pages/OfficialWebPage', params: { kind: 'daily-note' } }).catch(() => {
          this.toast('无法打开米游社验证页面');
        });
      } else { this.toast('请先登录并选择国服角色'); }
      return;
    }
    if (slot === DailyNotePage.BAR_ADD) {
      this.vm.trackCurrent().then((added: boolean) => {
        this.toast(added ? (this.vm.message.length > 0 ? `已添加便笺，${this.vm.message}` : '已追踪当前 UID') : this.vm.message);
      }).catch((error: Error): void => { this.toast(error.message); });
      return;
    }
    // 通知设置：Windows 顶栏 Flyout（自动刷新开关 + 间隔）
    this.noteAutoRefresh = PreferencesStore.getAutoRefreshEnabled();
    this.noteInterval = PreferencesStore.getRefreshIntervalMinutes();
    this.webhookInput = DailyNoteService.webhookUrl();
    this.showNoteSettings = true;
  }

  @Builder
  barButton(slot: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 6 }) {
        if (slot === DailyNotePage.BAR_REFRESH) {
          Text('⟳').fontSize(20).fontColor($r('app.color.text_secondary'))
        } else if (slot === DailyNotePage.BAR_ADD) {
          Text('+').fontSize(22).fontColor($r('app.color.text_secondary'))
        } else {
          NavIcon({ name: this.barGlyph(slot), iconSize: 15, symbolColor: $r('app.color.text_secondary') })
        }
        if (this.isWide || slot === DailyNotePage.BAR_REFRESH) {
          Text(this.barLabel(slot))
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .height(44)
    .constraintSize({ minWidth: 44 })
    .padding({ left: 10, right: 10 })
    .backgroundColor(Color.Transparent)
    .borderRadius(6)
    .enabled((slot !== DailyNotePage.BAR_REFRESH && slot !== DailyNotePage.BAR_ADD) || (!this.vm.isRefreshing && !this.vm.trackedBusy))
    .accessibilityText(slot === DailyNotePage.BAR_VERIFY ? '验证当前用户与角色'
      : slot === DailyNotePage.BAR_REFRESH ? '刷新所有追踪角色的实时便笺' : this.barLabel(slot))
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.onBarAction(slot);
    })
  }

  /** Windows CommandBar 的操作集中在右侧。 */
  @Builder
  toolbarActions() {
    Row({ space: 4 }) {
      this.barButton(DailyNotePage.BAR_REFRESH)
      this.barButton(DailyNotePage.BAR_VERIFY)
      this.barButton(DailyNotePage.BAR_ADD)
      this.barButton(DailyNotePage.BAR_NOTIFY)
    }
  }

  @Builder
  errorBanner() {
    Row({ space: 6 }) {
      Text('⚠')
        .fontSize(12)
        .fontColor($r('app.color.danger'))
      Text(this.lastNoteError)
        .fontSize(11)
        .fontColor($r('app.color.danger'))
        .layoutWeight(1)
        .maxLines(2)
      Text('立即刷新')
        .fontSize(11)
        .fontColor($r('app.color.app_primary_text'))
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.vm.refresh(this.currentUid).then((ok: boolean) => {
            this.toast(ok ? '已刷新' : this.vm.message);
          });
        })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(8)
    .backgroundColor($r('app.color.danger_bg'))
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  loadingBlock() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color($r('app.color.app_primary'))
      Text(this.vm.message.length > 0 ? this.vm.message : '加载中...')
        .fontSize(13)
        .fontColor(this.vm.message.length > 0 ? $r('app.color.danger') : $r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      if (this.vm.needGeetest) {
        Button('去完成人机验证', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .fontSize(14)
          .height(44)
          .onClick(() => {
            this.goGeetest();
          })
        Text('验证完成后返回本页会自动重试拉取')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 32, bottom: 24 })
  }

  // ==================== 每 UID 追踪卡 ====================

  private makeRow(category: string, icon: string, main: string, sub: string,
    progress: number, max: number): NoteRowData {
    const row: NoteRowData = new NoteRowData();
    row.category = category;
    row.icon = icon;
    row.main = main;
    row.sub = sub;
    row.max = max > 0 ? max : 1;
    row.progress = Math.max(0, Math.min(progress, row.max));
    return row;
  }

  /** 6 行 shimmer 行数据（对齐 Windows DailyNoteEntryTemplate：魔神任务/树脂/宝钱/每日委托/周本折扣/参变仪） */
  private cardRows(entry: NoteCardEntry): NoteRowData[] {
    const rows: NoteRowData[] = [];
    const n: DailyNote | undefined = entry.note;
    if (n === undefined) {
      const empty: NoteRowData = this.makeRow('ItemIcon', '', '尚未刷新', '点顶栏「立即刷新」拉取数据', 0, 1);
      empty.showProgress = false;
      rows.push(empty);
      return rows;
    }
    // 1 魔神任务（rawfile icons/Mark 无 Main_Start/Proce → MetaIcon 占位/云端兜底）
    const archon: NoteRowData = this.makeRow('Mark',
      n.archonQuestFinished() ? 'UI_MarkQuest_Main_Proce' : 'UI_MarkQuest_Main_Start',
      n.archonQuestMainText(), entry.archonChapterText || n.archonQuestSubText(),
      entry.archonProgress, entry.archonTotal);
    archon.showProgress = entry.archonProgress >= 0 && entry.archonTotal > 0;
    rows.push(archon);
    // 2 树脂
    rows.push(this.makeRow('ItemIcon', 'UI_ItemIcon_106',
      n.formattedResin(), n.resinRecoveryTargetText(), n.currentResin, n.maxResin));
    // 3 洞天宝钱
    rows.push(this.makeRow('ItemIcon', 'UI_ItemIcon_204',
      n.formattedHomeCoin(), n.homeCoinRecoveryTargetText(), n.currentHomeCoin, n.maxHomeCoin));
    // 4 每日委托
    rows.push(this.makeRow('Mark',
      n.isExtraTaskRewardReceived ? 'UI_MarkQuest_Events_Proce' : 'UI_MarkQuest_Events_Start',
      n.formattedTask(), n.extraTaskRewardDescription(), n.finishedTaskNum, n.totalTaskNum));
    // 5 周本折扣（方向对齐 Windows：已消耗/上限）
    rows.push(this.makeRow('Mark', 'UI_MarkTower',
      n.formattedResinDiscount(), '本周已消耗减半次数', n.resinDiscountUsedNum(), n.resinDiscountNumLimit));
    // 6 参量质变仪
    rows.push(this.makeRow('ItemIcon', 'UI_ItemIcon_220021',
      n.transformerMainText(), n.transformerSubText(), n.transformerElapsedSecond(),
      DailyNotePage.TRANSFORMER_MAX));
    return rows;
  }

  /** shimmer 行：高 48、底衬 tint + 1px 描边 + 圆角 4，进度条铺满行底（透明度 0.2），图标 32×32 */
  @Builder
  noteRow(row: NoteRowData) {
    Stack({ alignContent: Alignment.Center }) {
      if (row.showProgress) {
        Progress({ value: row.progress, total: row.max, type: ProgressType.Linear })
          .width('100%')
          .height(48)
          .style({ strokeWidth: 48, strokeRadius: DailyNotePage.ROW_RADIUS })
          .color($r('app.color.app_primary'))
          .backgroundColor(Color.Transparent)
          .opacity(0.2)
      }
      Row({ space: 8 }) {
        MetaIcon({ category: row.category, name: row.icon, iconSize: 32, remoteFallback: true })
        Column({ space: 2 }) {
          Text(row.main)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(row.sub)
            .fontSize(12)
            .opacity(0.6)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(48)
    .borderRadius(DailyNotePage.ROW_RADIUS)
    .clip(true)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  private makeExpRow(exp: Expedition): ExpRowData {
    const item: ExpRowData = new ExpRowData();
    item.avatar = exp.iconName();
    item.avatarUrl = exp.iconUrl();
    item.done = exp.isFinished();
    item.text = exp.finishText();
    item.total = exp.totalSecond();
    item.passed = exp.passedSecond();
    return item;
  }

  /** 派遣列数（对齐 Windows UniformPanel.MeasureOverride：floor((W+gap)/(minItem+gap))） */
  private expTemplate(): string {
    const cols: number = Math.max(1, Math.floor((this.expGridW + DailyNotePage.EXP_GAP)
      / (DailyNotePage.EXP_MIN_ITEM + DailyNotePage.EXP_GAP)));
    return Array(cols).fill('1fr').join(' ');
  }

  /** 派遣条目：shimmer 底衬行（进度 Max=TotalTime / Value=PassedTime 20% 透明度）+ 头像 32 + 剩余文本 */
  @Builder
  expRow(item: ExpRowData) {
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: item.passed, total: item.total, type: ProgressType.Linear })
        .width('100%')
        .height(40)
        .style({ strokeWidth: 40, strokeRadius: DailyNotePage.ROW_RADIUS })
        .color($r('app.color.app_primary'))
        .backgroundColor(Color.Transparent)
        .opacity(0.2)
      Row({ space: 12 }) {
        if (item.avatar.length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: item.avatar, iconSize: 32, remoteFallback: true })
        } else if (item.avatarUrl.length > 0) {
          // 接口返回哈希命名（本地/CDN 无此图标）：直接用接口 URL，加载失败落中性占位
          MetaIcon({ category: 'AvatarIcon', name: item.avatarUrl, iconSize: 32 })
        } else {
          Stack({ alignContent: Alignment.Center }) {
            NavIcon({ name: 'Airplane', iconSize: 15, symbolColor: $r('app.color.text_secondary') })
          }
          .width(32)
          .height(32)
        }
        Text(item.text)
          .fontSize(14)
          .fontColor(item.done ? $r('app.color.success') : $r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(40)
    .borderRadius(DailyNotePage.ROW_RADIUS)
    .clip(true)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  /** 派遣探索区：无头行/无「全部领取」（对齐 Windows），Grid 双列/窄卡单列 */
  @Builder
  expSection(entry: NoteCardEntry) {
    if (entry.note !== undefined && entry.note.expeditions.length > 0) {
      Grid() {
        ForEach(entry.note.expeditions, (exp: Expedition) => {
          GridItem() {
            this.expRow(this.makeExpRow(exp))
          }
        }, (exp: Expedition, idx: number) => `exp_${idx}_${exp.status}_${exp.remainedTime}`)
      }
      .columnsTemplate(this.expTemplate())
      .columnsGap(DailyNotePage.EXP_GAP)
      .rowsGap(DailyNotePage.EXP_GAP)
      .width('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.expGridW = Number(newValue.width);
      })
    }
  }

  private cardHeadText(entry: NoteCardEntry): string {
    const parts: string[] = [entry.nickname.length > 0 ? entry.nickname : `UID ${entry.uid}`];
    if (entry.region === 'cn_gf01') { parts.push('天空岛'); }
    else if (entry.region === 'cn_qd01') { parts.push('世界树'); }
    if (entry.level > 0) { parts.push(`Lv.${entry.level}`); }
    return parts.join(' | ');
  }

  /** 卡底刷新时间（Windows RefreshTimeFormatted 绝对时间 + UX11 估算/过期标注可区分） */
  private refreshTimeText(entry: NoteCardEntry): string {
    if (entry.note === undefined || entry.note.refreshTime <= 0) {
      return '尚未刷新';
    }
    const d: Date = new Date(entry.note.refreshTime);
    const t: string = `${DateUtil.pad2(d.getMonth() + 1)}.${DateUtil.pad2(d.getDate())} ` +
      `${DateUtil.pad2(d.getHours())}:${DateUtil.pad2(d.getMinutes())}:${DateUtil.pad2(d.getSeconds())}`;
    return DateUtil.isNoteStale(entry.note.refreshTime)
      ? `已过期 · 刷新于 ${t}`
      : `刷新于 ${t}（估算）`;
  }

  /** 卡底刷新时间颜色（过期醒目，其余次要文本） */
  private refreshTimeStale(entry: NoteCardEntry): boolean {
    return entry.note !== undefined && DateUtil.isNoteStale(entry.note.refreshTime);
  }

  private onCardRemove(entry: NoteCardEntry): void {
    this.vm.untrack(entry.userId, entry.uid).then(() => {
      this.toast('已移除追踪');
    });
  }

  private onCardNotify(entry: NoteCardEntry): void {
    this.vm.openUidSettings(entry.userId, entry.uid).then((ready: boolean): void => {
      if (ready) { this.showUidSettings = true; }
      else { this.toast('请先刷新该角色的便笺'); }
    });
  }

  /** 每 UID 追踪卡（对齐 Windows DailyNoteEntryTemplate：卡体 padding 8、区块间距 8、行间距 6） */
  @Builder
  noteCard(entry: NoteCardEntry) {
    Column({ space: 8 }) {
      // 卡头行 MinHeight 40：左 = 角色昵称/区服/等级（14fp）；右 = 40×40 透明按钮
      // （Windows 的「启动游戏」属注入/进程链功能，未移植，按规格省略）
      Row() {
        Text(this.cardHeadText(entry))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (entry.tracked) {
          Stack({ alignContent: Alignment.Center }) {
            NavIcon({ name: 'Close', iconSize: 16, symbolColor: $r('app.color.text_secondary') })
          }
          .width(40)
          .height(40)
          .hoverEffect(HoverEffect.Highlight)
          .accessibilityText('移除该便笺追踪')
          .accessibilityLevel('yes')
          .onClick(() => { this.onCardRemove(entry); })
        }
        Stack({ alignContent: Alignment.Center }) {
          NavIcon({ name: 'Setting', iconSize: 17, symbolColor: $r('app.color.text_secondary') })
        }
        .width(40)
        .height(40)
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('该角色的通知设置')
        .accessibilityLevel('yes')
        .onClick(() => {
          this.onCardNotify(entry);
        })
      }
      .width('100%')
      .height(40)
      .alignItems(VerticalAlign.Center)

      // 6 行 shimmer 行（键值含变化字段，刷新后整卡重建）
      Column({ space: 6 }) {
        ForEach(this.cardRows(entry), (row: NoteRowData) => {
          this.noteRow(row)
        }, (row: NoteRowData, idx: number) => `row_${idx}_${row.main}_${row.sub}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.expSection(entry)

      Text(this.refreshTimeText(entry))
        .fontSize(12)
        .opacity(0.7)
        .fontColor(this.refreshTimeStale(entry) ? $r('app.color.danger') : $r('app.color.text_primary'))
    }
    .width('100%')
    .padding(DailyNotePage.CARD_PADDING)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 8, offsetY: 4, color: $r('app.color.nav_scrim') })
    .alignItems(HorizontalAlign.Start)
  }

  private currentEntries(): NoteCardEntry[] {
    return this.vm.buildCardEntries();
  }

  private cardKey(entry: NoteCardEntry): string {
    const rt: number = entry.note !== undefined ? entry.note.refreshTime : 0;
    return `card_${entry.userId}_${entry.uid}_${entry.nickname}_${entry.region}_${entry.level}_` +
      `${entry.isCurrent ? 1 : 0}_${entry.tracked ? 1 : 0}_${rt}_` +
      `${entry.archonProgress}_${entry.archonTotal}_${entry.archonChapterText}`;
  }

  /** 宽屏卡宽包含派遣双列及卡内留白；窄屏继续填满内容区。 */
  @Builder
  noteWaterfall() {
    WaterFlow() {
      ForEach(this.currentEntries(), (entry: NoteCardEntry) => {
        FlowItem() {
          this.noteCard(entry)
        }
        .width('100%')
      }, (entry: NoteCardEntry) => this.cardKey(entry))
    }
    .columnsTemplate(this.isWide ? `repeat(auto-fill,${DailyNotePage.CARD_WIDTH}vp)` : '1fr')
    .columnsGap(12)
    .rowsGap(12)
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .scrollBar(BarState.Auto)
  }

  // ==================== 半窗设置 ====================

  @Builder
  flagToggle(label: string, flag: number) {
    Row({ space: 8 }) {
      Text(this.vm.settingsNotifyFlags & flag ? '☑' : '☐')
        .fontSize(16)
        .fontColor(this.vm.settingsNotifyFlags & flag ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.vm.toggleUidFlag(flag).catch((error: Error): void => { this.toast(error.message); });
        })
    }
  }

  private thresholdMax(resin: boolean): number { return resin ? this.vm.settingsResinMax : this.vm.settingsHomeMax; }

  private thresholdValue(resin: boolean): number { return resin ? this.vm.settingsResinThreshold : this.vm.settingsHomeThreshold; }

  @Builder
  thresholdSlider(resin: boolean) {
    Column({ space: 4 }) {
      Row() {
        Text(resin ? '树脂阈值' : '宝钱阈值').fontSize(13).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(`${this.thresholdValue(resin)} / ${this.thresholdMax(resin)}`).fontSize(13).fontColor($r('app.color.text_primary'))
      }.width('100%')
      if (this.thresholdMax(resin) > 0) {
        Slider({ value: this.thresholdValue(resin), min: 0, max: this.thresholdMax(resin), step: 1 })
          .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .width('100%').showTips(true)
          .accessibilityText(resin ? '树脂提醒阈值' : '洞天宝钱提醒阈值')
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              const saved: Promise<void> = resin ? this.vm.setUidResinThreshold(Math.round(value))
                : this.vm.setUidHomeThreshold(Math.round(value));
              saved.catch((error: Error): void => { this.toast(error.message); });
            }
          })
      }
    }.width('100%')
  }

  /** 每卡「通知设置」半窗：每 UID 通知开关位 + 树脂/宝钱阈值（沿用原每 UID 设置 UI） */
  @Builder
  uidSettingsSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('通知对象')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(`UID ${this.vm.settingsUid}`)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text('系统通知')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (!this.allowNotify) {
          Button('授权通知', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .fontSize(12)
            .height(44)
            .onClick(() => {
              const host = this.getUIContext().getHostContext();
              if (host === undefined) {
                return;
              }
              NotificationHelper.requestPermission(host as common.UIAbilityContext).then((ok: boolean) => {
                this.allowNotify = ok;
                this.toast(ok ? '通知已授权' : '授权失败，可到系统设置开启');
              });
            })
        } else {
          Text('已授权')
            .fontSize(12)
            .fontColor($r('app.color.success'))
        }
      }
      .width('100%')

      Row({ space: 10 }) {
        Column({ space: 6 }) {
          this.flagToggle('树脂', NotifyFlags.RESIN)
          this.flagToggle('派遣', NotifyFlags.EXPEDITION)
          this.flagToggle('每日', NotifyFlags.DAILY_TASK)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Column({ space: 6 }) {
          this.flagToggle('参变仪', NotifyFlags.TRANSFORMER)
          this.flagToggle('洞天宝钱', NotifyFlags.HOME_COIN)
          Text(' ')
            .fontSize(14)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      this.thresholdSlider(true)
      this.thresholdSlider(false)

      Text('树脂/宝钱达到阈值或派遣/每日委托完成时发送系统通知（随自动刷新检测，需先授权通知）。')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  /** 顶栏「通知设置」半窗：自动刷新开关 + 间隔（沿用现有间隔枚举，见汇报） */
  @Builder
  noteSettingsSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('自动刷新')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.noteAutoRefresh }).attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .onChange((isOn: boolean) => {
            this.noteAutoRefresh = isOn;
            PreferencesStore.setAutoRefreshEnabled(isOn);
            if (isOn) {
              DailyNoteService.getInstance().startAutoRefresh(this.noteInterval);
            } else {
              DailyNoteService.getInstance().stopAutoRefresh();
            }
          })
      }
      .width('100%')

      Column({ space: 4 }) {
        if (!PreferencesStore.DAILY_NOTE_REFRESH_INTERVALS.includes(this.noteInterval)) {
          Text(`当前间隔 ${this.noteInterval} 分钟`).fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        ForEach(PreferencesStore.DAILY_NOTE_REFRESH_INTERVALS, (min: number) => {
          Row({ space: 8 }) {
            Text(this.noteInterval === min ? '◉' : '○')
              .fontSize(14)
              .fontColor(this.noteInterval === min ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
            Text(`每 ${min} 分钟自动刷新`)
              .fontSize(14)
              .fontColor(this.noteInterval === min ? $r('app.color.app_primary') : $r('app.color.text_primary'))
            Blank()
            if (this.noteInterval === min) {
              Text('✓')
                .fontSize(13)
                .fontColor($r('app.color.app_primary_text'))
            }
          }
          .width('100%')
          .padding({ left: 6, right: 6, top: 9, bottom: 9 })
          .borderRadius(10)
          .backgroundColor(this.noteInterval === min ? $r('app.color.app_primary_bg') : $r('app.color.page_background'))
          .enabled(this.noteAutoRefresh)
          .opacity(this.noteAutoRefresh ? 1 : 0.45)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.noteInterval = min;
            PreferencesStore.setRefreshIntervalMinutes(min);
            if (this.noteAutoRefresh) {
              DailyNoteService.getInstance().startAutoRefresh(min);
            }
          })
        }, (min: number) => `${min}`)
      }
      .width('100%')

      Row() {
        Text('系统代理提醒').fontSize(14).fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.systemReminders }).attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .onChange((enabled: boolean) => { this.toggleSystemReminders(enabled); })
      }.width('100%')
      Text('按上次便笺估算树脂、宝钱、派遣和参量质变仪的到期时间。退出应用后由系统提醒；游戏内消耗后需刷新校正。')
        .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.reminderError.length > 0) {
        Text(this.reminderError).fontSize(12).fontColor($r('app.color.notice_on')).width('100%')
      }

      Text('便笺 Webhook')
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.webhookInput, placeholder: 'https://example.com/daily-note' })
        .onChange((value: string) => { this.webhookInput = value; })
      Text('配置后，每次刷新会发送 UID 和便笺数据。留空关闭。')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button('保存 Webhook', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
        .onClick(() => {
          try {
            DailyNoteService.setWebhookUrl(this.webhookInput);
            this.toast(this.webhookInput.trim().length > 0 ? 'Webhook 已保存' : 'Webhook 已关闭');
          } catch (e) {
            this.toast((e as Error).message);
          }
        })

      Text('自动刷新在应用运行时获取服务器数据；桌面卡片刷新由系统调度。系统代理提醒按最近快照执行，无需保持应用运行。')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  build() {
    Stack() {
      // 壁纸衬底：本页恒为 Index 壳层内嵌（壳层已铺壁纸），PageBackdrop 渲染为空仅透传
      PageBackdrop({ embedMode: true })
      Column() {
        if (!this.isLoggedIn) {
          this.loginGuide()
        } else if (this.currentUid.length === 0) {
          Column({ space: 14 }) {
            NavIcon({ name: 'Passport', iconSize: 60 })
            Text('请先选择默认 UID')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Button('去「账号与数据」选择', { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/UserPage' });
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Row() {
            PageToolbar({ trailing: (): void => this.toolbarActions() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })

          // 内容区：错误横幅 + 加载态 + 追踪卡瀑布流（宽屏断点读内容区自身宽度 >=840）
          Column() {
            if (this.lastNoteError.length > 0) {
              this.errorBanner()
            }
            if (!this.vm.loaded || (this.vm.isRefreshing && this.currentEntries().length === 0)) {
              this.loadingBlock()
            }
            if (this.currentEntries().length > 0) {
              this.noteWaterfall()
            } else if (this.vm.loaded && !this.vm.isRefreshing) {
              Text('点顶部「添加实时便笺」把当前 UID 加入追踪')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 32 })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.isWide = (newValue.width as number) >= 840;
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    // Windows 风格：设置均以半屏小窗呈现（不覆盖全屏）
    .bindSheet($$this.showNoteSettings, this.noteSettingsSheet(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
      title: { title: '刷新与通知' },
      showClose: true,
      dragBar: true,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.Regular,
      backgroundColor: $r('app.color.sheet_material_tint'),
    })
    .bindSheet($$this.showUidSettings, this.uidSettingsSheet(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
      title: { title: '通知设置' },
      showClose: true,
      dragBar: true,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.Regular,
      backgroundColor: $r('app.color.sheet_material_tint'),
    })
  }
}
