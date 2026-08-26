/**
 * CharacterData.ets
 * 角色资料数据模型（对齐米哈游 character/list + character/detail 接口字段）。
 */

/** 角色武器（列表） */
export class ListWeapon {
  id: number = 0;
  type: number = 0;
  rarity: number = 0;
  level: number = 0;
  affixLevel: number = 0;
}

/** 角色列表项 */
export class CharacterListItem {
  id: number = 0;
  name: string = '';
  element: string = '';
  fetter: number = 0;
  level: number = 0;
  rarity: number = 0;
  weaponType: number = 0;
  activedConstellationNum: number = 0;
  /** 官方头像 URL（character/list avatar_icon 字段，米哈游 CDN） */
  icon: string = '';
  weapon: ListWeapon = new ListWeapon();
}

/** 圣遗物属性 */
export class RelicProperty {
  propertyType: string = '';
  value: string = '';
  times: number = 0;
}

/** 圣遗物 */
export class Reliquary {
  id: number = 0;
  name: string = '';
  icon: string = '';
  pos: number = 0;
  rarity: number = 0;
  level: number = 0;
  posName: string = '';
  mainProperty: RelicProperty = new RelicProperty();
  subProperties: RelicProperty[] = [];
}

/** 命座 */
export class Constellation {
  id: number = 0;
  name: string = '';
  icon: string = '';
  effect: string = '';
  isActived: boolean = false;
  pos: number = 0;
}

/** 面板属性 */
export class BaseProperty {
  propertyType: string = '';
  base: string = '';
  add: string = '';
  final: string = '';
}

/** 推荐圣遗物属性（API recommend_relic_property，用于 Windows 加权评分） */
export class RecommendRelic {
  /** 推荐词条（FightProperty 名） */
  subProperties: string[] = [];
  /** 能量类型（NONE/MAVUIKA/SKIRK，用于充能权重） */
  energyType: string = '';
}

/** 角色详情 */
export class CharacterDetail {
  id: number = 0;
  name: string = '';
  element: string = '';
  level: number = 0;
  rarity: number = 0;
  fetter: number = 0;
  activedConstellationNum: number = 0;
  /** 官方头像 URL（detail 接口 avatar_icon 字段） */
  icon: string = '';
  weapon: DetailedWeapon = new DetailedWeapon();
  reliquaries: Reliquary[] = [];
  constellations: Constellation[] = [];
  selectedProperties: BaseProperty[] = [];
  promoteLevel: number = 0;
  /** 推荐圣遗物词条（Window 评分权重依据） */
  recommend: RecommendRelic = new RecommendRelic();
}

/** 详情武器 */
export class DetailedWeapon {
  id: number = 0;
  type: number = 0;
  rarity: number = 0;
  level: number = 0;
  affixLevel: number = 0;
  promoteLevel: number = 0;
}

/** 头像 URL（Enka 公开源，非胡桃云；规则 UI_AvatarIcon_{id}.png） */
export function avatarIconUrl(avatarId: number): string {
  return `https://enka.network/ui/UI_AvatarIcon_${avatarId}.png`;
}

/** 圆形头像 URL */
export function avatarCircleUrl(avatarId: number): string {
  return `https://enka.network/ui/UI_AvatarIconCircle_${avatarId}.png`;
}

/** 元素中文名 */
export function elementName(element: string): string {
  switch (element) {
    case 'Pyro': return '火';
    case 'Hydro': return '水';
    case 'Dendro': return '草';
    case 'Electro': return '雷';
    case 'Cryo': return '冰';
    case 'Anemo': return '风';
    case 'Geo': return '岩';
    default: return element;
  }
}

/** 元素 emoji */
export function elementIcon(element: string): string {
  switch (element) {
    case 'Pyro': return '🔥';
    case 'Hydro': return '💧';
    case 'Dendro': return '🌿';
    case 'Electro': return '⚡';
    case 'Cryo': return '❄';
    case 'Anemo': return '🌪';
    case 'Geo': return '⛰';
    default: return '❓';
  }
}
