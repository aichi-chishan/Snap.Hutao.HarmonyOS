/**
 * HardChallengePage.ets（@Entry）
 * 幽境危战：档位切换（单挑/多人）、难度档 Segmented、各挑战卡（名称/用时/队内角色/最佳角色/怪物、挑战项）。
 * 数据源：hard_challenge 接口（need_detail=true）。
 */
import { router, LengthMetrics } from '@kit.ArkUI';
import { HardChallengeViewModel } from '../viewmodel/HardChallengeViewModel';
import { HardChallengeChallenge, HardChallengeSimpleAvatar, HardChallengeBestAvatar, HardChallengeMonster, HardChallengeDataEntry } from '../model/HardChallenge';
import { RiskUiHelper, RiskVerifyParams } from '../common/RiskUiHelper';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { NavIcon } from '../components/NavIcon';
import { AssetIcon } from '../components/AssetIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { WikiMetaService } from '../service/WikiMetaService';
import { MetaIcon } from '../components/MetaIcon';
import { Logger } from '../common/Logger';

@Entry
@Component
export struct HardChallengePage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: HardChallengeViewModel = new HardChallengeViewModel();
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;
  /** 档位：0=单挑 1=联机（页面 @State 驱动刷新） */
  @State modeIndex: number = 0;
  /** 当前档位 DataEntry 快照（页面 @State：档位切换/加载完成后显式同步，避免 @Observed 深层不刷新） */
  @State currentEntry: HardChallengeDataEntry = new HardChallengeDataEntry();

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
        this.syncEntry();
      });
    } else {
      this.vm.loaded = true;
      this.vm.message = '请先登录';
    }
  }

  /** 同步当前档位快照（VM 加载/档位切换后调用） */
  syncEntry(): void {
    this.currentEntry = this.vm.entryOf(this.modeIndex);
    Logger.info('HC', `syncEntry mode=${this.modeIndex} hasData=${this.currentEntry.hasData} challenges=${this.currentEntry.challenges.length}`);
  }

  /** 档位切换：更新页面快照（VM 层同步切换） */
  switchMode(index: number): void {
    this.modeIndex = index;
    this.vm.selectMode(index);
    this.syncEntry();
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  @Builder
  header() {
    PageHeader({ title: '幽境危战', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
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
      NavIcon({ name: 'HardChallenge', iconSize: 60 })
      Text('需登录后查看幽境危战')
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
  avatarCircle(avatar: HardChallengeSimpleAvatar) {
    Column({ space: 3 }) {
      if (WikiMetaService.iconOfAvatar(avatar.avatarId).length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(avatar.avatarId), iconSize: 38, circular: true })
      } else if (WikiMetaService.iconOfAvatarName(avatar.name).length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatarName(avatar.name), iconSize: 38, circular: true })
      } else if (avatar.image.startsWith('http')) {
        Image(avatar.image)
          .width(38)
          .height(38)
          .borderRadius(19)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.app_primary_bg'))
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
      Text(avatar.name.length > 4 ? `${avatar.name.substring(0, 4)}…` : avatar.name)
        .fontSize(9)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  challengeCard(challenge: HardChallengeChallenge) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(challenge.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(HardChallengePage.formatSeconds(challenge.second))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_primary'))
      }
      .width('100%')

      if (challenge.teams.length > 0) {
        Text('最速队伍')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(challenge.teams[0].avatars, (avatar: HardChallengeSimpleAvatar) => {
            this.avatarCircle(avatar)
          }, (avatar: HardChallengeSimpleAvatar) => `hc_av_${avatar.avatarId}_${challenge.name}`)
        }
        .width('100%')
      }

      // 最佳伤害角色（对齐 Windows：按 type 分「最强一击/最高总伤害」两行）
      if (challenge.bestAvatars.length > 0) {
        Text('最佳伤害角色')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        ForEach(challenge.bestAvatars, (best: HardChallengeBestAvatar) => {
          Row({ space: 8 }) {
            Text(HardChallengePage.bestTypeLabel(best.type))
              .fontSize(11)
              .fontColor($r('app.color.text_primary'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor($r('app.color.app_primary_bg'))
            // 角色头像：avatar_id→本地元数据 →名称→元数据 →侧脸/图标 URL →字母兜底
            if (WikiMetaService.iconOfAvatar(best.avatarId).length > 0) {
              MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(best.avatarId), iconSize: 28, circular: true })
            } else if (WikiMetaService.iconOfAvatarName(best.name).length > 0) {
              MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatarName(best.name), iconSize: 28, circular: true })
            } else if (best.image.startsWith('http')) {
              Image(best.image)
                .width(28)
                .height(28)
                .borderRadius(14)
                .objectFit(ImageFit.Cover)
                .backgroundColor($r('app.color.app_primary_bg'))
            } else {
              Text(best.name.length > 0 ? best.name.substring(0, 1) : '★')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width(28)
                .height(28)
                .textAlign(TextAlign.Center)
                .borderRadius(14)
                .backgroundColor(best.rarity >= 5 ? $r('app.color.five_star') : $r('app.color.four_star'))
            }
            Text(`${best.value}`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_primary'))
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
        }, (best: HardChallengeBestAvatar) => `hc_best_${best.avatarId}_${best.type}_${challenge.name}`)
      }

      if (challenge.monster.name.length > 0) {
        Row({ space: 8 }) {
          NavIcon({ name: 'HardChallenge', iconSize: 18 })
          Column({ space: 2 }) {
            Text(challenge.monster.name)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`Lv.${challenge.monster.level}`)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
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
  difficultyView() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.currentEntry.best.name.length > 0 ? this.currentEntry.best.name : '挑战')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.currentEntry.best.second > 0) {
          Text(`最佳 ${HardChallengePage.formatSeconds(this.currentEntry.best.second)}`)
            .fontSize(11)
            .fontColor($r('app.color.app_primary'))
        }
      }
      .width('100%')

      ForEach(this.currentEntry.challenges, (challenge: HardChallengeChallenge) => {
        this.challengeCard(challenge)
      }, (challenge: HardChallengeChallenge) => `hc_cd_${challenge.name}`)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  build() {
    Column() {
      this.header()
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else if (this.vm.loading) {
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
      } else {
        Scroll() {
          Column({ space: 10 }) {
            if (!this.vm.isUnlock && !this.vm.single.hasData && !this.vm.mp.hasData) {
              Text(this.vm.message.length > 0 ? this.vm.message : '本账号暂无幽境危战数据')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ top: 30, bottom: 30 })
                .textAlign(TextAlign.Center)
            } else {
              // 档位切换（单挑/联机，对齐 Windows Segmented）
              Row({ space: 8 }) {
                Text('单挑')
                  .fontSize(13)
                  .fontWeight(this.modeIndex === 0 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.modeIndex === 0 ? Color.White : $r('app.color.text_primary'))
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(16)
                  .backgroundColor(this.modeIndex === 0 ? $r('app.color.app_primary') : $r('app.color.card_background'))
                  .border({ width: 1, color: $r('app.color.divider') })
                  .onClick(() => {
                    this.switchMode(0);
                  })
                Text('联机')
                  .fontSize(13)
                  .fontWeight(this.modeIndex === 1 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.modeIndex === 1 ? Color.White : $r('app.color.text_primary'))
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(16)
                  .backgroundColor(this.modeIndex === 1 ? $r('app.color.app_primary') : $r('app.color.card_background'))
                  .border({ width: 1, color: $r('app.color.divider') })
                  .onClick(() => {
                    this.switchMode(1);
                  })
              }
              .width('100%')

              this.difficultyView()
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

  private static formatSeconds(sec: number): string {
    if (sec <= 0) {
      return '--';
    }
    const m: number = Math.floor(sec / 60);
    const s: number = sec % 60;
    return m > 0 ? `${m}分${s}秒` : `${s}秒`;
  }
}
