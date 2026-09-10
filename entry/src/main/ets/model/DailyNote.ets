/**
 * DailyNote.ets
 * 实时便笺快照：树脂/派遣/每日/周本折扣/洞天宝钱/参变仪/魔神任务 + JSON 映射 + 格式化辅助。
 */
import { DateUtil } from '../common/DateUtil';

export class Expedition {
  avatarSideIcon: string = '';
  /** Ongoing / Finished */
  status: string = '';
  /** 剩余秒数（字符串或时间戳） */
  remainedTime: string = '';

  isFinished(): boolean {
    return this.status === 'Finished';
  }

  /** 剩余时间可读文本 */
  finishText(): string {
    if (this.isFinished()) {
      return '已完成';
    }
    const sec: number = Number(this.remainedTime);
    if (Number.isNaN(sec) || sec <= 0) {
      return '--';
    }
    return DateUtil.countdownText(sec * 1000);
  }
}

export class TransformerRecovery {
  day: number = 0;
  hour: number = 0;
  minute: number = 0;
  second: number = 0;
  reached: boolean = false;

  isReady(): boolean {
    return this.reached;
  }

  text(): string {
    if (this.reached) {
      return '已就绪';
    }
    const parts: string[] = [];
    if (this.day > 0) {
      parts.push(`${this.day}天`);
    }
    if (this.hour > 0) {
      parts.push(`${this.hour}小时`);
    }
    if (this.minute > 0) {
      parts.push(`${this.minute}分`);
    }
    return parts.length > 0 ? parts.join('') : '已就绪';
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
    return note;
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
