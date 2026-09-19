/**
 * DailyNotePage.ets（Index 便笺 Tab 内嵌组件）
 * 实时便笺：对齐 Windows DailyNotePage ——
 * 顶部 CommandBar 操作卡（立即刷新/验证/添加实时便笺/通知设置）+
 * 每 UID 一张追踪卡瀑布流（宽屏内容区 >=840 双列 / 窄屏单列，间距 12）。
 * 卡内 = 卡头（昵称 UID + 移除/通知设置 40×40 透明按钮）+ 6 行 shimmer 行
 * （高 48、底衬 card_inner_tint + 1px card_stroke 描边 + 圆角 4，进度条铺满行底
 * app_primary 透明度 0.2，图标 32×32 MetaIcon）+ 派遣网格（MinItemWidth=140 间距 6）+ 卡底刷新时间。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DailyNoteViewModel, NoteCardEntry } from '../viewmodel/DailyNoteViewModel';
import { DailyNote, Expedition } from '../model/DailyNote';
import { NotificationHelper } from '../data/local/NotificationHelper';
import { NotifyFlags } from '../service/DailyNoteService';
import { DailyNoteService } from '../service/DailyNoteService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { GeetestVerifyParams } from './GeetestVerifyPage';
import { DateUtil } from '../common/DateUtil';
import { NavIcon } from '../components/NavIcon';
import { MetaIcon } from '../components/MetaIcon';
import { PageBackdrop } from '../components/PageBackdrop';

/** shimmer 行渲染数据（单实例传入 @Builder，保证动态渲染；进度条 Max/Value） */
class NoteRowData {
  category: string = 'ItemIcon';
  icon: string = '';
  main: string = '';
  sub: string = '';
  progress: number = 0;
  max: number = 1;
}

/** 派遣条目渲染数据（shimmer 底衬行 + 头像 32 + 'X 时 Y 分'/'已完成'） */
class ExpRowData {
  avatar: string = '';
  text: string = '';
  done: boolean = false;
  passed: number = 0;
  total: number = 1;
}

@Component
export struct DailyNotePage {
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @StorageLink('currentUid') currentUid: string = '';
  @State vm: DailyNoteViewModel = new DailyNoteViewModel();
  @StorageLink('dailyNoteVersion') @Watch('onNoteVersion') noteVersion: number = 0;
  @State allowNotify: boolean = false;
  /** 顶栏「通知设置」半窗：自动刷新开关 + 间隔 */
  @State showNoteSettings: boolean = false;
  /** 每卡「通知设置」半窗：每 UID 开关位 + 树脂/宝钱阈值 */
  @State showUidSettings: boolean = false;
  @State noteAutoRefresh: boolean = PreferencesStore.getAutoRefreshEnabled();
  @State noteInterval: number = PreferencesStore.getRefreshIntervalMinutes();
  /** 最近一次后台（自动）刷新失败原因：风控拦截/网络异常时给用户可见反馈 */
  @StorageLink('dailyNoteLastError') lastNoteError: string = '';
  /** 宽屏（内容区宽 >=840）：追踪卡双列瀑布流（对齐 Windows UniformStaggeredPanel MinItemWidth=300） */
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
  /** 参变仪进度条上限：7 天秒数（对齐 Windows Maximum=604800） */
  private static readonly TRANSFORMER_MAX: number = 604800;

  /** 服务层刷新成功（自动刷新定时器 / 桌面卡片手动刷新）→ 重读本地缓存，界面数值即时同步 */
  onNoteVersion(): void {
    if (!this.isLoggedIn || this.currentUid.length === 0) {
      return;
    }
    this.vm.reloadFromCache(this.currentUid).then(() => {
    });
  }

  aboutToAppear(): void {
    this.vm.syncAutoRefresh();
    this.allowNotify = NotificationHelper.isEnabled();
    this.vm.load(this.currentUid).then(() => {
      // 无缓存且已登录 → 自动拉一次
      if (this.isLoggedIn && this.currentUid.length > 0 && this.vm.note === undefined) {
        this.vm.refresh(this.currentUid).then((ok: boolean) => {
          if (!ok) {
            this.toast(this.vm.message);
          }
        });
      }
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
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
      Button('去登录')
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
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
      return this.vm.isRefreshing ? '刷新中...' : '立即刷新';
    }
    if (slot === DailyNotePage.BAR_VERIFY) {
      return '验证';
    }
    if (slot === DailyNotePage.BAR_ADD) {
      return '添加实时便笺';
    }
    return '通知设置';
  }

  private barGlyph(slot: number): string {
    if (slot === DailyNotePage.BAR_VERIFY) {
      return '✓';
    }
    if (slot === DailyNotePage.BAR_ADD) {
      return '＋';
    }
    return '⚙';
  }

  private onBarAction(slot: number): void {
    if (slot === DailyNotePage.BAR_REFRESH) {
      this.vm.refresh(this.currentUid).then((ok: boolean) => {
        this.toast(ok ? '已刷新' : this.vm.message);
      });
      return;
    }
    if (slot === DailyNotePage.BAR_VERIFY) {
      this.goGeetest();
      return;
    }
    if (slot === DailyNotePage.BAR_ADD) {
      this.vm.trackCurrent().then((added: boolean) => {
        this.toast(added ? '已追踪当前 UID' : '当前 UID 已在追踪列表');
      });
      return;
    }
    // 通知设置：Windows 顶栏 Flyout（自动刷新开关 + 间隔）
    this.noteAutoRefresh = PreferencesStore.getAutoRefreshEnabled();
    this.noteInterval = PreferencesStore.getRefreshIntervalMinutes();
    this.showNoteSettings = true;
  }

  @Builder
  barButton(slot: number) {
    Row({ space: 6 }) {
      if (slot === DailyNotePage.BAR_REFRESH) {
        NavIcon({ name: 'DailyNote', iconSize: 16 })
      } else {
        Text(this.barGlyph(slot))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
      }
      Text(this.barLabel(slot))
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(34)
    .padding({ left: 10, right: 10 })
    .borderRadius(17)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.onBarAction(slot);
    })
  }

  /** 顶部整宽操作卡（对齐 Windows CommandBar 卡：margin 16、亚克力半透明、圆角、投影） */
  @Builder
  commandBarCard() {
    Row({ space: 4 }) {
      this.barButton(DailyNotePage.BAR_REFRESH)
      this.barButton(DailyNotePage.BAR_VERIFY)
      this.barButton(DailyNotePage.BAR_ADD)
      Blank()
      this.barButton(DailyNotePage.BAR_NOTIFY)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_acrylic_tint'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 8, offsetY: 4, color: $r('app.color.nav_scrim') })
    .margin({ left: 16, right: 16 })
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
        .fontColor($r('app.color.app_primary'))
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
        Button('去完成人机验证')
          .fontSize(14)
          .height(40)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
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
      rows.push(this.makeRow('ItemIcon', '', '尚未刷新', '点顶栏「立即刷新」拉取数据', 0, 1));
      return rows;
    }
    // 1 魔神任务（rawfile icons/Mark 无 Main_Start/Proce → MetaIcon 占位/云端兜底）
    rows.push(this.makeRow('Mark',
      n.archonQuestFinished() ? 'UI_MarkQuest_Main_Proce' : 'UI_MarkQuest_Main_Start',
      n.archonQuestMainText(), n.archonQuestSubText(),
      n.archonQuestFinishedCount(), n.archonQuestTotal()));
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
      Progress({ value: row.progress, total: row.max, type: ProgressType.Linear })
        .width('100%')
        .height(48)
        .style({ strokeWidth: 48 })
        .color($r('app.color.app_primary'))
        .backgroundColor(Color.Transparent)
        .opacity(0.2)
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
    .borderRadius(4)
    .clip(true)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  private makeExpRow(exp: Expedition): ExpRowData {
    const item: ExpRowData = new ExpRowData();
    item.avatar = exp.iconName();
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
        .style({ strokeWidth: 40 })
        .color($r('app.color.app_primary'))
        .backgroundColor(Color.Transparent)
        .opacity(0.2)
      Row({ space: 12 }) {
        if (item.avatar.length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: item.avatar, iconSize: 32, remoteFallback: true })
        } else {
          Text('✈')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
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
    .borderRadius(4)
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
    if (entry.isCurrent && entry.nickname.length > 0) {
      return `${entry.nickname}（UID ${entry.uid}）`;
    }
    return `UID ${entry.uid}`;
  }

  /** 卡底刷新时间（对齐 Windows RefreshTimeFormatted：'刷新于 MM.dd HH:mm:ss' / '尚未刷新'） */
  private refreshTimeText(entry: NoteCardEntry): string {
    if (entry.note === undefined || entry.note.refreshTime <= 0) {
      return '尚未刷新';
    }
    const d: Date = new Date(entry.note.refreshTime);
    const t: string = `${DateUtil.pad2(d.getMonth() + 1)}.${DateUtil.pad2(d.getDate())} ` +
      `${DateUtil.pad2(d.getHours())}:${DateUtil.pad2(d.getMinutes())}:${DateUtil.pad2(d.getSeconds())}`;
    return `刷新于 ${t}`;
  }

  private onCardRemove(entry: NoteCardEntry): void {
    this.vm.untrack(entry.uid).then(() => {
      this.toast('已移除追踪');
    });
  }

  private onCardNotify(entry: NoteCardEntry): void {
    this.vm.openUidSettings(entry.uid).then(() => {
      this.showUidSettings = true;
    });
  }

  /** 每 UID 追踪卡（对齐 Windows DailyNoteEntryTemplate：卡体 padding 8、区块间距 8、行间距 6） */
  @Builder
  noteCard(entry: NoteCardEntry) {
    Column({ space: 8 }) {
      // 卡头行 MinHeight 40：左 = 昵称+UID（14fp）；右 = 40×40 透明按钮
      // （Windows 的「启动游戏」属注入/进程链功能，未移植，按规格省略）
      Row() {
        Text(this.cardHeadText(entry))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('✕')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.onCardRemove(entry);
          })
        Text('⚙')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .hoverEffect(HoverEffect.Highlight)
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
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding(8)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_surface'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 8, offsetY: 4, color: $r('app.color.nav_scrim') })
    .alignItems(HorizontalAlign.Start)
  }

  private currentEntries(): NoteCardEntry[] {
    return this.vm.buildCardEntries();
  }

  private cardKey(entry: NoteCardEntry): string {
    const rt: number = entry.note !== undefined ? entry.note.refreshTime : 0;
    return `card_${entry.uid}_${entry.isCurrent ? 1 : 0}_${rt}`;
  }

  @Builder
  cardsColumn(entries: NoteCardEntry[]) {
    ForEach(entries, (entry: NoteCardEntry) => {
      this.noteCard(entry)
    }, (entry: NoteCardEntry) => this.cardKey(entry))
  }

  /** 瀑布流：宽屏双列各自独立 Scroll（近似 Windows UniformStaggeredPanel），窄屏单列 */
  @Builder
  noteWaterfall() {
    if (this.isWide) {
      Row({ space: 12 }) {
        Scroll() {
          Column({ space: 12 }) {
            this.cardsColumn(this.currentEntries()
              .filter((_: NoteCardEntry, i: number): boolean => i % 2 === 0))
          }
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)

        Scroll() {
          Column({ space: 12 }) {
            this.cardsColumn(this.currentEntries()
              .filter((_: NoteCardEntry, i: number): boolean => i % 2 === 1))
          }
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Top)
    } else {
      Scroll() {
        Column({ space: 12 }) {
          this.cardsColumn(this.currentEntries())
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
    }
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
          this.vm.toggleUidFlag(flag).then(() => {
          });
        })
    }
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
          Button('授权通知')
            .fontSize(12)
            .height(26)
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
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

      Row({ space: 8 }) {
        Text('树脂阈值')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        ForEach([80, 120, 160] as number[], (th: number) => {
          Text(`${th}`)
            .fontSize(13)
            .fontColor(this.vm.settingsResinThreshold === th ? Color.White : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(this.vm.settingsResinThreshold === th
              ? $r('app.color.app_primary') : $r('app.color.app_primary_bg'))
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.vm.setUidResinThreshold(th).then(() => {
              });
            })
        }, (th: number) => `usr_${th}`)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('宝钱阈值')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        ForEach([1200, 1800, 2400] as number[], (th: number) => {
          Text(`${th}`)
            .fontSize(13)
            .fontColor(this.vm.settingsHomeThreshold === th ? Color.White : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(this.vm.settingsHomeThreshold === th
              ? $r('app.color.app_primary') : $r('app.color.app_primary_bg'))
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.vm.setUidHomeThreshold(th).then(() => {
              });
            })
        }, (th: number) => `uhm_${th}`)
      }
      .width('100%')

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
        Toggle({ type: ToggleType.Switch, isOn: this.noteAutoRefresh })
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
        ForEach([5, 10, 15, 30, 60] as number[], (min: number) => {
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
                .fontColor($r('app.color.app_primary'))
            }
          }
          .width('100%')
          .padding({ left: 6, right: 6, top: 9, bottom: 9 })
          .borderRadius(10)
          .backgroundColor(this.noteInterval === min ? $r('app.color.app_primary_bg') : $r('app.color.page_background'))
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

      Text('树脂/派遣达到阈值时发送系统通知（需先授权通知）。应用进程被系统回收后，本地通知依赖系统提醒代理能力，当前版本在进程存活/后台驻留期间可靠。')
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
            Button('去「账号与数据」选择')
              .backgroundColor($r('app.color.app_primary'))
              .fontColor(Color.White)
              .onClick(() => {
                router.pushUrl({ url: 'pages/UserPage' });
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          // 标题行
          Row() {
            Text('实时便笺')
              .fontSize($r('app.float.page_title_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 8 })

          // 顶部 CommandBar 操作卡（立即刷新/验证/添加实时便笺/通知设置）
          this.commandBarCard()

          // 内容区：错误横幅 + 加载态 + 追踪卡瀑布流（宽屏断点读内容区自身宽度 >=840）
          Column() {
            if (this.lastNoteError.length > 0) {
              this.errorBanner()
            }
            if (this.vm.note === undefined) {
              this.loadingBlock()
            }
            if (this.currentEntries().length > 0) {
              this.noteWaterfall()
            } else if (this.vm.note !== undefined) {
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
    .bindSheet($$this.showNoteSettings, this.noteSettingsSheet(), {
      title: { title: '刷新与通知' },
      showClose: true,
      dragBar: true,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.Regular,
      backgroundColor: $r('app.color.sheet_material_tint'),
    })
    .bindSheet($$this.showUidSettings, this.uidSettingsSheet(), {
      title: { title: '通知设置' },
      showClose: true,
      dragBar: true,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.Regular,
      backgroundColor: $r('app.color.sheet_material_tint'),
    })
  }
}
