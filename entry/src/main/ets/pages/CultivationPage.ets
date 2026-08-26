/**
 * CultivationPage.ets（@Entry）
 * 养成计划：候选角色（角色列表）→ 勾选 + 目标等级 → 批量计算材料消耗 → 材料清单。
 * 数据源：character/list（角色）+ batch_compute（材料）。
 */
import { router } from '@kit.ArkUI';
import { CultivationViewModel, CultivateTarget } from '../viewmodel/CultivationViewModel';
import { CalItem } from '../model/Calculate';
import { elementName } from '../model/CharacterData';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { NavIcon } from '../components/NavIcon';
import { MetaIcon } from '../components/MetaIcon';
import { WikiMetaService } from '../service/WikiMetaService';

@Entry
@Component
export struct CultivationPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: CultivationViewModel = new CultivationViewModel();
  /** 目标等级输入（临时） */
  @State levelTmp: string = '';

  aboutToAppear(): void {
    this.loadData();
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
    PageHeader({ title: '养成计划', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
      Button('刷新')
        .fontSize(13)
        .height(32)
        .backgroundColor($r('app.color.app_primary_bg'))
        .fontColor($r('app.color.app_primary'))
        .onClick(() => {
          this.loadData();
        })
    }
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'Cultivation', iconSize: 60 })
      Text('需登录后使用养成计划')
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
  targetRow(target: CultivateTarget, idx: number) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (target.selected) {
          Circle()
            .width(58)
            .height(58)
            .fill($r('app.color.app_primary_bg'))
        } else {
          Circle()
            .width(58)
            .height(58)
            .fill($r('app.color.card_background'))
        }
        if (target.icon.length > 0) {
          // 官方图标名（UI_AvatarIcon_xxx）或 URL
          if (target.icon.startsWith('http')) {
            Image(target.icon)
              .width(52)
              .height(52)
              .objectFit(ImageFit.Cover)
              .borderRadius(26)
          } else {
            MetaIcon({ category: 'AvatarIcon', name: target.icon, iconSize: 52 })
              .borderRadius(26)
              .clip(true)
          }
        } else if (WikiMetaService.iconOfAvatar(target.avatarId).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(target.avatarId), iconSize: 52 })
            .borderRadius(26)
            .clip(true)
        } else {
          Text(target.name.length > 0 ? target.name.substring(0, 1) : '◇')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(52)
            .height(52)
            .textAlign(TextAlign.Center)
            .borderRadius(26)
            .backgroundColor($r('app.color.app_primary'))
        }
      }
      Column({ space: 3 }) {
        Row({ space: 4 }) {
          Text(target.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(elementName(target.element))
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        Text(`当前 Lv.${target.level}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Row({ space: 6 }) {
          Text('目标')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
          Text(`${target.targetLevel}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary'))
          Text('级')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(target.selected ? '✓' : '○')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(target.selected ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(target.selected ? $r('app.color.app_primary_bg') : $r('app.color.page_background'))
    .border({ width: 1, color: target.selected ? $r('app.color.app_primary') : $r('app.color.divider') })
    .onClick(() => {
      this.vm.toggle(idx);
    })
  }

  /** 快速设置目标（90/80/70/60） */
  @Builder
  quickLevelBar() {
    Row({ space: 6 }) {
      Text('目标等级')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
      ForEach([60, 70, 80, 90], (lv: number) => {
        Text(`${lv}`)
          .fontSize(11)
          .fontColor($r('app.color.app_primary'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(9)
          .backgroundColor($r('app.color.app_primary_bg'))
          .onClick(() => {
            for (let i = 0; i < this.vm.targets.length; i++) {
              if (this.vm.targets[i].selected) {
                this.vm.targets[i].targetLevel = lv;
              }
            }
          })
      }, (lv: number) => `quicklv_${lv}`)
      Blank()
    }
    .width('100%')
  }

  @Builder
  materialRow(item: CalItem) {
    Row({ space: 8 }) {
      Text(item.name.length > 0 ? item.name.substring(0, 1) : '◇')
        .fontSize(13)
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .borderRadius(8)
        .backgroundColor($r('app.color.app_primary_bg'))
      Text(item.name)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`× ${item.num}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_primary'))
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  resultSection() {
    if (this.vm.result !== undefined && this.vm.result.overallConsume.length > 0) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'Cultivation', iconSize: 20 })
          Text('所需材料汇总')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(`${this.vm.selectedCount} 个角色`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        ForEach(this.vm.result.overallConsume, (item: CalItem) => {
          this.materialRow(item)
        }, (item: CalItem) => `cal_item_${item.id}`)
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
            if (this.vm.targets.length === 0) {
              Text(this.vm.message.length > 0 ? this.vm.message : '暂无角色数据')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ top: 30, bottom: 30 })
                .textAlign(TextAlign.Center)
            } else {
              // 操作区
              Column({ space: 8 }) {
                this.quickLevelBar()
                Row({ space: 8 }) {
                  Button(`已选 ${this.vm.selectedCount} 个角色`)
                    .fontSize(12)
                    .height(30)
                    .layoutWeight(1)
                    .backgroundColor($r('app.color.card_background'))
                    .fontColor($r('app.color.text_primary'))
                  Button(this.vm.computing ? '计算中...' : '计算材料')
                    .fontSize(12)
                    .height(30)
                    .layoutWeight(1)
                    .backgroundColor($r('app.color.app_primary'))
                    .fontColor(Color.White)
                    .onClick(() => {
                      this.vm.compute(this.currentUid).then(() => {
                        this.toast(this.vm.message.length > 0 ? this.vm.message : '计算完成');
                      });
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .borderRadius($r('app.float.card_radius'))
              .backgroundColor($r('app.color.card_background'))
              .border({ width: 1, color: $r('app.color.divider') })

              // 结果区
              this.resultSection()

              // 候选角色网格
              Row() {
                Text('选择角色')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text(`共 ${this.vm.targets.length} 名`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')

              Column({ space: 8 }) {
                ForEach(this.vm.targets, (target: CultivateTarget, idx: number) => {
                  this.targetRow(target, idx)
                }, (target: CultivateTarget, idx: number) => `cult_${target.avatarId}`)
              }
              .width('100%')
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
  }
}
