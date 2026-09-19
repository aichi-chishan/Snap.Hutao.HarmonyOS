/**
 * SkillLevelService.ets
 * 角色技能等级对齐：character/detail 的 skills 数组只有 skill_id/skill_type/level（无名称/图标），
 * 本地元数据（avatar_meta.json）技能无 id（仅 n/d/i/k），无法按 id 匹配 —— 只能按接口顺序对齐：
 * skill_type=1（战斗天赋）在数组中依序为 [普攻, 元素战技, 元素爆发]，与元数据 k=A/E/Q 条目依序对应
 * （对齐 Windows SummaryAvatarFactory 以技能 id 关联的呈现结果：仅显示 A/E/Q 三项等级）。
 * 数量不一致（特殊角色/数据异常）时宁可缺省也不错配：返回全 0。
 */
import { AvatarSkill } from '../model/CharacterData';
import { MetaSkill } from './WikiMetaService';

export class SkillLevelService {
  /**
   * API 技能等级 → 元数据技能对齐。
   * @param metaSkills 元数据技能/天赋列表（WikiMetaService.skillsOfAvatar，含 A/E/X/Q/P… 项）
   * @param apiSkills  detail 接口 skills 数组
   * @returns 与 metaSkills 等长的等级数组：战斗天赋位为对应等级，其余/未对齐为 0（0 表示无数据，UI 不显示）
   */
  static matchLevels(metaSkills: MetaSkill[], apiSkills: AvatarSkill[]): number[] {
    const out: number[] = [];
    for (let i = 0; i < metaSkills.length; i++) {
      out.push(0);
    }
    // 元数据侧 A/E/Q 位置（跳过 X 替换冲刺等非等级化技能）
    const aeqIdx: number[] = [];
    for (let i = 0; i < metaSkills.length; i++) {
      const k: string = metaSkills[i].k;
      if (k === 'A' || k === 'E' || k === 'Q') {
        aeqIdx.push(i);
      }
    }
    if (aeqIdx.length === 0) {
      return out;
    }
    // API 侧战斗天赋（保持接口顺序：普攻→战技→爆发）
    const fight: AvatarSkill[] = [];
    for (const s of apiSkills) {
      if (s.skillType === 1) {
        fight.push(s);
      }
    }
    // 数量不齐视为不可靠映射（如 API 返回替换冲刺等额外战斗技能），宁可缺省
    if (fight.length !== aeqIdx.length) {
      return out;
    }
    for (let i = 0; i < fight.length; i++) {
      out[aeqIdx[i]] = fight[i].level;
    }
    return out;
  }

  /** 导出文本技能段：仅取已对齐的战斗天赋等级（对齐 Windows FormatSkills：Lv. 6, Lv. 9, Lv. 11） */
  static formatLevels(levels: number[]): string {
    const parts: string[] = [];
    for (const lv of levels) {
      if (lv > 0) {
        parts.push(`Lv.${lv}`);
      }
    }
    return parts.join(', ');
  }
}
