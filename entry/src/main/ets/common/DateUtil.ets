/**
 * DateUtil.ets
 * 时间戳格式化 / 倒计时 / 恢复时间差 → 可读文本。
 */
export class DateUtil {
  /** 补零 */
  static pad2(n: number): string {
    return n < 10 ? '0' + n : n.toString();
  }

  /** 毫秒时间戳 → 'yyyy-MM-dd HH:mm:ss' */
  static formatTimestamp(ms: number): string {
    if (ms <= 0) {
      return '--';
    }
    const d: Date = new Date(ms);
    const y: number = d.getFullYear();
    const mo: string = DateUtil.pad2(d.getMonth() + 1);
    const day: string = DateUtil.pad2(d.getDate());
    const h: string = DateUtil.pad2(d.getHours());
    const mi: string = DateUtil.pad2(d.getMinutes());
    const s: string = DateUtil.pad2(d.getSeconds());
    return `${y}-${mo}-${day} ${h}:${mi}:${s}`;
  }

  /** 毫秒时间戳 → 'MM-dd HH:mm' */
  static formatMonthDay(ms: number): string {
    if (ms <= 0) {
      return '--';
    }
    const d: Date = new Date(ms);
    return `${DateUtil.pad2(d.getMonth() + 1)}-${DateUtil.pad2(d.getDate())} ${DateUtil.pad2(d.getHours())}:${DateUtil.pad2(d.getMinutes())}`;
  }

  /** 毫秒时间戳 → 'yyyy-MM-dd'（签到日历用） */
  static formatDate(ms: number): string {
    if (ms <= 0) {
      return '--';
    }
    const d: Date = new Date(ms);
    return `${d.getFullYear()}-${DateUtil.pad2(d.getMonth() + 1)}-${DateUtil.pad2(d.getDate())}`;
  }

  /** 服务端时间字段 → 毫秒时间戳。
   *  兼容三种形态：Unix 秒字符串（便笺 resin_recovery_time/home_coin_recovery_time）、
   *  Unix 毫秒字符串，以及 'yyyy-MM-dd HH:mm:ss' / ISO8601。
   *  注：纯数字串直接交给 Date 解析在部分运行时会被当作年份，得到天文数字（曾导致
   *  "已满还需 1931514天18小时"），必须先按时间戳处理。 */
  static parseToMs(text: string): number {
    if (!text || text.length === 0) {
      return 0;
    }
    const trimmed: string = text.trim();
    if (DateUtil.isAllDigits(trimmed)) {
      const n: number = Number(trimmed);
      if (!Number.isNaN(n) && n > 0) {
        // 13 位及以上视为毫秒；10 位（秒）换算成毫秒
        return n < 100000000000 ? Math.floor(n * 1000) : n;
      }
      return 0;
    }
    // 兼容 'yyyy-MM-dd HH:mm:ss'（无 TimeZone，按本地解析）
    const normalized: string = trimmed.replace(' ', 'T');
    const d: Date = new Date(normalized);
    const ms: number = d.getTime();
    return Number.isNaN(ms) ? 0 : ms;
  }

  /** 纯数字串判断（不依赖正则，ArkTS 下遍历即可） */
  private static isAllDigits(text: string): boolean {
    if (text.length === 0) {
      return false;
    }
    for (let i = 0; i < text.length; i++) {
      const c: number = text.charCodeAt(i);
      if (c < 48 || c > 57) {
        return false;
      }
    }
    return true;
  }

  /** 剩余时长（毫秒）→ 'x天x小时x分' */
  static countdownText(ms: number): string {
    if (ms <= 0) {
      return '已就绪';
    }
    const totalSec: number = Math.floor(ms / 1000);
    const days: number = Math.floor(totalSec / 86400);
    const hours: number = Math.floor((totalSec % 86400) / 3600);
    const minutes: number = Math.floor((totalSec % 3600) / 60);
    if (days > 0) {
      return `${days}天${hours}小时`;
    }
    if (hours > 0) {
      return `${hours}小时${minutes}分`;
    }
    return `${minutes}分`;
  }

  /** 两个时间戳差值可读文本（from 到 to 还需多久） */
  static remainingBetween(fromMs: number, toMs: number): string {
    const diff: number = toMs - fromMs;
    if (diff <= 0) {
      return '完成';
    }
    return DateUtil.countdownText(diff);
  }

  /** 相对时间（毫秒）→ '刚刚/x分钟前/x小时前/x天前' */
  static timeAgo(ms: number): string {
    if (ms <= 0) {
      return '--';
    }
    const diff: number = Date.now() - ms;
    if (diff < 60 * 1000) {
      return '刚刚';
    }
    if (diff < 60 * 60 * 1000) {
      return `${Math.floor(diff / 60000)}分钟前`;
    }
    if (diff < 24 * 60 * 60 * 1000) {
      return `${Math.floor(diff / 3600000)}小时前`;
    }
    return `${Math.floor(diff / 86400000)}天前`;
  }
}
