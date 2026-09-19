/**
 * CharacterExportService.ets
 * 我的角色导出文本：按 Windows AvatarViewTextTemplating 默认模板的信息结构固定拼装
 * （Windows 原版即固定 C# 字符串插值，非 Scriban 模板引擎；鸿蒙版等价固定拼装，不引模板引擎），
 * 供剪贴板复制（对齐 Windows AvatarPropertyPage「导出文本到剪贴板 → 导出当前角色」）。
 * 与 Windows 的字段差异（详情模型无对应数据，相应内容省略）：
 *  - 技能等级列表（Windows FormatSkills）：character/detail 的 skills 数组（skill_id/skill_type/level）
 *    无名称/图标，本地元数据技能无 id，按接口顺序（普攻→战技→爆发）对齐元数据 A/E/Q 条目展示，
 *    数量不齐或缺数据时省略；未含命座 C3/C5 的 +3 加成（Windows LevelFormat 附加段）
 *  - 武器主/副词条：CharacterDetail 无武器词条字段
 *  - 圣遗物套装名（SetName）：以圣遗物名代替；评分复用 ReliquaryScore（推荐词条加权/双爆兜底）
 *  - 首行补充好感度（任务要求）
 */
import { CharacterDetail, Reliquary } from '../model/CharacterData';
import { WikiMetaService } from './WikiMetaService';
import { SkillLevelService } from './SkillLevelService';
import { ReliquaryScore } from '../common/ReliquaryScore';

export class CharacterExportService {
  /**
   * 生成角色导出文本。
   * propLabelFn：属性类型（FIGHT_PROP_*）→ 中文名，复用页面 CharacterPage.propLabel 避免映射重复。
   */
  static buildExportText(d: CharacterDetail, propLabelFn: (type: string) => string): string {
    const lines: string[] = [];
    lines.push('// =====================');
    // Windows: // {Name} [{Level}, ☆{Quality}, C{已激活命座数}] [{技能等级, ...}]
    let head: string = `// ${d.name} [Lv.${d.level}, ☆${d.rarity}, C${d.activedConstellationNum}, 好感${d.fetter}]`;
    const skillText: string = SkillLevelService.formatLevels(
      SkillLevelService.matchLevels(WikiMetaService.skillsOfAvatar(d.name), d.skills));
    if (skillText.length > 0) {
      head += ` [${skillText}]`;
    }
    lines.push(head);
    if (d.weapon.id > 0) {
      lines.push('');
      lines.push('// ---------------------');
      // Windows: // {武器名} [{Level}, ☆{Quality}, ❖{精炼阶数}]（+第二行武器主/副词条，此处无词条数据省略）
      lines.push(`// ${WikiMetaService.nameOfWeapon(d.weapon.id)} [Lv.${d.weapon.level}, ☆${d.weapon.rarity}, ❖${d.weapon.affixLevel}]`);
    }
    if (d.selectedProperties.length > 0) {
      lines.push('');
      lines.push('// ---------------------');
      // Windows: // [属性名: 值 + 强化值]（逐行）
      for (const p of d.selectedProperties) {
        const value: string = p.final.length > 0 ? p.final : `${p.base}+${p.add}`;
        lines.push(`// [${propLabelFn(p.propertyType)}: ${value}]`);
      }
    }
    if (d.reliquaries.length > 0) {
      lines.push('');
      lines.push('// ---------------------');
      // Windows: // {部位emoji} {主词条名}: {值} [☆{品质} {等级} {套装名}] 评分: {分数}（+空行）
      //           // [副词条: 值 ❶][...]（❶ = '\u2775' + 强化次数）
      for (const r of d.reliquaries) {
        lines.push('');
        lines.push(`// ${CharacterExportService.posEmoji(r.pos)} ${propLabelFn(r.mainProperty.propertyType)}: ${r.mainProperty.value} [☆${r.rarity} +${r.level} ${r.name}] 评分: ${CharacterExportService.relicScore(r, d)}`);
        lines.push(`// ${CharacterExportService.formatSubProperties(r, propLabelFn)}`);
      }
    }
    lines.push('// =====================');
    return lines.join('\n');
  }

  /** 圣遗物部位 emoji（对齐 Windows ReliquaryEmoji：花/羽/沙/杯/冠） */
  private static posEmoji(pos: number): string {
    switch (pos) {
      case 1:
        return '🌷';
      case 2:
        return '🪶';
      case 3:
        return '⏳';
      case 4:
        return '🍷';
      case 5:
        return '👑';
      default:
        return '';
    }
  }

  /** 副词条串：[名称: +值 ❶]（Windows '\u2775' + 强化次数；次数 0 时不附加） */
  private static formatSubProperties(r: Reliquary, propLabelFn: (type: string) => string): string {
    let s: string = '';
    for (const sp of r.subProperties) {
      let enh: string = '';
      if (sp.times > 0) {
        enh = ` ${String.fromCharCode(0x2775 + sp.times)}`;
      }
      s += `[${propLabelFn(sp.propertyType)}: +${sp.value}${enh}]`;
    }
    return s;
  }

  /** 圣遗物评分（对齐页面 CharacterPage.relicScore：推荐词条加权，无推荐回退双爆分） */
  private static relicScore(r: Reliquary, d: CharacterDetail): number {
    if (d.recommend.subProperties.length > 0) {
      const effective: boolean = ReliquaryScore.isCritEffective(d.id);
      const full: number = ReliquaryScore.calculate(r.subProperties, d.recommend.subProperties,
        d.recommend.energyType, effective);
      if (full > 0) {
        return Math.round(full * 10) / 10;
      }
    }
    return ReliquaryScore.doubleCritScore(r, ReliquaryScore.isCritEffective(d.id));
  }
}
