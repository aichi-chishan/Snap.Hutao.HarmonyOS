/**
 * CharacterPage.ets（@Entry）
 * 我的角色：角色列表 + 选中角色详情（武器/圣遗物/面板属性）。
 * 宽屏：左列表 + 右详情；窄屏：列表 + 详情顺序展示。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { CharacterViewModel, CharacterSortKind } from '../viewmodel/CharacterViewModel';
import { CharacterFilterToken } from '../viewmodel/CharacterFilter';
import { CharacterListItem, CharacterDetail, Reliquary, RelicProperty, BaseProperty, Constellation } from '../model/CharacterData';
import { ReliquaryScore } from '../common/ReliquaryScore';
import { RiskUiHelper, RiskVerifyParams } from '../common/RiskUiHelper';
import { PageBackdrop } from '../components/PageBackdrop';
import { PageToolbar } from '../components/PageToolbar';
import { CharacterFilterBox } from '../components/CharacterFilterBox';
import { CharacterNameCard, CharacterNameCardData, CharacterNameCardSkill,
  CharacterNameCardConstellation } from '../components/CharacterNameCard';
import { NavIcon } from '../components/NavIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { MetaIcon } from '../components/MetaIcon';
import { WikiMetaService, WikiAvatarMeta, MetaSkill } from '../service/WikiMetaService';
import { LocalizedGameDataService } from '../service/LocalizedGameDataService';
import { CharacterExportService } from '../service/CharacterExportService';
import { CultivationDraftViewModel } from '../viewmodel/CultivationDraftViewModel';
import { CultivationDraftEditor } from '../components/CultivationDraftEditor';
import { ReliquaryScoreEditor } from '../components/ReliquaryScoreEditor';
import { PromoteState } from '../model/PromoteState';
import { SkillLevelService, ResolvedAvatarSkill } from '../service/SkillLevelService';
import { Logger } from '../common/Logger';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { BackpackScoreEdit, BackpackScoreProfile, CharacterScoreOption } from '../model/BackpackScore';
import { AppButtonModifier, CardSurfaceModifier, SelectMaterialModifier, UiSurface } from '../common/UiSurface';

const TAG: string = 'CharacterPage';
const VIEW_MODE_KEY: string = 'Control.PanelSelector.AvatarPropertyPage.Summary.Avatars';
const SORT_KEY: string = 'Snap::Hutao::AvatarProperty::SortDescriptionKind';
const SORT_LABELS: string[] = ['默认顺序', '等级', '品质', '命座', '好感度', '生命值上限', '攻击力', '防御力', '元素精通'];

@Entry
@Component
export struct CharacterPage {
  @StorageProp('helpLocaleVersion') @Watch('onLocaleChanged') localeVersion: number = 0;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') @Watch('accountChanged') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: CharacterViewModel = new CharacterViewModel();
  @State isWide: boolean = false;
  @State contentWidth: number = 0;
  @State showGrid: boolean = false;
  @State showMobileDetail: boolean = false;
  @State selectingForPlan: boolean = false;
  @State propertiesExpanded: boolean = false;
  @State talentsExpanded: boolean = false;
  @State relicSetNames: Map<number, string> = new Map<number, string>();
  private detailScroller: Scroller = new Scroller();
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;
  /** 当前选中角色详情（页面 @State 驱动刷新；VM 内 @Observed 深属性不触发刷新） */
  @State currentDetail: CharacterDetail | undefined = undefined;
  @State showScoreSheet: boolean = false;
  @State scoreEdit: BackpackScoreEdit = new BackpackScoreEdit();
  private scoreEditAvatarId: number = 0;
  /** 当前选中角色 id（页面态） */
  @State selectedId: number = 0;
  @State @Watch('keepFilteredSelection') charTokens: CharacterFilterToken[] = [];
  @State charSort: CharacterSortKind = CharacterSortKind.Default;
  /** 养成计划选择半窗（多项目时让用户选，对齐 Windows 当前养成计划口径） */
  @State showPlanSheet: boolean = false;
  @State draftVm: CultivationDraftViewModel = new CultivationDraftViewModel();
  @State planSelectedIds: number[] = [];
  @State appliedLocaleVersion: number = -1;
  @State relicNames: Map<number, string> = new Map<number, string>();
  private attached: boolean = false;
  private metadataSequence: number = 0;

  accountChanged(): void {
    this.showScoreSheet = false;
    this.showPlanSheet = false; this.draftVm.cancel(); this.planSelectedIds = [];
    this.selectingForPlan = false; this.showMobileDetail = false; this.selectedId = 0; this.currentDetail = undefined;
    this.reload();
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.vm.dispose();
    this.metadataSequence++;
    this.showScoreSheet = false;
    this.draftVm.cancel();
  }

  aboutToAppear(): void {
    this.attached = true;
    this.vm.activate((): void => { this.onCharacterUpdated(); });
    this.showGrid = PreferencesStore.getNumber(VIEW_MODE_KEY, 0) === 1;
    const savedSort: number = PreferencesStore.getNumber(SORT_KEY, CharacterSortKind.Default);
    this.charSort = Number.isInteger(savedSort) && savedSort >= 0 && savedSort < SORT_LABELS.length
      ? savedSort as CharacterSortKind : CharacterSortKind.Default;
    this.loadDisplayMetadata();
    this.reload();
  }

  private onLocaleChanged(): void { this.loadDisplayMetadata(); }

  private async loadDisplayMetadata(): Promise<void> {
    if (!this.attached) { return; }
    const sequence: number = ++this.metadataSequence;
    const localeVersion: number = this.localeVersion;
    await WikiMetaService.ensureIconMaps();
    if (!this.attached || sequence !== this.metadataSequence) { return; }
    const names: Map<number, string> = await LocalizedGameDataService.names('Reliquary.json');
    if (!this.attached || sequence !== this.metadataSequence) { return; }
    const setNames: Map<number, string> = await LocalizedGameDataService.names('ReliquarySet.json');
    if (!this.attached || sequence !== this.metadataSequence) { return; }
    this.relicNames = names; this.relicSetNames = setNames;
    this.appliedLocaleVersion = localeVersion;
  }

  /** 页面显示：检测风控 → 自动弹验证窗（保持当前页上下文） */
  onPageShow(): void {
    if (this.currentDetail !== undefined) { this.vm.loadScoreOptions(this.currentDetail.id); }
    if (this.vm.needRiskVerify && !this.showVerify) {
      this.showVerify = true;
      return;
    }
    if (RiskUiHelper.hasPendingChallenge()) {
      // 用户刚完成验证：重放重载
      this.vm.resetRiskAndReload(this.currentUid);
    }
  }

  /** 缓存与每个成功批次直接更新页面，不等待整轮远端刷新。 */
  private onCharacterUpdated(): void {
    if (!this.attached) { return; }
    const visible: CharacterListItem[] = this.filteredItems();
    if (visible.length === 0) { this.selectedId = 0; this.currentDetail = undefined; return; }
    const selectionVisible: boolean = visible.some((item: CharacterListItem): boolean => item.id === this.vm.selectedId);
    if ((this.selectedId === 0 || !selectionVisible) && this.vm.selectedId !== visible[0].id) {
      this.vm.select(this.currentUid, visible[0].id);
      return;
    }
    this.syncDetail();
  }

  /** 页面详情使用整体引用替换，保留 V1 状态更新语义。 */
  syncDetail(): void {
    const previousId: number = this.currentDetail?.id ?? 0;
    this.selectedId = this.vm.selectedId;
    this.currentDetail = this.vm.detailOfSelected();
    if (this.currentDetail !== undefined && this.currentDetail.id !== previousId) {
      this.vm.loadScoreOptions(this.currentDetail.id);
    }
  }

  /** 选择角色：VM 切换 + 页面回填（守卫过期竞态结果，点击 id 与选中态不一致时丢弃） */
  selectCharacter(id: number, reveal: boolean = true): void {
    if (reveal) { this.showMobileDetail = true; }
    Logger.info(TAG, `selectCharacter id=${id}`);
    this.showScoreSheet = false;
    this.selectedId = id;
    const uid: string = this.currentUid;
    if (this.isWide) { this.detailScroller.scrollEdge(Edge.Top); }
    this.vm.select(uid, id).then(() => {
      Logger.info(TAG, `selectCharacter done id=${id} pageSel=${this.selectedId} vmSel=${this.vm.selectedId}`);
      if (!this.attached || this.currentUid !== uid || this.selectedId !== id) {
        return;
      }
      this.syncDetail();
    }).catch((e: Error) => {
      Logger.warn(TAG, `selectCharacter fail id=${id}: ${e.message}`);
    });
  }

  reload(): void {
    this.vm.load(this.currentUid).catch(() => { Logger.warn(TAG, 'character refresh interrupted'); });
  }

  private filteredItems(): CharacterListItem[] {
    return this.vm.filteredItems(this.charTokens, this.charSort, this.appliedLocaleVersion === this.localeVersion);
  }

  private displayAvatar(id: number): WikiAvatarMeta | undefined {
    return this.appliedLocaleVersion === this.localeVersion ? WikiMetaService.avatarOf(id) : undefined;
  }

  private avatarName(id: number, fallback: string): string {
    return this.displayAvatar(id)?.name || fallback;
  }

  private currentNameCardPic(): string {
    const detail: CharacterDetail | undefined = this.currentDetail;
    if (detail === undefined) { return ''; }
    return this.displayAvatar(detail.id)?.nameCardPic || WikiMetaService.nameCardPicOf(detail.name);
  }

  private currentSkills(): MetaSkill[] {
    const detail: CharacterDetail | undefined = this.currentDetail;
    if (detail === undefined) { return []; }
    return this.displayAvatar(detail.id)?.skills ?? WikiMetaService.skillsOfAvatar(detail.name);
  }

  private constellationMeta(cell: Constellation): MetaSkill | undefined {
    const detail: CharacterDetail | undefined = this.currentDetail;
    if (detail === undefined) { return undefined; }
    return this.displayAvatar(detail.id)?.talents.find((meta: MetaSkill): boolean =>
      (meta.canonicalName || meta.n) === cell.name);
  }

  private constellationName(cell: Constellation): string {
    return this.constellationMeta(cell)?.n || cell.name;
  }

  private currentWeaponName(): string {
    const detail: CharacterDetail | undefined = this.currentDetail;
    if (detail === undefined) { return ''; }
    const localized: string = this.appliedLocaleVersion === this.localeVersion
      ? WikiMetaService.nameOfWeapon(detail.weapon.id) : '';
    return localized || detail.weapon.name;
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1500 });
  }

  private keepFilteredSelection(): void {
    if (!this.attached) { return; }
    const visible: CharacterListItem[] = this.filteredItems();
    if (visible.some((item: CharacterListItem): boolean => item.id === this.selectedId)) { return; }
    if (visible.length === 0) { this.selectedId = 0; this.currentDetail = undefined; return; }
    this.selectCharacter(visible[0].id, false);
  }

  private rosterKey(item: CharacterListItem): string {
    const fields: string[] = [String(item.id), String(item.level), String(item.rarity), String(item.fetter),
      String(item.activedConstellationNum), String(this.selectedId === item.id),
      String(this.planSelectedIds.includes(item.id)), String(this.appliedLocaleVersion)];
    return fields.join('_');
  }

  private togglePlanSelection(id: number): void {
    this.planSelectedIds = this.planSelectedIds.includes(id)
      ? this.planSelectedIds.filter((selected: number): boolean => selected !== id) : this.planSelectedIds.concat(id);
  }

  private planSelectedCharacters(): void {
    if (!this.selectingForPlan || this.draftVm.busy) { return; }
    const selected: CharacterListItem[] = this.vm.items.filter((item: CharacterListItem): boolean =>
      this.planSelectedIds.includes(item.id));
    if (selected.length === 0) { return; }
    this.selectingForPlan = false;
    this.planSelectedIds = [];
    this.openBatchCharacterDraft(selected);
  }

  private activateRosterItem(item: CharacterListItem): void {
    if (this.selectingForPlan) { this.togglePlanSelection(item.id); }
    else { this.selectCharacter(item.id); }
  }

  private selectView(grid: boolean): void {
    this.showGrid = grid;
    PreferencesStore.setNumber(VIEW_MODE_KEY, grid ? 1 : 0);
  }

  private selectSort(index: number): void {
    if (this.charSort === index) { return; }
    this.charSort = index as CharacterSortKind;
    PreferencesStore.setNumber(SORT_KEY, index);
    const first: CharacterListItem | undefined = this.filteredItems()[0];
    if (first !== undefined) { this.selectCharacter(first.id, false); }
  }

  private listIcon(item: CharacterListItem): string {
    const meta: WikiAvatarMeta | undefined = this.displayAvatar(item.id);
    return meta?.sideIcon || meta?.icon || item.icon;
  }

  onBackPress(): boolean {
    if (!this.isWide && this.showMobileDetail) { this.showMobileDetail = false; return true; }
    return false;
  }

  private characterSortOptions(): SelectOption[] {
    return SORT_LABELS.map((label: string): SelectOption => ({ value: label }));
  }

  @Builder
  viewModeButton(grid: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Row() {
          SymbolGlyph(grid ? $r('sys.symbol.square_grid_2x2') : $r('sys.symbol.list_bullet'))
            .fontSize(17).fontColor([$r('app.color.text_primary')])
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        if (this.showGrid === grid) {
          Rect().width(16).height(2).borderRadius(1).fill($r('app.color.app_primary')).margin({ bottom: 1 })
        }
      }.width('100%').height('100%')
    }
    .width(40).height(34).padding(0).borderWidth(0).borderRadius(4)
    .backgroundColor(this.showGrid === grid ? $r('app.color.nav_selected') : Color.Transparent)
    .accessibilityText(grid ? '网格视图' : '列表视图').accessibilitySelected(this.showGrid === grid)
    .hoverEffect(HoverEffect.Highlight).onClick(() => this.selectView(grid))
  }

  @Builder
  viewSwitch() {
    Row() {
      this.viewModeButton(false)
      this.viewModeButton(true)
    }.attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
      .border({ width: 0.5, color: $r('app.color.card_stroke'), radius: 6 }).clip(true)
  }

  @Builder
  sortSelect() {
    Select(this.characterSortOptions()).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
      .font({ size: 13 }).selected(this.charSort).value(SORT_LABELS[this.charSort]).width(108).height(36)
      .accessibilityDescription('角色排序').hoverEffect(HoverEffect.Highlight)
      .onSelect((index: number): void => this.selectSort(index))
  }

  @Builder
  scoreSelect() {
    Select(this.scoreSelectOptions()).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
      .font({ size: 13 }).selected(this.vm.scoreOptionIndex)
      .value(this.vm.scoreOptions[this.vm.scoreOptionIndex]?.label ?? '米游社推荐属性')
      .width(this.isWide ? 148 : undefined).layoutWeight(this.isWide ? 0 : 1).height(36)
      .enabled(this.currentDetail !== undefined).accessibilityDescription($r('app.string.ui_avatar_property_score_algorithm'))
      .hoverEffect(HoverEffect.Highlight).onSelect((index: number): void => this.setScoreOption(index))
  }

  @Builder
  scoreButton() {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph($r('sys.symbol.info_circle')).fontSize(16).fontColor([$r('app.color.text_primary')])
    }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).width(36).height(36).padding(0)
      .accessibilityText('评分配置').enabled(this.currentDetail !== undefined).onClick(() => this.openScoreEditor())
  }

  @Builder
  toolbarLeading() {
    if (!this.isWide && this.showMobileDetail) {
      Button('返回角色', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44).onClick(() => { this.showMobileDetail = false; })
      Text(this.currentDetail !== undefined ? this.avatarName(this.currentDetail.id, this.currentDetail.name) : $r('app.string.ui_nav_character'))
        .fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else {
      this.viewSwitch()
      if (this.isWide) {
        this.sortSelect()
        this.scoreSelect()
        this.scoreButton()
        CharacterFilterBox({ tokens: this.charTokens }).layoutWeight(1)
      } else {
        Text(String(this.filteredItems().length) + ' 位角色').fontSize(12).fontColor($r('app.color.text_secondary'))
          .layoutWeight(1).maxLines(1)
      }
    }
  }

  @Builder
  exportMenu() {
    Menu() {
      MenuItem({ content: '导出当前角色' }).enabled(this.currentDetail !== undefined)
        .onClick(() => this.exportDetailText())
      MenuItem({ content: '导出所有角色' }).enabled(this.filteredItems().length > 0)
        .onClick(() => this.exportAllText())
    }
  }

  @Builder
  cultivationMenu() {
    Menu() {
      MenuItem({ content: '当前角色与武器' }).enabled(this.selectedId !== 0 && !this.draftVm.busy)
        .onClick(() => this.addCurrentWithWeapon())
      MenuItem({ content: '部分角色与武器' }).enabled(this.vm.items.length > 0 && !this.draftVm.busy)
        .onClick(() => { this.planSelectedIds = []; this.selectingForPlan = true; this.showMobileDetail = false; })
      MenuItem({ content: '所有角色与武器' }).enabled(this.vm.items.length > 0 && !this.draftVm.busy)
        .onClick(() => this.openBatchCharacterDraft(this.vm.items))
    }
  }

  @Builder
  moreMenu() {
    Menu() {
      if (!this.isWide) {
        MenuItem({ content: '导出文本到剪贴板', builder: (): void => { this.exportMenu(); } })
      }
      if (this.contentWidth < 1200) {
        MenuItem({ content: '养成计算', builder: (): void => { this.cultivationMenu(); } })
        MenuItem({ content: '同步角色信息' }).enabled(!this.vm.loading).onClick(() => this.reload())
      }
      // 触屏上同样可对选中角色执行列表右键菜单里的单项操作。
      MenuItem({ content: '添加角色到养成计划' }).enabled(this.selectedId !== 0 && !this.draftVm.busy)
        .onClick(() => this.addCurrentToPlan())
      MenuItem({ content: '添加武器到养成计划' }).enabled(this.selectedId !== 0 && !this.draftVm.busy)
        .onClick(() => this.addCurrentToPlan(true))
      MenuItem({ content: '米游社攻略' }).enabled(this.currentDetail !== undefined).onClick(() => this.openStrategy('mys'))
      MenuItem({ content: 'B站攻略' }).enabled(this.currentDetail !== undefined).onClick(() => this.openStrategy('bili'))
    }
  }

  @Builder
  toolbarTrailing() {
    if (this.isWide) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.arrow_right_to_line')).fontSize(15).fontColor([$r('app.color.text_primary')])
          Text('导出文本到剪贴板').fontSize(13).fontColor($r('app.color.text_primary'))
        }
      }.height(36).padding({ left: 8, right: 8 }).borderRadius(6).backgroundColor(Color.Transparent)
        .enabled(this.isLoggedIn).hoverEffect(HoverEffect.Highlight)
        .bindMenu((): void => { this.exportMenu(); }, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
    }
    if (this.contentWidth >= 1200) {
      Button('养成计算', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(36).borderRadius(6).fontSize(13).fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent)
        .enabled(this.isLoggedIn).hoverEffect(HoverEffect.Highlight)
        .bindMenu((): void => { this.cultivationMenu(); }, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
      Button('同步角色信息', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(36).borderRadius(6).fontSize(13).fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent)
        .enabled(this.isLoggedIn && !this.vm.loading).hoverEffect(HoverEffect.Highlight).onClick(() => this.reload())
    }
    Button('···', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
      .width(40).height(36).padding(0).borderRadius(6).fontSize(22).fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent).accessibilityText('更多角色操作')
      .enabled(this.isLoggedIn).hoverEffect(HoverEffect.Highlight)
      .bindMenu((): void => { this.moreMenu(); }, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
      .bindSheet($$this.showScoreSheet, this.scoreEditorSheet(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
        height: '80%', showClose: true, blurStyle: BlurStyle.Regular, backgroundColor: $r('app.color.sheet_material_tint') })
  }

  @Builder
  header() {
    Column({ space: 4 }) {
      PageToolbar({ embedMode: this.embedMode || (!this.isWide && this.showMobileDetail),
        leading: (): void => this.toolbarLeading(), trailing: (): void => this.toolbarTrailing() })
      if (!this.isWide && this.isLoggedIn) {
        Row({ space: 8 }) {
          if (this.showMobileDetail) {
            this.scoreSelect()
            this.scoreButton()
          } else {
            CharacterFilterBox({ tokens: this.charTokens }).layoutWeight(1)
            this.sortSelect()
          }
        }.width('100%').padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
      }
    }.width('100%').padding({ left: 12, right: 12, bottom: 10 })
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'AvatarProperty', iconSize: 60 })
      Text('需登录后查看角色')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Button('去登录', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  @Builder
  planMark(id: number) {
    Stack() {
      if (this.planSelectedIds.includes(id)) {
        NavIcon({ name: 'Check', iconSize: 14 })
      }
    }.width(22).height(22).borderRadius(4)
      .border({ width: 1, color: this.planSelectedIds.includes(id) ? $r('app.color.app_primary') : $r('app.color.text_secondary') })
      .accessibilityLevel('no')
  }

  @Builder
  rosterActions(item: CharacterListItem) {
    Menu() {
      MenuItem({ content: '添加角色到养成计划' }).onClick(() => this.openCharacterDraft([item]))
      MenuItem({ content: '添加武器到养成计划' }).onClick(() => this.openCharacterDraft([item], true))
      MenuItem({ content: '添加角色与武器到养成计划' }).onClick(() => this.addCurrentWithWeapon(item))
    }.enabled(!this.draftVm.busy)
  }

  @Builder
  characterRow(c: CharacterListItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column() {
          if (this.selectedId === c.id) {
            Rect().width(3).height(30).fill($r('app.color.app_primary')).borderRadius(2)
          }
        }.width(3)
        MetaIcon({ category: 'AvatarIcon', name: this.listIcon(c), iconSize: 42, remoteFallback: true })
        Column({ space: 3 }) {
          Text(this.avatarName(c.id, c.name)).fontSize(14)
            .fontWeight(this.selectedId === c.id ? FontWeight.Medium : FontWeight.Normal)
            .fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('Lv. ' + c.level).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.selectingForPlan) { this.planMark(c.id) }
      }.width('100%').padding({ left: 6, right: 8 })
    }
    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
    .width('100%').height(64).padding(0).border({ width: 0 }).borderRadius(6)
    .backgroundColor(this.selectedId === c.id ? $r('app.color.app_primary_bg') : Color.Transparent)
    .accessibilityGroup(true)
    .accessibilityText(this.avatarName(c.id, c.name) + '，等级 ' + c.level +
      (this.selectingForPlan ? (this.planSelectedIds.includes(c.id) ? '，已选择' : '，未选择') : ''))
    .onClick(() => this.activateRosterItem(c))
    .bindContextMenuWithResponse((): void => { this.rosterActions(c); },
      { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  characterTile(c: CharacterListItem) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(c.id) || c.icon, iconSize: 60, remoteFallback: true })
        Text(this.avatarName(c.id, c.name)).fontSize(12).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text('Lv. ' + c.level).fontSize(11).fontColor($r('app.color.text_secondary'))
          if (this.selectingForPlan) { this.planMark(c.id) }
        }
      }.width('100%').padding({ top: 8, bottom: 8, left: 4, right: 4 })
    }
    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
    .width('100%').padding(0).constraintSize({ minHeight: 116 }).borderRadius(6)
    .backgroundColor(this.selectedId === c.id ? $r('app.color.app_primary_bg') : Color.Transparent)
    .border({ width: this.selectedId === c.id ? 1 : 0, color: $r('app.color.app_primary') })
    .accessibilityGroup(true).accessibilityText(this.avatarName(c.id, c.name) + '，等级 ' + c.level)
    .onClick(() => this.activateRosterItem(c))
    .bindContextMenuWithResponse((): void => { this.rosterActions(c); },
      { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  planSelectionActions() {
    Button($r('app.string.common_cancel'), { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontSize(12).height(44)
      .onClick(() => { this.selectingForPlan = false; this.planSelectedIds = []; })
    Button('规划所选角色', { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).fontSize(12).height(44)
      .enabled(this.planSelectedIds.length > 0 && !this.draftVm.busy)
      .onClick(() => this.planSelectedCharacters())
  }

  @Builder
  rosterPanel() {
    Column({ space: 4 }) {
      if (this.showGrid) {
        Scroll() {
          GridRow({ columns: { xs: 2, sm: 3, md: 4 }, gutter: { x: 6, y: 6 },
            breakpoints: { value: ['320vp', '600vp'], reference: BreakpointsReference.ComponentSize } }) {
            ForEach(this.filteredItems(), (item: CharacterListItem) => {
              GridCol() { this.characterTile(item) }
            }, (item: CharacterListItem): string => this.rosterKey(item))
          }.width('100%')
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      } else {
        List({ space: 2 }) {
          ForEach(this.filteredItems(), (item: CharacterListItem) => {
            ListItem() { this.characterRow(item) }
          }, (item: CharacterListItem): string => this.rosterKey(item))
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      }
      if (this.selectingForPlan) {
        Row({ space: 4 }) {
          Text('已选 ' + this.planSelectedIds.length).fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          this.planSelectionActions()
        }.width('100%')
      }
      Text('共 ' + this.filteredItems().length + ' 位角色')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').textAlign(TextAlign.Center).padding(8)
    }
    .width(this.isWide ? (this.showGrid ? 284 : 220) : '100%').height('100%').padding(6)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
  }

  @Builder
  propertiesPanel() {
    Column({ space: 0 }) {
      Button({ type: ButtonType.Normal }) {
        Row() {
          Text('角色属性').fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
          SymbolGlyph(this.propertiesExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14).fontColor([$r('app.color.text_secondary')])
        }.width('100%').padding({ left: 14, right: 14 })
      }
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
      .width('100%').height(48).padding(0).backgroundColor(Color.Transparent)
      .onClick(() => { this.propertiesExpanded = !this.propertiesExpanded; })
      if (this.propertiesExpanded && this.currentDetail !== undefined) {
        GridRow({ columns: this.isWide ? 2 : 1, gutter: { x: 24, y: 8 } }) {
          ForEach(this.currentDetail.selectedProperties, (property: BaseProperty) => {
            GridCol() {
              Row({ space: 10 }) {
                Text(CharacterPage.propLabel(property.propertyType)).fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
                Text(property.final || property.base + '+' + property.add).fontSize(13).fontColor($r('app.color.text_primary'))
              }.width('100%').constraintSize({ minHeight: 28 })
            }
          }, (property: BaseProperty): string => property.propertyType + '_' + property.final + '_' + property.base + '_' + property.add)
        }.width('100%').padding({ left: 14, right: 14, bottom: 14 })
      }
    }.width('100%').attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
  }

  private recommendation(slot: number): string {
    const detail: CharacterDetail | undefined = this.currentDetail;
    if (detail === undefined) { return ''; }
    let properties: string[] = detail.recommend.subProperties;
    if (slot === 0) { properties = detail.recommend.sandMainProperties; }
    else if (slot === 1) { properties = detail.recommend.gobletMainProperties; }
    else if (slot === 2) { properties = detail.recommend.circletMainProperties; }
    const labels: string[] = [];
    for (const property of properties) {
      const label: string = CharacterPage.propLabel(property);
      if (!labels.includes(label)) { labels.push(label); }
    }
    return labels.length > 0 ? labels.join(' · ') : '未提供推荐';
  }

  @Builder
  recommendationTile(slot: number) {
    Column({ space: 10 }) {
      Text(['时之沙主属性推荐', '空之杯主属性推荐', '理之冠主属性推荐', '追加属性推荐'][slot])
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        Text(this.recommendation(slot)).fontSize(14).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (slot === 0) {
          Image($r('app.media.UI_Icon_RelicType3')).width(30).height(30).renderMode(ImageRenderMode.Template)
            .fillColor($r('app.color.text_secondary')).opacity(0.65).accessibilityLevel('no')
        } else if (slot === 1) {
          Image($r('app.media.UI_Icon_RelicType4')).width(30).height(30).renderMode(ImageRenderMode.Template)
            .fillColor($r('app.color.text_secondary')).opacity(0.65).accessibilityLevel('no')
        } else if (slot === 2) {
          Image($r('app.media.UI_Icon_RelicType5')).width(30).height(30).renderMode(ImageRenderMode.Template)
            .fillColor($r('app.color.text_secondary')).opacity(0.65).accessibilityLevel('no')
        }
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 92 }).padding(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
  }

  @Builder
  recommendationPanel() {
    GridRow({ columns: { xs: 1, sm: 2, md: 4 }, gutter: { x: 10, y: 10 },
      breakpoints: { value: ['320vp', '800vp'], reference: BreakpointsReference.ComponentSize } }) {
      ForEach([0, 1, 2, 3], (slot: number) => {
        GridCol() { this.recommendationTile(slot) }
      }, (slot: number): string => String(slot))
    }.width('100%')
  }

  private relicKey(relic: Reliquary): string {
    return String(this.selectedId) + '_' + relic.id + '_' + relic.pos + '_' + relic.level + '_' +
      this.vm.scoreOptionIndex + '_' + this.vm.scoreSettings.revision + '_' + this.appliedLocaleVersion + '_' +
      relic.mainProperty.value + '_' + JSON.stringify(relic.subProperties);
  }

  @Builder
  relicCard(relic: Reliquary) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        MetaIcon({ category: 'RelicIcon', name: CharacterPage.relicIconName(relic.icon), iconSize: 42 })
        Column({ space: 3 }) {
          Text(this.relicNames.get(relic.id) || relic.name).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.relicSetNames.get(relic.setId) || relic.setName || relic.posName)
            .fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        Text('+' + relic.level + ' · ' + '★'.repeat(Math.max(0, Math.min(5, relic.rarity))))
          .fontSize(12).fontColor($r('app.color.text_secondary'))
        Text(this.relicScoreOf(relic).toFixed(1) + ' 分').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.five_star'))
      }.width('100%')
      Divider().color($r('app.color.card_stroke'))
      Row({ space: 8 }) {
        Text(CharacterPage.relicPropLabel(relic.mainProperty.propertyType)).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(relic.mainProperty.value).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      }.width('100%').constraintSize({ minHeight: 32 })
      Divider().color($r('app.color.card_stroke'))
      Column({ space: 4 }) {
        ForEach(relic.subProperties, (property: RelicProperty) => {
          Row({ space: 7 }) {
            Text(CharacterPage.relicPropLabel(property.propertyType)).fontSize(12).fontColor($r('app.color.text_secondary'))
              .layoutWeight(1).maxLines(2)
            Text(property.value).fontSize(13).fontColor($r('app.color.text_primary'))
            Text(String(property.times + 1)).fontSize(11).fontColor($r('app.color.four_star'))
              .width(18).height(18).textAlign(TextAlign.Center).borderRadius(9)
              .border({ width: 1, color: $r('app.color.four_star') })
              .accessibilityText('包含初始词条，共 ' + (property.times + 1) + ' 次')
          }.width('100%').constraintSize({ minHeight: 28 })
        }, (property: RelicProperty): string => property.propertyType + '_' + property.value + '_' + property.times)
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 244 }).padding(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
  }

  @Builder
  additionalDetails() {
    Column({ space: 0 }) {
      Button(this.talentsExpanded ? '收起天赋与命座详情' : '天赋与命座详情', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .width('100%').height(44).onClick(() => { this.talentsExpanded = !this.talentsExpanded; })
      if (this.talentsExpanded && this.currentDetail !== undefined) {
        if (this.currentDetail.weapon.id > 0) {
          Text(this.currentWeaponName() + ' · ' + PromoteState.label(this.currentDetail.weapon.promoteLevel))
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding(12)
        }
        ForEach(this.currentSkills(), (skill: MetaSkill, index: number) => {
          Column({ space: 6 }) {
            Text(skill.n + ' ' + this.skillLevelAt(index)).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).width('100%')
            Text(WikiMetaService.cleanText(skill.d)).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }.width('100%').padding(12)
        }, (skill: MetaSkill, index: number): string => String(this.selectedId) + '_' + index + '_' + this.appliedLocaleVersion + '_' + this.skillLevelAt(index))
        ForEach(this.currentDetail.constellations, (entry: Constellation) => {
          Column({ space: 6 }) {
            Text(this.constellationName(entry)).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
            Text(WikiMetaService.cleanText(this.constellationMeta(entry)?.d || entry.effect)).fontSize(12)
              .fontColor($r('app.color.text_secondary')).width('100%')
          }.width('100%').padding(12)
        }, (entry: Constellation): string => String(this.selectedId) + '_' + entry.id + '_' + this.appliedLocaleVersion)
      }
    }.width('100%').attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
  }

  @Builder
  detailPanel() {
    Column({ space: 12 }) {
      if (this.currentDetail !== undefined) {
        this.detailHeader()
        this.propertiesPanel()
        this.recommendationPanel()
        GridRow({ columns: { xs: 1, sm: 2, md: 3 }, gutter: { x: 10, y: 10 },
          breakpoints: { value: ['360vp', '720vp'], reference: BreakpointsReference.ComponentSize } }) {
          ForEach(this.currentDetail.reliquaries, (relic: Reliquary) => {
            GridCol() { this.relicCard(relic) }
          }, (relic: Reliquary): string => this.relicKey(relic))
        }.width('100%')
        this.additionalDetails()
      }
    }.width('100%')
  }

  private nameCardData(): CharacterNameCardData {
    const card: CharacterNameCardData = new CharacterNameCardData();
    const detail: CharacterDetail | undefined = this.currentDetail;
    if (detail === undefined) { return card; }
    card.avatarId = detail.id;
    card.name = this.avatarName(detail.id, detail.name);
    card.icon = WikiMetaService.iconOfAvatar(detail.id) || detail.icon;
    card.level = detail.level; card.rarity = detail.rarity; card.fetter = detail.fetter;
    card.scoreText = detail.reliquaries.length > 0 ? this.totalRelicScore().toFixed(1) + ' 分' : '';
    card.nameCardPic = this.currentNameCardPic();
    card.weaponName = this.currentWeaponName();
    card.weaponIcon = WikiMetaService.iconOfWeapon(detail.weapon.id);
    card.weaponLevel = detail.weapon.level; card.weaponRarity = detail.weapon.rarity;
    card.refinement = detail.weapon.affixLevel;
    const metadata: MetaSkill[] = this.currentSkills();
    for (const kind of ['A', 'E', 'Q']) {
      const skill: CharacterNameCardSkill = new CharacterNameCardSkill();
      const index: number = metadata.findIndex((item: MetaSkill): boolean => SkillLevelService.kindOfMetaSkill(detail, item) === kind);
      if (index >= 0) {
        const item: MetaSkill = metadata[index];
        skill.id = index + 1; skill.name = item.n; skill.icon = item.i;
        skill.description = WikiMetaService.cleanText(item.d);
        skill.levelText = this.skillLevelAt(index);
      }
      card.skills.push(skill);
    }
    for (const entry of detail.constellations) {
      const item: CharacterNameCardConstellation = new CharacterNameCardConstellation();
      const meta: MetaSkill | undefined = this.constellationMeta(entry);
      item.id = entry.id; item.pos = entry.pos; item.name = this.constellationName(entry);
      item.icon = meta?.i || entry.icon; item.active = entry.isActived; item.known = entry.activationKnown;
      item.description = WikiMetaService.cleanText(meta?.d || entry.effect);
      card.constellations.push(item);
    }
    return card;
  }

  private showCharacterInfo(title: string, description: string): void {
    this.getUIContext().showAlertDialog({ systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
      title: title, message: description.length > 0 ? description : '暂无说明',
      primaryButton: { value: $r('app.string.ui_exception_close'), action: () => {} } });
  }

  @Builder
  detailHeader() {
    CharacterNameCard({ data: this.nameCardData(), compact: !this.isWide, cardHeight: this.isWide ? Math.min(400, Math.max(320, (this.contentWidth - 244) * 0.46)) : 300,
      onSkill: (skill: CharacterNameCardSkill) => { this.showCharacterInfo(skill.name + ' · ' + skill.levelText, skill.description); },
      onConstellation: (entry: CharacterNameCardConstellation) => { this.showCharacterInfo(entry.name, entry.description); } })
  }

  @Builder
  planPickerSheet() {
    CultivationDraftEditor({ vm: this.draftVm, uid: this.currentUid,
      onClose: (): void => { this.showPlanSheet = false; this.draftVm.cancel(); } })
  }

  /** 导出当前角色文本到剪贴板（对齐 Windows ExportToTextCommand，默认模板固定拼装） */
  private exportDetailText(): void {
    const d: CharacterDetail | undefined = this.currentDetail;
    if (d === undefined) {
      return;
    }
    const text: string = CharacterExportService.buildExportText(d,
      (t: string): string => CharacterPage.propLabel(t), this.vm.scoreWeights(d.id));
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('已复制');
    }).catch(() => {
      this.toast('复制失败');
    });
  }

  private async exportAllText(): Promise<void> {
    const visible: CharacterListItem[] = this.filteredItems();
    if (visible.length === 0) { this.toast('没有可导出的角色'); return; }
    const texts: string[] = [];
    for (const item of visible) {
      const detail: CharacterDetail | undefined = this.vm.detailMap.get(item.id);
      if (detail === undefined) {
        this.toast('列表中还有角色缺少详情，请同步角色信息后再导出');
        return;
      }
      texts.push(CharacterExportService.buildExportText(detail,
        (type: string): string => CharacterPage.propLabel(type), this.vm.scoreWeights(detail.id)));
    }
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, texts.join('\n\n')));
      this.toast(`已复制 ${texts.length} 个角色`);
    } catch (e) {
      this.toast('复制失败');
    }
  }

  private addCurrentToPlan(weaponOnly: boolean = false): void {
    const character: CharacterListItem | undefined = this.vm.items.find((item: CharacterListItem): boolean => item.id === this.selectedId);
    if (character !== undefined) { this.openCharacterDraft([character], weaponOnly); }
  }

  private openCharacterDraft(items: CharacterListItem[], weaponOnly: boolean = false): void {
    if (this.draftVm.busy || items.length === 0) { return; }
    this.showPlanSheet = true;
    this.draftVm.characters(this.currentUid, items.slice(), weaponOnly).then(() => {});
  }

  private addCurrentWithWeapon(character?: CharacterListItem): void {
    const target: CharacterListItem | undefined = character ??
      this.vm.items.find((item: CharacterListItem): boolean => item.id === this.selectedId);
    if (target === undefined || this.draftVm.busy) { return; }
    this.showPlanSheet = true;
    this.draftVm.characterAndWeapon(this.currentUid, target).then(() => {});
  }

  private openBatchCharacterDraft(items: CharacterListItem[]): void {
    if (this.draftVm.busy || items.length === 0) { return; }
    this.showPlanSheet = true;
    this.draftVm.batchCharacters(this.currentUid, items.slice()).then(() => {});
  }

  static kindLabel(k: string): string {
    switch (k) {
      case 'A': return '普攻';
      case 'E': return '战技';
      case 'Q': return '元素爆发';
      case 'P': return '被动';
      default: return '其他';
    }
  }

  /** Skill IDs join verified metadata; unknown mapping is displayed explicitly. */
  private skillLevelAt(idx: number): string {
    const detail: CharacterDetail | undefined = this.currentDetail;
    const meta: MetaSkill | undefined = this.currentSkills()[idx];
    if (detail === undefined || meta === undefined) { return ''; }
    const skill: ResolvedAvatarSkill | undefined = SkillLevelService.forMetaSkill(detail, meta);
    return skill !== undefined ? SkillLevelService.formatSkill(skill)
      : ['A', 'E', 'Q'].indexOf(SkillLevelService.kindOfMetaSkill(detail, meta)) >= 0 ? '等级未知' : '';
  }

  /** 战斗天赋等级徽章（无参读取组件状态；参数 name/idx 为常量槽位，满足 @Builder 刷新规则） */
  @Builder
  skillLevelBadge(idx: number) {
    if (this.skillLevelAt(idx).length > 0) {
      Text(this.skillLevelAt(idx))
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.app_primary_text'))
        .padding({ left: 6, right: 6, top: 1, bottom: 1 })
        .borderRadius(7)
        .backgroundColor($r('app.color.app_primary_bg'))
    }
  }

  /** 攻略外链：米游社/B站搜索当前角色（openLink 拉起浏览器） */
  openStrategy(target: string): void {
    if (this.currentDetail === undefined) {
      return;
    }
    const name: string = this.currentDetail.name;
    const url: string = target === 'mys'
      ? `https://www.miyoushe.com/ys/search?keyword=${encodeURIComponent(name + ' 攻略')}`
      : `https://search.bilibili.com/all?keyword=${encodeURIComponent('原神 ' + name + ' 攻略')}`;
    try {
      const host = this.getUIContext().getHostContext();
      if (host === undefined) {
        return;
      }
      const ui = host as common.UIAbilityContext;
      ui.openLink(url).catch((e: Error) => {
        this.toast(`打开失败：${e.message}`);
      });
    } catch (e) {
      this.toast(`打开失败：${(e as Error).message}`);
    }
  }

  /** 圣遗物图标名：API 可能带位置后缀 _N（CDN/打包无该变体），回退基础名 */
  static relicIconName(icon: string): string {
    if (icon.length === 0) {
      return '';
    }
    if (/_[0-9]$/.test(icon)) {
      const base: string = icon.substring(0, icon.lastIndexOf('_'));
      if (base.length > 0) {
        return base;
      }
    }
    return icon;
  }

  private relicScoreOf(reliquary: Reliquary): number {
    const detail: CharacterDetail | undefined = this.currentDetail;
    return detail === undefined ? 0 : ReliquaryScore.forCharacter(reliquary, detail, this.vm.scoreWeights(detail.id));
  }

  private totalRelicScore(): number {
    const detail: CharacterDetail | undefined = this.currentDetail;
    return detail === undefined ? 0 : ReliquaryScore.totalForCharacter(detail, this.vm.scoreWeights(detail.id));
  }

  private scoreSelectOptions(): SelectOption[] {
    return this.vm.scoreOptions.map((option: CharacterScoreOption): SelectOption => ({ value: option.label }));
  }

  private setScoreOption(index: number): void {
    if (this.currentDetail !== undefined) {
      this.vm.selectScoreOption(this.currentDetail.id, index);
    }
  }

  private openScoreEditor(): void {
    if (this.currentDetail === undefined) { return; }
    this.scoreEditAvatarId = this.currentDetail.id;
    this.scoreEdit = this.vm.beginScoreEdit(this.scoreEditAvatarId);
    this.showScoreSheet = true;
  }

  private saveScore(profile: BackpackScoreProfile, deletedIds: string[]): void {
    try {
      this.vm.saveScore(this.scoreEditAvatarId, this.scoreEdit, profile, deletedIds);
      this.showScoreSheet = false;
    } catch (e) {
      this.toast((e as Error).message);
    }
  }

  @Builder
  scoreEditorSheet() {
    Scroll() {
      Column() {
        ReliquaryScoreEditor({
          initialProfile: this.scoreEdit.profile,
          savedProfiles: this.vm.scoreSettings.profiles,
          warning: this.vm.scoreSettings.warning,
          onConfirm: (profile: BackpackScoreProfile, deletedIds: string[]) => this.saveScore(profile, deletedIds),
          onCancel: () => { this.showScoreSheet = false; }
        })
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }

  static relicPropLabel(type: string): string {
    if (type === '2' || type === 'FIGHT_PROP_HP') { return '生命值'; }
    if (type === '5' || type === 'FIGHT_PROP_ATTACK') { return '攻击力'; }
    if (type === '8' || type === 'FIGHT_PROP_DEFENSE') { return '防御力'; }
    return CharacterPage.propLabel(type);
  }

  /** 属性类型 → 中文标签（兼容：字符串 FIGHT_PROP_* 与数字 FightProperty 枚举） */
  static propLabel(type: string): string {
    switch (type) {
      case '2':
      case 'FIGHT_PROP_HP':
      case 'FIGHT_PROP_MAX_HP':
      case '2000': return '生命值上限';
      case '5':
      case 'FIGHT_PROP_ATTACK':
      case 'FIGHT_PROP_CUR_ATTACK':
      case '2001': return '攻击力';
      case '8':
      case 'FIGHT_PROP_DEFENSE':
      case 'FIGHT_PROP_CUR_DEFENSE':
      case '2002': return '防御力';
      case 'FIGHT_PROP_HP_PERCENT':
      case '3':
      case '3.0': return '生命值';
      case 'FIGHT_PROP_ATTACK_PERCENT':
      case '6':
      case '6.0': return '攻击力';
      case 'FIGHT_PROP_DEFENSE_PERCENT':
      case '9':
      case '9.0': return '防御力';
      case 'FIGHT_PROP_BASE_HP':
      case '1': return '基础生命值';
      case 'FIGHT_PROP_BASE_ATTACK':
      case '4': return '基础攻击力';
      case 'FIGHT_PROP_BASE_DEFENSE':
      case '7': return '基础防御力';
      case 'FIGHT_PROP_CRITICAL':
      case '20': return '暴击率';
      case 'FIGHT_PROP_CRITICAL_HURT':
      case '22': return '暴击伤害';
      case 'FIGHT_PROP_ELEMENT_MASTERY':
      case '28': return '元素精通';
      case 'FIGHT_PROP_CHARGE_EFFICIENCY':
      case '23': return '元素充能效率';
      case 'FIGHT_PROP_HEAL_ADD':
      case '26': return '治疗加成';
      case 'FIGHT_PROP_HEALED_ADD':
      case '27': return '受治疗加成';
      case 'FIGHT_PROP_FIRE_ADD_HURT':
      case '40': return '火元素伤害加成';
      case 'FIGHT_PROP_WATER_ADD_HURT':
      case '42': return '水元素伤害加成';
      case 'FIGHT_PROP_GRASS_ADD_HURT':
      case '43': return '草元素伤害加成';
      case 'FIGHT_PROP_ELEC_ADD_HURT':
      case '41': return '雷元素伤害加成';
      case 'FIGHT_PROP_ICE_ADD_HURT':
      case '46': return '冰元素伤害加成';
      case 'FIGHT_PROP_WIND_ADD_HURT':
      case '44': return '风元素伤害加成';
      case 'FIGHT_PROP_ROCK_ADD_HURT':
      case '45': return '岩元素伤害加成';
      case 'FIGHT_PROP_PHYSICAL_ADD_HURT':
      case '30': return '物理伤害加成';
      case 'FIGHT_PROP_FIRE_SUB_HURT':
      case '50': return '火元素抗性';
      case 'FIGHT_PROP_WATER_SUB_HURT':
      case '52': return '水元素抗性';
      case 'FIGHT_PROP_GRASS_SUB_HURT':
      case '53': return '草元素抗性';
      case 'FIGHT_PROP_ELEC_SUB_HURT':
      case '51': return '雷元素抗性';
      case 'FIGHT_PROP_ICE_SUB_HURT':
      case '56': return '冰元素抗性';
      case 'FIGHT_PROP_WIND_SUB_HURT':
      case '54': return '风元素抗性';
      case 'FIGHT_PROP_ROCK_SUB_HURT':
      case '55': return '岩元素抗性';
      case 'FIGHT_PROP_PHYSICAL_SUB_HURT':
      case '29': return '物理抗性';
      case 'FIGHT_PROP_SPEED_PERCENT':
      case '11': return '移动速度';
      case 'FIGHT_PROP_SKILL_CD_MINUS_RATIO':
      case '80': return '冷却缩减';
      case 'FIGHT_PROP_CUR_HP':
      case '1010': return '当前生命值';
      default: return type;
    }
  }

  @Builder
  detailViewport() {
    Scroll(this.detailScroller) {
      Column({ space: 12 }) {
        if (this.currentDetail !== undefined) {
          this.detailPanel()
        } else if (this.vm.loading || this.vm.detailLoading || this.vm.loadingDetail) {
          LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
          Text('加载详情中...').fontSize(13).fontColor($r('app.color.text_secondary'))
        } else {
          Text('选择角色查看详情').fontSize(13).fontColor($r('app.color.text_secondary'))
        }
      }.width('100%').padding({ bottom: 16, right: this.isWide ? 4 : 0 })
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column({ space: 0 }) {
        this.header()
        if (!this.isLoggedIn) {
          this.loginGuide()
        } else {
          if (this.vm.loading || this.vm.message.length > 0) {
            Row({ space: 8 }) {
              if (this.vm.loading) { LoadingProgress().width(20).height(20).color($r('app.color.app_primary')) }
              Text(this.vm.message || '正在同步角色数据...').fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
            }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
          }
          if (this.vm.items.length === 0 && !this.vm.loading) {
            Text('暂无角色数据').fontSize(14).fontColor($r('app.color.text_secondary')).padding(24)
          } else if (this.isWide) {
            Row({ space: 12 }) {
              this.rosterPanel()
              Column() { this.detailViewport() }.layoutWeight(1).height('100%')
            }.width('100%').layoutWeight(1).padding({ left: 12, right: 12, bottom: 12 })
          } else {
            Column() {
              if (this.showMobileDetail) { this.detailViewport() }
              else { this.rosterPanel() }
            }.width('100%').layoutWeight(1).padding({ left: 12, right: 12, bottom: 12 })
          }
        }
      }
      .width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => {
        const nextWide: boolean = Number(area.width) >= 840;
        if (this.isWide && !nextWide && this.currentDetail !== undefined) { this.showMobileDetail = true; }
        this.contentWidth = Number(area.width); this.isWide = nextWide;
      })
      .bindSheet(this.showVerify, () => {
        RiskVerifyDialog({ isShow: this.showVerify, gt: this.vm.riskGt, challenge: this.vm.riskChallenge, path: this.vm.riskPath,
          onDone: (challenge: string) => {
            AppStorage.setOrCreate<string>(RiskUiHelper.KEY_PENDING, challenge);
            this.vm.resetRiskAndReload(this.currentUid);
          } })
      }, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel), height: 420,
        backgroundColor: $r('app.color.sheet_material_tint'), showClose: false, blurStyle: BlurStyle.Regular })
      .bindSheet($$this.showPlanSheet, this.planPickerSheet(), {
        systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel), title: { title: '加入养成计划' },
        showClose: true, dragBar: true, height: '90%', onDisappear: (): void => { this.draftVm.cancel(); },
        blurStyle: BlurStyle.Regular, backgroundColor: $r('app.color.sheet_material_tint') })
    }.width('100%').height('100%')
  }
}
