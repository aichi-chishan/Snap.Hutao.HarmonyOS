/**
 * AchievementPage.ets（@Entry）
 * 成就系统：多档案管理 + 完成度统计 + 分类/状态/搜索筛选 + 手动勾选 + UIAF v1.1 导入导出。
 * 元数据：本地 rawfile（paimon-moe 社区数据集，无胡桃云依赖），对齐 Windows 版成就页。
 */
import { router, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AchievementService, UiafImportResult } from '../service/AchievementService';
import { AchievementRepo } from '../data/repo/AchievementRepo';
import {
  AchievementArchive,
  AchievementCategory,
  AchievementEntry,
  AchievementRecord,
  AchievementStats,
  CategoryStats,
  UiafImportStrategy,
} from '../model/AchievementData';
import { AppBackButton } from '../components/AppBackButton';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { PageBackdrop } from '../components/PageBackdrop';

/** 列表展示用分组行（多阶段成就归并） */
class DisplayGroup {
  catId: number = 0;
  catName: string = '';
  name: string = '';
  desc: string = '';
  reward: number = 0;
  ver: string = '';
  ids: number[] = [];
  total: number = 1;
  achieved: number = 0;
  /** 组内最近完成时间戳（秒；0=未完成） */
  latestTime: number = 0;
  /** 下一未完成阶段的实际进度（-1=没有导入记录） */
  progressCurrent: number = -1;
  isDailyQuest: boolean = false;
}

@Entry
@Component
export struct AchievementPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让 */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  @State archives: AchievementArchive[] = [];
  @State currentArchiveId: number = -1;
  @State stats: AchievementStats = new AchievementStats();
  @State catStats: CategoryStats[] = [];
  /** 完成状态表（id -> done），变更时整体重建以触发刷新 */
  @State doneMap: Map<number, boolean> = new Map();
  /** 长列表数据源（LazyForEach：1000+ 成就全量渲染卡顿，懒加载只画可视区） */
  private groupSource: SimpleDataSource<DisplayGroup> = new SimpleDataSource([]);
  /** 筛选：0=全部 1=已完成 2=未完成 */
  @State statusFilter: number = 0;
  /** 未完成优先排序（对齐 Windows IsUncompletedItemsFirst：未完成在前，完成组按完成时间倒序） */
  @State uncompletedFirst: boolean = false;
  /** 分类筛选：-1=全部 */
  @State categoryFilter: number = -1;
  @State keyword: string = '';
  @State groups: DisplayGroup[] = [];
  @State showCreate: boolean = false;
  @State newName: string = '';
  @State busy: boolean = false;
  @State importStrategy: UiafImportStrategy = UiafImportStrategy.Lazy;
  @State dailyQuestOnly: boolean = false;
  @State dailyQuestCount: number = 0;
  private records: Map<number, AchievementRecord> = new Map();
  /** 完成时间表（id -> 完成秒级时间戳，未完成优先排序用；非渲染状态） */
  private doneTime: Map<number, number> = new Map();
  /** 搜索防抖定时器（每键击全量重建列表会卡死 UI） */
  private searchTimer: number = -1;

  aboutToAppear(): void {
    this.reload();
  }

  async reload(): Promise<void> {
    this.loading = true;
    try {
      const archives: AchievementArchive[] = await AchievementService.ensureDefaultArchive();
      this.archives = archives;
      let target: AchievementArchive | undefined = undefined;
      for (const a of archives) {
        if (a.isSelected) {
          target = a;
          break;
        }
      }
      if (target === undefined) {
        target = archives[0];
      }
      this.currentArchiveId = target.id;
      await this.refreshData();
    } finally {
      this.loading = false;
    }
  }

  /** 重读当前档案完成状态并重建列表 */
  async refreshData(): Promise<void> {
    if (this.currentArchiveId < 0) {
      return;
    }
    const records: Map<number, AchievementRecord> = await AchievementRepo.getRecords(this.currentArchiveId);
    const doneMap: Map<number, boolean> = new Map<number, boolean>();
    const doneTime: Map<number, number> = new Map<number, number>();
    records.forEach((rec: AchievementRecord, id: number) => {
      if (AchievementRecord.isDone(rec)) {
        doneMap.set(id, true);
        if (rec.timestamp > 0 && rec.timestamp < 253402271999) {
          doneTime.set(id, rec.timestamp);
        }
      }
    });
    this.records = records;
    this.doneMap = doneMap;
    this.doneTime = doneTime;
    this.catStats = await AchievementService.getCategoryStats(this.currentArchiveId);
    let dailyQuestCount: number = 0;
    for (const cs of this.catStats) {
      dailyQuestCount += cs.category.entries.filter((entry: AchievementEntry) => entry.isDailyQuest).length;
    }
    this.dailyQuestCount = dailyQuestCount;
    if (dailyQuestCount === 0) {
      this.dailyQuestOnly = false;
    }
    const stats: AchievementStats = new AchievementStats();
    for (const cs of this.catStats) {
      stats.total += cs.stats.total;
      stats.done += cs.stats.done;
      stats.primogemsTotal += cs.stats.primogemsTotal;
      stats.primogemsEarned += cs.stats.primogemsEarned;
    }
    this.stats = stats;
    this.rebuildGroups();
  }

  /** 按当前筛选条件构建分组展示行 */
  rebuildGroups(): void {
    const out: DisplayGroup[] = [];
    for (const cs of this.catStats) {
      const cat: AchievementCategory = cs.category;
      if (this.categoryFilter >= 0 && cat.id !== this.categoryFilter) {
        continue;
      }
      // 按 groupKey 聚合（保持元数据顺序）
      const grouped: Map<string, DisplayGroup> = new Map();
      const descByEntry: Map<number, string> = new Map();
      for (const e of cat.entries) {
        if (this.dailyQuestOnly && !e.isDailyQuest) {
          continue;
        }
        let g: DisplayGroup | undefined = grouped.get(e.groupKey);
        if (g === undefined) {
          g = new DisplayGroup();
          g.catId = cat.id;
          g.catName = cat.name;
          g.name = e.name;
          g.ver = e.ver;
          grouped.set(e.groupKey, g);
        }
        g.ids.push(e.id);
        g.isDailyQuest = g.isDailyQuest || e.isDailyQuest;
        g.reward += e.reward;
        descByEntry.set(e.id, e.desc);
      }
      grouped.forEach((g: DisplayGroup) => {
        g.total = g.ids.length;
        let achieved: number = 0;
        for (const id of g.ids) {
          if (this.doneMap.has(id)) {
            achieved += 1;
          }
        }
        g.achieved = achieved;
        // 描述取"下一阶段"（全完成时取最后一阶段）
        const incompleteIdx: number = g.ids.findIndex((id: number) => !this.doneMap.has(id));
        const nextIdx: number = incompleteIdx >= 0 ? incompleteIdx : g.ids.length - 1;
        const record: AchievementRecord | undefined = this.records.get(g.ids[nextIdx]);
        if (incompleteIdx >= 0 && record !== undefined) {
          g.progressCurrent = record.current;
        }
        const desc: string | undefined = descByEntry.get(g.ids[nextIdx]);
        g.desc = desc !== undefined ? desc : '';
        // 组内最近完成时间（排序与展示共用）
        g.latestTime = this.groupLatestTime(g);
        if (this.statusFilter === 1 && achieved === 0) {
          return;
        }
        if (this.statusFilter === 2 && achieved >= g.total) {
          return;
        }
        // 搜索三态（对齐 Windows UpdateAchievementsFilterBySearch）：
        // 纯数字 → 成就 ID；x.y 形式 → 版本号；其余 → 名称/描述包含
        const kw: string = this.keyword.trim();
        if (kw.length > 0) {
          if (/^\d+$/.test(kw)) {
            const qid: number = Number(kw);
            if (!g.ids.includes(qid)) {
              return;
            }
          } else if (/^\d+\.\d+$/.test(kw)) {
            if (g.ver !== kw) {
              return;
            }
          } else if (!g.name.includes(kw) && !g.desc.includes(kw)) {
            return;
          }
        }
        out.push(g);
      });
    }
    if (this.uncompletedFirst) {
      out.sort((a: DisplayGroup, b: DisplayGroup) => {
        const aDone: number = a.achieved >= a.ids.length ? 1 : 0;
        const bDone: number = b.achieved >= b.ids.length ? 1 : 0;
        if (aDone !== bDone) {
          return aDone - bDone;
        }
        // 都完成时按最近完成时间倒序（取组内最大时间戳）
        if (aDone === 1) {
          const at: number = this.groupLatestTime(a);
          const bt: number = this.groupLatestTime(b);
          if (at !== bt) {
            return bt - at;
          }
        }
        return 0;
      });
    }
    this.groups = out;
    this.groupSource.notifyDataReload(out);
  }

  /** 分组内最大完成时间戳（无记录返回 0） */
  private groupLatestTime(g: DisplayGroup): number {
    let latest: number = 0;
    for (const id of g.ids) {
      const t: number | undefined = this.doneTime.get(id);
      if (t !== undefined && t > latest) {
        latest = t;
      }
    }
    return latest;
  }

  /** 完成时间戳 → "yyyy.MM.dd HH:mm:ss"（对齐 Windows AchievementView.Time 格式） */
  private static formatStamp(sec: number): string {
    const d: Date = new Date(sec * 1000);
    const p = (n: number): string => `${n}`.padStart(2, '0');
    return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())} `
      + `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async copyAchievementIds(g: DisplayGroup): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, g.ids.join(', '));
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast(g.ids.length > 1 ? '已复制各阶段成就 ID' : '已复制成就 ID');
    } catch (e) {
      this.toast(`复制失败：${(e as Error).message}`);
    }
  }

  private async openAchievementGuide(g: DisplayGroup, hoyolab: boolean): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(AchievementService.guideUrl(g.name, hoyolab));
    } catch (e) {
      this.toast(`打开失败：${(e as Error).message}`);
    }
  }

  /** 点击分组：未完成→完成下一阶段；全完成→清空整组 */
  async tapGroup(g: DisplayGroup): Promise<void> {
    if (this.busy || this.currentArchiveId < 0) {
      return;
    }
    this.busy = true;
    try {
      if (g.achieved >= g.ids.length) {
        for (const id of g.ids) {
          await AchievementRepo.setRecord(this.currentArchiveId, id, false, 0);
        }
      } else {
        const nextId: number = g.ids.find((id: number) => !this.doneMap.has(id)) ?? g.ids[0];
        await AchievementRepo.setRecord(this.currentArchiveId, nextId, true, Math.floor(Date.now() / 1000));
      }
      await this.refreshData();
    } finally {
      this.busy = false;
    }
  }

  async switchArchive(id: number): Promise<void> {
    if (this.busy || id === this.currentArchiveId) {
      return;
    }
    await AchievementRepo.selectArchive(id);
    this.currentArchiveId = id;
    await this.refreshData();
  }

  async createArchive(): Promise<void> {
    const name: string = this.newName.trim();
    if (name.length === 0) {
      this.toast('请输入档案名称');
      return;
    }
    await AchievementRepo.createArchive(name);
    this.showCreate = false;
    this.newName = '';
    await this.reload();
  }

  currentName(): string {
    for (const a of this.archives) {
      if (a.id === this.currentArchiveId) {
        return a.name;
      }
    }
    return '';
  }

  async deleteCurrentArchive(): Promise<void> {
    if (this.currentArchiveId < 0 || this.archives.length <= 1) {
      this.toast('至少保留一个档案');
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除档案',
      message: `确定删除「${this.currentName()}」及其全部完成记录？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.danger') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index === 1) {
        AchievementRepo.deleteArchive(this.currentArchiveId).then(() => {
          this.reload();
        });
      }
    });
  }

  /** 剪贴板导入 UIAF（对齐 Windows ImportUIAFFromClipboardCommand：剪贴板 JSON 直接解析） */
  async importUiafFromClipboard(): Promise<void> {
    if (this.busy || this.currentArchiveId < 0) {
      return;
    }
    const archiveId: number = this.currentArchiveId;
    this.busy = true;
    try {
      const pd: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      const text: string = pd.getPrimaryText();
      if (text.length === 0 || !text.includes('uiaf_version')) {
        this.toast('剪贴板中没有 UIAF 数据');
        return;
      }
      await this.applyUiaf(text, archiveId);
    } catch (e) {
      this.toast(`导入失败：${(e as Error).message}`);
    } finally {
      this.busy = false;
    }
  }

  /** 选择文件导入 UIAF */
  async importUiaf(): Promise<void> {
    if (this.busy || this.currentArchiveId < 0) {
      return;
    }
    const archiveId: number = this.currentArchiveId;
    this.busy = true;
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['.json'];
      const uris: string[] = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      try {
        const stat: fileIo.Stat = fileIo.statSync(file.fd);
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
        await this.applyUiaf(text, archiveId);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      this.toast(`导入失败：${(e as Error).message}`);
    } finally {
      this.busy = false;
    }
  }

  private async applyUiaf(text: string, archiveId: number): Promise<void> {
    const strategy: UiafImportStrategy = this.importStrategy;
    if (strategy === UiafImportStrategy.Overwrite) {
      const dialog: ShowDialogSuccessResponse = await this.getUIContext().getPromptAction().showDialog({
        title: '覆盖成就档案',
        message: `文件将替换「${this.currentName()}」的全部记录；文件中没有的成就记录会被移除。是否继续？`,
        buttons: [
          { text: '取消', color: $r('app.color.text_secondary') },
          { text: '覆盖导入', color: $r('app.color.danger') },
        ],
      });
      if (dialog.index !== 1) {
        return;
      }
    }
    const result: UiafImportResult = await AchievementService.importUiaf(archiveId, text, strategy);
    this.toast(result.ok ? result.message : `导入失败：${result.message}`);
    if (result.ok && this.currentArchiveId === archiveId) {
      await this.refreshData();
    }
  }

  private importStrategyLabel(): string {
    if (this.importStrategy === UiafImportStrategy.Aggressive) {
      return '积极合并：更新同 ID 的记录，保留其他记录';
    }
    if (this.importStrategy === UiafImportStrategy.Overwrite) {
      return '覆盖：档案完全以导入文件为准';
    }
    return '惰性合并：仅添加新成就，保留已有记录';
  }

  /** 导出 UIAF 到用户选择的文件 */
  async exportUiaf(): Promise<void> {
    try {
      const json: string = await AchievementService.exportUiaf(this.currentArchiveId);
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = ['uiaf_export.json'];
      const uris: string[] = await docPicker.save(opts);
      if (uris.length === 0) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, json);
      } finally {
        fileIo.closeSync(file);
      }
      this.toast('导出成功（UIAF v1.1）');
    } catch (e) {
      this.toast(`导出失败：${(e as Error).message}`);
    }
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
      this.header()
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
          Text('加载中...')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 单一 List + LazyForEach（Scroll 内套 List 会使 LazyForEach 失去视口无法虚拟化 → 1548 行全量实例化卡死）
        List() {
          ListItem() {
            this.statsCard()
          }
          .margin({ bottom: 12 })
          ListItem() {
            this.filterRow()
          }
          .margin({ bottom: 12 })
          if (this.groups.length === 0) {
            ListItem() {
              Text('没有符合条件的成就')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ top: 30, bottom: 30 })
                .textAlign(TextAlign.Center)
            }
          } else {
            LazyForEach(this.groupSource, (g: DisplayGroup) => {
              ListItem() {
                this.groupRow(g)
              }
              .margin({ bottom: 8 })
            }, (g: DisplayGroup) => `g_${g.ids[0]}_${g.achieved}_${g.latestTime}_${g.progressCurrent}_${g.isDailyQuest}`)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(5)
        .padding({ left: 16, right: 16, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      Row() {
        if (!this.embedMode) {
          AppBackButton()
        }
        Text('成就')
          .fontSize($r('app.float.page_title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: this.embedMode ? 0 : 10 })
        Blank()
        Button('剪贴板导入')
          .fontSize(12)
          .height(30)
          .backgroundColor($r('app.color.app_primary_bg'))
          .fontColor($r('app.color.app_primary'))
          .onClick(() => {
            this.importUiafFromClipboard();
          })
        Button('导入 UIAF')
          .fontSize(12)
          .height(30)
          .margin({ left: 6 })
          .backgroundColor($r('app.color.app_primary_bg'))
          .fontColor($r('app.color.app_primary'))
          .onClick(() => {
            this.importUiaf();
          })
        Button('导出 UIAF')
          .fontSize(12)
          .height(30)
          .margin({ left: 6 })
          .backgroundColor($r('app.color.app_primary_bg'))
          .fontColor($r('app.color.app_primary'))
          .onClick(() => {
            this.exportUiaf();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Select([{ value: '惰性合并' }, { value: '积极合并' }, { value: '覆盖档案' }])
          .selected(this.importStrategy)
          .value(this.importStrategy === UiafImportStrategy.Lazy ? '惰性合并' :
            (this.importStrategy === UiafImportStrategy.Aggressive ? '积极合并' : '覆盖档案'))
          .font({ size: 12 })
          .enabled(!this.busy)
          .hoverEffect(HoverEffect.Highlight)
          .onSelect((index: number) => {
            this.importStrategy = index as UiafImportStrategy;
          })
        Text(this.importStrategyLabel())
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')

      // 档案切换 + 档案管理
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.archives, (a: AchievementArchive) => {
            Text(a.name)
              .fontSize(12)
              .fontColor(a.id === this.currentArchiveId ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(a.id === this.currentArchiveId ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
              .border({ width: 1, color: a.id === this.currentArchiveId ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
              .onClick(() => {
                this.switchArchive(a.id);
              })
          }, (a: AchievementArchive) => `ach_${a.id}_${a.id === this.currentArchiveId}`)
          Text('＋ 新建档案')
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .onClick(() => {
              this.showCreate = !this.showCreate;
            })
          Text('删除当前')
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .onClick(() => {
              this.deleteCurrentArchive();
            })
        }
        .padding({ right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.showCreate) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '新档案名称（如：主号/小号）' })
            .fontSize(13)
            .height(36)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.newName = v;
            })
          Button('创建')
            .fontSize(12)
            .height(32)
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick(() => {
              this.createArchive();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 0, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 6 })
  }

  @Builder
  statsCard() {
    Column({ space: 8 }) {
      Row() {
        Text(`${this.currentName()} 完成度`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(`${this.stats.done} / ${this.stats.total}`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_primary'))
      }
      .width('100%')
      Progress({ value: this.stats.done, total: this.stats.total, type: ProgressType.Linear })
        .color($r('app.color.app_primary'))
        .backgroundColor($r('app.color.divider'))
        .width('100%')
      Row({ space: 12 }) {
        Text(`${this.stats.percent()}%`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(`原石 ${this.stats.primogemsEarned} / ${this.stats.primogemsTotal}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      // 分类完成率明细（对齐 Windows AchievementGoalView.FinishPercent 进度面板）
      ForEach(this.catStats, (cs: CategoryStats) => {
        Row({ space: 10 }) {
          Text(cs.category.name)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width(120)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Progress({ value: cs.stats.done, total: cs.stats.total, type: ProgressType.Linear })
            .color($r('app.color.app_primary'))
            .backgroundColor($r('app.color.divider'))
            .layoutWeight(1)
            .style({ strokeWidth: 6 })
          Text(`${cs.stats.done}/${cs.stats.total}`)
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width(64)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }, (cs: CategoryStats) => `catbar_${cs.category.id}_${cs.stats.done}`)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_surface'))
  }

  @Builder
  statusChip(label: string, value: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.statusFilter === value ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.statusFilter === value ? $r('app.color.app_primary_bg') : Color.Transparent)
      .borderRadius(10)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.statusFilter = value;
        this.rebuildGroups();
      })
  }

  /** 未完成优先切换 chip（对齐 Windows SortUncompletedSwitchCommand） */
  @Builder
  sortChip() {
    Text('未完成优先')
      .fontSize(12)
      .fontColor(this.uncompletedFirst ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.uncompletedFirst ? $r('app.color.app_primary_bg') : Color.Transparent)
      .borderRadius(10)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.uncompletedFirst = !this.uncompletedFirst;
        this.rebuildGroups();
      })
  }

  @Builder
  filterRow() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索名称/描述/ID/版本(如5.7)' })
          .fontSize(13)
          .height(36)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.keyword = v;
            if (this.searchTimer >= 0) {
              clearTimeout(this.searchTimer);
            }
            this.searchTimer = setTimeout(() => {
              this.rebuildGroups();
            }, 300);
          })
        Row({ space: 0 }) {
          this.statusChip('全部', 0)
          this.statusChip('已完成', 1)
          this.statusChip('未完成', 2)
          this.sortChip()
        }
        .borderRadius(10)
        .backgroundColor($r('app.color.card_surface'))
      }
      .width('100%')
      // 分类筛选（横向滚动 chips）
      Row({ space: 8 }) {
        Button(this.dailyQuestCount > 0 ? '只看每日委托' : '每日委托（暂无标记）')
          .fontSize(12)
          .height(30)
          .enabled(this.dailyQuestCount > 0)
          .backgroundColor(this.dailyQuestOnly ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
          .fontColor(this.dailyQuestOnly ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.dailyQuestOnly = !this.dailyQuestOnly;
            this.rebuildGroups();
          })
        Text(this.dailyQuestOnly ? `仅显示元数据明确标记的 ${this.dailyQuestCount} 项` : '按元数据委托标记筛选')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      Scroll() {
        Row({ space: 8 }) {
          Text('全部分类')
            .fontSize(12)
            .fontColor(this.categoryFilter === -1 ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(this.categoryFilter === -1 ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
            .onClick(() => {
              this.categoryFilter = -1;
              this.rebuildGroups();
            })
          ForEach(this.catStats, (cs: CategoryStats) => {
            Text(`${cs.category.name} ${cs.stats.done}/${cs.stats.total}`)
              .fontSize(12)
              .fontColor(this.categoryFilter === cs.category.id ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .backgroundColor(this.categoryFilter === cs.category.id ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
              .onClick(() => {
                this.categoryFilter = cs.category.id;
                this.rebuildGroups();
              })
          }, (cs: CategoryStats) => `cat_${cs.category.id}_${cs.stats.done}_${this.categoryFilter}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  groupRow(g: DisplayGroup) {
    Row({ space: 10 }) {
      // 完成勾选圈
      Stack({ alignContent: Alignment.Center }) {
        if (g.achieved >= g.total) {
          Text('✓')
            .fontSize(14)
            .fontColor(Color.White)
        }
      }
      .width(26)
      .height(26)
      .borderRadius(13)
      .backgroundColor(g.achieved >= g.total ? $r('app.color.success') : Color.Transparent)
      .border({ width: 1.5, color: g.achieved >= g.total ? $r('app.color.success') : $r('app.color.divider') })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.tapGroup(g))

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(g.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(g.achieved >= g.total ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.tapGroup(g))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (g.total > 1) {
            Text(`${g.achieved}/${g.total} 阶段`)
              .fontSize(10)
              .fontColor($r('app.color.app_primary'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor($r('app.color.app_primary_bg'))
          }
          if (g.ver.length > 0) {
            Text(g.ver)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
          if (g.isDailyQuest) {
            Text('委托')
              .fontSize(10)
              .fontColor($r('app.color.app_primary'))
          }
        }
        .width('100%')
        Text(g.desc)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${g.catName} · 奖励 ${g.reward} 原石`)
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        if (g.progressCurrent >= 0) {
          Text(`当前进度 ${g.progressCurrent}`)
            .fontSize(10)
            .fontColor($r('app.color.app_primary'))
            .width('100%')
        }
        // 最近完成时间（对齐 Windows AchievementView.Time：yyyy.MM.dd HH:mm:ss）
        if (g.latestTime > 0) {
          Text(`完成于 ${AchievementPage.formatStamp(g.latestTime)}`)
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        Row({ space: 8 }) {
          Button('复制 ID')
            .fontSize(10)
            .height(26)
            .backgroundColor($r('app.color.card_surface'))
            .fontColor($r('app.color.app_primary'))
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.copyAchievementIds(g);
            })
          Button('米游社攻略')
            .fontSize(10)
            .height(26)
            .backgroundColor($r('app.color.card_surface'))
            .fontColor($r('app.color.app_primary'))
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.openAchievementGuide(g, false);
            })
          Button('HoYoLAB')
            .fontSize(10)
            .height(26)
            .backgroundColor($r('app.color.card_surface'))
            .fontColor($r('app.color.app_primary'))
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.openAchievementGuide(g, true);
            })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_surface'))
    .opacity(g.achieved >= g.total ? 0.75 : 1)
    .hoverEffect(HoverEffect.Highlight)
    // 仅勾选圈和标题改变完成状态，攻略/复制按钮不会触发父卡片切换。
  }
}
