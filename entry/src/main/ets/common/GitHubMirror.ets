/**
 * GitHubMirror.ets
 * GitHub 国内直连加速：raw.githubusercontent.com 直连失败时依序回退公共镜像前缀。
 * 候选：直连 → ghfast.top → gh-proxy.com（免费公共反代，可用性随时间波动，依序尝试）。
 */
export class GitHubMirror {
  private static readonly MIRRORS: string[] = [
    'https://ghfast.top/',
    'https://gh-proxy.com/',
  ];

  /** 生成候选 URL 列表（直连优先，镜像随后） */
  static candidates(url: string): string[] {
    const out: string[] = [url];
    if (url.startsWith('https://raw.githubusercontent.com/')) {
      for (const m of GitHubMirror.MIRRORS) {
        out.push(`${m}${url}`);
      }
    }
    return out;
  }
}
