import { common } from '@kit.AbilityKit';
import { ShowDialogSuccessResponse } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BackpackArchive, BackpackCategory, BackpackFilterChoice, BackpackFilterKind, BackpackImport, BackpackItem,
  BackpackManualInput, BackpackSortRule } from '../model/BackpackData';
import { BackpackCatalog } from '../model/BackpackCatalog';
import { BackpackViewModel } from '../viewmodel/BackpackViewModel';
import { UIIFService } from '../service/UIIFService';
import { CultivateProject } from '../data/repo/CultivationRepo';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { EmptyState } from '../components/EmptyState';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { ReliquaryScoreEditor } from '../components/ReliquaryScoreEditor';
import { BackpackScoreEdit, BackpackScoreProfile, BackpackScoring, BackpackSubStat } from '../model/BackpackScore';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, SelectMaterialModifier, UiSurface } from '../common/UiSurface';
import { WikiMetaService } from '../service/WikiMetaService';

@Component
struct BackpackFilterSelect {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop labels: ResourceStr[] = [];
  onChoose: (index: number) => void = () => {};

  build() {
    Select(this.labels.map((label: ResourceStr): SelectOption => ({ value: label })))
      .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
      .selected(0).value(this.labels[0]).width('100%')
      .onSelect((index: number) => this.onChoose(index))
  }
}

@Entry
@Component
export struct BackpackPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('localeChanged') localeVersion: number = 0;
  @State vm: BackpackViewModel = new BackpackViewModel();
  @State busy: boolean = false;
  @State isWide: boolean = false;
  @State keyword: string = '';
  @State categoryIndex: number = 0;
  @State filterChoices: BackpackFilterChoice[] = [];
  @State sortRules: BackpackSortRule[] = [];
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
  @State scoreEdit: BackpackScoreEdit = new BackpackScoreEdit();
  private source: SimpleDataSource<BackpackItem> = new SimpleDataSource<BackpackItem>([]);
  private searchTimer: number = -1;
  private attached: boolean = false;

  aboutToAppear(): void { this.attached = true; this.vm.activate(); this.reload(); }
  aboutToDisappear(): void {
    this.attached = false;
    this.vm.invalidate();
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); this.searchTimer = -1; }
  }

  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: message, duration: 2400 }); }
  private available(): boolean { return !this.busy && !this.vm.loading; }
  private refreshList(): void {
    this.source.notifyDataReload(this.vm.items);
    this.selected = undefined;
  }
  private async reload(): Promise<void> { await this.vm.load(); if (this.attached) { this.refreshList(); } }
  private async refreshLocalizedItems(): Promise<void> {
    if (!this.attached) { return; }
    const refreshed: boolean = await this.vm.refreshDisplay();
    if (!refreshed || !this.attached) { return; }
    const selected: BackpackItem | undefined = this.selected;
    if (selected !== undefined) {
      this.selected = this.vm.allItems.find((item: BackpackItem): boolean =>
        item.archiveId === selected.archiveId && item.instanceId === selected.instanceId && item.rawJson === selected.rawJson);
      if (this.selected === undefined && this.sheetMode === 'details') { this.showSheet = false; }
    }
    const sets: Map<number, string> = new Map<number, string>();
    for (const item of this.vm.allItems) { if (item.setId > 0) { sets.set(item.setId, item.setName); } }
    this.filterChoices = this.filterChoices.map((choice: BackpackFilterChoice): BackpackFilterChoice =>
      choice.kind === BackpackFilterKind.Set ? new BackpackFilterChoice(choice.kind, choice.code, sets.get(choice.code) ?? choice.label) : choice);
    this.vm.filter.choices = this.filterChoices;
    this.source.notifyDataReload(this.vm.items);
  }
  private localeChanged(): void { this.refreshLocalizedItems(); }
  private async selectArchive(index: number): Promise<void> {
    if (!this.available() || this.vm.archives[index] === undefined) { return; }
    this.busy = true;
    try { await this.vm.select(this.vm.archives[index].id); this.refreshList(); }
    catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }
  private options(names: ResourceStr[]): SelectOption[] {
    return names.map((name: ResourceStr): SelectOption => { const option: SelectOption = { value: name }; return option; });
  }
  private categoryLabel(category: number): ResourceStr {
    if (category === BackpackCategory.Weapon) { return $r('app.string.ui_backpack_category_weapon'); }
    if (category === BackpackCategory.Reliquary) { return $r('app.string.ui_backpack_category_reliquary'); }
    return category < 0 ? '全部分类' : BackpackCatalog.CATEGORY_NAMES[category];
  }
  private categoryLabels(): ResourceStr[] {
    const labels: ResourceStr[] = [];
    for (let category: number = -1; category < BackpackCatalog.CATEGORY_NAMES.length; category++) {
      labels.push(this.categoryLabel(category));
    }
    return labels;
  }
  private manualKindLabels(): ResourceStr[] {
    return ['材料', this.categoryLabel(BackpackCategory.Weapon), this.categoryLabel(BackpackCategory.Reliquary), '摆设'];
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
      this.openSheet('score');
    } catch (e) { this.toast((e as Error).message); }
  }
  private saveScore(profile: BackpackScoreProfile, deletedIds: string[]): void {
    if (!this.available()) { return; }
    try {
      this.vm.saveScore(this.scoreEdit, profile, deletedIds);
      this.showSheet = false;
      this.refreshList();
      this.toast('评分配置已应用');
    } catch (e) { this.toast((e as Error).message); }
  }

  private availableSortKeys(): string[] {
    return BackpackCatalog.sortKeys(this.categoryIndex - 1)
      .filter((key: string): boolean => !this.sortRules.some((rule: BackpackSortRule): boolean => rule.key === key));
  }

  private sortLabel(key: string): ResourceStr {
    switch (key) {
      case 'rarity': return $r('app.string.ui_backpack_sort_quality');
      case 'level': return $r('app.string.ui_base_value_slider_level');
      case 'count': return $r('app.string.ui_backpack_sort_count');
      default: return BackpackCatalog.SORT_LABELS[key];
    }
  }

  private sortLabels(): ResourceStr[] {
    const labels: ResourceStr[] = ['添加排序条件'];
    for (const key of this.availableSortKeys()) { labels.push(this.sortLabel(key)); }
    return labels;
  }

  private setOptions(): BackpackItem[] {
    const sets: Map<number, BackpackItem> = new Map<number, BackpackItem>();
    for (const item of this.vm.allItems) {
      if (item.setId > 0 && item.setName.length > 0) { sets.set(item.setId, item); }
    }
    return Array.from(sets.values()).sort((left: BackpackItem, right: BackpackItem): number => left.setId - right.setId);
  }

  private numberedFilterChoices(kind: BackpackFilterKind, labels: string[], firstCode: number = 0): BackpackFilterChoice[] {
    return labels.map((label: string, index: number): BackpackFilterChoice => new BackpackFilterChoice(kind, firstCode + index, label));
  }

  private allFilterChoices(kind: BackpackFilterKind): BackpackFilterChoice[] {
    switch (kind) {
      case BackpackFilterKind.Rarity: return this.numberedFilterChoices(kind, ['一星', '二星', '三星', '四星', '五星'], 1);
      case BackpackFilterKind.WeaponType:
        return BackpackCatalog.WEAPON_TYPES.slice(1).map((type: number): BackpackFilterChoice =>
          new BackpackFilterChoice(kind, type, WikiMetaService.weaponTypeName(type)));
      case BackpackFilterKind.EquipType: return this.numberedFilterChoices(kind, BackpackCatalog.RELIC_SLOTS.slice(1), 1);
      case BackpackFilterKind.Set:
        return this.setOptions().map((item: BackpackItem): BackpackFilterChoice => new BackpackFilterChoice(kind, item.setId, item.setName));
      case BackpackFilterKind.FoodType: return this.numberedFilterChoices(kind, ['恢复类', '攻击类', '冒险类', '防御类'], 1);
      case BackpackFilterKind.FoodQuality: return this.numberedFilterChoices(kind, ['奇怪的', '普通', '美味的']);
      case BackpackFilterKind.Lock: return this.numberedFilterChoices(kind, ['未锁定', '已锁定', '锁定未知']);
      case BackpackFilterKind.Mark: return this.numberedFilterChoices(kind, ['未标记', '已标记', '标记未知']);
      case BackpackFilterKind.Equipped: return this.numberedFilterChoices(kind, ['未装备', '已装备', '装备状态未知']);
      case BackpackFilterKind.Purchased: return this.numberedFilterChoices(kind, ['未购定向词条', '已购定向词条', '定向词条未知']);
      default: return [];
    }
  }

  private availableFilterChoices(kind: BackpackFilterKind): BackpackFilterChoice[] {
    return this.allFilterChoices(kind).filter((choice: BackpackFilterChoice): boolean =>
      !this.filterChoices.some((selected: BackpackFilterChoice): boolean => selected.kind === choice.kind && selected.code === choice.code));
  }

  private filterLabel(choice: BackpackFilterChoice): ResourceStr {
    if (choice.kind === BackpackFilterKind.Rarity) {
      const stars: ResourceStr[] = [$r('app.string.ui_model_intrinsic_item_quality_white'),
        $r('app.string.ui_model_intrinsic_item_quality_green'), $r('app.string.ui_model_intrinsic_item_quality_blue'),
        $r('app.string.ui_model_intrinsic_item_quality_purple'), $r('app.string.ui_model_intrinsic_item_quality_orange')];
      return stars[choice.code - 1] ?? choice.label;
    }
    return choice.label;
  }

  private filterLabels(kind: BackpackFilterKind, title: ResourceStr): ResourceStr[] {
    const labels: ResourceStr[] = [title];
    for (const choice of this.availableFilterChoices(kind)) { labels.push(this.filterLabel(choice)); }
    return labels;
  }

  private chooseFilter(kind: BackpackFilterKind, index: number): void {
    const choice: BackpackFilterChoice | undefined = this.availableFilterChoices(kind)[index - 1];
    if (choice === undefined) { return; }
    this.filterChoices = this.filterChoices.concat([choice]);
    this.applyFilters();
  }

  private removeFilter(choice: BackpackFilterChoice): void {
    this.filterChoices = this.filterChoices.filter((selected: BackpackFilterChoice): boolean =>
      selected.kind !== choice.kind || selected.code !== choice.code);
    this.applyFilters();
  }

  private addSortRule(index: number): void {
    const key: string | undefined = this.availableSortKeys()[index - 1];
    if (key === undefined) { return; }
    this.sortRules = this.sortRules.concat([new BackpackSortRule(key, key !== 'id' && key !== 'name' && key !== 'set')]);
    this.applyFilters();
  }

  private changeSortRule(key: string, remove: boolean): void {
    this.sortRules = remove ? this.sortRules.filter((rule: BackpackSortRule): boolean => rule.key !== key)
      : this.sortRules.map((rule: BackpackSortRule): BackpackSortRule =>
        rule.key === key ? new BackpackSortRule(key, !rule.descending) : rule);
    this.applyFilters();
  }

  private selectCategory(index: number): void {
    this.categoryIndex = index;
    this.filterChoices = [];
    this.sortRules = [];
    this.applyFilters();
  }

  private applyFilters(): void {
    this.vm.filter.keyword = this.keyword;
    this.vm.filter.category = this.categoryIndex - 1;
    this.vm.filter.choices = this.filterChoices;
    this.vm.filter.sortRules = this.sortRules;
    this.vm.applyFilter();
    const selected: BackpackItem | undefined = this.selected;
    if (selected !== undefined && !this.vm.items.some((item: BackpackItem): boolean => item.instanceId === selected.instanceId)) {
      this.selected = undefined;
    }
    this.source.notifyDataReload(this.vm.items);
  }
  private search(value: string): void {
    this.keyword = value;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout(() => { this.searchTimer = -1; this.applyFilters(); }, 180);
  }
  private async confirm(title: string, message: string, action: string): Promise<boolean> {
    if (!this.attached) { return false; }
    const result: ShowDialogSuccessResponse = await this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: title, message: message,
      buttons: [{ text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') }, { text: action, color: $r('app.color.app_primary') }],
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
      await this.vm.updateCount(item, this.editCount);
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
      await this.vm.removeItem(item); this.refreshList(); this.showSheet = false;
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }

  private async categorize(index: number): Promise<void> {
    const item: BackpackItem | undefined = this.selected;
    if (!this.available() || item === undefined) { return; }
    this.busy = true;
    try {
      await this.vm.categorize(item, [2, 3, 4, 5, 6, 7, 9][index]);
      this.refreshList(); this.selected = this.vm.allItems.find((entry: BackpackItem): boolean => entry.instanceId === item.instanceId);
    } catch (e) { this.toast((e as Error).message); }
    finally { this.busy = false; }
  }

  @Builder
  header() {
    Column({ space: 10 }) {
      PageHeader({ title: $r('app.string.ui_nav_backpack'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
        Button($r('app.string.ui_cultivation_add_project_action'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
          .enabled(this.available()).onClick(() => this.openSheet('create'))
      }
      if (this.vm.archives.length > 0) {
        Select(this.archiveOptions()).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.archiveIndex()).value(this.title()).width('100%')
          .enabled(this.available()).onSelect((index: number) => { this.selectArchive(index); })
        Flex({ wrap: FlexWrap.Wrap }) {
          Button($r('app.string.ui_action_import'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 6 }).onClick(() => this.importFile())
          Button($r('app.string.ui_action_export'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 6 }).onClick(() => this.exportFile())
          Button('手动添加', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 6 }).onClick(() => this.openSheet('manual'))
          Button('同步养成库存', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 6 }).onClick(() => this.openSheet('sync'))
          Button('评分设置', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 6 }).onClick(() => this.openScore())
          Button('删除档案', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontColor($r('app.color.danger'))
            .height(44).margin({ bottom: 6 }).onClick(() => this.deleteArchive())
        }.enabled(this.available())
      }
      Text('离线文件与手动记录 · 不读取游戏内存 · UIIF 缺失字段显示为未知')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }
  }

  @Builder
  filters() {
    Column({ space: 8 }) {
      Search({ value: this.keyword, placeholder: '搜索名称、物品 ID 或实例 ID' })
        .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .onChange((value: string) => this.search(value))
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Select(this.options(this.categoryLabels())).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.categoryIndex)
          .value(this.categoryLabel(this.categoryIndex - 1))
          .margin({ right: 8, bottom: 6 }).onSelect((index: number) => this.selectCategory(index))
        Button('筛选与排序', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44).margin({ bottom: 6 })
          .enabled(this.available()).onClick(() => this.openSheet('filters'))
      }
      if (this.vm.scoreSettings.warning.length > 0) {
        Text(this.vm.scoreSettings.warning).fontSize(12).fontColor($r('app.color.danger')).width('100%')
      }
      Text(`${this.vm.items.length} / ${this.vm.allItems.length} 项 · 未识别物品保留原始 ID 与数据`)
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }.padding({ left: 16, right: 16, bottom: 10 })
  }

  @Builder
  filterControl(kind: BackpackFilterKind, title: ResourceStr) {
    if (this.availableFilterChoices(kind).length > 0) {
      BackpackFilterSelect({ labels: this.filterLabels(kind, title),
        onChoose: (index: number) => this.chooseFilter(kind, index) })
    }
  }

  @Builder
  filterSheet() {
    Column({ space: 10 }) {
      Text($r('app.string.ui_filter')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      if (this.filterChoices.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.filterChoices, (choice: BackpackFilterChoice) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 4 }) {
                Text(this.filterLabel(choice)).fontSize(12).fontColor($r('app.color.text_primary'))
                Text('×').fontSize(12).fontColor($r('app.color.text_primary'))
              }
            }
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 6, bottom: 6 })
              .accessibilityText(`移除${choice.label}筛选`)
              .onClick(() => this.removeFilter(choice))
          }, (choice: BackpackFilterChoice): string => `${choice.kind}:${choice.code}:${choice.label}`)
        }.width('100%')
      }
      this.filterControl(BackpackFilterKind.Rarity, $r('app.string.ui_backpack_sort_quality'))
      if (this.categoryIndex === BackpackCategory.Weapon + 1) {
        this.filterControl(BackpackFilterKind.WeaponType, '按武器类型筛选')
      }
      if (this.categoryIndex === BackpackCategory.Reliquary + 1) {
        this.filterControl(BackpackFilterKind.EquipType, '按圣遗物部位筛选')
        this.filterControl(BackpackFilterKind.Set, '按套装筛选')
        this.filterControl(BackpackFilterKind.Mark, '按标记状态筛选')
        this.filterControl(BackpackFilterKind.Purchased, '按定向词条筛选')
      }
      if (this.categoryIndex === BackpackCategory.Weapon + 1 || this.categoryIndex === BackpackCategory.Reliquary + 1) {
        this.filterControl(BackpackFilterKind.Equipped, '按装备状态筛选')
      }
      if (this.categoryIndex === 0 || this.categoryIndex === BackpackCategory.Weapon + 1 || this.categoryIndex === BackpackCategory.Reliquary + 1) {
        this.filterControl(BackpackFilterKind.Lock, '按锁定状态筛选')
      }
      if (this.categoryIndex === BackpackCategory.Food + 1) {
        this.filterControl(BackpackFilterKind.FoodType, '按料理类型筛选')
        this.filterControl(BackpackFilterKind.FoodQuality, '按料理品质筛选')
      }
      Text('排序').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      ForEach(this.sortRules, (rule: BackpackSortRule) => {
        Row({ space: 8 }) {
          Text(this.sortLabel(rule.key)).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
          Button(rule.descending ? '降序' : '升序', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).fontSize(12)
            .onClick(() => this.changeSortRule(rule.key, false))
          Button('移除', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).fontSize(12)
            .onClick(() => this.changeSortRule(rule.key, true))
        }.width('100%')
      }, (rule: BackpackSortRule): string => `${rule.key}:${rule.descending}`)
      if (this.availableSortKeys().length > 0) {
        BackpackFilterSelect({ labels: this.sortLabels(),
          onChoose: (index: number) => this.addSortRule(index) })
      }
      Button('重置筛选与排序', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44).onClick(() => {
        this.filterChoices = []; this.sortRules = []; this.applyFilters();
      })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  itemRow(item: BackpackItem) {
    Row({ space: 12 }) {
      MetaIcon({ category: item.iconCategory, name: item.icon, iconSize: 44, remoteFallback: false })
      Column({ space: 5 }) {
        Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.kind === 'reliquary') {
          Text(BackpackScoring.label(item.score)).fontSize(12).fontColor($r('app.color.app_primary_text')).maxLines(2)
        }
        Text(BackpackCatalog.detail(item)).fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(2)
        Row({ space: 4 }) {
          Text(this.categoryLabel(item.category)).fontSize(11).fontColor($r('app.color.text_secondary'))
          Text(`· #${item.itemId}${item.isLocked === true ? ' · 已锁定' : ''}`).fontSize(11).fontColor($r('app.color.text_secondary'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(24).fontColor($r('app.color.text_secondary')).accessibilityLevel('no')
    }.width('100%').padding(12).borderRadius(12).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
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
        if (this.selected.setName.length > 0) {
          Text(`${this.selected.setName} · ${BackpackCatalog.RELIC_SLOTS[this.selected.equipType]}`)
            .fontSize(13).fontColor($r('app.color.text_secondary'))
        }
        if (this.selected.kind === 'weapon' || this.selected.kind === 'reliquary') {
          Row({ space: 8 }) {
            if (this.vm.equippedAvatarIcon(this.selected.equippedAvatarId).length > 0) {
              MetaIcon({ category: 'AvatarIcon', name: this.vm.equippedAvatarIcon(this.selected.equippedAvatarId),
                iconSize: 32, remoteFallback: false })
            }
            Text(this.vm.equippedAvatarLabel(this.selected.equippedAvatarId))
              .fontSize(13).fontColor($r('app.color.text_secondary'))
          }
        }
        Text(`物品 ID：${this.selected.itemId}\n本地实例：${this.selected.instanceId}\n游戏 GUID：${this.selected.guid || '文件未提供'}\n锁定：${this.selected.isLocked === undefined ? '未知' : this.selected.isLocked ? '是' : '否'}\n标记：${this.selected.isMarked === undefined ? '未知' : this.selected.isMarked ? '是' : '否'}`)
          .fontSize(13).fontColor($r('app.color.text_secondary')).copyOption(CopyOptions.InApp)
        if (this.selected.kind === 'reliquary') {
          if (this.selected.purchasedAppendPropIds === undefined || this.selected.purchasedAppendPropIds.length === 0) {
            Text(this.selected.purchasedAppendPropIds === undefined ? '定向词条未知' : '未购定向词条')
              .fontSize(13).fontColor($r('app.color.text_secondary'))
          } else {
            Text('定向词条').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.vm.purchasedStatNames(this.selected.purchasedAppendPropIds).join('、'))
              .fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          Text(`副词条原始 ID（含重复强化记录）：\n${this.selected.appendPropIds.length > 0 ? this.selected.appendPropIds.join('、') : '无记录'}`)
            .fontSize(13).fontColor($r('app.color.text_secondary'))
          Text(BackpackScoring.label(this.selected.score)).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.app_primary_text'))
          ForEach(this.selected.score.stats, (stat: BackpackSubStat) => {
            Text(BackpackScoring.statLabel(stat)).fontSize(13).fontColor($r('app.color.text_primary'))
          }, (stat: BackpackSubStat) => `${stat.property}:${stat.rawValue}:${stat.rolls}`)
          Text('原始等级减 1 为显示等级。背包评分使用独立预设，仅计算副词条；未识别的词条会使评分不可用。')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        if (this.selected.kind === 'material' || this.selected.kind === 'furniture') {
          Row({ space: 8 }) {
            TextInput({ text: this.editCount, placeholder: $r('app.string.ui_backpack_sort_count') }).type(InputType.Number)
              .layoutWeight(1).onChange((value: string) => this.editCount = value)
            Button($r('app.string.ui_action_save'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
              .height(44).enabled(this.available()).onClick(() => this.saveCount())
          }
        }
        if (this.selected.kind === 'material') {
          Text('本地分类（随应用备份保留）').fontSize(12).fontColor($r('app.color.text_secondary'))
          Select(this.options(['养成道具', '食物', '材料', '小道具', '任务', '贵重道具', '恢复自动分类'])).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
            .value(BackpackCatalog.CATEGORY_NAMES[this.selected.category]).enabled(this.available())
            .onSelect((index: number) => this.categorize(index))
        }
        Button('移除此项记录', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontColor($r('app.color.danger'))
          .height(44).enabled(this.available()).onClick(() => this.removeItem())
        Text('原始 UIIF 条目').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.selected.rawJson.substring(0, 4000)).fontSize(12).fontFamily('monospace').fontColor($r('app.color.text_secondary')).copyOption(CopyOptions.InApp)
        if (this.selected.rawJson.length > 4000) {
          Text('预览仅显示前 4000 字符，导出文件保留完整原始内容。').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
    } else { EmptyState({ text: '选择物品查看装备详情与原始记录' }) }
  }

  @Builder
  sheetContent() {
    Scroll() {
      Column({ space: 14 }) {
        if (this.sheetMode === 'score') {
          ReliquaryScoreEditor({
            initialProfile: this.scoreEdit.profile,
            savedProfiles: this.vm.scoreSettings.profiles,
            warning: this.vm.scoreSettings.warning,
            onConfirm: (profile: BackpackScoreProfile, deletedIds: string[]) => this.saveScore(profile, deletedIds),
            onCancel: () => { this.showSheet = false; }
          })
        } else if (this.sheetMode === 'filters') {
          this.filterSheet()
        } else if (this.sheetMode === 'create') {
          Text('创建离线背包档案').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('UID 由你明确指定，不需要登录；同一 UID 可以保留不同时间的快照。').fontSize(13).fontColor($r('app.color.text_secondary'))
          TextInput({ text: this.newName, placeholder: '档案名称，例如 主号 · 10 月背包' }).maxLength(80)
            .enterKeyType(EnterKeyType.Next).onChange((value: string) => this.newName = value)
          TextInput({ text: this.newUid, placeholder: '9 或 10 位游戏 UID' }).type(InputType.Number).maxLength(10)
            .enterKeyType(EnterKeyType.Done).onChange((value: string) => this.newUid = value).onSubmit(() => this.createArchive())
          Button('创建档案', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).width('100%').enabled(this.available()).onClick(() => this.createArchive())
        } else if (this.sheetMode === 'manual') {
          Text('手动添加物品').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Select(this.options(this.manualKindLabels())).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
            .selected(this.manualKind).value(this.manualKindLabels()[this.manualKind])
            .onSelect((index: number) => this.manualKind = index)
          TextInput({ text: this.manualId, placeholder: '物品 ID' }).type(InputType.Number).onChange((value: string) => this.manualId = value)
          if (this.manualKind === 0 || this.manualKind === 3) {
            TextInput({ text: this.manualCount, placeholder: '数量，0 表示已确认没有' }).type(InputType.Number)
              .enterKeyType(EnterKeyType.Done).onChange((value: string) => this.manualCount = value).onSubmit(() => this.saveManual())
          } else {
            Text(this.manualKind === 2 ? 'UIIF 原始等级：1 = +0，21 = +20' : '武器等级与突破等级').fontSize(12).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.manualLevel, placeholder: $r('app.string.ui_base_value_slider_level') })
              .type(InputType.Number).onChange((value: string) => this.manualLevel = value)
            if (this.manualKind === 1) {
              TextInput({ text: this.manualPromote, placeholder: '突破等级' }).type(InputType.Number).onChange((value: string) => this.manualPromote = value)
              TextInput({ text: this.manualAffix, placeholder: '精炼词条 ID（可不填）' }).type(InputType.Number).onChange((value: string) => this.manualAffix = value)
              Text('精炼索引：0 = 1 阶，4 = 5 阶').fontSize(12).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.manualRank, placeholder: '精炼索引' }).type(InputType.Number)
                .enterKeyType(EnterKeyType.Done).onChange((value: string) => this.manualRank = value).onSubmit(() => this.saveManual())
            } else {
              TextInput({ text: this.manualMain, placeholder: '主词条 ID' }).type(InputType.Number).onChange((value: string) => this.manualMain = value)
              TextInput({ text: this.manualAppend, placeholder: '副词条 ID，以逗号或空格分隔，可留空' })
              .enterKeyType(EnterKeyType.Done).onChange((value: string) => this.manualAppend = value).onSubmit(() => this.saveManual())
            }
          }
          Text('不会推测 GUID、锁定或词条数值。同一物品 ID 的装备会保留为不同实例。').fontSize(12).fontColor($r('app.color.text_secondary'))
          Button('添加物品', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).width('100%').enabled(this.available()).onClick(() => this.saveManual())
        } else if (this.sheetMode === 'sync') {
          Text('同步材料到养成项目').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.title()).fontSize(13).fontColor($r('app.color.text_secondary'))
          if (this.vm.projects.length === 0) {
            EmptyState({ text: '暂无养成项目，请先在养成计算中创建项目' })
          } else {
            Select(this.options(this.vm.projects.map((project: CultivateProject): string => project.name))).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.projectIndex)
              .value(this.vm.projects[this.projectIndex]?.name ?? '选择项目').onSelect((index: number) => this.projectIndex = index)
            Row({ space: 8 }) {
              Checkbox({ name: 'replace' }).select(this.replaceMaterials).onChange((value: boolean) => this.replaceMaterials = value)
              Text('替换项目库存（默认合并）').fontSize(14).fontColor($r('app.color.text_primary'))
            }
            Text('合并只更新此背包中明确给出的材料数量。替换会移除目标项目里未出现的库存记录。').fontSize(13).fontColor($r('app.color.text_secondary'))
            Button('预览并同步', { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
              .height(44).width('100%').enabled(this.available()).onClick(() => this.syncMaterials())
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
          Button('重试', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).enabled(this.available()).onClick(() => this.reload())
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
                  (item: BackpackItem): string => `${this.vm.currentId}:${item.instanceId}:${item.count}:${item.level}:${item.category}:${item.score.available}:${item.score.value}:${this.vm.scoreSettings.revision}:${item.name}`)
              }.layoutWeight(1).height('100%').padding({ bottom: 24 }).cachedCount(5)
            }
            if (this.isWide) {
              Scroll() { this.details() }.width(340).height('100%').attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(12)
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
      .bindSheet($$this.showSheet, this.sheetContent(), { height: '80%', showClose: true,
        systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }
}
