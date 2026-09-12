/**
 * TowerMetadataService.ets
 * 深渊塔元数据解析（对齐 Windows SpiralAbyssMetadataContext + TowerWave）：
 *   - 渊月祝福：TowerSchedule（Id=scheduleId → BuffName/Descriptions）
 *   - 敌人波次：TowerSchedule.FloorIds → TowerFloor(Index) → LevelGroupId
 *     → TowerLevel(GroupId, Index=间号) → FirstWaves/SecondWaves（Type=波次语义，Monsters=怪物 describeId）
 *   - 怪物 describeId → name/icon（monster_meta，含 Windows MonsterDescribe.Normalize 归一表）
 * 数据：rawfile/metadata/{TowerSchedule,TowerFloor,TowerLevel,monster_meta}.json（本地打包）
 */
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'TowerMetadata';

/** 单波敌人视图 */
export class TowerWaveView {
  /** 波次语义描述（如"A组第一波：不同的组同时在场，各自分波独立"） */
  label: string = '';
  /** 出战怪物（名称+图标名已解析） */
  monsters: TowerMonsterView[] = [];
  /** 怪物等级 */
  monsterLevel: number = 0;
}

/** 单个怪物视图 */
export class TowerMonsterView {
  name: string = '';
  icon: string = '';
  count: number = 1;
}

/** 半场波次集合 */
export class ChamberWaves {
  upper: TowerWaveView[] = [];
  lower: TowerWaveView[] = [];
  monsterLevel: number = 0;
}

/** 渊月祝福 */
export class TowerBuff {
  name: string = '';
  description: string = '';
}

interface TowerScheduleRow {
  Id: number;
  FloorIds: number[];
  BuffName: string;
  Descriptions: string[];
}

interface TowerFloorRow {
  Id: number;
  Index: number;
  LevelGroupId: number;
}

interface TowerLevelRow {
  GroupId: number;
  Index: number;
  MonsterLevel: number;
  FirstWaves: TowerWaveRow[];
  SecondWaves: TowerWaveRow[];
}

interface TowerWaveRow {
  Type: number;
  Monsters: TowerMonsterRow[];
}

interface TowerMonsterRow {
  Id: number;
  Count: number;
}

interface MonsterMetaRow {
  describeId: number;
  name: string;
  icon: string;
}

/** Windows MonsterDescribe.Normalize：塔怪 describeId 归一（强化体→本体） */
const NORMALIZE: Map<number, number> = new Map([
  [5020, 502], [5021, 502], [5040, 504], [5041, 504], [5070, 507], [5071, 507],
  [5102, 510], [5112, 511], [30121, 30111], [30123, 30113], [30126, 30116],
  [30127, 30115], [30129, 30117], [30591, 30581], [30605, 30603], [30606, 30603],
  [31301, 31301], [31302, 31302], [31311, 31311], [31312, 31312],
]);

/** WaveType → 中文描述（对齐 Windows SH.ModelMetadataTowerWaveType*） */
const WAVE_LABELS: Map<number, string> = new Map([
  [0, '本间怪物'],
  [1, '第一波'], [2, '第二波'], [3, '第三波'], [4, '第四波'],
  [10, 'A组：不同的组同时在场，各自分波独立'],
  [11, 'A组第一波：不同的组同时在场，各自分波独立'],
  [12, 'A组第二波：不同的组同时在场，各自分波独立'],
  [13, 'A组第三波：不同的组同时在场，各自分波独立'],
  [20, 'B组：不同的组同时在场，各自分波独立'],
  [21, 'B组第一波：不同的组同时在场，各自分波独立'],
  [22, 'B组第二波：不同的组同时在场，各自分波独立'],
  [23, 'B组第三波：不同的组同时在场，各自分波独立'],
  [30, 'C组：不同的组同时在场，各自分波独立'],
  [31, 'C组第一波：不同的组同时在场，各自分波独立'],
  [32, 'C组第二波：不同的组同时在场，各自分波独立'],
  [33, 'C组第三波：不同的组同时在场，各自分波独立'],
  [40, 'D组：不同的组同时在场，各自分波独立'],
  [41, 'D组第一波：不同的组同时在场，各自分波独立'],
  [42, 'D组第二波：不同的组同时在场，各自分波独立'],
  [43, 'D组第三波：不同的组同时在场，各自分波独立'],
  [99, '压制：增援怪物'],
  [999, '附加：增援怪物'],
]);

export class TowerMetadataService {
  private static schedules: Map<number, TowerScheduleRow> | undefined = undefined;
  private static floorsBySchedule: Map<number, TowerFloorRow[]> | undefined = undefined;
  private static levelsByGroup: Map<number, TowerLevelRow[]> | undefined = undefined;
  private static monsterMap: Map<number, MonsterMetaRow> | undefined = undefined;
  private static loading: Promise<void> | undefined = undefined;

  /** 预加载（幂等；页面 load 前调用一次，之后同步方法可用） */
  static preload(): Promise<void> {
    if (TowerMetadataService.loading === undefined) {
      TowerMetadataService.loading = TowerMetadataService.loadAll().catch((e: Error) => {
        Logger.warn(TAG, `preload fail: ${e.message}`);
        TowerMetadataService.loading = undefined;
      });
    }
    return TowerMetadataService.loading;
  }

  private static async loadAll(): Promise<void> {
    const rm = AppContextProvider.getResourceManager();
    const read = async (file: string): Promise<string> => {
      // Promise.resolve 包一层：兼容 SDK 中该 API 的同步/异步重载（CI lint await-thenable）
      const bytes = await Promise.resolve(rm.getRawFileContent(`metadata/${file}`));
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    };
    const schedules: TowerScheduleRow[] = JSON.parse(await read('TowerSchedule.json')) as TowerScheduleRow[];
    const floors: TowerFloorRow[] = JSON.parse(await read('TowerFloor.json')) as TowerFloorRow[];
    const levels: TowerLevelRow[] = JSON.parse(await read('TowerLevel.json')) as TowerLevelRow[];
    const monsters: MonsterMetaRow[] = JSON.parse(await read('monster_meta.json')) as MonsterMetaRow[];

    TowerMetadataService.schedules = new Map();
    for (const sc of schedules) {
      TowerMetadataService.schedules.set(sc.Id, sc);
    }
    TowerMetadataService.floorsBySchedule = new Map();
    for (const fl of floors) {
      for (const sc of schedules) {
        if (sc.FloorIds.indexOf(fl.Id) >= 0) {
          let list: TowerFloorRow[] | undefined = TowerMetadataService.floorsBySchedule.get(sc.Id);
          if (list === undefined) {
            list = [];
            TowerMetadataService.floorsBySchedule.set(sc.Id, list);
          }
          list.push(fl);
        }
      }
    }
    TowerMetadataService.levelsByGroup = new Map();
    for (const lv of levels) {
      let list: TowerLevelRow[] | undefined = TowerMetadataService.levelsByGroup.get(lv.GroupId);
      if (list === undefined) {
        list = [];
        TowerMetadataService.levelsByGroup.set(lv.GroupId, list);
      }
      list.push(lv);
    }
    TowerMetadataService.monsterMap = new Map();
    for (const mo of monsters) {
      if (mo.describeId > 0 && !TowerMetadataService.monsterMap.has(mo.describeId)) {
        TowerMetadataService.monsterMap.set(mo.describeId, mo);
      }
    }
    Logger.info(TAG, `tower meta loaded: schedules=${schedules.length} floors=${floors.length} levels=${levels.length}`);
  }

  /** 渊月祝福（scheduleId → BuffName/Descriptions[0]） */
  static buffOf(scheduleId: number): TowerBuff {
    const out: TowerBuff = new TowerBuff();
    const sc: TowerScheduleRow | undefined = TowerMetadataService.schedules?.get(scheduleId);
    if (sc !== undefined) {
      out.name = sc.BuffName;
      out.description = sc.Descriptions.length > 0 ? sc.Descriptions[0] : '';
    }
    return out;
  }

  /** 某期某层某间的敌人波次（无元数据返回空集合） */
  static wavesOf(scheduleId: number, floorIndex: number, chamberIndex: number): ChamberWaves {
    const out: ChamberWaves = new ChamberWaves();
    if (TowerMetadataService.schedules === undefined || TowerMetadataService.floorsBySchedule === undefined
      || TowerMetadataService.levelsByGroup === undefined || TowerMetadataService.monsterMap === undefined) {
      return out;
    }
    const sc: TowerScheduleRow | undefined = TowerMetadataService.schedules.get(scheduleId);
    if (sc === undefined) {
      return out;
    }
    let targetFloor: TowerFloorRow | undefined = undefined;
    for (const fl of TowerMetadataService.floorsBySchedule.get(scheduleId) ?? []) {
      if (fl.Index === floorIndex) {
        targetFloor = fl;
        break;
      }
    }
    if (targetFloor === undefined) {
      return out;
    }
    const lvList: TowerLevelRow[] | undefined = TowerMetadataService.levelsByGroup.get(targetFloor.LevelGroupId);
    if (lvList === undefined) {
      return out;
    }
    let targetLevel: TowerLevelRow | undefined = undefined;
    for (const lv of lvList) {
      if (lv.Index === chamberIndex) {
        targetLevel = lv;
        break;
      }
    }
    if (targetLevel === undefined) {
      return out;
    }
    out.monsterLevel = targetLevel.MonsterLevel;
    out.upper = TowerMetadataService.toWaveViews(targetLevel.FirstWaves, targetLevel.MonsterLevel);
    out.lower = TowerMetadataService.toWaveViews(targetLevel.SecondWaves, targetLevel.MonsterLevel);
    return out;
  }

  private static toWaveViews(waves: TowerWaveRow[], monsterLevel: number): TowerWaveView[] {
    const out: TowerWaveView[] = [];
    for (const w of waves) {
      const view: TowerWaveView = new TowerWaveView();
      view.label = WAVE_LABELS.get(w.Type) ?? '本间怪物';
      view.monsterLevel = monsterLevel;
      // 去重保序（同类怪物合并数量）
      const merged: TowerMonsterView[] = [];
      for (const mo of w.Monsters) {
        const normId: number = NORMALIZE.has(mo.Id) ? (NORMALIZE.get(mo.Id) as number) : mo.Id;
        const meta: MonsterMetaRow | undefined = TowerMetadataService.monsterMap?.get(normId);
        let dup: TowerMonsterView | undefined = undefined;
        for (const mv of merged) {
          if (mv.name === (meta !== undefined ? meta.name : `怪物${normId}`)) {
            dup = mv;
            break;
          }
        }
        if (dup !== undefined) {
          dup.count += mo.Count;
        } else {
          const mv: TowerMonsterView = new TowerMonsterView();
          mv.name = meta !== undefined ? meta.name : `未知魔物 ${normId}`;
          mv.icon = meta !== undefined ? meta.icon : '';
          mv.count = mo.Count;
          merged.push(mv);
        }
      }
      view.monsters = merged;
      out.push(view);
    }
    return out;
  }
}
