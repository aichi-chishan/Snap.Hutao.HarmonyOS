/** Account cookies belong only to the exact, HTTPS miHoYo API origins below. */
export class CredentialPolicy {
  static accountRegion(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^https:\/\/([a-z0-9.-]+)(?::443)?(?:[/?#]|$)/i);
    if (match === null) {
      return '';
    }
    const host: string = match[1].toLowerCase();
    const chinese: string[] = [
      'passport-api.mihoyo.com', 'api-takumi.mihoyo.com', 'api-takumi-record.mihoyo.com',
      'bbs-api.mihoyo.com', 'bbs-api.miyoushe.com', 'hk4e-api.mihoyo.com',
    ];
    const oversea: string[] = [
      'api-account-os.hoyoverse.com', 'passport-api-sg.hoyoverse.com',
      'api-os-takumi.hoyoverse.com', 'bbs-api-os.hoyolab.com',
      'sg-public-api.hoyolab.com', 'sg-hk4e-api.hoyolab.com', 'sg-hk4e-api.hoyoverse.com',
    ];
    if (chinese.indexOf(host) >= 0) {
      return 'cn';
    }
    return oversea.indexOf(host) >= 0 ? 'os' : '';
  }

  static allowsSessionCookie(url: string, isOversea: boolean): boolean {
    return CredentialPolicy.accountRegion(url) === (isOversea ? 'os' : 'cn');
  }

  /** Query strings can contain authkey, stoken, tickets and verification challenges. */
  static logUrl(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([a-z0-9.-]+)(?::[0-9]+)?(\/[^?#]*)?/i);
    if (match === null || url.indexOf('@') >= 0) {
      return '[redacted-url]';
    }
    return `https://${match[1].toLowerCase()}${match[2] ?? '/'}`;
  }
}
