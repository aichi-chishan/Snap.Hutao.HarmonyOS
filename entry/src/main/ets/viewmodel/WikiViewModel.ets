/**
 * WikiViewModel.ets
 * 图鉴页状态容器（角色/武器通用）：列表 slug，惰性加载详情。
 */
import { WikiService, WikiAvatarDetail, WikiWeaponDetail, WikiEnemyDetail } from '../service/WikiService';

@Observed
export class WikiViewModel {
  /** slug 列表 */
  slugs: string[] = [];
  kind: string = 'avatar';
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 当前选中详情（惰性加载） */
  detailAvatar: WikiAvatarDetail | undefined = undefined;
  detailWeapon: WikiWeaponDetail | undefined = undefined;
  detailEnemy: WikiEnemyDetail | undefined = undefined;
  detailLoading: boolean = false;

  constructor(kind: string = 'avatar') {
    this.kind = kind;
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      if (this.kind === 'avatar') {
        this.slugs = await WikiService.getInstance().fetchCharacterList();
      } else if (this.kind === 'weapon') {
        this.slugs = await WikiService.getInstance().fetchWeaponList();
      } else {
        this.slugs = await WikiService.getInstance().fetchEnemyList();
      }
    } catch (e) {
      this.message = (e as Error).message;
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }

  /** 加载单个详情 */
  async loadDetail(slug: string): Promise<void> {
    this.detailLoading = true;
    try {
      if (this.kind === 'avatar') {
        this.detailAvatar = await WikiService.getInstance().fetchCharacterDetail(slug);
        this.detailWeapon = undefined;
        this.detailEnemy = undefined;
      } else if (this.kind === 'weapon') {
        this.detailWeapon = await WikiService.getInstance().fetchWeaponDetail(slug);
        this.detailAvatar = undefined;
        this.detailEnemy = undefined;
      } else {
        this.detailEnemy = await WikiService.getInstance().fetchEnemyDetail(slug);
        this.detailAvatar = undefined;
        this.detailWeapon = undefined;
      }
    } finally {
      this.detailLoading = false;
    }
  }

  clearDetail(): void {
    this.detailAvatar = undefined;
    this.detailWeapon = undefined;
    this.detailEnemy = undefined;
  }
}
