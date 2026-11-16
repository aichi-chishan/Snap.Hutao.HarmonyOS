import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, SelectMaterialModifier } from '../common/UiSurface';
import { AiSettingsViewModel } from '../viewmodel/AiSettingsViewModel';
import { AiWorkspaceChoice } from '../viewmodel/AiWorkspaceViewModel';

const AI_PROTOCOL_OPTIONS: SelectOption[] = [
  { value: 'OpenAI Chat Completions' }, { value: 'OpenAI Responses' }, { value: 'Anthropic Messages' }
];
const AI_REASONING_OPTIONS: SelectOption[] = [
  { value: $r('app.string.ui_settings_page_option_provider_default') },
  { value: $r('app.string.ui_settings_page_option_reasoning_effort_none') },
  { value: $r('app.string.ui_settings_page_option_reasoning_effort_low') },
  { value: $r('app.string.ui_settings_page_option_reasoning_effort_medium') },
  { value: $r('app.string.ui_settings_page_option_reasoning_effort_high') },
  { value: $r('app.string.ui_settings_page_option_reasoning_effort_extra_high') },
];
const AI_REASONING_VALUES: string[] = ['', 'none', 'low', 'medium', 'high', 'xhigh'];

@Component
export struct AiSettings {
  @State vm: AiSettingsViewModel = new AiSettingsViewModel();
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;

  aboutToAppear(): void { this.vm.load(); }

  private options(items: AiWorkspaceChoice[]): SelectOption[] {
    return items.map((item: AiWorkspaceChoice): SelectOption => ({ value: item.label }));
  }

  private index(items: AiWorkspaceChoice[], id: string): number {
    return items.findIndex((item: AiWorkspaceChoice): boolean => item.id === id);
  }

  @Builder
  modelFields() {
    Column({ space: 8 }) {
      TextInput({ placeholder: $r('app.string.ui_settings_page_label_profile_model_id'), text: this.vm.modelCode }).height(44)
        .onChange((value: string) => { this.vm.modelCode = value; })
      TextInput({ placeholder: $r('app.string.ui_settings_page_label_model_name'), text: this.vm.modelName }).height(44)
        .onChange((value: string) => { this.vm.modelName = value; })
      Row({ space: 8 }) {
        TextInput({ placeholder: $r('app.string.ui_settings_page_label_model_temperature'), text: this.vm.temperature }).height(44).layoutWeight(1)
          .onChange((value: string) => { this.vm.temperature = value; })
        TextInput({ placeholder: $r('app.string.ui_settings_page_label_model_top_p'), text: this.vm.topP }).height(44).layoutWeight(1)
          .onChange((value: string) => { this.vm.topP = value; })
      }.width('100%')
      TextInput({ placeholder: $r('app.string.ui_settings_page_label_model_max_input_tokens'), text: this.vm.maxInputTokens }).height(44).type(InputType.Number)
        .onChange((value: string) => { this.vm.maxInputTokens = value; })
      TextInput({ placeholder: $r('app.string.ui_settings_page_label_model_max_context_window_tokens'), text: this.vm.maxContextTokens }).height(44).type(InputType.Number)
        .onChange((value: string) => { this.vm.maxContextTokens = value; })
      TextInput({ placeholder: $r('app.string.ui_settings_page_label_model_max_output_tokens'), text: this.vm.maxOutputTokens }).height(44).type(InputType.Number)
        .onChange((value: string) => { this.vm.maxOutputTokens = value; })
      if (this.vm.protocol !== 2) {
        Row({ space: 8 }) {
          Text($r('app.string.ui_settings_page_label_model_reasoning_effort')).fontSize(13).fontColor($r('app.color.text_secondary'))
          Select(AI_REASONING_OPTIONS).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(AI_REASONING_VALUES.indexOf(this.vm.reasoningEffort)).layoutWeight(1)
            .constraintSize({ minHeight: 44 })
            .onSelect((index: number, _value: string) => { this.vm.reasoningEffort = AI_REASONING_VALUES[index] ?? ''; })
        }.width('100%')
      }
      if (this.vm.protocol === 0) {
        Row({ space: 8 }) {
          Text($r('app.string.ui_settings_page_label_model_thinking_enabled')).fontSize(13).fontColor($r('app.color.text_secondary'))
          Select([{ value: $r('app.string.ui_settings_page_option_provider_default') },
            { value: $r('app.string.ui_action_disable') }, { value: $r('app.string.ui_action_enable') }])
            .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
            .selected(this.vm.thinking + 1).layoutWeight(1).constraintSize({ minHeight: 44 })
            .onSelect((index: number, _value: string) => { this.vm.thinking = index - 1; })
        }.width('100%')
        Row({ space: 8 }) {
          Text($r('app.string.ui_settings_page_label_model_omit_reasoning_effort_when_thinking_disabled'))
            .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.vm.omitReasoningEffortWhenThinkingDisabled })
            .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
            .accessibilityText($r('app.string.ui_settings_page_label_model_omit_reasoning_effort_when_thinking_disabled'))
            .onChange((value: boolean) => { this.vm.omitReasoningEffortWhenThinkingDisabled = value; })
        }.width('100%')
      }
    }.width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text($r('app.string.ui_ai_mode')).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Select([{ value: $r('app.string.ui_ai_on_device') }, { value: $r('app.string.ui_ai_custom_api') }]).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .selected(this.vm.providerMode).constraintSize({ minHeight: 44 })
          .onSelect((index: number, _value: string) => this.vm.selectMode(index))
      }.width('100%')
      if (this.vm.providerMode === 1) {
        if (this.vm.providers.length > 0) {
          Select(this.options(this.vm.providers)).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.index(this.vm.providers, this.vm.providerId))
            .width('100%').constraintSize({ minHeight: 44 }).accessibilityText($r('app.string.ui_settings_page_label_model_provider_profiles'))
            .onSelect((index: number, _value: string) => this.vm.selectProvider(this.vm.providers[index]?.id ?? ''))
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          Button($r('app.string.ui_settings_page_label_add_profile'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 4 })
            .onClick(() => this.vm.addProvider())
          if (this.vm.providerId.length > 0) {
            Button($r('app.string.ui_settings_page_label_copy_profile'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 8, bottom: 4 })
              .onClick(() => { this.vm.copyProvider(); })
            Button($r('app.string.ui_settings_page_label_delete_profile'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontColor($r('app.color.danger'))
              .height(44).margin({ right: 8, bottom: 4 })
              .onClick(() => { this.vm.deleteProvider(); })
          }
        }.width('100%')
        if (this.vm.providerId.length > 0) {
          TextInput({ placeholder: $r('app.string.ui_settings_page_label_profile_name'), text: this.vm.providerName }).height(44)
            .onChange((value: string) => { this.vm.providerName = value; })
          Select(AI_PROTOCOL_OPTIONS).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.vm.protocol).width('100%').constraintSize({ minHeight: 44 })
            .accessibilityText($r('app.string.ui_settings_page_label_profile_provider_type')).onSelect((index: number, _value: string) => { this.vm.protocol = index; })
          TextInput({ placeholder: $r('app.string.ui_ai_endpoint_placeholder'), text: this.vm.endpoint }).height(44)
            .onChange((value: string) => { this.vm.endpoint = value; })
          TextInput({ placeholder: $r('app.string.ui_ai_key_placeholder'), text: this.vm.apiKey }).height(44)
            .type(InputType.Password).onChange((value: string) => { this.vm.apiKey = value; })
          if (this.vm.models.length > 0) {
            Select(this.options(this.vm.models)).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.index(this.vm.models, this.vm.modelId))
              .width('100%').constraintSize({ minHeight: 44 }).accessibilityText($r('app.string.ui_settings_page_label_selected_model'))
              .onSelect((index: number, _value: string) => this.vm.selectModel(this.vm.models[index]?.id ?? ''))
          }
          Flex({ wrap: FlexWrap.Wrap }) {
            Button($r('app.string.ui_ai_add_model'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 8, bottom: 4 })
              .onClick(() => this.vm.addModel())
            Button($r('app.string.ui_settings_page_label_fetch_models'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 8, bottom: 4 })
              .onClick(() => { this.vm.listModels(); })
            if (this.vm.modelId.length > 0) {
              Button($r('app.string.ui_ai_test'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
                .height(44).margin({ right: 8, bottom: 4 })
                .onClick(() => { this.vm.test(); })
              Button($r('app.string.ui_settings_page_label_delete_model'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontColor($r('app.color.danger'))
                .height(44).margin({ right: 8, bottom: 4 })
                .onClick(() => { this.vm.deleteModels(false); })
              Button($r('app.string.ui_settings_page_label_clear_models'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontColor($r('app.color.danger'))
                .height(44).margin({ right: 8, bottom: 4 })
                .onClick(() => { this.vm.deleteModels(true); })
            }
          }.width('100%')
          if (this.vm.modelId.length > 0) { this.modelFields() }
        }
        TextInput({ placeholder: $r('app.string.ui_settings_page_label_agent_user_name'), text: this.vm.userName }).height(44)
          .onChange((value: string) => { this.vm.userName = value; })
        TextArea({ placeholder: $r('app.string.ui_settings_page_label_agent_system_prompt'), text: this.vm.systemPrompt }).height(72)
          .onChange((value: string) => { this.vm.systemPrompt = value; })
        TextInput({ placeholder: $r('app.string.ui_settings_page_label_agent_maximum_iterations_per_request'), text: this.vm.maximumIterations }).height(44).type(InputType.Number)
          .onChange((value: string) => { this.vm.maximumIterations = value; })
        Button($r('app.string.ui_action_save'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .height(44)
          .onClick(() => { this.vm.save(); })
      }
      if (this.vm.status.length > 0) {
        Text(this.vm.status).fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
      }
    }.width('100%').padding(12).alignItems(HorizontalAlign.Start).enabled(!this.vm.busy)
      .borderRadius($r('app.float.card_radius')).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }
}
