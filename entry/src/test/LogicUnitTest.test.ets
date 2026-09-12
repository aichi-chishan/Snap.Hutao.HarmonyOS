import { describe, it, expect } from '@ohos/hypium';
import { ReliquaryScore } from '../main/ets/common/ReliquaryScore';
import { RelicProperty, Reliquary } from '../main/ets/model/CharacterData';
import { GachaType } from '../main/ets/model/GachaType';
import { WikiMetaService } from '../main/ets/service/WikiMetaService';
import { DateUtil } from '../main/ets/common/DateUtil';

const EPS: number = 0.001;

function prop(type: string, value: string): RelicProperty {
  const p: RelicProperty = new RelicProperty();
  p.propertyType = type;
  p.value = value;
  return p;
}

export default function logicUnitTest() {
  describe('reliquaryScoreTest', () => {
    it('doubleCritForcedEffective', 0, () => {
      // 非心海：双爆强制有效（即使推荐列表缺双爆），平面攻击不推荐不计分
      const subs: RelicProperty[] = [
        prop('FIGHT_PROP_CRITICAL', '10.5%'),
        prop('FIGHT_PROP_CRITICAL_HURT', '20%'),
        prop('FIGHT_PROP_ATTACK', '10'),
        prop('FIGHT_PROP_ATTACK_PERCENT', '10%'),
      ];
      const total: number = ReliquaryScore.calculate(subs,
        ['FIGHT_PROP_CRITICAL', 'FIGHT_PROP_CRITICAL_HURT'], 'SPECIAL_ENERGY_NONE', true);
      expect(Math.abs(total - 41.0) < EPS).assertTrue();
    });
    it('kokomiCritInactive', 0, () => {
      // 心海：双爆无效（推荐列表无双爆时权重 0），推荐的生命百分比正常计分
      const subs: RelicProperty[] = [
        prop('FIGHT_PROP_CRITICAL', '10.5%'),
        prop('FIGHT_PROP_HP_PERCENT', '10%'),
      ];
      const total: number = ReliquaryScore.calculate(subs,
        ['FIGHT_PROP_HP_PERCENT'], 'SPECIAL_ENERGY_NONE', false);
      expect(Math.abs(total - 13.3) < EPS).assertTrue();
    });
    it('critActiveForFlagTrue', 0, () => {
      // 同上条目，非心海 → 暴击率强制有效
      const subs: RelicProperty[] = [
        prop('FIGHT_PROP_CRITICAL', '10.5%'),
        prop('FIGHT_PROP_HP_PERCENT', '10%'),
      ];
      const total: number = ReliquaryScore.calculate(subs,
        ['FIGHT_PROP_HP_PERCENT'], 'SPECIAL_ENERGY_NONE', true);
      expect(Math.abs(total - 34.3) < EPS).assertTrue();
    });
    it('chargeEfficiencySpecialCase', 0, () => {
      // 充能非推荐：非充能角色（hasCritHurt=true）→ 权重 0；充能角色（hasCritHurt=false）→ 1.0
      const ce: RelicProperty[] = [prop('FIGHT_PROP_CHARGE_EFFICIENCY', '10%')];
      const withCrit: number = ReliquaryScore.calculate(ce,
        ['FIGHT_PROP_HP_PERCENT'], 'SPECIAL_ENERGY_FIRE', true);
      expect(withCrit === 0).assertTrue();
      const noCrit: number = ReliquaryScore.calculate(ce,
        ['FIGHT_PROP_HP_PERCENT'], 'SPECIAL_ENERGY_FIRE', false);
      expect(Math.abs(noCrit - 10 * 1.1979) < EPS).assertTrue();
    });
    it('doubleCritScore', 0, () => {
      // 心海双爆分恒 0；普通角色 = 暴击×2 + 爆伤，四舍五入到 1 位
      const r: Reliquary = new Reliquary();
      const c1: RelicProperty = prop('FIGHT_PROP_CRITICAL', '5.5%');
      const c2: RelicProperty = prop('FIGHT_PROP_CRITICAL_HURT', '10%');
      r.subProperties.push(c1);
      r.subProperties.push(c2);
      expect(Math.abs(ReliquaryScore.doubleCritScore(r, true) - 21.0) < EPS).assertTrue();
      expect(ReliquaryScore.doubleCritScore(r, false) === 0).assertTrue();
    });
    it('isCritEffectiveOnlyKokomi', 0, () => {
      // Windows AvatarIds.IsCritEffective：仅心海（10000002）双爆无效
      expect(ReliquaryScore.isCritEffective(10000002) === false).assertTrue();
      expect(ReliquaryScore.isCritEffective(10000042) === true).assertTrue();
    });
  });

  describe('gachaTypeTest', () => {
    it('nameMapping', 0, () => {
      expect(GachaType.nameOf(GachaType.NOVICE) === '新手祈愿').assertTrue();
      expect(GachaType.nameOf(GachaType.AVATAR_EVENT) === '角色活动祈愿').assertTrue();
      expect(GachaType.nameOf(GachaType.CHRONICLE) === '集录祈愿').assertTrue();
      expect(GachaType.nameOf(GachaType.UGC_STANDARD) === '常驻颂愿').assertTrue();
      expect(GachaType.nameOf(GachaType.UGC_AVATAR_EVENT) === '活动颂愿').assertTrue();
      expect(GachaType.nameOf(999).startsWith('卡池')).assertTrue();
    });
    it('standardBeyondMatrix', 0, () => {
      expect(GachaType.isStandard(GachaType.CHRONICLE)).assertTrue();
      expect(GachaType.isStandard(400)).assertFalse();
      expect(GachaType.isBeyond(GachaType.UGC_STANDARD)).assertTrue();
      expect(GachaType.isBeyond(GachaType.UGC_AVATAR_EVENT)).assertTrue();
      expect(GachaType.isBeyond(301)).assertFalse();
      expect(GachaType.isValid(400)).assertFalse();
      expect(GachaType.isValid(4000)).assertFalse();
      expect(GachaType.isValid(GachaType.UGC_STANDARD)).assertTrue();
    });
    it('queryOrders', 0, () => {
      expect(GachaType.QUERY_ORDER.length === 5).assertTrue();
      expect(GachaType.QUERY_ORDER[4] === GachaType.CHRONICLE).assertTrue();
      expect(GachaType.BEYOND_ORDER.length === 2).assertTrue();
      expect(GachaType.BEYOND_ORDER[0] === GachaType.UGC_STANDARD).assertTrue();
    });
  });

  describe('cleanTextTest', () => {
    it('stripColorTags', 0, () => {
      expect(WikiMetaService.cleanText('<color=#FF0000>火</color>') === '火').assertTrue();
    });
    it('stripLinkMarkers', 0, () => {
      expect(WikiMetaService.cleanText('A{LINK#123}B{/LINK}C') === 'ABC').assertTrue();
      expect(WikiMetaService.cleanText('A(/LINK)B') === 'AB').assertTrue();
    });
    it('stripTimezoneAndCompress', 0, () => {
      const out: string = WikiMetaService.cleanText('行一{TIMEZONE}\n\n\n\n行二');
      expect(out === '行一\n\n行二').assertTrue();
    });
    it('emptyPassthrough', 0, () => {
      expect(WikiMetaService.cleanText('') === '').assertTrue();
    });
  });

  describe('dateUtilTest', () => {
    it('pad2', 0, () => {
      expect(DateUtil.pad2(5) === '05').assertTrue();
      expect(DateUtil.pad2(12) === '12').assertTrue();
    });
    it('formatDateZero', 0, () => {
      expect(DateUtil.formatDate(0) === '--').assertTrue();
    });
    it('formatMonthDayLocal', 0, () => {
      // 格式 'MM-dd HH:mm'（本地时区构造，时分置零避免歧义）
      const ms: number = new Date(2024, 0, 2, 0, 0).getTime();
      expect(DateUtil.formatMonthDay(ms) === '01-02 00:00').assertTrue();
    });
    it('parseToMsDigitStrings', 0, () => {
      // 秒（10 位）→ 毫秒；毫秒（13 位）原样；非法 → 0
      expect(DateUtil.parseToMs('1700000000') === 1700000000000).assertTrue();
      expect(DateUtil.parseToMs('1700000000000') === 1700000000000).assertTrue();
      expect(DateUtil.parseToMs('') === 0).assertTrue();
      expect(DateUtil.parseToMs('abc') === 0).assertTrue();
    });
  });
}
