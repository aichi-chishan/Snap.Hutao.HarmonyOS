import { common } from '@kit.AbilityKit';
import { ShowDialogSuccessResponse } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BackpackArchive, BackpackImport, BackpackItem, BackpackManualInput } from '../model/BackpackData';
import { BackpackCatalog } from '../model/BackpackCatalog';
import { BackpackViewModel } from '../viewmodel/BackpackViewModel';
import { UIIFService } from '../service/UIIFService';
import { CultivateProject } from '../data/repo/CultivationRepo';
import { AppBackButton } from '../components/AppBackButton';
import { PageBackdrop } from '../components/PageBackdrop';
import { EmptyState } from '../components/EmptyState';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { BackpackScoreEdit, BackpackScoreProfile, BackpackScoring, BackpackSubStat } from '../model/BackpackScore';

@Entry
@Component
export struct BackpackPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State vm: BackpackViewModel = new BackpackViewModel();
  @State busy: boolean = false;
  @State isWide: boolean = false;
  @State keyword: string = '';
  @State categoryIndex: number = 0;
  @State sortIndex: number = 0;
  @State lockedOnly: boolean = false;
  @State selected: BackpackItem | undefined = undefined;
  @State showSheet: boolean = false;
  @State sheetMode: string = '';
  @State newName: string = '';
  @State newUid: string = '';
  @State manualKind: number = 0;
  @State manualId: string = '';
  @State manualCount: string = '1';
  @State manualLevel: string = '1';
  @State manualPromote: string = '0';
  @State manualAffix: string = '';
  @State manualRank: string = '0';
  @State manualMain: string = '';
  @State manualAppend: string = '';
  @State projectIndex: number = 0;
  @State replaceMaterials: boolean = false;
  @State editCount: string = '';
  @State scoreDraft: BackpackScoreProfile = new BackpackScoreProfile();
  private scoreEdit: BackpackScoreEdit | undefined = undefined;
  private source: SimpleDataSource<BackpackItem> = new SimpleDataSource<BackpackItem>([]);
  private searchTimer: number = -1;
  private attached: boolean = false;

  aboutToAppear(): void { this.attached = true; this.vm.activate(); this.reload(); }
  aboutToDisappear(): void {
    this.attached = false;
    this.vm.invalidate();
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); this.searchTimer = -1; }
  }

  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message: message, duration: 2400 }); }
  private available(): boolean { return !this.busy && !this.vm.loading; }
  private refreshList(): void {
    this.source.notifyDataReload(this.vm.items);
    this.selected = undefined;
  }
  private async reload(): Promise<void> { await this.vm.load(); if (this.attached) { this.refreshList(); } }
  private async selectArchive(index: number): Promise<void> {
    if (!this.available() || this.vm.archives[index] === undefined) { return; }
    this.busy = true;
    try { await this.vm.select(this.vm.archives[index].id); this.refreshList(); }
    catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }
  private options(names: string[]): SelectOption[] {
    return names.map((name: string): SelectOption => { const option: SelectOption = { value: name }; return option; });
  }
  private archiveOptions(): SelectOption[] {
    return this.options(this.vm.archives.map((archive: BackpackArchive): string => `${archive.name} · ${archive.uid}`));
  }
  private archiveIndex(): number { return this.vm.archives.findIndex((archive: BackpackArchive): boolean => archive.id === this.vm.currentId); }
  private title(): string {
    const archive: BackpackArchive | undefined = this.vm.currentArchive();
    return archive === undefined ? '选择或创建离线档案' : `${archive.name} · UID ${archive.uid}`;
  }
  private openSheet(mode: string): void { this.sheetMode = mode; this.showSheet = true; }
  private openScore(): void {
    if (!this.available()) { return; }
    try {
      this.scoreEdit = this.vm.beginScoreEdit();
      this.scoreDraft = BackpackScoreProfile.clone(this.scoreEdit.profile);
      this.openSheet('score');
    } catch (e) { this.toast((e as Error).message); }
  }
  private choosePreset(preset: number): void {
    const next: BackpackScoreProfile = BackpackScoreProfile.create(preset);
    next.id = this.scoreDraft.id;
    this.scoreDraft = next;
  }
  private changeWeight(index: number, value: number): void {
    const next: BackpackScoreProfile = BackpackScoreProfile.clone(this.scoreDraft);
    next.weights[index] = Math.round(value * 10) / 10;
    next.preset = 5;
    this.scoreDraft = next;
  }
  private saveScore(): void {
    if (!this.available() || this.scoreEdit === undefined) { return; }
    try {
      this.vm.saveScore(this.scoreEdit, this.scoreDraft);
      this.showSheet = false; this.scoreEdit = undefined; this.refreshList();
      this.toast('评分配置已应用');
    } catch (e) { this.toast((e as Error).message); }
  }
  private async deleteScore(): Promise<void> {
    const edit: BackpackScoreEdit | undefined = this.scoreEdit;
    const id: string = this.scoreDraft.id;
    if (!this.available() || edit === undefined || id.length === 0) { return; }
    this.busy = true;
    try {
      if (!await this.confirm('删除评分配置', `删除「${this.scoreDraft.name}」？删除活动配置后恢复默认评分，物品原始数据不变。`, '删除配置')) { return; }
      this.vm.deleteScore(edit, id);
      this.showSheet = false; this.scoreEdit = undefined; this.refreshList();
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }

  private applyFilters(): void {
    this.vm.filter.keyword = this.keyword;
    this.vm.filter.category = this.categoryIndex - 1;
    this.vm.filter.lockedOnly = this.lockedOnly;
    this.vm.filter.sort = ['id', 'name', 'rarity', 'level', 'count', 'score'][this.sortIndex];
    this.vm.applyFilter();
    this.source.notifyDataReload(this.vm.items);
  }
  private search(value: string): void {
    this.keyword = value;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout(() => { this.searchTimer = -1; this.applyFilters(); }, 180);
  }
  private async confirm(title: string, message: string, action: string): Promise<boolean> {
    if (!this.attached) { return false; }
    const result: ShowDialogSuccessResponse = await this.getUIContext().getPromptAction().showDialog({
      title: title, message: message,
      buttons: [{ text: '取消', color: $r('app.color.text_secondary') }, { text: action, color: $r('app.color.app_primary') }],
    });
    return result.index === 1 && this.attached;
  }
  private async createArchive(): Promise<void> {
    if (!this.available()) { return; }
    this.busy = true;
    try {
      await this.vm.create(this.newName, this.newUid.trim());
      this.newName = ''; this.newUid = ''; this.showSheet = false; this.refreshList();
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }
  private async deleteArchive(): Promise<void> {
    const archive: BackpackArchive | undefined = this.vm.currentArchive();
    if (!this.available() || archive === undefined) { return; }
    this.busy = true;
    try {
      if (!await this.confirm('删除背包档案', `删除「${archive.name}」(UID ${archive.uid}) 的全部物品？此操作无法撤销，请先导出或备份。`, '删除档案')) { return; }
      await this.vm.remove(archive.id); this.refreshList();
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }
  private async importFile(): Promise<void> {
    const archive: BackpackArchive | undefined = this.vm.currentArchive();
    if (!this.available() || archive === undefined) { return; }
    this.busy = true;
    try {
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) { throw new Error('页面尚未就绪'); }
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1; options.fileSuffixFilters = ['UIIF JSON|.json'];
      const paths: string[] = await documentPicker.select(options);
      if (paths.length === 0 || !this.attached) { return; }
      const file: fileIo.File = await fileIo.open(paths[0], fileIo.OpenMode.READ_ONLY);
      let text: string = '';
      try {
        const size: number = (await fileIo.stat(file.fd)).size;
        if (size < 1 || size > UIIFService.MAX_FILE_BYTES) { throw new Error('文件为空或超过 16 MiB'); }
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        const read: number = await fileIo.read(file.fd, buffer);
        if (read !== size) { throw new Error('文件未完整读取，请重新选择'); }
        text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(buffer));
      } finally { await fileIo.close(file.fd); }
      const prepared: BackpackImport = await this.vm.prepare(text);
      if (prepared.uid.length > 0 && prepared.uid !== archive.uid) { throw new Error('文件 UID 与当前档案不符，请切换或创建正确的档案'); }
      const origin: string = prepared.uid.length === 0 ? '文件未提供 UID，请确认属于此档案。' : `文件 UID：${prepared.uid}`;
      if (!await this.confirm('预览 UIIF 导入', `${archive.name} · UID ${archive.uid}\n${origin}\n武器 ${prepared.weaponCount} · 圣遗物 ${prepared.reliquaryCount}\n材料 ${prepared.materialCount} · 摆设 ${prepared.furnitureCount}\n将替换当前档案的 ${this.vm.allItems.length} 项，重复装备会保留为独立实例。缺失的锁定状态保持未知。`, '替换此档案')) { return; }
      await this.vm.importSnapshot(archive.id, prepared); this.refreshList();
      this.toast(`已保存 ${prepared.items.length} 项至 ${archive.name}`);
    } catch (e) { if (this.attached) { this.toast((e as Error).message); } }
    finally { this.busy = false; }
  }
  private async exportFile(): Promise<void> {
    const archive: BackpackArchive | undefined = this.vm.currentArchive();
    if (!this.available() || archive === undefined) { return; }
    this.busy = true;
    try {
      const text: string = await this.vm.exportArchive(archive.id);
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined || !this.attached) { return; }
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`UIIF_${archive.uid}_${Date.now()}.json`];
      const paths: string[] = await documentPicker.save(options);
      if (paths.length === 0 || !this.attached) { return; }
      const file: fileIo.File = await fileIo.open(paths[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        const bytes: Uint8Array = new util.TextEncoder().encodeInto(text);
        const written: number = await fileIo.write(file.fd, bytes.buffer);
        if (written !== bytes.length) { throw new Error('文件未完整写入，请重新导出'); }
      } finally { await fileIo.close(file.fd); }
      this.toast('UIIF 已导出，原始字段与装备实例均已保留');
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }
  private async saveManual(): Promise<void> {
    if (!this.available()) { return; }
    const input: BackpackManualInput = new BackpackManualInput();
    input.itemId = this.manualId; input.kind = ['material', 'weapon', 'reliquary', 'furniture'][this.manualKind];
    input.count = this.manualCount; input.level = this.manualLevel; input.promoteLevel = this.manualPromote;
    input.affixId = this.manualAffix; input.affixLevel = this.manualRank; input.mainPropId = this.manualMain; input.appendPropIds = this.manualAppend;
    this.busy = true;
    try { await this.vm.addManual(input); this.showSheet = false; this.manualId = ''; this.refreshList(); }
    catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }
  private async syncMaterials(): Promise<void> {
    const archive: BackpackArchive | undefined = this.vm.currentArchive();
    const project: CultivateProject | undefined = this.vm.projects[this.projectIndex];
    if (!this.available() || archive === undefined || project === undefined) { return; }
    this.busy = true;
    try {
      const verb: string = this.replaceMaterials ? '替换' : '合并';
      const hint: string = this.replaceMaterials ? '项目中未出现在此背包的库存数量将被移除。' : '只更新背包中出现的材料；其他材料数量保留。';
      if (!await this.confirm(`${verb}材料库存`, `来源：${archive.name} · UID ${archive.uid}\n目标：${project.name}\n${hint}\n装备和摆设不计入材料库存。`, `${verb}库存`)) { return; }
      const count: number = await this.vm.syncMaterials(archive.id, project.id, this.replaceMaterials);
      this.showSheet = false; this.toast(`已向「${project.name}」同步 ${count} 种材料`);
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }

  private async saveCount(): Promise<void> {
    const item: BackpackItem | undefined = this.selected;
    if (!this.available() || item === undefined) { return; }
    this.busy = true;
    try {
      await this.vm.updateCount(item.instanceId, this.editCount);
      this.refreshList(); this.selected = this.vm.items.find((entry: BackpackItem): boolean => entry.instanceId === item.instanceId);
      this.toast('数量已保存');
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }

  private async removeItem(): Promise<void> {
    const item: BackpackItem | undefined = this.selected;
    if (!this.available() || item === undefined) { return; }
    this.busy = true;
    try {
      if (!await this.confirm('移除物品记录', `仅从「${this.title()}」移除 ${item.name}（${item.instanceId}）？此操作无法撤销。`, '移除此项')) { return; }
      await this.vm.removeItem(item.instanceId); this.refreshList(); this.showSheet = false;
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }

  private async categorize(index: number): Promise<void> {
    const item: BackpackItem | undefined = this.selected;
    if (!this.available() || item === undefined) { return; }
    this.busy = true;
    try {
      await this.vm.categorize(item.instanceId, [2, 3, 4, 5, 6, 7, 9][index]);
      this.refreshList(); this.selected = this.vm.allItems.find((entry: BackpackItem): boolean => entry.instanceId === item.instanceId);
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }

  @Builder
  header() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if (!this.embedMode) { AppBackButton() }
        Text('背包档案').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Blank()
        Button('新建').height(44).hoverEffect(HoverEffect.Highlight).enabled(this.available()).onClick(() => this.openSheet('create'))
      }.width('100%')
      if (this.vm.archives.length > 0) {
        Select(this.archiveOptions()).selected(this.archiveIndex()).value(this.title()).width('100%')
          .enabled(this.available()).onSelect((index: number) => { this.selectArchive(index); })
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('导入 UIIF').height(44).margin({ right: 8, bottom: 6 }).hoverEffect(HoverEffect.Highlight).onClick(() => this.importFile())
          Button('导出').height(44).margin({ right: 8, bottom: 6 }).hoverEffect(HoverEffect.Highlight).onClick(() => this.exportFile())
          Button('手动添加').height(44).margin({ right: 8, bottom: 6 }).hoverEffect(HoverEffect.Highlight).onClick(() => this.openSheet('manual'))
          Button('同步养成库存').height(44).margin({ right: 8, bottom: 6 }).hoverEffect(HoverEffect.Highlight).onClick(() => this.openSheet('sync'))
          Button('评分设置').height(44).margin({ right: 8, bottom: 6 }).hoverEffect(HoverEffect.Highlight).onClick(() => this.openScore())
          Button('删除档案').height(44).margin({ bottom: 6 }).hoverEffect(HoverEffect.Highlight).onClick(() => this.deleteArchive())
        }.enabled(this.available())
      }
      Text('离线文件与手动记录 · 不读取游戏内存 · UIIF 缺失字段显示为未知')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }.padding({ left: 16, right: 16, top: (this.embedMode ? 0 : this.topAvoidVp) + 12, bottom: 10 })
  }

  @Builder
  filters() {
    Column({ space: 8 }) {
      Search({ value: this.keyword, placeholder: '搜索名称、物品 ID 或实例 ID' }).onChange((value: string) => this.search(value))
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Select(this.options(['全部分类'].concat(BackpackCatalog.CATEGORY_NAMES))).selected(this.categoryIndex)
          .value(this.categoryIndex === 0 ? '全部分类' : BackpackCatalog.CATEGORY_NAMES[this.categoryIndex - 1])
          .margin({ right: 8, bottom: 6 }).onSelect((index: number) => { this.categoryIndex = index; this.applyFilters(); })
        Select(this.options(['物品 ID', '名称', '品质', '等级', '数量', '圣遗物评分'])).selected(this.sortIndex)
          .value(['物品 ID', '名称', '品质', '等级', '数量', '圣遗物评分'][this.sortIndex])
          .margin({ right: 8, bottom: 6 }).onSelect((index: number) => { this.sortIndex = index; this.applyFilters(); })
        Row({ space: 4 }) {
          Checkbox({ name: 'locked' }).select(this.lockedOnly).onChange((value: boolean) => { this.lockedOnly = value; this.applyFilters(); })
          Text('仅已知锁定').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }
      if (this.vm.scoreSettings.warning.length > 0) {
        Text(this.vm.scoreSettings.warning).fontSize(12).fontColor($r('app.color.danger')).width('100%')
      }
      Text(`${this.vm.items.length} / ${this.vm.allItems.length} 项 · 未识别物品保留原始 ID 与数据`)
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }.padding({ left: 16, right: 16, bottom: 10 })
  }

  @Builder
  itemRow(item: BackpackItem) {
    Row({ space: 12 }) {
      MetaIcon({ category: item.iconCategory, name: item.icon, iconSize: 44, remoteFallback: false })
      Column({ space: 5 }) {
        Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.kind === 'reliquary') {
          Text(BackpackScoring.label(item.score)).fontSize(12).fontColor($r('app.color.app_primary')).maxLines(2)
        }
        Text(BackpackCatalog.detail(item)).fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(2)
        Text(`${BackpackCatalog.CATEGORY_NAMES[item.category]} · #${item.itemId}${item.isLocked === true ? ' · 已锁定' : ''}`)
          .fontSize(11).fontColor($r('app.color.text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(24).fontColor($r('app.color.text_secondary')).accessibilityLevel('no')
    }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.card_surface'))
      .border({ width: 1, color: $r('app.color.card_stroke') }).hoverEffect(HoverEffect.Highlight)
      .focusable(true).enabled(this.available()).onClick(() => { this.selected = item; this.editCount = String(item.count); if (!this.isWide) { this.openSheet('details'); } })
      .accessibilityText(`${item.name}，${BackpackCatalog.detail(item)}，查看详情`)
  }

  @Builder
  details() {
    if (this.selected !== undefined) {
      Column({ space: 12 }) {
        Text(this.selected.name).fontSize(21).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text(BackpackCatalog.detail(this.selected)).fontSize(14).fontColor($r('app.color.text_primary'))
        Text(`物品 ID：${this.selected.itemId}\n本地实例：${this.selected.instanceId}\n游戏 GUID：${this.selected.guid || '文件未提供'}\n锁定：${this.selected.isLocked === undefined ? '未知' : this.selected.isLocked ? '是' : '否'}\n标记：${this.selected.isMarked === undefined ? '未知' : this.selected.isMarked ? '是' : '否'}`)
          .fontSize(13).fontColor($r('app.color.text_secondary')).copyOption(CopyOptions.InApp)
        if (this.selected.kind === 'reliquary') {
          Text(`副词条原始 ID（含重复强化记录）：\n${this.selected.appendPropIds.length > 0 ? this.selected.appendPropIds.join('、') : '无记录'}`)
            .fontSize(13).fontColor($r('app.color.text_secondary'))
          Text(BackpackScoring.label(this.selected.score)).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.app_primary'))
          ForEach(this.selected.score.stats, (stat: BackpackSubStat) => {
            Text(BackpackScoring.statLabel(stat)).fontSize(13).fontColor($r('app.color.text_primary'))
          }, (stat: BackpackSubStat) => `${stat.property}:${stat.rawValue}:${stat.rolls}`)
          Text('原始等级减 1 为显示等级。背包评分使用独立预设，仅计算副词条；未识别的词条会使评分不可用。')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        if (this.selected.kind === 'material' || this.selected.kind === 'furniture') {
          Row({ space: 8 }) {
            TextInput({ text: this.editCount, placeholder: '数量' }).type(InputType.Number).layoutWeight(1).onChange((value: string) => this.editCount = value)
            Button('保存数量').height(44).enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.saveCount())
          }
        }
        if (this.selected.kind === 'material') {
          Text('本地分类（随应用备份保留）').fontSize(12).fontColor($r('app.color.text_secondary'))
          Select(this.options(['养成道具', '食物', '材料', '小道具', '任务', '贵重道具', '恢复自动分类']))
            .value(BackpackCatalog.CATEGORY_NAMES[this.selected.category]).enabled(this.available())
            .onSelect((index: number) => this.categorize(index))
        }
        Button('移除此项记录').height(44).enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.removeItem())
        Text('原始 UIIF 条目').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.selected.rawJson.substring(0, 4000)).fontSize(12).fontFamily('monospace').fontColor($r('app.color.text_secondary')).copyOption(CopyOptions.InApp)
        if (this.selected.rawJson.length > 4000) {
          Text('预览仅显示前 4000 字符，导出文件保留完整原始内容。').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
    } else { EmptyState({ text: '选择物品查看装备详情与原始记录' }) }
  }

  @Builder
  scoreWeight(index: number) {
    Row({ space: 10 }) {
      Text(BackpackScoreProfile.LABELS[index]).fontSize(13).fontColor($r('app.color.text_primary')).width(100)
      Slider({ value: this.scoreDraft.weights[index], min: 0, max: 1, step: 0.1 }).layoutWeight(1)
        .enabled(this.available()).onChange((value: number) => this.changeWeight(index, value))
      Text(this.scoreDraft.weights[index].toFixed(1)).fontSize(13).fontColor($r('app.color.text_secondary')).width(30)
    }.width('100%')
  }

  @Builder
  scoreEditor() {
    Column({ space: 12 }) {
      Text('圣遗物评分配置').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text('所有背包共用活动配置，与角色推荐评分分开。取消不会保存改动。').fontSize(12).fontColor($r('app.color.text_secondary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach([0, 1, 2, 3, 4], (preset: number) => {
          Button(BackpackScoreProfile.PRESETS[preset]).height(44).margin({ right: 8, bottom: 6 })
            .enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.choosePreset(preset))
        }, (preset: number) => `${preset}`)
      }
      if (this.vm.scoreSettings.profiles.length > 0) {
        Select(this.options(this.vm.scoreSettings.profiles.map((profile: BackpackScoreProfile): string => profile.name)))
          .value(this.scoreDraft.name).enabled(this.available()).onSelect((index: number) => {
            this.scoreDraft = BackpackScoreProfile.clone(this.vm.scoreSettings.profiles[index]);
          })
      }
      TextInput({ text: this.scoreDraft.name, placeholder: '配置名称' }).maxLength(80).enabled(this.available())
        .onChange((value: string) => {
          const next: BackpackScoreProfile = BackpackScoreProfile.clone(this.scoreDraft);
          next.name = value; this.scoreDraft = next;
        })
      this.scoreWeight(0)
      this.scoreWeight(1)
      this.scoreWeight(2)
      this.scoreWeight(3)
      this.scoreWeight(4)
      this.scoreWeight(5)
      this.scoreWeight(6)
      Text('固定生命、攻击、防御不计分。权重 0 表示不计入该项；合法零分仍会显示。').fontSize(12).fontColor($r('app.color.text_secondary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        Button('另存为新配置').height(44).margin({ right: 8, bottom: 6 }).enabled(this.available()).hoverEffect(HoverEffect.Highlight)
          .onClick(() => { const next: BackpackScoreProfile = BackpackScoreProfile.clone(this.scoreDraft); next.id = ''; this.scoreDraft = next; })
        if (this.scoreDraft.id.length > 0) {
          Button('删除当前配置').height(44).margin({ right: 8, bottom: 6 }).enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.deleteScore())
        }
        Button('应用并保存').height(44).enabled(this.available() && this.vm.scoreSettings.warning.length === 0)
          .hoverEffect(HoverEffect.Highlight).onClick(() => this.saveScore())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  sheetContent() {
    Scroll() {
      Column({ space: 14 }) {
        if (this.sheetMode === 'score') {
          this.scoreEditor()
        } else if (this.sheetMode === 'create') {
          Text('创建离线背包档案').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('UID 由你明确指定，不需要登录；同一 UID 可以保留不同时间的快照。').fontSize(13).fontColor($r('app.color.text_secondary'))
          TextInput({ text: this.newName, placeholder: '档案名称，例如 主号 · 10 月背包' }).maxLength(80).onChange((value: string) => this.newName = value)
          TextInput({ text: this.newUid, placeholder: '9 或 10 位游戏 UID' }).type(InputType.Number).maxLength(10).onChange((value: string) => this.newUid = value)
          Button('创建档案').height(44).width('100%').enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.createArchive())
        } else if (this.sheetMode === 'manual') {
          Text('手动添加物品').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Select(this.options(['材料', '武器', '圣遗物', '摆设'])).selected(this.manualKind).value(['材料', '武器', '圣遗物', '摆设'][this.manualKind])
            .onSelect((index: number) => this.manualKind = index)
          TextInput({ text: this.manualId, placeholder: '物品 ID' }).type(InputType.Number).onChange((value: string) => this.manualId = value)
          if (this.manualKind === 0 || this.manualKind === 3) {
            TextInput({ text: this.manualCount, placeholder: '数量，0 表示已确认没有' }).type(InputType.Number).onChange((value: string) => this.manualCount = value)
          } else {
            Text(this.manualKind === 2 ? 'UIIF 原始等级：1 = +0，21 = +20' : '武器等级与突破等级').fontSize(12).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.manualLevel, placeholder: '等级' }).type(InputType.Number).onChange((value: string) => this.manualLevel = value)
            if (this.manualKind === 1) {
              TextInput({ text: this.manualPromote, placeholder: '突破等级' }).type(InputType.Number).onChange((value: string) => this.manualPromote = value)
              TextInput({ text: this.manualAffix, placeholder: '精炼词条 ID（可不填）' }).type(InputType.Number).onChange((value: string) => this.manualAffix = value)
              Text('精炼索引：0 = 1 阶，4 = 5 阶').fontSize(12).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.manualRank, placeholder: '精炼索引' }).type(InputType.Number).onChange((value: string) => this.manualRank = value)
            } else {
              TextInput({ text: this.manualMain, placeholder: '主词条 ID' }).type(InputType.Number).onChange((value: string) => this.manualMain = value)
              TextInput({ text: this.manualAppend, placeholder: '副词条 ID，以逗号或空格分隔，可留空' }).onChange((value: string) => this.manualAppend = value)
            }
          }
          Text('不会推测 GUID、锁定或词条数值。同一物品 ID 的装备会保留为不同实例。').fontSize(12).fontColor($r('app.color.text_secondary'))
          Button('添加物品').height(44).width('100%').enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.saveManual())
        } else if (this.sheetMode === 'sync') {
          Text('同步材料到养成项目').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.title()).fontSize(13).fontColor($r('app.color.text_secondary'))
          if (this.vm.projects.length === 0) {
            EmptyState({ text: '暂无养成项目，请先在养成计算中创建项目' })
          } else {
            Select(this.options(this.vm.projects.map((project: CultivateProject): string => project.name))).selected(this.projectIndex)
              .value(this.vm.projects[this.projectIndex]?.name ?? '选择项目').onSelect((index: number) => this.projectIndex = index)
            Row({ space: 8 }) {
              Checkbox({ name: 'replace' }).select(this.replaceMaterials).onChange((value: boolean) => this.replaceMaterials = value)
              Text('替换项目库存（默认合并）').fontSize(14).fontColor($r('app.color.text_primary'))
            }
            Text('合并只更新此背包中明确给出的材料数量。替换会移除目标项目里未出现的库存记录。').fontSize(13).fontColor($r('app.color.text_secondary'))
            Button('预览并同步').height(44).width('100%').enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.syncMaterials())
          }
        } else { this.details() }
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
        this.header()
        if (this.vm.message.length > 0) {
          Text(this.vm.message).fontColor($r('app.color.danger')).padding(12)
          Button('重试').height(44).enabled(this.available()).hoverEffect(HoverEffect.Highlight).onClick(() => this.reload())
        }
        if (this.vm.loading || this.busy) {
          Row({ space: 8 }) {
            LoadingProgress().width(24).height(24)
            Text('正在读取或保存…').fontSize(12).fontColor($r('app.color.text_secondary'))
          }.padding(8)
        }
        if (this.vm.archives.length === 0 && !this.vm.loading) {
          EmptyState({ text: '创建档案后，可导入 UIIF v1.0 文件或手动添加\n武器、圣遗物、材料与摆设' })
        } else {
          this.filters()
          Row({ space: 12 }) {
            if (this.vm.items.length === 0 && !this.vm.loading) {
              Column() { EmptyState({ text: this.vm.allItems.length === 0 ? '此档案还没有物品，导入文件即可开始' : '没有匹配的物品，试试其他筛选条件' }) }.layoutWeight(1)
            } else {
              List({ space: 8 }) {
                LazyForEach(this.source, (item: BackpackItem) => { ListItem() { this.itemRow(item) } },
                  (item: BackpackItem): string => `${this.vm.currentId}:${item.instanceId}:${item.count}:${item.level}:${item.category}:${item.score.available}:${item.score.value}:${this.vm.scoreSettings.revision}`)
              }.layoutWeight(1).height('100%').padding({ bottom: 24 })
            }
            if (this.isWide) {
              Scroll() { this.details() }.width(340).height('100%').backgroundColor($r('app.color.card_surface')).borderRadius(12)
            }
          }.layoutWeight(1).padding({ left: 16, right: 16, bottom: 12 }).alignItems(VerticalAlign.Top)
        }
      }.width('100%').height('100%')
    }.width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => {
        const wide: boolean = Number(area.width) >= 840;
        if (wide && !this.isWide && this.sheetMode === 'details') { this.showSheet = false; }
        this.isWide = wide;
      })
      .bindSheet($$this.showSheet, this.sheetContent(), { height: '80%', showClose: true })
  }
}
