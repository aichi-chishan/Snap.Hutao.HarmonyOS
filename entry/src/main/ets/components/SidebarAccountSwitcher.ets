import { RegionUtil } from '../common/Constants';
import { SurfaceClass, UiSurface } from '../common/UiSurface';
import { UserAccountItem, UserRoleItem, UserViewModel } from '../viewmodel/UserViewModel';
import { MetaIcon } from './MetaIcon';

interface SidebarToolboxParams {
  kind: string;
}

/** The navigation footer and its local-account popup share one bounded subscription. */
@Component
export struct SidebarAccountSwitcher {
  @Prop compact: boolean = false;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('currentUserName') currentUserName: string = '';
  @StorageProp('currentUserAvatar') currentUserAvatar: string = '';
  @StorageProp('appForeground') @Watch('foregroundChanged') appForeground: boolean = true;
  @State vm: UserViewModel = new UserViewModel(false);
  @State popupVisible: boolean = false;
  @State loading: boolean = false;
  @State busy: boolean = false;
  @State message: string = '';
  onOpenAccounts: () => void = () => {};
  private attached: boolean = false;
  private panelVersion: number = 0;
  private stopWatching: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.attached = true;
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.releasePanel();
  }

  foregroundChanged(): void {
    if (!this.appForeground) { this.dismiss(); }
  }

  private releasePanel(): void {
    this.panelVersion++;
    this.stopWatching?.();
    this.stopWatching = undefined;
    this.vm.dispose();
  }

  private dismiss(): void {
    this.popupVisible = false;
    this.releasePanel();
  }

  private open(): void {
    if (!this.attached) { return; }
    if (this.popupVisible) { this.dismiss(); return; }
    this.vm = new UserViewModel(false);
    this.popupVisible = true;
    const model: UserViewModel = this.vm;
    this.stopWatching = model.watchSession((): void => {
      if (this.popupVisible && this.vm === model) { this.loadPanel(); }
    });
    this.loadPanel();
  }

  private async loadPanel(): Promise<void> {
    const version: number = ++this.panelVersion;
    const model: UserViewModel = this.vm;
    this.loading = true;
    this.message = '';
    await model.load();
    if (this.attached && this.popupVisible && this.vm === model && this.panelVersion === version) {
      this.loading = false;
    }
  }

  private async run(action: () => Promise<string>): Promise<void> {
    if (!this.popupVisible || this.loading || this.busy) { return; }
    const version: number = this.panelVersion;
    const model: UserViewModel = this.vm;
    this.busy = true;
    this.message = '';
    try {
      const message: string = await action();
      if (this.popupVisible && this.vm === model && this.panelVersion === version) { this.message = message; }
    } catch (e) {
      if (this.popupVisible && this.vm === model && this.panelVersion === version) {
        this.message = e instanceof Error ? e.message : '账号操作失败，请重试';
      }
    } finally {
      if (this.attached) { this.busy = false; }
    }
  }

  private selectUser(user: UserAccountItem): void {
    if (!user.canSwitch || user.isSelected || user.isOversea) { return; }
    const model: UserViewModel = this.vm;
    this.run(async (): Promise<string> => {
      await model.switchUser(user.id);
      return '已切换账号';
    });
  }

  private selectRole(role: UserRoleItem): void {
    if (!role.canRefreshAvatar || role.isDefault || !RegionUtil.isCnUid(role.gameUid)) { return; }
    const model: UserViewModel = this.vm;
    this.run(async (): Promise<string> => {
      await model.setDefaultUid(role.gameUid, role.userId);
      return '已切换角色';
    });
  }

  private refreshCookie(): void {
    if (this.vm.currentAccount === undefined || !this.vm.currentAccount.canSwitch) { return; }
    const model: UserViewModel = this.vm;
    this.run(async (): Promise<string> => {
      const updated: boolean = await model.refreshCredentials();
      return updated ? 'Cookie 已刷新' : '请在账号页重新登录';
    });
  }

  private openLogin(): void {
    if (this.busy) { return; }
    this.dismiss();
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginPage' }).catch(() => this.routeFailed());
  }

  private openAccounts(): void {
    if (this.busy) { return; }
    this.dismiss();
    this.onOpenAccounts();
  }

  private openToolbox(): void {
    if (this.busy || this.loading || !this.vm.canOpenTravelTools()) { return; }
    this.dismiss();
    const params: SidebarToolboxParams = { kind: 'toolbox' };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/OfficialWebPage', params: params }).catch(() => this.routeFailed());
  }

  private routeFailed(): void {
    if (this.attached) {
      this.getUIContext().getPromptAction().showToast({
        message: '无法打开账号页面，请重试',
        systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
      });
    }
  }

  private roles(): UserRoleItem[] {
    return this.vm.roles.filter((role: UserRoleItem): boolean => role.canRefreshAvatar);
  }

  @Builder
  avatar(url: string, name: string) {
    if (url.length > 0) {
      Image(url).width(34).height(34).borderRadius(17).objectFit(ImageFit.Cover)
        .draggable(false).accessibilityLevel('no')
    } else {
      Text(name.substring(0, 1) || '旅').fontSize(16).fontColor($r('app.color.app_primary_text'))
        .width(34).height(34).textAlign(TextAlign.Center).borderRadius(17)
        .backgroundColor($r('app.color.app_primary_bg')).accessibilityLevel('no')
    }
  }

  @Builder
  footerAvatar() {
    if (this.currentUserAvatar.length > 0) {
      Image(this.currentUserAvatar).width(34).height(34).borderRadius(17).objectFit(ImageFit.Cover)
        .draggable(false).accessibilityLevel('no')
    } else {
      Text(this.currentUserName.substring(0, 1) || '旅').fontSize(16).fontColor($r('app.color.app_primary_text'))
        .width(34).height(34).textAlign(TextAlign.Center).borderRadius(17)
        .backgroundColor($r('app.color.app_primary_bg')).accessibilityLevel('no')
    }
  }

  @Builder
  actionIcon(slot: number) {
    if (slot === 0) {
      SymbolGlyph($r('sys.symbol.person_badge_plus')).fontSize(24).fontColor([$r('app.color.text_primary')])
    } else if (slot === 1) {
      SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(24).fontColor([$r('app.color.text_primary')])
    } else if (slot === 2) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(24).fontColor([$r('app.color.text_primary')])
    } else {
      SymbolGlyph($r('sys.symbol.person_2')).fontSize(24).fontColor([$r('app.color.text_primary')])
    }
  }

  private actionLabel(slot: number): ResourceStr {
    if (slot === 0) { return '米游社登录'; }
    if (slot === 1) { return '旅行工具'; }
    if (slot === 2) { return '刷新 Cookie'; }
    return $r('app.string.setting_account');
  }

  private actionEnabled(slot: number): boolean {
    if (this.busy) { return false; }
    if (slot === 1) { return !this.loading && this.vm.canOpenTravelTools(); }
    if (slot === 2) { return !this.loading && this.vm.currentAccount?.canSwitch === true; }
    return true;
  }

  private actionClicked(slot: number): void {
    if (slot === 0) { this.openLogin(); }
    else if (slot === 1) { this.openToolbox(); }
    else if (slot === 2) { this.refreshCookie(); }
    else { this.openAccounts(); }
  }

  @Builder
  actionButton(slot: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 5 }) {
        this.actionIcon(slot)
        Text(this.actionLabel(slot)).fontSize(12).fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center)
      }.justifyContent(FlexAlign.Center).width('100%')
    }
    .width('100%').height(70).padding(6).borderRadius(6).backgroundColor(Color.Transparent)
    .enabled(this.actionEnabled(slot)).hoverEffect(HoverEffect.Highlight).accessibilityGroup(true)
    .onClick(() => this.actionClicked(slot))
  }

  @Builder
  roleRow(role: UserRoleItem) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 9 }) {
        Column().width(3).height(22).borderRadius(2)
          .backgroundColor(role.isDefault ? $r('app.color.app_primary') : Color.Transparent)
        if (role.avatarIcon.length > 0) {
          MetaIcon({ category: 'AvatarIconCircle', name: role.avatarIcon, iconSize: 36, circular: true })
        } else {
          Image($r('app.media.nav_WikiAvatar')).width(36).height(36).objectFit(ImageFit.Contain)
        }
        Column({ space: 3 }) {
          Text(role.nickname).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(role.description).fontSize(11).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
    }
    .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 5, right: 8, top: 8, bottom: 8 })
    .borderRadius(6).backgroundColor(role.isDefault ? $r('app.color.card_inner_tint') : Color.Transparent)
    .enabled(!this.busy && !this.loading).accessibilitySelected(role.isDefault)
    .accessibilityGroup(true).hoverEffect(HoverEffect.Highlight).onClick(() => this.selectRole(role))
  }

  @Builder
  userRow(user: UserAccountItem) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 9 }) {
        Column().width(3).height(22).borderRadius(2)
          .backgroundColor(user.isSelected ? $r('app.color.app_primary') : Color.Transparent)
        this.avatar(user.avatar, user.displayName)
        Column({ space: 2 }) {
          Text(user.displayName).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!user.canSwitch) {
            Text(user.isOversea ? '仅支持国服' : '需重新登录').fontSize(11).fontColor($r('app.color.text_secondary'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
    }
    .width('100%').constraintSize({ minHeight: 56 }).padding({ left: 5, right: 8, top: 8, bottom: 8 })
    .borderRadius(6).backgroundColor(user.isSelected ? $r('app.color.card_inner_tint') : Color.Transparent)
    .enabled(!this.busy && !this.loading && user.canSwitch)
    .accessibilitySelected(user.isSelected).accessibilityGroup(true).hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.selectUser(user))
  }

  @Builder
  panel() {
    Row() {
      Scroll() {
        Column({ space: 2 }) {
          this.actionButton(0)
          Divider().color($r('app.color.divider'))
          Text('当前用户').fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary')).padding(6)
          this.actionButton(1)
          this.actionButton(2)
          Divider().color($r('app.color.divider'))
          this.actionButton(3)
        }.width('100%').padding(5)
      }.width(104).height('100%').scrollBar(BarState.Auto).backgroundColor($r('app.color.card_inner_tint'))
      Scroll() {
        Column({ space: 4 }) {
          if (this.loading || this.busy) {
            LoadingProgress().width(24).height(24).color($r('app.color.app_primary'))
          }
          if (this.roles().length > 0) {
            Text($r('app.string.ui_gacha_pivot_avatar')).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).width('100%').padding({ top: 2, bottom: 4 })
            ForEach(this.roles(), (role: UserRoleItem) => { this.roleRow(role) }, (role: UserRoleItem): string => role.key())
          }
          Text('用户').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .width('100%').padding({ top: 8, bottom: 4 })
          if (!this.loading && this.vm.users.length === 0) {
            Text('暂无本地账号').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').padding(8)
          }
          ForEach(this.vm.users, (user: UserAccountItem) => { this.userRow(user) }, (user: UserAccountItem): string => user.key())
          if (this.message.length > 0 || this.vm.message.length > 0) {
            Text(this.message || this.vm.message).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding(6)
          }
        }.width('100%').padding(10).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).height('100%').scrollBar(BarState.Auto)
    }.width('100%').height(360).borderRadius(8).clip(true)
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 10 }) {
        this.footerAvatar()
        if (!this.compact) {
          Text(this.currentUserName || $r('app.string.ui_settings_not_logged_in'))
            .fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('›').fontSize(20).fontColor($r('app.color.text_secondary')).accessibilityLevel('no')
        }
      }.width('100%')
    }
    .width('100%').constraintSize({ minHeight: 52 })
    .padding({ left: this.compact ? 3 : 6, right: this.compact ? 3 : 6, top: 8, bottom: 8 })
    .borderRadius(8).backgroundColor(this.popupVisible ? $r('app.color.card_inner_tint') : Color.Transparent)
    .accessibilityText('切换账号与角色').accessibilityGroup(true).hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.open())
    .bindPopup(this.popupVisible, {
      builder: (): void => { this.panel(); },
      width: 430,
      placement: Placement.RightBottom,
      enableArrow: false,
      focusable: true,
      autoCancel: true,
      systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
      backgroundBlurStyle: UiSurface.blurStyle(SurfaceClass.OVERLAY_MODAL, this.surfaceMode, this.surfaceLevel),
      popupColor: UiSurface.immersiveActive() ? Color.Transparent : $r('app.color.sheet_material_tint'),
      onStateChange: (event: PopupStateChangeParam): void => {
        if (this.attached && !event.isVisible && this.popupVisible) { this.dismiss(); }
      },
    })
  }
}
