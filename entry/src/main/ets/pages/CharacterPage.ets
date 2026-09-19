/**
 * CharacterPage.ets（@Entry）
 * 我的角色：角色列表 + 选中角色详情（武器/圣遗物/面板属性）。
 * 宽屏：左列表 + 右详情；窄屏：列表 + 详情顺序展示。
 */
import { router, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { CharacterViewModel, AddPlanResult } from '../viewmodel/CharacterViewModel';
import { CharacterListItem, CharacterDetail, Reliquary, RelicProperty, BaseProperty, Constellation, avatarIconUrl } from '../model/CharacterData';
import { ReliquaryScore } from '../common/ReliquaryScore';
import { RiskUiHelper, RiskVerifyParams } from '../common/RiskUiHelper';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { NavIcon } from '../components/NavIcon';
import { AssetIcon } from '../components/AssetIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { MetaIcon } from '../components/MetaIcon';
import { WikiMetaService, MetaSkill } from '../service/WikiMetaService';
import { CharacterExportService } from '../service/CharacterExportService';
import { CultivationRepo, CultivateProject } from '../data/repo/CultivationRepo';
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
  /** 角色列表搜索关键字（名称包含，对齐 Windows AutoSuggestTokenBox 的名称过滤） */
  @State charKeyword: string = '';
  /** 角色列表排序：0=默认 1=等级 2=稀有度 3=好感（对齐 Windows AvatarPropertySortDescriptions） */
  @State charSort: number = 0;
  /** 元素筛选（空=全部；取 API 原始元素名 Pyro/Hydro/...） */
  @State charElement: string = '';
  /** 养成计划选择半窗（多项目时让用户选，对齐 Windows 当前养成计划口径） */
  @State showPlanSheet: boolean = false;
  /** 待选养成计划列表（bindSheet 数据源） */
  @State pendingProjects: CultivateProject[] = [];
  /** 待加入计划的角色详情快照（选项目期间固定） */
  @State pendingDetail: CharacterDetail | undefined = undefined;
  /** 加入计划进行中（防重复点击） */
  @State addingPlan: boolean = false;

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

  /** 列表过滤+排序（对齐 Windows AvatarPropertyViewModel 排序/筛选：默认/等级/稀有度/好感） */
  private filteredItems(): CharacterListItem[] {
    const kw: string = this.charKeyword.trim();
    const out: CharacterListItem[] = [];
    for (const c of this.vm.items) {
      if (kw.length > 0 && !c.name.includes(kw)) {
        continue;
      }
      if (this.charElement.length > 0 && c.element !== this.charElement) {
        continue;
      }
      out.push(c);
    }
    if (this.charSort === 1) {
      out.sort((a: CharacterListItem, b: CharacterListItem) => b.level - a.level);
    } else if (this.charSort === 2) {
      out.sort((a: CharacterListItem, b: CharacterListItem) =>
        b.rarity - a.rarity || b.level - a.level);
    } else if (this.charSort === 3) {
      out.sort((a: CharacterListItem, b: CharacterListItem) => b.fetter - a.fetter);
    }
    return out;
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
  }

  /** 列表筛选栏：搜索 + 排序 + 元素 chips（对齐 Windows 角色页筛选/排序） */
  @Builder
  charFilterBar() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        TextInput({ placeholder: '搜索角色' })
          .fontSize(12)
          .height(30)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.charKeyword = v;
          })
        Text(this.charSortLabel())
          .fontSize(11)
          .fontColor($r('app.color.app_primary'))
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .borderRadius(8)
          .backgroundColor($r('app.color.app_primary_bg'))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            // 循环切换排序：默认→等级→稀有度→好感
            this.charSort = (this.charSort + 1) % 4;
          })
      }
      .width('100%')
      Scroll() {
        Row({ space: 4 }) {
          this.elementChip('', '全部')
          this.elementChip('Pyro', '火')
          this.elementChip('Hydro', '水')
          this.elementChip('Electro', '雷')
          this.elementChip('Dendro', '草')
          this.elementChip('Cryo', '冰')
          this.elementChip('Anemo', '风')
          this.elementChip('Geo', '岩')
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
  }

  /** 当前排序模式名 */
  private charSortLabel(): string {
    switch (this.charSort) {
      case 1:
        return '等级↓';
      case 2:
        return '稀有度↓';
      case 3:
        return '好感↓';
      default:
        return '默认序';
    }
  }

  /** 元素筛选 chip */
  @Builder
  elementChip(element: string, label: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.charElement === element ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(this.charElement === element ? $r('app.color.app_primary') : $r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.charElement = element;
      })
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
    Stack({ alignContent: Alignment.TopStart }) {
      // 角色专属背景：名片大图（NameCardPic，已打包 rawfile；名下无名片时不显示）
      if (this.currentDetail !== undefined && WikiMetaService.nameCardPicOf(this.currentDetail.name).length > 0) {
        Image($rawfile(`icons/NameCardPic/${WikiMetaService.nameCardPicOf(this.currentDetail.name)}.png`))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(0.22)
      }
      Column({ space: 10 }) {
      if (this.currentDetail !== undefined) {
        this.detailHeader()
        // 详情操作命令行（对齐 Windows AvatarView 底部命令区：导出文本 / 加入养成计划）
        this.detailActions()
        // 名片 + 攻略外链（对齐 Windows：名片展示 + 米游社/B站攻略入口）
        if (WikiMetaService.nameCardPicOf(this.currentDetail.name).length > 0) {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              NavIcon({ name: 'Database', iconSize: 20 })
              Text('名片')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
            }
            .width('100%')
            Image($rawfile(`icons/NameCardPic/${WikiMetaService.nameCardPicOf(this.currentDetail.name)}.png`))
              .width('100%')
              .borderRadius(10)
              .objectFit(ImageFit.Cover)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.divider') })
        }
        Row({ space: 10 }) {
          Button('米游社攻略')
            .fontSize(13)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.app_primary_bg'))
            .fontColor($r('app.color.app_primary'))
            .onClick(() => {
              this.openStrategy('mys');
            })
          Button('B站攻略')
            .fontSize(13)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.app_primary_bg'))
            .fontColor($r('app.color.app_primary'))
            .onClick(() => {
              this.openStrategy('bili');
            })
        }
        .width('100%')
        // 天赋/技能（本地元数据：普攻/战技/爆发/被动，对齐 Windows 角色详情天赋区）
        if (WikiMetaService.skillsOfAvatar(this.currentDetail.name).length > 0) {
          Column({ space: 8 }) {
            Text('天赋')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            ForEach(WikiMetaService.skillsOfAvatar(this.currentDetail.name), (sk: MetaSkill) => {
              Column({ space: 3 }) {
                Row({ space: 8 }) {
                  if (sk.i.length > 0) {
                    Row() {
                      MetaIcon({ category: 'Skill', name: sk.i, iconSize: 28 })
                    }
                    .width(38)
                    .height(38)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.icon_dark_chip'))
                    .alignItems(VerticalAlign.Center)
                    .justifyContent(FlexAlign.Center)
                  }
                  Column({ space: 2 }) {
                    Text(sk.n)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    if (sk.k.length > 0) {
                      Text(CharacterPage.kindLabel(sk.k))
                        .fontSize(10)
                        .fontColor($r('app.color.app_primary'))
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                Text(sk.d)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .width('100%')
              .padding({ top: 8, bottom: 8, left: 12, right: 12 })
              .borderRadius(10)
              .backgroundColor($r('app.color.page_background'))
            }, (sk: MetaSkill) => `sk_${sk.n}`)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.divider') })
        }
        if (this.currentDetail.weapon.id > 0) {
          Row({ space: 10 }) {
            if (WikiMetaService.iconOfWeapon(this.currentDetail.weapon.id).length > 0) {
              MetaIcon({
                category: 'EquipIcon',
                name: WikiMetaService.iconOfWeapon(this.currentDetail.weapon.id),
                iconSize: 40,
              })
            } else {
              NavIcon({ name: 'AvatarProperty', iconSize: 22 })
            }
            Text(`${WikiMetaService.nameOfWeapon(this.currentDetail.weapon.id)} · Lv.${this.currentDetail.weapon.level} ★${this.currentDetail.weapon.rarity} · 精炼${this.currentDetail.weapon.affixLevel}`)
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
                  MetaIcon({
                    category: 'RelicIcon',
                    name: CharacterPage.relicIconName(r.icon),
                    iconSize: 36,
                  })
                  Column({ space: 2 }) {
                    Text(`${r.posName} · ${r.name}`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
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
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
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
              .padding({ top: 8, bottom: 8, left: 12, right: 12 })
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

  /**
   * 详情操作命令行（对齐 Windows AvatarPropertyPage 命令区）：
   * 导出文本（默认模板结构固定拼装 → 剪贴板）/ 加入养成计划（多项目先弹选择）。
   * 无参 @Builder 直接读 @State，传参会固定快照不刷新（同 detailHeader 约定）。
   */
  @Builder
  detailActions() {
    Row({ space: 10 }) {
      Button('导出文本')
        .fontSize(this.isWide ? 13 : 12)
        .height(34)
        .layoutWeight(1)
        .backgroundColor($r('app.color.app_primary_bg'))
        .fontColor($r('app.color.app_primary'))
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.exportDetailText();
        })
      Button(this.addingPlan ? '加入中...' : '加入养成计划')
        .fontSize(this.isWide ? 13 : 12)
        .height(34)
        .layoutWeight(1)
        .backgroundColor($r('app.color.app_primary_bg'))
        .fontColor($r('app.color.app_primary'))
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.addCurrentToPlan();
        })
    }
    .width('100%')
  }

  /** 养成计划选择半窗内容（多项目时列出项目供选择） */
  @Builder
  planPickerSheet() {
    Column({ space: 10 }) {
      Text('选择要加入的养成计划')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.pendingProjects, (p: CultivateProject) => {
            Row({ space: 10 }) {
              NavIcon({ name: 'Cultivation', iconSize: 20 })
              Text(p.name)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('加入')
                .fontSize(12)
                .fontColor($r('app.color.app_primary'))
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .backgroundColor($r('app.color.page_background'))
            .border({ width: 1, color: $r('app.color.divider') })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.pickPlanProject(p);
            })
          }, (p: CultivateProject) => `plan_${p.id}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding(16)
  }

  /** 导出当前角色文本到剪贴板（对齐 Windows ExportToTextCommand，默认模板固定拼装） */
  private exportDetailText(): void {
    const d: CharacterDetail | undefined = this.currentDetail;
    if (d === undefined) {
      return;
    }
    const text: string = CharacterExportService.buildExportText(d,
      (t: string): string => CharacterPage.propLabel(t));
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('已复制');
    }).catch(() => {
      this.toast('复制失败');
    });
  }

  /** 加入养成计划入口：0 项目自动建默认 → 1 项目直接加入 → 多项目弹半窗选择 */
  private async addCurrentToPlan(): Promise<void> {
    const d: CharacterDetail | undefined = this.currentDetail;
    if (d === undefined || d.id <= 0 || this.addingPlan) {
      return;
    }
    try {
      const projects: CultivateProject[] = await CultivationRepo.getProjects();
      if (projects.length === 0) {
        const p: CultivateProject = await CultivationRepo.createProject('默认养成计划');
        await this.addToProject(d, p);
      } else if (projects.length === 1) {
        await this.addToProject(d, projects[0]);
      } else {
        this.pendingDetail = d;
        this.pendingProjects = projects;
        this.showPlanSheet = true;
      }
    } catch (e) {
      this.toast(`加入失败：${(e as Error).message}`);
    }
  }

  /** 半窗内选中项目：关闭半窗并加入 */
  private pickPlanProject(p: CultivateProject): void {
    const d: CharacterDetail | undefined = this.pendingDetail;
    this.showPlanSheet = false;
    if (d === undefined) {
      return;
    }
    this.addToProject(d, p);
  }

  /** 加入指定项目并 toast 结果（对齐 Windows：成功/已存在提示） */
  private async addToProject(d: CharacterDetail, p: CultivateProject): Promise<void> {
    if (this.addingPlan) {
      return;
    }
    this.addingPlan = true;
    try {
      const r: AddPlanResult = await this.vm.addAvatarToPlan(d, p);
      this.toast(r.message);
    } catch (e) {
      this.toast(`加入失败：${(e as Error).message}`);
    } finally {
      this.addingPlan = false;
    }
  }

  static kindLabel(k: string): string {
    switch (k) {
      case 'A': return '普攻';
      case 'E': return '战技';
      case 'Q': return '元素爆发';
      case 'P': return '被动';
      default: return '其他';
    }
  }

  /** 攻略外链：米游社/B站搜索当前角色（openLink 拉起浏览器） */
  openStrategy(target: string): void {
    if (this.currentDetail === undefined) {
      return;
    }
    const name: string = this.currentDetail.name;
    const url: string = target === 'mys'
      ? `https://www.miyoushe.com/ys/search?keyword=${encodeURIComponent(name + ' 攻略')}`
      : `https://search.bilibili.com/all?keyword=${encodeURIComponent('原神 ' + name + ' 攻略')}`;
    try {
      const host = this.getUIContext().getHostContext();
      if (host === undefined) {
        return;
      }
      const ui = host as common.UIAbilityContext;
      ui.openLink(url).catch((e: Error) => {
        this.toast(`打开失败：${e.message}`);
      });
    } catch (e) {
      this.toast(`打开失败：${(e as Error).message}`);
    }
  }

  /** 圣遗物图标名：API 可能带位置后缀 _N（CDN/打包无该变体），回退基础名 */
  static relicIconName(icon: string): string {
    if (icon.length === 0) {
      return '';
    }
    if (/_[0-9]$/.test(icon)) {
      const base: string = icon.substring(0, icon.lastIndexOf('_'));
      if (base.length > 0) {
        return base;
      }
    }
    return icon;
  }

  static relicScore(r: Reliquary, d: CharacterDetail): number {
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
                this.charFilterBar()
                ForEach(this.filteredItems(), (c: CharacterListItem) => {
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
    // 养成计划选择半窗（多项目时让用户选目标计划；$$ 双向同步下滑关闭）
    .bindSheet($$this.showPlanSheet, this.planPickerSheet(), {
      title: { title: '加入养成计划' },
      showClose: true,
      dragBar: true,
      height: 360,
      backgroundColor: $r('app.color.card_background'),
    })
  }
}
