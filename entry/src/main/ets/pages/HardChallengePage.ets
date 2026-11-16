/**
 * HardChallengePage.ets（@Entry）
 * 幽境危战：档位切换（单挑/多人）、难度档 Segmented、各挑战卡（名称/用时/队内角色/最佳角色/怪物、挑战项）。
 * 数据源：hard_challenge 接口（need_detail=true）。
 */
import { router, LengthMetrics } from '@kit.ArkUI';
import { HardChallengeViewModel } from '../viewmodel/HardChallengeViewModel';
import { HardChallengeChallenge, HardChallengeSimpleAvatar, HardChallengeBestAvatar, HardChallengeMonsterTag, HardChallengeDataEntry } from '../model/HardChallenge';
import { ChallengePeriod } from '../model/ChallengePeriod';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { PageToolbar } from '../components/PageToolbar';
import { ChallengePeriodActions, ChallengePeriodRail, ChallengePeriodTabs } from '../components/ChallengePeriodRail';
import { NavIcon } from '../components/NavIcon';
import { AssetIcon } from '../components/AssetIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { WikiMetaService } from '../service/WikiMetaService';
import { MetaIcon } from '../components/MetaIcon';
import { PageBackdrop } from '../components/PageBackdrop';
import { Logger } from '../common/Logger';
import { AppButtonModifier, CardSurfaceModifier, UiSurface } from '../common/UiSurface';

@Entry
@Component
export struct HardChallengePage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('helpLocaleVersion') @Watch('loadIcons') localeVersion: number = 0;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageProp('currentUserId') @Watch('onOwnerChanged') ownerId: number = 0;
  @StorageProp('isLoggedIn') @Watch('onOwnerChanged') isLoggedIn: boolean = false;
  @State vm: HardChallengeViewModel = new HardChallengeViewModel();
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;
  @State isWide: boolean = false;
  @State challengeColumns: number = 1;
  @State iconRevision: number = 0;
  @State detailOpen: boolean = false;
  @State showStatistics: boolean = false;
  @State pendingPeriodId: number = 0;
  private readonly detailScroller: Scroller = new Scroller();
  /** 档位：0=单挑 1=联机（页面 @State 驱动刷新） */
  @State modeIndex: number = 0;
  /** 当前档位 DataEntry 快照（页面 @State：档位切换/加载完成后显式同步，避免 @Observed 深层不刷新） */
  @State currentEntry: HardChallengeDataEntry = new HardChallengeDataEntry();
  private attached: boolean = false;
  private ownerTimer: number = -1;
  private iconSequence: number = 0;

  onOwnerChanged(): void {
    if (!this.attached) { return; }
    this.vm.invalidate();
    this.vm = new HardChallengeViewModel();
    this.showVerify = false;
    this.showPeriods();
    this.pendingPeriodId = 0;
    this.syncEntry();
    clearTimeout(this.ownerTimer);
    this.ownerTimer = setTimeout((): void => { this.loadData(); }, 0);
  }

  aboutToAppear(): void {
    this.attached = true;
    this.loadData();
  }

  aboutToDisappear(): void {
    this.attached = false;
    clearTimeout(this.ownerTimer);
    this.iconSequence++;
    this.vm.invalidate();
  }

  /** 页面显示：检测风控 → 自动弹验证窗（保持当前页上下文） */
  onPageShow(): void {
    if (this.vm.needRiskVerify && !this.showVerify) {
      this.showVerify = true;
      return;
    }
    if (RiskUiHelper.hasPendingChallenge()) {
      this.refreshData(false);
    }
  }

  loadData(): void {
    this.loadIcons();
    const vm: HardChallengeViewModel = this.vm;
    vm.initialize(this.currentUid).then((): void => {
      if (this.attached && this.vm === vm) { this.syncEntry(); }
    });
  }

  private loadIcons(): void {
    if (!this.attached) { return; }
    const vm: HardChallengeViewModel = this.vm;
    const sequence: number = ++this.iconSequence;
    WikiMetaService.ensureIconMaps().then((): void => {
      if (this.attached && this.vm === vm && sequence === this.iconSequence) { this.iconRevision++; }
    }).catch((): void => { Logger.warn('HardChallengePage', 'local avatar icons unavailable'); });
  }

  private onChallengeAreaChange(width: number): void {
    if (Number.isFinite(width) && width > 0) { this.challengeColumns = Math.min(3, Math.max(1, Math.floor((width + 10) / 270))); }
  }

  private showMonsterDetails(challenge: HardChallengeChallenge): void {
    const description: string = WikiMetaService.cleanText(challenge.monster.desc);
    if (description.length === 0) { return; }
    this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
      title: challenge.monster.name || challenge.name, message: description,
      buttons: [{ text: '关闭', color: $r('app.color.text_primary') }],
    }).catch((): void => {});
  }

  private damageIcon(best: HardChallengeBestAvatar): string {
    return WikiMetaService.sideIconOfAvatar(best.avatarId) || best.image ||
      WikiMetaService.iconOfAvatar(best.avatarId) || WikiMetaService.iconOfAvatarName(best.name);
  }

  private refreshData(announce: boolean): void {
    const vm: HardChallengeViewModel = this.vm;
    vm.load(this.currentUid).then((): void => {
      if (!this.attached || this.vm !== vm) { return; }
      this.syncEntry();
      if (vm.needRiskVerify) { this.showVerify = true; }
      else if (announce) { this.toast(vm.message.length > 0 ? vm.message : '已刷新'); }
    });
  }

  /** 同步当前档位快照（VM 加载/档位切换后调用） */
  syncEntry(): void {
    this.modeIndex = this.vm.modeIndex;
    this.currentEntry = this.vm.entryOf(this.modeIndex);
    Logger.info('HC', `syncEntry mode=${this.modeIndex} hasData=${this.currentEntry.hasData} challenges=${this.currentEntry.challenges.length}`);
  }

  /** 档位切换：更新页面快照（VM 层同步切换） */
  switchMode(index: number): void {
    this.vm.selectMode(index);
    this.syncEntry();
  }

  @Builder
  modeChip(label: string, index: number) {
    Button(label, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
      .layoutWeight(1).height(44).fontSize(13).borderRadius(6)
      .fontColor(this.modeIndex === index ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
      .backgroundColor(this.modeIndex === index && this.vm.single.hasData && this.vm.mp.hasData
        ? $r('app.color.app_primary_bg') : Color.Transparent)
      .accessibilitySelected(this.modeIndex === index)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.switchMode(index))
  }

  @Builder
  modeSelector() {
    Row({ space: 2 }) {
      if (this.vm.single.hasData) { this.modeChip('单人挑战', 0) }
      if (this.vm.mp.hasData) { this.modeChip('联机挑战', 1) }
    }
    .width('100%')
    .padding(2)
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1800 });
  }

  private shownPeriodId(): number {
    return this.pendingPeriodId > 0 ? this.pendingPeriodId : (this.vm.scheduleId);
  }

  private scrollDetailToTop(): void {
    if (this.isWide || this.detailOpen || this.vm.history.length === 0) {
      this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
  }

  private selectPeriod(scheduleId: number): void {
    this.scrollDetailToTop();
    this.detailOpen = true;
    if (this.shownPeriodId() === scheduleId) { return; }
    this.pendingPeriodId = scheduleId;
    const vm: HardChallengeViewModel = this.vm;
    vm.loadFromHistory(this.currentUid, scheduleId).then((): void => {
      if (!this.attached || this.vm !== vm || this.pendingPeriodId !== scheduleId) { return; }
      this.pendingPeriodId = 0;
      this.syncEntry();
    });
  }

  private selectTab(statistics: boolean): void {
    this.scrollDetailToTop();
    this.showStatistics = statistics;
    if (statistics) { this.detailOpen = true; }
  }

  private showPeriods(): void {
    this.detailOpen = false;
    this.showStatistics = false;
  }

  onBackPress(): boolean {
    if (!this.isWide && this.detailOpen && this.vm.history.length > 0) {
      this.showPeriods();
      return true;
    }
    return false;
  }

  @Builder
  toolbarLeading() {
    if (!this.isLoggedIn) {
      Text($r('app.string.ui_nav_challenge')).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).maxLines(1)
    } else if (!this.isWide && this.detailOpen && this.vm.history.length > 0) {
      Button('‹ 期次', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(44).fontSize(13).fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent)
        .padding({ left: 6, right: 6 }).hoverEffect(HoverEffect.Highlight).accessibilityText('返回期次列表')
        .onClick(() => this.showPeriods())
      Text(this.showStatistics ? $r('app.string.ui_spiral_abyss_hutao_statistics') : '分期详情')
        .fontSize(13).fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    } else {
      ChallengePeriodTabs({ statistics: this.showStatistics,
        onSelect: (value: boolean): void => { this.selectTab(value); } })
    }
  }

  @Builder
  toolbarActions() {
    if (this.isLoggedIn) {
      ChallengePeriodActions({ split: this.isWide, refreshEnabled: this.currentUid.length > 0 && !this.vm.loading,
        detailOpen: this.detailOpen && this.vm.history.length > 0, statistics: this.showStatistics,
        onInsights: (): void => { router.pushUrl({ url: 'pages/AccountInsightsPage' }).catch(() => {}); },
        onRefresh: (): void => { this.refreshData(true); },
        onSwitchTab: (): void => { this.selectTab(!this.showStatistics); } })
    }
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'HardChallenge', iconSize: 60 })
      Text('需登录后查看幽境危战')
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
  avatarCircle(avatar: HardChallengeSimpleAvatar) {
    Column({ space: 3 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (WikiMetaService.iconOfAvatar(avatar.avatarId).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(avatar.avatarId), iconSize: 48, circular: true })
        } else if (WikiMetaService.iconOfAvatarName(avatar.name).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatarName(avatar.name), iconSize: 48, circular: true })
        } else if (avatar.image.startsWith('http')) {
          Image(avatar.image)
            .width(48)
            .height(48)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.app_primary_bg'))
      } else if (AssetIcon.elemName(avatar.element).length > 0) {
        Image(AssetIcon.resolve(AssetIcon.elemName(avatar.element)))
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.app_primary_bg'))
      } else {
        Text(avatar.name.length > 0 ? avatar.name.substring(0, 1) : '★')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_accent'))
          .width(48)
          .height(48)
          .textAlign(TextAlign.Center)
          .borderRadius(24)
          .backgroundColor($r('app.color.app_primary'))
      }
        // 命座角标（对齐 Windows AvatarView.ActivatedConstellationCount = Rank）
        if (avatar.rank > 0 && avatar.rank < 6) {
          Text(`${avatar.rank}命`)
            .fontSize(10)
            .fontColor($r('app.color.on_accent'))
            .padding({ left: 4, right: 4 })
            .borderRadius(6)
            .backgroundColor($r('app.color.image_scrim'))
            .translate({ x: -1, y: -1 })
        } else if (avatar.rank >= 6) {
          Text('6命')
            .fontSize(10)
            .fontColor($r('app.color.on_accent'))
            .padding({ left: 4, right: 4 })
            .borderRadius(6)
            .backgroundColor($r('app.color.app_primary'))
            .translate({ x: -1, y: -1 })
        }
      }
      Text(avatar.name.length > 4 ? `${avatar.name.substring(0, 4)}…` : avatar.name)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  challengeCard(challenge: HardChallengeChallenge) {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
        if (challenge.monster.icon.startsWith('https://')) {
          Image(challenge.monster.icon).width(64).height(64).borderRadius(8).objectFit(ImageFit.Contain)
        } else if (challenge.monster.icon.length > 0) {
          MetaIcon({ category: 'MonsterIcon', name: challenge.monster.icon, iconSize: 64 })
        } else {
          NavIcon({ name: 'HardChallenge', iconSize: 44 })
        }
        Column({ space: 4 }) {
          Text(challenge.monster.name || challenge.name)
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (challenge.monster.level > 0) {
            Text(`Lv. ${challenge.monster.level}`).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ minHeight: 66 })
      .focusable(true).hoverEffect(HoverEffect.Highlight)
      .accessibilityDescription('点击查看强敌机制').onClick(() => this.showMonsterDetails(challenge))

      Row() {
        Text('战斗用时').fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(HardChallengePage.formatSeconds(challenge.second)).fontSize(13).fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding(8)
      .border({ width: 1, radius: 6, color: $r('app.color.card_stroke') })

      if (challenge.teams.length > 0) {
        GridRow({ columns: 4, gutter: 4 }) {
          ForEach(challenge.teams[0].avatars, (avatar: HardChallengeSimpleAvatar, index: number) => {
            GridCol() { this.teamAvatar(avatar) }
          }, (avatar: HardChallengeSimpleAvatar, index: number): string => `${index}_${avatar.avatarId}`)
        }.width('100%')
      }

      ForEach(challenge.bestAvatars, (best: HardChallengeBestAvatar) => {
        this.damageRow(best)
      }, (best: HardChallengeBestAvatar, index: number): string => `${index}_${best.avatarId}_${best.type}`)

      if (challenge.monster.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(4), cross: LengthMetrics.vp(4) } }) {
          ForEach(challenge.monster.tags, (tag: HardChallengeMonsterTag) => {
            Text(WikiMetaService.cleanText(tag.desc)).fontSize(10).fontColor($r('app.color.notice_on'))
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .border({ width: 1, radius: 5, color: $r('app.color.divider') })
          }, (tag: HardChallengeMonsterTag): string => `${tag.type}_${tag.desc}`)
        }.width('100%')
      }
    }
    .width('100%')
    .padding(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  teamAvatar(avatar: HardChallengeSimpleAvatar) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (WikiMetaService.iconOfAvatar(avatar.avatarId).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(avatar.avatarId), iconSize: 48 })
        } else if (avatar.image.startsWith('https://')) {
          Image(avatar.image).width(48).height(48).objectFit(ImageFit.Cover)
        } else {
          NavIcon({ name: 'AvatarProperty', iconSize: 28 })
        }
        if (avatar.rank >= 0) {
          Text(`${Math.min(6, avatar.rank)}`).fontSize(10).fontColor($r('app.color.on_accent')).padding({ left: 3, right: 3 })
            .borderRadius(4).backgroundColor($r('app.color.image_scrim'))
        }
      }.width(48).height(48).borderRadius(5).clip(true)
        .backgroundColor(avatar.rarity >= 5 ? $r('app.color.five_star') : $r('app.color.four_star'))
      Text(WikiMetaService.nameOfAvatarId(avatar.avatarId) || avatar.name).fontSize(10).width('100%').textAlign(TextAlign.Center)
        .fontColor($r('app.color.text_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  damageRow(best: HardChallengeBestAvatar) {
    Row({ space: 5 }) {
      if (this.damageIcon(best).length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: this.damageIcon(best), iconSize: 36 })
      }
      Text(HardChallengePage.bestTypeLabel(best.type))
        .fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${best.value}`).fontSize(13).fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding(7)
    .border({ width: 1, radius: 6, color: $r('app.color.card_stroke') })
  }

  private difficultyIcon(): string {
    const parts: string[] = this.currentEntry.best.icon.split(',');
    return parts[parts.length - 1].trim();
  }

  @Builder
  difficultyView() {
    Row({ space: 8 }) {
      if (this.difficultyIcon().startsWith('https://')) {
        Image(this.difficultyIcon()).width(38).height(38).objectFit(ImageFit.Contain)
      } else {
        NavIcon({ name: 'HardChallenge', iconSize: 36 })
      }
      Column({ space: 3 }) {
        Text(this.difficultyTitle()).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        if (this.currentEntry.best.second > 0) {
          Text(HardChallengePage.formatSeconds(this.currentEntry.best.second))
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
  }

  @Builder
  blingSection() {
    if (this.vm.blings.length > 0) {
      Column({ space: 8 }) {
        Text('耀金角色').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.vm.blings, (avatar: HardChallengeSimpleAvatar) => {
            this.avatarCircle(avatar)
          }, (avatar: HardChallengeSimpleAvatar): string => `${avatar.avatarId}_${this.iconRevision}`)
        }.width('100%')
      }
      .width('100%')
      .padding(10)
      .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  popularityCard() {
    Column({ space: 8 }) {
      Row() {
        Text('当前人气角色')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button(this.vm.popularityLoading ? $r('app.string.ui_common_loading') : $r('app.string.common_refresh'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).constraintSize({ minHeight: 44 })
          .fontSize(12)
          .enabled(!this.vm.popularityLoading)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => { this.vm.loadPopularity(this.currentUid); })
      }.width('100%')
      if (this.vm.popularityError.length > 0) {
        Text(this.vm.popularityError).fontSize(12).fontColor($r('app.color.text_secondary'))
      } else if (!this.vm.popularityLoading && this.vm.popularity.length === 0) {
        Text('暂无人气角色数据').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.vm.popularity, (avatar: HardChallengeSimpleAvatar) => {
          this.avatarCircle(avatar)
        }, (avatar: HardChallengeSimpleAvatar) => `hc_pop_${avatar.avatarId}_${avatar.image}_${this.iconRevision}`)
      }.width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  periodPanels() {
    Row() {
      if (this.vm.history.length > 0 && (this.isWide || !this.detailOpen)) {
        ChallengePeriodRail({ periods: this.vm.history, selectedId: this.shownPeriodId(), split: this.isWide, showNames: true,
          onSelect: (scheduleId: number): void => { this.selectPeriod(scheduleId); } })
      }
      if (this.isWide || this.detailOpen || this.vm.history.length === 0) {
        Scroll(this.detailScroller) {
          Column({ space: 10 }) {
            this.periodDetail()
          }
          .width('100%')
          .padding(12)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(VerticalAlign.Top)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
    .clip(true)
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column({ space: 10 }) {
        PageToolbar({ embedMode: this.embedMode, leading: (): void => this.toolbarLeading(), trailing: (): void => this.toolbarActions() })
        if (!this.isLoggedIn) {
          this.loginGuide()
        } else {
          this.periodPanels()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: this.embedMode ? 8 : 0, bottom: 12 })
      .onAreaChange((_old: Area, area: Area): void => { this.isWide = Number(area.width) >= 840; })
      .bindSheet(this.showVerify, () => {
        RiskVerifyDialog({
          isShow: this.showVerify,
          gt: this.vm.riskGt,
          challenge: this.vm.riskChallenge,
          path: this.vm.riskPath,
          onDone: (challenge: string): void => {
            AppStorage.setOrCreate<string>(RiskUiHelper.KEY_PENDING, challenge);
            this.refreshData(false);
          },
        })
      }, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel), height: 420,
        backgroundColor: $r('app.color.sheet_material_tint'), showClose: false, blurStyle: BlurStyle.Regular })
    }
    .width('100%')
    .height('100%')
  }

  private static bestTypeLabel(type: string): string {
    switch (type) {
      case 'oneAttack':
        return '最强一击';
      case 'allAttack':
        return '最高总伤害';
      default:
        return '最佳';
    }
  }

  @Builder
  periodDetail() {
    if (this.vm.loading && (this.vm.scheduleId === 0 || this.pendingPeriodId > 0)) {
      Column({ space: 8 }) {
        LoadingProgress().width(32).height(32).color($r('app.color.app_primary'))
        Text($r('app.string.ui_common_loading')).fontSize(13).fontColor($r('app.color.text_secondary'))
      }.width('100%').padding({ top: 48, bottom: 48 })
    } else {
      if (this.vm.message.length > 0) {
        Text(this.vm.message).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.currentEntry.hasData) {
        this.modeSelector()
        this.difficultyView()
        if (!this.showStatistics) {
          GridRow({ columns: this.challengeColumns, gutter: 10 }) {
            ForEach(this.currentEntry.challenges, (challenge: HardChallengeChallenge) => {
              GridCol() { this.challengeCard(challenge) }
            }, (challenge: HardChallengeChallenge, index: number): string => `hc_${this.vm.recordVersion}_${this.modeIndex}_${index}_${this.iconRevision}`)
          }.width('100%').constraintSize({ maxWidth: 960 })
            .onAreaChange((_old: Area, area: Area): void => { this.onChallengeAreaChange(Number(area.width)); })
        }
      } else {
        Text(this.vm.scheduleId > 0 ? '该期暂无本地战绩' : '暂无本地战绩，点击刷新获取')
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 12 })
      }
      if (this.showStatistics) {
        this.blingSection()
        this.popularityCard()
      }
    }
  }

  private difficultyTitle(): string {
    const difficulty: string = this.currentEntry.best.difficultyLabel();
    return difficulty || (this.modeIndex === 0 ? '单人挑战' : '联机挑战');
  }

  private static formatSeconds(sec: number): string {
    if (sec <= 0) {
      return '--';
    }
    return `${sec} 秒`;
  }
}
