/**
 * CharacterViewModel.ets
 * 角色资料页状态容器（含 1034 风控极验重放：needRiskVerify 通知 UI 弹验证窗）。
 * 缓存先显示；远端列表及每个详情批次逐步发布，整轮仅合并写入一次详情缓存。
 */
import { CharacterService } from '../service/CharacterService';
import { UserService } from '../service/UserService';
import { BaseProperty, CharacterListItem, CharacterDetail, Constellation, DetailedWeapon } from '../model/CharacterData';
import { BackpackScoreEdit, BackpackScoreProfile, BackpackScoreSettings, CharacterScoreOption } from '../model/BackpackScore';
import { BackpackScoreService } from '../service/BackpackScoreService';
import { WikiMetaService } from '../service/WikiMetaService';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { Logger } from '../common/Logger';
import { CharacterFilterKind, CharacterFilterToken } from './CharacterFilter';

const TAG: string = 'CharacterViewModel';
const ELEMENT_ORDER: string[] = ['', 'Pyro', 'Hydro', 'Dendro', 'Electro', 'Cryo', 'Frozen', 'Anemo', 'Geo'];

export enum CharacterSortKind {
  Default,
  Level,
  Quality,
  Constellations,
  Fetter,
  MaxHp,
  Attack,
  Defense,
  ElementalMastery,
}

/** 加入养成计划结果（对齐 Windows ConsumptionSaveResultKind 的页面提示口径） */
export class AddPlanResult {
  ok: boolean = false;
  message: string = '';
}

@Observed
export class CharacterViewModel {
  items: CharacterListItem[] = [];
  /** 本轮已可用的详情，角色点击优先本地切换。 */
  detailMap: Map<number, CharacterDetail> = new Map();
  detail: CharacterDetail | undefined = undefined;
  loading: boolean = false;
  loadingDetail: boolean = false;
  detailLoading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 当前选中的角色 id */
  selectedId: number = 0;
  scoreSettings: BackpackScoreSettings = new BackpackScoreSettings();
  scoreOptions: CharacterScoreOption[] = BackpackScoreService.characterOptions(this.scoreSettings);
  scoreOptionIndex: number = 0;
  private currentUid: string = '';
  private requestRevision: number = 0;
  private selectionRevision: number = 0;
  private active: boolean = true;
  private onUpdated: (() => void) | undefined = undefined;
  private stopSessionWatch: (() => void) | undefined = undefined;

  activate(onUpdated: () => void): void {
    this.active = true;
    this.onUpdated = onUpdated;
    if (this.stopSessionWatch === undefined) {
      const users: UserService = UserService.getInstance();
      this.stopSessionWatch = users.addSessionRevisionListener((): void => {
        if (this.active && !users.isSessionTransitionPending()) { this.load(this.currentUid); }
      });
    }
  }

  dispose(): void {
    this.active = false; this.requestRevision++; this.selectionRevision++;
    this.onUpdated = undefined;
    this.stopSessionWatch?.(); this.stopSessionWatch = undefined;
  }

  private notify(): void { if (this.active) { this.onUpdated?.(); } }

  private owns(revision: number, uid: string, session: number): boolean {
    return this.active && revision === this.requestRevision && uid === this.currentUid &&
      session === UserService.getInstance().sessionRevision();
  }

  private chooseSelection(preferred: number): void {
    this.selectedId = this.items.some((item: CharacterListItem): boolean => item.id === preferred)
      ? preferred : this.items[0]?.id ?? 0;
    this.syncCurrentDetail();
  }
  /** 风控需人机验证（true 时 UI 弹验证窗） */
  needRiskVerify: boolean = false;
  /** 极验参数（弹窗用） */
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  async load(uid: string): Promise<void> {
    if (!this.active) { return; }
    const preferred: number = uid === this.currentUid ? this.selectedId : 0;
    const revision: number = ++this.requestRevision;
    this.selectionRevision++;
    const users: UserService = UserService.getInstance();
    const session: number = users.sessionRevision();
    this.currentUid = uid;
    this.message = ''; this.detailLoading = false; this.loadingDetail = false;
    this.needRiskVerify = false;
    if (uid.length === 0) {
      this.items = []; this.detailMap = new Map<number, CharacterDetail>();
      this.selectedId = 0; this.detail = undefined; this.loading = false; this.loaded = true;
      this.message = '请先在「账号与数据」选择默认 UID'; this.notify();
      return;
    }
    const service: CharacterService = CharacterService.getInstance();
    this.items = service.getCachedList(uid);
    this.detailMap = new Map<number, CharacterDetail>();
    for (const detail of service.getCachedDetails(uid)) { this.detailMap.set(detail.id, detail); }
    this.chooseSelection(preferred);
    this.loading = true;
    this.loaded = this.items.length > 0;
    this.notify();
    // AppStorage 的 UID 变化可能先于账号事务结束；会话完成通知会重启当前 UID 的刷新。
    if (users.isSessionTransitionPending()) { return; }
    const isCurrent: () => boolean = (): boolean => this.owns(revision, uid, session);
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      const items: CharacterListItem[] = await service.fetchList(uid, challenge || undefined, isCurrent);
      if (!isCurrent()) { return; }
      this.items = items;
      this.chooseSelection(this.selectedId || preferred);
      this.loaded = true;
      this.notify();
      if (items.length > 0) { await this.loadAllDetails(uid); }
    } catch (e) {
      if (isCurrent()) { this.handleError(e); }
    } finally {
      if (isCurrent()) { this.loading = false; this.loaded = true; this.notify(); }
    }
  }

  /** 选中角色放在第一批；每批成功即可显示，失败保留已到达的数据与错误提示。 */
  async loadAllDetails(uid: string): Promise<void> {
    if (!this.active || uid !== this.currentUid || this.items.length === 0) { return; }
    const revision: number = this.requestRevision;
    const session: number = UserService.getInstance().sessionRevision();
    const isCurrent: () => boolean = (): boolean => this.owns(revision, uid, session);
    const ids: number[] = this.items.map((item: CharacterListItem): number => item.id);
    const selectedIndex: number = ids.indexOf(this.selectedId);
    if (selectedIndex > 0) { ids.splice(selectedIndex, 1); ids.unshift(this.selectedId); }
    this.detailLoading = true;
    this.loadingDetail = this.selectedId > 0 && !this.detailMap.has(this.selectedId);
    this.notify();
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      await CharacterService.getInstance().fetchDetailBatches(uid, ids, (details: CharacterDetail[]): void => {
        if (!isCurrent()) { return; }
        const next: Map<number, CharacterDetail> = new Map<number, CharacterDetail>(this.detailMap);
        for (const detail of details) { next.set(detail.id, detail); }
        this.detailMap = next;
        this.syncCurrentDetail();
        this.loadingDetail = this.selectedId > 0 && !this.detailMap.has(this.selectedId);
        this.notify();
      }, isCurrent, challenge || undefined);
      if (isCurrent()) { this.message = ''; }
    } catch (e) {
      if (isCurrent()) { this.handleError(e); }
    } finally {
      if (isCurrent()) { this.detailLoading = false; this.loadingDetail = false; this.notify(); }
    }
  }

  /** 缓存点击同步可用；全量刷新已覆盖的角色不重复发单角色请求。 */
  async select(uid: string, id: number): Promise<void> {
    if (!this.active || uid !== this.currentUid) { return; }
    const revision: number = this.requestRevision;
    const selection: number = ++this.selectionRevision;
    const session: number = UserService.getInstance().sessionRevision();
    const isCurrent: () => boolean = (): boolean => this.owns(revision, uid, session) &&
      selection === this.selectionRevision && id === this.selectedId;
    this.selectedId = id;
    this.syncCurrentDetail();
    this.loadingDetail = this.detail === undefined;
    this.notify();
    if (this.detail !== undefined || this.loading || this.detailLoading) { return; }
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      const details: CharacterDetail[] = await CharacterService.getInstance()
        .fetchDetail(uid, [id], challenge || undefined, isCurrent);
      if (!isCurrent()) { return; }
      const detail: CharacterDetail | undefined = details.find((item: CharacterDetail): boolean => item.id === id);
      if (detail !== undefined) {
        const next: Map<number, CharacterDetail> = new Map<number, CharacterDetail>(this.detailMap);
        next.set(id, detail); this.detailMap = next; this.syncCurrentDetail();
      }
    } catch (e) { if (isCurrent()) { this.handleError(e); } }
    finally { if (isCurrent()) { this.loadingDetail = false; this.notify(); } }
  }

  /** 兼容旧调用：加载选中角色详情（点击时由 UI 调用） */
  async loadDetail(uid: string, id: number): Promise<void> {
    await this.select(uid, id);
  }

  /** 当前选中角色的详情（页面调用后回填 @State） */
  detailOfSelected(): CharacterDetail | undefined {
    return this.detailMap.get(this.selectedId);
  }

  filteredItems(tokens: CharacterFilterToken[], sort: CharacterSortKind,
    useLocalizedNames: boolean = true): CharacterListItem[] {
    const names: string[] = [];
    const elements: string[] = [];
    const weapons: string[] = [];
    const qualities: string[] = [];
    for (const token of tokens) {
      switch (token.kind) {
        case CharacterFilterKind.Name: names.push(token.value.toLowerCase()); break;
        case CharacterFilterKind.Element: elements.push(token.value); break;
        case CharacterFilterKind.Weapon: weapons.push(token.value); break;
        case CharacterFilterKind.Quality: qualities.push(token.value); break;
      }
    }
    const filtered: CharacterListItem[] = this.items.filter((item: CharacterListItem): boolean => {
      if (names.length > 0) {
        const original: string = item.name.toLowerCase();
        const localized: string = useLocalizedNames ? (WikiMetaService.avatarOf(item.id)?.name ?? '').toLowerCase() : '';
        const canonical: string = useLocalizedNames ? (WikiMetaService.avatarOf(item.id)?.canonicalName ?? '').toLowerCase() : '';
        if (!names.some((name: string): boolean => original.includes(name) || localized.includes(name) || canonical.includes(name))) {
          return false;
        }
      }
      if (elements.length > 0 && !elements.includes(item.element)) { return false; }
      if (weapons.length > 0 && !weapons.includes(String(this.weaponType(item)))) { return false; }
      return qualities.length === 0 || qualities.includes(String(CharacterViewModel.quality(item)));
    });
    filtered.sort((left: CharacterListItem, right: CharacterListItem): number => {
      const quality: number = CharacterViewModel.quality(right) - CharacterViewModel.quality(left);
      const level: number = right.level - left.level;
      const element: number = ELEMENT_ORDER.indexOf(left.element) - ELEMENT_ORDER.indexOf(right.element);
      if (sort === CharacterSortKind.Default) {
        return quality || level || element || this.weaponType(left) - this.weaponType(right) || right.fetter - left.fetter;
      }
      return this.sortValue(right, sort) - this.sortValue(left, sort) || level || quality || -element || right.id - left.id;
    });
    return filtered;
  }

  private static quality(item: CharacterListItem): number {
    return WikiMetaService.avatarOf(item.id)?.quality || item.rarity;
  }

  private weaponType(item: CharacterListItem): number {
    const weapon: DetailedWeapon | undefined = this.detailMap.get(item.id)?.weapon;
    const id: number = weapon?.id || item.weapon.id;
    return WikiMetaService.weaponOf(id)?.weaponType || weapon?.type || item.weapon.type || item.weaponType;
  }

  private sortValue(item: CharacterListItem, sort: CharacterSortKind): number {
    const detail: CharacterDetail | undefined = this.detailMap.get(item.id);
    switch (sort) {
      case CharacterSortKind.Level: return item.level;
      case CharacterSortKind.Quality: return CharacterViewModel.quality(item);
      case CharacterSortKind.Constellations:
        if (detail !== undefined && detail.constellations.length > 0) {
          return detail.constellations.filter((constellation: Constellation): boolean => constellation.isActived).length;
        }
        return detail !== undefined && detail.activedConstellationNum >= 0
          ? detail.activedConstellationNum : item.activedConstellationNum;
      case CharacterSortKind.Fetter: return item.fetter;
      case CharacterSortKind.MaxHp: return CharacterViewModel.propertyValue(detail, 'FIGHT_PROP_MAX_HP', '2000');
      case CharacterSortKind.Attack: return CharacterViewModel.propertyValue(detail, 'FIGHT_PROP_CUR_ATTACK', '2001');
      case CharacterSortKind.Defense: return CharacterViewModel.propertyValue(detail, 'FIGHT_PROP_CUR_DEFENSE', '2002');
      case CharacterSortKind.ElementalMastery:
        return CharacterViewModel.propertyValue(detail, 'FIGHT_PROP_ELEMENT_MASTERY', '28');
      default: return 0;
    }
  }

  private static propertyValue(detail: CharacterDetail | undefined, name: string, id: string): number {
    const property: BaseProperty | undefined = detail?.selectedProperties.find((value: BaseProperty): boolean =>
      value.propertyType === name || value.propertyType === id);
    if (property === undefined) { return 0; }
    const value: number = property.base.length > 0 ? Number(property.base) + Number(property.add) : Number(property.final);
    return Number.isFinite(value) ? value : 0;
  }

  loadScoreOptions(avatarId: number): void {
    this.scoreSettings = BackpackScoreService.load();
    const options: CharacterScoreOption[] = BackpackScoreService.characterOptions(this.scoreSettings);
    this.scoreOptionIndex = options.indexOf(BackpackScoreService.characterOption(avatarId, this.scoreSettings, options));
    this.scoreOptions = options;
  }

  selectScoreOption(avatarId: number, index: number): void {
    const option: CharacterScoreOption | undefined = this.scoreOptions[index];
    if (avatarId !== this.selectedId || option === undefined) { return; }
    BackpackScoreService.setCharacterOption(avatarId, option.key);
    this.scoreOptionIndex = index;
  }

  scoreWeights(avatarId: number): number[] | undefined {
    if (avatarId === this.selectedId) { return this.scoreOptions[this.scoreOptionIndex]?.profile?.weights; }
    return BackpackScoreService.characterOption(avatarId, this.scoreSettings, this.scoreOptions).profile?.weights;
  }

  beginScoreEdit(avatarId: number): BackpackScoreEdit {
    this.loadScoreOptions(avatarId);
    const current: BackpackScoreProfile | undefined = this.scoreOptions[this.scoreOptionIndex]?.profile;
    const edit: BackpackScoreEdit = new BackpackScoreEdit();
    edit.settingsRevision = this.scoreSettings.revision;
    edit.profile = current !== undefined && current.id.length > 0
      ? BackpackScoreProfile.clone(current) : BackpackScoreService.active(this.scoreSettings);
    return edit;
  }

  saveScore(avatarId: number, edit: BackpackScoreEdit, profile: BackpackScoreProfile, deletedIds: string[]): void {
    if (avatarId !== this.selectedId) { throw new Error('所选角色已改变，请重新打开评分设置'); }
    const settings: BackpackScoreSettings = BackpackScoreService.save(profile, edit.settingsRevision, deletedIds);
    const key: string = BackpackScoreProfile.isTransientDefault(profile) ? 'preset:0' : `saved:${settings.activeId}`;
    BackpackScoreService.setCharacterOption(avatarId, key);
    this.loadScoreOptions(avatarId);
  }

  private syncCurrentDetail(): void {
    const d: CharacterDetail | undefined = this.detailMap.get(this.selectedId);
    this.detail = d;
  }

  private handleError(e: Error): void {
    if (e instanceof RiskControlError) {
      this.needRiskVerify = true;
      this.riskGt = e.gt;
      this.riskChallenge = e.challenge;
      this.riskPath = e.path;
      this.message = '需要完成人机验证';
    } else {
      this.message = (e as Error).message;
      Logger.warn(TAG, `load fail: ${this.message}`);
    }
  }

  /** 极验完成后由 UI 调用：清除标记并重新加载 */
  resetRiskAndReload(uid: string): void {
    this.needRiskVerify = false;
    this.load(uid).then(() => {
    });
  }
}
