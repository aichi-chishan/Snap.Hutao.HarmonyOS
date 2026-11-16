import { WishHistoryWikiParams } from '../model/WishHistory';
import { CultivationDraftViewModel } from '../viewmodel/CultivationDraftViewModel';
import { CultivationDraftEditor } from '../components/CultivationDraftEditor';
/**
 * WikiAvatarPage.ets（@Entry）
 * 角色资料（对齐 Windows WikiAvatarPage）：列表/详情双栏（宽屏）/ 单栏切换（窄屏）。
 * 数据：本地元数据 rawfile/metadata/avatar_meta.json（Snap.Metadata 公开仓库提取）；
 * 图标：rawfile/icons（离线）。区块：简介(元素/武器/生日/命座/CV)、养成材料、基础属性曲线(滑条+突破)、天赋技能、命座、料理、语音、故事。
 */
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { WikiMetaService, WikiAvatarMeta, AvatarCostumeMeta, MetaSkill, MetaText, MetaMaterial } from '../service/WikiMetaService';
import { StandardIconService } from '../data/remote/StandardIconService';
import { CharacterViewModel, AddPlanResult } from '../viewmodel/CharacterViewModel';
import { CharacterDetail } from '../model/CharacterData';
import { CultivationRepo, CultivateProject } from '../data/repo/CultivationRepo';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { AppContextProvider } from '../common/AppContext';
import { AppBackButton } from '../components/AppBackButton';
import { PageBackdrop } from '../components/PageBackdrop';
import { PageToolbar } from '../components/PageToolbar';
import { AvatarSkillParameterService } from '../service/AvatarSkillParameterService';
import { AvatarWikiSkill, AvatarSkillParameterRow } from '../model/AvatarWikiSkill';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { WikiAvatarFilter, WikiAvatarToken, WikiAvatarTokenKind } from '../service/WikiAvatarFilter';
import { WikiAvatarGuide } from '../service/WikiAvatarGuide';
import { AppLocaleService } from '../service/AppLocaleService';
import { BaseValueService, AvatarGrowInfo, AvatarBaseValues } from '../service/BaseValueService';
import { Logger } from '../common/Logger';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, UiSurface } from '../common/UiSurface';

const AVATAR_PAGE_TAG: string = 'WikiAvatarPage';
/** 立绘 CDN 类目（对齐 Windows GachaAvatarImgConverter：2048×1024 横版完整立绘） */
const SPLASH_IMG_CATEGORY: string = 'GachaAvatarImg';
/** 角色抠图类目（320×1024 竖版；完整立绘缺失时回退，包内已预打包） */
const SPLASH_ICON_CATEGORY: string = 'GachaAvatarIcon';
/** 皮肤立绘类目（对齐 Windows CostumeConverter：官方静态 CDN Costumes 全身立绘） */
const COSTUME_ART_CATEGORY: string = 'Costume';

/**
 * 单张角色立绘（按需拉取 + 沙盒缓存）：
 * 首选 GachaAvatarImg（UI_Gacha_AvatarImg_{icon 去掉 UI_AvatarIcon_ 前缀}，对齐 Windows
 * GachaAvatarImgConverter，2048×1024 横版完整立绘，容器按 2:1 呈现）；
 * 旅行者等 CDN 缺失时回退 GachaAvatarIcon 竖版抠图，均缺失显示占位。
 * costumeFrontIcon 非空（皮肤 FrontIcon，UI_AvatarIcon_XxxCostumeYyy）时改取
 * Costume/UI_Costume_X 皮肤立绘（同一套缓存→rawfile→CDN 三级解析）。
 */
@Component
export struct SplashArtView {
  @Prop @Watch('onIconChanged') icon: string = '';
  /** 皮肤立绘覆盖（非默认服装的 FrontIcon；空串=默认立绘） */
  @Prop @Watch('onIconChanged') costumeFrontIcon: string = '';
  @State src: string = '';
  private resolveToken: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.resolve();
  }

  aboutToDisappear(): void { this.active = false; this.resolveToken++; }

  private current(token: number): boolean { return this.active && token === this.resolveToken; }

  onIconChanged(): void {
    this.resolve();
  }

  private async resolve(): Promise<void> {
    const token: number = ++this.resolveToken;
    if (!this.active) { return; }
    // A replaced avatar must not display the previous identity while its image is loading.
    this.src = '';
    if (/^UI_AvatarIcon_[A-Za-z0-9_-]+$/.test(this.costumeFrontIcon)) {
      // 皮肤立绘（Costume 类目，包内不预打包；缓存 → rawfile → CDN 三级解析）
      const artName: string = `UI_Costume_${this.costumeFrontIcon.substring('UI_AvatarIcon_'.length)}`;
      const artPath: string = await this.cachedOrFetch(COSTUME_ART_CATEGORY, artName, token);
      if (this.current(token)) {
        this.src = artPath;
      }
      return;
    }
    if (!/^UI_AvatarIcon_[A-Za-z0-9_-]+$/.test(this.icon)) { return; }
    const suffix: string = this.icon.substring('UI_AvatarIcon_'.length);
    // 1) 完整立绘（GachaAvatarImg，未预打包，走缓存→CDN）
    const imgPath: string = await this.cachedOrFetch(SPLASH_IMG_CATEGORY,
      `UI_Gacha_AvatarImg_${suffix}`, token);
    if (!this.current(token)) { return; }
    if (imgPath.length > 0) {
      this.src = imgPath;
      return;
    }
    // 2) 竖版抠图兜底（GachaAvatarIcon，包内预打包 + CDN）
    const iconPath: string = await this.cachedOrFetch(SPLASH_ICON_CATEGORY,
      `UI_Gacha_AvatarIcon_${suffix}`, token);
    if (this.current(token)) {
      this.src = iconPath;
    }
  }

  /** 单类目三级解析：沙盒缓存 → rawfile 预打包 → 静态 CDN（StandardIconService） */
  private async cachedOrFetch(category: string, name: string, token: number): Promise<string> {
    if (!this.current(token)) { return ''; }
    const dir: string = `${AppContextProvider.getCacheDir()}/rawicons/${category}`;
    const dest: string = `${dir}/${name}.png`;
    // 1) 沙盒缓存命中（含已从 rawfile 落盘过的）
    try {
      if (fileIo.accessSync(dest)) {
        return fileUri.getUriFromPath(dest);
      }
    } catch (e) {
      // 未缓存，继续
    }
    // 2) rawfile 预打包（离线可用）→ 落盘缓存
    try {
      const raw: Uint8Array = await AppContextProvider.getResourceManager()
        .getRawFileContent(`icons/${category}/${name}.png`);
      if (!this.current(token)) { return ''; }
      SplashArtView.ensureDir(dir);
      SplashArtView.writeCache(dest, raw);
      return fileUri.getUriFromPath(dest);
    } catch (e) {
      // 包内无该图，继续
    }
    // 3) 静态 CDN 按需拉取
    if (!this.current(token)) { return ''; }
    try {
      const path: string = await StandardIconService.ensure(category, name);
      return this.current(token) && path.length > 0 ? fileUri.getUriFromPath(path) : '';
    } catch (e) {
      return '';
    }
  }

  /** 逐级创建目录（fileIo.mkdirSync 非递归） */
  private static ensureDir(full: string): void {
    try {
      fileIo.mkdirSync(full);
      return;
    } catch (e) {
      // 已存在或父目录缺失：逐级创建
    }
    const segs: string[] = full.split('/');
    let cur: string = full.startsWith('/') ? '/' : '';
    for (const seg of segs) {
      if (seg.length === 0) {
        continue;
      }
      cur += cur.length > 0 && cur !== '/' ? `/${seg}` : seg;
      try {
        fileIo.mkdirSync(cur);
      } catch (e) {
        // 已存在
      }
    }
  }

  /** Publish only a complete, closed write from an OS-unique staging directory. */
  private static writeCache(dest: string, raw: Uint8Array): void {
    const staging: string = fileIo.mkdtempSync(`${dest}.stage-XXXXXX`);
    const temporary: string = `${staging}/image.png`;
    try {
      const file = fileIo.openSync(temporary, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        const buffer: ArrayBuffer = new Uint8Array(raw).buffer as ArrayBuffer;
        if (fileIo.writeSync(file.fd, buffer) !== buffer.byteLength) { throw new Error('Incomplete icon cache write'); }
      } finally { fileIo.closeSync(file); }
      fileIo.renameSync(temporary, dest);
    } finally {
      // The OS returned this directory to this operation; never remove the shared cache parent.
      try { fileIo.rmdirSync(staging); } catch (_) { /* Cache cleanup is best effort. */ }
    }
  }

  build() {
    Stack() {
      if (this.src.length > 0) {
        Image(this.src)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        Column() {
          Text('暂无立绘')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.5)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_inner_tint'))
  }
}

@Entry
@Component
export struct WikiAvatarPage {
  @StorageProp('helpLocaleVersion') @Watch('onLocaleChanged') localeVersion: number = 0;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  /** Metadata and route ownership belong to this mounted page only. */
  private active: boolean = false;
  private loadSequence: number = 0;
  private routeItemId: number = 0;
  private routeRequested: boolean = false;
  @State routeMessage: string = '';
  @State avatars: WikiAvatarMeta[] = [];
  @State materials: Map<number, MetaMaterial> = new Map();
  @State selectedId: number = 0;
  /** 当前详情对象（页面 @State 显式赋值驱动刷新；@Builder 内方法派生在当前构建不触发重绘） */
  @State current: WikiAvatarMeta | undefined = undefined;
  @State keyword: string = '';
  @State gridMode: boolean = false;
  @State showFilters: boolean = false;
  @State filterTokens: WikiAvatarToken[] = [];
  @State suggestionCount: number = 0;
  @State contentLocale: string = '';
  private filterCatalog: WikiAvatarToken[] = [];
  private suggestionSource: SimpleDataSource<WikiAvatarToken> = new SimpleDataSource<WikiAvatarToken>([]);
  @State visibleCount: number = 0;
  @State appliedLocaleVersion: number = 0;
  @State showDetail: boolean = false;
  @State isWide: boolean = false;
  private detailScroller: Scroller = new Scroller();
  @State baseExpanded: boolean = true;
  @State skillItems: AvatarWikiSkill[] = [];
  @State skillStripWidth: number = 0;
  @State selectedSkillId: number = 0;
  @State selectedSkillLevel: number = 0;
  @State skillsLoading: boolean = false;
  @State parametersExpanded: boolean = true;
  private skillSequence: number = 0;
  /** 角色列表懒加载数据源（140+ 项全量渲染开销大，LazyForEach 只画可视区） */
  private listSource: SimpleDataSource<WikiAvatarMeta> = new SimpleDataSource([]);
  /** 立绘 Swiper 独立数据源（与列表同数据；LazyForEach+cachedCount(1) 按需创建立绘页，避免全量下载） */
  private splashSource: SimpleDataSource<WikiAvatarMeta> = new SimpleDataSource([]);
  /** 基础属性滑条状态（对齐 Windows BaseValueSlider） */
  @State curLevel: number = 1;
  @State curPromoted: boolean = false;
  @State curHp: number = 0;
  @State curAtk: number = 0;
  @State curDef: number = 0;
  @State curBonusText: string = '';
  /** 名片名称/描述（NameCard.json 懒加载，跟随 current 异步刷新） */
  @State ncName: string = '';
  @State ncDesc: string = '';
  /** 当前角色在列表中的位置（立绘 Swiper 翻页联动） */
  @State curIdx: number = 0;
  /** 当前角色的服装选择（0=默认款；对齐 Windows CostumesView 翻页，切换角色时复位） */
  @State costumeIdx: number = 0;
  /** 基础属性计算请求序号（拖动滑条连发时丢弃过期异步结果） */
  private calcSeq: number = 0;
  /** 该角色无基础属性元数据（旅行者等，官方数据不含其成长曲线） */
  @State baseDataMissing: boolean = false;
  /** 养成计划加入动作（复用 CharacterViewModel.addAvatarToPlan，对齐 Windows WikiAvatarPage CultivateCommand） */
  @State draftVm: CultivationDraftViewModel = new CultivationDraftViewModel();
  /** 养成计划选择半窗（多项目时让用户选，逻辑与 CharacterPage 同款） */
  @State showPlanSheet: boolean = false;
  /** 待选养成计划列表（bindSheet 数据源） */
  @State pendingProjects: CultivateProject[] = [];
  /** 待加入计划的图鉴角色快照（选项目期间固定） */
  @State pendingDetail: CharacterDetail | undefined = undefined;
  /** 加入计划进行中（防重复点击） */
  @State addingPlan: boolean = false;

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1500 });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
    this.calcSeq++;
    this.skillSequence++;
    this.draftVm.cancel();
  }

  aboutToAppear(): void {
    this.active = true;
    this.readRouteItem();
    this.gridMode = PreferencesStore.getBool('wiki.avatar.grid', false);
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
          && params.itemId >= 10000000 && params.itemId <= 99999999) { this.routeItemId = params.itemId; }
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
    this.calcSeq++;
    if (!restoreSelection) {
      this.loading = true;
      this.routeMessage = '';
    }
    try {
      const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
      if (!this.ownsLoad(sequence)) { return; }
      const materials: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
      if (!this.ownsLoad(sequence)) { return; }
      // Windows Wiki uses the real Avatar array; WithPlayers belongs to identity/icon lookup contexts.
      this.avatars = avatars.filter((avatar: WikiAvatarMeta): boolean => avatar.id !== 10000005 && avatar.id !== 10000007)
        .sort((left: WikiAvatarMeta, right: WikiAvatarMeta): number =>
          right.begin.localeCompare(left.begin) || right.sort - left.sort);
      this.contentLocale = AppLocaleService.current();
      this.filterCatalog = WikiAvatarFilter.catalog(this.avatars, this.contentLocale);
      this.filterTokens = WikiAvatarFilter.relabel(this.filterCatalog, this.filterTokens);
      this.refreshSuggestions();
      this.materials = materials;
      const filtered: WikiAvatarMeta[] = this.filtered();
      const previousId: number = this.selectedId;
      if (restoreSelection) {
        this.current = this.avatars.find((item: WikiAvatarMeta): boolean => item.id === previousId);
        this.showDetail = this.showDetail && this.current !== undefined;
      } else {
        // A requested unknown/invalid ID must not silently display the first unrelated item.
        this.current = requested
          ? this.avatars.find((item: WikiAvatarMeta): boolean => item.id === itemId)
          : (this.isWide ? filtered[0] : undefined);
        this.showDetail = requested && this.current !== undefined;
        this.routeMessage = requested && this.current === undefined ? '本地暂无该角色资料，请从列表选择或更新游戏数据' : '';
      }
      this.selectedId = this.current?.id ?? 0;
      this.visibleCount = filtered.length;
      this.appliedLocaleVersion = this.localeVersion;
      this.listSource.notifyDataReload(filtered);
      const selected: WikiAvatarMeta | undefined = this.current;
      // A search term can be language-specific; keep its selected artwork visible after a locale switch.
      this.splashSource.notifyDataReload(selected !== undefined && !filtered.some((item: WikiAvatarMeta): boolean =>
        item.id === selected.id) ? [selected] : filtered);
      this.syncCurIdx();
      if (selected !== undefined) {
        if (restoreSelection && selected.id === previousId) {
          this.calcAvatarBase();
          this.loadNameCardInfo();
          this.loadSkills(true);
        } else {
          this.onAvatarSelected();
        }
      }
    } catch (_) {
      if (!this.ownsLoad(sequence)) { return; }
      if (restoreSelection) { return; }
      this.avatars = [];
      this.current = undefined;
      this.selectedId = 0;
      this.showDetail = false;
      this.visibleCount = 0;
      this.routeMessage = '无法读取本地角色资料，请重新进入后重试';
      this.listSource.notifyDataReload([]);
      this.splashSource.notifyDataReload([]);
    } finally {
      if (this.ownsLoad(sequence)) { this.loading = false; }
    }
  }

  /** 点击列表行：显式赋值页面 @State（弃方法派生，确保详情刷新） */
  select(a: WikiAvatarMeta): void {
    if (!this.active) { return; }
    this.showFilters = false;
    this.routeMessage = '';
    this.showDetail = true;
    this.setCurrent(a);
    this.syncCurIdx();
  }

  private setCurrent(avatar: WikiAvatarMeta | undefined): void {
    if (this.current?.id === avatar?.id) { return; }
    if (this.current !== undefined && avatar !== undefined) {
      this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
    this.current = avatar;
    this.selectedId = avatar?.id ?? 0;
    if (avatar === undefined) { this.showDetail = false; }
    else { this.onAvatarSelected(); }
  }

  /** 同步当前角色在列表中的下标（立绘 Swiper 用） */
  private syncCurIdx(): void {
    // 循环内只读局部快照，状态只写一次（lint: 避免循环里反复读写状态变量）
    const avatars: WikiAvatarMeta[] = this.splashSource.getItems();
    const selectedId: number = this.selectedId;
    let found: number = -1;
    for (let i = 0; i < avatars.length; i++) {
      if (avatars[i].id === selectedId) {
        found = i;
        break;
      }
    }
    this.curIdx = found >= 0 ? found : 0;
  }

  /** 重置滑条并重算基础属性（切换角色时） */
  onAvatarSelected(): void {
    this.curLevel = this.avatarMaxLevel();
    this.curPromoted = false;
    this.costumeIdx = 0;
    this.calcAvatarBase();
    this.loadNameCardInfo();
    this.loadSkills();
  }

  private async loadSkills(preserveSelection: boolean = false): Promise<void> {
    const avatarId: number = this.current?.id ?? 0;
    const sequence: number = ++this.skillSequence;
    const previousId: number = preserveSelection ? this.selectedSkillId : 0;
    const previousLevel: number = this.selectedSkillLevel;
    this.skillItems = [];
    this.selectedSkillId = 0;
    this.selectedSkillLevel = 0;
    this.skillsLoading = avatarId > 0;
    if (avatarId === 0) { return; }
    try {
      const skills: AvatarWikiSkill[] = await AvatarSkillParameterService.forAvatar(avatarId);
      if (!this.active || sequence !== this.skillSequence || this.current?.id !== avatarId) { return; }
      this.skillItems = skills;
      const selected: AvatarWikiSkill | undefined = skills.find((skill: AvatarWikiSkill): boolean => skill.id === previousId) ?? skills[0];
      this.selectedSkillId = selected?.id ?? 0;
      this.selectedSkillLevel = selected !== undefined && selected.id === previousId && selected.levels.includes(previousLevel)
        ? previousLevel : selected?.defaultLevel ?? 0;
    } catch (_) {
      // A missing parameter table leaves the rest of this character's verified metadata usable.
    } finally {
      if (this.active && sequence === this.skillSequence) { this.skillsLoading = false; }
    }
  }

  private selectSkill(id: number): void {
    const skill: AvatarWikiSkill | undefined = this.skillItems.find((item: AvatarWikiSkill): boolean => item.id === id);
    if (skill === undefined || this.selectedSkillId === id) { return; }
    this.selectedSkillId = id;
    this.selectedSkillLevel = skill.defaultLevel;
  }

  private selectedSkill(): AvatarWikiSkill | undefined {
    return this.skillItems.find((skill: AvatarWikiSkill): boolean => skill.id === this.selectedSkillId);
  }

  private skillLevelOptions(): SelectOption[] {
    return (this.selectedSkill()?.levels ?? []).map((level: number): SelectOption => {
      const option: SelectOption = { value: 'Lv. ' + level };
      return option;
    });
  }

  private skillLevelIndex(): number {
    return this.selectedSkill()?.levels.indexOf(this.selectedSkillLevel) ?? -1;
  }

  private selectSkillLevel(index: number): void {
    const level: number | undefined = this.selectedSkill()?.levels[index];
    if (level !== undefined) { this.selectedSkillLevel = level; }
  }

  private skillParameterRows(): AvatarSkillParameterRow[] {
    const skill: AvatarWikiSkill | undefined = this.selectedSkill();
    return skill === undefined ? [] : AvatarSkillParameterService.rows(skill, this.selectedSkillLevel);
  }

  private skillTabWidth(): number {
    const count: number = Math.max(1, this.skillItems.length);
    const available: number = this.skillStripWidth - 4 * (count - 1);
    return Math.max(64, Math.floor(available / count));
  }

  /** 名片描述懒加载（NameCard.json 按大图名匹配；与 current 异步对齐，避免切换串台） */
  async loadNameCardInfo(): Promise<void> {
    if (!this.active) { return; }
    const sequence: number = this.loadSequence;
    const avatar: WikiAvatarMeta | undefined = this.current;
    this.ncName = '';
    this.ncDesc = '';
    if (avatar === undefined || avatar.nameCardPic.length === 0) {
      return;
    }
    const info = await WikiMetaService.getNameCardByPic(avatar.nameCardPic);
    // 异步返回时用户可能已切到其他角色，仅在接受者仍是当前角色时应用
    if (this.ownsLoad(sequence) && info !== undefined && this.current?.id === avatar.id) {
      this.ncName = info.name;
      this.ncDesc = info.description;
    }
  }

  /** 图鉴元素中文 → API 英文元素名（addAvatarToPlan → elementAttrIdOf 需要 Pyro/Hydro/… 口径） */
  private static elementEn(vision: string): string {
    switch (vision) {
      case '火': return 'Pyro';
      case '水': return 'Hydro';
      case '雷': return 'Electro';
      case '草': return 'Dendro';
      case '冰': return 'Cryo';
      case '风': return 'Anemo';
      case '岩': return 'Geo';
      default: return vision;
    }
  }

  /** 由图鉴元数据构造最小可用 CharacterDetail（addAvatarToPlan 只消费 id/name/element/level/icon 等基础字段）：
   *  图鉴为离线数据，无等级/命座 → 当前等级取 1（目标固定 90）、命座 0、突破 0 */
  private buildWikiDetail(a: WikiAvatarMeta): CharacterDetail {
    const d: CharacterDetail = new CharacterDetail();
    d.id = a.id;
    d.name = a.name;
    d.element = WikiAvatarPage.elementEn(a.vision);
    d.level = 1;
    d.rarity = a.quality;
    d.icon = a.icon;
    d.promoteLevel = 0;
    return d;
  }

  private confirmAddPlan(): void { this.addCurrentToPlan(); }

  private async addCurrentToPlan(): Promise<void> {
    if (this.current === undefined || this.draftVm.busy) { return; }
    this.showPlanSheet = true;
    await this.draftVm.offline('avatar', this.current.id);
  }

  private filtered(): WikiAvatarMeta[] {
    return WikiAvatarFilter.filter(this.avatars, this.filterTokens);
  }

  private applyFilter(): void {
    const filtered: WikiAvatarMeta[] = this.filtered();
    this.visibleCount = filtered.length;
    this.listSource.notifyDataReload(filtered);
    this.splashSource.notifyDataReload(filtered);
    if (!filtered.some((avatar: WikiAvatarMeta): boolean => avatar.id === this.selectedId)) {
      this.setCurrent(filtered[0]);
    }
    this.syncCurIdx();
  }

  private updateWidth(width: number): void {
    const wide: boolean = width >= 840;
    if (wide === this.isWide) { return; }
    this.isWide = wide;
    if (wide && !this.loading && this.current === undefined && !this.routeRequested) { this.applyFilter(); }
  }

  onBackPress(): boolean {
    if (this.showFilters) { this.showFilters = false; return true; }
    if (this.isWide || !this.showDetail) { return false; }
    this.showDetail = false;
    return true;
  }

  private back(): void {
    if (!this.onBackPress()) { router.back(); }
  }

  private refreshSuggestions(): void {
    if (!this.showFilters) { return; }
    const choices: WikiAvatarToken[] = WikiAvatarFilter.suggestions(this.filterCatalog, this.filterTokens, this.keyword);
    this.suggestionCount = choices.length;
    this.suggestionSource.notifyDataReload(choices);
  }

  private showSuggestions(): void {
    this.showFilters = !this.loading && this.filterTokens.length < WikiAvatarFilter.LIMIT;
    this.refreshSuggestions();
  }

  private editFilterText(value: string): void {
    this.keyword = value;
    // Keep a full localized name (e.g. Hu Tao) available as a single suggestion.
    const query: string = value.trim().toLocaleLowerCase();
    if (query.includes(' ') && !this.filterCatalog.some((option: WikiAvatarToken): boolean =>
      option.label.toLocaleLowerCase().startsWith(query) || option.alias.toLocaleLowerCase().startsWith(query))) {
      const words: string[] = value.trim().split(/ +/);
      this.keyword = words.pop() ?? '';
      let selected: WikiAvatarToken[] = this.filterTokens;
      for (const word of words) {
        const token: WikiAvatarToken | undefined = WikiAvatarFilter.fromText(this.filterCatalog, word);
        if (token !== undefined) { selected = WikiAvatarFilter.add(selected, token); }
      }
      this.filterTokens = selected;
      if (selected.length === WikiAvatarFilter.LIMIT) { this.keyword = ''; }
      this.applyFilter();
    }
    this.showSuggestions();
  }

  private addFilter(token: WikiAvatarToken): void {
    if (this.filterTokens.length >= WikiAvatarFilter.LIMIT) { return; }
    this.filterTokens = WikiAvatarFilter.add(this.filterTokens, token);
    this.keyword = '';
    this.showFilters = false;
    this.applyFilter();
  }

  private commitFilterText(): void {
    const token: WikiAvatarToken | undefined = WikiAvatarFilter.fromText(this.filterCatalog, this.keyword);
    if (token !== undefined) { this.addFilter(token); }
  }

  private removeFilter(token: WikiAvatarToken): void {
    const key: string = token.key();
    this.filterTokens = this.filterTokens.filter((item: WikiAvatarToken): boolean => item.key() !== key);
    this.applyFilter();
    this.refreshSuggestions();
  }

  private clearFilters(): void {
    this.keyword = '';
    this.filterTokens = [];
    this.showFilters = false;
    this.applyFilter();
  }

  private async openStrategy(target: string): Promise<void> {
    const avatar: WikiAvatarMeta | undefined = this.current;
    if (!this.active || avatar === undefined) { return; }
    const url: string = WikiAvatarGuide.url(target, avatar.id, avatar.canonicalName || avatar.name, this.contentLocale);
    if (url.length === 0) {
      this.toast(WikiAvatarGuide.unavailable(this.contentLocale));
      return;
    }
    try {
      const host: common.UIAbilityContext | undefined = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (host !== undefined) { await host.openLink(url); }
    } catch (error) {
      if (this.active && this.current?.id === avatar.id) {
        this.toast(`打开失败：${(error as Error).message}`);
      }
    }
  }

  @Builder
  planPickerSheet() {
    CultivationDraftEditor({ vm: this.draftVm,
      onClose: (): void => { this.showPlanSheet = false; this.draftVm.cancel(); } })
  }

  /** 依据当前角色+等级+突破重算 生命/攻击/防御/突破属性 */
  calcAvatarBase(): void {
    if (!this.active) { return; }
    const seq: number = ++this.calcSeq;
    const cur: WikiAvatarMeta | undefined = this.current;
    if (cur === undefined || cur.growCurves.length === 0) {
      this.baseDataMissing = true;
      Logger.warn(AVATAR_PAGE_TAG, `calc skip: cur=${cur?.name ?? 'undefined'} growCurves=${cur?.growCurves.length ?? -1}`);
      this.curHp = 0;
      this.curAtk = 0;
      this.curDef = 0;
      this.curBonusText = '';
      return;
    }
    this.baseDataMissing = false;
    const maxLv: number = BaseValueService.avatarMaxLevel(cur.quality);
    if (this.curLevel > maxLv) {
      this.curLevel = maxLv;
    }
    const info: AvatarGrowInfo = new AvatarGrowInfo();
    info.hpBase = cur.hpBase;
    info.attackBase = cur.attackBase;
    info.defenseBase = cur.defenseBase;
    info.promoteId = cur.promoteId;
    info.growCurves = cur.growCurves;
    const reqLevel: number = this.curLevel;
    const reqPromoted: boolean = this.curPromoted;
    BaseValueService.avatarBaseValues(info, reqLevel, reqPromoted).then((v: AvatarBaseValues) => {
      // 异步返回时角色/等级/突破任一变化即为过期结果，丢弃（防拖动滑条连发时旧值覆盖新值）
      if (!this.active || seq !== this.calcSeq || this.curLevel !== reqLevel || this.curPromoted !== reqPromoted) {
        return;
      }
      if (this.current !== undefined && this.current.id === cur.id) {
        Logger.info(AVATAR_PAGE_TAG, `calc applied lv=${reqLevel} pro=${reqPromoted} hp=${v.hp} atk=${v.atk} def=${v.def}`);
        this.baseDataMissing = false;
        this.curHp = v.hp;
        this.curAtk = v.atk;
        this.curDef = v.def;
        this.curBonusText = v.bonusType > 0
          ? `${BaseValueService.fightPropName(v.bonusType)} ${BaseValueService.fightPropText(v.bonusType, v.bonusValue)}`
          : '';
      }
    }).catch(() => {
    });
  }

  /** 当前角色最大等级 */
  avatarMaxLevel(): number {
    return BaseValueService.avatarMaxLevel(this.current?.quality ?? 0);
  }

  static qualityColor(q: number): Resource {
    return q >= 5 ? $r('app.color.five_star') : $r('app.color.four_star');
  }

  static kindLabel(k: string): string {
    switch (k) {
      case 'A': return '普攻';
      case 'E': return '战技';
      case 'Q': return '爆发';
      case 'P': return '被动';
      default: return '技能';
    }
  }

  matName(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.n : `${id}`;
  }

  matIcon(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.i : '';
  }

  cvOf(a: WikiAvatarMeta, idx: number): string {
    return a.cv.length > idx ? a.cv[idx] : '—';
  }

  build() {
    Stack() {
      // 壁纸衬底：router 独立页透出壁纸，embed 内嵌时由壳层统一铺（组件内渲染为空）
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
      this.header()
      if (this.routeMessage.length > 0) {
        Text(this.routeMessage).fontSize(12).fontColor($r('app.color.text_secondary'))
          .width('100%').padding({ left: 16, right: 16, bottom: 8 })
      }
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
          Text($r('app.string.ui_common_loading'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Row({ space: 10 }) {
          this.listPanel()
          this.detailPanel()
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_old: Area, area: Area) => this.updateWidth(Number(area.width)))
    // 养成计划选择半窗（多项目时让用户选目标计划；$$ 双向同步下滑关闭）
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
    .width('100%')
    .height('100%')
  }

  @Builder
  header() {
    Column() {
      PageToolbar({ embedMode: true,
        leading: (): void => { this.toolbarLeading(); }, trailing: (): void => { this.toolbarTrailing(); } })
      if ((this.isWide || !this.showDetail) && this.filterTokens.length > 0) { this.selectedFilters() }
      if ((this.isWide || !this.showDetail) && this.showFilters) { this.filterSuggestions() }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 8, bottom: 10 })
  }

  @Builder
  toolbarLeading() {
    if (!this.embedMode || (!this.isWide && this.showDetail)) {
      AppBackButton({ accessibilityLabel: !this.isWide && this.showDetail ? '返回角色列表' : '返回',
        onBack: () => this.back() })
    }
    if (!this.isWide && this.showDetail) {
      Text(this.current?.name ?? '角色资料').fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    } else {
      Row({ space: 2 }) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18)
            .fontColor([!this.gridMode ? $r('app.color.app_primary_text') : $r('app.color.text_secondary')])
        }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .width(40).height(40).padding(0).accessibilityText($r('app.string.ui_list_view'))
          .backgroundColor(!this.gridMode ? $r('app.color.app_primary_bg') : Color.Transparent)
          .onClick(() => { this.gridMode = false; PreferencesStore.setBool('wiki.avatar.grid', false); })
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.grid')).fontSize(18)
            .fontColor([this.gridMode ? $r('app.color.app_primary_text') : $r('app.color.text_secondary')])
        }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .width(40).height(40).padding(0).accessibilityText($r('app.string.ui_grid_view'))
          .backgroundColor(this.gridMode ? $r('app.color.app_primary_bg') : Color.Transparent)
          .onClick(() => { this.gridMode = true; PreferencesStore.setBool('wiki.avatar.grid', true); })
      }
      Row({ space: 2 }) {
        TextInput({ text: this.keyword, placeholder: $r('app.string.ui_wi_ki_avatar_auto_suggest_box_place_holder') })
          .fontSize(13).height(40).layoutWeight(1).enterKeyType(EnterKeyType.Search)
          .enabled(!this.loading && this.filterTokens.length < WikiAvatarFilter.LIMIT)
          .onFocus((): void => { this.showSuggestions(); })
          .onChange((text: string): void => { this.editFilterText(text); })
          .onSubmit((): void => { this.commitFilterText(); })
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            Text(`${this.filterTokens.length}/${WikiAvatarFilter.LIMIT}`).fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(14).fontColor([$r('app.color.text_secondary')])
          }
        }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).height(44)
          .padding({ left: 5, right: 5 }).accessibilityText($r('app.string.ui_filter_count', this.filterTokens.length))
          .enabled(!this.loading && this.filterTokens.length < WikiAvatarFilter.LIMIT)
          .onClick((): void => {
            if (this.keyword.trim().length > 0) { this.commitFilterText(); }
            else if (this.showFilters) { this.showFilters = false; }
            else { this.showSuggestions(); }
          })
      }.layoutWeight(1).constraintSize({ maxWidth: 600 })
    }
  }

  @Builder
  toolbarTrailing() {
    Button(this.isWide ? (this.addingPlan ? '加入中...' : '加入养成计划') : '＋', { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
      .height(40).fontSize(this.isWide ? 13 : 20).width(this.isWide ? 144 : 40)
      .accessibilityText('加入养成计划').enabled(this.current !== undefined && !this.addingPlan)
      .onClick(() => { this.confirmAddPlan(); })
  }

  @Builder
  selectedFilters() {
    Row({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.filterTokens, (token: WikiAvatarToken) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                Text(token.label).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor($r('app.color.text_primary')).flexShrink(1)
                Text('×').fontSize(14).fontColor($r('app.color.text_secondary')).accessibilityLevel('no')
              }
            }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).constraintSize({ maxWidth: 220 }).accessibilityText(token.label)
              .accessibilityDescription($r('app.string.ui_action_clear')).onClick((): void => { this.removeFilter(token); })
          }, (token: WikiAvatarToken): string => `${token.key()}_${this.appliedLocaleVersion}`)
        }
      }.layoutWeight(1).height(44).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
      Button($r('app.string.ui_clear_filters'), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44).fontSize(12).onClick((): void => { this.clearFilters(); })
    }.width('100%').margin({ top: 4 })
  }

  @Builder
  filterSuggestions() {
    Column() {
      if (this.suggestionCount > 0) {
        List() {
          LazyForEach(this.suggestionSource, (token: WikiAvatarToken) => {
            ListItem() {
              Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                Row({ space: 8 }) {
                  if (token.kind === WikiAvatarTokenKind.Avatar) {
                    MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.avatarOf(Number(token.value))?.sideIcon ?? '', iconSize: 30 })
                  }
                  Text(token.label).fontSize(13).fontColor($r('app.color.text_primary'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }.width('100%')
              }.width('100%').height(44).padding({ left: 10, right: 10 })
                .hoverEffect(HoverEffect.Highlight).accessibilityText(token.label)
                .onClick((): void => { this.addFilter(token); })
            }
          }, (token: WikiAvatarToken): string => `${token.key()}_${this.appliedLocaleVersion}`)
        }.width('100%').height(Math.min(4, this.suggestionCount) * 44).scrollBar(BarState.Auto)
      } else {
        Text($r('app.string.common_empty')).fontSize(12).fontColor($r('app.color.text_secondary')).padding(12)
      }
    }.width('100%').constraintSize({ maxWidth: 600 }).alignItems(HorizontalAlign.Start)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8).margin({ top: 4 })
  }

  /** 左侧列表（搜索 + 品质筛选 + 角色行） */
  @Builder
  listPanel() {
    Column({ space: 8 }) {
      if (this.visibleCount === 0) {
        Text('没有匹配的角色').fontSize(13).fontColor($r('app.color.text_secondary')).padding(12)
      } else if (this.gridMode) {
        Grid() {
          LazyForEach(this.listSource, (a: WikiAvatarMeta) => {
            GridItem() {
              Column({ space: 6 }) {
                MetaIcon({ category: 'AvatarIcon', name: a.icon, iconSize: 56 })
                Text(a.name).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor($r('app.color.text_primary'))
              }.width('100%').height(98).padding(8).borderRadius(10)
                .backgroundColor(this.selectedId === a.id ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
                .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => { this.select(a); })
            }
          }, (a: WikiAvatarMeta) => `grid_${a.id}_${this.appliedLocaleVersion}`)
        }.columnsTemplate(this.isWide ? '1fr 1fr' : '1fr 1fr 1fr')
          .columnsGap(8).rowsGap(8).cachedCount(4).width('100%').layoutWeight(1)
      } else {
      List({ space: 4 }) {
        LazyForEach(this.listSource, (a: WikiAvatarMeta) => {
          ListItem() {
            Row({ space: 10 }) {
              MetaIcon({ category: 'AvatarIcon', name: a.sideIcon || a.icon, iconSize: 36 })
              Text(a.name).fontSize(14).fontWeight(this.selectedId === a.id ? FontWeight.Medium : FontWeight.Normal)
                .fontColor($r('app.color.text_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%').constraintSize({ minHeight: 56 }).padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.selectedId === a.id ? $r('app.color.app_primary_bg') : Color.Transparent)
            .focusable(true).hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.select(a);
            })
          }
        }, (a: WikiAvatarMeta) => `a_${a.id}_${this.appliedLocaleVersion}`)
      }
      .cachedCount(5)
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      }
    }
    .width(this.isWide ? 216 : '100%')
    .height('100%')
    .padding(6)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .borderRadius(8)
    .visibility(this.isWide || !this.showDetail ? Visibility.Visible : Visibility.None)
  }

  /** 资料中的材料行，保留固定 ID 与语言版本作为渲染键。 */
  @Builder
  materialItem(id: number) {
    Row({ space: 8 }) {
      MetaIcon({ category: 'ItemIcon', name: this.matIcon(id), iconSize: 34 })
      Text(this.matName(id)).fontSize(12).fontColor($r('app.color.text_primary'))
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }
    .width('100%').constraintSize({ minHeight: 44 }).padding({ left: 4, right: 8, top: 4, bottom: 4 })
    .borderRadius(6).backgroundColor($r('app.color.card_inner_tint'))
  }

  /** 右侧详情（无参：直接读 @State current；传参 @Builder 为值快照，切换角色不刷新） */
  @Builder
  detailPanel() {
    if (this.current !== undefined) {
      Scroll(this.detailScroller) {
        Column({ space: 12 }) {
          this.profileCard()
          this.strategyBlock()
          this.baseValueCard()
          this.skillsCard()
          this.talentsCard()
          if (this.current!.cook !== null) {
            this.cookCard()
          }
          this.splashCard()
          this.textsCard('语音', 'fetters')
          this.textsCard('故事', 'stories')
          this.nameCardBlock()
          Text('数据来源：Snap.Metadata（本地打包）')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 8 })
        }
        .width('100%')
        .padding({ bottom: 4 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .visibility(this.isWide || this.showDetail ? Visibility.Visible : Visibility.None)
    }
  }

  /** 当前选中皮肤 FrontIcon（默认款或无图标返回空串 → 显示默认立绘 Swiper） */
  private costumeFrontIconOf(): string {
    const c: AvatarCostumeMeta | undefined = this.current?.costumes[this.costumeIdx];
    return c !== undefined && !c.isDefault ? c.frontIcon : '';
  }

  /** 当前选中服装描述（详情立绘卡脚注） */
  private costumeDescOf(): string {
    const c: AvatarCostumeMeta | undefined = this.current?.costumes[this.costumeIdx];
    return c !== undefined ? c.description : '';
  }

  private costumeChipLabel(c: AvatarCostumeMeta): string {
    return c.isDefault ? '默认' : c.name;
  }

  /** 立绘卡（FlipView 式翻页：Swiper 左右滑动切换相邻角色立绘，仅渲染当前±1 页控制内存） */
  @Builder
  splashCard() {
    if (this.current !== undefined) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text('立绘')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('左右滑动查看其他角色')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(`${this.curIdx + 1}/${Math.max(1, this.splashSource.totalCount())}`)
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        // 服装切换（对齐 Windows CostumesView：默认款居首，皮肤按期次排列）
        if (this.current.costumes.length > 1) {
          Row({ space: 6 }) {
            ForEach(this.current.costumes, (c: AvatarCostumeMeta, idx: number) => {
              Text(this.costumeChipLabel(c))
                .fontSize(11)
                .fontColor(this.costumeIdx === idx ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .borderRadius(10)
                .backgroundColor(this.costumeIdx === idx ? $r('app.color.app_primary_bg') : Color.Transparent)
                .hoverEffect(HoverEffect.Highlight)
                .accessibilityText(`切换到${this.costumeChipLabel(c)}`)
                .onClick(() => { this.costumeIdx = idx; })
            }, (c: AvatarCostumeMeta) => `${this.current?.id ?? 0}_${c.id}_${this.appliedLocaleVersion}`)
          }.width('100%')
        }

        if (this.costumeFrontIconOf().length > 0) {
          // 皮肤立绘（Costume 类目，与默认立绘同容器比例）
          Column() {
            SplashArtView({ icon: this.current!.icon, costumeFrontIcon: this.costumeFrontIconOf() })
          }
          .width('100%')
          .aspectRatio(2)
          .constraintSize({ minHeight: 170, maxHeight: 460 })
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          Text(this.costumeDescOf())
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else {
          Swiper() {
            LazyForEach(this.splashSource, (a: WikiAvatarMeta) => {
              Column() {
                SplashArtView({ icon: a.icon })
              }
              .width('100%')
              .height('100%')
            }, (a: WikiAvatarMeta) => `sp_${a.id}`)
          }
          .index(this.curIdx)
          .loop(false)
          .indicator(false)
          .duration(this.reduceMotion ? 0 : 240)
          .curve(this.reduceMotion ? Curve.Linear : Curve.Ease)
          .effectMode(this.reduceMotion ? EdgeEffect.None : EdgeEffect.Spring)
          .cachedCount(1)
          .onChange((idx: number) => {
            const target: WikiAvatarMeta | undefined = this.splashSource.getData(idx);
            if (target !== undefined && target.id !== this.selectedId) {
              this.select(target);
            }
          })
          .width('100%')
          // 2:1 比例（对齐 Windows ConstrainedBox AspectRatio 2048:1024）：完整立绘铺满不裁切
          .aspectRatio(2)
          .constraintSize({ minHeight: 170, maxHeight: 460 })
          .borderRadius($r('app.float.card_radius'))
          .clip(true)
        }
      }
      .width('100%')
      .padding(14)
      .borderRadius($r('app.float.card_radius'))
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    }
  }

  /** 等级和突破计算保持原逻辑，仅折叠数值行。 */
  @Builder
  baseValueCard() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text('等级').fontSize(13).fontColor($r('app.color.text_primary'))
        Text('Lv. ' + this.curLevel).fontSize(13).fontColor($r('app.color.text_primary')).width(58)
        if (this.isWide) {
          Text('突破后').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        Toggle({ type: ToggleType.Switch, isOn: this.curPromoted })
          .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .accessibilityText('突破后')
          .onChange((isOn: boolean) => { this.curPromoted = isOn; this.calcAvatarBase(); })
        Slider({ value: this.curLevel, min: 1, max: this.avatarMaxLevel(), step: 1, style: SliderStyle.OutSet })
          .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .layoutWeight(1).blockColor($r('app.color.app_primary')).selectedColor($r('app.color.app_primary'))
          .onChange((level: number) => { this.curLevel = Math.round(level); this.calcAvatarBase(); })
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph(this.baseExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14).fontColor([$r('app.color.text_secondary')])
        }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .width(40).height(40).padding(0).accessibilityText(this.baseExpanded ? '收起基础属性' : '展开基础属性')
          .onClick(() => { this.baseExpanded = !this.baseExpanded; })
      }.width('100%').padding({ left: 12, right: 8, top: 4, bottom: 4 })
      if (this.baseExpanded) {
        this.propCell('生命值')
        this.propCell('攻击力')
        this.propCell('防御力')
        if (this.curBonusText.length > 0) {
          Text(this.curBonusText).fontSize(12).fontColor($r('app.color.app_primary_text'))
            .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
        if (this.baseDataMissing) {
          Text('该角色的基础属性与元素相关，当前资料未提供对应数值。')
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding(12)
        }
      }
    }.width('100%').attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
  }

  @Builder
  propCell(label: string) {
    Row() {
      Text('基础' + label).fontSize(13).fontColor($r('app.color.text_primary'))
      Blank()
      Text(this.baseDataMissing ? '—' : String(this.propValueOf(label)))
        .fontSize(13).fontColor($r('app.color.text_primary'))
    }.width('100%').padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .border({ width: { top: 1 }, color: $r('app.color.divider') })
  }

  private propValueOf(label: string): number {
    if (label === '生命值') { return this.curHp; }
    if (label === '攻击力') { return this.curAtk; }
    return this.curDef;
  }


  private profileLabel(slot: number): string {
    const labels: string[] = ['生日', '所属', '神之眼', '命之座', '汉语 CV', '日语 CV', '英语 CV', '韩语 CV'];
    return labels[slot] ?? '';
  }

  private profileValue(slot: number): string {
    const avatar: WikiAvatarMeta | undefined = this.current;
    if (avatar === undefined) { return '—'; }
    if (slot === 0) { return avatar.birthText || avatar.birth || '—'; }
    if (slot === 1) { return avatar.native || '—'; }
    if (slot === 2) { return avatar.visionName || WikiMetaService.elementName(avatar.vision) || '—'; }
    if (slot === 3) { return avatar.constellation || '—'; }
    return this.cvOf(avatar, slot - 4) || '—';
  }

  @Builder
  profileFields() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7], (slot: number) => {
        Column({ space: 4 }) {
          Text(this.profileLabel(slot)).fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Text(this.profileValue(slot)).fontSize(12).fontColor($r('app.color.text_primary'))
        }.alignItems(HorizontalAlign.Start).width(this.isWide ? '25%' : '50%')
          .padding({ right: 10, top: 8, bottom: 4 })
      }, (slot: number) => 'profile_' + this.selectedId + '_' + slot + '_' + this.appliedLocaleVersion)
    }.width('100%')
  }

  @Builder
  profileCard() {
    if (this.current !== undefined) {
      Column({ space: 12 }) {
        Row({ space: 16 }) {
          Column({ space: 8 }) {
            Text(WikiMetaService.weaponTypeName(this.current.weapon)).fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            MetaIcon({ category: 'AvatarIcon', name: this.current.icon, iconSize: this.isWide ? 104 : 80 })
            Text(WikiMetaService.qualityName(this.current.quality)).fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }.width(this.isWide ? 112 : 88)
          Column({ space: 6 }) {
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Text(this.current.name).fontSize(21).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary')).margin({ right: 12 })
              if (this.current.title.length > 0) {
                Text(this.current.title).fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
              }
            }.width('100%')
            if (this.current.detail.length > 0) {
              Text(this.current.detail).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            }
            if (this.isWide) { this.profileFields() }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Top)
        if (!this.isWide) { this.profileFields() }
        if (this.current.cultivationItems.length > 0) {
          GridRow({ columns: this.isWide ? 3 : 2, gutter: { x: 8, y: 8 } }) {
            ForEach(this.current.cultivationItems, (id: number) => {
              GridCol() { this.materialItem(id) }
            }, (id: number) => 'material_' + id + '_' + this.appliedLocaleVersion)
          }.width('100%')
        }
      }.width('100%').padding(14)
        .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
    }
  }


  /** 技能顺序、等级和倍率均使用同源参数服务。 */
  @Builder
  skillsCard() {
    if (this.skillsLoading) {
      Row({ space: 10 }) {
        LoadingProgress().width(24).height(24).color($r('app.color.app_primary'))
        Text($r('app.string.ui_common_loading')).fontSize(12).fontColor($r('app.color.text_secondary'))
      }.width('100%').padding(14)
    } else if (this.skillItems.length > 0) {
      Column({ space: 12 }) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.skillItems, (skill: AvatarWikiSkill) => {
              Button({ type: ButtonType.Normal }) {
                Column({ space: 6 }) {
                  MetaIcon({ category: skill.icon.startsWith('UI_Talent_') ? 'Talent' : 'Skill', name: skill.icon, iconSize: 30 })
                  Text(skill.name).fontSize(11).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontColor(this.selectedSkillId === skill.id ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
                    .textAlign(TextAlign.Center)
                }.width('100%').constraintSize({ minHeight: 68 }).padding(6)
              }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
                .width(this.skillTabWidth()).padding({ left: 4, right: 4 })
                .backgroundColor(this.selectedSkillId === skill.id ? $r('app.color.app_primary_bg') : Color.Transparent)
                .accessibilityText(skill.name).onClick(() => { this.selectSkill(skill.id); })
            }, (skill: AvatarWikiSkill) => 'skill_' + this.selectedId + '_' + skill.id + '_' +
              this.appliedLocaleVersion + '_' + Math.floor(this.skillStripWidth) + '_' + (this.selectedSkillId === skill.id))
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).width('100%')
          .onAreaChange((_old: Area, area: Area): void => { this.skillStripWidth = Number(area.width); })
        Flex({ wrap: FlexWrap.Wrap }) {
          Column({ space: 8 }) {
            Text(this.selectedSkill()?.name ?? '').fontSize(15).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(WikiMetaService.cleanText(this.selectedSkill()?.description ?? ''))
              .fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
            if ((this.selectedSkill()?.specialDescription.length ?? 0) > 0) {
              Text(WikiMetaService.cleanText(this.selectedSkill()?.specialDescription ?? ''))
                .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            }
          }.alignItems(HorizontalAlign.Start)
            .width(this.isWide && (this.selectedSkill()?.levels.length ?? 0) > 0 ? '50%' : '100%')
            .padding({ right: this.isWide ? 14 : 0, bottom: 12 })
          if ((this.selectedSkill()?.levels.length ?? 0) > 0) {
            this.skillParameters()
          }
        }.width('100%')
      }.width('100%').padding(14)
        .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel)).borderRadius(8)
    }
  }

  @Builder
  skillParameters() {
    Column() {
      Row({ space: 6 }) {
        Text('等级').fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Select(this.skillLevelOptions()).selected(this.skillLevelIndex()).value('Lv. ' + this.selectedSkillLevel)
          .font({ size: 13 }).fontColor($r('app.color.text_primary'))
          .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .onSelect((index: number, _value: string): void => { this.selectSkillLevel(index); })
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph(this.parametersExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14).fontColor([$r('app.color.text_secondary')])
        }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .width(40).height(40).padding(0).accessibilityText(this.parametersExpanded ? '收起技能数值' : '展开技能数值')
          .onClick(() => { this.parametersExpanded = !this.parametersExpanded; })
      }.width('100%').padding({ left: 10, right: 4, top: 4, bottom: 4 })
      if (this.parametersExpanded) {
        ForEach(this.skillParameterRows(), (row: AvatarSkillParameterRow, index: number) => {
          Row({ space: 10 }) {
            Text(WikiMetaService.cleanText(row.label)).fontSize(12).fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            Text(WikiMetaService.cleanText(row.value)).fontSize(12)
              .fontColor(row.isSpecial ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
              .textAlign(TextAlign.End).constraintSize({ maxWidth: '55%' })
          }.width('100%').alignItems(VerticalAlign.Top)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .border({ width: { top: 1 }, color: $r('app.color.divider') })
        }, (row: AvatarSkillParameterRow, index: number) => 'parameter_' + this.selectedId + '_' +
          this.selectedSkillId + '_' + this.selectedSkillLevel + '_' + index + '_' + this.appliedLocaleVersion)
      }
    }.width(this.isWide ? '50%' : '100%').border({ width: 1, color: $r('app.color.card_stroke') }).borderRadius(6)
  }

  /** 命座卡（无参：读 @State current） */
  @Builder
  talentsCard() {
    Column({ space: 8 }) {
      Text(`命座 · ${this.current?.constellation ?? ''}`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      ForEach(this.current?.talents ?? [], (s: MetaSkill, idx: number) => {
        Row({ space: 10 }) {
          Text(`${idx + 1}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary_text'))
            .width(20)
            .textAlign(TextAlign.Center)
          Row() {
            MetaIcon({ category: 'Talent', name: s.i, iconSize: 34 })
          }
          .width(44)
          .height(44)
          .borderRadius(10)
          .backgroundColor($r('app.color.icon_dark_chip'))
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          Column({ space: 3 }) {
            Text(s.n)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(s.d)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8, left: 12, right: 12 })
        .borderRadius(10)
        .backgroundColor($r('app.color.card_inner_tint'))
        .alignItems(VerticalAlign.Top)
      }, (s: MetaSkill, idx: number) => `tl_${this.selectedId}_${idx}_${this.appliedLocaleVersion}`)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  /** 料理卡（无参：读 @State current） */
  @Builder
  cookCard() {
    Column({ space: 8 }) {
      Text($r('app.string.ui_wi_ki_avatar_special_food_title'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.current !== undefined && this.current.cook !== null) {
        Row({ space: 10 }) {
          MetaIcon({ category: 'ItemIcon', name: this.matIcon(Number(this.current.cook!['item'])), iconSize: 36 })
          Column({ space: 2 }) {
            Text(this.matName(Number(this.current.cook!['item'])))
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
            Text(`基于 ${this.matName(Number(this.current.cook!['origin']))} 制作`)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  /** 语音/故事卡（kind：'fetters'|'stories'；直接读 @State current，切换角色自动刷新） */
  @Builder
  textsCard(title: string, kind: string) {
    if (this.current !== undefined) {
      if (kind === 'stories' ? this.current.stories.length > 0 : this.current.fetters.length > 0) {
        Column({ space: 8 }) {
          Text(`${title}（${kind === 'stories' ? this.current.stories.length : this.current.fetters.length}）`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          ForEach(kind === 'stories' ? this.current.stories : this.current.fetters, (t: MetaText, idx: number) => {
            Column({ space: 3 }) {
              Text(t.t)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(t.c)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding({ top: 8, bottom: 8, left: 12, right: 12 })
            .borderRadius(8)
            .backgroundColor($r('app.color.card_inner_tint'))
          }, (t: MetaText, idx: number) => `tx_${this.selectedId}_${kind}_${idx}_${this.appliedLocaleVersion}`)
        }
        .width('100%')
        .padding(14)
        .borderRadius($r('app.float.card_radius'))
        .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      }
    }
  }

  /** 名片区块（对齐 Windows WikiAvatarPage NameCard Expander：胶囊横幅 + 大图卡） */
  @Builder
  nameCardBlock() {
    if (this.current !== undefined && this.current.nameCardPic.length > 0) {
      Column({ space: 8 }) {
        Text($r('app.string.ui_wi_ki_avatar_name_card_header'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        // 胶囊横幅：右侧大图 + 左侧头像圆框（对齐 Windows 90 高圆角 45 布局）
        Stack({ alignContent: Alignment.Start }) {
          Image($rawfile(`icons/NameCardPic/${this.current.nameCardPic}.png`))
            .height(90)
            .width('100%')
            .objectFit(ImageFit.Cover)
          Row() {
            MetaIcon({ category: 'AvatarIcon', name: this.current.icon, iconSize: 56 })
          }
          .margin({ left: 12 })
        }
        .width('100%')
        .height(90)
        .borderRadius(45)
        .clip(true)
        .backgroundColor($r('app.color.page_background'))
        // 大图卡：全幅名片 + 左下角图标/名称/描述浮层（对齐 Windows AcrylicSecondaryGridCardStyle）
        Stack({ alignContent: Alignment.BottomStart }) {
          Image($rawfile(`icons/NameCardPic/${this.current.nameCardPic}.png`))
            .width('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
          Row({ space: 12 }) {
            MetaIcon({ category: 'NameCardIcon', name: this.current.nameCardIcon, iconSize: 52 })
            Column({ space: 4 }) {
              Text(this.ncName.length > 0 ? this.ncName : `${this.current.name}的名片`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.ncDesc.length > 0) {
                Text(this.ncDesc)
                  .fontSize(10)
                  .fontColor(Color.White)
                  .opacity(0.85)
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Bottom)
          .padding(12)
        }
        .width('100%')
        .borderRadius(12)
        .clip(true)
        .backgroundColor($r('app.color.page_background'))
      }
      .width('100%')
      .padding(14)
      .borderRadius($r('app.float.card_radius'))
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    }
  }



  /** 与资料相邻的外部攻略入口。 */
  @Builder
  strategyBlock() {
    if (this.current !== undefined) {
      GridRow({ columns: this.isWide ? (this.contentLocale === 'zh-Hans' ? 3 : 2) : 1, gutter: { x: 8, y: 6 } }) {
        GridCol() { this.strategyChip('mys') }
        if (this.contentLocale === 'zh-Hans') { GridCol() { this.strategyChip('bili') } }
        GridCol() { this.strategyChip('hoyolab') }
      }.width('100%')
    }
  }

  @Builder
  strategyChip(target: string) {
    Button({ type: ButtonType.Normal }) {
      Text(WikiAvatarGuide.label(target, this.contentLocale)).fontSize(13).fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Start).width('100%')
    }
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
      .width('100%').constraintSize({ minHeight: 44 }).padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .accessibilityText(WikiAvatarGuide.label(target, this.contentLocale))
      .onClick((): void => { this.openStrategy(target); })
  }



}
