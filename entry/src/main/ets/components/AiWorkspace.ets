import { pasteboard } from '@kit.BasicServicesKit';
import { AppButtonModifier, CardSurfaceModifier, SelectMaterialModifier, UiSurface } from '../common/UiSurface';
import { AiTranscriptRow, AiWorkspaceChoice, AiWorkspaceViewModel } from '../viewmodel/AiWorkspaceViewModel';
import { AiMarkdown } from './AiMarkdown';
import { AiSettings } from './AiSettings';

@Component
struct AiReasoning {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop text: string = '';
  @Prop streaming: boolean = false;
  @Prop inProgress: boolean = false;
  @Prop expanded: boolean = false;
  onToggle: () => void = () => {};
  onCopy: (text: string) => void = (_text: string) => {};

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Button() {
          Row({ space: 6 }) {
            Text(this.expanded ? '▾' : '▸').fontColor($r('app.color.text_secondary'))
            Text(this.inProgress ? $r('app.string.ui_ai_reasoning_in_progress') : $r('app.string.ui_ai_reasoning_completed'))
              .fontColor($r('app.color.text_secondary')).fontSize(13)
          }
        }.height(36).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
          .onClick(() => { this.onToggle(); })
        if (this.expanded) {
          Button($r('app.string.ui_ai_copy_text'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).fontSize(12)
            .onClick(() => { this.onCopy(this.text); })
        }
      }.width('100%')
      if (this.expanded) {
        AiMarkdown({ text: this.text, streaming: this.streaming })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct AiWorkspace {
  @Prop hasSnapshot: boolean = false;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @ObjectLink vm: AiWorkspaceViewModel;
  @State showSettings: boolean = false;
  @State expandedReasoningIds: string[] = [];
  private readonly transcriptScroller: Scroller = new Scroller();
  private followingTail: boolean = true;
  private userScrollPending: boolean = false;

  private options(items: AiWorkspaceChoice[]): SelectOption[] {
    return items.map((item: AiWorkspaceChoice): SelectOption => ({ value: item.label }));
  }

  private index(items: AiWorkspaceChoice[], id: string): number {
    return items.findIndex((item: AiWorkspaceChoice): boolean => item.id === id);
  }

  private async copy(text: string): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast($r('app.string.ui_ai_copied_text'));
    } catch (_) {
      this.toast($r('app.string.ui_ai_copy_error'));
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message, systemMaterial: UiSurface.dialogMaterial() });
  }

  private showPrivacy(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.ui_ai_privacy_title'),
      message: $r('app.string.ui_ai_privacy_body'),
      buttons: [{ text: $r('app.string.common_confirm'), color: $r('app.color.app_primary_text') }],
      systemMaterial: UiSurface.dialogMaterial(),
    }).catch(() => {});
  }

  private resetTranscriptPosition(): void {
    this.followingTail = true;
    this.userScrollPending = false;
    this.transcriptScroller.scrollEdge(Edge.Bottom);
  }

  private previewId(): string { return `${this.vm.conversationId}:${this.vm.rows.length}`; }

  private toggleReasoning(id: string): void {
    this.expandedReasoningIds = this.expandedReasoningIds.includes(id)
      ? this.expandedReasoningIds.filter((entry: string): boolean => entry !== id)
      : [...this.expandedReasoningIds, id];
  }

  private conversationMenu(): MenuElement[] {
    const remove: MenuElement = {
      value: $r('app.string.ui_agent_page_label_delete_conversation'),
      action: (): void => {
        this.vm.deleteConversation();
        this.resetTranscriptPosition();
      },
    };
    return [remove];
  }

  private generate(): void {
    this.resetTranscriptPosition();
    const prompt: string | undefined = this.getUIContext().getHostContext()?.resourceManager.getStringSync(
      $r('app.string.ui_ai_initial_request').id);
    this.vm.generate(prompt);
  }

  @Builder
  systemAnalysis() {
    Scroll() {
      Column({ space: 10 }) {
        Button($r('app.string.ui_ai_device_generate'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .height(44).enabled(!this.vm.localBusy && this.hasSnapshot)
          .onClick(() => { this.vm.runSystemAnalysis(); })
        if (this.vm.localBusy) {
          LoadingProgress().width(24).height(24).color($r('app.color.app_primary'))
        }
        if (this.vm.localContent.length > 0) {
          Button($r('app.string.ui_ai_copy_text'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44)
            .onClick(() => { this.copy(this.vm.localContent); })
          AiMarkdown({ text: this.vm.localContent })
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  customWorkspace() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.vm.conversations.length > 0) {
          Select(this.options(this.vm.conversations)).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.index(this.vm.conversations, this.vm.conversationId))
            .layoutWeight(1).constraintSize({ minHeight: 44 })
            .accessibilityText($r('app.string.ui_ai_select_conversation'))
            .onSelect((index: number, _value: string) => {
              const id: string = this.vm.conversations[index]?.id ?? '';
              if (id !== this.vm.conversationId) {
                this.vm.selectConversation(id);
                this.resetTranscriptPosition();
              }
            })
          Button('⋯', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .width(44).height(44).enabled(!this.vm.busy)
            .accessibilityText($r('app.string.ui_ai_conversation_actions'))
            .bindMenu(this.conversationMenu(), { systemMaterial: UiSurface.dialogMaterial() })
        }
        Button($r('app.string.ui_ai_new'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
          .onClick(() => {
            this.vm.newConversation();
            this.resetTranscriptPosition();
          })
        Button($r('app.string.ui_ai_generate'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .height(44).enabled(this.hasSnapshot && this.vm.modelId.length > 0)
          .onClick(() => this.generate())
      }.width('100%')
      if (this.vm.providers.length > 0) {
        Row({ space: 8 }) {
          Select(this.options(this.vm.providers)).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.index(this.vm.providers, this.vm.providerId))
            .layoutWeight(1).constraintSize({ minHeight: 44 }).accessibilityText($r('app.string.ui_agent_page_label_model_provider_profile'))
            .onSelect((index: number, _value: string) => this.vm.selectProvider(this.vm.providers[index]?.id ?? ''))
          if (this.vm.models.length > 0) {
            Select(this.options(this.vm.models)).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.index(this.vm.models, this.vm.modelId))
              .layoutWeight(1).constraintSize({ minHeight: 44 }).accessibilityText($r('app.string.ui_agent_page_label_model_profile'))
              .onSelect((index: number, _value: string) => this.vm.selectModel(this.vm.models[index]?.id ?? ''))
          }
        }.width('100%').enabled(!this.vm.busy && this.vm.approvalName.length === 0)
      } else {
        Text($r('app.string.ui_settings_page_description_add_model_provider_profile_to_edit')).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      Scroll(this.transcriptScroller) {
        Column({ space: 12 }) {
          ForEach(this.vm.rows, (row: AiTranscriptRow) => {
            Column({ space: 4 }) {
              Row() {
                Text(row.author).fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                if (row.text.length > 0) {
                  Button($r('app.string.ui_ai_copy_text'), { type: ButtonType.Normal })
                    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
                    .height(44).fontSize(12)
                    .onClick(() => { this.copy(row.text); })
                }
              }.width('100%')
              if (row.reasoning.length > 0) {
                AiReasoning({
                  text: row.reasoning,
                  expanded: this.expandedReasoningIds.includes(row.id),
                  onToggle: () => { this.toggleReasoning(row.id); },
                  onCopy: (text: string) => { this.copy(text); },
                })
              }
              if (row.text.length > 0) {
                AiMarkdown({ text: row.text })
              }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }, (row: AiTranscriptRow): string => `${row.id}:${row.author}:${row.reasoning}:${row.text}`)
          if (this.vm.preview.length > 0 || this.vm.previewReasoning.length > 0) {
            Text('AI').fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
            if (this.vm.previewReasoning.length > 0) {
              AiReasoning({
                text: this.vm.previewReasoning,
                streaming: true,
                inProgress: this.vm.preview.length === 0,
                expanded: this.expandedReasoningIds.includes(this.previewId()),
                onToggle: () => { this.toggleReasoning(this.previewId()); },
                onCopy: (text: string) => { this.copy(text); },
              })
            }
            if (this.vm.preview.length > 0) {
              AiMarkdown({ text: this.vm.preview, streaming: true })
            }
          }
          if (this.vm.approvalName.length > 0) {
            Column({ space: 6 }) {
              Text($r('app.string.ui_ai_approval')).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Text(this.vm.approvalName).fontSize(12).fontColor($r('app.color.text_secondary'))
              Text(this.vm.approvalText).fontColor($r('app.color.text_secondary')).width('100%')
              Row({ space: 8 }) {
                Button($r('app.string.ui_chat_tool_approval_request_segment_view_label_allow'), { type: ButtonType.Normal })
                  .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
                  .height(44)
                  .onClick(() => { this.vm.answerApproval(true); })
                Button($r('app.string.ui_chat_tool_approval_request_segment_view_label_deny'), { type: ButtonType.Normal })
                  .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
                  .height(44)
                  .onClick(() => { this.vm.answerApproval(false); })
              }
            }.width('100%').padding(10).alignItems(HorizontalAlign.Start).borderRadius($r('app.float.card_radius'))
              .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
          }
        }.width('100%').padding(8).alignItems(HorizontalAlign.Start)
          .onAreaChange((previous: Area, current: Area) => {
            if (this.followingTail && previous.height !== current.height) { this.transcriptScroller.scrollEdge(Edge.Bottom); }
          })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
        .onWillScroll((_x: number, y: number, _state: ScrollState, source: ScrollSource): void => {
          this.userScrollPending = y !== 0 && source !== ScrollSource.SCROLLER &&
            source !== ScrollSource.SCROLLER_ANIMATION && source !== ScrollSource.EDGE_EFFECT;
          if (this.userScrollPending) { this.followingTail = false; }
        })
        .onDidScroll(() => {
          if (this.userScrollPending) {
            this.followingTail = this.transcriptScroller.isAtEnd();
            this.userScrollPending = false;
          }
        })
        .onReachEnd(() => { this.followingTail = true; })
      if (this.vm.error.length > 0) {
        Text(this.vm.error).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.usageText.length > 0) {
        Text(this.vm.usageText).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      TextArea({ placeholder: $r('app.string.ui_agent_page_label_placeholder'), text: this.vm.input }).height(64).width('100%')
        .enabled(!this.vm.busy && this.vm.approvalName.length === 0)
        .enterKeyType(EnterKeyType.Send).onSubmit((_key: EnterKeyType) => { this.vm.send(); })
        .onChange((value: string) => { this.vm.input = value; })
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.vm.busy) {
          Button($r('app.string.ui_ai_stop'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 4 })
            .onClick(() => this.vm.stop())
        } else {
          Button($r('app.string.ui_ai_send'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).margin({ right: 8, bottom: 4 })
            .enabled(this.vm.approvalName.length === 0 && this.vm.modelId.length > 0 && this.vm.input.trim().length > 0)
            .onClick(() => { this.vm.send(); })
          if (this.vm.canContinue) {
            Button($r('app.string.ui_ai_continue'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 8, bottom: 4 })
              .onClick(() => { this.vm.resume(); })
          }
          if (this.vm.canRetry && this.vm.approvalName.length === 0) {
            Button($r('app.string.ui_ai_regenerate'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 8, bottom: 4 })
              .onClick(() => { this.vm.regenerate(); })
          }
          if (this.vm.rows.length > 0) {
            Button($r('app.string.ui_ai_copy'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 8, bottom: 4 })
              .onClick(() => { this.copy(this.vm.transcript()); })
          }
        }
      }.width('100%')
    }.width('100%').layoutWeight(1)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.showSettings ? $r('app.string.ui_section_ai') : $r('app.string.ui_ai_workspace')).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        if (!this.showSettings && !this.vm.loading && !this.vm.systemMode) {
          Button('ⓘ', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .width(44).height(44)
            .accessibilityText($r('app.string.ui_ai_privacy_title'))
            .onClick(() => { this.showPrivacy(); })
        }
        Button(this.showSettings ? $r('app.string.ui_ai_return') : $r('app.string.ui_section_ai'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
          .enabled(!this.vm.busy && !this.vm.localBusy)
          .onClick(() => {
            this.showSettings = !this.showSettings;
            if (!this.showSettings) { this.vm.reloadSettings(); }
          })
      }.width('100%')
      if (this.showSettings) {
        Scroll() {
          AiSettings()
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      } else if (this.vm.loading) {
        LoadingProgress().width(32).height(32).color($r('app.color.app_primary'))
      } else if (this.vm.systemMode) {
        this.systemAnalysis()
      } else {
        this.customWorkspace()
      }
    }.width('100%').height('100%').padding(12).alignItems(HorizontalAlign.Start).borderRadius($r('app.float.card_radius'))
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }
}
