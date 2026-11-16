/**
 * UserPage.ets（@Entry）
 * 账号与数据：账号列表/添加/删除/切换；游戏角色绑定与默认 UID 选择；退出登录。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { UserAccountItem, UserRoleItem, UserViewModel } from '../viewmodel/UserViewModel';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { NavIcon } from '../components/NavIcon';
import { MetaIcon } from '../components/MetaIcon';
import { AppButtonModifier, CardSurfaceModifier, UiSurface } from '../common/UiSurface';

interface UserTravelToolParams {
  kind: string;
}

@Entry
@Component
export struct UserPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State vm: UserViewModel = new UserViewModel();
  @State actionPending: boolean = false;
  @State reordering: boolean = false;
  private stopWatching: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.vm.activate();
    this.actionPending = false;
    this.reordering = false;
    this.stopWatching = this.vm.watchSession((): void => {
      this.vm.load();
    });
    this.vm.load();
  }

  onPageShow(): void {
    if (!this.actionPending) { this.vm.load(); }
  }

  aboutToDisappear(): void {
    this.stopWatching?.();
    this.stopWatching = undefined;
    this.vm.dispose();
  }

  toast(msg: string): void {
    if (this.stopWatching === undefined) { return; }
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1800 });
  }

  async runAccountAction(action: () => Promise<string>): Promise<void> {
    const subscription: (() => void) | undefined = this.stopWatching;
    if (this.actionPending || subscription === undefined) { return; }
    this.actionPending = true;
    try {
      const message: string = await action();
      if (this.stopWatching === subscription) { this.toast(message); }
    } catch (e) {
      if (this.stopWatching !== subscription) { return; }
      await this.vm.load();
      if (this.stopWatching === subscription) {
        this.toast(e instanceof Error ? e.message : '账号操作失败，请稍后重试');
      }
    } finally {
      if (this.stopWatching === subscription) { this.actionPending = false; }
    }
  }

  async copyCookie(userId?: number): Promise<string> {
    const cookie: string = userId === undefined
      ? this.vm.cookieForClipboard() : await this.vm.savedCookieForClipboard(userId);
    if (cookie.length === 0) { return '该账号没有可复制的凭证'; }
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cookie);
    try { await pasteboard.getSystemPasteboard().setData(data); }
    catch (e) { throw new Error('复制 Cookie 失败，请稍后重试'); }
    return 'Cookie 已复制到剪贴板';
  }

  private accountMenu(user: UserAccountItem): MenuElement[] {
    return [
      { value: $r('app.string.ui_user_copy_cookie_action'), enabled: user.canSwitch, action: (): void => {
        this.runAccountAction((): Promise<string> => this.copyCookie(user.id));
      } },
      { value: $r('app.string.ui_account_insights_delete'), action: (): void => { this.confirmDelete(user); } }
    ];
  }

  private moveAccount(userId: number, direction: number): void {
    this.runAccountAction(async (): Promise<string> => {
      await this.vm.moveUser(userId, direction);
      return '账号顺序已保存';
    });
  }

  goLogin(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginPage' }).catch((): void => {
      this.toast('无法打开登录页，请稍后重试');
    });
  }

  goTravelTools(): void {
    if (this.actionPending || !this.vm.canOpenTravelTools()) { return; }
    const params: UserTravelToolParams = { kind: 'toolbox' };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/OfficialWebPage', params: params }).catch((): void => {
      this.toast('无法打开旅行工具，请稍后重试');
    });
  }

  @Builder
  header() {
    PageHeader({ title: $r('app.string.ui_section_account'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp })
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'Passport', iconSize: 64 })
      Text($r('app.string.ui_settings_not_logged_in'))
        .fontSize($r('app.float.title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('登录后可管理账号、绑定游戏角色并同步祈愿与便笺数据')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.page_title_login'), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
        .enabled(!this.actionPending)
        .onClick(() => {
          this.goLogin();
        })
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  accountCard(user: UserAccountItem) {
    Row({ space: 12 }) {
      // 优先加载真实头像；头像不可用则用昵称首字占位
      if (user.avatar.length > 0) {
        Image(user.avatar)
          .width(44)
          .height(44)
          .borderRadius(22)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.app_primary_bg'))
      } else {
        Text(user.displayName.length > 0 ? user.displayName.substring(0, 1) : '?')
          .fontSize(20)
          .fontColor($r('app.color.on_accent'))
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .borderRadius(22)
          .backgroundColor($r('app.color.app_primary'))
      }
      Column({ space: 3 }) {
        Text(user.displayName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text(`米游社 UID ${user.accountId}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.reordering) {
        Button('上移', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44)
          .enabled(!this.actionPending && user.canMoveUp)
          .onClick(() => { this.moveAccount(user.id, -1); })
        Button('下移', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44)
          .enabled(!this.actionPending && user.canMoveDown)
          .onClick(() => { this.moveAccount(user.id, 1); })
      } else if (user.isSelected) {
        Text('当前')
          .fontSize(11)
          .fontColor($r('app.color.app_primary_text'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor($r('app.color.app_primary_bg'))
      } else if (user.canSwitch) {
        Button('切换', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44)
          .enabled(!this.actionPending)
          .onClick(() => {
            this.runAccountAction(async (): Promise<string> => {
              await this.vm.switchUser(user.id);
              return '已切换账号';
            });
          })
      } else {
        Text(user.isOversea ? '仅支持国服' : '待重新登录')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      if (!this.reordering) {
        Button('更多', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44)
          .enabled(!this.actionPending)
          .bindMenu(this.accountMenu(user), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  confirmDelete(user: UserAccountItem): void {
    this.getUIContext().showAlertDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: '删除账号',
      message: `确定删除「${user.displayName}」的本机登录凭证、角色绑定、便笺和签到缓存？`,
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {
        },
      },
      secondaryButton: {
        value: $r('app.string.ui_account_insights_delete'),
        fontColor: $r('app.color.danger'),
        action: () => {
          this.runAccountAction(async (): Promise<string> => {
            await this.vm.deleteUser(user.id);
            return '已删除账号';
          });
        },
      },
    });
  }

  @Builder
  roleSection() {
    Column({ space: 10 }) {
      Text('绑定角色')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Button('刷新凭证', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44).margin({ right: 8, bottom: 6 })
          .enabled(!this.actionPending)
          .onClick(() => {
            this.runAccountAction(async (): Promise<string> => {
              const ok: boolean = await this.vm.refreshCredentials();
              return ok ? '凭证已刷新' : '未能刷新登录凭证，请重试或重新登录';
            });
          })
        Button($r('app.string.ui_user_copy_cookie_action'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44).margin({ right: 8, bottom: 6 })
          .enabled(!this.actionPending)
          .onClick(() => {
            this.runAccountAction((): Promise<string> => this.copyCookie());
          })
        Button('刷新角色', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44).margin({ right: 8, bottom: 6 })
          .enabled(!this.actionPending)
          .onClick(() => {
            this.runAccountAction(async (): Promise<string> => {
              const count: number = await this.vm.refreshRoles();
              return count > 0 ? `已同步 ${count} 个角色` : '该账号暂无绑定的国服角色';
            });
          })
        Button('旅行工具', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .fontSize(12)
          .height(44).margin({ bottom: 6 })
          .enabled(!this.actionPending && this.vm.canOpenTravelTools())
          .onClick(() => { this.goTravelTools(); })
      }
      .width('100%')

      if (this.vm.roles.length === 0) {
        Text('暂无角色数据，点击「刷新角色」从账号同步')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      ForEach(this.vm.roles, (role: UserRoleItem) => {
        Row({ space: 10 }) {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 2 }) {
              if (role.avatarIcon.length > 0) {
                MetaIcon({ category: 'AvatarIconCircle', name: role.avatarIcon, iconSize: 28, circular: true,
                  remoteFallback: true })
              } else {
                NavIcon({ name: 'WikiAvatar', iconSize: 28 })
              }
              Text('刷新头像')
                .fontSize(9)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .width(50)
          .height(48)
          .padding(3)
          .enabled(!this.actionPending && role.canRefreshAvatar)
          .accessibilityText(`刷新 ${role.nickname} 的头像`)
          .onClick(() => {
            this.runAccountAction(async (): Promise<string> => {
              const ok: boolean = await this.vm.refreshRoleAvatar(role.gameUid, role.userId);
              return ok ? '角色头像已刷新' : '暂无可用角色头像，请稍后重试';
            });
          })
          Row({ space: 10 }) {
            Text(role.isDefault ? '◉' : '○')
              .fontSize(16)
              .fontColor(role.isDefault ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
            Column({ space: 2 }) {
              Text(role.nickname)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text(role.description)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (role.isDefault) {
              Text($r('app.string.ui_setting_control_material_default'))
                .fontSize(11)
                .fontColor($r('app.color.app_primary_text'))
            }
          }
          .layoutWeight(1)
          .constraintSize({ minHeight: 44 })
          .hoverEffect(HoverEffect.Highlight)
          .enabled(!this.actionPending)
          .onClick(() => {
            if (role.isDefault) { return; }
            this.runAccountAction(async (): Promise<string> => {
              await this.vm.setDefaultUid(role.gameUid, role.userId);
              return `已设为默认 UID ${role.gameUid}`;
            });
          })
        }
        .width('100%')
        .padding(10)
        .borderRadius(10)
        .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      }, (role: UserRoleItem): string => role.key())
    }
    .width('100%')
  }

  build() {
    Stack() {
      // 壁纸衬底：router 独立页透出壁纸，embed 内嵌时由壳层统一铺（组件内渲染为空）
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
      this.header()
      Scroll() {
        Column({ space: 12 }) {
          if (this.vm.message.length > 0) {
            Text(this.vm.message)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          if (!this.vm.loaded) {
            Blank().height(200)
          } else if (this.vm.currentAccount === undefined) {
            this.loginGuide()
            this.accountListCard()
          } else {
            Row({ space: 10 }) {
              if ((this.vm.currentAccount?.avatar ?? '').length > 0) {
                Image(this.vm.currentAccount?.avatar ?? '')
                  .width(52)
                  .height(52)
                  .borderRadius(26)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.app_primary_bg'))
              } else {
                Text(this.vm.currentAccount?.displayName.substring(0, 1) ?? '?')
                  .fontSize(22)
                  .fontColor($r('app.color.on_accent'))
                  .width(52)
                  .height(52)
                  .textAlign(TextAlign.Center)
                  .borderRadius(26)
                  .backgroundColor($r('app.color.app_primary'))
              }
              Column({ space: 4 }) {
                Text(this.vm.currentAccount?.displayName ?? '未命名账号')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text(`当前默认 UID ${this.vm.currentUid || '未选择'}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(14)
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.app_primary_bg'))

            this.roleSection()
            this.accountListCard()

            Button($r('app.string.ui_setting_hutao_passport_logout_action'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontColor($r('app.color.danger'))
              .width('100%')
              .height(44)
              .enabled(!this.actionPending)
              .onClick(() => {
                this.runAccountAction(async (): Promise<string> => {
                  await this.vm.logout();
                  return '已退出登录';
                });
              })
          }
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  accountListCard() {
    Column({ space: 8 }) {
      Row() {
        Text('账号列表')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.vm.users.length > 1 || this.reordering) {
          Button(this.reordering ? $r('app.string.ui_content_dialog_complete_primary_button_text') : '调整顺序', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .fontSize(12)
            .height(44)
            .margin({ right: 8 })
            .enabled(!this.actionPending)
            .onClick(() => { this.reordering = !this.reordering; })
        }
        Button('＋ 添加账号', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .fontSize(12)
          .height(44)
          .enabled(!this.actionPending)
          .onClick(() => {
            this.goLogin();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.users.length === 0) {
        Text('暂无账号')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      ForEach(this.vm.users, (user: UserAccountItem) => {
        this.accountCard(user)
      }, (user: UserAccountItem): string => user.key())
    }
    .width('100%')
  }
}
