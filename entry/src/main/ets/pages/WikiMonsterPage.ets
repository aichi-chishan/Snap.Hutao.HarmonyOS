/**
 * WikiMonsterPage.ets（@Entry）
 * 怪物资料（对齐 Windows WikiMonsterPage）：列表/详情双栏（宽屏）/ 单栏切换（窄屏）。
 * 数据：rawfile/metadata/monster_meta.json（Snap.Metadata 提取）；图标：rawfile/icons/MonsterIcon（离线）。
 */
import { WikiMetaService, WikiMonsterMeta, MetaMaterial } from '../service/WikiMetaService';
import { AppBackButton } from '../components/AppBackButton';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';

@Entry
@Component
export struct WikiMonsterPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  @State monsters: WikiMonsterMeta[] = [];
  @State materials: Map<number, MetaMaterial> = new Map();
  @State selectedId: number = 0;
  /** 当前详情对象（页面 @State 显式赋值驱动刷新） */
  @State current: WikiMonsterMeta | undefined = undefined;
  @State keyword: string = '';
  @State isWide: boolean = false;
  /** 列表懒加载数据源 */
  private listSource: SimpleDataSource<WikiMonsterMeta> = new SimpleDataSource([]);

  /** 8 项抗性标签（顺序对齐 subHurts：火/水/草/雷/冰/岩/风/物理） */
  private static readonly RESIST_LABELS: string[] = [
    '火元素抗性', '水元素抗性', '草元素抗性', '雷元素抗性',
    '冰元素抗性', '岩元素抗性', '风元素抗性', '物理抗性',
  ];

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.monsters = await WikiMetaService.getMonsters();
    this.materials = await WikiMetaService.getMaterials();
    // 宽屏默认展示第一只；窄屏进入列表
    if (this.isWide && this.monsters.length > 0) {
      this.selectedId = this.monsters[0].id;
      this.current = this.monsters[0];
    } else {
      this.selectedId = 0;
      this.current = undefined;
    }
    this.listSource.notifyDataReload(this.monsters.slice());
    this.loading = false;
  }

  /** 点击列表行：显式赋值页面 @State */
  select(m: WikiMonsterMeta): void {
    this.selectedId = m.id;
    this.current = m;
  }

  matName(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.n : `${id}`;
  }

  matIcon(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.i : '';
  }

  filtered(): WikiMonsterMeta[] {
    const out: WikiMonsterMeta[] = [];
    for (const m of this.monsters) {
      if (this.keyword.length > 0 && !m.name.includes(this.keyword) && !m.title.includes(this.keyword)) {
        continue;
      }
      out.push(m);
    }
    return out;
  }

  /** 筛选后重建懒加载数据源 */
  applyFilter(): void {
    this.listSource.notifyDataReload(this.filtered());
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
      Text('怪物资料')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
      Text(`${this.monsters.length} 种怪物`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  listPanel() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '搜索怪物名/头衔' })
        .fontSize(13)
        .height(36)
        .onChange((v: string) => {
          this.keyword = v;
          this.applyFilter();
        })
      List({ space: 4 }) {
        LazyForEach(this.listSource, (m: WikiMonsterMeta) => {
          ListItem() {
            Row({ space: 10 }) {
              MetaIcon({ category: 'MonsterIcon', name: m.icon, iconSize: 40 })
              Column({ space: 2 }) {
                Text(m.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                if (m.title.length > 0) {
                  Text(m.title)
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(8)
            .borderRadius(10)
            .backgroundColor(this.selectedId === m.id ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
            .border({
              width: 1,
              color: this.selectedId === m.id ? $r('app.color.app_primary') : $r('app.color.divider'),
              radius: 10,
            })
            .onClick(() => {
              this.select(m);
            })
          }
        }, (m: WikiMonsterMeta) => `m_${m.id}`)
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

  @Builder
  detailPanel() {
    if (this.current !== undefined) {
      Scroll() {
        Column({ space: 12 }) {
          // 头图卡
          Column({ space: 10 }) {
            Row({ space: 14 }) {
              MetaIcon({ category: 'MonsterIcon', name: this.current!.icon, iconSize: 96 })
              Column({ space: 4 }) {
                Text(this.current!.name)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                if (this.current!.title.length > 0) {
                  Text(this.current!.title)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                Text(`类别编号 ${this.current!.describeId}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')

            if (this.current!.description.length > 0) {
              Text(this.current!.description)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }

            if (this.current!.affixes.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.current!.affixes, (aff: string) => {
                  Text(aff)
                    .fontSize(10)
                    .fontColor($r('app.color.app_primary'))
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                    .margin({ right: 5, bottom: 4 })
                    .borderRadius(8)
                    .backgroundColor($r('app.color.app_primary_bg'))
                }, (aff: string, idx: number) => `aff_${idx}_${aff}`)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius($r('app.float.card_radius'))
          .backgroundColor($r('app.color.card_background'))

          // 基础数值卡
          if (this.current!.hpBase > 0 || this.current!.attackBase > 0) {
            Column({ space: 8 }) {
              Text('基础数值')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              this.monStat('生命值', this.current!.hpBase)
              this.monStat('攻击力', this.current!.attackBase)
              this.monStat('防御力', this.current!.defenseBase)
            }
            .width('100%')
            .padding(14)
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.card_background'))
          }

          // 抗性卡
          if (this.current!.subHurts.length >= 8) {
            Column({ space: 8 }) {
              Text('元素/物理抗性')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Grid() {
                ForEach(WikiMonsterPage.RESIST_LABELS, (label: string, idx: number) => {
                  GridItem() {
                    Row({ space: 6 }) {
                      Text(label)
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .layoutWeight(1)
                      Text(`${Math.round(this.current!.subHurts[idx] * 100)}%`)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                  }
                }, (label: string, idx: number) => `res_${idx}_${label}`)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(12)
              .rowsGap(8)
              .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.card_background'))
          }

          // 掉落物卡
          if (this.current!.drops.length > 0) {
            Column({ space: 8 }) {
              Text('掉落物')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.current!.drops, (id: number) => {
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
                }, (id: number) => `drop_${id}`)
              }
              .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.card_background'))
          }

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

  @Builder
  monStat(label: string, value: number) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      Text(`${value}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
  }
}
