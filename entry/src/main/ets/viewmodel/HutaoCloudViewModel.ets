import { HutaoCloudService } from '../service/HutaoCloudService';
import { HutaoCloudEntry, HutaoCloudMetric } from '../model/HutaoCloud';
import { GachaArchive } from '../model/GachaArchive';

@Observed
export class HutaoCloudViewModel {
  busy: boolean = false;
  loggedIn: boolean = false;
  userName: string = '';
  email: string = '';
  password: string = '';
  code: string = '';
  newEmail: string = '';
  newCode: string = '';
  redeemCode: string = '';
  uid: string = '';
  message: string = '';
  entries: HutaoCloudEntry[] = [];
  archives: GachaArchive[] = [];
  info: HutaoCloudMetric[] = [];
  metrics: HutaoCloudMetric[] = [];
  private service: HutaoCloudService = HutaoCloudService.getInstance();

  async load(): Promise<void> {
    try {
      await this.service.initialize();
      this.syncSession();
      this.archives = await this.service.localArchives();
      if (this.uid.length === 0 && this.archives.length > 0) { this.uid = this.archives[0].uid; }
    } catch (error) { this.message = (error as Error).message; }
  }

  private syncSession(): void {
    this.loggedIn = this.service.isLoggedIn();
    this.userName = this.service.getUserName();
    if (this.email.length === 0) { this.email = this.userName; }
  }

  async execute(action: string): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.message = '';
    try {
      if (action === 'login' || action === 'register' || action === 'reset') {
        await this.service.authenticate(this.email, this.password, this.code, action);
        this.password = ''; this.code = '';
        this.message = '通行证登录状态已更新';
        this.syncSession();
        this.info = await this.service.userInfo();
      } else if (action === 'verifyRegister' || action === 'verifyReset' || action === 'verifyCancel') {
        await this.service.verify(this.email, action === 'verifyReset' ? 'reset' : (action === 'verifyCancel' ? 'cancel' : 'register'));
        this.message = '验证码已发送，请检查邮箱';
      } else if (action === 'verifyOldEmail' || action === 'verifyNewEmail') {
        await this.service.verify(action === 'verifyOldEmail' ? this.userName : this.newEmail,
          action === 'verifyOldEmail' ? 'oldEmail' : 'newEmail');
        this.message = '邮箱验证码已发送';
      } else if (action === 'resetEmail') {
        await this.service.resetEmail(this.code, this.newEmail, this.newCode);
        this.email = this.newEmail; this.newCode = ''; this.code = '';
        this.message = '邮箱已更新';
      } else if (action === 'userInfo') {
        this.info = await this.service.userInfo();
      } else if (action === 'logout' || action === 'revokeAll') {
        await this.service.logout(action === 'revokeAll');
        this.info = []; this.entries = []; this.message = '已撤销登录凭据并退出';
      } else if (action === 'forget') {
        await this.service.forgetLocal(); this.info = []; this.entries = [];
        this.message = '已清除此设备上的云登录状态';
      } else if (action === 'unregister') {
        await this.service.unregister(this.email, this.password, this.code);
        this.password = ''; this.code = ''; this.info = []; this.entries = [];
        this.message = '通行证账号已注销';
      } else if (action === 'redeem') {
        await this.service.redeem(this.redeemCode); this.redeemCode = '';
        this.info = await this.service.userInfo(); this.message = '兑换成功';
      } else if (action === 'entries') {
        this.entries = await this.service.entries();
        this.message = `已读取 ${this.entries.length} 个云存档`;
      } else if (action === 'upload') {
        const count: number = await this.service.upload(this.uid);
        this.message = `已上传 ${count} 条新增记录`;
        this.entries = await this.service.entries();
      } else if (action === 'retrieve') {
        const count: number = await this.service.retrieve(this.uid);
        this.message = `已合并 ${count} 条云记录`;
        this.archives = await this.service.localArchives();
      } else if (action === 'delete') {
        await this.service.deleteArchive(this.uid);
        this.entries = await this.service.entries(); this.message = '指定 UID 云存档已删除';
      }
      this.syncSession();
    } catch (error) {
      this.message = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  async statistics(kind: string, last: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.message = ''; this.metrics = [];
    try {
      const data: Object = await this.service.statistics(kind, last);
      const rows: HutaoCloudMetric[] = [];
      this.flatten(data, '', rows, 0);
      this.metrics = rows;
      this.message = rows.length === 0 ? '本期暂无统计数据' : `已读取 ${rows.length} 项统计`;
    } catch (error) { this.message = (error as Error).message; }
    finally { this.busy = false; }
  }

  private label(key: string): string {
    const labels: Record<string, string> = {
      'scheduleId': '期次', 'recordTotal': '上传记录', 'spiralAbyssTotal': '深渊挑战记录',
      'spiralAbyssPassed': '通关人数', 'spiralAbyssStarTotal': '星数总计', 'spiralAbyssFullStar': '满星人数',
      'spiralAbyssBattleTotal': '战斗次数', 'timestamp': '统计时间', 'timeTotal': '总用时', 'timeAverage': '平均用时',
      'avatarId': '角色编号', 'id': '编号', 'item': '物品编号', 'count': '数量', 'pull': '抽数',
      'rate': '比率', 'value': '数值', 'avatarEvent': '角色活动祈愿', 'avatarEvent2': '角色活动祈愿 2',
      'weaponEvent': '武器活动祈愿', 'chronicled': '集录祈愿', 'totalValidPulls': '有效总抽数',
      'distribution': '分布', 'weaponId': '武器编号', 'avatar': '角色', 'avatars': '角色列表',
      'holdingRate': '持有率', 'utilizationRate': '使用率', 'attendanceRate': '出场率',
      'team': '队伍', 'floor': '楼层', 'level': '等级', 'constellation': '命座', 'reliquarySets': '圣遗物套装',
    };
    const lower: string = key.charAt(0).toLowerCase() + key.substring(1);
    return labels[lower] ?? key;
  }

  private flatten(value: Object, prefix: string, rows: HutaoCloudMetric[], depth: number): void {
    if (depth > 12 || value === null || value === undefined) { return; }
    if (Array.isArray(value)) {
      const array: Object[] = value as Object[];
      for (let i: number = 0; i < array.length; i++) { this.flatten(array[i], `${prefix} ${i + 1}`, rows, depth + 1); }
    } else if (typeof value === 'object') {
      const object: Record<string, Object> = value as Record<string, Object>;
      for (const key of Object.keys(object)) {
        this.flatten(object[key], prefix.length > 0 ? `${prefix} · ${this.label(key)}` : this.label(key), rows, depth + 1);
      }
    } else {
      rows.push(HutaoCloudMetric.of(prefix, String(value)));
    }
  }
}
