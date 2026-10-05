import { CultivationDraft } from '../model/CultivationDraft';
import { CultivationService } from '../service/CultivationService';
import { CharacterService } from '../service/CharacterService';
import { CharacterListItem } from '../model/CharacterData';
import { CultivateEntry, CultivateProject, CultivationRepo, CultivationPreparedEntry, CultivationSaveReport } from '../data/repo/CultivationRepo';
import { UserService } from '../service/UserService';

@Observed
export class CultivationDraftViewModel {
  drafts: CultivationDraft[] = [];
  projects: CultivateProject[] = [];
  projectId: number = 0;
  overwrite: boolean = false;
  busy: boolean = false;
  message: string = '';
  preview: CultivationPreparedEntry[] = [];
  saved: boolean = false;
  private revision: number = 0;
  private scope: string = '';

  private static accountScope(): string {
    return `${UserService.getInstance().getCurrentUser()?.id ?? 0}:${AppStorage.get<string>('currentUid') ?? ''}`;
  }

  cancel(): void {
    this.revision++;
    this.drafts = []; this.preview = []; this.busy = false; this.saved = false;
  }

  private active(revision: number): boolean {
    return revision === this.revision && this.scope === CultivationDraftViewModel.accountScope();
  }

  async begin(drafts: CultivationDraft[], projectId: number = 0): Promise<void> {
    this.cancel();
    this.scope = CultivationDraftViewModel.accountScope();
    const revision: number = this.revision;
    this.busy = true; this.message = ''; this.overwrite = false;
    try {
      const projects: CultivateProject[] = await CultivationRepo.getProjects();
      if (!this.active(revision)) { return; }
      this.projects = projects;
      this.projectId = projects.some((project: CultivateProject): boolean => project.id === projectId)
        ? projectId : projects[0]?.id ?? 0;
      this.drafts = drafts.map((draft: CultivationDraft): CultivationDraft => CultivationDraft.copy(draft));
    } catch (e) { if (this.active(revision)) { this.message = (e as Error).message; } }
    finally { if (revision === this.revision) { this.busy = false; } }
  }

  async characters(uid: string, characters: CharacterListItem[], weaponOnly: boolean = false): Promise<void> {
    this.cancel(); this.scope = CultivationDraftViewModel.accountScope();
    const revision: number = this.revision;
    this.busy = true; this.message = '正在同步准确的当前进度';
    try {
      const drafts: CultivationDraft[] = await CultivationService.fromCharacters(uid, characters, weaponOnly);
      if (!this.active(revision)) { return; }
      await this.begin(drafts);
    } catch (e) { if (this.active(revision)) { this.message = (e as Error).message; } }
    finally { if (revision === this.revision) { this.busy = false; } }
  }

  async selectedTargets(uid: string, ids: number[]): Promise<void> {
    this.cancel(); this.scope = CultivationDraftViewModel.accountScope();
    const revision: number = this.revision;
    this.busy = true; this.message = '正在准备可编辑目标';
    try {
      const drafts: CultivationDraft[] = [];
      if (uid.length > 0) {
        const characters: CharacterListItem[] = await CharacterService.getInstance().fetchList(uid);
        const selected: CharacterListItem[] = characters.filter((item: CharacterListItem): boolean => ids.indexOf(item.id) >= 0);
        if (selected.length !== ids.length) { throw new Error('本次角色数据不完整，未创建不完整草稿'); }
        const synced: CultivationDraft[] = await CultivationService.fromCharacters(uid, selected);
        for (const draft of synced) { drafts.push(draft); }
      } else {
        for (const id of ids) { drafts.push(await CultivationService.offlineAvatar(id)); }
      }
      if (!this.active(revision)) { return; }
      await this.begin(drafts);
    } catch (e) { if (this.active(revision)) { this.message = (e as Error).message; } }
    finally { if (revision === this.revision) { this.busy = false; } }
  }

  async offline(kind: string, id: number): Promise<void> {
    this.cancel(); this.scope = CultivationDraftViewModel.accountScope();
    const revision: number = this.revision; this.busy = true; this.message = '';
    try {
      const draft: CultivationDraft = kind === 'weapon' ? await CultivationService.offlineWeapon(id) : await CultivationService.offlineAvatar(id);
      if (this.active(revision)) { await this.begin([draft]); }
    } catch (e) { if (this.active(revision)) { this.message = (e as Error).message; } }
    finally { if (revision === this.revision) { this.busy = false; } }
  }

  async edit(entry: CultivateEntry): Promise<void> {
    try {
      const draft: CultivationDraft = CultivationDraft.decode(entry.inputJson);
      draft.entryId = entry.id; draft.expectedInput = entry.inputJson;
      await this.begin([draft], entry.projectId);
      this.message = '保存后仅保留数量未变材料的备齐标记；数量变化的材料需要重新确认';
    } catch (e) {
      this.cancel(); this.scope = CultivationDraftViewModel.accountScope();
      if (entry.inputJson.length > 0) { this.message = (e as Error).message; return; }
      const revision: number = this.revision;
      this.busy = true;
      try {
        const draft: CultivationDraft = entry.avatarId >= 10000000
          ? await CultivationService.offlineAvatar(entry.avatarId) : await CultivationService.offlineWeapon(entry.avatarId);
        if (!this.active(revision)) { return; }
        draft.entryId = entry.id; draft.expectedInput = entry.inputJson;
        draft.current = entry.level; draft.target = entry.targetLevel;
        draft.promote = -1; draft.targetPromote = CultivationDraft.promoteFor(entry.targetLevel, draft.maxLevel);
        for (const skill of draft.skills) { skill.current = 0; skill.target = 0; }
        await this.begin([draft], entry.projectId);
        this.message = '旧计划缺少完整输入。请确认当前突破与每项天赋当前/目标等级；未知值留空，原计划仍保留';
      } catch (failure) { if (this.active(revision)) { this.message = (failure as Error).message; } }
      finally { if (revision === this.revision) { this.busy = false; } }
    }
  }

  change(index: number, field: string, text: string, skillIndex: number = -1): void {
    if (this.busy || this.saved || index < 0 || index >= this.drafts.length) { return; }
    const value: number = /^\d+$/.test(text) ? Number(text) : -1;
    const draft: CultivationDraft = CultivationDraft.copy(this.drafts[index]);
    if (skillIndex >= 0 && skillIndex < draft.skills.length) {
      if (field === 'current') { draft.skills[skillIndex].current = value; }
      else { draft.skills[skillIndex].target = value; }
    } else if (field === 'current') { draft.current = value; }
    else if (field === 'target') { draft.target = value; draft.targetPromote = CultivationDraft.promoteFor(value, draft.maxLevel); }
    else if (field === 'promote') { draft.promote = value; }
    else if (field === 'targetPromote') { draft.targetPromote = value; }
    if (field === 'current' || field === 'promote') { draft.sourceAt = 0; }
    this.drafts[index] = draft; this.drafts = this.drafts.slice(); this.preview = [];
  }

  async calculate(): Promise<void> {
    if (this.busy || this.saved || this.drafts.length === 0) { return; }
    const revision: number = this.revision;
    this.busy = true; this.preview = [];
    try {
      const preview: CultivationPreparedEntry[] = await CultivationService.calculate(this.drafts);
      if (!this.active(revision)) { return; }
      this.preview = preview;
      this.message = '材料预览已更新，确认项目与重复条目策略后保存';
    } catch (e) { if (this.active(revision)) { this.message = (e as Error).message; } }
    finally { if (revision === this.revision) { this.busy = false; } }
  }

  async sync(uid: string): Promise<void> {
    if (this.busy || this.saved || uid.length === 0 || this.drafts.length === 0) { return; }
    const revision: number = this.revision;
    this.busy = true;
    try {
      const characters: CharacterListItem[] = await CharacterService.getInstance().fetchList(uid);
      const updated: CultivationDraft[] = [];
      for (const draft of this.drafts) {
        if (draft.sourceUid.length > 0 && draft.sourceUid !== uid) { throw new Error('请切换回此计划所属 UID 后同步'); }
        const character: CharacterListItem | undefined = characters.find((item: CharacterListItem): boolean => item.id === draft.avatarId);
        if (character === undefined) { throw new Error(`${draft.name} 不在本次完整角色数据中，原计划保持不变`); }
        const fresh: CultivationDraft[] = await CultivationService.fromCharacters(uid, [character], draft.kind === 'weapon', false);
        updated.push(CultivationService.mergeCurrent(draft, fresh[0]));
      }
      if (!this.active(revision)) { return; }
      this.drafts = updated; this.preview = [];
      this.message = '已刷新当前进度，所选目标保持不变；计算预览并保存后才会更新计划';
    } catch (e) { if (this.active(revision)) { this.message = `同步未应用：${(e as Error).message}`; } }
    finally { if (revision === this.revision) { this.busy = false; } }
  }

  async save(): Promise<boolean> {
    if (this.busy || this.saved || this.preview.length !== this.drafts.length || this.preview.length === 0) { return false; }
    if (!this.active(this.revision)) { this.message = '账号已切换，请重新打开目标编辑'; return false; }
    this.busy = true;
    try {
      const report: CultivationSaveReport = await CultivationService.save(this.projectId, this.preview, this.overwrite);
      this.saved = true;
      this.message = `新增 ${report.added} · 更新 ${report.updated} · 跳过 ${report.skipped}\n${report.details.join('\n')}`;
      return true;
    } catch (e) { this.message = `保存失败，原计划未修改：${(e as Error).message}`; return false; }
    finally { this.busy = false; }
  }
}
