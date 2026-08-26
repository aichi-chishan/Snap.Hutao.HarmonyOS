/**
 * DailyNotePage.ets（Index 便笺 Tab 内嵌组件）
 * 实时便笺：树脂环形进度、派遣列表、每日委托、周本折扣、洞天宝钱、参变仪；阈值通知设置；自动刷新。
 */
import { router, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DailyNoteViewModel } from '../viewmodel/DailyNoteViewModel';
import { DailyNote, Expedition } from '../model/DailyNote';
import { NotificationHelper } from '../data/local/NotificationHelper';
import { NotifyFlags } from '../service/DailyNoteService';
import { GeetestVerifyParams } from './GeetestVerifyPage';
  import { DateUtil } from '../common/DateUtil';
  import { NavIcon } from '../components/NavIcon';
  import { MetaIcon } from '../components/MetaIcon';

@Component
export struct DailyNotePage {
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @StorageLink('currentUid') currentUid: string = '';
  @State vm: DailyNoteViewModel = new DailyNoteViewModel();
  @State allowNotify: boolean = false;
  /** 宽屏（平板/PC）：左数据面板 + 右侧立绘背景 */
  @State isWide: boolean = false;

  aboutToAppear(): void {
    this.vm.syncAutoRefresh();
    this.allowNotify = NotificationHelper.isEnabled();
    this.isWide = DailyNotePage.detectWide();
    this.vm.load(this.currentUid).then(() => {
      // 无缓存且已登录 → 自动拉一次
      if (this.isLoggedIn && this.currentUid.length > 0 && this.vm.note === undefined) {
        this.vm.refresh(this.currentUid).then((ok: boolean) => {
          if (!ok) {
            this.toast(this.vm.message);
          }
        });
      }
    });
  }

  /** 宽屏检测：屏幕宽度 vp >= 720 */
  private static detectWide(): boolean {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const widthVp: number = d.densityPixels > 0 ? d.width / d.densityPixels : d.width;
      return widthVp >= 720;
    } catch (e) {
      return false;
    }
  }

  /** 便笺内容区滚动控制器（通知设置按钮跳转用） */
  private settingRef: Scroller = new Scroller();
  /** 顶部操作按钮：官方图标+文字小按钮（对齐 Windows 立即刷新/通知设置样式） */
  @Builder
  headerIconButton(iconName: string, label: string, secondary: boolean, onTap: () => void) {
    Row({ space: 4 }) {
      if (iconName.length > 0) {
        NavIcon({ name: iconName, iconSize: 14 })
      }
      Text(label)
        .fontSize(12)
        .fontColor(secondary ? $r('app.color.text_secondary') : Color.White)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(28)
    .padding({ left: 12, right: 12 })
    .borderRadius(14)
    .backgroundColor(secondary ? $r('app.color.card_background') : $r('app.color.app_primary'))
    .onClick(onTap)
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  /** 跳转极验人机验证页，返回后轮询 challenge 并自动重放 */
  goGeetest(): void {
    const params: GeetestVerifyParams = {
      gt: this.vm.geetestGt,
      challenge: this.vm.geetestChallenge,
    };
    // 清掉旧的 challenge，避免误用
    AppStorage.setOrCreate<string>('dailyNoteChallenge', '');
    router.pushUrl({ url: 'pages/GeetestVerifyPage', params: params });
    // 轮询：验证页完成后写入 dailyNoteChallenge 并返回，此处检测到即重放
    const poll = setInterval(() => {
      const challenge: string = AppStorage.get<string>('dailyNoteChallenge') ?? '';
      if (challenge.length > 0) {
        clearInterval(poll);
        this.vm.refresh(this.currentUid, challenge).then((ok: boolean) => {
          this.toast(ok ? '验证通过，已刷新' : this.vm.message);
        });
      }
    }, 800);
    // 安全上限：2 分钟内未完成则停止轮询
    setTimeout(() => {
      clearInterval(poll);
    }, 120000);
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'DailyNote', iconSize: 60 })
      Text('需登录后查看实时便笺')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('登录并绑定 UID 后，可查看树脂/派遣/洞天宝钱等实时数据')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Button('去登录')
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  resinCard(note: DailyNote) {
    Row({ space: 16 }) {
      Progress({ value: note.currentResin, total: note.maxResin, type: ProgressType.Ring })
        .width(84)
        .height(84)
        .color(Color.White)
        .style({ strokeWidth: 10 })
      Column({ space: 3 }) {
        Text(`进行中`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text(`树脂 ${note.currentResin}/${note.maxResin} · ${note.resinRecoveryText()}`)
          .fontSize(11)
          .fontColor(Color.White)
          .opacity(0.85)
        Text(`洞天宝钱 ${note.currentHomeCoin}/${note.maxHomeCoin}`)
          .fontSize(11)
          .fontColor(Color.White)
          .opacity(0.85)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#2A7A50')
  }

  @Builder
  taskCard(note: DailyNote) {
    Row({ space: 10 }) {
      Text(note.dailyTask.isAllFinished() ? '✔' : '◻')
        .fontSize(18)
        .fontColor(note.dailyTask.isAllFinished() ? Color.White : Color.White)
      Column({ space: 2 }) {
        Text('每日委托')
          .fontSize(15)
          .fontColor(Color.White)
        Text(`已完成 ${note.dailyTask.finishedTaskNum}/${note.dailyTask.totalTaskNum}${note.isExtraTaskRewardReceived ? ' · 已领额外奖励' : ''}`)
          .fontSize(11)
          .fontColor(Color.White)
          .opacity(0.85)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(`周本折扣 ${note.remainResinDiscountNum}/${note.resinDiscountNumLimit}`)
        .fontSize(11)
        .fontColor(Color.White)
        .opacity(0.85)
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor('#2A7A50')
  }

  @Builder
  expeditionCard(note: DailyNote) {
    Column({ space: 8 }) {
      Row() {
        Text('派遣任务')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${note.currentExpeditionNum}/${note.maxExpeditionNum} 进行中`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      if (note.expeditions.length === 0) {
        Text('暂无派遣数据')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      ForEach(note.expeditions, (exp: Expedition, idx: number) => {
        Row({ space: 10 }) {
          if (exp.avatarSideIcon.length > 0) {
            Image(exp.avatarSideIcon)
              .width(34)
              .height(34)
              .borderRadius(17)
              .objectFit(ImageFit.Cover)
              .backgroundColor($r('app.color.app_primary_bg'))
          } else {
            Text(exp.isFinished() ? '✔' : '…')
              .fontSize(16)
              .fontColor(Color.White)
              .width(34)
              .height(34)
              .textAlign(TextAlign.Center)
              .borderRadius(17)
              .backgroundColor(exp.isFinished() ? $r('app.color.success') : $r('app.color.notice_on'))
          }
          Text(exp.isFinished() ? '完成' : '进行中')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(exp.finishText())
            .fontSize(13)
            .fontColor(exp.isFinished() ? $r('app.color.success') : $r('app.color.app_primary'))
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }, (exp: Expedition, idx: number) => `${idx}_${exp.status}`)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  transformerCard(note: DailyNote) {
    Row({ space: 10 }) {
      MetaIcon({ category: 'ItemIcon', name: 'UI_ItemIcon_220021', iconSize: 24, remoteFallback: true })
        .opacity(note.transformer.isReady() ? 1 : 0.55)
      Column({ space: 2 }) {
        Text('参量质变仪')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Text(!note.transformer.isReady() ? `剩余 ${note.transformer.text()}` : '已就绪，可使用')
          .fontSize(12)
          .fontColor(note.transformer.isReady() ? $r('app.color.success') : $r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  notifySettingCard() {
    Column({ space: 10 }) {
      Row() {
        Text('阈值通知')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (!this.allowNotify) {
          Button('授权通知')
            .fontSize(12)
            .height(26)
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick(() => {
              const host = this.getUIContext().getHostContext();
              if (host === undefined) {
                return;
              }
              NotificationHelper.requestPermission(host as common.UIAbilityContext).then((ok: boolean) => {
                this.allowNotify = ok;
                this.toast(ok ? '通知已授权' : '授权失败，可到系统设置开启');
              });
            })
        } else {
          Text('已授权')
            .fontSize(12)
            .fontColor($r('app.color.success'))
        }
      }
      .width('100%')

      // 通知开关
      Row({ space: 10 }) {
        Column({ space: 6 }) {
          this.flagToggle('树脂', NotifyFlags.RESIN)
          this.flagToggle('派遣', NotifyFlags.EXPEDITION)
          this.flagToggle('每日', NotifyFlags.DAILY_TASK)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Column({ space: 6 }) {
          this.flagToggle('参变仪', NotifyFlags.TRANSFORMER)
          this.flagToggle('洞天宝钱', NotifyFlags.HOME_COIN)
          Text(' ')
            .fontSize(14)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('树脂阈值')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        ForEach([80, 120, 160] as number[], (th: number) => {
          Text(`${th}`)
            .fontSize(13)
            .fontColor(this.vm.resinThreshold === th ? Color.White : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(this.vm.resinThreshold === th ? $r('app.color.app_primary') : $r('app.color.app_primary_bg'))
            .onClick(() => {
              this.vm.setResinThreshold(th).then(() => {
              });
            })
        }, (th: number) => `r_${th}`)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('宝钱阈值')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        ForEach([1200, 1800, 2400] as number[], (th: number) => {
          Text(`${th}`)
            .fontSize(13)
            .fontColor(this.vm.homeThreshold === th ? Color.White : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(this.vm.homeThreshold === th ? $r('app.color.app_primary') : $r('app.color.app_primary_bg'))
            .onClick(() => {
              this.vm.setHomeThreshold(th).then(() => {
              });
            })
        }, (th: number) => `h_${th}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  flagToggle(label: string, flag: number) {
    Row({ space: 8 }) {
      Text(this.vm.notifyFlags & flag ? '☑' : '☐')
        .fontSize(16)
        .fontColor(this.vm.notifyFlags & flag ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.vm.toggleFlag(flag).then(() => {
          });
        })
    }
  }

  @Builder
  autoRefreshBar() {
    Row({ space: 8 }) {
      Text(this.vm.isAutoRunning ? '自动刷新已开启' : '自动刷新已关闭')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(`上次刷新：${this.vm.lastRefreshAt > 0 ? DateUtil.formatTimestamp(this.vm.lastRefreshAt) : '--'}`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
  }

  build() {
    Column() {
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else if (this.currentUid.length === 0) {
        Column({ space: 14 }) {
          NavIcon({ name: 'Passport', iconSize: 60 })
          Text('请先选择默认 UID')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Button('去「账号与数据」选择')
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick(() => {
              router.pushUrl({ url: 'pages/UserPage' });
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 顶部操作行：对齐 Windows（立即刷新 / 通知设置 图标+文字小按钮，一行右对齐）
        Row({ space: 6 }) {
          Text('实时便笺')
            .fontSize($r('app.float.page_title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
          this.headerIconButton('DailyNote', this.vm.isRefreshing ? '刷新中...' : '立即刷新', false, () => {
            this.vm.refresh(this.currentUid).then((ok: boolean) => {
              this.toast(ok ? '已刷新' : this.vm.message);
            });
          })
          this.headerIconButton('', '通知设置', true, () => {
            const anim: ScrollAnimationOptions = { duration: 200, curve: Curve.EaseOut };
            const so: ScrollOptions = { xOffset: 0, yOffset: 0, animation: anim };
            this.settingRef.scrollTo(so);
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        // 宽屏：右侧立绘渐变背景 + 左侧数据面板限宽；窄屏：单列
        Stack({ alignContent: Alignment.Center }) {
          if (this.isWide) {
            // 右侧立绘背景（渐变 + 本地胡桃横幅，对齐 Windows 版背景氛围）
            Column()
              .width('100%')
              .height('100%')
              .linearGradient({
                angle: 135,
                colors: [
                  [('app.color.ambient_gradient_start'), 0.0],
                  [('app.color.ambient_gradient_mid'), 0.5],
                  [('app.color.ambient_gradient_end'), 1.0],
                ],
              })
            Image($r('app.media.hutao_daily_banner'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .opacity(0.14)
          }
          Scroll(this.settingRef) {
            Column({ space: 10 }) {
              this.autoRefreshBar()
              if (this.vm.note === undefined) {
                Column({ space: 12 }) {
                  LoadingProgress()
                    .width(40)
                    .height(40)
                    .color($r('app.color.app_primary'))
                  Text('加载中...')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  if (this.vm.message.length > 0) {
                    Text(this.vm.message)
                      .fontSize(13)
                      .fontColor($r('app.color.danger'))
                      .textAlign(TextAlign.Center)
                  }
                  if (this.vm.needGeetest) {
                    Button('去完成人机验证')
                      .fontSize(14)
                      .height(40)
                      .backgroundColor($r('app.color.app_primary'))
                      .fontColor(Color.White)
                      .onClick(() => {
                        this.goGeetest();
                      })
                    Text('验证完成后返回本页会自动重试拉取')
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                  }
                }
                .width('100%')
                .padding({ top: 60, bottom: 60 })
              } else {
                this.resinCard(this.vm.note)
                this.taskCard(this.vm.note)
                this.expeditionCard(this.vm.note)
                this.transformerCard(this.vm.note)
              }
              this.notifySettingCard()
              Text('提示：在「设置 → 实时便笺」可调整自动刷新间隔')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 16 })
            .alignItems(HorizontalAlign.Center)
            .constraintSize({ maxWidth: this.isWide ? 440 : 9999 })
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .backgroundColor(this.isWide ? '#00000000' : $r('app.color.page_background'))
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
