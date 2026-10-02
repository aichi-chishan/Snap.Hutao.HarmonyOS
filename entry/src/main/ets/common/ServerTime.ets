/** 与 Windows PlayerUid.GetRegionTimeZoneUtcOffsetForRegion 相同的服务器时区。 */
export class ServerTime {
  static offsetHours(region: string): number {
    if (region === 'os_usa') { return -5; }
    if (region === 'os_euro') { return 1; }
    return 8;
  }

  static date(region: string, timestamp: number = Date.now()): string {
    return new Date(timestamp + ServerTime.offsetHours(region) * 3600000).toISOString().substring(0, 10);
  }
}
