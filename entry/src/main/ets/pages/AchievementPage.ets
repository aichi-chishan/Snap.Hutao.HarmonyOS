/**
 * AchievementPage.ets（@Entry）
 * 成就系统：多档案管理 + 完成度统计 + 分类/状态/搜索筛选 + 手动勾选 + UIAF v1.1 导入导出。
 * 元数据：本地 rawfile（paimon-moe 社区数据集，无胡桃云依赖），对齐 Windows 版成就页。
 */
import { ShowDialogSuccessResponse } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AchievementService, UiafImportResult } from '../service/AchievementService';
import {
  AchievementArchive,
  AchievementCategory,
  AchievementEntry,
  AchievementRecord,
  AchievementStats,
  CategoryStats,
  UiafImportStrategy,
} from '../model/AchievementData';
import { PageToolbar } from '../components/PageToolbar';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { PageBackdrop } from '../components/PageBackdrop';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, SelectMaterialModifier, UiSurface } from '../common/UiSurface';

const UIAF_MAX_BYTES: number = 32 * 1024 * 1024;

/** 同名的每个阶段都使用自己的成就 ID 和完成状态。 */
class AchievementRow {
  archiveId: number = -1;
  entry: AchievementEntry = new AchievementEntry();
  categoryName: string = '';
  completed: boolean = false;
  timestamp: number = 0;
  progress: number = -1;
}

@Entry
@Component
export struct AchievementPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('helpLocaleVersion') @Watch('onLocaleChanged') localeVersion: number = 0;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让 */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  @State isWide: boolean = false;
  @State contentWidth: number = 0;
  @State gridMode: boolean = false;
  @State categoryColumns: number = 1;
  @State archives: AchievementArchive[] = [];
  @State currentArchiveId: number = -1;
  @State stats: AchievementStats = new AchievementStats();
  @State catStats: CategoryStats[] = [];
  @State categoryRows: CategoryStats[] = [];
  /** 长列表数据源（LazyForEach：1000+ 成就全量渲染卡顿，懒加载只画可视区） */
  private entrySource: SimpleDataSource<AchievementRow> = new SimpleDataSource([]);
  /** 筛选：0=全部 1=已完成 2=未完成 */
  @State statusFilter: number = 0;
  /** 未完成优先排序，完成条目按完成时间倒序。 */
  @State uncompletedFirst: boolean = true;
  /** 分类筛选：-1=全部 */
  @State categoryFilter: number = -1;
  @State keyword: string = '';
  @State visibleCount: number = 0;
  @State showCreate: boolean = false;
  @State newName: string = '';
  @State busy: boolean = false;
  @State importStrategy: UiafImportStrategy = UiafImportStrategy.Lazy;
  @State showImportOptions: boolean = false;
  @State showFilters: boolean = false;
  @State dailyQuestOnly: boolean = false;
  @State dailyQuestCount: number = 0;
  private records: Map<number, AchievementRecord> = new Map();
  /** 搜索防抖定时器（每键击全量重建列表会卡死 UI） */
  private searchTimer: number = -1;
  private attached: boolean = false;
  private dataSequence: number = 0;
  private archiveSequence: number = 0;
  private pageEpoch: number = 0;

  aboutToAppear(): void {
    this.attached = true;
    this.pageEpoch++;
    const epoch: number = this.pageEpoch;
    this.reload().catch((e: Error): void => {
      if (this.attached && epoch === this.pageEpoch) { this.toast(`读取失败：${e.message}`); }
    });
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.pageEpoch++;
    this.archiveSequence++;
    this.dataSequence++;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
  }

  private onLocaleChanged(): void {
    if (!this.attached || this.currentArchiveId < 0) { return; }
    const epoch: number = this.pageEpoch;
    const sequence: number = this.dataSequence + 1;
    this.refreshData().catch((e: Error): void => {
      if (this.attached && epoch === this.pageEpoch && sequence === this.dataSequence) { this.toast(`读取失败：${e.message}`); }
    });
  }

  async reload(): Promise<void> {
    const sequence: number = ++this.archiveSequence;
    const epoch: number = this.pageEpoch;
    this.loading = true;
    try {
      const archives: AchievementArchive[] = await AchievementService.getArchives();
      if (!this.attached || epoch !== this.pageEpoch || sequence !== this.archiveSequence) { return; }
      this.archives = archives;
      const target: AchievementArchive | undefined = archives.find((archive: AchievementArchive): boolean => archive.isSelected) ?? archives[0];
      this.currentArchiveId = target?.id ?? -1;
      await this.refreshData();
    } finally {
      if (this.attached && epoch === this.pageEpoch && sequence === this.archiveSequence) { this.loading = false; }
    }
  }

  /** 重读当前档案完成状态并重建列表 */
  async refreshData(): Promise<void> {
    const sequence: number = ++this.dataSequence;
    const archiveId: number = this.currentArchiveId;
    if (archiveId < 0) {
      this.records = new Map<number, AchievementRecord>();
      this.catStats = [];
      this.categoryRows = [];
      this.stats = new AchievementStats();
      this.visibleCount = 0;
      this.entrySource.notifyDataReload([]);
      return;
    }
    const records: Map<number, AchievementRecord> = await AchievementService.getRecords(archiveId);
    const categoryStats: CategoryStats[] = await AchievementService.getCategoryStats(archiveId, records);
    if (!this.attached || sequence !== this.dataSequence || archiveId !== this.currentArchiveId) { return; }
    this.records = records;
    this.catStats = categoryStats;
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
    this.rebuildEntries();
  }

  private rebuildEntries(): void {
    const query: string = this.keyword.trim().toLowerCase();
    const categoryFilter: number = this.categoryFilter;
    const dailyQuestOnly: boolean = this.dailyQuestOnly;
    const statusFilter: number = this.statusFilter;
    const rows: AchievementRow[] = [];
    const categories: CategoryStats[] = [];
    for (const group of this.catStats) {
      const category: AchievementCategory = group.category;
      let matches: boolean = false;
      for (const entry of category.entries) {
        if (dailyQuestOnly && !entry.isDailyQuest) { continue; }
        if (!AchievementPage.matchesSearch(entry, query)) { continue; }
        const record: AchievementRecord | undefined = this.records.get(entry.id);
        const completed: boolean = AchievementRecord.isDone(record);
        if (statusFilter === 1 && !completed || statusFilter === 2 && completed) { continue; }
        matches = true;
        if (categoryFilter >= 0 && category.id !== categoryFilter) { continue; }
        const row: AchievementRow = new AchievementRow();
        row.archiveId = this.currentArchiveId;
        row.entry = entry;
        row.categoryName = category.name;
        row.completed = completed;
        row.timestamp = completed && record !== undefined && record.timestamp < 253402271999 ? record.timestamp : 0;
        row.progress = !completed && record !== undefined ? record.current : -1;
        rows.push(row);
      }
      if (matches || query.length === 0 && !dailyQuestOnly && statusFilter === 0) { categories.push(group); }
    }
    const uncompletedFirst: boolean = this.uncompletedFirst;
    if (uncompletedFirst) {
      // 同完成率保持元数据分类顺序；不改服务返回的统计快照。
      categories.sort((left: CategoryStats, right: CategoryStats): number =>
        left.stats.done / Math.max(1, left.stats.total) - right.stats.done / Math.max(1, right.stats.total));
    }
    this.categoryRows = categories;
    rows.sort((left: AchievementRow, right: AchievementRow): number => {
      if (uncompletedFirst) {
        const difference: number = Number(left.completed) - Number(right.completed) || right.timestamp - left.timestamp;
        if (difference !== 0) { return difference; }
      }
      return left.entry.order - right.entry.order;
    });
    this.visibleCount = rows.length;
    this.entrySource.notifyDataReload(rows);
  }

  private static matchesSearch(entry: AchievementEntry, query: string): boolean {
    if (query.length === 0) { return true; }
    if (/^\d+$/.test(query)) { return entry.id === Number(query); }
    if (/^\d+\.\d+$/.test(query)) { return entry.ver.toLowerCase() === query; }
    const name: string = entry.name.toLowerCase();
    const canonicalName: string = entry.canonicalName.toLowerCase();
    const description: string = entry.desc.toLowerCase();
    return name.includes(query) || description.includes(query) ||
      canonicalName.includes(query) || canonicalName.replace(/\p{P}/gu, '').includes(query) ||
      name.replace(/\p{P}/gu, '').includes(query) || description.replace(/\p{P}/gu, '').includes(query);
  }

  private static completionText(stats: AchievementStats): string {
    return `${stats.done}/${stats.total} - ${(stats.total > 0 ? stats.done / stats.total * 100 : 0).toFixed(2)}%`;
  }

  private onContentAreaChange(width: number): void {
    if (!Number.isFinite(width) || width <= 0) { return; }
    this.contentWidth = width;
    this.isWide = width >= 840;
    this.categoryColumns = Math.max(1, Math.floor((width - 20) / 212));
  }

  private toggleSort(): void {
    this.uncompletedFirst = !this.uncompletedFirst;
    this.rebuildEntries();
  }

  private openCategory(id: number): void {
    this.chooseCategory(id);
    this.gridMode = false;
  }

  private ownsArchive(epoch: number, archiveId: number): boolean {
    return this.attached && epoch === this.pageEpoch && archiveId === this.currentArchiveId;
  }
  private static formatStamp(sec: number): string {
    const d: Date = new Date(sec * 1000);
    const p = (n: number): string => `${n}`.padStart(2, '0');
    return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())} `
      + `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 2000 });
  }

  private async copyAchievementId(id: number): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, String(id));
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('已复制成就 ID');
    } catch (e) {
      this.toast(`复制失败：${(e as Error).message}`);
    }
  }

  private async openAchievementGuide(name: string, hoyolab: boolean): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(AchievementService.guideUrl(name, hoyolab));
    } catch (e) {
      this.toast(`打开失败：${(e as Error).message}`);
    }
  }

  private async setCompletion(row: AchievementRow, completed: boolean): Promise<void> {
    if (!this.attached || this.busy || this.currentArchiveId < 0 || row.archiveId !== this.currentArchiveId ||
      row.completed === completed) { return; }
    this.busy = true;
    const archiveId: number = this.currentArchiveId;
    const epoch: number = this.pageEpoch;
    try {
      await AchievementService.setCompleted(archiveId, row.entry.id, completed);
      if (this.ownsArchive(epoch, archiveId)) { await this.refreshData(); }
    } catch (e) {
      if (this.ownsArchive(epoch, archiveId)) { this.toast(`保存失败：${(e as Error).message}`); }
    } finally {
      this.busy = false;
    }
  }

  async switchArchive(id: number): Promise<void> {
    if (!this.attached || this.busy || id === this.currentArchiveId ||
      !this.archives.some((archive: AchievementArchive): boolean => archive.id === id)) {
      return;
    }
    this.busy = true;
    const epoch: number = this.pageEpoch;
    try {
      await AchievementService.selectArchive(id);
      if (!this.attached || epoch !== this.pageEpoch) { return; }
      this.currentArchiveId = id;
      await this.refreshData();
    } catch (e) {
      if (this.attached && epoch === this.pageEpoch) { this.toast(`切换失败：${(e as Error).message}`); }
    } finally {
      this.busy = false;
    }
  }

  async createArchive(): Promise<void> {
    if (!this.attached || this.busy) { return; }
    const name: string = this.newName.trim();
    if (name.length === 0) {
      this.toast('请输入档案名称');
      return;
    }
    this.busy = true;
    const epoch: number = this.pageEpoch;
    try {
      await AchievementService.createArchive(name);
      if (!this.attached || epoch !== this.pageEpoch) { return; }
      this.showCreate = false;
      this.newName = '';
      await this.reload();
    } catch (e) {
      if (this.attached && epoch === this.pageEpoch) { this.toast(`创建失败：${(e as Error).message}`); }
    } finally {
      this.busy = false;
    }
  }

  currentName(): string {
    // 循环内只读局部快照（lint: 避免循环里反复读状态变量）
    const archives: AchievementArchive[] = this.archives;
    const currentId: number = this.currentArchiveId;
    for (const a of archives) {
      if (a.id === currentId) {
        return a.name;
      }
    }
    return '';
  }

  async deleteCurrentArchive(): Promise<void> {
    if (!this.attached || this.busy || this.currentArchiveId < 0) { return; }
    const archiveId: number = this.currentArchiveId;
    const epoch: number = this.pageEpoch;
    this.busy = true;
    try {
      const choice: ShowDialogSuccessResponse | undefined = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: UiSurface.dialogMaterial(),
        title: '删除档案',
        message: `确定删除「${this.currentName()}」及其全部记录？`,
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.ui_account_insights_delete'), color: $r('app.color.danger') },
        ],
      }).catch((): undefined => undefined);
      if (choice?.index !== 1 || !this.ownsArchive(epoch, archiveId)) { return; }
      await AchievementService.deleteArchive(archiveId);
      if (this.ownsArchive(epoch, archiveId)) { await this.reload(); }
    } catch (e) {
      if (this.ownsArchive(epoch, archiveId)) { this.toast(`删除失败：${(e as Error).message}`); }
    } finally {
      this.busy = false;
    }
  }

  /** 剪贴板导入 UIAF（对齐 Windows ImportUIAFFromClipboardCommand：剪贴板 JSON 直接解析） */
  async importUiafFromClipboard(): Promise<void> {
    if (!this.attached || this.busy || this.currentArchiveId < 0) {
      return;
    }
    const archiveId: number = this.currentArchiveId;
    const epoch: number = this.pageEpoch;
    this.busy = true;
    try {
      const pd: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      if (!this.ownsArchive(epoch, archiveId)) { return; }
      const text: string = pd.getPrimaryText();
      if (text.length > UIAF_MAX_BYTES) { throw new Error('UIAF 文件超过 32 Mi 字符限制'); }
      if (text.length === 0 || !text.includes('uiaf_version')) {
        this.toast('剪贴板中没有 UIAF 数据');
        return;
      }
      await this.applyUiaf(text, archiveId, epoch);
    } catch (e) {
      if (this.ownsArchive(epoch, archiveId)) { this.toast(`导入失败：${(e as Error).message}`); }
    } finally {
      this.busy = false;
    }
  }

  /** 选择文件导入 UIAF */
  async importUiaf(): Promise<void> {
    if (!this.attached || this.busy || this.currentArchiveId < 0) {
      return;
    }
    const archiveId: number = this.currentArchiveId;
    const epoch: number = this.pageEpoch;
    this.busy = true;
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['.json'];
      const uris: string[] = await docPicker.select(opts);
      if (uris.length === 0 || !this.ownsArchive(epoch, archiveId)) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      let text: string = '';
      try {
        const stat: fileIo.Stat = fileIo.statSync(file.fd);
        if (!Number.isSafeInteger(stat.size) || stat.size <= 0 || stat.size > UIAF_MAX_BYTES) {
          throw new Error('UIAF 文件为空或超过 32 MiB 限制');
        }
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        if (fileIo.readSync(file.fd, buf) !== stat.size || fileIo.statSync(file.fd).size !== stat.size) {
          throw new Error('UIAF 文件读取不完整或大小发生变化');
        }
        text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(buf));
      } finally {
        fileIo.closeSync(file);
      }
      if (this.ownsArchive(epoch, archiveId)) { await this.applyUiaf(text, archiveId, epoch); }
    } catch (e) {
      if (this.ownsArchive(epoch, archiveId)) { this.toast(`导入失败：${(e as Error).message}`); }
    } finally {
      this.busy = false;
    }
  }

  private async applyUiaf(text: string, archiveId: number, epoch: number): Promise<void> {
    if (!this.ownsArchive(epoch, archiveId)) { return; }
    const strategy: UiafImportStrategy = this.importStrategy;
    if (strategy === UiafImportStrategy.Overwrite) {
      const dialog: ShowDialogSuccessResponse = await this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
        title: '覆盖成就档案',
        message: `文件将替换「${this.currentName()}」的全部记录；文件中没有的成就记录会被移除。是否继续？`,
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
          { text: '覆盖导入', color: $r('app.color.danger') },
        ],
      });
      if (dialog.index !== 1 || !this.ownsArchive(epoch, archiveId)) {
        return;
      }
    }
    const result: UiafImportResult = await AchievementService.importUiaf(archiveId, text, strategy);
    if (!this.ownsArchive(epoch, archiveId)) { return; }
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
    if (!this.attached || this.busy || this.currentArchiveId < 0) { return; }
    const epoch: number = this.pageEpoch;
    const archiveId: number = this.currentArchiveId;
    const name: string = this.currentName().replace(/[<>:"/\\|?*\u0000-\u001f]/g, '_') || 'uiaf_export';
    this.busy = true;
    try {
      const json: string = await AchievementService.exportUiaf(archiveId);
      if (!this.ownsArchive(epoch, archiveId)) { return; }
      const bytes: Uint8Array = util.TextEncoder.create().encodeInto(json);
      if (bytes.byteLength > UIAF_MAX_BYTES) { throw new Error('UIAF 导出超过 32 MiB 限制'); }
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = [`${name}.json`];
      const uris: string[] = await docPicker.save(opts);
      if (uris.length === 0 || !this.ownsArchive(epoch, archiveId)) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        if (fileIo.writeSync(file.fd, bytes.buffer) !== bytes.byteLength) { throw new Error('UIAF 文件写入不完整，请重新导出'); }
      } finally {
        fileIo.closeSync(file);
      }
      this.toast('导出成功（UIAF v1.1）');
    } catch (e) {
      if (this.ownsArchive(epoch, archiveId)) { this.toast(`导出失败：${(e as Error).message}`); }
    } finally { this.busy = false; }
  }

  private importActions(): MenuElement[] {
    const enabled: boolean = !this.busy && this.currentArchiveId >= 0;
    return [
      { value: '从剪贴板导入 UIAF', enabled: enabled, action: () => { this.importUiafFromClipboard(); } },
      { value: '从文件导入 UIAF', enabled: enabled, action: () => { this.importUiaf(); } },
    ];
  }

  private pageActions(): MenuElement[] {
    const enabled: boolean = !this.busy && this.currentArchiveId >= 0;
    return [
      { value: '创建新档案', enabled: !this.busy, action: () => { this.showCreate = !this.showCreate; } },
      { value: '删除当前档案', enabled: enabled, action: () => { this.deleteCurrentArchive(); } },
      { value: '从文件导入 UIAF', enabled: enabled, action: () => { this.importUiaf(); } },
      { value: '从剪贴板导入 UIAF', enabled: enabled, action: () => { this.importUiafFromClipboard(); } },
      { value: '导出 UIAF', enabled: enabled, action: () => { this.exportUiaf(); } },
      { value: this.uncompletedFirst ? '恢复默认顺序' : '优先未完成', enabled: enabled, action: () => { this.toggleSort(); } },
      { value: this.showFilters ? '收起状态筛选' : '展开状态筛选', enabled: enabled, action: () => { this.showFilters = !this.showFilters; } },
      { value: this.dailyQuestOnly ? '显示全部成就' : '仅每日委托', enabled: enabled && this.dailyQuestCount > 0,
        action: () => { this.dailyQuestOnly = !this.dailyQuestOnly; this.categoryFilter = -1; this.rebuildEntries(); } },
      { value: this.showImportOptions ? '收起导入策略' : 'UIAF 导入策略', enabled: enabled,
        action: () => { this.showImportOptions = !this.showImportOptions; } },
    ];
  }

  private chooseCategory(id: number): void {
    this.categoryFilter = id;
    this.keyword = '';
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.rebuildEntries();
  }

  private search(value: string): void {
    if (this.keyword === value) { return; }
    this.keyword = value;
    this.categoryFilter = -1;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout(() => this.rebuildEntries(), 300);
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
        this.header()
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
            Text('正在读取成就档案').fontSize(13).fontColor($r('app.color.text_secondary'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.currentArchiveId < 0) {
          Column({ space: 12 }) {
            Text('暂无成就档案').fontSize(15).fontColor($r('app.color.text_secondary'))
            Button('新建档案', { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
              .height(44).hoverEffect(HoverEffect.Highlight)
              .onClick(() => { this.showCreate = true; })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.gridMode) {
          this.categoryGrid()
        } else {
          Row({ space: 12 }) {
            if (this.isWide) { this.categoryPanel() }
            this.entryList()
          }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)
        }
      }.width('100%').height('100%').onAreaChange((_old: Area, area: Area) => {
        this.onContentAreaChange(Number(area.width));
      })
    }.width('100%').height('100%')
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      PageToolbar({ embedMode: this.embedMode,
        leading: (): void => this.toolbarLeading(), trailing: (): void => this.toolbarActions() })
      if (this.currentArchiveId >= 0 && this.contentWidth < 1200) {
        Row({ space: 8 }) {
          this.archiveSelector()
          Button('新建', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44).fontSize(12)
            .enabled(!this.busy).hoverEffect(HoverEffect.Highlight).onClick(() => { this.showCreate = !this.showCreate; })
          this.importButton()
          this.exportButton()
        }.width('100%')
      }
      if (this.currentArchiveId >= 0 && !this.isWide) {
        Row({ space: 8 }) {
          this.searchBox()
          Text(`${(this.stats.total > 0 ? this.stats.done / this.stats.total * 100 : 0).toFixed(2)}%`)
            .fontSize(12).fontColor($r('app.color.text_secondary')).accessibilityText('成就完成比率')
        }.width('100%').height(44)
      }
      if (this.showCreate) {
        Row({ space: 8 }) {
          TextInput({ text: this.newName, placeholder: '成就档案名称' }).fontSize(13).height(44).layoutWeight(1)
            .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
            .enabled(!this.busy)
            .enterKeyType(EnterKeyType.Done).onChange((value: string) => { this.newName = value; })
            .onSubmit(() => this.createArchive())
          Button('创建档案', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44)
            .enabled(!this.busy).hoverEffect(HoverEffect.Highlight).onClick(() => this.createArchive())
        }.width('100%')
      }
      if (this.currentArchiveId >= 0 && this.showImportOptions) {
        Row({ space: 8 }) {
          Select([{ value: '惰性合并' }, { value: '积极合并' }, { value: '覆盖档案' }])
            .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.importStrategy)
            .value(this.importStrategy === UiafImportStrategy.Lazy ? '惰性合并' :
              (this.importStrategy === UiafImportStrategy.Aggressive ? '积极合并' : '覆盖档案'))
            .font({ size: 12 }).accessibilityText('UIAF 导入策略').enabled(!this.busy).hoverEffect(HoverEffect.Highlight)
            .onSelect((index: number) => { this.importStrategy = index as UiafImportStrategy; })
          Text(this.importStrategyLabel()).fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        }.width('100%')
      }
      if (this.currentArchiveId >= 0) { this.filterRow() }
    }.width('100%').padding({ left: 16, right: 16, top: this.embedMode ? 8 : 0, bottom: 8 })
  }

  @Builder
  toolbarLeading() {
    Row({ space: 4 }) {
      this.viewButton(0)
      this.viewButton(1)
      Text(this.isWide ? AchievementPage.completionText(this.stats) : `${this.stats.done}/${this.stats.total}`)
        .fontSize(this.isWide ? 14 : 12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .accessibilityText(`成就完成度 ${AchievementPage.completionText(this.stats)}`)
      if (this.isWide && this.currentArchiveId >= 0) { this.searchBox() }
    }.width('100%')
  }

  @Builder
  toolbarActions() {
    if (this.contentWidth >= 1200 && this.currentArchiveId >= 0) {
      Row({ space: 4 }) { this.archiveSelector() }.width(140)
      Button('创建档案', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44).fontSize(12)
        .enabled(!this.busy).hoverEffect(HoverEffect.Highlight).onClick(() => { this.showCreate = !this.showCreate; })
      Button('删除', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44).fontSize(12)
        .enabled(!this.busy).hoverEffect(HoverEffect.Highlight).onClick(() => this.deleteCurrentArchive())
      this.importButton()
      this.exportButton()
    }
    if (this.isWide && this.currentArchiveId >= 0) {
      Button('优先未完成', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, this.uncompletedFirst))
        .height(44).fontSize(12).enabled(!this.busy).hoverEffect(HoverEffect.Highlight).onClick(() => this.toggleSort())
    }
    Button('更多', { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44).fontSize(12)
      .accessibilityText('成就档案与筛选操作').hoverEffect(HoverEffect.Highlight)
      .bindMenu(this.pageActions(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  viewButton(slot: number) {
    Button(slot === 0 ? '列表' : '网格', { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, this.gridMode === (slot === 1)))
      .width(44).height(44).fontSize(12).accessibilityText(slot === 0 ? '成就列表视图' : '成就分类网格视图')
      .hoverEffect(HoverEffect.Highlight).onClick(() => { this.gridMode = slot === 1; })
  }

  @Builder
  archiveSelector() {
    Select(this.archives.map((archive: AchievementArchive): SelectOption => ({ value: archive.name })))
      .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
      .selected(this.archives.findIndex((archive: AchievementArchive): boolean => archive.id === this.currentArchiveId))
      .value(this.currentName()).layoutWeight(1).constraintSize({ minHeight: 44 }).font({ size: 12 })
      .accessibilityText('选择成就档案').enabled(!this.busy).hoverEffect(HoverEffect.Highlight)
      .onSelect((index: number) => {
        const archive: AchievementArchive | undefined = this.archives[index];
        if (archive !== undefined) { this.switchArchive(archive.id); }
      })
  }

  @Builder
  searchBox() {
    TextInput({ text: this.keyword, placeholder: '搜索成就名称、描述、版本或编号' }).fontSize(13).height(44)
      .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
      .layoutWeight(1).accessibilityText('搜索成就名称、描述、版本或编号')
      .enterKeyType(EnterKeyType.Search).onChange((value: string) => this.search(value))
  }

  @Builder
  importButton() {
    Button('导入', { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44).fontSize(12)
      .enabled(!this.busy).hoverEffect(HoverEffect.Highlight)
      .bindMenu(this.importActions(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  exportButton() {
    Button('导出', { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44).fontSize(12)
      .enabled(!this.busy).hoverEffect(HoverEffect.Highlight).onClick(() => this.exportUiaf())
  }

  @Builder
  entryList() {
    List({ space: 8 }) {
      if (this.visibleCount === 0) {
        ListItem() {
          Text('没有符合条件的成就').fontSize(13).fontColor($r('app.color.text_secondary'))
            .width('100%').padding(24).textAlign(TextAlign.Center)
        }
      } else {
        LazyForEach(this.entrySource, (row: AchievementRow) => {
          ListItem() { this.achievementRow(row) }
        }, (row: AchievementRow): string =>
          `achievement_${this.currentArchiveId}_${row.entry.id}_${row.entry.name}_${row.entry.desc}_${row.completed}_${row.timestamp}_${row.progress}`)
      }
    }.layoutWeight(1).height('100%').cachedCount(5).scrollBar(BarState.Auto)
      .padding({ left: this.isWide ? 0 : 16, right: 16, bottom: 16 })
  }

  @Builder
  categoryPanel() {
    List({ space: 6 }) {
      ListItem() {
        this.categoryChip(-1, '全部分类')
      }
      ForEach(this.categoryRows, (entry: CategoryStats) => {
        ListItem() {
          Row({ space: 12 }) {
            MetaIcon({ category: 'AchievementIcon',
              name: entry.category.icon || AchievementService.categoryIcon(entry.category.id), iconSize: 36 })
            Column({ space: 6 }) {
              Text(entry.category.name).fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
              Text(AchievementPage.completionText(entry.stats)).fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
              Progress({ value: entry.stats.done, total: Math.max(1, entry.stats.total), type: ProgressType.Linear })
                .width('100%').color($r('app.color.app_primary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').padding(10).borderRadius(10).constraintSize({ minHeight: 44 })
            .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
            .border({ width: 1, color: this.categoryFilter === entry.category.id ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
            .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => this.chooseCategory(entry.category.id))
        }
      }, (entry: CategoryStats): string => `category_${entry.category.id}_${entry.category.name}_${entry.stats.done}_${entry.stats.total}`)
    }.width(276).height('100%').padding({ left: 16, bottom: 16 }).scrollBar(BarState.Auto)
  }

  @Builder
  categoryGrid() {
    if (this.categoryRows.length === 0) {
      Column() {
        Text('没有符合条件的成就分类').fontSize(13).fontColor($r('app.color.text_secondary'))
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else {
      Grid() {
        ForEach(this.categoryRows, (entry: CategoryStats) => {
          GridItem() {
            Column({ space: 8 }) {
              MetaIcon({ category: 'AchievementIcon',
                name: entry.category.icon || AchievementService.categoryIcon(entry.category.id), iconSize: 64 })
              Text(entry.category.name).fontSize(14).fontColor($r('app.color.text_primary'))
                .textAlign(TextAlign.Center).width('100%')
              Text(AchievementPage.completionText(entry.stats)).fontSize(12).fontColor($r('app.color.text_secondary'))
              Row({ space: 4 }) {
                MetaIcon({ category: 'ItemIcon', name: 'UI_ItemIcon_201', iconSize: 24 })
                Text(`${entry.stats.primogemsEarned}/${entry.stats.primogemsTotal}`).fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              Progress({ value: entry.stats.done, total: Math.max(1, entry.stats.total), type: ProgressType.Linear })
                .width('100%').color($r('app.color.app_primary'))
            }.width('100%').padding(16).constraintSize({ minHeight: 200 }).borderRadius(12)
              .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
              .border({ width: 1, color: this.categoryFilter === entry.category.id ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
              .focusable(true).hoverEffect(HoverEffect.Highlight)
              .accessibilityText(`${entry.category.name}，${AchievementPage.completionText(entry.stats)}`)
              .accessibilityDescription('打开此分类的成就列表').onClick(() => this.openCategory(entry.category.id))
          }
        }, (entry: CategoryStats): string => `grid_${entry.category.id}_${entry.category.name}_${entry.stats.done}_${entry.stats.total}`)
      }.columnsTemplate(`repeat(${this.categoryColumns}, 1fr)`).columnsGap(12).rowsGap(12)
        .width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 }).scrollBar(BarState.Auto)
    }
  }

  @Builder
  statusChip(label: string, value: number) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(12).buttonStyle(ButtonStyleMode.NORMAL)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
      .fontColor(this.statusFilter === value ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .border({ width: 1, radius: 10,
        color: this.statusFilter === value ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
      .margin({ right: 6, bottom: 6 }).hoverEffect(HoverEffect.Highlight)
      .onClick(() => { this.statusFilter = value; this.rebuildEntries(); })
  }

  @Builder
  categoryChip(id: number, label: string) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(12).buttonStyle(ButtonStyleMode.NORMAL)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
      .fontColor(this.categoryFilter === id ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .border({ width: 1, radius: 10,
        color: this.categoryFilter === id ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
      .hoverEffect(HoverEffect.Highlight).onClick(() => this.chooseCategory(id))
  }

  @Builder
  filterRow() {
    Column({ space: 8 }) {
      if (this.showFilters) {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.statusChip('全部', 0)
          this.statusChip('已完成', 1)
          this.statusChip('未完成', 2)
          Button('未完成优先', { type: ButtonType.Normal }).height(44).fontSize(12).buttonStyle(ButtonStyleMode.NORMAL)
            .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
            .fontColor($r('app.color.text_primary'))
            .border({ width: 1, radius: 10,
              color: this.uncompletedFirst ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
            .margin({ right: 6, bottom: 6 }).hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.toggleSort())
          if (this.dailyQuestCount > 0) {
            Button('仅每日委托', { type: ButtonType.Normal }).height(44).fontSize(12).buttonStyle(ButtonStyleMode.NORMAL)
              .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
              .fontColor($r('app.color.text_primary'))
              .border({ width: 1, radius: 10,
                color: this.dailyQuestOnly ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
              .margin({ right: 6, bottom: 6 }).hoverEffect(HoverEffect.Highlight)
              .onClick(() => { this.dailyQuestOnly = !this.dailyQuestOnly; this.rebuildEntries(); })
          }
        }.width('100%')
      }
      if (!this.isWide && !this.gridMode) {
        Scroll() {
          Row({ space: 8 }) {
            this.categoryChip(-1, '全部分类')
            ForEach(this.categoryRows, (entry: CategoryStats) => {
              this.categoryChip(entry.category.id, `${entry.category.name} ${AchievementPage.completionText(entry.stats)}`)
            }, (entry: CategoryStats): string => `cat_${entry.category.id}_${entry.category.name}_${entry.stats.done}_${entry.stats.total}`)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }.width('100%')
  }

  private achievementActions(row: AchievementRow): MenuElement[] {
    return [
      { value: `复制 ID ${row.entry.id}`, action: () => { this.copyAchievementId(row.entry.id); } },
      { value: '米游社攻略', action: () => { this.openAchievementGuide(row.entry.canonicalName || row.entry.name, false); } },
      { value: 'HoYoLAB 攻略', action: () => { this.openAchievementGuide(row.entry.name, true); } },
    ];
  }

  @Builder
  achievementRow(row: AchievementRow) {
    Row({ space: 8 }) {
      Checkbox({ name: `achievement_${row.entry.id}` })
        .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .select(row.completed).width(44).height(44).enabled(!this.busy)
        .accessibilityText(row.entry.name)
        .hoverEffect(HoverEffect.Highlight).onChange((done: boolean) => this.setCompletion(row, done))
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(row.entry.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
          if (row.entry.ver.length > 0) {
            Text(row.entry.ver).fontSize(11).fontColor($r('app.color.app_primary_text')).padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius(3).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
          }
        }.width('100%')
        Text(row.entry.desc).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Text(this.isWide ? row.categoryName : `${row.categoryName} · ${row.entry.reward} 原石`)
          .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
        if (row.progress >= 0) {
          Text(`当前进度 ${row.progress}`).fontSize(11).fontColor($r('app.color.app_primary_text')).width('100%')
        }
        if (row.timestamp > 0) {
          Text(AchievementPage.formatStamp(row.timestamp)).fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (this.isWide) {
        Row({ space: 4 }) {
          MetaIcon({ category: 'ItemIcon', name: 'UI_ItemIcon_201', iconSize: 28 })
          Text(String(row.entry.reward)).fontSize(14).fontColor($r('app.color.text_primary'))
        }.width(64).justifyContent(FlexAlign.End)
      }
      Button('更多', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .width(44).height(44).fontSize(12).hoverEffect(HoverEffect.Highlight)
        .accessibilityDescription(`${row.entry.name}的成就操作`)
        .bindMenu(this.achievementActions(row), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
    }.width('100%').padding(12).borderRadius(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .alignItems(VerticalAlign.Center)
  }
}
