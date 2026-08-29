/**
 * WikiAvatarPage.ets（@Entry）
 * 角色资料（对齐 Windows WikiAvatarPage）：列表/详情双栏（宽屏）/ 单栏切换（窄屏）。
 * 数据：本地元数据 rawfile/metadata/avatar_meta.json（Snap.Metadata 公开仓库提取）；
 * 图标：rawfile/icons（离线）。区块：简介(元素/武器/生日/命座/CV)、养成材料、基础属性曲线(滑条+突破)、天赋技能、命座、料理、语音、故事。
 */
import { router } from '@kit.ArkUI';
import { WikiMetaService, WikiAvatarMeta, MetaSkill, MetaText, MetaMaterial } from '../service/WikiMetaService';
import { AppBackButton } from '../components/AppBackButton';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { BaseValueService, AvatarGrowInfo, AvatarBaseValues } from '../service/BaseValueService';

@Entry
@Component
export struct WikiAvatarPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  @State avatars: WikiAvatarMeta[] = [];
  @State materials: Map<number, MetaMaterial> = new Map();
  @State selectedId: number = 0;
  /** 当前详情对象（页面 @State 显式赋值驱动刷新；@Builder 内方法派生在当前构建不触发重绘） */
  @State current: WikiAvatarMeta | undefined = undefined;
  @State keyword: string = '';
  @State qualityFilter: number = 0;
  @State isWide: boolean = false;
  /** 角色列表懒加载数据源（140+ 项全量渲染开销大，LazyForEach 只画可视区） */
  private listSource: SimpleDataSource<WikiAvatarMeta> = new SimpleDataSource([]);
  /** 基础属性滑条状态（对齐 Windows BaseValueSlider） */
  @State curLevel: number = 1;
  @State curPromoted: boolean = false;
  @State curHp: number = 0;
  @State curAtk: number = 0;
  @State curDef: number = 0;
  @State curBonusText: string = '';

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.avatars = await WikiMetaService.getAvatars();
    this.materials = await WikiMetaService.getMaterials();
    // 宽屏默认展示第一个角色详情；窄屏进入列表，点击后再进详情
    if (this.isWide && this.avatars.length > 0) {
      this.selectedId = this.avatars[0].id;
      this.current = this.avatars[0];
      this.onAvatarSelected();
    } else {
      this.selectedId = 0;
      this.current = undefined;
    }
    this.listSource.notifyDataReload(this.avatars.slice());
    this.loading = false;
  }

  /** 点击列表行：显式赋值页面 @State（弃方法派生，确保详情刷新） */
  select(a: WikiAvatarMeta): void {
    this.selectedId = a.id;
    this.current = a;
    this.onAvatarSelected();
  }

  /** 重置滑条并重算基础属性（切换角色时） */
  onAvatarSelected(): void {
    this.curLevel = 1;
    this.curPromoted = false;
    this.calcAvatarBase();
  }

  /** 依据当前角色+等级+突破重算 生命/攻击/防御/突破属性 */
  calcAvatarBase(): void {
    const cur: WikiAvatarMeta | undefined = this.current;
    if (cur === undefined || cur.growCurves.length === 0) {
      this.curHp = 0;
      this.curAtk = 0;
      this.curDef = 0;
      this.curBonusText = '';
      return;
    }
    const maxLv: number = BaseValueService.avatarMaxLevel(cur.quality);
    if (this.curLevel > maxLv) {
      this.curLevel = maxLv;
    }
    const info: AvatarGrowInfo = new AvatarGrowInfo();
    info.hpBase = cur.hpBase;
    info.attackBase = cur.attackBase;
    info.defenseBase = cur.defenseBase;
    info.promoteId = cur.promoteId;
    info.growCurves = cur.growCurves;
    BaseValueService.avatarBaseValues(info, this.curLevel, this.curPromoted).then((v: AvatarBaseValues) => {
      // 异步返回时角色可能已切换，校验后再落地
      if (this.current !== undefined && this.current.id === cur.id) {
        this.curHp = v.hp;
        this.curAtk = v.atk;
        this.curDef = v.def;
        this.curBonusText = v.bonusType > 0
          ? `${BaseValueService.fightPropName(v.bonusType)} ${BaseValueService.fightPropText(v.bonusType, v.bonusValue)}`
          : '';
      }
    }).catch(() => {
    });
  }

  /** 当前角色最大等级 */
  avatarMaxLevel(): number {
    return BaseValueService.avatarMaxLevel(this.current?.quality ?? 0);
  }

  filtered(): WikiAvatarMeta[] {
    const out: WikiAvatarMeta[] = [];
    for (const a of this.avatars) {
      if (this.qualityFilter > 0 && a.quality !== this.qualityFilter) {
        continue;
      }
      if (this.keyword.length > 0 && !a.name.includes(this.keyword) && !a.title.includes(this.keyword)) {
        continue;
      }
      out.push(a);
    }
    return out;
  }

  /** 筛选后重建懒加载数据源（在筛选 chip/搜索变化时调用） */
  refreshListSource(): void {
    this.listSource.notifyDataReload(this.filtered());
  }

  /** 筛选 chip 变化：刷新状态 + 数据源 */
  applyFilter(): void {
    this.refreshListSource();
  }

  static qualityColor(q: number): Resource {
    return q >= 5 ? $r('app.color.five_star') : $r('app.color.four_star');
  }

  static kindLabel(k: string): string {
    switch (k) {
      case 'A': return '普攻';
      case 'E': return '战技';
      case 'Q': return '爆发';
      case 'P': return '被动';
      default: return '技能';
    }
  }

  matName(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.n : `${id}`;
  }

  matIcon(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.i : '';
  }

  cvOf(a: WikiAvatarMeta, idx: number): string {
    return a.cv.length > idx ? a.cv[idx] : '—';
  }

  build() {
    Column() {
      this.header()
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
          Text('加载中...')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.isWide) {
        Row({ space: 10 }) {
          this.listPanel()
          this.detailPanel()
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        if (this.selectedId === 0) {
          this.listPanel()
        } else {
          this.detailPanel()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.isWide = (newValue.width as number) >= 840;
    })
  }

  @Builder
  header() {
    Row() {
      if (!this.embedMode) {
        AppBackButton()
      }
      if (!this.isWide && this.selectedId !== 0) {
        Text('‹')
          .fontSize(22)
          .fontColor($r('app.color.text_primary'))
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.selectedId = 0;
            this.current = undefined;
          })
      }
      Text('角色资料')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
      Text(`${this.avatars.length} 位角色`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  qualityChip(label: string, value: number) {
    Text(label)
      .fontSize(11)
      .fontColor(this.qualityFilter === value ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(this.qualityFilter === value ? $r('app.color.app_primary_bg') : Color.Transparent)
      .onClick(() => {
        this.qualityFilter = value;
        this.applyFilter();
      })
  }

  /** 左侧列表（搜索 + 品质筛选 + 角色行） */
  @Builder
  listPanel() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '搜索角色名/称号' })
        .fontSize(13)
        .height(36)
        .onChange((v: string) => {
          this.keyword = v;
          this.applyFilter();
        })
      Row({ space: 6 }) {
        this.qualityChip('全部', 0)
        this.qualityChip('五星', 5)
        this.qualityChip('四星', 4)
      }
      .width('100%')

      List({ space: 4 }) {
        LazyForEach(this.listSource, (a: WikiAvatarMeta) => {
          ListItem() {
            Row({ space: 10 }) {
              MetaIcon({ category: 'AvatarIcon', name: a.sideIcon, iconSize: 40 })
              Column({ space: 2 }) {
                Text(a.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                if (a.title.length > 0) {
                  Text(a.title)
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(`${WikiMetaService.elementName(a.vision)}·${WikiMetaService.weaponTypeName(a.weapon)}`)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding(8)
            .borderRadius(10)
            .backgroundColor(this.selectedId === a.id ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
            .border({
              width: 1,
              color: this.selectedId === a.id ? $r('app.color.app_primary') : WikiAvatarPage.qualityColor(a.quality),
              radius: 10,
            })
            .onClick(() => {
              this.select(a);
            })
          }
        }, (a: WikiAvatarMeta) => `a_${a.id}`)
      }
      .cachedCount(5)
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width(this.isWide ? 300 : '100%')
    .height('100%')
    .padding({ left: 16, right: this.isWide ? 0 : 16 })
  }

  /** 材料小项 */
  @Builder
  materialItem(id: number) {
    Column({ space: 3 }) {
      MetaIcon({ category: 'ItemIcon', name: this.matIcon(id), iconSize: 36 })
      Text(this.matName(id))
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .constraintSize({ maxWidth: 72 })
    }
    .width(76)
    .alignItems(HorizontalAlign.Center)
  }

  /** 右侧详情（无参：直接读 @State current；传参 @Builder 为值快照，切换角色不刷新） */
  @Builder
  detailPanel() {
    if (this.current !== undefined) {
      Scroll() {
        Column({ space: 12 }) {
          this.profileCard()
          this.baseValueCard()
          this.skillsCard()
          this.talentsCard()
          if (this.current!.cook !== null) {
            this.cookCard()
          }
          this.textsCard('语音', 'fetters')
          this.textsCard('故事', 'stories')
          Text('数据来源：Snap.Metadata（本地打包）')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 4, right: 16, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
  }

  /** 基础属性卡：等级滑条 + 突破开关 + 生命/攻击/防御/突破加成（对齐 Windows BaseValueSlider） */
  @Builder
  baseValueCard() {
    Column({ space: 10 }) {
      Text('基础属性')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row() {
        Text(`等级 ${this.curLevel}`)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.curBonusText.length > 0) {
          Text(this.curBonusText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_primary'))
        }
      }
      .width('100%')

      Slider({
        value: this.curLevel,
        min: 1,
        max: this.avatarMaxLevel(),
        step: 1,
        style: SliderStyle.OutSet,
      })
        .width('100%')
        .blockColor($r('app.color.app_primary'))
        .selectedColor($r('app.color.app_primary'))
        .onChange((value: number) => {
          this.curLevel = Math.round(value);
          this.calcAvatarBase();
        })

      Row({ space: 12 }) {
        this.propCell('生命值', this.curHp)
        this.propCell('攻击力', this.curAtk)
        this.propCell('防御力', this.curDef)
      }
      .width('100%')

      Row() {
        Text('是否突破')
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.curPromoted })
          .onChange((isOn: boolean) => {
            this.curPromoted = isOn;
            this.calcAvatarBase();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  propCell(label: string, value: number) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
      Text(`${value}`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  infoChip(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor($r('app.color.app_primary'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .margin({ right: 6, bottom: 4 })
      .borderRadius(9)
      .backgroundColor($r('app.color.app_primary_bg'))
  }

  /** 简介卡（无参：读 @State current） */
  @Builder
  profileCard() {
    Column({ space: 10 }) {
      if (this.current !== undefined) {
      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          MetaIcon({ category: 'AvatarIcon', name: this.current.icon, iconSize: 88 })
          Text(`${this.current.quality}★`)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor(this.current.quality >= 5 ? $r('app.color.five_star') : $r('app.color.four_star'))
        }
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(this.current.name)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            if (this.current.title.length > 0) {
              Text(this.current.title)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          Text(this.current.detail)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        this.infoChip(`${WikiMetaService.elementName(this.current.vision)}元素`)
        this.infoChip(WikiMetaService.weaponTypeName(this.current.weapon))
        this.infoChip(`生日 ${this.current.birth}`)
        if (this.current.constellation.length > 0) {
          this.infoChip(`命座 ${this.current.constellation}`)
        }
        if (this.current.native.length > 0) {
          this.infoChip(this.current.native)
        }
        if (this.current.begin.length > 0) {
          this.infoChip(`实装 ${this.current.begin}`)
        }
      }
      .width('100%')

      Row({ space: 10 }) {
        Text('配音')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text(`中 ${this.cvOf(this.current, 0)}　日 ${this.cvOf(this.current, 1)}　英 ${this.cvOf(this.current, 2)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .layoutWeight(1)
      }
      .width('100%')

      if (this.current.cultivationItems.length > 0) {
        Column({ space: 6 }) {
          Text('养成材料')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.current.cultivationItems, (id: number) => {
              this.materialItem(id)
            }, (id: number) => `m_${id}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding(8)
        .borderRadius(10)
        .backgroundColor($r('app.color.page_background'))
      }
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  /** 天赋技能卡（无参：读 @State current） */
  @Builder
  skillsCard() {
    Column({ space: 8 }) {
      Text('天赋')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      ForEach(this.current?.skills ?? [], (s: MetaSkill, idx: number) => {
        Row({ space: 10 }) {
          MetaIcon({ category: s.i.startsWith('UI_Talent_') ? 'Talent' : 'Skill', name: s.i, iconSize: 38 })
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(s.n)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(WikiAvatarPage.kindLabel(s.k))
                .fontSize(9)
                .fontColor($r('app.color.app_primary'))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(7)
                .backgroundColor($r('app.color.app_primary_bg'))
            }
            Text(s.d)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
        .alignItems(VerticalAlign.Top)
      }, (s: MetaSkill, idx: number) => `sk_${s.n}`)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  /** 命座卡（无参：读 @State current） */
  @Builder
  talentsCard() {
    Column({ space: 8 }) {
      Text(`命座 · ${this.current?.constellation ?? ''}`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      ForEach(this.current?.talents ?? [], (s: MetaSkill, idx: number) => {
        Row({ space: 10 }) {
          Text(`${idx + 1}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary'))
            .width(20)
            .textAlign(TextAlign.Center)
          MetaIcon({ category: 'Talent', name: s.i, iconSize: 34 })
          Column({ space: 3 }) {
            Text(s.n)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(s.d)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
        .alignItems(VerticalAlign.Top)
      }, (s: MetaSkill, idx: number) => `tl_${s.n}`)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  /** 料理卡（无参：读 @State current） */
  @Builder
  cookCard() {
    Column({ space: 8 }) {
      Text('特殊料理')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.current !== undefined && this.current.cook !== null) {
        Row({ space: 10 }) {
          MetaIcon({ category: 'ItemIcon', name: this.matIcon(Number(this.current.cook!['item'])), iconSize: 36 })
          Column({ space: 2 }) {
            Text(this.matName(Number(this.current.cook!['item'])))
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
            Text(`基于 ${this.matName(Number(this.current.cook!['origin']))} 制作`)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  /** 语音/故事卡（kind：'fetters'|'stories'；直接读 @State current，切换角色自动刷新） */
  @Builder
  textsCard(title: string, kind: string) {
    if (this.current !== undefined) {
      if (kind === 'stories' ? this.current.stories.length > 0 : this.current.fetters.length > 0) {
        Column({ space: 8 }) {
          Text(`${title}（${kind === 'stories' ? this.current.stories.length : this.current.fetters.length}）`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          ForEach(kind === 'stories' ? this.current.stories : this.current.fetters, (t: MetaText, idx: number) => {
            Column({ space: 3 }) {
              Text(t.t)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(t.c)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding({ top: 6, bottom: 6, left: 8, right: 8 })
            .borderRadius(8)
            .backgroundColor($r('app.color.page_background'))
          }, (t: MetaText, idx: number) => `tx_${title}_${idx}_${t.t}`)
        }
        .width('100%')
        .padding(14)
        .borderRadius($r('app.float.card_radius'))
        .backgroundColor($r('app.color.card_background'))
      }
    }
  }
}
