/**
 * MiyoliveCode.ets
 * 前瞻直播兑换码（对齐 Windows Web\Hoyolab\Takumi\Event\Miyolive\CodeWrapper）。
 */
export class MiyoliveCode {
  title: string = '';
  code: string = '';
  img: string = '';
  /** 兑换截止时间戳（秒），0 表示未知 */
  toGetTime: number = 0;

  static fromJson(obj: Object): MiyoliveCode {
    const rec = obj as Record<string, Object>;
    const c: MiyoliveCode = new MiyoliveCode();
    c.title = String(rec['title'] ?? '');
    c.code = String(rec['code'] ?? '');
    c.img = String(rec['img'] ?? '');
    c.toGetTime = Number(rec['to_get_time'] ?? 0);
    return c;
  }
}
