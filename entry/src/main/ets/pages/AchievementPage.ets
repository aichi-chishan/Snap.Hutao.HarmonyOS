/**
 * AchievementPage.ets（@Entry）
 * 成就系统：多档案管理 + 完成度统计 + 分类/状态/搜索筛选 + 手动勾选 + UIAF v1.1 导入导出。
 * 元数据：本地 rawfile（paimon-moe 社区数据集，无胡桃云依赖），对齐 Windows 版成就页。
 */
import { router, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AchievementService, UiafImportResult } from '../service/AchievementService';
import { AchievementRepo } from '../data/repo/AchievementRepo';
import {
  AchievementArchive,
  AchievementCategory,
  AchievementRecord,
  AchievementStats,
  CategoryStats,
} from '../model/AchievementData';
import { AppBackButton } from '../components/AppBackButton';
import { SimpleDataSource } from '../components/SimpleDataSource';

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
  /** 分类筛选：-1=全部 */
  @State categoryFilter: number = -1;
  @State keyword: string = '';
  @State groups: DisplayGroup[] = [];
  @State showCreate: boolean = false;
  @State newName: string = '';
  @State busy: boolean = false;
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
    records.forEach((_rec: AchievementRecord, id: number) => {
      doneMap.set(id, true);
    });
    this.doneMap = doneMap;
    this.catStats = await AchievementService.getCategoryStats(this.currentArchiveId);
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
        const nextIdx: number = Math.min(achieved, g.ids.length - 1);
        const desc: string | undefined = descByEntry.get(g.ids[nextIdx]);
        g.desc = desc !== undefined ? desc : '';
        if (this.statusFilter === 1 && achieved === 0) {
          return;
        }
        if (this.statusFilter === 2 && achieved > 0) {
          return;
        }
        if (this.keyword.length > 0 && !g.name.includes(this.keyword) && !g.desc.includes(this.keyword)) {
          return;
        }
        out.push(g);
      });
    }
    this.groups = out;
    this.groupSource.notifyDataReload(out);
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
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
        const nextId: number = g.ids[g.achieved];
        await AchievementRepo.setRecord(this.currentArchiveId, nextId, true, Math.floor(Date.now() / 1000));
      }
      await this.refreshData();
    } finally {
      this.busy = false;
    }
  }

  async switchArchive(id: number): Promise<void> {
    if (id === this.currentArchiveId) {
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
        { text: '取消', color: ('app.color.text_secondary') },
        { text: '删除', color: ('app.color.danger') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index === 1) {
        AchievementRepo.deleteArchive(this.currentArchiveId).then(() => {
          this.reload();
        });
      }
    });
  }

  /** 选择文件导入 UIAF */
  async importUiaf(): Promise<void> {
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
        const result: UiafImportResult = await AchievementService.importUiaf(this.currentArchiveId, text);
        this.toast(result.ok ? result.message : `导入失败：${result.message}`);
        if (result.ok) {
          await this.refreshData();
        }
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      this.toast(`导入失败：${(e as Error).message}`);
    }
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
            }, (g: DisplayGroup) => `g_${g.ids[0]}_${g.achieved}`)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
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
        Button('导入 UIAF')
          .fontSize(12)
          .height(30)
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

      // 档案切换 + 档案管理
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.archives, (a: AchievementArchive) => {
            Text(a.name)
              .fontSize(12)
              .fontColor(a.id === this.currentArchiveId ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(a.id === this.currentArchiveId ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
              .border({ width: 1, color: a.id === this.currentArchiveId ? $r('app.color.app_primary') : $r('app.color.divider') })
              .onClick(() => {
                this.switchArchive(a.id);
              })
          }, (a: AchievementArchive) => `ach_${a.id}_${a.id === this.currentArchiveId}`)
          Text('＋ 新建档案')
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })
            .onClick(() => {
              this.showCreate = !this.showCreate;
            })
          Text('删除当前')
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })
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
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  statusChip(label: string, value: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.statusFilter === value ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.statusFilter === value ? $r('app.color.app_primary_bg') : Color.Transparent)
      .borderRadius(10)
      .onClick(() => {
        this.statusFilter = value;
        this.rebuildGroups();
      })
  }

  @Builder
  filterRow() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索成就名称/描述' })
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
        }
        .borderRadius(10)
        .backgroundColor($r('app.color.card_background'))
      }
      .width('100%')
      // 分类筛选（横向滚动 chips）
      Scroll() {
        Row({ space: 8 }) {
          Text('全部分类')
            .fontSize(12)
            .fontColor(this.categoryFilter === -1 ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(this.categoryFilter === -1 ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
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
              .backgroundColor(this.categoryFilter === cs.category.id ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
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

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(g.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(g.achieved >= g.total ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
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
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .opacity(g.achieved >= g.total ? 0.75 : 1)
    .onClick(() => {
      this.tapGroup(g);
    })
  }
}
