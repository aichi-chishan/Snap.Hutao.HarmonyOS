/**
 * SpiralAbyssPage.ets（@Entry）
 * 深境螺旋：总览（总星数/最深楼层/战斗场次）+ 层列表（每层星级、每半场出战角色）。
 */
import { router } from '@kit.ArkUI';
import { SpiralAbyssViewModel } from '../viewmodel/SpiralAbyssViewModel';
import { SpiralAbyssData, SpiralAbyssFloor, SpiralAbyssLevel, SpiralAbyssAvatar, SpiralAbyssBattle, SpiralAbyssRank } from '../model/SpiralAbyss';
import { RiskUiHelper, RiskVerifyParams } from '../common/RiskUiHelper';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { NavIcon } from '../components/NavIcon';
import { RiskVerifyDialog } from '../components/RiskVerifyDialog';
import { DateUtil } from '../common/DateUtil';
import { MetaIcon } from '../components/MetaIcon';
import { WikiMetaService } from '../service/WikiMetaService';

@Entry
@Component
export struct SpiralAbyssPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: SpiralAbyssViewModel = new SpiralAbyssViewModel();
  /** 风控验证弹窗开关（needRiskVerify 时自动弹出，对齐 Windows 验证小窗） */
  @State showVerify: boolean = false;

  aboutToAppear(): void {
    this.reload();
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

  reload(): void {
    this.vm.load(this.currentUid).then(() => {
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  @Builder
  header() {
    PageHeader({ title: '深境螺旋', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
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
      NavIcon({ name: 'SpiralAbyss', iconSize: 60 })
      Text('需登录后查看深境螺旋')
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
  overviewCard(abyss: SpiralAbyssData) {
    Column({ space: 10 }) {
      Row() {
        this.overviewCell(`${abyss.totalStar}`, '总星数')
        this.overviewCell(abyss.maxFloor.length > 0 ? abyss.maxFloor : '--', '最深楼层')
        this.overviewCell(`${abyss.totalWinTimes}/${abyss.totalBattleTimes}`, '获胜/挑战')
      }
      .width('100%')
      if (abyss.startTime > 0) {
        Text(`${DateUtil.formatDate(abyss.startTime)} ~ ${DateUtil.formatDate(abyss.endTime)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  overviewCell(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(24)
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
  floorSection(floor: SpiralAbyssFloor) {
    Column({ space: 8 }) {
      Row() {
        Text(`第 ${floor.index} 层`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`★ ${floor.star}/${floor.maxStar}`)
          .fontSize(12)
          .fontColor($r('app.color.notice_on'))
      }
      .width('100%')

      ForEach(floor.levels, (level: SpiralAbyssLevel, li: number) => {
        Column({ space: 6 }) {
          Row() {
            Text(`第 ${level.index} 间`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`★ ${level.star}/${level.maxStar}`)
              .fontSize(12)
              .fontColor($r('app.color.notice_on'))
          }
          .width('100%')
          ForEach(level.battles, (battle: SpiralAbyssBattle, bi: number) => {
            Row({ space: 8 }) {
              Text(battle.index === 1 ? '上半' : '下半')
                .fontSize(11)
                .fontColor(Color.White)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(6)
                .backgroundColor($r('app.color.app_primary'))
              Row({ space: 6 }) {
                ForEach(battle.avatars, (av: SpiralAbyssAvatar, ai: number) => {
                  this.avatarChip(av)
                }, (av: SpiralAbyssAvatar, ai: number) => `${ai}_${av.id}`)
              }
            }
            .width('100%')
          }, (battle: SpiralAbyssBattle, bi: number) => `${bi}_${battle.index}`)
        }
        .width('100%')
        .padding(10)
        .borderRadius(10)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1, color: $r('app.color.divider') })
      }, (level: SpiralAbyssLevel, li: number) => `${li}_${level.index}`)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  avatarChip(av: SpiralAbyssAvatar) {
    Column({ space: 2 }) {
      if (av.icon.startsWith('http')) {
        Image(av.icon)
          .width(26)
          .height(26)
          .borderRadius(13)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.card_background'))
      } else if (av.icon.length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: av.icon, iconSize: 26 })
          .borderRadius(13)
          .clip(true)
      } else if (WikiMetaService.iconOfAvatar(av.id).length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(av.id), iconSize: 26 })
          .borderRadius(13)
          .clip(true)
      } else {
        Image($r('app.media.nav_Announcement'))
          .width(26)
          .height(26)
          .borderRadius(13)
          .objectFit(ImageFit.Cover)
      }
      Text(`Lv.${av.level}`)
        .fontSize(9)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding(4)
    .borderRadius(8)
    .backgroundColor($r('app.color.app_primary_bg'))
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
          Text('本期统计')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(abyss.maxFloor.length > 0 ? `最深 ${abyss.maxFloor}` : '')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        this.rankRow('满星', abyss.revealRank)
        this.rankRow('击败', abyss.defeatRank)
        this.rankRow('伤害', abyss.damageRank)
        this.rankRow('承伤', abyss.takeDamageRank)
        this.rankRow('普攻', abyss.normalSkillRank)
        this.rankRow('元素爆发', abyss.energySkillRank)
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
    }
  }

  /** Enka 官方头像（按角色 id，icon 缺失时兜底） */
  static avatarUrl(id: number): string {
    return `https://enka.network/ui/UI_AvatarIcon_${id}.png`;
  }

  build() {
    Column() {
      this.header()
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else {
        // 当期/上期切换
        Row({ space: 8 }) {
          this.scheduleChip(1, '当期')
          this.scheduleChip(2, '上期')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })

        Scroll() {
          Column({ space: 10 }) {
            if (this.vm.loading) {
              Column({ space: 10 }) {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color($r('app.color.app_primary'))
                Text('加载中...')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding({ top: 60, bottom: 60 })
            } else if (this.vm.message.length > 0) {
              Column({ space: 10 }) {
                NavIcon({ name: 'SpiralAbyss', iconSize: 56 })
                Text(this.vm.message)
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center)
                Button('重试')
                  .fontSize(14)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.reload();
                  })
              }
              .width('100%')
              .padding({ top: 60, bottom: 60 })
            } else if (this.vm.abyss !== undefined) {
              this.overviewCard(this.vm.abyss)
              this.statsCard(this.vm.abyss)
              if (!this.vm.abyss.isUnlock) {
                Text('深境螺旋尚未解锁')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ top: 20, bottom: 20 })
              }
              ForEach(this.vm.abyss.floors, (floor: SpiralAbyssFloor, fi: number) => {
                this.floorSection(floor)
              }, (floor: SpiralAbyssFloor, fi: number) => `${fi}_${floor.index}`)
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

  @Builder
  scheduleChip(type: number, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.vm.scheduleType === type ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .borderRadius(12)
      .backgroundColor(this.vm.scheduleType === type ? $r('app.color.app_primary') : $r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
      .onClick(() => {
        this.vm.switchSchedule(this.currentUid, type).then(() => {
        });
      })
  }
}
