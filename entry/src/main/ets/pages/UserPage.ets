/**
 * UserPage.ets（@Entry）
 * 账号与数据：账号列表/添加/删除/切换；游戏角色绑定与默认 UID 选择；退出登录。
 */
import { router } from '@kit.ArkUI';
import { UserViewModel } from '../viewmodel/UserViewModel';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { UserService } from '../service/UserService';
import { AppBackButton } from '../components/AppBackButton';
import { NavIcon } from '../components/NavIcon';

@Entry
@Component
export struct UserPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  // 全局登录态订阅：嵌入式（Index 宽屏容器内）不触发 onPageShow，靠 AppStorage 驱动刷新
  @StorageLink('isLoggedIn') @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  @StorageLink('currentUid') @Watch('onUidStateChanged') currentUid: string = '';
  @State vm: UserViewModel = new UserViewModel();
  @State loaded: boolean = false;
  // 页面级快照（避免嵌套 @Observed 不触发 UI 刷新）
  @State snapDisplayName: string = '';
  @State snapAvatar: string = '';
  @State snapUid: string = '';
  @State snapRoles: UserGameRole[] = [];
  @State snapUsers: User[] = [];
  /** 登录态变化刷新防抖（isLoggedIn/currentUid 成对写入，合并为一次 load） */
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.vm.load().then(() => {
      this.loaded = true;
      this.syncSnap();
    });
  }

  /** 页面显示/返回：同步登录态与角色绑定（登录/切换账号后立即刷新） */
  onPageShow(): void {
    this.vm.load().then(() => {
      this.loaded = true;
      this.syncSnap();
    });
  }

  /** 登录态变化（登录/退出/切号）：防抖后重载页面数据 */
  onLoginStateChanged(): void {
    this.scheduleRefresh();
  }

  /** 默认 UID 变化（绑定角色）：防抖后重载页面数据 */
  onUidStateChanged(): void {
    this.scheduleRefresh();
  }

  scheduleRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout(() => {
      this.vm.load().then(() => {
        this.loaded = true;
        this.syncSnap();
      });
    }, 150);
  }

  /** 同步全部显示快照到页面状态（@State 直接驱动 UI） */
  syncSnap(): void {
    const user: User | undefined = this.vm.currentUser;
    this.snapDisplayName = user !== undefined ? user.displayName : '';
    this.snapAvatar = user !== undefined ? user.avatar : '';
    this.snapUid = this.vm.currentUid;
    this.snapRoles = user !== undefined ? user.roles.slice() : [];
    this.snapUsers = this.vm.users.slice();
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  goLogin(): void {
    router.pushUrl({ url: 'pages/LoginPage' });
  }

  /** 账号栏显示米游社 UID（stuid/account_id）；绑定角色区显示原神 UID（role.gameUid） */
  displayUid(user: User): string {
    const accountId: string = user.stuid.length > 0 ? user.stuid : user.accountId;
    return accountId.length > 0 ? `米游社UID：${accountId}` : '米游社UID：--';
  }

  @Builder
  header() {
    Row() {
      if (!this.embedMode) {
        AppBackButton()
      }
      Text('账号与数据')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'Passport', iconSize: 64 })
      Text('未登录')
        .fontSize($r('app.float.title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('登录后可管理账号、绑定游戏角色并同步祈愿与便笺数据')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Button('去登录')
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.goLogin();
        })
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  accountCard(user: User) {
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
          .fontColor(Color.White)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .borderRadius(22)
          .backgroundColor($r('app.color.app_primary'))
      }
      Column({ space: 3 }) {
        Text(user.displayName.length > 0 ? user.displayName : '未命名账号')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        // 账号卡片展示游戏默认角色 UID（而非米游社账号 ID），避免误导
        Text(this.displayUid(user))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (user.isSelected) {
        Text('当前')
          .fontSize(11)
          .fontColor($r('app.color.app_primary'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor($r('app.color.app_primary_bg'))
      } else {
        Button('切换')
          .fontSize(12)
          .height(28)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick(() => {
            this.vm.switchUser(user.id).then(() => {
              this.syncSnap();
              this.toast('已切换账号');
            });
          })
      }
      Button('删除')
        .fontSize(12)
        .height(28)
        .backgroundColor($r('app.color.card_background'))
        .hoverEffect(HoverEffect.Highlight)
        .fontColor($r('app.color.danger'))
        .border({ width: 1, color: $r('app.color.divider') })
        .onClick(() => {
          this.confirmDelete(user);
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  confirmDelete(user: User): void {
    this.getUIContext().showAlertDialog({
      title: '删除账号',
      message: `确定删除账号「${user.displayName || '未命名'}」？其角色与本地数据将保留。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.vm.deleteUser(user.id).then(() => {
            this.syncSnap();
            this.toast('已删除');
          });
        },
      },
    });
  }

  @Builder
  roleSection() {
    Column({ space: 10 }) {
      Row() {
        Text('绑定角色（默认 UID）')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button('刷新角色')
          .fontSize(12)
          .height(26)
          .backgroundColor($r('app.color.app_primary_bg'))
          .fontColor($r('app.color.app_primary'))
          .onClick(() => {
            this.vm.refreshRoles().then((count: number) => {
              this.syncSnap();
              if (count > 0) {
                this.toast(`已同步 ${count} 个角色`);
              } else {
                this.toast('未同步到角色，请稍后重试或检查登录态');
              }
            }).catch((e: Error) => {
              this.toast(`角色同步失败：${e.message}`);
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.snapRoles.length === 0) {
        Text('暂无角色数据，点击「刷新角色」从账号同步')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      ForEach(this.snapRoles, (role: UserGameRole, index: number) => {
        Row({ space: 10 }) {
          Text(role.isDefault ? '◉' : '○')
            .fontSize(16)
            .fontColor(role.isDefault ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
          Column({ space: 2 }) {
            Text(role.nickname.length > 0 ? role.nickname : `旅行者${role.gameUid}`)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text(`UID ${role.gameUid} · ${role.region}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (role.isDefault) {
            Text('默认')
              .fontSize(11)
              .fontColor($r('app.color.app_primary'))
          }
        }
        .width('100%')
        .padding(10)
        .borderRadius(10)
        .backgroundColor($r('app.color.card_background'))
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.vm.setDefaultUid(role.gameUid).then(() => {
            this.syncSnap();
            this.toast(`已设为默认 UID：${role.gameUid}`);
          });
        })
      // key 含 isDefault：换默认后 ForEach 重建该行（仅 gameUid 不会触发 item 更新）
      }, (role: UserGameRole) => `${role.gameUid}_${role.isDefault ? 1 : 0}`)
    }
    .width('100%')
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 12 }) {
          if (!this.loaded) {
            Blank().height(200)
          } else if (this.vm.currentUser === undefined) {
            this.loginGuide()
            this.accountListCard()
          } else {
            Row({ space: 10 }) {
              if (this.snapAvatar.length > 0) {
                Image(this.snapAvatar)
                  .width(52)
                  .height(52)
                  .borderRadius(26)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.app_primary_bg'))
              } else {
                Text(this.snapDisplayName.length > 0 ? this.snapDisplayName.substring(0, 1) : '?')
                  .fontSize(22)
                  .fontColor(Color.White)
                  .width(52)
                  .height(52)
                  .textAlign(TextAlign.Center)
                  .borderRadius(26)
                  .backgroundColor($r('app.color.app_primary'))
              }
              Column({ space: 4 }) {
                Text(this.snapDisplayName.length > 0 ? this.snapDisplayName : '未命名账号')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text(`当前默认 UID：${this.snapUid.length > 0 ? this.snapUid : '未选择'}`)
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

            Button('退出登录')
              .width('100%')
              .height(44)
              .backgroundColor($r('app.color.card_background'))
        .hoverEffect(HoverEffect.Highlight)
              .fontColor($r('app.color.danger'))
              .border({ width: 1, color: $r('app.color.divider') })
              .onClick(() => {
                UserService.getInstance().logout().then(() => {
                  this.toast('已退出登录');
                  this.vm.currentUser = undefined;
                  this.vm.currentUid = '';
                  this.vm.load().then(() => {
                    this.syncSnap();
                    this.toast('已退出登录');
                  });
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
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
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
        Button('＋ 添加账号')
          .fontSize(12)
          .height(28)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick(() => {
            this.goLogin();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.snapUsers.length === 0) {
        Text('暂无账号')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      ForEach(this.snapUsers, (user: User) => {
        this.accountCard(user)
      }, (user: User) => `${user.id}`)
    }
    .width('100%')
  }
}
