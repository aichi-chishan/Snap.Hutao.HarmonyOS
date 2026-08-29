/**
 * CharacterPage.ets（@Entry）
 * 我的角色：角色列表 + 选中角色详情（武器/圣遗物/面板属性）。
 * 宽屏：左列表 + 右详情；窄屏：列表 + 详情顺序展示。
 */
import { router, display } from '@kit.ArkUI';
import { CharacterViewModel } from '../viewmodel/CharacterViewModel';
import { CharacterListItem, CharacterDetail, Reliquary, RelicProperty, BaseProperty, Constellation, avatarIconUrl } from '../model/CharacterData';
import { ReliquaryScore } from '../common/ReliquaryScore';
import { RiskUiHelper, RiskVerifyParams } from '../common/RiskUiHelper';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { NavIcon } from '../components/NavIcon';
import { AssetIcon } from '../components/AssetIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { MetaIcon } from '../components/MetaIcon';
import { WikiMetaService } from '../service/WikiMetaService';
import { Logger } from '../common/Logger';

const TAG: string = 'CharacterPage';

@Entry
@Component
export struct CharacterPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: CharacterViewModel = new CharacterViewModel();
  @State isWide: boolean = false;
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;
  /** 当前选中角色详情（页面 @State 驱动刷新；VM 内 @Observed 深属性不触发刷新） */
  @State currentDetail: CharacterDetail | undefined = undefined;
  /** 当前选中角色 id（页面态） */
  @State selectedId: number = 0;

  aboutToAppear(): void {
    this.isWide = CharacterPage.detectWide();
    // id→图标映射就绪后再加载（列表头像需要）
    WikiMetaService.ensureIconMaps().then(() => {
      this.reload();
    }).catch(() => {
      this.reload();
    });
  }

  /** 页面显示：检测风控 → 自动弹验证窗（保持当前页上下文） */
  onPageShow(): void {
    if (this.vm.needRiskVerify && !this.showVerify) {
      this.showVerify = true;
      return;
    }
    if (RiskUiHelper.hasPendingChallenge()) {
      // 用户刚完成验证：重放重载
      this.vm.resetRiskAndReload(this.currentUid);
    }
  }

  /** VM 加载完成后回填页面详情（@Observed 不深跟踪，页面显式同步） */
  syncDetail(): void {
    this.selectedId = this.vm.selectedId;
    this.currentDetail = this.vm.detailOfSelected();
    Logger.info(TAG, `syncDetail id=${this.selectedId} detail=${this.currentDetail?.name ?? 'undefined'}`);
  }

  /** 选择角色：VM 切换 + 页面回填（守卫过期竞态结果，点击 id 与选中态不一致时丢弃） */
  selectCharacter(id: number): void {
    Logger.info(TAG, `selectCharacter id=${id}`);
    this.selectedId = id;
    this.vm.select(this.currentUid, id).then(() => {
      Logger.info(TAG, `selectCharacter done id=${id} pageSel=${this.selectedId} vmSel=${this.vm.selectedId}`);
      if (this.selectedId !== id) {
        return;
      }
      this.syncDetail();
    }).catch((e: Error) => {
      Logger.warn(TAG, `selectCharacter fail id=${id}: ${e.message}`);
    });
  }

  private static detectWide(): boolean {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const widthVp: number = d.densityPixels > 0 ? d.width / d.densityPixels : d.width;
      return widthVp >= 720;
    } catch (e) {
      return false;
    }
  }

  reload(): void {
    this.vm.load(this.currentUid).then(() => {
      this.syncDetail();
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
  }

  @Builder
  header() {
    PageHeader({ title: '我的角色', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
      Button('刷新')
        .fontSize(12)
        .height(28)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.reload();
        })
    }
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'AvatarProperty', iconSize: 60 })
      Text('需登录后查看角色')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Button('去登录')
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  @Builder
  characterRow(c: CharacterListItem) {
    Row({ space: 10 }) {
      // rawfile 图标按角色 id 从本地元数据映射（WikiMetaService.iconOfAvatar），未命中回退 Enka
      if (WikiMetaService.iconOfAvatar(c.id).length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(c.id), iconSize: 44 })
      } else if (c.icon.length > 0) {
        // 本地元数据图标名（UI_AvatarIcon_xxx）或 http 直图；统一走 MetaIcon（rawfile→CDN 兜底）
        MetaIcon({ category: 'AvatarIcon', name: c.icon, iconSize: 44, remoteFallback: false })
      } else {
        MetaIcon({ category: 'AvatarIcon', name: '', iconSize: 44 })
      }
      Column({ space: 2 }) {
        Row({ space: 5 }) {
          Text(c.name)
            .fontSize(15)
            .fontWeight(this.selectedId === c.id ? FontWeight.Medium : FontWeight.Normal)
            .fontColor($r('app.color.text_primary'))
          if (AssetIcon.elemName(c.element).length > 0) {
            AssetIcon({ name: AssetIcon.elemName(c.element), iconSize: 12 })
          }
        }
        Text(`Lv.${c.level} ★${c.rarity}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.selectedId === c.id) {
        Text('▣')
          .fontSize(12)
          .fontColor($r('app.color.app_primary'))
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(this.selectedId === c.id ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
    .onClick(() => {
      this.selectCharacter(c.id);
    })
  }

  @Builder
  detailPanel() {
    Column({ space: 10 }) {
      if (this.currentDetail !== undefined) {
        this.detailHeader()
        if (this.currentDetail.weapon.id > 0) {
          Row({ space: 10 }) {
            NavIcon({ name: 'AvatarProperty', iconSize: 22 })
            Text(`武器 Lv.${this.currentDetail.weapon.level} ★${this.currentDetail.weapon.rarity} · 精炼${this.currentDetail.weapon.affixLevel}`)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.divider') })
        }

        if (this.currentDetail.selectedProperties.length > 0) {
          Column({ space: 6 }) {
            Text('面板属性')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            ForEach(this.currentDetail.selectedProperties, (p: BaseProperty, i: number) => {
              Row({ space: 8 }) {
                Text(CharacterPage.propLabel(p.propertyType))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Text(p.final.length > 0 ? p.final : `${p.base}+${p.add}`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
              }
              .width('100%')
            }, (p: BaseProperty) => `${p.propertyType}_${p.final}`)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.divider') })
        }

        if (this.currentDetail.reliquaries.length > 0) {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text('圣遗物')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text('双爆分 = 暴击率×2 + 暴击伤害×1')
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            ForEach(this.currentDetail.reliquaries, (r: Reliquary, i: number) => {
              Column({ space: 5 }) {
                Row({ space: 8 }) {
                  Text(`${r.posName} · ${r.name}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                  Text(`★${r.rarity} +${r.level}`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  // 圣遗物评分徽章（Windows ReliquaryScoreCalculator：推荐词条加权；无推荐回退双爆分）
                  Text(`${CharacterPage.relicScore(r, this.currentDetail)} 分 · ${ReliquaryScore.grade(CharacterPage.relicScore(r, this.currentDetail))}`)
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.app_primary'))
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(9)
                    .backgroundColor($r('app.color.app_primary_bg'))
                }
                .width('100%')
                if (r.mainProperty.propertyType.length > 0) {
                  Row({ space: 6 }) {
                    Text(CharacterPage.propLabel(r.mainProperty.propertyType))
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                    Text(r.mainProperty.value)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                  }
                  .width('100%')
                }
                if (r.subProperties.length > 0) {
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(r.subProperties, (sp: RelicProperty, j: number) => {
                      Text(`${CharacterPage.propLabel(sp.propertyType)} +${sp.value}`)
                        .fontSize(10)
                        .fontColor(sp.propertyType === 'FIGHT_PROP_CRITICAL' || sp.propertyType === 'FIGHT_PROP_CRITICAL_HURT'
                          ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .margin({ right: 4, bottom: 4 })
                        .borderRadius(7)
                        .backgroundColor($r('app.color.page_background'))
                    }, (sp: RelicProperty) => `${r.id}_${sp.propertyType}_${sp.value}_${sp.times}`)
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .borderRadius(10)
              .backgroundColor($r('app.color.page_background'))
            }, (r: Reliquary) => `${r.id}_${r.pos}_${r.level}_${r.subProperties.length}`)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.divider') })
        }
        if (this.currentDetail.constellations.length > 0) {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text('命座')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(`已激活 ${this.currentDetail.activedConstellationNum}/${this.currentDetail.constellations.length}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            ForEach(this.currentDetail.constellations, (c: Constellation, ci: number) => {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(`第 ${c.pos} 层`)
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(c.isActived ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
                    .width(44)
                    .textAlign(TextAlign.Center)
                    .padding({ top: 3, bottom: 3 })
                    .borderRadius(7)
                    .backgroundColor(c.isActived ? $r('app.color.app_primary_bg') : $r('app.color.page_background'))
                  Text(c.name.length > 8 ? `${c.name.substring(0, 8)}…` : c.name)
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                }
                .width(44)
                Column({ space: 2 }) {
                  Text(c.name.length > 0 ? c.name : `星座 ${c.pos}`)
                    .fontSize(12)
                    .fontWeight(c.isActived ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(c.isActived ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(c.effect.length > 0 ? c.effect : '尚未解锁')
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }, (c: Constellation) => `con_${c.id}`)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.divider') })
        }
      }
    }
    .width('100%')
  }

  /** 详情头部卡（元素图标 + 头像 + 名称等级）——无参：直接读 @State currentDetail，传参会固定快照不刷新 */
  @Builder
  detailHeader() {
    Row({ space: 12 }) {
      if (this.currentDetail !== undefined) {
        if (WikiMetaService.iconOfAvatar(this.currentDetail.id).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(this.currentDetail.id), iconSize: 64 })
        } else if (this.currentDetail.icon.startsWith('http')) {
          Image(this.currentDetail.icon)
            .width(64)
            .height(64)
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.app_primary_bg'))
        } else if (this.currentDetail.icon.length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: this.currentDetail.icon, iconSize: 64 })
        } else {
          MetaIcon({ category: 'AvatarIcon', name: '', iconSize: 64 })
        }
        Column({ space: 3 }) {
          Text(this.currentDetail.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(`Lv.${this.currentDetail.level} · ★${this.currentDetail.rarity} · 好感 ${this.currentDetail.fetter} · 命座 ${this.currentDetail.activedConstellationNum}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }
  static relicScore(r: Reliquary, d: CharacterDetail): number {
    if (d.recommend.subProperties.length > 0) {
      const full: number = ReliquaryScore.calculate(r.subProperties, d.recommend.subProperties, d.recommend.energyType);
      if (full > 0) {
        return Math.round(full * 10) / 10;
      }
    }
    return ReliquaryScore.doubleCritScore(r);
  }

  /** 属性类型 → 中文标签（兼容：字符串 FIGHT_PROP_* 与数字 FightProperty 枚举） */
  static propLabel(type: string): string {
    switch (type) {
      case 'FIGHT_PROP_HP':
      case 'FIGHT_PROP_MAX_HP':
      case '2000': return '生命值上限';
      case 'FIGHT_PROP_ATTACK':
      case 'FIGHT_PROP_CUR_ATTACK':
      case '2001': return '攻击力';
      case 'FIGHT_PROP_DEFENSE':
      case 'FIGHT_PROP_CUR_DEFENSE':
      case '2002': return '防御力';
      case 'FIGHT_PROP_HP_PERCENT':
      case '3':
      case '3.0': return '生命值';
      case 'FIGHT_PROP_ATTACK_PERCENT':
      case '6':
      case '6.0': return '攻击力';
      case 'FIGHT_PROP_DEFENSE_PERCENT':
      case '9':
      case '9.0': return '防御力';
      case 'FIGHT_PROP_BASE_HP':
      case '1': return '基础生命值';
      case 'FIGHT_PROP_BASE_ATTACK':
      case '4': return '基础攻击力';
      case 'FIGHT_PROP_BASE_DEFENSE':
      case '7': return '基础防御力';
      case 'FIGHT_PROP_CRITICAL':
      case '20': return '暴击率';
      case 'FIGHT_PROP_CRITICAL_HURT':
      case '22': return '暴击伤害';
      case 'FIGHT_PROP_ELEMENT_MASTERY':
      case '28': return '元素精通';
      case 'FIGHT_PROP_CHARGE_EFFICIENCY':
      case '23': return '元素充能效率';
      case 'FIGHT_PROP_HEAL_ADD':
      case '26': return '治疗加成';
      case 'FIGHT_PROP_HEALED_ADD':
      case '27': return '受治疗加成';
      case 'FIGHT_PROP_FIRE_ADD_HURT':
      case '40': return '火元素伤害加成';
      case 'FIGHT_PROP_WATER_ADD_HURT':
      case '42': return '水元素伤害加成';
      case 'FIGHT_PROP_GRASS_ADD_HURT':
      case '43': return '草元素伤害加成';
      case 'FIGHT_PROP_ELEC_ADD_HURT':
      case '41': return '雷元素伤害加成';
      case 'FIGHT_PROP_ICE_ADD_HURT':
      case '46': return '冰元素伤害加成';
      case 'FIGHT_PROP_WIND_ADD_HURT':
      case '44': return '风元素伤害加成';
      case 'FIGHT_PROP_ROCK_ADD_HURT':
      case '45': return '岩元素伤害加成';
      case 'FIGHT_PROP_PHYSICAL_ADD_HURT':
      case '30': return '物理伤害加成';
      case 'FIGHT_PROP_FIRE_SUB_HURT':
      case '50': return '火元素抗性';
      case 'FIGHT_PROP_WATER_SUB_HURT':
      case '52': return '水元素抗性';
      case 'FIGHT_PROP_GRASS_SUB_HURT':
      case '53': return '草元素抗性';
      case 'FIGHT_PROP_ELEC_SUB_HURT':
      case '51': return '雷元素抗性';
      case 'FIGHT_PROP_ICE_SUB_HURT':
      case '56': return '冰元素抗性';
      case 'FIGHT_PROP_WIND_SUB_HURT':
      case '54': return '风元素抗性';
      case 'FIGHT_PROP_ROCK_SUB_HURT':
      case '55': return '岩元素抗性';
      case 'FIGHT_PROP_PHYSICAL_SUB_HURT':
      case '29': return '物理抗性';
      case 'FIGHT_PROP_SPEED_PERCENT':
      case '11': return '移动速度';
      case 'FIGHT_PROP_SKILL_CD_MINUS_RATIO':
      case '80': return '冷却缩减';
      case 'FIGHT_PROP_CUR_HP':
      case '1010': return '当前生命值';
      default: return type;
    }
  }

  build() {
    Column() {
      this.header()
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else {
        Row({ space: 12 }) {
          // 左侧角色列表
          Scroll() {
            Column({ space: 8 }) {
              if (this.vm.loading) {
                LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
                Text('加载中...').fontSize(13).fontColor($r('app.color.text_secondary'))
              } else if (this.vm.message.length > 0) {
                Text(this.vm.message).fontSize(13).fontColor($r('app.color.text_secondary'))
                Button('重试').fontSize(13).backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White).onClick(() => {
                    this.reload();
                  })
              } else if (this.vm.items.length === 0) {
                Text('暂无角色数据').fontSize(13).fontColor($r('app.color.text_secondary'))
              } else {
                ForEach(this.vm.items, (c: CharacterListItem) => {
                  this.characterRow(c)
                }, (c: CharacterListItem) => `${c.id}`)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 8, bottom: 16 })
          }
          .width(this.isWide ? 260 : '100%')
          .scrollBar(BarState.Off)

          // 右侧详情（宽屏显示；窄屏也顺序显示）
          if (this.isWide) {
            Scroll() {
              Column({ space: 10 }) {
                if (this.vm.loadingDetail) {
                  Text('加载详情中...').fontSize(13).fontColor($r('app.color.text_secondary'))
                } else if (this.currentDetail !== undefined) {
                  this.detailPanel()
                } else {
                  Text('点击角色查看详情').fontSize(13).fontColor($r('app.color.text_secondary'))
                }
              }
              .width('100%')
              .padding({ left: 8, right: 16, bottom: 16 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          } else {
            // 窄屏详情在列表下方顺序展示
            Scroll() {
              Column({ space: 10 }) {
                if (this.vm.loadingDetail) {
                  Text('加载详情中...').fontSize(13).fontColor($r('app.color.text_secondary'))
                } else if (this.currentDetail !== undefined) {
                  this.detailPanel()
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 16 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
    .bindSheet(this.showVerify, () => {
      RiskVerifyDialog({
        isShow: this.showVerify,
        gt: this.vm.riskGt,
        challenge: this.vm.riskChallenge,
        path: this.vm.riskPath,
        onDone: (challenge: string) => {
          // 验证完成：写入待重放 challenge 并触发重放
          AppStorage.setOrCreate<string>(RiskUiHelper.KEY_PENDING, challenge);
          this.vm.resetRiskAndReload(this.currentUid);
        },
      })
    }, { height: 420, backgroundColor: $r('app.color.page_background'), showClose: false, blurStyle: BlurStyle.Regular })
  }
}
