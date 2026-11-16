/**
 * CultivationPage.ets（@Entry）
 * 养成计划：候选角色（角色列表）→ 勾选 + 目标等级 → 批量计算材料消耗 → 材料清单；
 * 计算结果可保存为持久化培养条目（多项目 + 材料勾选，对齐 Windows CultivationPage）。
 * 数据源：character/list（角色）+ batch_compute（材料）+ 本地计划库。
 */
import { CultivationDraftViewModel } from '../viewmodel/CultivationDraftViewModel';
import { CultivationDraftEditor } from '../components/CultivationDraftEditor';
import { CultivationService } from '../service/CultivationService';
import { CultivationDraft } from '../model/CultivationDraft';
import { CultivationFilterKind, CultivationFilterToken } from '../model/CultivationFilterToken';
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { CultivationViewModel, CultivateTarget, InventoryMaterialView } from '../viewmodel/CultivationViewModel';
import { CalItem } from '../model/Calculate';
import { elementName } from '../model/CharacterData';
import { CultivateEntry, CultivateEntryItem, CultivateProject } from '../data/repo/CultivationRepo';
import { ResinStatisticsService, ResinCategoryRow, ResinStatisticsResult } from '../service/ResinStatisticsService';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { NavIcon } from '../components/NavIcon';
import { BackpackArchive } from '../model/BackpackData';
import { MetaIcon } from '../components/MetaIcon';
import { WikiMetaService } from '../service/WikiMetaService';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, SelectMaterialModifier, UiSurface } from '../common/UiSurface';
import { GameCalendarRules } from '../service/GameCalendarRules';
import { SimpleDataSource } from '../components/SimpleDataSource';

@Entry
@Component
export struct CultivationPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') @Watch('accountChanged') currentUid: string = '';
  @StorageLink('isLoggedIn') @Watch('accountChanged') isLoggedIn: boolean = false;
  @StorageProp('cultivationDataVersion') @Watch('refreshSavedPlan') cultivationDataVersion: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('localeChanged') localeVersion: number = 0;
  @State vm: CultivationViewModel = new CultivationViewModel();
  /** 目标等级输入（临时） */
  @State showDraft: boolean = false;
  @State draftVm: CultivationDraftViewModel = new CultivationDraftViewModel();
  @State levelTmp: string = '';
  @State showInventory: boolean = false;
  @State editInventory: boolean = false;
  @State materialQuery: string = '';
  @State materialRowCount: number = 0;
  @State incompleteFirst: boolean = false;
  @State inventoryEditId: number = 0;
  @State inventoryCountText: string = '';
  @State showCreateProject: boolean = false;
  @State projectName: string = '';
  @State projectOffsetIndex: number = 0;
  @State planSearch: string = '';
  @State showPlanFilters: boolean = false;
  @State planTokens: CultivationFilterToken[] = [];
  private inventorySource: SimpleDataSource<InventoryMaterialView> = new SimpleDataSource<InventoryMaterialView>([]);
  private attached: boolean = false;
  /** 内容区宽 >=840 双栏（对齐 WikiAvatarPage 断点写法） */
  @State isWide: boolean = false;

  accountChanged(): void { this.showDraft = false; this.draftVm.cancel(); this.loadData(); }
  aboutToDisappear(): void { this.attached = false; this.draftVm.cancel(); this.vm.invalidate(); }

  @Builder
  draftSheet() {
    CultivationDraftEditor({ vm: this.draftVm, uid: this.isLoggedIn ? this.currentUid : '',
      onClose: (): void => { this.showDraft = false; this.draftVm.cancel(); } })
  }

  private async editSelected(): Promise<void> {
    if (this.draftVm.busy) { return; }
    this.showDraft = true;
    const selected: CultivateTarget[] = this.vm.targets.filter((target: CultivateTarget): boolean => target.selected);
    if (selected.length === 0) { this.draftVm.message = '请先选择角色'; return; }
    const uid: string = this.isLoggedIn ? this.currentUid : '';
    await this.draftVm.selectedTargets(uid, selected.map((target: CultivateTarget): number => target.avatarId), this.vm.currentProjectId);
  }

  private editEntry(entry: CultivateEntry): void {
    this.showDraft = true; this.draftVm.edit(entry).then(() => {});
  }

  aboutToAppear(): void {
    this.attached = true;
    this.loadData();
  }

  loadData(): void {
    this.vm.load(this.isLoggedIn ? this.currentUid : '').catch((e: Error) => {
      this.vm.message = e.message;
    });
    this.refreshSavedPlan();
  }

  private refreshSavedPlan(): void {
    this.vm.loadPlan().then(() => { if (this.attached) { this.refreshMaterials(); } });
  }

  private localeChanged(): void {
    if (this.attached) { this.vm.refreshDisplay().then(() => { if (this.attached) { this.refreshMaterials(); } }); }
  }

  private openTargetSource(url: string): void {
    this.getUIContext().getRouter().pushUrl({ url: url }).catch((error: Error): void => this.toast(error.message));
  }

  private targetSources(): MenuElement[] {
    return [
      { value: $r('app.string.ui_nav_wiki_avatar'), action: (): void => this.openTargetSource('pages/WikiAvatarPage') },
      { value: $r('app.string.ui_nav_wiki_weapon'), action: (): void => this.openTargetSource('pages/WikiWeaponPage') },
      { value: $r('app.string.ui_nav_character'), action: (): void => this.openTargetSource('pages/CharacterPage') },
    ];
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1800 });
  }

  /** 材料今日是否可刷（周一四/二五/三六轮换，周日全开；对齐 Windows Material.IsItemOfToday） */
  isTodayItem(itemId: number): boolean {
    return this.vm.isTodayItem(itemId);
  }

  private selectOptions(labels: ResourceStr[]): SelectOption[] {
    return labels.map((label: ResourceStr): SelectOption => ({ value: label }));
  }

  private planQualityLabels(): ResourceStr[] {
    return [$r('app.string.ui_model_intrinsic_item_quality_white'), $r('app.string.ui_model_intrinsic_item_quality_green'),
      $r('app.string.ui_model_intrinsic_item_quality_blue'), $r('app.string.ui_model_intrinsic_item_quality_purple'),
      $r('app.string.ui_model_intrinsic_item_quality_orange'), $r('app.string.ui_model_intrinsic_item_quality_red')];
  }

  private planVisionLabels(): ResourceStr[] {
    return [$r('app.string.ui_model_intrinsic_element_name_fire'), $r('app.string.ui_model_intrinsic_element_name_water'),
      $r('app.string.ui_model_intrinsic_element_name_elec'), $r('app.string.ui_model_intrinsic_element_name_grass'),
      $r('app.string.ui_model_intrinsic_element_name_ice'), $r('app.string.ui_model_intrinsic_element_name_wind'),
      $r('app.string.ui_model_intrinsic_element_name_rock')];
  }

  private planTokenLabel(token: CultivationFilterToken): ResourceStr {
    switch (token.kind) {
      case CultivationFilterKind.Target:
        return token.value === '1' ? $r('app.string.ui_gacha_pivot_avatar') : $r('app.string.ui_backpack_category_weapon');
      case CultivationFilterKind.Quality:
        return this.planQualityLabels()[CultivationFilterToken.options(token.kind).indexOf(token.value)] ?? token.value;
      case CultivationFilterKind.Weapon:
        return WikiMetaService.weaponTypeName(Number(token.value));
      case CultivationFilterKind.Element:
        return this.planVisionLabels()[CultivationFilterToken.options(token.kind).indexOf(token.value)] ?? token.value;
      default:
        return token.value;
    }
  }

  private async createProject(): Promise<void> {
    const offset: number = GameCalendarRules.OFFSET_HOURS[this.projectOffsetIndex];
    if (await this.vm.createProject(this.projectName, offset)) { this.showCreateProject = false; }
    this.toast(this.vm.planMessage);
  }

  /** 树脂统计行（Builder 内经方法读取，规避属性窄化与 @Builder 多参刷新问题） */
  resinRows(): ResinCategoryRow[] {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.rows : [];
  }

  hasResinRows(): boolean {
    return this.resinRows().length > 0;
  }

  resinTotalResin(): number {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.totalResin : 0;
  }

  resinTotalFragile(): number {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.totalFragile : 0;
  }

  resinTotalDays(): number {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.totalDays : 0;
  }

  @Builder
  header() {
    PageHeader({ title: $r('app.string.ui_nav_cultivation'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
      Row({ space: 6 }) {
        Button('添加目标', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .fontSize(13).height(44)
          .bindMenu(this.targetSources(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
        Button($r('app.string.common_refresh'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(13).height(44)
          .onClick(() => this.loadData())
      }
    }
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'Cultivation', iconSize: 60 })
      Text('需登录后使用养成计划')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Button('去登录', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  @Builder
  targetRow(target: CultivateTarget, idx: number) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (target.selected) {
          Circle()
            .width(58)
            .height(58)
            .fill($r('app.color.app_primary_bg'))
        } else {
          Circle()
            .width(58)
            .height(58)
            .fill($r('app.color.card_background'))
        }
        if (target.icon.length > 0) {
          // 官方图标名（UI_AvatarIcon_xxx）或 URL
          if (target.icon.startsWith('http')) {
            Image(target.icon)
              .width(52)
              .height(52)
              .objectFit(ImageFit.Cover)
              .borderRadius(26)
          } else {
            MetaIcon({ category: 'AvatarIcon', name: target.icon, iconSize: 52 })
              .borderRadius(26)
              .clip(true)
          }
        } else if (WikiMetaService.iconOfAvatar(target.avatarId).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(target.avatarId), iconSize: 52 })
            .borderRadius(26)
            .clip(true)
        } else {
          Text(target.name.length > 0 ? target.name.substring(0, 1) : '◇')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_accent'))
            .width(52)
            .height(52)
            .textAlign(TextAlign.Center)
            .borderRadius(26)
            .backgroundColor($r('app.color.app_primary'))
        }
      }
      Column({ space: 3 }) {
        Row({ space: 4 }) {
          Text(target.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(elementName(target.element))
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        Text(`当前 Lv.${target.level} · 天赋目标${target.targetSkillLevel} · 武器目标${target.targetWeaponLevel}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Row({ space: 6 }) {
          Text('目标')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
          Text(`${target.targetLevel}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary_text'))
          Text('级')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(target.selected ? '✓' : '○')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(target.selected ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(target.selected ? $r('app.color.app_primary_bg') : $r('app.color.card_inner_tint'))
    .border({ width: 1, color: target.selected ? $r('app.color.app_primary') : $r('app.color.divider') })
    .onClick(() => {
      this.vm.toggle(idx);
    })
  }

  /** 快速设置目标（90/80/70/60） */
  @Builder
  quickLevelBar() {
    Row({ space: 6 }) {
      Text('目标等级')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
      ForEach([60, 70, 80, 90, 95, 100], (lv: number) => {
        Text(`${lv}`)
          .fontSize(11)
          .fontColor($r('app.color.app_primary_text'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(9)
          .backgroundColor($r('app.color.app_primary_bg'))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            // 走 setTargetLevel（整体重赋值 targets）触发 @State 刷新；就地改 targets[i].targetLevel
            // 是深层变更不驱动 UI，且不会持久化
            for (let i = 0; i < this.vm.targets.length; i++) {
              if (this.vm.targets[i].selected) {
                this.vm.setTargetLevel(i, lv);
              }
            }
          })
      }, (lv: number) => `quicklv_${lv}`)
      Blank()
    }
    .width('100%')
  }

  @Builder
  materialRow(item: CalItem) {
    Row({ space: 8 }) {
      Text(item.name.length > 0 ? item.name.substring(0, 1) : '◇')
        .fontSize(13)
        .width(30)
        .height(44)
        .textAlign(TextAlign.Center)
        .borderRadius(8)
        .backgroundColor($r('app.color.app_primary_bg'))
      Text(item.name)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`× ${item.num}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_primary_text'))
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }

  /** 结果区附加：保存到养成计划（对齐 Windows 条目持久化） */
  @Builder
  savePlanBar() {
    if (this.vm.result !== undefined && this.vm.result.overallConsume.length > 0) {
      Button(this.vm.planBusy ? '保存中...' : '保存计算结果到养成计划', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
        .width('100%')
        .height(44)
        .fontSize(14)
        .borderRadius(10)
        .onClick(() => {
          this.vm.saveResultToPlan().then((ok: boolean) => {
            this.toast(ok ? this.vm.message : (this.vm.message.length > 0 ? this.vm.message : '保存失败'));
          });
        })
    }
  }

  /** 项目切换条（chips + 新建/删除） */
  @Builder
  projectBar() {
    Row({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.vm.projects, (p: CultivateProject) => {
            Text(p.name)
              .fontSize(12)
              .fontColor(this.vm.currentProjectId === p.id ? $r('app.color.on_accent') : $r('app.color.text_primary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(this.vm.currentProjectId === p.id
                ? $r('app.color.app_primary') : $r('app.color.card_inner_tint'))
              .border({ width: 1, color: this.vm.currentProjectId === p.id
                ? $r('app.color.app_primary') : $r('app.color.divider') })
              .constraintSize({ minWidth: 48 })
              .enabled(!this.vm.planBusy)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.vm.selectProject(p.id).then(() => this.refreshMaterials());
              })
          }, (p: CultivateProject) => `proj_${p.id}_${p.name}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      Text('＋')
        .fontSize(16)
        .fontColor($r('app.color.app_primary_text'))
        .width(30)
        .height(44)
        .textAlign(TextAlign.Center)
        .borderRadius(15)
        .backgroundColor($r('app.color.app_primary_bg'))
        .enabled(!this.vm.planBusy && !this.vm.planLoading)
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('新建养成计划')
        .accessibilityLevel('yes')
        .onClick(() => {
          this.projectName = '';
          this.projectOffsetIndex = 0;
          this.showCreateProject = true;
        })
      if (this.vm.currentProjectId > 0) {
        NavIcon({ name: 'Delete', iconSize: 16, symbolColor: $r('app.color.danger') })
          .width(30)
          .height(44)
          .borderRadius(15)
          .backgroundColor($r('app.color.card_inner_tint'))
          .enabled(!this.vm.planBusy && !this.vm.planLoading)
          .hoverEffect(HoverEffect.Highlight)
          .accessibilityText('删除当前养成计划')
          .accessibilityLevel('yes')
          .onClick(() => {
            this.confirmDeleteProject();
          })
      }
    }
    .width('100%')
    .bindSheet($$this.showCreateProject, this.createProjectSheet(), { height: '65%', showClose: true,
      backgroundColor: $r('app.color.sheet_material_tint'), systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  createProjectSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Text('新建养成计划').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        TextInput({ text: this.projectName, placeholder: '项目名称' }).maxLength(80)
          .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .onChange((value: string) => this.projectName = value)
        Text('服务器时区').fontSize(13).fontColor($r('app.color.text_secondary'))
        Select(this.selectOptions(GameCalendarRules.OFFSET_HOURS.map((offset: number): string => GameCalendarRules.offsetLabel(offset))))
          .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .selected(this.projectOffsetIndex).value(GameCalendarRules.offsetLabel(GameCalendarRules.OFFSET_HOURS[this.projectOffsetIndex]))
          .width('100%').onSelect((index: number) => this.projectOffsetIndex = index)
        Button($r('app.string.ui_setting_create_desktop_shortcut_action'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .width('100%').height(44)
          .enabled(this.projectName.trim().length > 0 && !this.vm.planBusy).onClick(() => this.createProject())
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }
  }

  private confirmDeleteProject(): void {
    const projectId: number = this.vm.currentProjectId;
    this.getUIContext().showAlertDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: '删除计划', message: '此项目的培养目标、备齐记录和库存将一并删除。',
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.ui_account_insights_delete'), action: (): void => {
        this.vm.deleteCurrentProject(projectId).then((message: string) => this.toast(message));
      } }
    });
  }

  private confirmRemoveEntry(entry: CultivateEntry): void {
    this.getUIContext().showAlertDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: '删除培养目标', message: `从当前项目移除「${this.vm.entryName(entry)}」？`,
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.ui_account_insights_delete'), action: (): void => {
        this.vm.removeEntry(entry).then((message: string) => this.toast(message));
      } }
    });
  }

  /** 条目内单个材料行（点击切换已备齐；已备齐划线置灰） */
  @Builder
  planItemRow(entry: CultivateEntry, item: CultivateEntryItem) {
    Row({ space: 8 }) {
      Text(item.finished ? '✓' : '○')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.finished ? $r('app.color.success') : $r('app.color.text_secondary'))
        .width(24)
      MetaIcon({ category: 'ItemIcon', name: item.icon, iconSize: 30 })
      Text(this.vm.materialName(item))
        .fontSize(12)
        .fontColor(item.finished ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        .decoration({ type: item.finished ? TextDecorationType.LineThrough : TextDecorationType.None })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isTodayItem(item.itemId)) {
        Text($r('app.string.ui_travelers_diary_today'))
          .fontSize(9)
          .fontColor($r('app.color.notice_on'))
          .backgroundColor($r('app.color.notice_bg'))
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(6)
      }
      Text(`× ${item.count}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.finished ? $r('app.color.text_secondary') : $r('app.color.app_primary'))
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
    .enabled(!this.vm.planBusy && !this.vm.planLoading)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.vm.togglePlanItem(entry, item.id).then(() => {
      });
    })
  }

  /** 单个培养条目卡（角色 + 等级目标 + 材料勾选清单） */
  @Builder
  planEntryCard(entry: CultivateEntry) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          if (entry.icon.length > 0) {
            if (entry.icon.startsWith('http')) {
              Image(entry.icon)
                .width(40)
                .height(40)
                .objectFit(ImageFit.Cover)
                .borderRadius(20)
            } else {
              MetaIcon({ category: entry.avatarId >= 10000000 ? 'AvatarIcon' : 'EquipIcon', name: entry.icon, iconSize: 40 })
                .borderRadius(20)
                .clip(true)
            }
          } else if (WikiMetaService.iconOfAvatar(entry.avatarId).length > 0) {
            MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(entry.avatarId), iconSize: 40 })
              .borderRadius(20)
              .clip(true)
          } else {
            Text(entry.name.length > 0 ? entry.name.substring(0, 1) : '◇')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent'))
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .borderRadius(20)
              .backgroundColor($r('app.color.app_primary'))
          }
        }
        Column({ space: 2 }) {
          Text(this.vm.entryName(entry))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(`Lv.${entry.level} → Lv.${entry.targetLevel} · 已备齐 ${entry.finishedCount()}/${entry.items.length}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button($r('app.string.ui_action_edit'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44).fontSize(12)
          .enabled(!this.vm.planBusy && !this.vm.planLoading)
          .onClick(() => this.editEntry(entry))
        Text($r('app.string.ui_account_insights_delete'))
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(9)
          .backgroundColor($r('app.color.card_inner_tint'))
          .enabled(!this.vm.planBusy && !this.vm.planLoading)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.confirmRemoveEntry(entry))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(entry.inputJson.length > 0 ? '完整目标已保存，可编辑或重新同步当前进度' : '旧计划：需重新确认完整输入')
        .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      Divider()
        .color($r('app.color.divider'))
      ForEach(entry.items, (item: CultivateEntryItem) => {
        this.planItemRow(entry, item)
      }, (item: CultivateEntryItem) => `pe_${item.id}_${item.finished}_t${this.isTodayItem(item.itemId) ? 1 : 0}_${this.vm.materialName(item)}`)
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  /** 树脂统计表头（树脂图标已内置 rawfile；脆弱树脂无图标用文字） */
  @Builder
  resinHeaderRow() {
    Row({ space: 6 }) {
      Text('类别')
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      Row({ space: 2 }) {
        MetaIcon({ category: 'ItemIcon', name: 'UI_ItemIcon_106', iconSize: 12 })
        Text('树脂')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(58)
      Text('脆弱')
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .width(44)
        .textAlign(TextAlign.Center)
      Text('天数')
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .width(48)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  /** 树脂统计单行（单参数 @Builder，按引用传递可动态渲染） */
  @Builder
  resinRow(row: ResinCategoryRow) {
    Row({ space: 6 }) {
      Column({ space: 1 }) {
        Text(row.title)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.demandText)
          .fontSize(9)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(`${row.totalResin}`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_primary_text'))
        .width(58)
        .textAlign(TextAlign.Center)
      Text(row.fragileResin > 0 ? `${row.fragileResin}` : '—')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width(44)
        .textAlign(TextAlign.Center)
      Text(`${row.days}天`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width(48)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /** 树脂换算统计卡（对齐 Windows 统计区：分类 × 总树脂 × 脆弱树脂 × 自然恢复天数） */
  @Builder
  resinSection() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('树脂统计')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text($r('app.string.ui_cultivation_material_list_world_level_title'))
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
        ForEach([5, 6, 7, 8, 9], (lv: number) => {
          Text(`${lv}`)
            .fontSize(10)
            .fontColor(this.vm.resinWorldLevel === lv ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
            .width(24)
            .height(20)
            .textAlign(TextAlign.Center)
            .borderRadius(10)
            .backgroundColor(this.vm.resinWorldLevel === lv
              ? $r('app.color.app_primary') : $r('app.color.card_inner_tint'))
            .border({ width: 1, color: this.vm.resinWorldLevel === lv
              ? $r('app.color.app_primary') : $r('app.color.divider') })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.vm.setResinWorldLevel(lv).then(() => {
              });
            })
        }, (lv: number) => `resin_wl_${lv}_${this.vm.resinWorldLevel === lv ? 1 : 0}`)
      }
      .width('100%')
      if (this.hasResinRows()) {
        Row({ space: 8 }) {
          Text(`共需树脂 ${this.resinTotalResin()}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary_text'))
          Text(`脆弱 ×${this.resinTotalFragile()}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Text(`自然恢复约 ${this.resinTotalDays()} 天`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Blank()
        }
        .width('100%')
        this.resinHeaderRow()
        ForEach(this.resinRows(), (row: ResinCategoryRow) => {
          this.resinRow(row)
        }, (row: ResinCategoryRow) => `resin_row_${row.kind}_${row.totalResin}_${row.runs}`)
      } else {
        Text('当前计划无需额外树脂')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  private async importInventoryFile(): Promise<void> {
    const projectId: number = this.vm.currentProjectId;
    try {
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) { throw new Error('页面尚未就绪'); }
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json'];
      const files: string[] = await documentPicker.select(options);
      if (files.length === 0 || !this.attached) { return; }
      if (projectId !== this.vm.currentProjectId) { throw new Error('养成项目已切换，请重新导入'); }
      const file: fileIo.File = fileIo.openSync(files[0], fileIo.OpenMode.READ_ONLY);
      let text: string = '';
      try {
        const size: number = fileIo.statSync(file.fd).size;
        if (size > 16 * 1024 * 1024) { throw new Error('库存文件超过 16 MB'); }
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        if (fileIo.readSync(file.fd, buffer) !== size) { throw new Error('库存文件读取不完整'); }
        text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
      } finally { fileIo.closeSync(file.fd); }
      this.finishPlanAction(await this.vm.importInventoryText(projectId, text));
    } catch (e) { if (this.attached) { this.toast((e as Error).message); } }
  }

  private openMaterialSheet(editable: boolean): void {
    this.editInventory = editable;
    this.materialQuery = '';
    this.inventoryEditId = 0;
    this.inventoryCountText = '';
    this.refreshMaterials();
    this.showInventory = true;
  }

  private refreshMaterials(): void {
    const query: string = this.materialQuery.trim().toLocaleLowerCase();
    const rows: InventoryMaterialView[] = this.vm.inventoryRows.filter((row: InventoryMaterialView): boolean =>
      (this.editInventory || row.planned > 0) &&
      (query.length === 0 || row.name.toLocaleLowerCase().includes(query) || String(row.itemId).includes(query)));
    rows.sort((left: InventoryMaterialView, right: InventoryMaterialView): number => {
      if (!this.editInventory && this.incompleteFirst && (left.shortfall > 0) !== (right.shortfall > 0)) {
        return left.shortfall > 0 ? -1 : 1;
      }
      if (!this.editInventory && left.availableToday !== right.availableToday) { return left.availableToday ? -1 : 1; }
      return left.itemId - right.itemId;
    });
    this.materialRowCount = rows.length;
    this.inventorySource.notifyDataReload(rows);
  }

  private finishPlanAction(message: string): void {
    if (!this.attached) { return; }
    this.refreshMaterials();
    this.toast(message);
  }

  private async saveInventoryCount(): Promise<void> {
    if (!/^\d+$/.test(this.inventoryCountText.trim())) { this.toast('请输入非负整数数量'); return; }
    const message: string = await this.vm.setInventoryCount(
      this.vm.currentProjectId, this.inventoryEditId, Number(this.inventoryCountText));
    this.finishPlanAction(message);
  }

  @Builder
  inventorySection() {
    Flex({ wrap: FlexWrap.Wrap }) {
      Button('材料统计', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .fontSize(12).height(44).margin({ right: 6, bottom: 4 })
        .enabled(this.vm.currentProjectId > 0 && !this.vm.planLoading && !this.vm.planBusy)
        .onClick(() => this.openMaterialSheet(false))
      Button('管理库存', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .fontSize(12).height(44).margin({ right: 6, bottom: 4 })
        .enabled(this.vm.currentProjectId > 0 && !this.vm.planLoading && !this.vm.planBusy)
        .onClick(() => this.openMaterialSheet(true))
      if (this.isLoggedIn && this.vm.planEntries.length > 0) {
        Button('同步角色信息', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12).height(44).margin({ bottom: 4 })
          .enabled(this.currentUid.length > 0 && !this.vm.planLoading && !this.vm.planBusy)
          .onClick(() => this.vm.syncProjectProgress().then((message: string) => this.finishPlanAction(message)))
      }
    }
    .width('100%')
    .bindSheet($$this.showInventory, this.materialSheet(), { height: '85%', showClose: true, dragBar: true,
      backgroundColor: $r('app.color.sheet_material_tint'), systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  inventoryMaterialRow(row: InventoryMaterialView) {
    Row({ space: 10 }) {
      MetaIcon({ category: 'ItemIcon', name: row.icon, iconSize: 36 })
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(row.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (row.availableToday && !this.editInventory) {
            Text('今日可刷').fontSize(11).fontColor($r('app.color.app_primary_text'))
          }
        }
        .width('100%')
        Text(this.editInventory ? `#${row.itemId} · 持有 ${row.known ? row.current : '未知'}`
          : `总计 ${row.planned} · 持有 ${row.known ? row.current : '未知'} · 缺 ${row.shortfall}`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.editInventory) { Text($r('app.string.ui_action_edit')).fontSize(12).fontColor($r('app.color.app_primary_text')) }
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .hoverEffect(this.editInventory ? HoverEffect.Highlight : HoverEffect.None)
    .onClick(() => {
      if (this.editInventory && !this.vm.planBusy) {
        this.inventoryEditId = row.itemId;
        this.inventoryCountText = row.known ? String(row.current) : '';
      }
    })
  }

  @Builder
  materialSheet() {
    Column({ space: 10 }) {
      Text(this.editInventory ? '项目库存' : '材料统计')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      if (this.editInventory) {
        Flex({ wrap: FlexWrap.Wrap }) {
          Button($r('app.string.ui_action_import'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .fontSize(12).height(44).margin({ right: 6, bottom: 4 })
            .onClick(() => this.importInventoryFile())
          if (this.isLoggedIn) {
            Button('计算器同步', { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .fontSize(12).height(44).margin({ right: 6, bottom: 4 })
              .enabled(this.currentUid.length > 0)
              .onClick(() => this.vm.syncInventory().then((message: string) => this.finishPlanAction(message)))
          }
          Button('从背包档案同步', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .fontSize(12).height(44).margin({ right: 6, bottom: 4 })
            .onClick(() => this.chooseInventoryBackpack())
          Button('清空库存', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .fontSize(12).height(44).margin({ bottom: 4 })
            .fontColor($r('app.color.danger')).onClick(() => this.confirmClearInventory())
        }
        .width('100%')
        .enabled(!this.vm.planBusy && !this.vm.planLoading)
        if (this.inventoryEditId > 0) {
          Row({ space: 6 }) {
            Text(`#${this.inventoryEditId}`).fontSize(12).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.inventoryCountText, placeholder: '持有数量' }).type(InputType.Number).layoutWeight(1)
              .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
              .onChange((value: string) => this.inventoryCountText = value)
              .onSubmit(() => this.saveInventoryCount())
            Button($r('app.string.ui_action_save'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
              .height(44).fontSize(12).onClick(() => this.saveInventoryCount())
          }
          .width('100%')
          .enabled(!this.vm.planBusy)
        }
      } else {
        Row({ space: 5 }) {
          Checkbox({ name: 'cultivation-incomplete' }).select(this.incompleteFirst).onChange((value: boolean) => {
            this.incompleteFirst = value;
            this.refreshMaterials();
          })
          Text('未备齐优先').fontSize(13).fontColor($r('app.color.text_secondary'))
        }
      }
      Search({ value: this.materialQuery, placeholder: '搜索材料名称或 ID' })
        .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .onChange((value: string) => { this.materialQuery = value; this.refreshMaterials(); })
      if (this.materialRowCount === 0) {
        Text(this.materialQuery.length > 0 ? '没有匹配的材料' : '当前项目暂无所需材料')
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          .textAlign(TextAlign.Center).padding(20)
      } else {
        List({ space: 6 }) {
          LazyForEach(this.inventorySource, (row: InventoryMaterialView) => {
            ListItem() { this.inventoryMaterialRow(row) }
          }, (row: InventoryMaterialView): string =>
            `${row.itemId}:${row.planned}:${row.shortfall}:${row.known}:${row.current}:${row.availableToday}:${row.name}`)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(5)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 18 })
    .alignItems(HorizontalAlign.Start)
  }

  private confirmClearInventory(): void {
    const projectId: number = this.vm.currentProjectId;
    this.getUIContext().showAlertDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: '清空项目库存', message: '清空当前项目的所有材料库存？',
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.ui_action_clear'), action: (): void => {
        if (this.attached) { this.vm.clearInventory(projectId).then((message: string) => this.finishPlanAction(message)); }
      } }
    });
  }

  private async chooseInventoryBackpack(): Promise<void> {
    const projectId: number = this.vm.currentProjectId;
    try {
      const archives: BackpackArchive[] = await this.vm.getBackpackArchives();
      if (!this.attached || projectId !== this.vm.currentProjectId) { return; }
      if (archives.length === 0) { this.toast('请先创建背包档案'); return; }
      const sheets: SheetInfo[] = archives.map((archive: BackpackArchive): SheetInfo => {
        const sheet: SheetInfo = { title: `${archive.name} · ${archive.uid}`, action: (): void => {
          if (this.attached) {
            this.vm.syncBackpackInventory(archive.id, projectId).then((message: string) => this.finishPlanAction(message));
          }
        } };
        return sheet;
      });
      this.getUIContext().showActionSheet({ systemMaterial: UiSurface.dialogMaterial(),
        title: '选择背包档案', message: '用所选档案的养成材料替换当前项目库存。',
        sheets: sheets, confirm: { value: $r('app.string.common_cancel'), action: (): void => {} }
      });
    } catch (e) { if (this.attached) { this.toast((e as Error).message); } }
  }

  private filteredPlanEntries(): CultivateEntry[] {
    return this.vm.filteredEntries(this.effectivePlanTokens());
  }

  private hasPlanToken(token: CultivationFilterToken): boolean {
    const key: string = token.key();
    return this.planTokens.some((selected: CultivationFilterToken): boolean => selected.key() === key);
  }

  private effectivePlanTokens(): CultivationFilterToken[] {
    if (this.planTokens.length >= CultivationFilterToken.LIMIT) { return this.planTokens; }
    const draft: CultivationFilterToken = new CultivationFilterToken(CultivationFilterKind.Name, this.planSearch);
    return draft.value.length > 0 && !this.hasPlanToken(draft) ? this.planTokens.concat([draft]) : this.planTokens;
  }

  private setPlanToken(token: CultivationFilterToken, selected: boolean): void {
    if (!selected) {
      const key: string = token.key();
      this.planTokens = this.planTokens.filter((item: CultivationFilterToken): boolean => item.key() !== key);
    } else if (this.effectivePlanTokens().length < CultivationFilterToken.LIMIT && !this.hasPlanToken(token)) {
      this.planTokens = this.planTokens.concat([token]);
    }
  }

  private commitPlanSearch(value: string): void {
    const token: CultivationFilterToken = new CultivationFilterToken(CultivationFilterKind.Name, value);
    if (token.value.length === 0) { return; }
    if (!this.hasPlanToken(token)) {
      if (this.planTokens.length >= CultivationFilterToken.LIMIT) { return; }
      this.planTokens = this.planTokens.concat([token]);
    }
    this.planSearch = '';
  }

  private clearPlanFilters(): void {
    this.planSearch = '';
    this.planTokens = [];
  }

  @Builder
  planTokenMenu(kind: CultivationFilterKind) {
    Menu() {
      ForEach(CultivationFilterToken.options(kind), (value: string) => {
        MenuItem({ content: this.planTokenLabel(new CultivationFilterToken(kind, value)) })
          .selected(this.hasPlanToken(new CultivationFilterToken(kind, value)))
          .selectIcon(true)
          .enabled(this.hasPlanToken(new CultivationFilterToken(kind, value)) ||
            this.effectivePlanTokens().length < CultivationFilterToken.LIMIT)
          .onChange((selected: boolean): void => this.setPlanToken(new CultivationFilterToken(kind, value), selected))
      }, (value: string): string => `${kind}_${value}`)
    }
  }

  @Builder
  planFilterMenuButton(kind: CultivationFilterKind, label: ResourceStr) {
    Button(label, { type: ButtonType.Normal })
      .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
      .height(44).margin({ right: 6, bottom: 6 })
      .bindMenu(() => { this.planTokenMenu(kind) }, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  planFilters() {
    Row({ space: 8 }) {
      Search({ value: this.planSearch, placeholder: '搜索培养目标' })
        .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .layoutWeight(1)
        .enabled(this.planTokens.length < CultivationFilterToken.LIMIT)
        .searchButton($r('app.string.ui_settings_page_label_add_profile'),
          { fontSize: 13, fontColor: $r('app.color.app_primary_text') })
        .onChange((value: string): void => { this.planSearch = value; })
        .onSubmit((value: string): void => this.commitPlanSearch(value))
      Button(this.showPlanFilters ? $r('app.string.ui_info_bar_panel_contract_content') :
        (this.effectivePlanTokens().length > 0 ? $r('app.string.ui_filter_count', this.effectivePlanTokens().length)
          : $r('app.string.ui_filter')), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .fontSize(12).height(44)
        .onClick(() => this.showPlanFilters = !this.showPlanFilters)
    }.width('100%')
    if (this.effectivePlanTokens().length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.planTokens, (token: CultivationFilterToken) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              Text(this.planTokenLabel(token)).fontSize(12).fontColor($r('app.color.text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
              Text('×').fontSize(13).fontColor($r('app.color.text_secondary')).accessibilityLevel('no')
            }
          }
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44).constraintSize({ maxWidth: 240 }).margin({ right: 6, bottom: 6 })
          .accessibilityGroup(true).accessibilityDescription('移除此筛选条件')
          .onClick(() => this.setPlanToken(token, false))
        }, (token: CultivationFilterToken): string => token.key())
        Button($r('app.string.ui_clear_filters'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44).fontSize(12).fontColor($r('app.color.app_primary_text')).backgroundColor(Color.Transparent)
          .hoverEffect(HoverEffect.Highlight).onClick(() => this.clearPlanFilters())
      }.width('100%')
    }
    if (this.showPlanFilters) {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.planFilterMenuButton(CultivationFilterKind.Target, '目标类型')
        this.planFilterMenuButton(CultivationFilterKind.Quality, $r('app.string.ui_backpack_sort_quality'))
        this.planFilterMenuButton(CultivationFilterKind.Weapon, '武器类型')
        this.planFilterMenuButton(CultivationFilterKind.Element, '元素')
        Text(`${this.effectivePlanTokens().length}/${CultivationFilterToken.LIMIT}`)
          .height(44).fontSize(12).fontColor($r('app.color.text_secondary'))
      }.width('100%')
    }
  }

  /** 养成计划区（项目条 + 条目清单；置于计算区上方，可持续追踪） */
  @Builder
  planSection() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        NavIcon({ name: 'Cultivation', iconSize: 20 })
        Text($r('app.string.ui_nav_cultivation'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.vm.planEntries.length} 个目标`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      this.projectBar()
      if (this.vm.currentProjectId > 0) {
        Text(GameCalendarRules.offsetLabel(this.vm.currentProjectOffset()))
          .fontSize(11).fontColor($r('app.color.text_secondary'))
        this.inventorySection()
        this.resinSection()
      }
      if (this.vm.message.length > 0) {
        Text(this.vm.message).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.planMessage.length > 0) {
        Text(this.vm.planMessage).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.planLoading || this.vm.planBusy) {
        Text('正在更新项目…').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      if (this.vm.planEntries.length === 0 && !this.vm.planLoading) {
        Text('暂无培养目标，可选择角色后编辑并保存目标。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .textAlign(TextAlign.Center)
      } else if (this.vm.planEntries.length > 0) {
        this.planFilters()
        if (this.filteredPlanEntries().length === 0) {
          Text('没有匹配的培养目标').fontSize(12).fontColor($r('app.color.text_secondary')).padding(8)
        }
        ForEach(this.filteredPlanEntries(), (entry: CultivateEntry) => {
          this.planEntryCard(entry)
        }, (entry: CultivateEntry) =>
          `plan_${entry.id}_${entry.finishedCount()}_${entry.inputJson}_${entry.items.length}_${this.vm.materialLabelVersion}_${this.vm.entryName(entry)}`)
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  /** 计算结果材料汇总 */
  @Builder
  resultSection() {
    if (this.vm.result !== undefined && this.vm.result.overallConsume.length > 0) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'Cultivation', iconSize: 20 })
          Text('所需材料汇总')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(`${this.vm.selectedCount} 个角色`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        ForEach(this.vm.result.overallConsume, (item: CalItem) => {
          this.materialRow(item)
        }, (item: CalItem) => `cal_item_${item.id}`)
      }
      .width('100%')
      .padding(14)
      .borderRadius($r('app.float.card_radius'))
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .border({ width: 1, color: $r('app.color.card_stroke') })
    }
  }

  /** 宽屏左栏：养成计划（项目/树脂统计/条目） */
  @Builder
  planColumn() {
    Column({ space: 10 }) {
      this.planSection()
    }
    .width('100%')
  }

  /** 右栏（窄屏下半区）：计算操作 + 结果 + 候选角色 */
  @Builder
  computeColumn() {
    Column({ space: 8 }) {
      Text(this.isLoggedIn ? '勾选角色后编辑各自的等级、突破与三项天赋目标' : '离线规划：默认从 1 级开始，可手动修改当前进度')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Button(`编辑目标并预览 · 已选 ${this.vm.selectedCount}`, { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
        .height(44).width('100%')
        .enabled(this.vm.selectedCount > 0 && !this.draftVm.busy)
        .onClick(() => this.editSelected())
    }.width('100%').padding(14).borderRadius(12).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))

    // 候选角色网格
    Row() {
      Text('选择角色')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(`共 ${this.vm.targets.length} 名`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')

    Column({ space: 8 }) {
      if (this.vm.loading) {
        Text('正在刷新角色列表，已有计划保持不变').fontSize(12).fontColor($r('app.color.text_secondary'))
      } else if (this.vm.targets.length === 0) {
        Text('暂无可用角色；仍可查看和编辑已保存计划').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      ForEach(this.vm.targets, (target: CultivateTarget, idx: number) => {
        this.targetRow(target, idx)
        // 键必须包含会变的字段（AGENTS @Builder 规则）：仅 avatarId 时 toggle 重赋值 targets 后
        // 键不变 → ForEach 复用旧组件、targetRow 不重建，选中态（圆点/勾选/高亮）永不刷新
      }, (target: CultivateTarget) => `cult_${target.avatarId}_${target.selected ? 1 : 0}_${target.targetLevel}_${target.targetSkillLevel}_${target.targetWeaponLevel}_${target.name}`)
    }
    .width('100%')
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
      this.header()
      if (this.vm.loading && this.vm.targets.length === 0 && this.vm.projects.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.app_primary'))
          Text($r('app.string.ui_common_loading'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 80, bottom: 80 })
      } else {
        Scroll() {
          if (this.isWide) {
            // 宽屏双栏：左计划 / 右计算（内容区宽 >=840，对齐页面断点规范）
            Row({ space: 10 }) {
              Column() {
                this.planColumn()
              }
              .layoutWeight(1)

              Column() {
                this.computeColumn()
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column({ space: 10 }) {
              this.planColumn()
              this.computeColumn()
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showDraft, this.draftSheet(), { height: '90%', showClose: true, dragBar: true,
      onDisappear: (): void => { this.draftVm.cancel(); }, backgroundColor: $r('app.color.sheet_material_tint'),
      systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
    .backgroundColor(Color.Transparent)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.isWide = (newValue.width as number) >= 840;
    })
    }
    .width('100%')
    .height('100%')
  }
}
