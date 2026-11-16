/**
 * HomeSignInCard.ets
 * 主页签到卡（对齐 Windows HomeCardSignInCard）：
 * 头部（图标+累计天数+UID）、本月奖励网格（7 列，已签置灰打勾）、底部签到/补签按钮。
 * 标题行打开签到页，底部按钮执行对应的签到操作。
 */
import { SignInInfo, SignInReward } from '../model/SignInInfo';
import { NavIcon } from './NavIcon';
import { MetaIcon } from './MetaIcon';
import { MetaMaterial, WikiMetaService } from '../service/WikiMetaService';
import { AppButtonModifier, CardSurfaceModifier } from '../common/UiSurface';
import { FrameCallback } from '@kit.ArkUI';

class SignInRewardScrollFrame extends FrameCallback {
  private readonly scroll: () => void;
  constructor(scroll: () => void) { super(); this.scroll = scroll; }
  onIdle(_timeLeftInNano: number): void { this.scroll(); }
}

@Component
export struct HomeSignInCard {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('helpLocaleVersion') @Watch('loadRewardIcons') localeVersion: number = 0;
  @Prop @Watch('scheduleRewardScroll') uid: string = '';
  @Prop @Watch('scheduleRewardScroll') info: SignInInfo | undefined = undefined;
  @Prop @Watch('scheduleRewardScroll') loaded: boolean = false;
  @Prop signing: boolean = false;
  /** 今日日期（天） */
  @Prop todayDay: number = 1;
  @State rewardIcons: Map<string, string> = new Map();
  private attached: boolean = false;
  private iconRevision: number = 0;
  private readonly rewardScroller: Scroller = new Scroller();
  private scrollQueued: boolean = false;
  private rewardOwner: string = '';
  private positionedDays: number = -1;
  /** 打开每日签到页 */
  onTap: () => void = () => {
  };
  /** 点击签到 */
  onSignIn: () => void = () => {
  };
  /** 点击补签 */
  onResignIn: () => void = () => {
  };

  aboutToAppear(): void {
    this.attached = true;
    this.loadRewardIcons();
    this.scheduleRewardScroll();
  }

  /** 等本帧奖励网格完成布局，再定位当前领取行；图标或主题更新不打断手动滚动。 */
  private scheduleRewardScroll(): void {
    if (!this.attached || !this.loaded || !this.fillHeight || this.info === undefined || this.scrollQueued) { return; }
    this.scrollQueued = true;
    this.getUIContext().postFrameCallback(new SignInRewardScrollFrame((): void => {
      this.scrollQueued = false;
      const info: SignInInfo | undefined = this.info;
      if (!this.attached || !this.loaded || !this.fillHeight || info === undefined || info.rewards.length === 0) { return; }
      const owner: string = `${this.uid}_${info.currentMonth}`;
      if (owner === this.rewardOwner && this.positionedDays === info.signedDays) { return; }
      const justClaimed: boolean = owner === this.rewardOwner && this.positionedDays >= 0 && info.signedDays > this.positionedDays;
      const index: number = Math.max(0, Math.min(info.rewards.length - 1, info.signedDays - (justClaimed ? 1 : 0)));
      this.rewardScroller.scrollToIndex(Math.floor(index / 7) * 7, false, ScrollAlign.START);
      this.rewardOwner = owner;
      this.positionedDays = info.signedDays;
    }));
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.iconRevision++;
  }

  private loadRewardIcons(): void {
    if (!this.attached) { return; }
    const revision: number = ++this.iconRevision;
    WikiMetaService.getMaterials().then((materials: Map<number, MetaMaterial>) => {
      if (!this.attached || revision !== this.iconRevision) { return; }
      const icons: Map<string, string> = new Map();
      materials.forEach((material: MetaMaterial) => {
        if (material.n.length > 0 && material.i.length > 0) { icons.set(material.n, material.i); }
      });
      materials.forEach((material: MetaMaterial) => {
        if (material.canonicalName.length > 0 && material.i.length > 0) { icons.set(material.canonicalName, material.i); }
      });
      this.rewardIcons = icons;
    });
  }

  @Builder
  loadingView() {
    Column({ space: 8 }) {
      LoadingProgress()
        .width(24)
        .height(24)
        .color($r('app.color.app_primary'))
      Text('签到信息加载中...')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  emptyView() {
    Column({ space: 8 }) {
      NavIcon({ name: 'CheckIn', iconSize: 28 })
      Text('暂无签到数据')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(this.fillHeight ? 136 : 140)
    .justifyContent(FlexAlign.Center)
  }

  /** 该日奖励是否已领取（渲染期读取组件状态，签到/刷新后格子状态实时变化；
   *  注意 @Builder 多参数按值传递不参与刷新，故 isSigned 不能作为参数传入） */
  private isDaySigned(day: number): boolean {
    return this.info !== undefined && day <= this.info.signedDays;
  }

  /** 单个奖励格（参数只保留 ForEach 项，领取状态在渲染期计算） */
  @Builder
  awardCell(reward: SignInReward) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (reward.icon.startsWith('http')) {
          Image(reward.icon)
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
            .borderRadius(7)
            .backgroundColor($r('app.color.app_primary_bg'))
            .opacity(this.isDaySigned(reward.day) ? 0.35 : 1)
        } else {
          // 图标为物品 ID/名：尝试 rawfile ItemIcon 材料映射，未命中显示礼包图标
          MetaIcon({ category: 'ItemIcon', name: this.rewardIcons.get(reward.name) ?? '', iconSize: 22, remoteFallback: true })
            .opacity(this.isDaySigned(reward.day) ? 0.35 : 1)
        }
        if (this.isDaySigned(reward.day)) {
          Text('✓')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.success'))
        }
        Stack({ alignContent: Alignment.BottomEnd }) {
          Text(`×${reward.count}`)
            .fontSize(8)
            .fontColor($r('app.color.text_secondary'))
        }
        .width(24)
        .height(24)
      }
      .width(22)
      .height(22)
      Text(`${reward.day}日`)
        .fontSize(9)
        .fontColor(this.isDaySigned(reward.day) ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        .opacity(this.isDaySigned(reward.day) ? 0.6 : 1)
    }
    .width('100%')
    .height(40)
    .padding(2)
    .borderRadius(8)
    .backgroundColor(this.isDaySigned(reward.day) ? $r('app.color.card_inner_tint') : Color.Transparent)
  }

  /** 自然模式展示完整月表；40vp 奖励格加 2vp 行间距，不能按视口压缩格子。 */
  static gridHeight(count: number): number {
    const rows: number = Math.ceil(count / 7);
    return rows * 40 + Math.max(0, rows - 1) * 2;
  }

  /** 是否撑满 Grid 单元格高度（行内等高） */
  @Prop @Watch('scheduleRewardScroll') fillHeight: boolean = false;

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        NavIcon({ name: 'CheckIn', iconSize: 20 })
        Column({ space: 0 }) {
          Text('每日签到').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          if (this.info !== undefined) {
            Text(`本月已签 ${this.info.signedDays} 天`).fontSize(12).fontColor($r('app.color.text_secondary'))
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.uid.length > 0) {
          Text(this.uid).fontSize(12).fontColor($r('app.color.app_primary_text'))
        }
      }.width('100%').height(44).flexShrink(0).focusable(true).hoverEffect(HoverEffect.Highlight)
        .accessibilityDescription('打开每日签到').onClick(() => this.onTap())

      if (!this.loaded) {
        this.loadingView()
      } else if (this.info === undefined || this.info.rewards.length === 0) {
        this.emptyView()
      } else {
        Grid(this.rewardScroller) {
          ForEach(this.info.rewards, (reward: SignInReward) => {
            GridItem() {
              this.awardCell(reward)
            }.height(40)
          }, (reward: SignInReward) => `sign_${reward.day}_${reward.name}_${reward.count}_${reward.icon}_${this.info?.signedDays}`)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .columnsGap(2).rowsGap(2).width('100%')
        .height(this.fillHeight ? undefined : HomeSignInCard.gridHeight(this.info.rewards.length))
        .layoutWeight(this.fillHeight ? 1 : 0)
        .scrollBar(this.fillHeight ? BarState.Auto : BarState.Off)
        .enableScrollInteraction(this.fillHeight)
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })

        Divider().width('100%').color($r('app.color.divider'))

        Row({ space: 8 }) {
          Button(this.info.isTodaySigned(this.todayDay) ? '今日已签' : '签到', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .fontSize(13).height(44).layoutWeight(1)
            .enabled(!this.info.isTodaySigned(this.todayDay) && !this.signing)
            .onClick(() => this.onSignIn())
          Button('补签', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .fontSize(13).height(44).layoutWeight(1)
            .onClick(() => this.onResignIn())
        }.width('100%').height(44).flexShrink(0)
      }
    }
    .width('100%').height(this.fillHeight ? '100%' : undefined).padding(12).borderRadius(12)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }
}
