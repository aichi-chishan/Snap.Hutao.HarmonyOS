import { router } from '@kit.ArkUI';
import { fileUri } from '@kit.CoreFileKit';
import { WishHistoryWikiParams } from '../model/WishHistory';
import { CultivationDraftViewModel } from '../viewmodel/CultivationDraftViewModel';
import { CultivationDraftEditor } from '../components/CultivationDraftEditor';
/**
 * WikiWeaponPage.ets（@Entry）
 * 武器资料（对齐 Windows WikiWeaponPage）：列表/详情双栏（宽屏）/ 单栏切换（窄屏）。
 * 数据：rawfile/metadata/weapon_meta.json；图标：rawfile/icons（离线）。
 * 区块：简介（大图/类型/稀有度/描述）、精炼 1-5、养成材料。
 */
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { WikiMetaService, WikiWeaponMeta, MetaMaterial } from '../service/WikiMetaService';
import { BaseValueService, WeaponBaseValues } from '../service/BaseValueService';
import { AppBackButton } from '../components/AppBackButton';
import { PageBackdrop } from '../components/PageBackdrop';
import { PageToolbar } from '../components/PageToolbar';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { WikiFilterGroup } from '../components/WikiFilterGroup';
import { StandardIconService } from '../data/remote/StandardIconService';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, UiSurface } from '../common/UiSurface';

class WikiWeaponArtFrame {
  source: string;
  sequence: number;
  constructor(source: string, sequence: number) { this.source = source; this.sequence = sequence; }
}

/** Windows GachaEquipIconConverter uses the same icon identity with a UI_Gacha_ prefix. */
@Component
struct WikiWeaponArt {
  @Prop @Watch('resolve') icon: string = '';
  @State sources: WikiWeaponArtFrame[] = [];
  private active: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void { this.active = true; this.resolve(); }
  aboutToDisappear(): void { this.active = false; this.sequence++; }

  private async resolve(): Promise<void> {
    const sequence: number = ++this.sequence;
    this.sources = [];
    if (!this.active || !/^UI_EquipIcon_[A-Za-z0-9_-]+$/.test(this.icon)) { return; }
    const name: string = `UI_Gacha_${this.icon.substring(3)}`;
    const path: string = await StandardIconService.ensure('GachaEquipIcon', name);
    if (this.active && sequence === this.sequence && path.length > 0) {
      this.sources = [new WikiWeaponArtFrame(fileUri.getUriFromPath(path), sequence)];
    }
  }

  build() {
    Stack() {
      if (this.sources.length > 0) {
        ForEach(this.sources, (frame: WikiWeaponArtFrame) => {
          Image(frame.source).width('100%').height('100%').objectFit(ImageFit.Contain)
            .onError(() => {
              if (this.sources[0] === frame) { this.sources = []; }
            })
        }, (frame: WikiWeaponArtFrame): string => `${frame.sequence}_${frame.source}`)
      } else {
        MetaIcon({ category: 'EquipIcon', name: this.icon, iconSize: 144, remoteFallback: true })
      }
    }.width('100%').height('100%')
  }
}

@Entry
@Component
export struct WikiWeaponPage {
  @StorageProp('helpLocaleVersion') @Watch('onLocaleChanged') localeVersion: number = 0;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  /** Metadata and route ownership belong to this mounted page only. */
  private active: boolean = false;
  private loadSequence: number = 0;
  private routeItemId: number = 0;
  private routeRequested: boolean = false;
  @State routeMessage: string = '';
  @State weapons: WikiWeaponMeta[] = [];
  @State materials: Map<number, MetaMaterial> = new Map();
  @State selectedId: number = 0;
  /** 当前详情对象（页面 @State 显式赋值驱动刷新） */
  @State current: WikiWeaponMeta | undefined = undefined;
  @State keyword: string = '';
  @State nameTokens: string[] = [];
  @State gridMode: boolean = false;
  @State showFilters: boolean = false;
  @State qualities: string[] = [];
  @State weaponTypes: string[] = [];
  @State properties: string[] = [];
  @State visibleCount: number = 0;
  @State appliedLocaleVersion: number = 0;
  @State showDetail: boolean = false;
  @State isWide: boolean = false;
  private detailScroller: Scroller = new Scroller();
  /** 列表懒加载数据源 */
  private listSource: SimpleDataSource<WikiWeaponMeta> = new SimpleDataSource([]);
  /** 基础数值滑条状态 */
  @State curLevel: number = 1;
  @State curPromoted: boolean = false;
  @State curAttack: number = 0;
  @State curSecondary: string = '';
  @State statsExpanded: boolean = true;
  @State refinementIndex: number = 0;
  private valueSequence: number = 0;

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1500 });
  }
  @State draftVm: CultivationDraftViewModel = new CultivationDraftViewModel();
  @State showPlanSheet: boolean = false;

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
    this.valueSequence++;
    this.draftVm.cancel();
  }

  aboutToAppear(): void {
    this.active = true;
    this.readRouteItem();
    this.gridMode = PreferencesStore.getBool('wiki.weapon.grid', false);
    this.load();
  }

  private readRouteItem(): void {
    this.routeItemId = 0;
    this.routeRequested = false;
    // Embedded pages share Index's router context; it must never select a Wiki item.
    if (this.embedMode) { return; }
    try {
      const params: WishHistoryWikiParams | undefined = router.getParams() as WishHistoryWikiParams | undefined;
      if (params !== undefined && params !== null && params.itemId !== undefined) {
        this.routeRequested = true;
        if (typeof params.itemId === 'number' && Number.isInteger(params.itemId)
          && params.itemId >= 10000 && params.itemId <= 99999) { this.routeItemId = params.itemId; }
      }
    } catch (_) {
      this.routeRequested = true;
    }
  }

  private ownsLoad(sequence: number): boolean { return this.active && sequence === this.loadSequence; }

  private onLocaleChanged(): void { this.load(true); }

  async load(preserveSelection: boolean = false): Promise<void> {
    if (!this.active) { return; }
    const sequence: number = ++this.loadSequence;
    const restoreSelection: boolean = preserveSelection && !this.loading;
    const requested: boolean = this.routeRequested;
    const itemId: number = this.routeItemId;
    this.valueSequence++;
    if (!restoreSelection) {
      this.loading = true;
      this.routeMessage = '';
    }
    try {
      const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
      if (!this.ownsLoad(sequence)) { return; }
      const materials: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
      if (!this.ownsLoad(sequence)) { return; }
      this.weapons = weapons.slice().sort((left: WikiWeaponMeta, right: WikiWeaponMeta): number => right.sort - left.sort);
      this.materials = materials;
      const filtered: WikiWeaponMeta[] = this.filtered();
      const previousId: number = this.selectedId;
      if (restoreSelection) {
        this.current = weapons.find((item: WikiWeaponMeta): boolean => item.id === previousId);
        this.showDetail = this.showDetail && this.current !== undefined;
      } else {
        // A requested unknown/invalid ID must not silently display the first unrelated item.
        this.current = requested
          ? weapons.find((item: WikiWeaponMeta): boolean => item.id === itemId)
          : (this.isWide ? filtered[0] : undefined);
        this.showDetail = requested && this.current !== undefined;
        this.routeMessage = requested && this.current === undefined ? '本地暂无该武器资料，请从列表选择或更新游戏数据' : '';
      }
      this.selectedId = this.current?.id ?? 0;
      this.visibleCount = filtered.length;
      this.appliedLocaleVersion = this.localeVersion;
      this.listSource.notifyDataReload(filtered);
      if (this.current !== undefined) {
        if (restoreSelection && this.current.id === previousId) { this.calcWeaponBase(); }
        else { this.onWeaponSelected(); }
      }
    } catch (_) {
      if (!this.ownsLoad(sequence)) { return; }
      if (restoreSelection) { return; }
      this.weapons = [];
      this.current = undefined;
      this.selectedId = 0;
      this.showDetail = false;
      this.visibleCount = 0;
      this.routeMessage = '无法读取本地武器资料，请重新进入后重试';
      this.listSource.notifyDataReload([]);
    } finally {
      if (this.ownsLoad(sequence)) { this.loading = false; }
    }
  }

  /** 点击列表行：显式赋值页面 @State，并重置数值滑条 */
  select(w: WikiWeaponMeta): void {
    if (!this.active) { return; }
    this.routeMessage = '';
    this.showDetail = true;
    this.setCurrent(w);
  }

  private setCurrent(weapon: WikiWeaponMeta | undefined): void {
    if (this.current?.id === weapon?.id) { return; }
    if (this.current !== undefined && weapon !== undefined) {
      this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
    this.current = weapon;
    this.selectedId = weapon?.id ?? 0;
    if (weapon === undefined) { this.showDetail = false; }
    else { this.onWeaponSelected(); }
  }

  /** 依据等级和突破阶段重算攻击力和副属性。 */
  async calcWeaponBase(): Promise<void> {
    const weapon: WikiWeaponMeta | undefined = this.current;
    if (!this.active || weapon === undefined) { return; }
    const sequence: number = ++this.valueSequence;
    const maxLv: number = BaseValueService.weaponMaxLevel(weapon.rankLevel);
    if (this.curLevel > maxLv) {
      this.curLevel = maxLv;
    }
    const values: WeaponBaseValues = await BaseValueService.weaponBaseValues(weapon.growCurves, weapon.promoteId,
      maxLv, this.curLevel, this.curPromoted);
    if (this.active && sequence === this.valueSequence) {
      this.curAttack = values.attack;
      this.curSecondary = values.secondary;
    }
  }

  /** 重置滑条为选中武器状态 */
  onWeaponSelected(): void {
    this.curLevel = this.maxLevel();
    this.curPromoted = false;
    this.curAttack = 0;
    this.curSecondary = '';
    this.refinementIndex = 0;
    this.calcWeaponBase();
  }

  /** 当前武器最大等级 */
  maxLevel(): number {
    return BaseValueService.weaponMaxLevel(this.current?.rankLevel ?? 0);
  }

  private secondaryLabel(): string {
    return BaseValueService.fightPropName(this.current?.secondaryProperty ?? 0);
  }

  private secondaryValue(): string {
    const prefix: string = `${this.secondaryLabel()} `;
    return this.curSecondary.startsWith(prefix) ? this.curSecondary.substring(prefix.length) : this.curSecondary;
  }

  private confirmAddPlan(): void { this.addCurrentToPlan(); }

  private async addCurrentToPlan(): Promise<void> {
    if (this.current === undefined || this.draftVm.busy) { return; }
    this.showPlanSheet = true;
    await this.draftVm.offline('weapon', this.current.id);
  }

  private filtered(): WikiWeaponMeta[] {
    const query: string = this.keyword.trim().toLowerCase();
    const names: string[] = this.nameTokens.map((name: string): string => name.toLowerCase());
    if (query.length > 0 && !names.includes(query)) { names.push(query); }
    const qualities: string[] = this.qualities;
    const weaponTypes: string[] = this.weaponTypes;
    const properties: string[] = this.properties;
    return this.weapons.filter((weapon: WikiWeaponMeta): boolean =>
      (names.length === 0 || names.some((name: string): boolean => weapon.name.toLowerCase().includes(name) ||
        (weapon.canonicalName || weapon.name).toLowerCase().includes(name))) &&
      (qualities.length === 0 || qualities.includes(WikiMetaService.qualityName(weapon.rankLevel))) &&
      (weaponTypes.length === 0 || weaponTypes.includes(WikiMetaService.weaponTypeName(weapon.weaponType))) &&
      (properties.length === 0 || properties.includes(BaseValueService.fightPropName(weapon.secondaryProperty))));
  }

  private applyFilter(): void {
    const filtered: WikiWeaponMeta[] = this.filtered();
    this.visibleCount = filtered.length;
    this.listSource.notifyDataReload(filtered);
    if (!filtered.some((weapon: WikiWeaponMeta): boolean => weapon.id === this.selectedId)) {
      this.setCurrent(filtered[0]);
    }
  }

  private updateWidth(width: number): void {
    const wide: boolean = width >= 840;
    if (wide === this.isWide) { return; }
    this.isWide = wide;
    if (wide && !this.loading && this.current === undefined && !this.routeRequested) { this.applyFilter(); }
  }

  onBackPress(): boolean {
    if (this.isWide || !this.showDetail) { return false; }
    this.showDetail = false;
    return true;
  }

  private back(): void {
    if (!this.onBackPress()) { router.back(); }
  }

  private filterCount(): number {
    return this.nameTokens.length + this.qualities.length + this.weaponTypes.length + this.properties.length;
  }

  private setKeyword(keyword: string): void {
    if (keyword.trim().length > 0 && this.filterCount() >= 5) { return; }
    this.keyword = keyword;
    this.applyFilter();
  }

  private commitKeyword(): void {
    const keyword: string = this.keyword.trim();
    if (keyword.length === 0) { return; }
    if (!this.nameTokens.some((name: string): boolean => name.toLowerCase() === keyword.toLowerCase())) {
      if (this.filterCount() >= 5) { return; }
      this.nameTokens = this.nameTokens.concat(keyword);
    }
    this.keyword = '';
    this.applyFilter();
  }

  private updateFilterGroup(group: number, values: string[]): void {
    const previous: string[] = group === 0 ? this.qualities : group === 1 ? this.weaponTypes : this.properties;
    const draftCount: number = this.keyword.trim().length > 0 ? 1 : 0;
    if (this.filterCount() - previous.length + values.length + draftCount > 5) { return; }
    if (group === 0) { this.qualities = values; }
    else if (group === 1) { this.weaponTypes = values; }
    else { this.properties = values; }
    this.applyFilter();
  }

  private clearFilters(): void {
    this.keyword = '';
    this.nameTokens = [];
    this.qualities = [];
    this.weaponTypes = [];
    this.properties = [];
    this.applyFilter();
  }

  private setGridMode(grid: boolean): void {
    if (this.gridMode === grid) { return; }
    this.gridMode = grid;
    PreferencesStore.setBool('wiki.weapon.grid', grid);
  }

  private propertyOptions(): string[] {
    const types: number[] = Array.from(new Set(this.weapons.map((weapon: WikiWeaponMeta): number => weapon.secondaryProperty)));
    return types.sort((left: number, right: number): number => left - right)
      .map((type: number): string => BaseValueService.fightPropName(type))
      .filter((label: string): boolean => label.length > 0);
  }

  @Builder
  planPickerSheet() {
    CultivationDraftEditor({ vm: this.draftVm,
      onClose: (): void => { this.showPlanSheet = false; this.draftVm.cancel(); } })
  }


  static rankColor(r: number): Resource {
    if (r >= 5) {
      return $r('app.color.five_star');
    }
    if (r === 4) {
      return $r('app.color.four_star');
    }
    return $r('app.color.text_secondary');
  }

  matName(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.n : `${id}`;
  }

  matIcon(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.i : '';
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
        this.header()
        if (this.routeMessage.length > 0) {
          Text(this.routeMessage).fontSize(12).fontColor($r('app.color.text_secondary'))
            .width('100%').padding({ bottom: 8 })
        }
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
            Text($r('app.string.ui_common_loading')).fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Row({ space: 12 }) {
            this.listPanel()
            this.detailPanel()
          }
          .layoutWeight(1).width('100%').alignItems(VerticalAlign.Top)
        }
      }
      .width('100%').height('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
      .bindSheet($$this.showPlanSheet, this.planPickerSheet(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
        title: { title: '加入养成计划' },
        showClose: true,
        dragBar: true,
        height: '90%',
        onDisappear: (): void => { this.draftVm.cancel(); },
        blurStyle: BlurStyle.Regular,
        backgroundColor: $r('app.color.sheet_material_tint'),
      })
    }
    .width('100%').height('100%')
    .onAreaChange((_old: Area, area: Area) => this.updateWidth(Number(area.width)))
  }

  @Builder
  header() {
    Column() {
      PageToolbar({ embedMode: true,
        leading: (): void => { this.toolbarLeading(); }, trailing: (): void => { this.toolbarTrailing(); } })
      if ((this.isWide || !this.showDetail) && this.nameTokens.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.nameTokens, (name: string) => {
              Button(`${name} ×`, { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
                .height(44).fontSize(12)
                .onClick(() => {
                  this.nameTokens = this.nameTokens.filter((token: string): boolean => token !== name);
                  this.applyFilter();
                })
            }, (name: string): string => name)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ top: 6 })
      }
    }
    .width('100%').padding({ top: (this.embedMode ? 0 : this.topAvoidVp) + 8, bottom: 10 })
  }

  @Builder
  toolbarLeading() {
    if (!this.embedMode || (!this.isWide && this.showDetail)) {
      AppBackButton({ accessibilityLabel: !this.isWide && this.showDetail ? '返回武器列表' : '返回',
        onBack: () => this.back() })
    }
    if (this.isWide || !this.showDetail) {
      Row({ space: 2 }) {
        this.viewButton(false)
        this.viewButton(true)
      }
      TextInput({ text: this.keyword, placeholder: $r('app.string.ui_wi_ki_weapon_auto_suggest_box_place_holder') })
        .fontSize(13).height(36).layoutWeight(1).enterKeyType(EnterKeyType.Search)
        .enabled(this.filterCount() < 5)
        .onChange((keyword: string) => this.setKeyword(keyword))
        .onSubmit(() => this.commitKeyword())
      Text(`${this.filterCount() + (this.keyword.trim().length > 0 ? 1 : 0)}/5`)
        .fontSize(11).fontColor($r('app.color.text_secondary'))
      Button(this.filterCount() > 0 ? $r('app.string.ui_filter_count', this.filterCount()) : $r('app.string.ui_filter'),
        { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(40).fontSize(12).onClick(() => { this.showFilters = true; })
        .bindSheet($$this.showFilters, this.filterSheet(), { title: { title: $r('app.string.ui_wi_ki_weapon_auto_suggest_box_place_holder') }, height: '80%', showClose: true,
          systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel), blurStyle: BlurStyle.Regular,
          backgroundColor: UiSurface.immersiveActive() ? Color.Transparent : $r('app.color.sheet_material_tint') })
    } else {
      Text(this.current?.name ?? $r('app.string.ui_nav_wiki_weapon'))
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }
  }

  @Builder
  viewButton(grid: boolean) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(grid ? $r('sys.symbol.grid') : $r('sys.symbol.list_bullet')).fontSize(18)
        .fontColor([this.gridMode === grid ? $r('app.color.app_primary_text') : $r('app.color.text_secondary')])
    }
    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
    .width(40).height(40).padding(0)
    .backgroundColor(this.gridMode === grid ? $r('app.color.app_primary_bg') : Color.Transparent)
    .accessibilityText(grid ? $r('app.string.ui_grid_view') : $r('app.string.ui_list_view'))
    .accessibilitySelected(this.gridMode === grid)
    .onClick(() => this.setGridMode(grid))
  }

  @Builder
  toolbarTrailing() {
    if (this.current !== undefined && (this.isWide || this.showDetail) && !this.loading) {
      Button(this.isWide ? '加入养成计划' : '＋', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(40).width(this.isWide ? 144 : 40).fontSize(this.isWide ? 13 : 20)
        .accessibilityText('加入养成计划')
        .enabled(!this.draftVm.busy).onClick(() => this.confirmAddPlan())
    }
  }

  @Builder
  filterSheet() {
    Scroll() {
      Column({ space: 14 }) {
        WikiFilterGroup({ title: $r('app.string.ui_backpack_sort_quality'), options: ['一星', '二星', '三星', '四星', '五星'], selected: this.qualities,
          onChange: (values: string[]) => this.updateFilterGroup(0, values) })
        WikiFilterGroup({ title: '武器种类', options: WikiMetaService.WEAPON_TYPES, selected: this.weaponTypes,
          onChange: (values: string[]) => this.updateFilterGroup(1, values) })
        WikiFilterGroup({ title: '副属性', options: this.propertyOptions(), selected: this.properties,
          onChange: (values: string[]) => this.updateFilterGroup(2, values) })
        Button($r('app.string.ui_clear_filters'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
          .enabled(this.filterCount() > 0 || this.keyword.length > 0).onClick(() => this.clearFilters())
      }.width('100%').constraintSize({ maxWidth: 560 }).padding(20).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%')
  }

  @Builder
  listPanel() {
    Column() {
      if (this.visibleCount === 0) {
        Text('没有匹配的武器').fontSize(13).fontColor($r('app.color.text_secondary')).padding(12)
      } else if (this.gridMode) {
        Grid() {
          LazyForEach(this.listSource, (w: WikiWeaponMeta) => {
            GridItem() {
              Column({ space: 4 }) {
                MetaIcon({ category: 'EquipIcon', name: w.icon, iconSize: 48 })
                Text(w.name).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor($r('app.color.text_primary'))
              }.width('100%').height(84).padding(6).borderRadius(6)
                .backgroundColor(this.selectedId === w.id ? $r('app.color.app_primary_bg') : Color.Transparent)
                .accessibilitySelected(this.selectedId === w.id)
                .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => { this.select(w); })
            }
          }, (w: WikiWeaponMeta) => `grid_${w.id}_${this.appliedLocaleVersion}`)
        }.columnsTemplate(this.isWide ? '1fr 1fr' : '1fr 1fr 1fr')
          .columnsGap(4).rowsGap(4).cachedCount(4).width('100%').layoutWeight(1)
      } else {
        List({ space: 2 }) {
          LazyForEach(this.listSource, (w: WikiWeaponMeta) => {
            ListItem() {
              Row({ space: 10 }) {
                MetaIcon({ category: 'EquipIcon', name: w.icon, iconSize: 38 })
                Text(w.name)
                  .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%').constraintSize({ minHeight: 56 })
              .padding({ left: 10, right: 8, top: 6, bottom: 6 }).borderRadius(6)
              .backgroundColor(this.selectedId === w.id ? $r('app.color.app_primary_bg') : Color.Transparent)
              .accessibilitySelected(this.selectedId === w.id)
              .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => { this.select(w); })
            }
          }, (w: WikiWeaponMeta) => `w_${w.id}_${this.appliedLocaleVersion}`)
        }
        .cachedCount(5).width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      }
    }
    .width(this.isWide ? 216 : '100%').height('100%').padding(6)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
    .visibility(this.isWide || !this.showDetail ? Visibility.Visible : Visibility.None)
  }

  @Builder
  detailPanel() {
    if (this.current !== undefined) {
      Scroll(this.detailScroller) {
        Column({ space: 12 }) {
          this.weaponProfile()
          if (this.current!.description.length > 0) {
            Text(this.current!.description).fontSize(13).lineHeight(20).fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          this.baseValueCard()
          if (this.current!.cultivationItems.length > 0) { this.materialsCard(); }
          if (this.current!.affixName.length > 0 || this.current!.affixDesc.length > 0) {
            this.refinementCard()
          }
          Text('数据来源：Snap.Metadata（本地打包）')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .width('100%').padding({ bottom: 4 })
      }
      .height('100%').layoutWeight(1)
      .scrollBar(BarState.Auto)
      .visibility(this.isWide || this.showDetail ? Visibility.Visible : Visibility.None)
    }
  }

  @Builder
  weaponProfile() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image($rawfile('wiki/weapon/UI_GachaShowPanel_Bg_Weapon.png'))
        .width('100%').height('100%').objectFit(ImageFit.Fill).opacity(this.isDarkMode ? 0.45 : 1)
      Row({ space: 12 }) {
        Column({ space: 10 }) {
          this.ascensionIcon(false)
          if (this.current!.awakenIcon.length > 0) { this.ascensionIcon(true); }
        }
        .width(this.isWide ? 80 : 56).height('100%').justifyContent(FlexAlign.Start)
        WikiWeaponArt({ icon: this.current!.icon }).layoutWeight(1).height('100%')
      }
      .width('100%').height('100%').padding(this.isWide ? 16 : 10)
      Text(this.current!.name).fontSize(this.isWide ? 20 : 16).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).margin({ right: 16, bottom: 12, left: 84 })
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').aspectRatio(2).clip(true)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
  }

  @Builder
  ascensionIcon(awakened: boolean) {
    Column({ space: 2 }) {
      MetaIcon({ category: 'EquipIcon', name: awakened ? this.current!.awakenIcon : this.current!.icon,
        iconSize: this.isWide ? 72 : 48, remoteFallback: true })
      Text(awakened ? '突破后' : '突破前').fontSize(11).fontColor($r('app.color.text_primary'))
    }
    .width('100%').padding(2).borderRadius(6).backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 0.5, color: $r('app.color.card_stroke'), radius: 6 })
  }

  @Builder
  materialsCard() {
    Column({ space: 10 }) {
      Text($r('app.string.ui_wi_ki_avatar_ascension_materials_header')).fontSize(14)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      GridRow({ columns: this.isWide ? 3 : 2, gutter: 6 }) {
        ForEach(this.current!.cultivationItems, (id: number) => {
          GridCol() {
            Row({ space: 8 }) {
              MetaIcon({ category: 'ItemIcon', name: this.matIcon(id), iconSize: 40 })
              Text(this.matName(id)).fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1)
            }
            .width('100%').constraintSize({ minHeight: 44 })
            .padding({ left: 4, right: 8, top: 4, bottom: 4 })
            .border({ width: 0.5, color: $r('app.color.card_stroke'), radius: 6 })
          }
        }, (id: number, index: number) => `m_${id}_${index}_${this.appliedLocaleVersion}`)
      }.width('100%')
    }
    .width('100%').padding(14).borderRadius(8)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  refinementCard() {
    Column({ space: 10 }) {
      Text(this.current!.affixName || '精炼').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      if (this.current!.affixDesc.length > 0) {
        Row({ space: 6 }) {
          ForEach(this.current!.affixDesc, (_description: string, index: number) => {
            Button(`${index + 1}`, { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, this.refinementIndex === index))
              .height(44).width(40).padding(0)
              .accessibilityText(`精炼 ${index + 1} 阶`).accessibilitySelected(this.refinementIndex === index)
              .onClick(() => { this.refinementIndex = index; })
          }, (_description: string, index: number) => `r_${this.selectedId}_${index}`)
        }
        .width('100%')
        Text(this.current!.affixDesc[this.refinementIndex] ?? '').fontSize(13).lineHeight(20)
          .fontColor($r('app.color.text_secondary')).width('100%')
      }
    }
    .width('100%').padding(14).borderRadius(8)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  baseValueCard() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.ui_base_value_slider_level')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`Lv. ${this.curLevel}`).fontSize(13).fontColor($r('app.color.text_primary'))
        if (this.isWide) {
          this.promotedControl()
          Column() { this.levelSlider() }
            .width('34%').constraintSize({ maxWidth: 240 })
        }
        Button(this.statsExpanded ? '⌃' : '⌄', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(40).width(40).padding(0)
          .accessibilityText(this.statsExpanded ? '收起基础数值' : '展开基础数值')
          .onClick(() => { this.statsExpanded = !this.statsExpanded; })
      }
      .width('100%').padding({ left: 12, right: 8, top: 4, bottom: 4 })
      if (this.statsExpanded) {
        if (!this.isWide) {
          Row({ space: 8 }) {
            this.promotedControl()
            Column() { this.levelSlider() }.layoutWeight(1)
          }
          .width('100%').padding({ left: 8, right: 12, bottom: 4 })
        }
        Divider().color($r('app.color.divider'))
        Row() {
          Text('基础攻击力').fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          Text(this.curAttack > 0 ? `${this.curAttack}` : '—')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        }
        .width('100%').constraintSize({ minHeight: 38 }).padding({ left: 12, right: 12 })
        if (this.curSecondary.length > 0) {
          Divider().color($r('app.color.divider'))
          Row({ space: 8 }) {
            Text(this.secondaryLabel()).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
            Text(this.secondaryValue()).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          }
          .width('100%').constraintSize({ minHeight: 38 }).padding({ left: 12, right: 12 })
        }
      }
    }
    .width('100%').borderRadius(8)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  levelSlider() {
    Slider({ value: this.curLevel, min: 1, max: this.maxLevel(), step: 1, style: SliderStyle.InSet })
      .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
      .width('100%').blockColor($r('app.color.app_primary')).selectedColor($r('app.color.app_primary'))
      .accessibilityText($r('app.string.ui_base_value_slider_level'))
      .onChange((level: number) => {
        this.curLevel = Math.round(level);
        this.calcWeaponBase();
      })
  }

  @Builder
  promotedControl() {
    Row() {
      Toggle({ type: ToggleType.Checkbox, isOn: this.curPromoted })
        .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .width(36).height(36).accessibilityText('突破后')
        .onChange((promoted: boolean) => {
          this.curPromoted = promoted;
          this.calcWeaponBase();
        })
      Text('突破后').fontSize(12).fontColor($r('app.color.text_secondary'))
    }
  }
}
