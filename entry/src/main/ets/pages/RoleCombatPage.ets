/**
 * RoleCombatPage.ets（@Entry）
 * 幻想真境剧诗/幽境危战：档期切换、奖章/金币/难度统计、每回合出战角色 + 敌方 + 卡牌/祝福、候补角色、战斗统计。
 * 数据源：role_combat 接口（need_detail=true）。
 */
import { router } from '@kit.ArkUI';
import { RoleCombatViewModel } from '../viewmodel/RoleCombatViewModel';
import { RoleCombatDataItem, RoleCombatRoundData, RoleCombatAvatar, RoleCombatBuff, RoleCombatEnemy, RoleCombatAvatarStat } from '../model/RoleCombat';
import { RiskUiHelper, RiskVerifyParams } from '../common/RiskUiHelper';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { MetaIcon } from '../components/MetaIcon';
import { NavIcon } from '../components/NavIcon';
import { AssetIcon } from '../components/AssetIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { WikiMetaService } from '../service/WikiMetaService';

@Entry
@Component
export struct RoleCombatPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: RoleCombatViewModel = new RoleCombatViewModel();
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;

  aboutToAppear(): void {
    this.loadData();
  }

  /** 页面显示：检测风控 → 自动弹验证窗（保持当前页上下文） */
  onPageShow(): void {
    if (this.vm.needRiskVerify && !this.showVerify) {
      this.showVerify = true;
      return;
    }
    if (RiskUiHelper.hasPendingChallenge()) {
      this.vm.resetRiskAndReload(this.currentUid);
    }
  }

  loadData(): void {
    if (this.isLoggedIn && this.currentUid.length > 0) {
      this.vm.load(this.currentUid).then(() => {
      });
    } else {
      this.vm.loaded = true;
      this.vm.message = '请先登录';
    }
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  @Builder
  header() {
    PageHeader({ title: '幻想真境剧诗', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
      Button('刷新')
        .fontSize(13)
        .height(32)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.vm.load(this.currentUid).then(() => {
            this.toast(this.vm.message.length > 0 ? this.vm.message : '已刷新');
          });
        })
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
  loadingView() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color($r('app.color.app_primary'))
      Text('加载中...')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  @Builder
  statCell(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  summaryCard(item: RoleCombatDataItem) {
    Column({ space: 10 }) {
      Row() {
        Text('本期战局')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(RoleCombatPage.formatSpan(item.schedule.startDateTime, item.schedule.endDateTime))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Row({ space: 8 }) {
        this.statCell('奖章数', `${item.stat.medalNumber}`)
        this.statCell('金币占用', `${item.stat.coinNumber}`)
        this.statCell('总回合', `${item.stat.maxRoundId}`)
        this.statCell('获得奖章回合', `${item.stat.getMedalRoundList.length}`)
      }
      .width('100%')

      Divider()
        .width('100%')
        .color($r('app.color.divider'))

      Text('历战回合')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      // 回合标签行
      Row({ space: 6 }) {
        ForEach(item.detail.roundsData, (round: RoleCombatRoundData) => {
          this.staticRoundTag(round.roundId, round.isGetMedal)
        }, (round: RoleCombatRoundData) => `rc_round_${round.roundId}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  staticRoundTag(roundId: number, isMedal: boolean) {
    Text(`回合 ${roundId}`)
      .fontSize(11)
      .fontColor(isMedal ? Color.White : $r('app.color.app_primary'))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(isMedal ? $r('app.color.app_primary') : $r('app.color.app_primary_bg'))
  }

  @Builder
  roundCard(round: RoleCombatRoundData) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(`回合 ${round.roundId}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (round.isGetMedal) {
          Row({ space: 4 }) {
            NavIcon({ name: 'RoleCombat', iconSize: 14 })
            Text('获得奖章')
              .fontSize(10)
              .fontColor($r('app.color.app_primary'))
          }
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor($r('app.color.app_primary_bg'))
        }
      }
      .width('100%')

      Text('出战角色')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(round.avatars, (avatar: RoleCombatAvatar) => {
          Column({ space: 3 }) {
            if (avatar.image.startsWith('http')) {
              Image(avatar.image)
                .width(36)
                .height(36)
                .borderRadius(18)
                .objectFit(ImageFit.Cover)
                .backgroundColor($r('app.color.card_background'))
            } else if (avatar.image.length > 0) {
              MetaIcon({ category: 'AvatarIcon', name: avatar.image, iconSize: 36 })
                .borderRadius(18)
                .clip(true)
            } else if (WikiMetaService.iconOfAvatar(avatar.avatarId).length > 0) {
              MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(avatar.avatarId), iconSize: 36 })
                .borderRadius(18)
                .clip(true)
            } else if (AssetIcon.elemName(avatar.element).length > 0) {
              Image(AssetIcon.resolve(AssetIcon.elemName(avatar.element)))
                .width(36)
                .height(36)
                .borderRadius(18)
                .objectFit(ImageFit.Cover)
                .backgroundColor($r('app.color.app_primary_bg'))
            } else {
              Text(avatar.name.length > 0 ? avatar.name.substring(0, 1) : '★')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width(36)
                .height(36)
                .textAlign(TextAlign.Center)
                .borderRadius(18)
                .backgroundColor($r('app.color.app_primary'))
            }
            Text(`Lv.${avatar.level}`)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
        }, (avatar: RoleCombatAvatar) => `rc_av_${avatar.avatarId}_${round.roundId}_${avatar.image}`)
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
            }
          }, (enemy: RoleCombatEnemy) => `rc_en_${enemy.name}`)
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
            Text(buff.name.length > 0 ? buff.name.substring(0, 1) : '🎴')
              .fontSize(12)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
              .borderRadius(8)
              .backgroundColor($r('app.color.app_primary_bg'))
            Text(buff.name)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(buff.desc.length > 12 ? `${buff.desc.substring(0, 12)}…` : buff.desc)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }, (buff: RoleCombatBuff) => `rc_buff_${buff.id}_${round.roundId}`)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: 1, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  backupSection(item: RoleCombatDataItem) {
    if (item.detail.backupAvatars.length > 0) {
      Column({ space: 8 }) {
        Text(`候补角色（${item.detail.backupAvatars.length}）`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(item.detail.backupAvatars, (avatar: RoleCombatAvatar) => {
            Column({ space: 3 }) {
              if (avatar.image.startsWith('http')) {
                Image(avatar.image)
                  .width(38)
                  .height(38)
                  .borderRadius(19)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.card_background'))
              } else if (avatar.image.length > 0) {
                MetaIcon({ category: 'AvatarIcon', name: avatar.image, iconSize: 38 })
                  .borderRadius(19)
                  .clip(true)
              } else if (WikiMetaService.iconOfAvatar(avatar.avatarId).length > 0) {
                MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(avatar.avatarId), iconSize: 38 })
                  .borderRadius(19)
                  .clip(true)
              } else if (AssetIcon.elemName(avatar.element).length > 0) {
                Image(AssetIcon.resolve(AssetIcon.elemName(avatar.element)))
                  .width(38)
                  .height(38)
                  .borderRadius(19)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.app_primary_bg'))
              } else {
                Text(avatar.name.length > 0 ? avatar.name.substring(0, 1) : '★')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .width(38)
                  .height(38)
                  .textAlign(TextAlign.Center)
                  .borderRadius(19)
                  .backgroundColor($r('app.color.app_primary'))
              }
              Text(`Lv.${avatar.level}`)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
          }, (avatar: RoleCombatAvatar) => `rc_bk_${avatar.avatarId}_${avatar.image}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
    }
  }

  build() {
    Column() {
      this.header()
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else if (this.vm.loading) {
        this.loadingView()
      } else if (!this.vm.isUnlock && this.vm.dataItems.length === 0) {
        Column({ space: 10 }) {
          NavIcon({ name: 'RoleCombat', iconSize: 60 })
          Text('本账号暂无幻想真境剧诗数据')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 80, bottom: 80 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            if (this.vm.dataItems.length === 0) {
              Text(this.vm.message.length > 0 ? this.vm.message : '暂无数据，点击右上角「刷新」重试')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ top: 30, bottom: 30 })
                .textAlign(TextAlign.Center)
            } else {
              // 档期切换
              if (this.vm.dataItems.length > 1) {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(this.vm.dataItems, (item: RoleCombatDataItem, idx: number) => {
                      Text(`第 ${idx + 1} 期`)
                        .fontSize(12)
                        .fontColor(this.vm.currentIndex === idx ? Color.White : $r('app.color.text_primary'))
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .borderRadius(14)
                        .backgroundColor(this.vm.currentIndex === idx ? $r('app.color.app_primary') : $r('app.color.card_background'))
                        .border({ width: 1, color: $r('app.color.divider') })
                        .onClick(() => {
                          this.vm.select(idx);
                        })
                    }, (item: RoleCombatDataItem, idx: number) => `rc_sched_${idx}`)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                .width('100%')
              }

              if (this.vm.current() !== undefined) {
                this.currentDataSection(this.vm.current() ?? this.vm.dataItems[0])
              }
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
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
          AppStorage.setOrCreate<string>(RiskUiHelper.KEY_PENDING, challenge);
          this.vm.resetRiskAndReload(this.currentUid);
        },
      })
    }, { height: 420, backgroundColor: $r('app.color.page_background'), showClose: false, blurStyle: BlurStyle.Regular })
  }

  /** 当前档期内容区 */
  @Builder
  currentDataSection(cur: RoleCombatDataItem) {
    Column({ space: 10 }) {
      this.summaryCard(cur)

      ForEach(cur.detail.roundsData, (round: RoleCombatRoundData) => {
        this.roundCard(round)
      }, (round: RoleCombatRoundData) => `rc_roundcard_${round.roundId}`)

      this.backupSection(cur)

      this.moonStatCard(cur)
    }
    .width('100%')
  }

  /** 统计卡：带角色图标的数值格（label 左 / value 右） */
  @Builder
  statValueCell(label: string, value: string, icon: string, avatarId: number) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (avatarId > 0 && WikiMetaService.iconOfAvatar(avatarId).length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(avatarId), iconSize: 26, circular: true })
      } else if (icon.length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: RoleCombatPage.iconNameOf(icon), iconSize: 26, circular: true })
      }
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 月谕模式统计卡（对齐 Windows：最多击破/最强一击/…/最快演出） */
  @Builder
  moonStatCard(cur: RoleCombatDataItem) {
    if (cur.detail.fightStatistics.isShowBattleStats ||
      cur.detail.fightStatistics.maxDefeat.value.length > 0 ||
      cur.detail.fightStatistics.maxDamage.value.length > 0) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('月谕模式')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          if (cur.stat.maxRoundId > 0) {
            Text(`已抵达成第 ${cur.stat.maxRoundId} 幕 圣牌 ${cur.stat.heraldry}`)
              .fontSize(11)
              .fontColor($r('app.color.app_primary'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(8)
              .backgroundColor($r('app.color.app_primary_bg'))
          }
        }
        .width('100%')

        // 2 列网格：最多击破/最强一击/最多承伤/幻剧之花/星章/总时长/最佳记录/声援/助演/最快
        Grid() {
          GridItem() {
            this.statValueCell('最多击破', cur.detail.fightStatistics.maxDefeat.value, cur.detail.fightStatistics.maxDefeat.icon, cur.detail.fightStatistics.maxDefeat.avatarId)
          }
          GridItem() {
            this.statValueCell('最强一击', cur.detail.fightStatistics.maxDamage.value, cur.detail.fightStatistics.maxDamage.icon, cur.detail.fightStatistics.maxDamage.avatarId)
          }
          GridItem() {
            this.statValueCell('最多承伤', cur.detail.fightStatistics.maxTakeDamage.value, cur.detail.fightStatistics.maxTakeDamage.icon, cur.detail.fightStatistics.maxTakeDamage.avatarId)
          }
          GridItem() {
            this.statValueCell('消弭「幻剧之花」', cur.detail.fightStatistics.totalCoinConsumed.value, cur.detail.fightStatistics.totalCoinConsumed.icon, cur.detail.fightStatistics.totalCoinConsumed.avatarId)
          }
          GridItem() {
            this.statValueCell('挑战星章', `${cur.stat.medalNumber}`, '', 0)
          }
          GridItem() {
            this.statValueCell('演出总时长', RoleCombatPage.formatMinutes(cur.detail.fightStatistics.totalUseTime), '', 0)
          }
          GridItem() {
            this.statValueCell('最佳记录', `第 ${cur.stat.maxRoundId} 幕`, '', 0)
          }
          GridItem() {
            this.statValueCell('场外声援', `${cur.stat.rentCount}`, '', 0)
          }
          GridItem() {
            this.statValueCell('助演次数', `${cur.stat.avatarBonusNumber}`, '', 0)
          }
          if (cur.detail.fightStatistics.shortestAvatarList.length > 0) {
            GridItem() {
              Row({ space: 4 }) {
                Text('最快演出')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
                  ForEach(cur.detail.fightStatistics.shortestAvatarList, (st: RoleCombatAvatarStat) => {
                    MetaIcon({ category: 'AvatarIcon', name: RoleCombatPage.statIconOf(st), iconSize: 24, circular: true })
                  }, (st: RoleCombatAvatarStat, idx: number) => `rc_short_${idx}_${st.icon}`)
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor($r('app.color.page_background'))
              .border({ width: 1, color: $r('app.color.divider') })
            }
          }
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
    }
  }

  /** avatar_icon 全名（如 UI_AvatarIcon_Ayaka）→ MetaIcon name（UI_AvatarIcon_Ayaka）直接可用 */
  private static iconNameOf(icon: string): string {
    if (icon.length === 0) {
      return '';
    }
    // 可能带 .png 后缀
    if (icon.endsWith('.png')) {
      return icon.substring(0, icon.length - 4);
    }
    return icon;
  }

  /** 统计格角色图：优先 avatar_id→本地元数据图标，次选 avatar_icon 名 */
  private static statIconOf(st: RoleCombatAvatarStat): string {
    if (st.avatarId > 0) {
      const local: string = WikiMetaService.iconOfAvatar(st.avatarId);
      if (local.length > 0) {
        return local;
      }
    }
    return RoleCombatPage.iconNameOf(st.icon);
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
    const m: number = Math.floor(sec / 60);
    const s: number = sec % 60;
    return `${m} 分 ${s} 秒`;
  }
}
