/** Character text export shares exact identity/base+extra semantics with the character page. */
import { CharacterDetail, Reliquary } from '../model/CharacterData';
import { WikiMetaService } from './WikiMetaService';
import { SkillLevelService } from './SkillLevelService';
import { ReliquaryScore } from '../common/ReliquaryScore';
import { PromoteState } from '../model/PromoteState';

export class CharacterExportService {
  /**
   * 生成角色导出文本。
   * propLabelFn：属性类型（FIGHT_PROP_*）→ 中文名，复用页面 CharacterPage.propLabel 避免映射重复。
   */
  static buildExportText(d: CharacterDetail, propLabelFn: (type: string) => string): string {
    const lines: string[] = [];
    lines.push('// =====================');
    // Windows: // {Name} [{Level}, ☆{Quality}, C{已激活命座数}] [{技能等级, ...}]
    let head: string = `// ${d.name} [Lv.${d.level}, ☆${d.rarity}, C${d.activedConstellationNum >= 0 ? d.activedConstellationNum : '?'}, 好感${d.fetter}]`;
    const skillText: string = SkillLevelService.formatDetail(d);
    if (skillText.length > 0) {
      head += ` [${skillText}]`;
    }
    lines.push(head);
    if (d.weapon.id > 0) {
      lines.push('');
      lines.push('// ---------------------');
      // Weapon properties are exported only when supplied; unknown promotion is explicit.
      lines.push(`// ${d.weapon.name || WikiMetaService.nameOfWeapon(d.weapon.id)} [Lv.${d.weapon.level}, ☆${d.weapon.rarity}, ❖${d.weapon.affixLevel}, ${PromoteState.label(d.weapon.promoteLevel)}]`);
      for (const property of [d.weapon.mainProperty, d.weapon.subProperty]) {
        if (property.propertyType.length > 0) {
          lines.push(`// [${propLabelFn(property.propertyType)}: ${property.value}]`);
        }
      }
    }
    if (d.weapon.id <= 0) {
      lines.push(`// 武器：${d.weapon.equipmentState === 'unequipped' ? '未装备' : '装备信息未知'}`);
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
        lines.push(`// ${CharacterExportService.posEmoji(r.pos)} ${propLabelFn(r.mainProperty.propertyType)}: ${r.mainProperty.value} [☆${r.rarity} +${r.level} ${r.setName || r.name}] 评分: ${CharacterExportService.relicScore(r, d)}`);
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
    return Math.round(ReliquaryScore.calculate(r.subProperties, d.recommend.subProperties,
      d.recommend.energyType, ReliquaryScore.isCritEffective(d.id)) * 10) / 10;
  }
}
