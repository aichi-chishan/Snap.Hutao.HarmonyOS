/**
 * SpiralAbyssPage.ets（@Entry）
 * 深境螺旋：总览（总星数/最深楼层/战斗场次）+ 层列表（每层星级、每半场出战角色）。
 */
import { router } from '@kit.ArkUI';
import { SpiralAbyssViewModel } from '../viewmodel/SpiralAbyssViewModel';
import { ChallengePeriod } from '../model/ChallengePeriod';
import { SpiralAbyssData, SpiralAbyssFloor, SpiralAbyssLevel, SpiralAbyssAvatar, SpiralAbyssBattle, SpiralAbyssRank } from '../model/SpiralAbyss';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { PageToolbar } from '../components/PageToolbar';
import { ChallengePeriodActions, ChallengePeriodRail, ChallengePeriodTabs } from '../components/ChallengePeriodRail';
import { NavIcon } from '../components/NavIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { MetaIcon } from '../components/MetaIcon';
import { PageBackdrop } from '../components/PageBackdrop';
import { WikiMetaService } from '../service/WikiMetaService';
import { TowerMetadataService, TowerBuff, TowerWaveView, ChamberWaves, TowerMonsterView } from '../service/TowerMetadataService';
import { AppButtonModifier, CardSurfaceModifier, UiSurface } from '../common/UiSurface';

@Entry
@Component
export struct SpiralAbyssPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageProp('currentUserId') @Watch('onOwnerChanged') ownerId: number = 0;
  @StorageProp('isLoggedIn') @Watch('onOwnerChanged') isLoggedIn: boolean = false;
  @State vm: SpiralAbyssViewModel = new SpiralAbyssViewModel();
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;
  @State isWide: boolean = false;
  @State detailOpen: boolean = false;
  @State showStatistics: boolean = false;
  @State showPeriodStats: boolean = false;
  @State pendingPeriodId: number = 0;
  private readonly detailScroller: Scroller = new Scroller();
  private attached: boolean = false;
  private ownerTimer: number = -1;

  onOwnerChanged(): void {
    if (!this.attached) { return; }
    this.vm.invalidate();
    this.vm = new SpiralAbyssViewModel();
    this.showVerify = false;
    this.showPeriods();
    this.pendingPeriodId = 0;
    clearTimeout(this.ownerTimer);
    this.ownerTimer = setTimeout((): void => { this.vm.initialize(this.currentUid); }, 0);
  }

  aboutToAppear(): void {
    this.attached = true;
    this.vm.initialize(this.currentUid);
  }

  aboutToDisappear(): void {
    this.attached = false;
    clearTimeout(this.ownerTimer);
    this.vm.invalidate();
  }

  /** 页面显示：检测风控 → 自动弹验证窗（保持当前页上下文） */
  onPageShow(): void {
    if (this.vm.needRiskVerify && !this.showVerify) {
      this.showVerify = true;
      return;
    }
    if (RiskUiHelper.hasPendingChallenge()) {
      this.reload();
    }
  }

  reload(): void {
    const vm: SpiralAbyssViewModel = this.vm;
    vm.load(this.currentUid).then((): void => {
      if (this.attached && this.vm === vm && vm.needRiskVerify) { this.showVerify = true; }
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1800 });
  }

  private shownPeriodId(): number {
    return this.pendingPeriodId > 0 ? this.pendingPeriodId : (this.vm.abyss?.scheduleId ?? 0);
  }

  private scrollDetailToTop(): void {
    if (this.isWide || this.detailOpen || this.vm.history.length === 0) {
      this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
  }

  private selectPeriod(scheduleId: number): void {
    this.showPeriodStats = false;
    this.scrollDetailToTop();
    this.detailOpen = true;
    if (this.shownPeriodId() === scheduleId) { return; }
    this.pendingPeriodId = scheduleId;
    const vm: SpiralAbyssViewModel = this.vm;
    vm.loadFromHistory(this.currentUid, scheduleId).then((): void => {
      if (!this.attached || this.vm !== vm || this.pendingPeriodId !== scheduleId) { return; }
      this.pendingPeriodId = 0;
    });
  }

  private selectTab(statistics: boolean): void {
    this.showPeriodStats = false;
    this.scrollDetailToTop();
    this.showStatistics = statistics;
    if (statistics) { this.detailOpen = true; }
  }

  private showPeriods(): void {
    this.showPeriodStats = false;
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
      Text($r('app.string.ui_nav_abyss')).fontSize(16).fontWeight(FontWeight.Medium)
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
        onRefresh: (): void => { this.reload(); },
        onSwitchTab: (): void => { this.selectTab(!this.showStatistics); } })
    }
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'SpiralAbyss', iconSize: 60 })
      Text('需登录后查看深境螺旋')
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
  overviewCard(abyss: SpiralAbyssData) {
    Column({ space: 10 }) {
      Row() {
        this.overviewCell(`${abyss.totalStar}`, '总星数')
        this.overviewCell(abyss.maxFloor.length > 0 ? abyss.maxFloor : '--', '最深楼层')
        this.overviewCell(`${abyss.totalWinTimes}/${abyss.totalBattleTimes}`, '获胜/挑战')
      }
      .width('100%')
      if (abyss.startTime > 0) {
        Text(ChallengePeriod.dateRange(abyss.startTime, abyss.endTime))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  overviewCell(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_primary_text'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  floorSection(floor: SpiralAbyssFloor) {
    Column({ space: 10 }) {
      Row() {
        Text(`第 ${floor.index} 层`).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        if (floor.hasRecord) {
          Text(`★ ${floor.star}`).fontSize(13).fontColor($r('app.color.notice_on'))
        }
      }.width('100%')

      if (this.disordersFor(floor.index).length > 0) {
        this.disorderTexts(floor.index, 0)
      } else if (this.disordersFor(floor.index, 1).length > 0 || this.disordersFor(floor.index, 2).length > 0) {
        if (this.isWide) {
          Row({ space: 12 }) {
            Column() { this.disorderTexts(floor.index, 1) }.layoutWeight(1)
            Column() { this.disorderTexts(floor.index, 2) }.layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top)
        } else {
          this.disorderTexts(floor.index, 1)
          this.disorderTexts(floor.index, 2)
        }
      }

      ForEach(floor.levels, (level: SpiralAbyssLevel) => {
        Divider().width('100%').color($r('app.color.divider'))
        Column({ space: 10 }) {
          Row() {
            Text(`第 ${level.index} 间`).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            if (level.hasRecord) {
              Text(`★ ${level.star}`).fontSize(13).fontColor($r('app.color.notice_on'))
            }
          }.width('100%')
          if (this.isWide) {
            Row({ space: 12 }) {
              Column() { this.battleHalf(floor.index, level, 1) }.layoutWeight(1)
              Column() { this.battleHalf(floor.index, level, 2) }.layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Top)
          } else {
            this.battleHalf(floor.index, level, 1)
            this.battleHalf(floor.index, level, 2)
          }
        }.width('100%').padding({ top: 2, bottom: 4 })
      }, (level: SpiralAbyssLevel): string => level.index.toString())
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
  }

  @Builder
  disorderTexts(floorIndex: number, half: number) {
    if (this.disordersFor(floorIndex, half).length > 0) {
      Column({ space: 3 }) {
        if (half > 0) {
          Text(half === 1 ? '上半' : '下半').fontSize(12).fontColor($r('app.color.text_primary')).width('100%')
        }
        ForEach(this.disordersFor(floorIndex, half), (description: string) => {
          Text(description).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }, (description: string, index: number): string => `${index}_${description}`)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  private battleOf(level: SpiralAbyssLevel, half: number): SpiralAbyssBattle | undefined {
    return level.battles.find((battle: SpiralAbyssBattle): boolean => battle.index === half);
  }

  @Builder
  battleHalf(floorIndex: number, level: SpiralAbyssLevel, half: number) {
    Column({ space: 6 }) {
      Text(half === 1 ? '上半' : '下半').fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      if ((this.battleOf(level, half)?.avatars.length ?? 0) > 0) {
        Text('上场角色').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.battleOf(level, half)?.avatars ?? [], (avatar: SpiralAbyssAvatar) => {
            this.avatarChip(avatar)
          }, (avatar: SpiralAbyssAvatar, index: number): string => `${index}_${avatar.id}`)
        }.width('100%')
      }
      if ((this.battleOf(level, half)?.timestamp ?? 0) > 0) {
        Text(SpiralAbyssPage.formatBattleTime(this.battleOf(level, half)?.timestamp ?? 0))
          .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      }
      ForEach(this.wavesFor(floorIndex, level.index, half), (wave: TowerWaveView, index: number) => {
        Column({ space: 4 }) {
          Text(wave.label).fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(wave.monsters, (monster: TowerMonsterView, monsterIndex: number) => {
              this.waveMonster(monster)
            }, (monster: TowerMonsterView, monsterIndex: number): string => `${monsterIndex}_${monster.name}`)
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (wave: TowerWaveView, index: number): string => `${index}_${wave.label}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  waveMonster(monster: TowerMonsterView) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (monster.icon.length > 0) {
        MetaIcon({ category: 'MonsterIcon', name: monster.icon, iconSize: 34, circular: true })
      } else {
        Text(monster.name.substring(0, 1)).fontSize(12).fontColor($r('app.color.text_primary'))
          .width(34).height(34).textAlign(TextAlign.Center).borderRadius(17).backgroundColor($r('app.color.notice_bg'))
      }
      if (monster.count > 1) {
        Text(`×${monster.count}`).fontSize(9).fontColor(Color.White)
          .padding({ left: 3, right: 3 }).borderRadius(4).backgroundColor($r('app.color.image_scrim'))
      }
    }.margin({ right: 5, bottom: 2 }).accessibilityText(monster.name)
  }

  @Builder
  avatarChip(av: SpiralAbyssAvatar) {
    Column({ space: 2 }) {
      if (av.icon.startsWith('http')) {
        Image(av.icon).width(38).height(38).borderRadius(5).objectFit(ImageFit.Cover)
      } else {
        MetaIcon({ category: 'AvatarIcon', name: av.icon || WikiMetaService.iconOfAvatar(av.id), iconSize: 38 })
          .borderRadius(5).clip(true)
      }
      if (av.level > 0) {
        Text(`Lv.${av.level}`).fontSize(9).fontColor($r('app.color.text_secondary'))
      }
    }
    .padding(3)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, radius: 6, color: $r('app.color.divider') })
    .margin({ right: 5, bottom: 2 })
    .alignItems(HorizontalAlign.Center)
  }

  /** 单行排行：标签 + 角色头像 + 数值（对齐 Windows 统计弹层卡） */
  @Builder
  rankRow(label: string, ranks: SpiralAbyssRank[]) {
    if (ranks.length > 0) {
      Row({ space: 8 }) {
        Text(label)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .width(52)
        Row({ space: 6 }) {
          ForEach(ranks, (r: SpiralAbyssRank, ri: number) => {
            Column({ space: 2 }) {
              if (r.avatarIcon.startsWith('http')) {
                Image(r.avatarIcon)
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.card_background'))
              } else if (r.avatarIcon.length > 0) {
                MetaIcon({ category: 'AvatarIcon', name: r.avatarIcon, iconSize: 30 })
                  .borderRadius(15)
                  .clip(true)
              } else if (WikiMetaService.iconOfAvatar(r.avatarId).length > 0) {
                MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(r.avatarId), iconSize: 30 })
                  .borderRadius(15)
                  .clip(true)
              } else {
                Image($r('app.media.nav_Announcement'))
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .objectFit(ImageFit.Cover)
              }
              Text(`${r.value}`)
                .fontSize(9)
                .fontColor($r('app.color.text_secondary'))
            }
          }, (r: SpiralAbyssRank, ri: number) => `rank_${label}_${r.avatarId}_${ri}`)
        }
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
    }
  }

  /** 深境统计卡（本期 6 项排行；对齐 Windows 分期详情右上统计弹层） */
  @Builder
  statsCard(abyss: SpiralAbyssData) {
    if (abyss.revealRank.length > 0 || abyss.defeatRank.length > 0 || abyss.damageRank.length > 0) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          NavIcon({ name: 'SpiralAbyss', iconSize: 16 })
          Text($r('app.string.ui_spiral_abyss_hutao_statistics'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(abyss.maxFloor.length > 0 ? `最深 ${abyss.maxFloor}` : '')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        this.rankRow('出战次数', abyss.revealRank)
        this.rankRow('击败', abyss.defeatRank)
        this.rankRow('伤害', abyss.damageRank)
        this.rankRow('承伤', abyss.takeDamageRank)
        this.rankRow('元素战技', abyss.normalSkillRank)
        this.rankRow('元素爆发', abyss.energySkillRank)
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .border({ width: 1, color: $r('app.color.card_stroke') })
    }
  }

  /** 某间某半的敌人波次（Tower 元数据；未预载返回空集合） */
  wavesFor(floorIndex: number, chamberIndex: number, battleIndex: number): TowerWaveView[] {
    if (this.vm.abyss === undefined) {
      return [];
    }
    const cw: ChamberWaves = TowerMetadataService.wavesOf(this.vm.abyss.scheduleId, floorIndex, chamberIndex);
    return battleIndex === 1 ? cw.upper : cw.lower;
  }

  /** 渊月祝福（塔元数据优先，API 解析兜底） */
  abyssBuff(): TowerBuff {
    const tower: TowerBuff = TowerMetadataService.buffOf(this.vm.abyss !== undefined ? this.vm.abyss.scheduleId : 0);
    if (tower.name.length > 0) {
      return tower;
    }
    const out: TowerBuff = new TowerBuff();
    out.name = this.vm.abyss !== undefined ? this.vm.abyss.buffName : '';
    out.description = this.vm.abyss !== undefined ? this.vm.abyss.buffDesc : '';
    if (out.description.length > 0) {
      out.descriptions.push(out.description);
    }
    return out;
  }

  /** 本层地脉紊乱（塔元数据；无数据返回空集合） */
  disordersFor(floorIndex: number, half: number = 0): string[] {
    if (this.vm.abyss === undefined) {
      return [];
    }
    return TowerMetadataService.floorDisorders(this.vm.abyss.scheduleId, floorIndex, half);
  }

  /** 战斗时间使用国服时区。 */
  static formatBattleTime(ts: number): string {
    const d: Date = ChallengePeriod.serverDate(ts);
    return `${ChallengePeriod.dateTime(ts)}:${String(d.getUTCSeconds()).padStart(2, '0')}`;
  }

  @Builder
  periodPanels() {
    Row() {
      if (this.vm.history.length > 0 && (this.isWide || !this.detailOpen)) {
        ChallengePeriodRail({ periods: this.vm.history, selectedId: this.shownPeriodId(), split: this.isWide,
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
            this.reload();
          },
        })
      }, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel), height: 420,
        backgroundColor: $r('app.color.sheet_material_tint'), showClose: false, blurStyle: BlurStyle.Regular })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  periodDetail() {
    if (this.vm.loading && (this.vm.abyss === undefined || this.pendingPeriodId > 0)) {
      Column({ space: 8 }) {
        LoadingProgress().width(32).height(32).color($r('app.color.app_primary'))
        Text($r('app.string.ui_common_loading')).fontSize(13).fontColor($r('app.color.text_secondary'))
      }.width('100%').padding({ top: 48, bottom: 48 })
    } else {
      if (this.vm.message.length > 0) {
        Text(this.vm.message).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.abyss === undefined) {
        Text('暂无本地战绩，点击刷新获取当期与上期')
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 16 })
      } else if (this.showStatistics) {
        if (!this.vm.publishedOnly && this.vm.abyss.isUnlock) {
          this.overviewCard(this.vm.abyss)
          this.statsCard(this.vm.abyss)
        } else {
          Text('该期暂无本地统计').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        }
      } else {
        this.blessingCard()
        if (this.vm.publishedOnly) {
          Text('该期暂无本地战绩').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        } else if (!this.vm.abyss.isUnlock) {
          Text('深境螺旋尚未解锁').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        }
        this.floorSelector()
        ForEach(this.vm.selectedFloors(), (floor: SpiralAbyssFloor) => {
          this.floorSection(floor)
        }, (floor: SpiralAbyssFloor): string => `${this.vm.recordVersion}_${floor.index}`)
      }
    }
  }

  @Builder
  blessingCard() {
    if (this.abyssBuff().name.length > 0 || this.abyssBuff().descriptions.length > 0) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.abyssBuff().name).fontSize(19).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          if (!this.vm.publishedOnly && this.vm.abyss?.isUnlock === true) {
            Button('统计数据', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .height(44).fontSize(12).fontColor($r('app.color.app_primary_text'))
              .backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
              .onClick(() => { this.showPeriodStats = !this.showPeriodStats; })
              .bindPopup(this.showPeriodStats, {
                builder: (): void => { this.periodStatsPopup(); },
                width: this.isWide ? 410 : '90%', placement: Placement.BottomRight, autoCancel: true, focusable: true,
                systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
                popupColor: $r('app.color.sheet_material_tint'),
                onStateChange: (event: PopupStateChangeParam): void => { if (!event.isVisible) { this.showPeriodStats = false; } }
              })
          }
        }.width('100%')
        ForEach(this.abyssBuff().descriptions, (description: string) => {
          Text(description).fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
        }, (description: string, index: number): string => `${index}_${description}`)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.card_inner_tint'))
      .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
    }
  }

  @Builder
  periodStatsPopup() {
    if (this.vm.abyss !== undefined) {
      Scroll() {
        Column({ space: 6 }) {
          this.overviewCard(this.vm.abyss)
          this.statsCard(this.vm.abyss)
        }.width('100%').padding(8)
      }.width('100%').constraintSize({ maxHeight: 420 }).scrollBar(BarState.Auto)
    }
  }

  @Builder
  floorSelector() {
    if (this.vm.floors.length > 0) {
      if (this.isWide || this.vm.floors.length <= 4) {
        this.floorTabs()
      } else {
        Scroll() { this.floorTabs() }
          .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }
  }

  @Builder
  floorTabs() {
    Row({ space: 2 }) {
      ForEach(this.vm.floors, (floor: SpiralAbyssFloor) => {
        Button(`第 ${floor.index} 层`, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .layoutWeight(this.isWide || this.vm.floors.length <= 4 ? 1 : 0)
          .height(44).fontSize(13).borderRadius(6)
          .fontColor(this.vm.selectedFloorIndex === floor.index ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
          .backgroundColor(this.vm.selectedFloorIndex === floor.index ? $r('app.color.app_primary_bg') : Color.Transparent)
          .accessibilitySelected(this.vm.selectedFloorIndex === floor.index)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.vm.selectFloor(floor.index))
      }, (floor: SpiralAbyssFloor): string => floor.index.toString())
    }
    .width('100%')
    .padding(2)
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
  }
}
