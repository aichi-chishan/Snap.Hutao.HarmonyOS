/**
 * RoleCombatPage.ets（@Entry）
 * 幻想真境剧诗/幽境危战：档期切换、奖章/金币/难度统计、每回合出战角色 + 敌方 + 卡牌/祝福、候补角色、战斗统计。
 * 数据源：role_combat 接口（need_detail=true）。
 */
import { router } from '@kit.ArkUI';
import { RoleCombatViewModel } from '../viewmodel/RoleCombatViewModel';
import { RoleCombatDataItem, RoleCombatRoundData, RoleCombatAvatar, RoleCombatBuff, RoleCombatEnemy, RoleCombatAvatarStat } from '../model/RoleCombat';
import { ChallengePeriod } from '../model/ChallengePeriod';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { PageToolbar } from '../components/PageToolbar';
import { ChallengePeriodActions, ChallengePeriodRail, ChallengePeriodTabs } from '../components/ChallengePeriodRail';
import { MetaIcon } from '../components/MetaIcon';
import { PageBackdrop } from '../components/PageBackdrop';
import { NavIcon } from '../components/NavIcon';
import { AssetIcon } from '../components/AssetIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { WikiMetaService, RoleCombatScheduleMeta } from '../service/WikiMetaService';
import { DateUtil } from '../common/DateUtil';
import { Logger } from '../common/Logger';
import { AppButtonModifier, CardSurfaceModifier, UiSurface } from '../common/UiSurface';

@Entry
@Component
export struct RoleCombatPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('helpLocaleVersion') @Watch('loadIcons') localeVersion: number = 0;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageProp('currentUserId') @Watch('onOwnerChanged') ownerId: number = 0;
  @StorageProp('isLoggedIn') @Watch('onOwnerChanged') isLoggedIn: boolean = false;
  @State vm: RoleCombatViewModel = new RoleCombatViewModel();
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;
  @State isWide: boolean = false;
  @State detailOpen: boolean = false;
  @State showStatistics: boolean = false;
  @State pendingPeriodId: number = 0;
  private readonly detailScroller: Scroller = new Scroller();
  /** 本期期次元数据（限定元素/特邀/初始可选角色，本地 RoleCombatSchedule.json 按 scheduleId 匹配） */
  @State scheduleMeta: RoleCombatScheduleMeta | undefined = undefined;
  /** 月谕统计 Grid 自身宽度（vp，onAreaChange 读取；列数按它推导，不用屏幕宽） */
  @State moonGridW: number = 0;
  @State iconRevision: number = 0;
  private attached: boolean = false;
  private ownerTimer: number = -1;
  private iconSequence: number = 0;

  onOwnerChanged(): void {
    if (!this.attached) { return; }
    this.vm.invalidate();
    this.vm = new RoleCombatViewModel();
    this.scheduleMeta = undefined;
    this.showVerify = false;
    this.showPeriods();
    this.pendingPeriodId = 0;
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
    const vm: RoleCombatViewModel = this.vm;
    vm.initialize(this.currentUid).then((): void => {
      if (this.attached && this.vm === vm) { this.syncScheduleMeta(); }
    });
  }

  private loadIcons(): void {
    if (!this.attached) { return; }
    const vm: RoleCombatViewModel = this.vm;
    const sequence: number = ++this.iconSequence;
    WikiMetaService.ensureIconMaps().then((): void => {
      if (this.attached && this.vm === vm && sequence === this.iconSequence) { this.iconRevision++; }
    }).catch((): void => { Logger.warn('RoleCombatPage', 'local avatar icons unavailable'); });
  }

  private refreshData(announce: boolean): void {
    const vm: RoleCombatViewModel = this.vm;
    vm.load(this.currentUid).then((): void => {
      if (!this.attached || this.vm !== vm) { return; }
      this.syncScheduleMeta();
      if (vm.needRiskVerify) { this.showVerify = true; }
      else if (announce) { this.toast(vm.message.length > 0 ? vm.message : '已刷新'); }
    });
  }

  /** 数据到位后按当前期 scheduleId 匹配本地期次元数据（限定元素/特邀/初始可选） */
  private syncScheduleMeta(): void {
    const vm: RoleCombatViewModel = this.vm;
    const current: RoleCombatDataItem | undefined = vm.current();
    if (current === undefined || current.schedule.scheduleId <= 0) {
      this.scheduleMeta = undefined;
      return;
    }
    const scheduleId: number = current.schedule.scheduleId;
    if (this.scheduleMeta?.id !== scheduleId) { this.scheduleMeta = undefined; }
    WikiMetaService.getRoleCombatSchedules().then((all: RoleCombatScheduleMeta[]) => {
      if (!this.attached || this.vm !== vm || this.vm.current()?.schedule.scheduleId !== scheduleId) { return; }
      let hit: RoleCombatScheduleMeta | undefined = undefined;
      for (const m of all) {
        if (m.id === current.schedule.scheduleId) {
          hit = m;
          break;
        }
      }
      this.scheduleMeta = hit;
      if (hit === undefined) {
        Logger.warn('RoleCombatPage', `schedule meta miss id=${current.schedule.scheduleId}`);
      }
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1800 });
  }

  private shownPeriodId(): number {
    return this.pendingPeriodId > 0 ? this.pendingPeriodId : (this.vm.current()?.schedule.scheduleId ?? 0);
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
    const vm: RoleCombatViewModel = this.vm;
    vm.loadFromHistory(this.currentUid, scheduleId).then((): void => {
      if (!this.attached || this.vm !== vm || this.pendingPeriodId !== scheduleId) { return; }
      this.pendingPeriodId = 0;
      this.syncScheduleMeta();
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
      Text($r('app.string.ui_nav_theater')).fontSize(16).fontWeight(FontWeight.Medium)
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
      NavIcon({ name: 'RoleCombat', iconSize: 60 })
      Text('需登录后查看幻想真境剧诗')
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
  loadingView() {
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
  }

  @Builder
  statCell(slot: number) {
    Column({ space: 2 }) {
      Text(this.summaryValue(slot))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_primary_text'))
      Text(this.summaryLabel(slot))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  summaryCard(item: RoleCombatDataItem) {
    Column({ space: 10 }) {
      Text(item.stat.difficultyLabel() || '挑战战绩').fontSize(19).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      if (item.stat.maxRoundId > 0) {
        Text(`已抵达第 ${item.stat.maxRoundId} 幕${item.stat.tarotFinishedCount > 0 ? ` · 圣牌 ${item.stat.tarotFinishedCount}` : ''}`)
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (item.detail.fightStatistics.isShowBattleStats ||
        item.detail.fightStatistics.maxDefeat.value.length > 0 || item.detail.fightStatistics.maxDamage.value.length > 0) {
        this.moonStatCard(item)
      } else {
        GridRow({ columns: this.isWide ? 4 : 2, gutter: 6 }) {
          GridCol() { this.statCell(0) }
          GridCol() { this.statCell(1) }
          GridCol() { this.statCell(2) }
          GridCol() { this.statCell(3) }
        }.width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
  }

  @Builder
  scheduleCards() {
    if (this.scheduleMeta !== undefined && this.scheduleMeta.id === this.vm.current()?.schedule.scheduleId) {
      if (this.scheduleMeta.elements.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.scheduleMeta.elements, (element: number) => {
            Row({ space: 4 }) {
              Stack() {
                MetaIcon({ category: 'IconElement', name: WikiMetaService.elementIconById(element), iconSize: 17 })
              }.width(25).height(25).borderRadius(12).backgroundColor($r('app.color.element_icon_background'))
              Text(WikiMetaService.elementNameById(element)).fontSize(12).fontColor($r('app.color.text_primary'))
            }.margin({ right: 10 })
          }, (element: number): string => element.toString())
        }
        .width('100%')
        .padding(8)
        .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
        .accessibilityDescription('限定元素')
      }
      GridRow({ columns: this.isWide ? 2 : 1, gutter: 8 }) {
        if (this.scheduleMeta!.initialAvatars.length > 0) {
          GridCol() { this.metaAvatarRow('开幕角色', this.scheduleMeta!.initialAvatars) }
        }
        if (this.scheduleMeta!.specialAvatars.length > 0) {
          GridCol() { this.metaAvatarRow('特邀角色', this.scheduleMeta!.specialAvatars) }
        }
      }.width('100%')
    }
  }

  @Builder
  metaAvatarRow(label: string, ids: number[]) {
    Column({ space: 7 }) {
      Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(ids, (id: number) => {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(id), iconSize: 48 })
            .borderRadius(5).clip(true).margin({ right: 5, bottom: 4 })
            .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false)).accessibilityText(WikiMetaService.nameOfAvatarId(id))
        }, (id: number): string => `${id}_${this.iconRevision}`)
      }.width('100%')
    }
    .width('100%')
    .padding(8)
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
  }

  @Builder
  combatAvatar(avatar: RoleCombatAvatar) {
    Column({ space: 3 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (WikiMetaService.iconOfAvatar(avatar.avatarId).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(avatar.avatarId), iconSize: 48 })
        } else if (avatar.image.length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: avatar.image, iconSize: 48 })
        } else if (AssetIcon.elemName(avatar.element).length > 0) {
          AssetIcon({ name: AssetIcon.elemName(avatar.element), iconSize: 48 })
        } else {
          NavIcon({ name: 'AvatarProperty', iconSize: 44 })
        }
        if (avatar.avatarType === 2 || avatar.avatarType === 3) {
          Text(avatar.avatarType === 2 ? $r('app.string.ui_role_combat_avatar_trial_hint') : $r('app.string.ui_role_combat_support'))
            .fontSize(10).fontColor($r('app.color.on_accent')).padding({ left: 3, right: 3 })
            .backgroundColor($r('app.color.image_scrim')).borderRadius(4)
        }
      }.width(48).height(48).borderRadius(4).clip(true)
        .backgroundColor(avatar.rarity >= 5 ? $r('app.color.five_star') : $r('app.color.four_star'))
      Text(`Lv.${avatar.level}`).fontSize(10).fontColor($r('app.color.text_secondary'))
    }.width(54).margin({ right: 4, bottom: 4 })
      .accessibilityText(`${WikiMetaService.nameOfAvatarId(avatar.avatarId) || avatar.name}，等级 ${avatar.level}`)
  }

  @Builder
  roundCard(round: RoleCombatRoundData) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        AssetIcon({ name: RoleCombatPage.medalIcon(round), iconSize: 20 })
        Text(round.label())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (round.isGetMedal) {
          Row({ space: 4 }) {
            Text('获得奖章')
              .fontSize(10)
              .fontColor($r('app.color.app_primary_text'))
          }
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor($r('app.color.app_primary_bg'))
        }
      }
      .width('100%')
      // 回合完成时间（对齐 Windows RoundView.FinishTimeString：yyyy.MM.dd HH:mm:ss）
      if (round.finishTime > 0) {
        Text(`完成于 ${RoleCombatPage.formatRoundTime(round.finishTime)}`)
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      Text('出战角色')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(round.avatars, (avatar: RoleCombatAvatar) => {
          this.combatAvatar(avatar)
        }, (avatar: RoleCombatAvatar): string => `rc_av_${avatar.avatarId}_${round.roundId}_${avatar.avatarType}_${this.iconRevision}`)
      }
      .width('100%')

      if (round.enemies.length > 0) {
        Text('敌方')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(round.enemies, (enemy: RoleCombatEnemy) => {
            Column({ space: 3 }) {
              if (WikiMetaService.iconOfMonsterName(enemy.name).length > 0) {
                MetaIcon({
                  category: 'MonsterIcon',
                  name: WikiMetaService.iconOfMonsterName(enemy.name),
                  iconSize: 32,
                })
              } else {
                Text(enemy.name.length > 0 ? enemy.name.substring(0, 1) : '妖')
                  .fontSize(12)
                  .width(32)
                  .height(32)
                  .textAlign(TextAlign.Center)
                  .borderRadius(16)
                  .backgroundColor($r('app.color.notice_bg'))
              }
              Text(enemy.name.length > 6 ? `${enemy.name.substring(0, 6)}…` : enemy.name)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .width(52)
                .textAlign(TextAlign.Center)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              // 敌人等级（对齐 Windows EnemyView tooltip Level）
              if (enemy.level > 0) {
                Text(`Lv.${enemy.level}`)
                  .fontSize(9)
                  .fontColor($r('app.color.text_secondary'))
                  .width(52)
                  .textAlign(TextAlign.Center)
              }
            }
          }, (enemy: RoleCombatEnemy) => `rc_en_${enemy.name}`)
        }
        .width('100%')
      }

      if (round.splendourBuffs.length > 0 || round.splendourSummary.length > 0 || round.buffs.length > 0) {
        Text(round.splendourBuffs.length > 0 || round.splendourSummary.length > 0 ? $r('app.string.ui_role_combat_splendour_buffs_header') : '回合效果')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        if (round.splendourSummary.length > 0) {
          Text(WikiMetaService.cleanText(round.splendourSummary)).fontSize(12)
            .fontColor($r('app.color.text_secondary')).width('100%')
        }
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(round.splendourBuffs.length > 0 ? round.splendourBuffs : round.buffs, (buff: RoleCombatBuff) => {
            Row({ space: 4 }) {
              if (buff.icon.startsWith('http')) {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  Image(buff.icon)
                    .width(28)
                    .height(28)
                    .borderRadius(8)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor($r('app.color.app_primary_bg'))
                  if (buff.level > 0) {
                    Text(`${buff.level}`)
                      .fontSize(8)
                      .fontColor(Color.White)
                      .padding({ left: 4, right: 4 })
                      .borderRadius(6)
                      .backgroundColor($r('app.color.image_scrim'))
                  }
                }
              } else {
                Text('◆')
                  .fontSize(11)
                  .fontColor($r('app.color.app_primary_text'))
                  .width(28)
                  .height(28)
                  .textAlign(TextAlign.Center)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.app_primary_bg'))
              }
              Column({ space: 1 }) {
                Text(buff.name)
                  .fontSize(11)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (buff.desc.length > 0) {
                  Text(WikiMetaService.cleanText(buff.desc))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 3, bottom: 3 })
          }, (buff: RoleCombatBuff, index: number) => `rc_spb_${buff.id}_${index}`)
        }
        .width('100%')
      }

      if (round.choiceCards.length > 0) {
        Text('选择卡牌')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        ForEach(round.choiceCards, (buff: RoleCombatBuff) => {
          Row({ space: 8 }) {
            if (buff.icon.startsWith('http')) {
              Image(buff.icon)
                .width(28)
                .height(28)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            } else {
              Text('◆')
                .fontSize(11)
                .fontColor($r('app.color.app_primary_text'))
                .width(28)
                .height(28)
                .textAlign(TextAlign.Center)
                .borderRadius(8)
                .backgroundColor($r('app.color.app_primary_bg'))
            }
            Column({ space: 2 }) {
              Text(buff.name).fontSize(12).fontColor($r('app.color.text_primary')).width('100%')
              if (buff.desc.length > 0) {
                Text(WikiMetaService.cleanText(buff.desc)).fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
              }
            }.layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }, (buff: RoleCombatBuff, index: number) => `rc_buff_${buff.id}_${index}`)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  backupSection(item: RoleCombatDataItem) {
    if (item.detail.backupAvatars.length > 0) {
      Column({ space: 8 }) {
        Text(`待命角色（${item.detail.backupAvatars.length}）`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(item.detail.backupAvatars, (avatar: RoleCombatAvatar) => {
            this.combatAvatar(avatar)
          }, (avatar: RoleCombatAvatar): string => `rc_bk_${avatar.avatarId}_${avatar.avatarType}_${this.iconRevision}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius($r('app.float.card_radius'))
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .border({ width: 1, color: $r('app.color.card_stroke') })
    }
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
            this.refreshData(false);
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
    if (this.vm.loading && (this.vm.current() === undefined || this.pendingPeriodId > 0)) {
      this.loadingView()
    } else {
      if (this.vm.message.length > 0) {
        Text(this.vm.message).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.current() !== undefined) {
        this.currentDataSection(this.vm.current() ?? this.vm.dataItems[0])
      } else {
        Text('暂无本地战绩，点击刷新获取').fontSize(13).fontColor($r('app.color.text_secondary'))
          .width('100%').padding({ top: 16 })
      }
    }
  }

  /** 当前档期内容区 */
  @Builder
  currentDataSection(cur: RoleCombatDataItem) {
    Column({ space: 8 }) {
      if (!this.showStatistics) { this.scheduleCards() }
      if (cur.hasData) {
        this.summaryCard(cur)
        if (!this.showStatistics) {
          this.backupSection(cur)
          GridRow({ columns: this.isWide ? 2 : 1, gutter: 8 }) {
            ForEach(cur.detail.roundsData, (round: RoleCombatRoundData) => {
              GridCol() { this.roundCard(round) }
            }, (round: RoleCombatRoundData, index: number): string => `rc_roundcard_${this.vm.recordVersion}_${index}_${this.iconRevision}`)
          }.width('100%')
        }
      } else {
        Text(this.showStatistics ? '该期暂无本地统计' : '该期暂无本地战绩')
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 12 })
      }
    }.width('100%')
  }

  private summaryLabel(slot: number): string {
    const labels: string[] = ['奖章数', '金币占用', '总回合', '获得奖章回合'];
    return labels[slot] ?? '';
  }

  private summaryValue(slot: number): string {
    const current: RoleCombatDataItem | undefined = this.vm.current();
    if (current === undefined) { return '--'; }
    const values: number[] = [current.stat.medalNumber, current.stat.coinNumber,
      current.stat.maxRoundId, current.stat.getMedalRoundList.length];
    return String(values[slot] ?? 0);
  }

  private statLabel(slot: number): string {
    const labels: string[] = ['最多击破', '最强一击', '最多承伤', '消耗「幻剧之花」', '挑战星章',
      '演出总时长', '最佳记录', '场外声援', '助演次数'];
    return labels[slot] ?? '';
  }

  private statValue(slot: number): string {
    const current: RoleCombatDataItem | undefined = this.vm.current();
    if (current === undefined) { return '--'; }
    switch (slot) {
      case 0: return current.detail.fightStatistics.maxDefeat.value || '--';
      case 1: return current.detail.fightStatistics.maxDamage.value || '--';
      case 2: return current.detail.fightStatistics.maxTakeDamage.value || '--';
      case 3: return String(current.stat.coinNumber);
      case 4: return String(current.stat.medalNumber);
      case 5: return RoleCombatPage.formatMinutes(current.detail.fightStatistics.totalUseTime);
      case 6: return `第 ${current.stat.maxRoundId} 幕` +
        (current.stat.tarotFinishedCount > 0 ? ` 圣牌 ${current.stat.tarotFinishedCount}` : '');
      // Windows XAML：AvatarBonusNumber → 场外声援，RentCount → 助演次数。
      case 7: return String(current.stat.avatarBonusNumber);
      case 8: return String(current.stat.rentCount);
      default: return '';
    }
  }

  private statIcon(slot: number): string {
    const current: RoleCombatDataItem | undefined = this.vm.current();
    if (current === undefined) { return ''; }
    const avatars: RoleCombatAvatarStat[] = [current.detail.fightStatistics.maxDefeat,
      current.detail.fightStatistics.maxDamage, current.detail.fightStatistics.maxTakeDamage];
    const avatar: RoleCombatAvatarStat | undefined = slot < 3 ? avatars[slot] : undefined;
    return avatar !== undefined ? RoleCombatPage.statIconOf(avatar) : '';
  }

  /** 统计参数只传常量槽位，切期后的动态数值与角色图在渲染时读取。 */
  @Builder
  statValueCell(slot: number) {
    Row({ space: 6 }) {
      Text(this.statLabel(slot))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.statIcon(slot).length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: this.statIcon(slot), iconSize: 32 })
      }
      Text(this.statValue(slot))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 月谕模式统计卡（对齐 Windows：最多击破/最强一击/…/最快演出） */
  @Builder
  moonStatCard(cur: RoleCombatDataItem) {
    if (cur.detail.fightStatistics.isShowBattleStats ||
      cur.detail.fightStatistics.maxDefeat.value.length > 0 ||
      cur.detail.fightStatistics.maxDamage.value.length > 0) {
      Column({ space: 10 }) {
        // 2 列网格：最多击破/最强一击/最多承伤/幻剧之花/星章/总时长/最佳记录/声援/助演/最快
        Grid() {
          ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (slot: number) => {
            GridItem() {
              if (slot === 4 && cur.detail.roundsData.length > 0) { this.medalStrip(cur) }
              else { this.statValueCell(slot) }
            }
          }, (slot: number): string => `rc_stat_${this.vm.recordVersion}_${slot}_${this.iconRevision}`)
          if (cur.detail.fightStatistics.shortestAvatarList.length > 0) {
            GridItem() {
              Row({ space: 4 }) {
                Text($r('app.string.ui_role_combat_shortest'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
                  ForEach(cur.detail.fightStatistics.shortestAvatarList, (st: RoleCombatAvatarStat) => {
                    MetaIcon({ category: 'AvatarIcon', name: RoleCombatPage.statIconOf(st), iconSize: 32 })
                  }, (st: RoleCombatAvatarStat, idx: number) => `rc_short_${idx}_${st.avatarId}_${st.icon}_${this.iconRevision}`)
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
              .border({ width: 1, color: $r('app.color.divider') })
            }
          }
        }
        .columnsTemplate(Array(this.moonCols()).fill('1fr').join(' '))
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.moonGridW = Number(newValue.width);
        })
      }
      .width('100%')
    }
  }

  moonCols(): number {
    return this.moonGridW > 0 ? (this.moonGridW >= 500 ? 2 : 1) : (this.isWide ? 2 : 1);
  }

  @Builder
  medalStrip(cur: RoleCombatDataItem) {
    Row({ space: 6 }) {
      Text('挑战星章').fontSize(12).fontColor($r('app.color.text_secondary'))
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
        ForEach(cur.detail.roundsData, (round: RoleCombatRoundData, index: number) => {
          AssetIcon({ name: RoleCombatPage.medalIcon(round), iconSize: 20 })
            .margin({ left: 3 })
            .accessibilityText(round.label())
        }, (round: RoleCombatRoundData, index: number): string => `${index}_${round.isGetMedal}_${round.isTarot}`)
      }.layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
    .border({ width: 1, radius: 8, color: $r('app.color.divider') })
  }

  /** avatar_icon 全名（如 UI_AvatarIcon_Ayaka）→ MetaIcon name（UI_AvatarIcon_Ayaka）直接可用 */
  private static iconNameOf(icon: string): string {
    if (icon.length === 0) {
      return '';
    }
    // 可能带 .png 后缀
    if (!icon.startsWith('http') && !icon.startsWith('file://') && icon.endsWith('.png')) {
      return icon.substring(0, icon.length - 4);
    }
    return icon;
  }

  /** 统计格角色图：优先 avatar_id→本地元数据图标，次选 avatar_icon 名 */
  private static statIconOf(st: RoleCombatAvatarStat): string {
    if (st.avatarId > 0) {
      const local: string = WikiMetaService.sideIconOfAvatar(st.avatarId) || WikiMetaService.iconOfAvatar(st.avatarId);
      if (local.length > 0) {
        return local;
      }
    }
    return RoleCombatPage.iconNameOf(st.icon);
  }

  private static medalIcon(round: RoleCombatRoundData): string {
    return round.isTarot ? (round.isGetMedal ? 'tarot4' : 'tarot5') : (round.isGetMedal ? 'towerStar1' : 'towerStar2');
  }

  private static formatSpan(start: string, end: string): string {
    if (start.length === 0) {
      return '';
    }
    const s: string = start.length >= 10 ? start.substring(0, 10) : start;
    const e: string = end.length >= 10 ? end.substring(0, 10) : end;
    return `${s} ~ ${e}`;
  }

  private static formatMinutes(sec: number): string {
    if (sec <= 0) {
      return '--';
    }
    const h: number = Math.floor(sec / 3600);
    const m: number = Math.floor(sec / 60) % 60;
    const s: number = sec % 60;
    return `${DateUtil.pad2(h)}:${DateUtil.pad2(m)}:${DateUtil.pad2(s)}`;
  }

  /** 回合完成时间（秒级时间戳 → yyyy.MM.dd HH:mm:ss，对齐 Windows RoundView.FinishTimeString） */
  private static formatRoundTime(sec: number): string {
    const d: Date = ChallengePeriod.serverDate(sec * 1000);
    const p = (n: number): string => `${n}`.padStart(2, '0');
    return `${d.getUTCFullYear()}.${p(d.getUTCMonth() + 1)}.${p(d.getUTCDate())} `
      + `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`;
  }
}
