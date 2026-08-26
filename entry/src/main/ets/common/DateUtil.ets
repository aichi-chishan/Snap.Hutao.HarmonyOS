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

  /** ISO 字符串 → 毫秒时间戳（服务端返回的 'yyyy-MM-dd HH:mm:ss' 或 ISO8601） */
  static parseToMs(text: string): number {
    if (!text || text.length === 0) {
      return 0;
    }
    // 兼容 'yyyy-MM-dd HH:mm:ss'（无 TimeZone，按本地解析）
    const normalized: string = text.replace(' ', 'T');
    const d: Date = new Date(normalized);
    const ms: number = d.getTime();
    return Number.isNaN(ms) ? 0 : ms;
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
