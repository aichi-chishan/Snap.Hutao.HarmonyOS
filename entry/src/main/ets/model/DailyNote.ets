/**
 * DailyNote.ets
 * 实时便笺快照：树脂/派遣/每日/周本折扣/洞天宝钱/参变仪/魔神任务 + JSON 映射 + 格式化辅助。
 * 文案与口径对齐 Windows Snap.Hutao（DailyNote.cs / Transformer.cs / Expedition.cs / SH.resx）：
 * 树脂「原粹树脂已完全恢复 / 将于 MM.dd HH:mm 全部恢复」、洞天宝钱「尚未解锁洞天 /
 * 洞天宝钱已达存储上限 / 将于 MM.dd HH:mm 达到存储上限」、每日委托奖励三态、
 * 周本折扣显示已消耗/上限、参变仪「X 天 X 时 X 分后可再次使用」。
 */
import { DateUtil } from '../common/DateUtil';

/** 魔神任务章节（archon_quest_progress.list 项） */
export class ArchonQuestChapter {
  /** Ongoing / Finished / NotOpen（兼容 API 带 Status 前缀的形态） */
  status: string = '';
  /** 第X章 */
  chapterNum: string = '';
  chapterTitle: string = '';

  /** 归一化状态：Ongoing / Finished / NotOpen */
  normalizedStatus(): string {
    return this.status.replace('Status', '');
  }

  isFinished(): boolean {
    return this.normalizedStatus() === 'Finished';
  }

  /** 状态文案（对齐 Windows ArchonQuestStatus 本地化） */
  statusText(): string {
    const s: string = this.normalizedStatus();
    if (s === 'Finished') {
      return '全部完成';
    }
    if (s === 'NotOpen') {
      return '尚未开启';
    }
    return '进行中';
  }
}

export class Expedition {
  avatarSideIcon: string = '';
  /** Ongoing / Finished */
  status: string = '';
  /** 剩余秒数（字符串或时间戳） */
  remainedTime: string = '';

  /** 15 小时短派遣角色（对齐 Windows Expedition.ShortExpeditionTimeAvatars） */
  private static readonly SHORT_EXPEDITION_AVATARS: string[] = [
    'UI_AvatarIcon_Side_Bennett',
    'UI_AvatarIcon_Side_Chongyun',
    'UI_AvatarIcon_Side_Fischl',
    'UI_AvatarIcon_Side_Keqing',
    'UI_AvatarIcon_Side_Sara',
  ];

  isFinished(): boolean {
    return this.status === 'Finished';
  }

  /** 派遣总时长秒数：短派遣角色 15h，其余 20h（对齐 Windows TotalTime） */
  totalSecond(): number {
    const hours: number = Expedition.isShortAvatar(this.avatarSideIcon) ? 15 : 20;
    return hours * 60 * 60;
  }

  /** 已进行秒数（对齐 Windows PassedTime = TotalTime - RemainedTime） */
  passedSecond(): number {
    const remain: number = Number(this.remainedTime);
    const remainSec: number = Number.isNaN(remain) ? 0 : Math.max(0, remain);
    return Math.max(0, this.totalSecond() - remainSec);
  }

  /** side icon URL → AvatarIcon 图标名（UI_AvatarIcon_Side_Xxx → UI_AvatarIcon_Xxx） */
  iconName(): string {
    if (this.avatarSideIcon.length === 0) {
      return '';
    }
    const slash: number = this.avatarSideIcon.lastIndexOf('/');
    let name: string = slash >= 0 ? this.avatarSideIcon.substring(slash + 1) : this.avatarSideIcon;
    if (name.endsWith('.png')) {
      name = name.substring(0, name.length - 4);
    }
    return name.replace('UI_AvatarIcon_Side_', 'UI_AvatarIcon_');
  }

  private static isShortAvatar(sideIcon: string): boolean {
    for (const a of Expedition.SHORT_EXPEDITION_AVATARS) {
      if (sideIcon.includes(a)) {
        return true;
      }
    }
    return false;
  }

  /** 剩余时间：已完成 → '已完成'；否则 'X 时 Y 分'（对齐 Windows RemainedTimeFormatted） */
  finishText(): string {
    if (this.isFinished()) {
      return '已完成';
    }
    const sec: number = Number(this.remainedTime);
    const remainSec: number = Number.isNaN(sec) ? 0 : Math.max(0, sec);
    const h: number = Math.floor(remainSec / 3600);
    const m: number = Math.floor((remainSec % 3600) / 60);
    return `${h} 时 ${m} 分`;
  }
}

export class TransformerRecovery {
  /** 是否已获得参变仪（obtained；旧缓存 JSON 无该字段时由 hasTransformer 推断） */
  obtained: boolean = false;
  day: number = 0;
  hour: number = 0;
  minute: number = 0;
  second: number = 0;
  reached: boolean = false;

  /** 是否拥有参变仪（兼容仅含冷却字段的旧缓存：有冷却数据/已就绪即视为已获得） */
  hasTransformer(): boolean {
    return this.obtained || this.reached || this.day > 0 || this.hour > 0 || this.minute > 0 || this.second > 0;
  }

  isReady(): boolean {
    return this.reached;
  }

  /** 冷却剩余可读时长 'X 天 X 时 X 分'（仅拼接 >0 的段；已就绪返回 '已就绪'） */
  text(): string {
    if (this.reached) {
      return '已就绪';
    }
    const parts: string[] = [];
    if (this.day > 0) {
      parts.push(`${this.day} 天`);
    }
    if (this.hour > 0) {
      parts.push(`${this.hour} 时`);
    }
    if (this.minute > 0) {
      parts.push(`${this.minute} 分`);
    }
    return parts.join(' ');
  }
}

export class DailyTaskStatus {
  finishedTaskNum: number = 0;
  totalTaskNum: number = 0;
  isExtraTaskRewardReceived: boolean = false;
  status: number = 0;

  isAllFinished(): boolean {
    return this.totalTaskNum > 0 && this.finishedTaskNum >= this.totalTaskNum;
  }
}

export class DailyNote {
  currentResin: number = 0;
  maxResin: number = 160;
  /** 树脂恢复完成时间（ISO/日期字符串） */
  resinRecoveryTime: string = '';
  /** 树脂恢复剩余秒数（部分接口） */
  resinRecoverySecond: number = 0;

  finishedTaskNum: number = 0;
  totalTaskNum: number = 0;
  isExtraTaskRewardReceived: boolean = false;

  remainResinDiscountNum: number = 0;
  resinDiscountNumLimit: number = 0;

  currentHomeCoin: number = 0;
  maxHomeCoin: number = 0;
  homeCoinRecoveryTime: string = '';

  currentExpeditionNum: number = 0;
  maxExpeditionNum: number = 0;
  expeditions: Expedition[] = [];

  transformer: TransformerRecovery = new TransformerRecovery();
  dailyTask: DailyTaskStatus = new DailyTaskStatus();
  /** 魔神任务进度（archon_quest_progress.list；空列表 = 全部完成，对齐 Windows IsArchonQuestFinished） */
  archonQuests: ArchonQuestChapter[] = [];

  /** 刷新时间戳（本地） */
  refreshTime: number = 0;

  /** 从 dailyNote API data 解析 */
  static fromJson(data: Object): DailyNote {
    const obj = data as Record<string, Object>;
    const note: DailyNote = new DailyNote();
    note.currentResin = number(obj['current_resin'], 0);
    note.maxResin = number(obj['max_resin'], 160);
    // 注意：resin_recovery_time 是「距树脂回满的秒数」（对齐 Windows DailyNote.ResinRecoveryTime:int），
    // 不是 Unix 时间戳；home_coin_recovery_time 同理。锚点为本次拉取时间 refreshTime。
    note.resinRecoveryTime = str(obj['resin_recovery_time']);
    note.resinRecoverySecond = number(obj['resin_recovery_time'], 0);
    note.finishedTaskNum = number(obj['finished_task_num'], 0);
    note.totalTaskNum = number(obj['total_task_num'], 0);
    note.isExtraTaskRewardReceived = bool(obj['is_extra_task_reward_received']);
    note.remainResinDiscountNum = number(obj['remain_resin_discount_num'], 0);
    note.resinDiscountNumLimit = number(obj['resin_discount_num_limit'], 0);
    note.currentHomeCoin = number(obj['current_home_coin'], 0);
    note.maxHomeCoin = number(obj['max_home_coin'], 0);
    note.homeCoinRecoveryTime = str(obj['home_coin_recovery_time']);
    note.currentExpeditionNum = number(obj['current_expedition_num'], 0);
    note.maxExpeditionNum = number(obj['max_expedition_num'], 0);

    const exps = obj['expeditions'] as Array<Object>;
    if (exps !== undefined && exps !== null) {
      for (let i = 0; i < exps.length; i++) {
        const e = exps[i] as Record<string, Object>;
        const exp: Expedition = new Expedition();
        exp.avatarSideIcon = str(e['avatar_side_icon']);
        exp.status = str(e['status']);
        exp.remainedTime = str(e['remained_time']);
        note.expeditions.push(exp);
      }
    }
    // transformer
    const tr = obj['transformer'] as Record<string, Object>;
    if (tr !== undefined && tr !== null) {
      note.transformer.obtained = bool(tr['obtained']);
      const rec = tr['recovery_time'] as Record<string, Object>;
      if (rec !== undefined && rec !== null) {
        note.transformer.day = number(rec['Day'], 0);
        note.transformer.hour = number(rec['Hour'], 0);
        note.transformer.minute = number(rec['Minute'], 0);
        note.transformer.second = number(rec['Second'], 0);
        note.transformer.reached = bool(rec['reached']);
      }
    }
    // daily task
    const dt = obj['daily_task'] as Record<string, Object>;
    if (dt !== undefined && dt !== null) {
      note.dailyTask.finishedTaskNum = number(dt['finished_task_num'], note.finishedTaskNum);
      note.dailyTask.totalTaskNum = number(dt['total_task_num'], note.totalTaskNum);
      note.dailyTask.isExtraTaskRewardReceived = bool(dt['is_extra_task_reward_received']);
      note.dailyTask.status = number(dt['status'], 0);
    }
    // 接口部分版本不返回 daily_task 子对象（或字段缺失）：用顶层 finished/total_task_num 兜底，
    // 否则便笺页「每日委托」恒显示 0/0（主页卡用的是顶层字段，两处会不一致）。
    if (note.dailyTask.totalTaskNum <= 0 && note.totalTaskNum > 0) {
      note.dailyTask.finishedTaskNum = note.finishedTaskNum;
      note.dailyTask.totalTaskNum = note.totalTaskNum;
      note.dailyTask.isExtraTaskRewardReceived = note.isExtraTaskRewardReceived;
    }
    // archon quest progress（魔神任务章节）
    const aqp = obj['archon_quest_progress'] as Record<string, Object>;
    if (aqp !== undefined && aqp !== null) {
      const list = aqp['list'] as Array<Object>;
      if (list !== undefined && list !== null) {
        for (let i = 0; i < list.length; i++) {
          const q = list[i] as Record<string, Object>;
          const chapter: ArchonQuestChapter = new ArchonQuestChapter();
          chapter.status = str(q['status']);
          chapter.chapterNum = str(q['chapter_num']);
          chapter.chapterTitle = str(q['chapter_title']);
          note.archonQuests.push(chapter);
        }
      }
    }
    return note;
  }

  /** 从 prefs 持久化 JSON 还原魔神任务列表（DB 表 archon_json 列恒空，由 ViewModel 落 prefs） */
  static archonListFromJson(text: string): ArchonQuestChapter[] {
    const list: ArchonQuestChapter[] = [];
    if (text.length === 0) {
      return list;
    }
    try {
      const arr = JSON.parse(text) as Array<Object>;
      for (let i = 0; i < arr.length; i++) {
        const q = arr[i] as Record<string, Object>;
        const chapter: ArchonQuestChapter = new ArchonQuestChapter();
        chapter.status = String(q['status'] ?? '');
        chapter.chapterNum = String(q['chapterNum'] ?? '');
        chapter.chapterTitle = String(q['chapterTitle'] ?? '');
        list.push(chapter);
      }
    } catch (e) {
      return list;
    }
    return list;
  }

  // ---- 魔神任务（对齐 Windows DailyNoteArchonQuestView / DailyNote.IsArchonQuestFinished）----

  /** 魔神任务是否全部完成：list 为空即全部完成（对齐 Windows） */
  archonQuestFinished(): boolean {
    return this.archonQuests.length === 0;
  }

  archonQuestFinishedCount(): number {
    let n: number = 0;
    for (const c of this.archonQuests) {
      if (c.isFinished()) {
        n++;
      }
    }
    return n;
  }

  /** 主文本：任务状态文案（全部完成/进行中/尚未开启） */
  archonQuestMainText(): string {
    if (this.archonQuests.length === 0) {
      return '全部完成';
    }
    return this.archonQuests[0].statusText();
  }

  /** 副文本：'第X章 章节名' / '所有魔神任务已完成'（对齐 Windows FormattedChapter） */
  archonQuestSubText(): string {
    if (this.archonQuests.length === 0) {
      return '所有魔神任务已完成';
    }
    const c: ArchonQuestChapter = this.archonQuests[0];
    return `${c.chapterNum} ${c.chapterTitle}`.trim();
  }

  /** 进度条总数（Max=任务章节数，Value=已完成数） */
  archonQuestTotal(): number {
    return Math.max(1, this.archonQuests.length);
  }

  // ---- 文本格式化（对齐 Windows DailyNote.cs FormattedX 属性）----

  /** 主文本 '160/160'（对齐 Windows FormattedResin） */
  formattedResin(): string {
    return `${this.currentResin}/${this.maxResin}`;
  }

  /**
   * 树脂副文本（对齐 Windows ResinRecoveryTargetTime）：
   * 已满/无剩余 = '原粹树脂已完全恢复'；否则 = '将于 MM.dd HH:mm 全部恢复'
   */
  resinRecoveryTargetText(): string {
    const sec: number = this.resinRecoverySeconds();
    if (sec <= 0) {
      return '原粹树脂已完全恢复';
    }
    return `将于 ${DailyNote.targetClockText(this.resinRecoveryRemainMs())} 全部恢复`;
  }

  /** 洞天宝钱主文本（对齐 Windows FormattedHomeCoin）：未解锁 '尚未解锁洞天'；否则 'X/Y' */
  formattedHomeCoin(): string {
    return this.maxHomeCoin <= 0 ? '尚未解锁洞天' : `${this.currentHomeCoin}/${this.maxHomeCoin}`;
  }

  /**
   * 洞天宝钱副文本（对齐 Windows FormattedHomeCoinRecoveryTargetTime）：
   * 未解锁 = '尚未解锁洞天'；已满 = '洞天宝钱已达存储上限'；否则 = '将于 MM.dd HH:mm 达到存储上限'
   */
  homeCoinRecoveryTargetText(): string {
    if (this.maxHomeCoin <= 0) {
      return '尚未解锁洞天';
    }
    const n: number = Number(this.homeCoinRecoveryTime);
    const sec: number = !Number.isNaN(n) && n > 0 ? (n > 100000000000 ? Math.floor(n / 1000) : n) : 0;
    if (sec <= 0) {
      return '洞天宝钱已达存储上限';
    }
    const anchor: number = this.refreshTime > 0 ? this.refreshTime : Date.now();
    return `将于 ${DailyNote.targetClockText(Math.max(0, anchor + sec * 1000 - Date.now()))} 达到存储上限`;
  }

  /** 每日委托主文本 'X/Y'（对齐 Windows FormattedTask） */
  formattedTask(): string {
    return `${this.finishedTaskNum}/${this.totalTaskNum}`;
  }

  /** 每日委托奖励副文本三态（对齐 Windows ExtraTaskRewardDescription） */
  extraTaskRewardDescription(): string {
    if (this.isExtraTaskRewardReceived) {
      return '「每日委托」奖励已领取';
    }
    return this.finishedTaskNum === this.totalTaskNum
      ? '「每日委托」奖励未领取' : '今日完成委托数量不足';
  }

  /** 周本折扣已消耗次数（对齐 Windows ResinDiscountUsedNum = Limit - Remain） */
  resinDiscountUsedNum(): number {
    return Math.max(0, this.resinDiscountNumLimit - this.remainResinDiscountNum);
  }

  /** 周本折扣主文本 '已消耗/上限'（对齐 Windows FormattedResinDiscount；方向与旧版 remain/limit 相反） */
  formattedResinDiscount(): string {
    return `${this.resinDiscountUsedNum()}/${this.resinDiscountNumLimit}`;
  }

  /** 参变仪主文本（对齐 Windows Transformer.ObtainedAndReachedFormatted） */
  transformerMainText(): string {
    if (!this.transformer.hasTransformer()) {
      return '尚未获得';
    }
    return this.transformer.reached ? '可使用' : '冷却中';
  }

  /** 参变仪副文本（对齐 Windows Transformer.ObtainedAndTimeFormatted） */
  transformerSubText(): string {
    if (!this.transformer.hasTransformer()) {
      return '尚未获得参量质变仪';
    }
    if (this.transformer.reached) {
      return '已准备完成';
    }
    const t: string = this.transformer.text();
    return t.length > 0 ? `${t}后可再次使用` : '即将就绪';
  }

  /** 参变仪冷却已进行秒数（对齐 Windows RecoveryTime.TotalSeconds = 7天 - 剩余；进度条 Max=604800） */
  transformerElapsedSecond(): number {
    const remain: number = this.transformer.second + this.transformer.minute * 60
      + this.transformer.hour * 3600 + this.transformer.day * 86400;
    return Math.max(0, Math.min(604800, 604800 - remain));
  }

  /** 树脂环形进度 0~1 */
  resinProgress(): number {
    if (this.maxResin <= 0) {
      return 0;
    }
    return Math.min(1, this.currentResin / this.maxResin);
  }

  /** 树脂是否达到恢复阈值 */
  resinReached(threshold: number): boolean {
    return threshold > 0 && this.currentResin >= threshold;
  }

  /** 树脂恢复剩余可读文本 */
  resinRecoveryText(): string {
    if (this.currentResin >= this.maxResin) {
      return '树脂已满';
    }
    const ms: number = this.resinRecoveryRemainMs();
    if (ms > 0) {
      return `已满还需 ${DateUtil.countdownText(ms)}`;
    }
    if (this.resinRecoverySeconds() > 0) {
      // 已到恢复时刻但快照未更新（下一次自动刷新会拉正）
      return '即将回满';
    }
    return '--';
  }

  /** 剩余毫秒 → 'MM.dd HH:mm' 目标时刻（对齐 Windows {0:MM.dd HH:mm} 格式） */
  private static targetClockText(remainMs: number): string {
    if (remainMs <= 0) {
      return '--';
    }
    const d: Date = new Date(Date.now() + remainMs);
    return `${DateUtil.pad2(d.getMonth() + 1)}.${DateUtil.pad2(d.getDate())} ` +
      `${DateUtil.pad2(d.getHours())}:${DateUtil.pad2(d.getMinutes())}`;
  }

  /** 回满剩余秒数（resin_recovery_time；兼容历史库里存的字符串形态） */
  resinRecoverySeconds(): number {
    if (this.resinRecoverySecond > 0) {
      return this.resinRecoverySecond;
    }
    const n: number = Number(this.resinRecoveryTime);
    if (!Number.isNaN(n) && n > 0) {
      // 兼容曾被误存为毫秒时间戳的旧数据
      return n > 100000000000 ? Math.floor(n / 1000) : n;
    }
    return 0;
  }

  /** 距树脂回满的剩余毫秒（秒数 + 拉取时刻锚点；从库里读出来同样可算） */
  private resinRecoveryRemainMs(): number {
    if (this.currentResin >= this.maxResin) {
      return 0;
    }
    const sec: number = this.resinRecoverySeconds();
    if (sec <= 0) {
      return 0;
    }
    const anchor: number = this.refreshTime > 0 ? this.refreshTime : Date.now();
    return Math.max(0, anchor + sec * 1000 - Date.now());
  }

  /** 洞天宝钱是否达到阈值 */
  homeCoinReached(threshold: number): boolean {
    return threshold > 0 && this.currentHomeCoin >= threshold;
  }
}

function number(v: Object, def: number): number {
  if (v === undefined || v === null) {
    return def;
  }
  const n: number = Number(v);
  return Number.isNaN(n) ? def : n;
}

function str(v: Object): string {
  if (v === undefined || v === null) {
    return '';
  }
  return String(v);
}

function bool(v: Object): boolean {
  if (v === undefined || v === null) {
    return false;
  }
  return v === true || v === 'true' || v === 1 || v === '1';
}
