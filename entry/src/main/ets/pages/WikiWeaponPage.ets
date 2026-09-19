/**
 * WikiWeaponPage.ets（@Entry）
 * 武器资料（对齐 Windows WikiWeaponPage）：列表/详情双栏（宽屏）/ 单栏切换（窄屏）。
 * 数据：rawfile/metadata/weapon_meta.json；图标：rawfile/icons（离线）。
 * 区块：简介（大图/类型/稀有度/描述）、精炼 1-5、养成材料。
 */
import { WikiMetaService, WikiWeaponMeta, MetaMaterial } from '../service/WikiMetaService';
import { BaseValueService } from '../service/BaseValueService';
import { CharacterViewModel, AddPlanResult } from '../viewmodel/CharacterViewModel';
import { CultivationRepo, CultivateProject } from '../data/repo/CultivationRepo';
import { AppBackButton } from '../components/AppBackButton';
import { PageBackdrop } from '../components/PageBackdrop';
import { MetaIcon } from '../components/MetaIcon';
import { SimpleDataSource } from '../components/SimpleDataSource';

@Entry
@Component
export struct WikiWeaponPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State loading: boolean = true;
  @State weapons: WikiWeaponMeta[] = [];
  @State materials: Map<number, MetaMaterial> = new Map();
  @State selectedId: number = 0;
  /** 当前详情对象（页面 @State 显式赋值驱动刷新） */
  @State current: WikiWeaponMeta | undefined = undefined;
  @State keyword: string = '';
  @State rankFilter: number = 0;
  @State isWide: boolean = false;
  /** 列表懒加载数据源 */
  private listSource: SimpleDataSource<WikiWeaponMeta> = new SimpleDataSource([]);
  /** 基础数值滑条状态 */
  @State curLevel: number = 1;
  @State curPromoted: boolean = false;
  @State curAttack: number = 0;

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
  }
  /** 养成计划加入动作（复用 CharacterViewModel.addWeaponToPlan，对齐 Windows WikiWeaponPage CultivateCommand） */
  private planVm: CharacterViewModel = new CharacterViewModel();
  /** 养成计划选择半窗（多项目时让用户选，逻辑与 CharacterPage 同款） */
  @State showPlanSheet: boolean = false;
  /** 待选养成计划列表（bindSheet 数据源） */
  @State pendingProjects: CultivateProject[] = [];
  /** 待加入计划的武器快照（选项目期间固定） */
  @State pendingWeaponId: number = 0;
  @State pendingWeaponName: string = '';
  /** 加入计划进行中（防重复点击） */
  @State addingPlan: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.weapons = await WikiMetaService.getWeapons();
    this.materials = await WikiMetaService.getMaterials();
    // 宽屏默认展示第一件；窄屏进入列表
    if (this.isWide && this.weapons.length > 0) {
      this.selectedId = this.weapons[0].id;
      this.current = this.weapons[0];
      await this.calcAttack();
    } else {
      this.selectedId = 0;
      this.current = undefined;
    }
    this.listSource.notifyDataReload(this.weapons.slice());
    this.loading = false;
  }

  /** 点击列表行：显式赋值页面 @State，并重置数值滑条 */
  select(w: WikiWeaponMeta): void {
    this.selectedId = w.id;
    this.current = w;
    this.onWeaponSelected();
  }

  /** 依据当前选中武器+等级+突破重算攻击力 */
  async calcAttack(): Promise<void> {
    const maxLv: number = BaseValueService.weaponMaxLevel(this.current?.rankLevel ?? 0);
    if (this.curLevel > maxLv) {
      this.curLevel = maxLv;
    }
    this.curAttack = await BaseValueService.weaponAttack(this.selectedId, this.curLevel, this.curPromoted);
  }

  /** 重置滑条为选中武器状态 */
  onWeaponSelected(): void {
    this.curLevel = 1;
    this.curPromoted = false;
    this.calcAttack();
  }

  /** 当前武器最大等级 */
  maxLevel(): number {
    return BaseValueService.weaponMaxLevel(this.current?.rankLevel ?? 0);
  }

  /** 加入养成计划入口（对齐 CharacterPage）：确认弹窗 → 0 项目自动建默认 / 1 项目直接加入 / 多项目弹半窗选择 */
  private async addCurrentToPlan(): Promise<void> {
    const w: WikiWeaponMeta | undefined = this.current;
    if (w === undefined || this.addingPlan) {
      return;
    }
    try {
      const projects: CultivateProject[] = await CultivationRepo.getProjects();
      if (projects.length === 0) {
        const p: CultivateProject = await CultivationRepo.createProject('默认养成计划');
        await this.addToProject(w.id, w.name, p);
      } else if (projects.length === 1) {
        await this.addToProject(w.id, w.name, projects[0]);
      } else {
        this.pendingWeaponId = w.id;
        this.pendingWeaponName = w.name;
        this.pendingProjects = projects;
        this.showPlanSheet = true;
      }
    } catch (e) {
      this.toast(`加入失败：${(e as Error).message}`);
    }
  }

  /** 确认弹窗：说明图鉴数据限制（按 Lv.90 目标记录），确认后走项目选择流程 */
  private confirmAddPlan(): void {
    const w: WikiWeaponMeta | undefined = this.current;
    if (w === undefined) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '加入养成计划',
      message: `图鉴为离线数据，将按 Lv.1 → Lv.90 目标记录「${w.name}」的养成目标（材料清单暂无法自动计算）。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '加入',
        fontColor: $r('app.color.app_primary'),
        action: () => {
          this.addCurrentToPlan();
        },
      },
    });
  }

  /** 半窗内选中项目：关闭半窗并加入 */
  private pickPlanProject(p: CultivateProject): void {
    const id: number = this.pendingWeaponId;
    const name: string = this.pendingWeaponName;
    this.showPlanSheet = false;
    if (id <= 0) {
      return;
    }
    this.addToProject(id, name, p);
  }

  /** 加入指定项目并 toast 结果（重复加入/失败提示对齐 Windows 口径） */
  private async addToProject(weaponId: number, weaponName: string, p: CultivateProject): Promise<void> {
    if (this.addingPlan) {
      return;
    }
    this.addingPlan = true;
    try {
      const r: AddPlanResult = await this.planVm.addWeaponToPlan(weaponId, weaponName, p);
      this.toast(r.ok ? `${r.message}（按 Lv.90 目标记录）` : r.message);
    } catch (e) {
      this.toast(`加入失败：${(e as Error).message}`);
    } finally {
      this.addingPlan = false;
    }
  }

  /** 养成计划选择半窗内容（多项目时列出项目供选择，样式与 CharacterPage 同款） */
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

  filtered(): WikiWeaponMeta[] {
    const out: WikiWeaponMeta[] = [];
    for (const w of this.weapons) {
      if (this.rankFilter > 0 && w.rankLevel !== this.rankFilter) {
        continue;
      }
      if (this.keyword.length > 0 && !w.name.includes(this.keyword)) {
        continue;
      }
      out.push(w);
    }
    return out;
  }

  /** 筛选后重建懒加载数据源 */
  applyFilter(): void {
    this.listSource.notifyDataReload(this.filtered());
  }

  static rankColor(r: number): Resource {
    if (r >= 5) {
      return $r('app.color.five_star');
    }
    if (r === 4) {
      return $r('app.color.four_star');
    }
    return $r('app.color.text_secondary');
  }

  matName(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.n : `${id}`;
  }

  matIcon(id: number): string {
    const m: MetaMaterial | undefined = this.materials.get(id);
    return m !== undefined ? m.i : '';
  }

  build() {
    Stack() {
      // 壁纸衬底：router 独立页透出壁纸，embed 内嵌时由壳层统一铺（组件内渲染为空）
      PageBackdrop({ embedMode: this.embedMode })
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
    .backgroundColor(Color.Transparent)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.isWide = (newValue.width as number) >= 840;
    })
    // 养成计划选择半窗（多项目时让用户选目标计划；$$ 双向同步下滑关闭）
    .bindSheet($$this.showPlanSheet, this.planPickerSheet(), {
      title: { title: '加入养成计划' },
      showClose: true,
      dragBar: true,
      height: 360,
      blurStyle: BlurStyle.Regular,
      backgroundColor: $r('app.color.sheet_material_tint'),
    })
    }
    .width('100%')
    .height('100%')
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
      Text('武器资料')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
      Text(`${this.weapons.length} 件武器`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  rankChip(label: string, value: number) {
    Text(label)
      .fontSize(11)
      .fontColor(this.rankFilter === value ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(this.rankFilter === value ? $r('app.color.app_primary_bg') : Color.Transparent)
      .onClick(() => {
        this.rankFilter = value;
        this.applyFilter();
      })
  }

  @Builder
  listPanel() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '搜索武器名' })
        .fontSize(13)
        .height(36)
        .onChange((v: string) => {
          this.keyword = v;
          this.applyFilter();
        })
      Row({ space: 6 }) {
        this.rankChip('全部', 0)
        this.rankChip('五星', 5)
        this.rankChip('四星', 4)
        this.rankChip('三星', 3)
      }
      .width('100%')

      List({ space: 4 }) {
        LazyForEach(this.listSource, (w: WikiWeaponMeta) => {
          ListItem() {
            Row({ space: 10 }) {
              MetaIcon({ category: 'EquipIcon', name: w.icon, iconSize: 38 })
              Column({ space: 2 }) {
                Text(w.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(WikiMetaService.weaponTypeName(w.weaponType))
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(`${w.rankLevel}★`)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(WikiWeaponPage.rankColor(w.rankLevel))
            }
            .width('100%')
            .padding(8)
            .borderRadius(10)
            .backgroundColor(this.selectedId === w.id ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
            .border({
              width: 1,
              color: this.selectedId === w.id ? $r('app.color.app_primary') : WikiWeaponPage.rankColor(w.rankLevel),
              radius: 10,
            })
            .onClick(() => {
              this.select(w);
            })
          }
        }, (w: WikiWeaponMeta) => `w_${w.id}`)
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
          // 简介卡
          Column({ space: 10 }) {
            Row({ space: 14 }) {
              Stack({ alignContent: Alignment.BottomEnd }) {
                MetaIcon({ category: 'EquipIcon', name: this.current!.icon, iconSize: 88 })
                Text(`${this.current!.rankLevel}★`)
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(8)
                  .backgroundColor(WikiWeaponPage.rankColor(this.current!.rankLevel))
              }
              Column({ space: 4 }) {
                Text(this.current!.name)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text(WikiMetaService.weaponTypeName(this.current!.weaponType))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            Text(this.current!.description)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius($r('app.float.card_radius'))
          .backgroundColor($r('app.color.card_surface'))

          // 养成计划操作区（对齐 Windows WikiWeaponPage 命令区 CultivateCommand）
          this.planActionBlock()

          // 基础数值卡（等级滑条 + 攻击力/突破）
          this.baseValueCard()

          // 精炼卡
          if (this.current!.affixName.length > 0) {
            Column({ space: 8 }) {
              Text(this.current!.affixName)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              ForEach(this.current!.affixDesc, (d: string, idx: number) => {
                Column({ space: 3 }) {
                  Text(`精炼 ${idx + 1} 阶`)
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.app_primary'))
                    .width('100%')
                  Text(d)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .width('100%')
                .padding({ top: 8, bottom: 8, left: 12, right: 12 })
                .borderRadius(8)
                .backgroundColor($r('app.color.page_background'))
              }, (d: string, idx: number) => `af_${idx}_${d.length}`)
            }
            .width('100%')
            .padding(14)
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.card_surface'))
          }

          // 养成材料卡
          if (this.current!.cultivationItems.length > 0) {
            Column({ space: 8 }) {
              Text('养成材料')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.current!.cultivationItems, (id: number) => {
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
                }, (id: number) => `m_${id}`)
              }
              .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.card_surface'))
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

  /** 养成计划操作区按钮（加入动作见 confirmAddPlan → addCurrentToPlan） */
  @Builder
  planActionBlock() {
    Row({ space: 10 }) {
      Button(this.addingPlan ? '加入中...' : '加入养成计划')
        .fontSize(13)
        .height(36)
        .layoutWeight(1)
        .backgroundColor($r('app.color.app_primary_bg'))
        .fontColor($r('app.color.app_primary'))
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.confirmAddPlan();
        })
    }
    .width('100%')
  }

  /** 基础数值卡：等级滑条 + 突破开关 + 攻击力（对齐 Windows BaseValueSlider） */
  @Builder
  baseValueCard() {
    Column({ space: 10 }) {
      Text('基础数值')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row({ space: 10 }) {
        Text(`等级 ${this.curLevel}`)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`攻击力 ${this.curAttack}`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_primary'))
      }
      .width('100%')

      Slider({
        value: this.curLevel,
        min: 1,
        max: this.maxLevel(),
        step: 1,
        style: SliderStyle.OutSet,
      })
        .width('100%')
        .blockColor($r('app.color.app_primary'))
        .selectedColor($r('app.color.app_primary'))
        .onChange((value: number) => {
          this.curLevel = Math.round(value);
          this.calcAttack();
        })

      Row() {
        Text('是否突破')
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.curPromoted })
          .onChange((isOn: boolean) => {
            this.curPromoted = isOn;
            this.calcAttack();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_surface'))
  }
}
