import { CultivationDraftViewModel } from '../viewmodel/CultivationDraftViewModel';
import { CultivationDraft, CultivationSkillDraft } from '../model/CultivationDraft';
import { CultivateProject, CultivationPreparedEntry } from '../data/repo/CultivationRepo';
import { CalItem } from '../model/Calculate';

/** The same review surface is used before first save, on edit, and after current-progress sync. */
@Component
export struct CultivationDraftEditor {
  @ObjectLink vm: CultivationDraftViewModel;
  @Prop uid: string = '';
  onClose: () => void = (): void => {};
  onSaved: () => void = (): void => {};

  private fieldText(index: number, field: string, skill: number): string {
    const draft: CultivationDraft | undefined = this.vm.drafts[index];
    if (draft === undefined) { return ''; }
    let value: number = -1;
    if (skill >= 0) {
      value = field === 'current' ? draft.skills[skill].current : draft.skills[skill].target;
      if (value < 1) { return ''; }
    } else if (field === 'current') { value = draft.current; }
    else if (field === 'target') { value = draft.target; }
    else if (field === 'promote') { value = draft.promote; }
    else { value = draft.targetPromote; }
    return value >= 0 ? `${value}` : '';
  }

  private sourceLabel(index: number): string {
    const draft: CultivationDraft | undefined = this.vm.drafts[index];
    if (draft === undefined || draft.sourceUid.length === 0) { return '离线输入，请确认当前进度'; }
    return `UID ${draft.sourceUid}${draft.sourceAt === 0 ? ' · 手动输入，请确认当前进度' : ' · 已取得当前进度'}`;
  }

  @Builder
  levelField(index: number, field: string, label: string, skill: number = -1) {
    Column({ space: 4 }) {
      Text(label).fontSize(11).fontColor($r('app.color.text_secondary'))
      TextInput({ text: this.fieldText(index, field, skill), placeholder: '待确认' })
        .type(InputType.Number).height(44).fontSize(14)
        .enabled(!this.vm.busy && !this.vm.saved)
        .onChange((text: string) => this.vm.change(index, field, text, skill))
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  draftCard(draft: CultivationDraft, index: number) {
    Column({ space: 10 }) {
      Text(`${draft.name} · ${draft.kind === 'weapon' ? '武器' : '角色与天赋'}`)
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Text(this.sourceLabel(index))
        .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        this.levelField(index, 'current', '当前等级')
        this.levelField(index, 'target', `目标等级（≤${draft.maxLevel}）`)
      }.width('100%')
      Row({ space: 8 }) {
        this.levelField(index, 'promote', `当前突破（0–${draft.maxLevel === 70 ? 4 : 6}）`)
        this.levelField(index, 'targetPromote', `目标突破（0–${draft.maxLevel === 70 ? 4 : 6}）`)
      }.width('100%')
      ForEach(draft.skills, (skill: CultivationSkillDraft, skillIndex: number) => {
        Column({ space: 4 }) {
          Text(`${skill.label} · 基础等级，不含命座加成`).fontSize(12).fontColor($r('app.color.text_primary')).width('100%')
          Row({ space: 8 }) {
            this.levelField(index, 'current', '当前（1–10）', skillIndex)
            this.levelField(index, 'target', '目标（1–10）', skillIndex)
          }.width('100%')
        }
      }, (skill: CultivationSkillDraft) => `${skill.id}`)
    }.width('100%').padding(14).borderRadius(12).backgroundColor($r('app.color.card_surface'))
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.vm.saved ? '保存结果' : '编辑培养目标').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button(this.vm.saved ? '完成' : '取消').height(44).hoverEffect(HoverEffect.Highlight)
          .enabled(!this.vm.busy).onClick(() => this.onClose())
      }.width('100%')
      if (this.vm.busy) { LoadingProgress().height(32).width(32) }
      Scroll() {
        Column({ space: 12 }) {
          if (this.vm.message.length > 0) {
            Text(this.vm.message).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
          if (!this.vm.saved) {
            Text('保存到项目').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            if (this.vm.projects.length === 0) {
              Text('保存时新建默认养成计划').fontSize(13).fontColor($r('app.color.text_primary'))
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.vm.projects, (project: CultivateProject) => {
                  Button(project.name).height(44).margin({ right: 8, bottom: 8 })
                    .backgroundColor(this.vm.projectId === project.id ? $r('app.color.app_primary') : $r('app.color.app_primary_bg'))
                    .fontColor(this.vm.projectId === project.id ? Color.White : $r('app.color.app_primary'))
                    .hoverEffect(HoverEffect.Highlight).enabled(!this.vm.busy && this.vm.drafts[0]?.entryId === 0)
                    .onClick(() => { this.vm.projectId = project.id; })
                }, (project: CultivateProject) => `${project.id}_${this.vm.projectId}`)
              }.width('100%')
            }
            if (this.vm.drafts.length > 0 && this.vm.drafts[0].entryId === 0) {
              Row({ space: 8 }) {
                Text('重复目标').fontSize(12).fontColor($r('app.color.text_secondary'))
                Button(this.vm.overwrite ? '覆盖已有条目' : '跳过已有条目').height(44)
                  .enabled(!this.vm.busy).hoverEffect(HoverEffect.Highlight)
                  .onClick(() => { this.vm.overwrite = !this.vm.overwrite; })
              }.width('100%')
            }
            ForEach(this.vm.drafts, (draft: CultivationDraft, index: number) => {
              this.draftCard(draft, index)
            }, (draft: CultivationDraft) => `${draft.kind}_${draft.itemId}_${draft.entryId}`)
            ForEach(this.vm.preview, (entry: CultivationPreparedEntry) => {
              Column({ space: 4 }) {
                Text(`${entry.draft.name} · 材料预览`).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
                if (entry.items.length === 0) {
                  Text('已达到所选目标，无剩余材料').fontSize(12).fontColor($r('app.color.text_secondary'))
                }
                ForEach(entry.items, (item: CalItem) => {
                  Text(`${item.name} × ${item.num}`).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
                }, (item: CalItem) => `${item.id}_${item.num}`)
              }.width('100%')
            }, (entry: CultivationPreparedEntry) => `${entry.draft.kind}_${entry.draft.itemId}_${JSON.stringify(entry.items)}`)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%')
      if (!this.vm.saved) {
        if (this.uid.length > 0) {
          Button('重新同步当前进度（保留目标）').height(44).width('100%').enabled(!this.vm.busy)
            .hoverEffect(HoverEffect.Highlight).onClick(() => this.vm.sync(this.uid))
        }
        Row({ space: 8 }) {
          Button('计算预览').height(44).layoutWeight(1).enabled(!this.vm.busy && this.vm.drafts.length > 0)
            .hoverEffect(HoverEffect.Highlight).onClick(() => this.vm.calculate())
          Button('确认保存').height(44).layoutWeight(1).backgroundColor($r('app.color.app_primary')).fontColor(Color.White)
            .enabled(!this.vm.busy && this.vm.preview.length > 0).hoverEffect(HoverEffect.Highlight)
            .onClick(() => { this.vm.save().then((saved: boolean) => { if (saved) { this.onSaved(); } }); })
        }.width('100%')
      }
    }.width('100%').height('100%').padding(16)
  }
}
