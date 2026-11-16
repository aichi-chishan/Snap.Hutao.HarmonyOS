import { router } from '@kit.ArkUI';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier } from '../common/UiSurface';
/**
 * WikiMonsterPage.ets（@Entry）
 * 怪物资料（对齐 Windows WikiMonsterPage）：列表/详情双栏（宽屏）/ 单栏切换（窄屏）。
 * 数据：rawfile/metadata/monster_meta.json（Snap.Metadata 提取）；图标：rawfile/icons/MonsterIcon（离线）。
 */
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { WikiMetaService, WikiMonsterMeta, MetaMaterial } from '../service/WikiMetaService';
import { AppBackButton } from '../components/AppBackButton';
import { PageBackdrop } from '../components/PageBackdrop';
import { PageToolbar } from '../components/PageToolbar';
import { MetaIcon } from '../components/MetaIcon';
import { BaseValueService, MonsterBaseValues } from '../service/BaseValueService';
import { SimpleDataSource } from '../components/SimpleDataSource';

@Entry
@Component
export struct WikiMonsterPage {
  @StorageProp('helpLocaleVersion') @Watch('onLocaleChanged') localeVersion: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  @State monsters: WikiMonsterMeta[] = [];
  @State materials: Map<number, MetaMaterial> = new Map();
  /** 选中项 describeId（monster id 有 90 个 0 值重复，不可作唯一键） */
  @State selectedId: number = 0;
  /** 当前详情对象（页面 @State 显式赋值驱动刷新） */
  @State current: WikiMonsterMeta | undefined = undefined;
  @State keyword: string = '';
  @State nameTokens: string[] = [];
  @State gridMode: boolean = false;
  @State isWide: boolean = false;
  private detailScroller: Scroller = new Scroller();
  @State visibleCount: number = 0;
  @State appliedLocaleVersion: number = 0;
  @State showDetail: boolean = false;
  private active: boolean = false;
  private loadSequence: number = 0;
  /** 基础属性滑条状态（对齐 Windows 数值曲线，1-110 级） */
  @State curLevel: number = 1;
  @State curHp: number = 0;
  @State curAtk: number = 0;
  @State curDef: number = 0;
  @State statsExpanded: boolean = true;
  private valueSequence: number = 0;
  /** 列表懒加载数据源 */
  private listSource: SimpleDataSource<WikiMonsterMeta> = new SimpleDataSource([]);

  /** 8 项抗性标签（顺序对齐 subHurts：火/水/草/雷/冰/岩/风/物理） */
  private static readonly RESIST_LABELS: string[] = [
    '火元素抗性', '水元素抗性', '草元素抗性', '雷元素抗性',
    '冰元素抗性', '岩元素抗性', '风元素抗性', '物理抗性',
  ];
  /** WikiMetaService normalizes old compact files to fire/water/grass/electric/ice/rock/wind/physical. */
  private static readonly RESIST_ORDER: number[] = [0, 1, 2, 3, 6, 4, 5, 7];

  aboutToAppear(): void {
    this.active = true;
    this.gridMode = PreferencesStore.getBool('wiki.monster.grid', false);
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
    this.valueSequence++;
  }

  private onLocaleChanged(): void { this.load(true); }

  async load(preserveSelection: boolean = false): Promise<void> {
    if (!this.active) { return; }
    const sequence: number = ++this.loadSequence;
    const restoreSelection: boolean = preserveSelection && !this.loading;
    if (!restoreSelection) { this.loading = true; }
    const monsters: WikiMonsterMeta[] = await WikiMetaService.getMonsters();
    const materials: Map<number, MetaMaterial> = await WikiMetaService.getMonsterDrops();
    if (!this.active || sequence !== this.loadSequence) { return; }
    this.monsters = monsters.slice().sort((left: WikiMonsterMeta, right: WikiMonsterMeta): number =>
      left.describeId - right.describeId);
    this.materials = materials;
    const filtered: WikiMonsterMeta[] = this.filtered();
    this.visibleCount = filtered.length;
    this.appliedLocaleVersion = this.localeVersion;
    this.listSource.notifyDataReload(filtered);
    if (restoreSelection) {
      const previousId: number = this.selectedId;
      this.current = monsters.find((monster: WikiMonsterMeta): boolean => monster.describeId === previousId);
      this.selectedId = this.current?.describeId ?? 0;
      this.showDetail = this.showDetail && this.current !== undefined;
      if (this.current !== undefined) { this.calcMonsterBase(); }
    } else if (this.isWide) { this.setCurrent(filtered[0]); }
    this.loading = false;
  }

  /** 点击列表行：显式赋值页面 @State */
  select(m: WikiMonsterMeta): void {
    this.showDetail = true;
    this.setCurrent(m);
  }

  private setCurrent(monster: WikiMonsterMeta | undefined): void {
    if (this.current?.describeId === monster?.describeId) { return; }
    if (this.current !== undefined && monster !== undefined) {
      this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
    this.current = monster;
    this.selectedId = monster?.describeId ?? 0;
    if (monster === undefined) { this.showDetail = false; }
    else { this.onMonsterSelected(); }
  }

  /** 重置滑条并重算基础属性（切换怪物时） */
  onMonsterSelected(): void {
    this.curLevel = 110;
    this.curHp = Math.round(this.current?.hpBase ?? 0);
    this.curAtk = Math.round(this.current?.attackBase ?? 0);
    this.curDef = Math.round(this.current?.defenseBase ?? 0);
    this.calcMonsterBase();
  }

  /** 依据当前怪物+等级重算 生命/攻击/防御（无突破，曲线最高 110 级取数值区间） */
  calcMonsterBase(): void {
    const sequence: number = ++this.valueSequence;
    const cur: WikiMonsterMeta | undefined = this.current;
    if (cur === undefined || cur.growCurves.length === 0) {
      return;
    }
    if (this.curLevel > 110) {
      this.curLevel = 110;
    }
    BaseValueService.monsterBaseValues(cur.growCurves, cur.hpBase, cur.attackBase, cur.defenseBase,
      this.curLevel).then((v: MonsterBaseValues) => {
      if (sequence === this.valueSequence && this.current?.describeId === cur.describeId) {
        this.curHp = v.hp;
        this.curAtk = v.atk;
        this.curDef = v.def;
      }
    }).catch(() => {
    });
  }

  /** 基础属性卡：等级滑条 + 生命/攻击/防御（对齐 Windows 怪物数值曲线 1-110 级） */
  @Builder
  monsterBaseCard() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.ui_base_value_slider_level')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        if ((this.current?.growCurves.length ?? 0) > 0) {
          Text(`Lv. ${this.curLevel}`).fontSize(13).fontColor($r('app.color.text_primary'))
          if (this.isWide) {
            Column() { this.levelSlider() }
              .width('34%').constraintSize({ maxWidth: 240 })
          }
        }
        Button(this.statsExpanded ? '⌃' : '⌄', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(40).width(40).padding(0)
          .accessibilityText(this.statsExpanded ? '收起基础属性' : '展开基础属性')
          .onClick(() => { this.statsExpanded = !this.statsExpanded; })
      }
      .width('100%').padding({ left: 12, right: 8, top: 4, bottom: 4 })
      if (this.statsExpanded) {
        if (!this.isWide && (this.current?.growCurves.length ?? 0) > 0) {
          Column() { this.levelSlider() }.width('100%').padding({ left: 12, right: 12, bottom: 4 })
        }
        this.monStat('生命值')
        this.monStat('攻击力')
        this.monStat('防御力')
      }
    }
    .width('100%').borderRadius(8)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  levelSlider() {
    Slider({ value: this.curLevel, min: 1, max: 110, step: 1, style: SliderStyle.InSet })
      .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
      .width('100%').blockColor($r('app.color.app_primary')).selectedColor($r('app.color.app_primary'))
      .accessibilityText($r('app.string.ui_base_value_slider_level'))
      .onChange((level: number) => {
        this.curLevel = Math.round(level);
        this.calcMonsterBase();
      })
  }

  matName(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.n : `${id}`;
  }

  matIcon(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.i : '';
  }

  private matCategory(id: number): string {
    return this.matIcon(id).startsWith('UI_RelicIcon_') ? 'RelicIcon' : 'ItemIcon';
  }

  filtered(): WikiMonsterMeta[] {
    const keyword: string = this.keyword.trim().toLowerCase();
    const names: string[] = this.nameTokens.map((name: string): string => name.toLowerCase());
    if (keyword.length > 0 && !names.includes(keyword)) { names.push(keyword); }
    return this.monsters.filter((monster: WikiMonsterMeta): boolean =>
      names.length === 0 || names.some((name: string): boolean => monster.name.toLowerCase().includes(name) ||
        monster.title.toLowerCase().includes(name) || (monster.canonicalName || monster.name).toLowerCase().includes(name)));
  }

  private setKeyword(keyword: string): void {
    if (keyword.trim().length > 0 && this.nameTokens.length >= 5) { return; }
    this.keyword = keyword;
    this.applyFilter();
  }

  private commitKeyword(): void {
    const keyword: string = this.keyword.trim();
    if (keyword.length === 0) { return; }
    if (!this.nameTokens.some((name: string): boolean => name.toLowerCase() === keyword.toLowerCase())) {
      if (this.nameTokens.length >= 5) { return; }
      this.nameTokens = this.nameTokens.concat(keyword);
    }
    this.keyword = '';
    this.applyFilter();
  }

  private clearFilters(): void {
    this.keyword = '';
    this.nameTokens = [];
    this.applyFilter();
  }

  private resistanceText(index: number): string {
    return `${((this.current?.subHurts[index] ?? 0) * 100).toFixed(1)}%`;
  }

  /** 筛选后重建懒加载数据源 */
  applyFilter(): void {
    const filtered: WikiMonsterMeta[] = this.filtered();
    this.visibleCount = filtered.length;
    this.listSource.notifyDataReload(filtered);
    if (!filtered.some((monster: WikiMonsterMeta): boolean => monster.describeId === this.selectedId)) {
      this.setCurrent(filtered[0]);
    }
  }

  private updateWidth(width: number): void {
    const wide: boolean = width >= 840;
    if (wide === this.isWide) { return; }
    this.isWide = wide;
    if (wide && !this.loading && this.current === undefined) { this.applyFilter(); }
  }

  onBackPress(): boolean {
    if (this.isWide || !this.showDetail) { return false; }
    this.showDetail = false;
    return true;
  }

  private back(): void {
    if (!this.onBackPress()) { router.back(); }
  }

  private setGridMode(grid: boolean): void {
    if (this.gridMode === grid) { return; }
    this.gridMode = grid;
    PreferencesStore.setBool('wiki.monster.grid', grid);
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
        this.header()
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
    }
    .width('100%').height('100%')
    .onAreaChange((_old: Area, area: Area) => this.updateWidth(Number(area.width)))
  }

  @Builder
  header() {
    Column() {
      PageToolbar({ embedMode: true, leading: (): void => { this.toolbarLeading(); } })
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
      AppBackButton({ accessibilityLabel: !this.isWide && this.showDetail ? '返回怪物列表' : '返回',
        onBack: () => this.back() })
    }
    if (this.isWide || !this.showDetail) {
      Row({ space: 2 }) {
        this.viewButton(false)
        this.viewButton(true)
      }
      TextInput({ text: this.keyword, placeholder: '搜索怪物名/头衔' })
        .fontSize(13).height(36).layoutWeight(1).enterKeyType(EnterKeyType.Search)
        .enabled(this.nameTokens.length < 5)
        .onChange((keyword: string) => this.setKeyword(keyword))
        .onSubmit(() => this.commitKeyword())
      Text(`${this.nameTokens.length + (this.keyword.trim().length > 0 ? 1 : 0)}/5`)
        .fontSize(11).fontColor($r('app.color.text_secondary'))
      if (this.keyword.length > 0 || this.nameTokens.length > 0) {
        Button('×', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44).width(40).padding(0).accessibilityText($r('app.string.ui_clear_filters'))
          .onClick(() => this.clearFilters())
      }
    } else {
      Text(this.current?.name || this.current?.title || $r('app.string.ui_nav_wiki_monster'))
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
  listPanel() {
    Column() {
      if (this.visibleCount === 0) {
        Text('没有匹配的怪物').fontSize(13).fontColor($r('app.color.text_secondary')).padding(12)
      } else if (this.gridMode) {
        Grid() {
          LazyForEach(this.listSource, (m: WikiMonsterMeta) => {
            GridItem() {
              Column({ space: 4 }) {
                MetaIcon({ category: 'MonsterIcon', name: m.icon, iconSize: 48 })
                Text(m.name || m.title || `#${m.describeId}`).fontSize(12).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor($r('app.color.text_primary'))
              }.width('100%').height(84).padding(6).borderRadius(6)
                .backgroundColor(this.selectedId === m.describeId ? $r('app.color.app_primary_bg') : Color.Transparent)
                .accessibilitySelected(this.selectedId === m.describeId)
                .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => { this.select(m); })
            }
          }, (m: WikiMonsterMeta) => `grid_${m.describeId}_${this.appliedLocaleVersion}`)
        }.columnsTemplate(this.isWide ? '1fr 1fr' : '1fr 1fr 1fr')
          .columnsGap(4).rowsGap(4).cachedCount(4).width('100%').layoutWeight(1)
      } else {
        List({ space: 2 }) {
          LazyForEach(this.listSource, (m: WikiMonsterMeta) => {
            ListItem() {
              Row({ space: 10 }) {
                MetaIcon({ category: 'MonsterIcon', name: m.icon, iconSize: 40 })
                Text(m.name || m.title || `#${m.describeId}`)
                  .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%').constraintSize({ minHeight: 56 })
              .padding({ left: 10, right: 8, top: 6, bottom: 6 }).borderRadius(6)
              .backgroundColor(this.selectedId === m.describeId ? $r('app.color.app_primary_bg') : Color.Transparent)
              .accessibilitySelected(this.selectedId === m.describeId)
              .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => { this.select(m); })
            }
          }, (m: WikiMonsterMeta) => `m_${m.describeId}_${this.appliedLocaleVersion}`)
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
          this.monsterProfile()
          if (this.current!.growCurves.length > 0 || this.current!.hpBase > 0 ||
            this.current!.attackBase > 0 || this.current!.defenseBase > 0) {
            this.monsterBaseCard()
          }
          if (this.current!.subHurts.length >= 8) {
            this.resistanceCard()
          }
          if (this.current!.drops.length > 0) {
            this.dropsCard()
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
  monsterProfile() {
    Column({ space: 10 }) {
      Text(this.current!.title || this.current!.name || `#${this.current!.describeId}`)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      if (this.current!.description.length > 0) {
        Text(this.current!.description).fontSize(13).lineHeight(20).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.current!.affixes.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.current!.affixes, (affix: string) => {
            Text(affix).fontSize(11).fontColor($r('app.color.text_primary'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 }).margin({ right: 6, bottom: 4 })
              .borderRadius(6).backgroundColor($r('app.color.card_inner_tint'))
          }, (affix: string, index: number) => `affix_${index}_${affix}`)
        }
        .width('100%')
      }
    }
    .width('100%').padding({ left: 2, right: 2, top: 4, bottom: 8 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  resistanceCard() {
    GridRow({ columns: 2, gutter: { x: 4, y: 4 } }) {
        ForEach(WikiMonsterPage.RESIST_ORDER, (index: number) => {
          GridCol() {
            Row({ space: 6 }) {
              Text(WikiMonsterPage.RESIST_LABELS[index]).fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1)
              Text(this.resistanceText(index))
                .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            }
            .width('100%').constraintSize({ minHeight: 40 })
            .padding({ left: 12, right: 12 })
            .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
            .border({ width: 0.5, color: $r('app.color.card_stroke'), radius: 6 })
          }
        }, (index: number) => `res_${this.selectedId}_${index}_${this.current!.subHurts[index]}_${this.appliedLocaleVersion}`)
    }
    .width('100%')
  }

  @Builder
  dropsCard() {
    Column({ space: 8 }) {
      Text('掉落物').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      GridRow({ columns: this.isWide ? 3 : 2, gutter: 6 }) {
        ForEach(this.current!.drops, (id: number) => {
          GridCol() {
            Row({ space: 8 }) {
              MetaIcon({ category: this.matCategory(id), name: this.matIcon(id), iconSize: 40 })
              Text(this.matName(id)).fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1)
            }
            .width('100%').constraintSize({ minHeight: 44 })
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .border({ width: 0.5, color: $r('app.color.card_stroke'), radius: 6 })
          }
        }, (id: number, index: number) => `drop_${id}_${index}_${this.appliedLocaleVersion}`)
      }
      .width('100%')
    }
    .width('100%').padding(14).borderRadius(8)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  monStat(label: string) {
    Divider().color($r('app.color.divider'))
    Row() {
      Text(`基础${label}`).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
      Text(`${this.monStatValueOf(label)}`).fontSize(13)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
    }
    .width('100%').constraintSize({ minHeight: 38 }).padding({ left: 12, right: 12 })
  }

  /** Read calculated state in the builder so level changes update the visible rows. */
  private monStatValueOf(label: string): number {
    if (label === '生命值') { return this.curHp; }
    if (label === '攻击力') { return this.curAtk; }
    return this.curDef;
  }
}
