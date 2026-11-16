import { CardSurfaceModifier } from '../common/UiSurface';
import { MetaIcon } from './MetaIcon';

const SKILL_SLOTS: number[] = [0, 1, 2];
const SKILL_LETTERS: string[] = ['A', 'E', 'Q'];
const CONSTELLATION_SLOTS: number[] = [1, 2, 3, 4, 5, 6];
const HIT_TARGET: number = 44;
const WIDE_SKILL_WIDTH: number = 108;

export class CharacterNameCardSkill {
  id: number = 0;
  name: string = '';
  icon: string = '';
  levelText: string = '';
  description: string = '';
}

export class CharacterNameCardConstellation {
  id: number = 0;
  pos: number = 0;
  name: string = '';
  icon: string = '';
  active: boolean = false;
  known: boolean = false;
  description: string = '';
}

export class CharacterNameCardData {
  avatarId: number = 0;
  name: string = '';
  icon: string = '';
  level: number = 0;
  rarity: number = 0;
  fetter: number = 0;
  scoreText: string = '';
  nameCardPic: string = '';
  weaponName: string = '';
  weaponIcon: string = '';
  weaponLevel: number = 0;
  weaponRarity: number = 0;
  refinement: number = 0;
  /** Display order is normal attack, elemental skill, elemental burst. */
  skills: CharacterNameCardSkill[] = [];
  constellations: CharacterNameCardConstellation[] = [];
}

@Component
export struct CharacterNameCard {
  @Prop data: CharacterNameCardData = new CharacterNameCardData();
  @Prop compact: boolean = false;
  @Prop cardHeight: number = 320;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  onSkill: ((skill: CharacterNameCardSkill) => void) | undefined = undefined;
  onConstellation: ((constellation: CharacterNameCardConstellation) => void) | undefined = undefined;
  @State private measuredWidth: number = 0;

  private displayHeight(): number {
    const reserved: number = this.compact ? 20 : 44 + WIDE_SKILL_WIDTH;
    const visibleSlots: number = this.measuredWidth > 0
      ? Math.max(1, Math.floor((this.measuredWidth - reserved) / HIT_TARGET)) : CONSTELLATION_SLOTS.length;
    const extraRows: number = Math.ceil(CONSTELLATION_SLOTS.length / visibleSlots) - 1;
    return Math.max(this.cardHeight, (this.compact ? 288 : 300) + extraRows * HIT_TARGET);
  }

  private stars(rarity: number): string {
    return rarity > 0 ? '✦'.repeat(Math.min(5, Math.floor(rarity))) : '';
  }

  private skillAt(slot: number): CharacterNameCardSkill | undefined {
    return this.data.skills[slot];
  }

  private constellationAt(slot: number): CharacterNameCardConstellation | undefined {
    return this.data.constellations.find((entry: CharacterNameCardConstellation): boolean => entry.pos === slot);
  }

  private constellationStatus(slot: number): string {
    const entry: CharacterNameCardConstellation | undefined = this.constellationAt(slot);
    if (entry === undefined || !entry.known) { return '解锁状态未知'; }
    return entry.active ? '已解锁' : '未解锁';
  }

  private hasSkillDetails(slot: number): boolean {
    const skill: CharacterNameCardSkill | undefined = this.skillAt(slot);
    return this.onSkill !== undefined && skill !== undefined && (skill.name.length > 0 || skill.description.length > 0);
  }

  private hasConstellationDetails(slot: number): boolean {
    const entry: CharacterNameCardConstellation | undefined = this.constellationAt(slot);
    return this.onConstellation !== undefined && entry !== undefined &&
      (entry.name.length > 0 || entry.description.length > 0);
  }

  @Builder
  private avatarSummary() {
    Row({ space: this.compact ? 10 : 14 }) {
      Stack() {
        MetaIcon({ category: 'AvatarIcon', name: this.data.icon, iconSize: this.compact ? 58 : 78 })
      }
      .borderRadius(9)
      .clip(true)
      .backgroundColor($r('app.color.image_scrim_soft'))
      .accessibilityLevel('no')
      Column({ space: 3 }) {
        Text(this.data.name)
          .fontSize(this.compact ? 20 : 25)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.image_foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.data.rarity > 0) {
          Text(this.stars(this.data.rarity)).fontSize(14).fontColor($r('app.color.image_foreground'))
            .accessibilityText(`${this.data.rarity} 星`)
        }
        Row({ space: 12 }) {
          Text(this.data.level > 0 ? `Lv. ${this.data.level}` : 'Lv. —')
            .fontSize(14).fontColor($r('app.color.image_foreground'))
          if (this.data.fetter > 0) {
            Row({ space: 3 }) {
              Image($r('app.media.UI_Icon_Fetter')).width(14).height(14).objectFit(ImageFit.Contain)
                .draggable(false).accessibilityLevel('no')
              Text(`${this.data.fetter}`).fontSize(13).fontColor($r('app.color.image_foreground'))
                .accessibilityText(`好感度 ${this.data.fetter}`)
            }
          }
        }
        if (this.data.scoreText.length > 0) {
          Row({ space: 6 }) {
            Text('角色总分').fontSize(12).fontColor($r('app.color.image_foreground'))
            Text(this.data.scoreText).fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.five_star'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 4, right: 4 })
              .borderRadius(4)
              .backgroundColor($r('app.color.image_scrim_soft'))
          }
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private weaponSummary() {
    if (this.data.weaponName.length > 0 || this.data.weaponIcon.length > 0) {
      Row({ space: this.compact ? 10 : 14 }) {
        Stack() {
          MetaIcon({ category: 'EquipIcon', name: this.data.weaponIcon, iconSize: this.compact ? 48 : 64 })
        }
        .borderRadius(8)
        .clip(true)
        .backgroundColor($r('app.color.image_scrim_soft'))
        .accessibilityLevel('no')
        Column({ space: 2 }) {
          Text(this.data.weaponName).fontSize(this.compact ? 16 : 19).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.image_foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.data.weaponRarity > 0) {
            Text(this.stars(this.data.weaponRarity)).fontSize(12).fontColor($r('app.color.image_foreground'))
              .accessibilityText(`${this.data.weaponRarity} 星`)
          }
          Row({ space: 9 }) {
            if (this.data.weaponLevel > 0) {
              Text(`Lv. ${this.data.weaponLevel}`).fontSize(13).fontColor($r('app.color.image_foreground'))
            }
            if (this.data.refinement > 0) {
              Text(`精炼 ${this.data.refinement}`).fontSize(12).fontColor($r('app.color.image_foreground'))
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
  }

  @Builder
  private skillButton(slot: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 6 }) {
        if ((this.skillAt(slot)?.icon ?? '').length > 0) {
          MetaIcon({ category: 'Skill', name: this.skillAt(slot)?.icon ?? '', iconSize: this.compact ? 23 : 28 })
        } else {
          Text(SKILL_LETTERS[slot]).width(24).textAlign(TextAlign.Center).fontSize(13)
            .fontColor($r('app.color.image_foreground'))
        }
        Text(this.skillAt(slot)?.levelText || 'Lv. —').fontSize(this.compact ? 12 : 14)
          .fontColor($r('app.color.image_foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: this.compact ? 0 : 8 })
      .justifyContent(this.compact ? FlexAlign.Center : FlexAlign.Start)
    }
    .width(this.compact ? '33%' : WIDE_SKILL_WIDTH)
    .height(HIT_TARGET)
    .constraintSize({ minWidth: HIT_TARGET })
    .padding(0)
    .borderRadius(8)
    .hoverEffect(HoverEffect.Highlight)
    .enabled(this.hasSkillDetails(slot))
    .accessibilityGroup(true)
    .accessibilityText(`${SKILL_LETTERS[slot]} ${this.skillAt(slot)?.name ?? ''} ${this.skillAt(slot)?.levelText || '等级未知'}`)
    .onClick(() => {
      const skill: CharacterNameCardSkill | undefined = this.skillAt(slot);
      if (skill !== undefined) { this.onSkill?.(skill); }
    })
  }

  @Builder
  private constellationButton(slot: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Stack({ alignContent: Alignment.Center }) {
        Row() {
          if ((this.constellationAt(slot)?.icon ?? '').length > 0) {
            MetaIcon({ category: 'Talent', name: this.constellationAt(slot)?.icon ?? '', iconSize: 28 })
          } else {
            Text(`${slot}`).fontSize(14).fontColor($r('app.color.image_foreground'))
          }
        }
        .opacity(this.constellationAt(slot)?.known === true && this.constellationAt(slot)?.active === true ? 1 : 0.56)
        if (this.constellationAt(slot)?.known !== true) {
          Text('?').fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.image_foreground'))
            .align(Alignment.BottomEnd)
        } else if (this.constellationAt(slot)?.active !== true) {
          Image($r('app.media.UI_Icon_Locked')).width(14).height(14).objectFit(ImageFit.Contain)
            .align(Alignment.BottomEnd).draggable(false)
        }
      }
      .width(34)
      .height(34)
    }
    .width(HIT_TARGET)
    .height(HIT_TARGET)
    .padding(0)
    .borderRadius(8)
    .hoverEffect(HoverEffect.Highlight)
    .enabled(this.hasConstellationDetails(slot))
    .accessibilityGroup(true)
    .accessibilityText(`第 ${slot} 命座 ${this.constellationAt(slot)?.name ?? ''}，${this.constellationStatus(slot)}`)
    .onClick(() => {
      const entry: CharacterNameCardConstellation | undefined = this.constellationAt(slot);
      if (entry !== undefined) { this.onConstellation?.(entry); }
    })
  }

  @Builder
  private constellationStrip() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: this.compact ? FlexAlign.SpaceBetween : FlexAlign.Start }) {
      ForEach(CONSTELLATION_SLOTS, (slot: number) => {
        this.constellationButton(slot)
      }, (slot: number): string => `constellation-${slot}`)
    }
    .width('100%')
  }

  @Builder
  private compactBody() {
    Column({ space: 8 }) {
      this.avatarSummary()
      this.weaponSummary()
      Blank()
      Row() {
        ForEach(SKILL_SLOTS, (slot: number) => {
          this.skillButton(slot)
        }, (slot: number): string => `skill-${slot}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      this.constellationStrip()
    }
    .width('100%')
    .height('100%')
    .padding({ top: 12, bottom: 12, left: 10, right: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private wideBody() {
    Row({ space: 12 }) {
      Column({ space: 14 }) {
        this.avatarSummary()
        this.weaponSummary()
        Blank()
        this.constellationStrip()
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        ForEach(SKILL_SLOTS, (slot: number) => {
          this.skillButton(slot)
        }, (slot: number): string => `skill-${slot}`)
      }
      .width(WIDE_SKILL_WIDTH)
      .height('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (/^[A-Za-z0-9_-]+$/.test(this.data.nameCardPic)) {
        Image($rawfile(`icons/NameCardPic/${this.data.nameCardPic}.png`))
          .width('100%').height('100%').objectFit(ImageFit.Cover).draggable(false).accessibilityLevel('no')
      }
      Column().width('100%').height('100%').backgroundColor($r('app.color.image_scrim'))
        .accessibilityLevel('no')
      if (this.compact) {
        this.compactBody()
      } else {
        this.wideBody()
      }
    }
    .width('100%')
    .height(this.displayHeight())
    .borderRadius($r('app.float.card_radius'))
    .clip(true)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const widthVp: number = Number(newArea.width);
      if (widthVp > 0 && widthVp !== this.measuredWidth) { this.measuredWidth = widthVp; }
    })
  }
}
