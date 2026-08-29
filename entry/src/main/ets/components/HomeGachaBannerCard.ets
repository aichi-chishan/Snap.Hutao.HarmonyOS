/**
 * HomeGachaBannerCard.ets
 * 主页祈愿横幅池卡（对齐 Windows 主页左侧卡池横幅）：
 * 支持两种数据源：
 *  - 网络卡池（ActCalendarEntry）：池名 + 剩余时间 + 角色头像行 + 日期区间
 *  - 本地祈愿统计（HomePoolSummary）：池名 + 总抽数 + 五星/四星统计（离线可用）
 * 整卡可点击 → 祈愿页。
 */
import { ActCalendarEntry } from '../model/ActCalendarEntry';
import { HomePoolSummary } from '../viewmodel/HomeViewModel';
import { PressCard } from './PressCard';
import { MetaIcon } from './MetaIcon';

/** UP 图标显示单元（名称用于本地离线图标，URL 用于网络直连） */
class UpIconCell {
  name: string = '';
  url: string = '';
}

@Component
export struct HomeGachaBannerCard {
  /** 网络卡池数据（优先，非空则用） */
  @Prop pool: ActCalendarEntry = new ActCalendarEntry();
  /** 本地祈愿统计（pool 为空时兜底） */
  @Prop summary: HomePoolSummary | undefined = undefined;
  onTap: () => void = () => {
  };

  private title(): string {
    if (this.pool.name.length > 0) {
      return this.pool.name;
    }
    if (this.summary !== undefined) {
      return this.summary.typeName;
    }
    return '';
  }

  /** 剩余时间文案（对齐 Windows "剩余时间：9 天 18 小时"） */
  remainText(): string {
    const now: number = Date.now();
    if (this.pool.startTime > 0) {
      if (this.pool.startTime > now) {
        return `剩余时间：${ActCalendarEntry.timeSpan(this.pool.startTime - now)}`;
      }
      return `剩余时间：${ActCalendarEntry.timeSpan(this.pool.endTime - now)}`;
    }
    return '';
  }

  /** UP 待显示图标池（武器池 weaponIcons 优先，角色池用 avatarIcons） */
  private upIcons(): string[] {
    return this.pool.weaponIcons.length > 0 ? this.pool.weaponIcons : this.pool.avatarIcons;
  }

  build() {
    PressCard({
      onTap: () => {
        this.onTap()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 8 }) {
        // 头部：池名 + 剩余时间
        Row({ space: 6 }) {
          Text(this.title())
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.remainText().length > 0) {
            Text(this.remainText())
              .fontSize(12)
              .fontFamily('HarmonyOS Sans')
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')

        // 内容：网络卡池→UP 头像行（武器池 weaponIcons；角色池 avatarIcons）；本地统计→抽数+星级
        if (this.upIcons().length > 0) {
          Row({ space: 6 }) {
            ForEach(this.upCells(), (cell: UpIconCell, idx: number) => {
              if (cell.name.startsWith('UI_')) {
                MetaIcon({
                  category: HomeGachaBannerCard.upIconCategory(cell.name),
                  name: cell.name,
                  iconSize: 44,
                  remoteFallback: true,
                })
              } else {
                Image(cell.url)
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.app_primary_bg'))
              }
            }, (cell: UpIconCell, idx: number) => `gb_${idx}_${cell.name.length}`)
            Blank()
          }
          .width('100%')
        } else if (this.summary !== undefined) {
          Row({ space: 10 }) {
            Column({ space: 0 }) {
              Text(`${this.summary.fiveStarCount}`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.five_star'))
              Text('五星')
                .fontSize(9)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            Column({ space: 0 }) {
              Text(`${this.summary.fourStarCount}`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.four_star'))
              Text('四星')
                .fontSize(9)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            Column({ space: 0 }) {
              Text(`${this.summary.totalCount}`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('总抽')
                .fontSize(9)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
          }
          .width('100%')
        }

        // 日期区间（网络卡池）
        if (this.pool.startTime > 0 || this.pool.endTime > 0) {
          Text(`${HomeGachaBannerCard.timestamp(this.pool.startTime)} 至 ${HomeGachaBannerCard.timestamp(this.pool.endTime)}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .padding(12)
    }
  }

  /** UP 图标显示单元（解析 URL 尾段文件名，本地可离线命中） */
  upCells(): UpIconCell[] {
    const out: UpIconCell[] = [];
    const icons: string[] = this.upIcons();
    for (let i = 0; i < icons.length; i++) {
      const cell: UpIconCell = new UpIconCell();
      cell.url = icons[i];
      cell.name = HomeGachaBannerCard.upIconName(icons[i]);
      out.push(cell);
    }
    return out;
  }

  /** UP 图标的文件名字（URL 取尾段；本地 rawfile 名规范为 UI_*） */
  static upIconName(url: string): string {
    if (url.length === 0) {
      return '';
    }
    const seg: string[] = url.split('/');
    const name: string = seg[seg.length - 1].replace(/\.png$/, '');
    return name;
  }

  /** 文件名 → 图标类别（武器 EquipIcon，其余 AvatarIcon） */
  static upIconCategory(name: string): string {
    return name.includes('Equip') || name.startsWith('UI_EquipIcon') ? 'EquipIcon' : 'AvatarIcon';
  }

  private static timestamp(ts: number): string {
    if (ts <= 0) {
      return '--';
    }
    const d: Date = new Date(ts);
    return `${d.getFullYear()}/${HomeGachaBannerCard.pad(d.getMonth() + 1)}/${HomeGachaBannerCard.pad(d.getDate())}`;
  }

  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }
}
