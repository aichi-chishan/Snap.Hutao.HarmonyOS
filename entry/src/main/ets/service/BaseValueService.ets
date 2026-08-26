/**
 * BaseValueService.ets
 * 基础数值曲线计算（对齐 Windows BaseValueInfoConverter 公式）：
 *   值(level, promoted) = InitValue × GrowCurveMap[level][growCurveType] + PromoteMap[promoteLevel].AddProperties[fightProperty]
 * 数据：rawfile/metadata/{WeaponCurve,WeaponPromote,AvatarCurve,AvatarPromote,MonsterCurve}.json
 */
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'BaseValueService';

type Curves = Map<number, Map<number, number>>; // level -> (curveType -> 系数)
type Promotes = Map<number, Map<number, Map<number, number>>>; // promoteId -> (promoteLevel -> (fightProp -> 值))

export class BaseValueService {
  private static weaponCurves: Curves | undefined = undefined;
  private static weaponPromotes: Promotes | undefined = undefined;
  private static avatarCurves: Curves | undefined = undefined;
  private static avatarPromotes: Promotes | undefined = undefined;
  private static monsterCurves: Curves | undefined = undefined;

  /** 品质 → 最大等级（>=4星90，否则70；对齐 Windows GetMaxLevelByQuality） */
  static weaponMaxLevel(rankLevel: number): number {
    return rankLevel >= 4 ? 90 : 70;
  }

  /** 突破等级（对齐 Windows GetPromoteLevel） */
  static promoteLevel(level: number, maxLevel: number, promoted: boolean): number {
    if (promoted) {
      if (level >= 80) { return 6; }
      if (level >= 70) { return 5; }
      if (level >= 60) { return 4; }
      if (level >= 50) { return 3; }
      if (level >= 40) { return 2; }
      if (level >= 20) { return 1; }
      return 0;
    }
    if (level > 80) { return 6; }
    if (level > 70) { return 5; }
    if (level > 60) { return 4; }
    if (level > 50) { return 3; }
    if (level > 40) { return 2; }
    if (level > 20) { return 1; }
    return 0;
  }

  /** 武器某等级攻击力（value = InitValue × curve[level][growCurveType] + promote[promoteLevel][FIGHT_PROP_BASE_ATTACK]） */
  static async weaponAttack(id: number, level: number, promoted: boolean): Promise<number> {
    const weapon = await BaseValueService.weaponOf(id);
    if (weapon === undefined) {
      return 0;
    }
    const curves: Curves = await BaseValueService.getWeaponCurves();
    const promotes: Promotes = await BaseValueService.getWeaponPromotes();
    const maxLv: number = BaseValueService.weaponMaxLevel(weapon.rankLevel);
    const pLevel: number = BaseValueService.promoteLevel(level, maxLv, promoted);
    let base: number = 0;
    let added: number = 0;
    for (const g of weapon.growCurves) {
      // t: 4=FIGHT_PROP_BASE_ATTACK（攻击）；只算攻击
      if (g.t === 4) {
        const curveLevel: Map<number, number> | undefined = curves.get(level);
        base = g.i * ((curveLevel !== undefined ? curveLevel.get(g.v) : undefined) ?? 0);
      }
    }
    const pMap: Map<number, Map<number, number>> | undefined = promotes.get(weapon.promoteId);
    const pLevelMap: Map<number, number> | undefined = pMap !== undefined ? pMap.get(pLevel) : undefined;
    added = (pLevelMap !== undefined ? pLevelMap.get(4) : undefined) ?? 0;
    return Math.round(base + added);
  }

  private static async weaponOf(id: number): Promise<GrowCurveItem | undefined> {
    const meta = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/weapon_meta.json'))) as Object[];
    for (const raw of meta) {
      const o = raw as Record<string, Object>;
      if (Number(o['id']) === id) {
        const w: GrowCurveItem = { rankLevel: Number(o['rankLevel'] ?? 0), promoteId: Number(o['promoteId'] ?? 0), growCurves: [] };
        const arr = (o['growCurves'] as Object[]) ?? [];
        for (const g of arr) {
          const go = g as Record<string, Object>;
          const c: Curve3 = new Curve3();
          c.i = Number(go['i'] ?? 0);
          c.t = Number(go['t'] ?? 0);
          c.v = Number(go['v'] ?? 0);
          w.growCurves.push(c);
        }
        return w;
      }
    }
    return undefined;
  }

  private static async getWeaponCurves(): Promise<Curves> {
    if (BaseValueService.weaponCurves !== undefined) {
      return BaseValueService.weaponCurves;
    }
    const raw = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/WeaponCurve.json'))) as Object[];
    const map: Curves = new Map();
    for (const levelRow of raw) {
      const ro = levelRow as Record<string, Object>;
      const level = Number(ro['Level'] ?? 0);
      const inner: Map<number, number> = new Map();
      const curvesArr = (ro['Curves'] as Object[]) ?? [];
      for (const c of curvesArr) {
        const co = c as Record<string, Object>;
        inner.set(Number(co['Type'] ?? 0), Number(co['Value'] ?? 0));
      }
      map.set(level, inner);
    }
    BaseValueService.weaponCurves = map;
    Logger.info(TAG, `weaponCurves: ${map.size} levels`);
    return map;
  }

  private static async getWeaponPromotes(): Promise<Promotes> {
    if (BaseValueService.weaponPromotes !== undefined) {
      return BaseValueService.weaponPromotes;
    }
    const raw = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/WeaponPromote.json'))) as Object[];
    const map: Promotes = new Map();
    for (const row of raw) {
      const ro = row as Record<string, Object>;
      const promoteId = Number(ro['Id'] ?? 0);
      const level = Number(ro['Level'] ?? 0);
      let idMap: Map<number, Map<number, number>> | undefined = map.get(promoteId);
      if (idMap === undefined) {
        idMap = new Map();
        map.set(promoteId, idMap);
      }
      const props: Map<number, number> = new Map();
      const adds = (ro['AddProperties'] as Object[]) ?? [];
      for (const add of adds) {
        const ao = add as Record<string, Object>;
        props.set(Number(ao['Type'] ?? 0), Number(ao['Value'] ?? 0));
      }
      idMap.set(level, props);
    }
    BaseValueService.weaponPromotes = map;
    Logger.info(TAG, `weaponPromotes: ${map.size} ids`);
    return map;
  }
}

/** 武器曲线项（供等级滑条计算） */
export class GrowCurveItem {
  rankLevel: number = 0;
  promoteId: number = 0;
  growCurves: Curve3[] = [];
}

/** 单条曲线 */
export class Curve3 {
  i: number = 0;
  t: number = 0;
  v: number = 0;
}
