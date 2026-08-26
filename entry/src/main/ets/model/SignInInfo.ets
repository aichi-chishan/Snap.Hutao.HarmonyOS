/**
 * SignInInfo.ets
 * 签到信息模型（对齐米游社 luna 接口）：
 * - luna/info -> total_sign_day / is_sign / today
 * - luna/home -> month / awards[icon,name,cnt] / resign
 */
export class SignInReward {
  day: number = 1;
  name: string = '';
  count: number = 1;
  icon: string = '';
}

export class SignInInfo {
  signedDays: number = 0;
  currentMonth: number = 0;
  rewards: SignInReward[] = [];
  message: string = '';

  /** 从 luna/home 响应 data 解析（awards 是当月 1..N 天奖励） */
  static fromHome(data: Object): SignInInfo {
    const obj = data as Record<string, Object>;
    const info: SignInInfo = new SignInInfo();
    info.currentMonth = Number(obj['month'] ?? new Date().getMonth() + 1);
    const awards = obj['awards'] as Array<Object>;
    if (awards !== undefined && awards !== null) {
      for (let i = 0; i < awards.length; i++) {
        const a = awards[i] as Record<string, Object>;
        const r: SignInReward = new SignInReward();
        r.day = i + 1;
        r.name = String(a['name'] ?? '');
        r.count = Number(a['cnt'] ?? 1);
        r.icon = String(a['icon'] ?? '');
        info.rewards.push(r);
      }
    }
    return info;
  }

  /** 从 luna/info 响应 data 解析（is_sign/total_sign_day） */
  static fromInfo(data: Object): SignInInfo {
    const obj = data as Record<string, Object>;
    const info: SignInInfo = new SignInInfo();
    info.signedDays = Number(obj['total_sign_day'] ?? 0);
    // is_sign 表示今日已签，则今日计入总天数
    const isSign: boolean = Boolean(obj['is_sign'] ?? false);
    const todayDay: number = new Date().getDate();
    if (isSign && info.signedDays < todayDay) {
      info.signedDays = todayDay;
    }
    return info;
  }

  /** 合并：以 home 为奖励基础，写入 info 的已签天数 */
  merge(home: SignInInfo): void {
    this.currentMonth = home.currentMonth;
    this.rewards = home.rewards;
  }

  /** 某天是否已签到（前 signedDays 天视为已签） */
  isSigned(day: number): boolean {
    return day > 0 && day <= this.signedDays;
  }

  /** 今天是否已签到 */
  isTodaySigned(todayDay: number): boolean {
    return this.signedDays >= todayDay;
  }
}
