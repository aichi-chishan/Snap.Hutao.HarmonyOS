/**
 * CultivationPage.ets（@Entry）
 * 养成计划：候选角色（角色列表）→ 勾选 + 目标等级 → 批量计算材料消耗 → 材料清单；
 * 计算结果可保存为持久化培养条目（多项目 + 材料勾选，对齐 Windows CultivationPage）。
 * 数据源：character/list（角色）+ batch_compute（材料）+ 本地计划库。
 */
import { router, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { CultivationViewModel, CultivateTarget } from '../viewmodel/CultivationViewModel';
import { CalItem } from '../model/Calculate';
import { elementName } from '../model/CharacterData';
import { CultivateEntry, CultivateEntryItem, CultivateProject } from '../data/repo/CultivationRepo';
import { ResinStatisticsService, ResinCategoryRow, ResinStatisticsResult } from '../service/ResinStatisticsService';
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
  /** 内容区宽 >=840 双栏（对齐 WikiAvatarPage 断点写法） */
  @State isWide: boolean = false;

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
    // 计划不依赖登录（本地库），进入页面即加载
    this.vm.loadPlan().then(() => {
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  /** 材料今日是否可刷（周一四/二五/三六轮换，周日全开；对齐 Windows Material.IsItemOfToday） */
  isTodayItem(itemId: number): boolean {
    return ResinStatisticsService.isItemOfToday(itemId, new Date().getDay());
  }

  /** 树脂统计行（Builder 内经方法读取，规避属性窄化与 @Builder 多参刷新问题） */
  resinRows(): ResinCategoryRow[] {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.rows : [];
  }

  hasResinRows(): boolean {
    return this.resinRows().length > 0;
  }

  resinTotalResin(): number {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.totalResin : 0;
  }

  resinTotalFragile(): number {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.totalFragile : 0;
  }

  resinTotalDays(): number {
    const stats: ResinStatisticsResult | undefined = this.vm.resinStats;
    return stats !== undefined ? stats.totalDays : 0;
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
        .hoverEffect(HoverEffect.Highlight)
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
          .hoverEffect(HoverEffect.Highlight)
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

  /** 结果区附加：保存到养成计划（对齐 Windows 条目持久化） */
  @Builder
  savePlanBar() {
    if (this.vm.result !== undefined && this.vm.result.overallConsume.length > 0) {
      Button(this.vm.planBusy ? '保存中...' : '保存计算结果到养成计划')
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .borderRadius(10)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.vm.saveResultToPlan().then((ok: boolean) => {
            this.toast(ok ? this.vm.message : (this.vm.message.length > 0 ? this.vm.message : '保存失败'));
          });
        })
    }
  }

  /** 项目切换条（chips + 新建/删除） */
  @Builder
  projectBar() {
    Row({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.vm.projects, (p: CultivateProject) => {
            Text(p.name)
              .fontSize(12)
              .fontColor(this.vm.currentProjectId === p.id ? Color.White : $r('app.color.text_primary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(this.vm.currentProjectId === p.id
                ? $r('app.color.app_primary') : $r('app.color.page_background'))
              .border({ width: 1, color: this.vm.currentProjectId === p.id
                ? $r('app.color.app_primary') : $r('app.color.divider') })
              .constraintSize({ minWidth: 48 })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.vm.selectProject(p.id);
              })
          }, (p: CultivateProject) => `proj_${p.id}_${p.name}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      Text('＋')
        .fontSize(16)
        .fontColor($r('app.color.app_primary'))
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .borderRadius(15)
        .backgroundColor($r('app.color.app_primary_bg'))
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          const name: string = `计划 ${this.vm.projects.length + 1}`;
          this.vm.createProject(name).then(() => {
            this.toast(`已创建「${name}」`);
          });
        })
      if (this.vm.projects.length > 1) {
        Text('🗑')
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .borderRadius(15)
          .backgroundColor($r('app.color.page_background'))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.confirmDeleteProject();
          })
      }
    }
    .width('100%')
  }

  /** 删除当前项目确认 */
  confirmDeleteProject(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除计划',
      message: '将删除当前计划及其全部培养目标与勾选进度，是否继续？',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.danger') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index !== 1) {
        return;
      }
      this.vm.deleteCurrentProject().then(() => {
        this.toast('已删除');
      });
    });
  }

  /** 条目内单个材料行（点击切换已备齐；已备齐划线置灰） */
  @Builder
  planItemRow(entry: CultivateEntry, item: CultivateEntryItem) {
    Row({ space: 8 }) {
      Text(item.finished ? '✓' : '○')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.finished ? $r('app.color.success') : $r('app.color.text_secondary'))
        .width(24)
      Text(item.name.length > 0 ? item.name.substring(0, 1) : '◇')
        .fontSize(13)
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .borderRadius(8)
        .backgroundColor($r('app.color.app_primary_bg'))
      Text(item.name)
        .fontSize(12)
        .fontColor(item.finished ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        .decoration({ type: item.finished ? TextDecorationType.LineThrough : TextDecorationType.None })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isTodayItem(item.itemId)) {
        Text('今日')
          .fontSize(9)
          .fontColor($r('app.color.notice_on'))
          .backgroundColor($r('app.color.notice_bg'))
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(6)
      }
      Text(`× ${item.count}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.finished ? $r('app.color.text_secondary') : $r('app.color.app_primary'))
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.vm.togglePlanItem(entry, item.id).then(() => {
      });
    })
  }

  /** 单个培养条目卡（角色 + 等级目标 + 材料勾选清单） */
  @Builder
  planEntryCard(entry: CultivateEntry) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          if (entry.icon.length > 0) {
            if (entry.icon.startsWith('http')) {
              Image(entry.icon)
                .width(40)
                .height(40)
                .objectFit(ImageFit.Cover)
                .borderRadius(20)
            } else {
              MetaIcon({ category: 'AvatarIcon', name: entry.icon, iconSize: 40 })
                .borderRadius(20)
                .clip(true)
            }
          } else if (WikiMetaService.iconOfAvatar(entry.avatarId).length > 0) {
            MetaIcon({ category: 'AvatarIcon', name: WikiMetaService.iconOfAvatar(entry.avatarId), iconSize: 40 })
              .borderRadius(20)
              .clip(true)
          } else {
            Text(entry.name.length > 0 ? entry.name.substring(0, 1) : '◇')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .borderRadius(20)
              .backgroundColor($r('app.color.app_primary'))
          }
        }
        Column({ space: 2 }) {
          Text(entry.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(`Lv.${entry.level} → Lv.${entry.targetLevel} · 已备齐 ${entry.finishedCount()}/${entry.items.length}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('删除')
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(9)
          .backgroundColor($r('app.color.page_background'))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.vm.removeEntry(entry).then(() => {
              this.toast('已移除培养目标');
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Divider()
        .color($r('app.color.divider'))
      ForEach(entry.items, (item: CultivateEntryItem) => {
        this.planItemRow(entry, item)
      }, (item: CultivateEntryItem) => `pe_${item.id}_${item.finished}_t${this.isTodayItem(item.itemId) ? 1 : 0}`)
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 树脂统计表头（树脂图标已内置 rawfile；脆弱树脂无图标用文字） */
  @Builder
  resinHeaderRow() {
    Row({ space: 6 }) {
      Text('类别')
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      Row({ space: 2 }) {
        MetaIcon({ category: 'ItemIcon', name: 'UI_ItemIcon_106', iconSize: 12 })
        Text('树脂')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(58)
      Text('脆弱')
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .width(44)
        .textAlign(TextAlign.Center)
      Text('天数')
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .width(48)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  /** 树脂统计单行（单参数 @Builder，按引用传递可动态渲染） */
  @Builder
  resinRow(row: ResinCategoryRow) {
    Row({ space: 6 }) {
      Column({ space: 1 }) {
        Text(row.title)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.demandText)
          .fontSize(9)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(`${row.totalResin}`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_primary'))
        .width(58)
        .textAlign(TextAlign.Center)
      Text(row.fragileResin > 0 ? `${row.fragileResin}` : '—')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width(44)
        .textAlign(TextAlign.Center)
      Text(`${row.days}天`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width(48)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /** 树脂换算统计卡（对齐 Windows 统计区：分类 × 总树脂 × 脆弱树脂 × 自然恢复天数） */
  @Builder
  resinSection() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('树脂统计')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('世界等级')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
        ForEach([5, 6, 7, 8, 9], (lv: number) => {
          Text(`${lv}`)
            .fontSize(10)
            .fontColor(this.vm.resinWorldLevel === lv ? Color.White : $r('app.color.text_secondary'))
            .width(24)
            .height(20)
            .textAlign(TextAlign.Center)
            .borderRadius(10)
            .backgroundColor(this.vm.resinWorldLevel === lv
              ? $r('app.color.app_primary') : $r('app.color.page_background'))
            .border({ width: 1, color: this.vm.resinWorldLevel === lv
              ? $r('app.color.app_primary') : $r('app.color.divider') })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.vm.setResinWorldLevel(lv).then(() => {
              });
            })
        }, (lv: number) => `resin_wl_${lv}_${this.vm.resinWorldLevel === lv ? 1 : 0}`)
      }
      .width('100%')
      if (this.hasResinRows()) {
        Row({ space: 8 }) {
          Text(`共需树脂 ${this.resinTotalResin()}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary'))
          Text(`脆弱 ×${this.resinTotalFragile()}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Text(`自然恢复约 ${this.resinTotalDays()} 天`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Blank()
        }
        .width('100%')
        this.resinHeaderRow()
        ForEach(this.resinRows(), (row: ResinCategoryRow) => {
          this.resinRow(row)
        }, (row: ResinCategoryRow) => `resin_row_${row.kind}_${row.totalResin}_${row.runs}`)
      } else {
        Text('当前计划暂无未完成的树脂类材料（摩拉/经验书/天赋书/武器突破/Boss 掉落）')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 养成计划区（项目条 + 条目清单；置于计算区上方，可持续追踪） */
  @Builder
  planSection() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        NavIcon({ name: 'Cultivation', iconSize: 20 })
        Text('养成计划')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.vm.planEntries.length} 个目标`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      this.projectBar()
      // 树脂换算统计（当前项目聚合，展示在项目详情顶部；对齐 Windows 统计区）
      this.resinSection()
      if (this.vm.planEntries.length === 0) {
        Text('暂无培养目标：勾选角色并计算材料后，点「保存计算结果到养成计划」')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .textAlign(TextAlign.Center)
      } else {
        ForEach(this.vm.planEntries, (entry: CultivateEntry) => {
          this.planEntryCard(entry)
        }, (entry: CultivateEntry) => `plan_${entry.id}_${entry.finishedCount()}`)
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 计算结果材料汇总 */
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

  /** 宽屏左栏：养成计划（项目/树脂统计/条目） */
  @Builder
  planColumn() {
    Column({ space: 10 }) {
      this.planSection()
    }
    .width('100%')
  }

  /** 右栏（窄屏下半区）：计算操作 + 结果 + 候选角色 */
  @Builder
  computeColumn() {
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
          .hoverEffect(HoverEffect.Highlight)
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
    this.savePlanBar()

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
          if (this.vm.targets.length === 0) {
            Text(this.vm.message.length > 0 ? this.vm.message : '暂无角色数据')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 30, bottom: 30 })
              .textAlign(TextAlign.Center)
          } else if (this.isWide) {
            // 宽屏双栏：左计划 / 右计算（内容区宽 >=840，对齐页面断点规范）
            Row({ space: 10 }) {
              Column() {
                this.planColumn()
              }
              .layoutWeight(1)

              Column() {
                this.computeColumn()
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column({ space: 10 }) {
              this.planColumn()
              this.computeColumn()
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.isWide = (newValue.width as number) >= 840;
    })
  }
}
