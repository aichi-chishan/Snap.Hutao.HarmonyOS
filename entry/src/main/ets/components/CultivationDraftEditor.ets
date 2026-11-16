import { CultivationDraftViewModel } from '../viewmodel/CultivationDraftViewModel';
import { CultivationBatchField, CultivationBatchTargets, CultivationDraft, CultivationSaveMode, CultivationSkillDraft } from '../model/CultivationDraft';
import { CultivateProject, CultivationPreparedEntry } from '../data/repo/CultivationRepo';
import { CalItem } from '../model/Calculate';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, SelectMaterialModifier } from '../common/UiSurface';

/** The same review surface is used before first save, on edit, and after current-progress sync. */
@Component
export struct CultivationDraftEditor {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @ObjectLink vm: CultivationDraftViewModel;
  @Prop uid: string = '';
  @State expandedPreview: string = '';
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

  private batchFieldText(field: CultivationBatchField): string {
    const level: number = this.vm.batchTargets?.levels[field] ?? -1;
    return level > 0 ? String(level) : '';
  }

  private previewKey(entry: CultivationPreparedEntry): string {
    return `${entry.draft.kind}_${entry.draft.avatarId}_${entry.draft.itemId}_${entry.draft.entryId}`;
  }

  private previewTitle(entry: CultivationPreparedEntry): string {
    if (entry.draft.kind !== 'weapon') { return entry.draft.name; }
    const role: CultivationDraft | undefined = this.vm.drafts.find((draft: CultivationDraft): boolean =>
      draft.kind === 'avatar' && draft.avatarId === entry.draft.avatarId);
    return role === undefined ? entry.draft.name : `${entry.draft.name} · ${role.name}`;
  }

  @Builder
  batchField(field: CultivationBatchField, label: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(12).fontColor($r('app.color.text_secondary'))
      TextInput({ text: this.batchFieldText(field), placeholder: `1–${CultivationBatchTargets.maxLevel(field)}` })
        .type(InputType.Number).height(44).fontSize(14)
        .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .enabled(!this.vm.busy && !this.vm.saved).onChange((text: string) => this.vm.changeBatchTarget(field, text))
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  batchFields() {
    Column({ space: 10 }) {
      Text(`${this.vm.drafts.length / 2} 个角色及其当前装备武器${this.vm.batchSkipped > 0 ? ` · 跳过 ${this.vm.batchSkipped} 个角色` : ''}`)
        .fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
      Row({ space: 8 }) {
        this.batchField(CultivationBatchField.AvatarLevel, '角色目标等级')
        this.batchField(CultivationBatchField.WeaponLevel, '武器目标等级')
      }.width('100%')
      Row({ space: 8 }) {
        this.batchField(CultivationBatchField.SkillA, '普通攻击')
        this.batchField(CultivationBatchField.SkillE, '元素战技')
        this.batchField(CultivationBatchField.SkillQ, '元素爆发')
      }.width('100%')
    }.width('100%').padding(14).borderRadius(12).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
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
    }.width('100%').padding(14).borderRadius(12).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.vm.saved ? '保存结果' : this.vm.batchTargets === undefined ? '编辑培养目标' : '统一培养目标')
          .fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button(this.vm.saved ? '完成' : '取消', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
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
                  Button(project.name, { type: ButtonType.Normal })
                    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, this.vm.projectId === project.id))
                    .height(44).margin({ right: 8, bottom: 8 }).enabled(!this.vm.busy && this.vm.drafts[0]?.entryId === 0)
                    .onClick(() => { this.vm.projectId = project.id; })
                }, (project: CultivateProject) => `${project.id}_${this.vm.projectId}`)
              }.width('100%')
            }
            if (this.vm.drafts.length > 0 && this.vm.drafts[0].entryId === 0) {
              Row({ space: 8 }) {
                Text('重复目标').fontSize(12).fontColor($r('app.color.text_secondary'))
                Select([{ value: '跳过已有条目' }, { value: '覆盖已有条目' }, { value: '另存为新条目' }])
                  .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
                  .selected(this.vm.saveMode).value(['跳过已有条目', '覆盖已有条目', '另存为新条目'][this.vm.saveMode])
                  .enabled(!this.vm.busy).onSelect((index: number) => {
                    this.vm.saveMode = index === 1 ? CultivationSaveMode.Overwrite
                      : index === 2 ? CultivationSaveMode.CreateNew : CultivationSaveMode.Preserve;
                  })
              }.width('100%')
            }
            if (this.vm.batchTargets !== undefined) {
              this.batchFields()
            } else {
              ForEach(this.vm.drafts, (draft: CultivationDraft, index: number) => {
                this.draftCard(draft, index)
              }, (draft: CultivationDraft) => `${draft.kind}_${draft.avatarId}_${draft.itemId}_${draft.entryId}`)
            }
            ForEach(this.vm.preview, (entry: CultivationPreparedEntry) => {
              Column({ space: 4 }) {
                Text(`${this.previewTitle(entry)} · 材料预览`).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
                if (this.vm.batchTargets !== undefined) {
                  Text(`当前 Lv.${entry.draft.current} · 目标 Lv.${entry.draft.target}`)
                    .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
                }
                if (entry.items.length === 0) {
                  Text('已达到所选目标，无剩余材料').fontSize(12).fontColor($r('app.color.text_secondary'))
                } else if (this.vm.batchTargets !== undefined) {
                  Button(this.expandedPreview === this.previewKey(entry) ? '收起材料' : `查看 ${entry.items.length} 种材料`, { type: ButtonType.Normal })
                    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
                    .height(44).fontSize(12)
                    .onClick(() => this.expandedPreview = this.expandedPreview === this.previewKey(entry) ? '' : this.previewKey(entry))
                }
                if (this.vm.batchTargets === undefined || this.expandedPreview === this.previewKey(entry)) {
                  ForEach(entry.items, (item: CalItem) => {
                    Text(`${item.name} × ${item.num}`).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
                  }, (item: CalItem, index: number) => `${item.id}_${index}`)
                }
              }.width('100%')
            }, (entry: CultivationPreparedEntry) => `${this.previewKey(entry)}_${JSON.stringify(entry.items)}`)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%')
      if (!this.vm.saved) {
        if (this.uid.length > 0) {
          Button('重新同步当前进度（保留目标）', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).width('100%').enabled(!this.vm.busy)
            .onClick(() => this.vm.sync(this.uid))
        }
        Row({ space: 8 }) {
          Button('计算预览', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).layoutWeight(1).enabled(!this.vm.busy && this.vm.drafts.length > 0)
            .onClick(() => this.vm.calculate())
          Button('确认保存', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).layoutWeight(1)
            .enabled(!this.vm.busy && this.vm.preview.length > 0)
            .onClick(() => { this.vm.save().then((saved: boolean) => { if (saved) { this.onSaved(); } }); })
        }.width('100%')
      }
    }.width('100%').height('100%').padding(16)
  }
}
