import { HutaoCloudClient } from '../data/network/HutaoCloudClient';
import { HutaoCloudVault } from '../data/local/HutaoCloudVault';
import { HutaoCloudSession, HutaoCloudEntry, HutaoCloudMetric, HutaoCloudJson } from '../model/HutaoCloud';
import { HutaoCloudGacha } from '../model/HutaoCloudGacha';
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaArchive } from '../model/GachaArchive';
import { GachaItem } from '../model/GachaItem';
import { RegionUtil } from '../common/Constants';
import { WikiMetaService, WikiAvatarMeta, WikiWeaponMeta } from './WikiMetaService';

export class HutaoCloudService {
  private static instance: HutaoCloudService = new HutaoCloudService();
  private session: HutaoCloudSession = new HutaoCloudSession();
  private initialized: boolean = false;

  static getInstance(): HutaoCloudService { return HutaoCloudService.instance; }
  getUserName(): string { return this.session.userName; }
  isLoggedIn(): boolean { return this.session.refreshToken.length > 0; }

  async initialize(): Promise<void> {
    if (!this.initialized) {
      this.session = await HutaoCloudVault.load();
      this.initialized = true;
    }
  }

  private async accept(data: Object, userName: string): Promise<void> {
    const raw: Record<string, Object> = data as Record<string, Object>;
    const next: HutaoCloudSession = new HutaoCloudSession();
    next.userName = userName;
    next.accessToken = String(HutaoCloudJson.field(raw, 'AccessToken') ?? '');
    next.refreshToken = String(HutaoCloudJson.field(raw, 'RefreshToken') ?? '');
    next.expiresAt = Date.now() + Number(HutaoCloudJson.field(raw, 'ExpiresIn') ?? 0) * 1000;
    if (next.accessToken.length === 0 || next.refreshToken.length === 0 || !Number.isFinite(next.expiresAt) || next.expiresAt <= Date.now()) {
      throw new Error('通行证返回了无效登录凭据');
    }
    await HutaoCloudVault.save(next);
    this.session = next;
    this.initialized = true;
  }

  private async accessToken(): Promise<string> {
    await this.initialize();
    if (!this.isLoggedIn()) { throw new Error('请先登录胡桃通行证'); }
    if (this.session.expiresAt <= Date.now() + 60000) {
      const body: Record<string, string> = { 'RefreshToken': await HutaoCloudClient.encrypt(this.session.refreshToken) };
      const data: Object = await HutaoCloudClient.request('/Passport/v2/RefreshToken', JSON.stringify(body));
      await this.accept(data, this.session.userName);
    }
    return this.session.accessToken;
  }

  async verify(email: string, kind: string): Promise<void> {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { throw new Error('请输入有效邮箱'); }
    const body: Record<string, Object> = { 'UserName': await HutaoCloudClient.encrypt(email) };
    if (kind === 'reset') { body['IsResetPassword'] = true; }
    if (kind === 'cancel') { body['IsCancelRegistration'] = true; }
    if (kind === 'oldEmail') { body['IsResetUserName'] = true; }
    if (kind === 'newEmail') { body['IsResetUserNameNew'] = true; }
    await HutaoCloudClient.request('/Passport/v2/Verify', JSON.stringify(body));
  }

  async authenticate(email: string, password: string, code: string, mode: string): Promise<void> {
    if (email.trim().length === 0 || password.length === 0) { throw new Error('请填写邮箱和密码'); }
    if (mode !== 'login' && (password.length < 8 || code.trim().length === 0)) {
      throw new Error('请填写验证码，新密码至少 8 位');
    }
    const body: Record<string, string> = {
      'UserName': await HutaoCloudClient.encrypt(email.trim()),
      'Password': await HutaoCloudClient.encrypt(password),
    };
    let path: string = '/Passport/v2/Login';
    if (mode === 'register' || mode === 'reset') {
      body['VerifyCode'] = await HutaoCloudClient.encrypt(code.trim());
      path = mode === 'register' ? '/Passport/v2/Register' : '/Passport/v2/ResetPassword';
    }
    await this.accept(await HutaoCloudClient.request(path, JSON.stringify(body)), email.trim());
  }

  async userInfo(): Promise<HutaoCloudMetric[]> {
    const raw: Record<string, Object> = await HutaoCloudClient.request('/Passport/v2/UserInfo', '', await this.accessToken()) as Record<string, Object>;
    return [
      HutaoCloudMetric.of('邮箱', String(HutaoCloudJson.field(raw, 'UserName') ?? this.session.userName)),
      HutaoCloudMetric.of('祈愿云服务到期', String(HutaoCloudJson.field(raw, 'GachaLogExpireAt') ?? '服务端未返回')),
      HutaoCloudMetric.of('CDN 服务到期', String(HutaoCloudJson.field(raw, 'CdnExpireAt') ?? '服务端未返回')),
    ];
  }

  async logout(revokeAll: boolean = false): Promise<void> {
    const token: string = await this.accessToken();
    const body: Record<string, string> = { 'DeviceId': await HutaoCloudClient.encrypt(HutaoCloudClient.deviceId()) };
    await HutaoCloudClient.request(revokeAll ? '/Passport/v2/RevokeAllTokens' : '/Passport/v2/RevokeToken',
      revokeAll ? '{}' : JSON.stringify(body), token);
    await this.forgetLocal();
  }

  async forgetLocal(): Promise<void> {
    await HutaoCloudVault.clear();
    this.session = new HutaoCloudSession();
  }

  async unregister(email: string, password: string, code: string): Promise<void> {
    if (password.length === 0 || code.trim().length === 0) { throw new Error('请填写密码和注销验证码'); }
    const body: Record<string, string> = {
      'UserName': await HutaoCloudClient.encrypt(email), 'Password': await HutaoCloudClient.encrypt(password),
      'VerifyCode': await HutaoCloudClient.encrypt(code),
    };
    await HutaoCloudClient.request('/Passport/v2/Cancel', JSON.stringify(body), await this.accessToken());
    await this.forgetLocal();
  }

  async resetEmail(oldCode: string, newEmail: string, newCode: string): Promise<void> {
    if (oldCode.length === 0 || newEmail.length === 0 || newCode.length === 0) { throw new Error('请填写新邮箱及两个邮箱的验证码'); }
    const body: Record<string, string> = {
      'UserName': await HutaoCloudClient.encrypt(this.session.userName),
      'NewUserName': await HutaoCloudClient.encrypt(newEmail),
      'VerifyCode': await HutaoCloudClient.encrypt(oldCode), 'NewVerifyCode': await HutaoCloudClient.encrypt(newCode),
    };
    await this.accept(await HutaoCloudClient.request('/Passport/v2/ResetUsername', JSON.stringify(body)), newEmail);
  }

  async redeem(code: string): Promise<void> {
    if (code.trim().length === 0) { throw new Error('请输入兑换码'); }
    const body: Record<string, string> = { 'code': code.trim() };
    await HutaoCloudClient.request('/Redeem/Use', JSON.stringify(body), await this.accessToken());
  }

  async entries(): Promise<HutaoCloudEntry[]> {
    const raw: Object = await HutaoCloudClient.request('/GachaLog/Entries', '', await this.accessToken());
    if (!Array.isArray(raw)) { throw new Error('云存档列表结构无效'); }
    const rows: HutaoCloudEntry[] = [];
    for (const value of raw as Object[]) {
      const object: Record<string, Object> = value as Record<string, Object>;
      const row: HutaoCloudEntry = new HutaoCloudEntry();
      row.uid = String(HutaoCloudJson.field(object, 'Uid') ?? '');
      row.count = Number(HutaoCloudJson.field(object, 'ItemCount') ?? 0);
      row.excluded = Boolean(HutaoCloudJson.field(object, 'Excluded') ?? false);
      if (RegionUtil.isValidUid(row.uid)) { rows.push(row); }
    }
    return rows;
  }

  async localArchives(): Promise<GachaArchive[]> { return GachaRepo.getAllArchives(); }

  private validateUid(uid: string): void {
    if (!RegionUtil.isValidUid(uid)) { throw new Error('请输入有效游戏 UID'); }
  }

  private async localItems(uid: string): Promise<GachaItem[]> {
    const archives: GachaArchive[] = await GachaRepo.getAllArchives();
    for (const archive of archives) { if (archive.uid === uid) { return GachaRepo.getItemsByArchive(archive.id); } }
    return [];
  }

  async upload(uid: string): Promise<number> {
    this.validateUid(uid);
    const items: GachaItem[] = await this.localItems(uid);
    if (items.length === 0) { throw new Error('此 UID 没有本地祈愿记录'); }
    const token: string = await this.accessToken();
    const endIds: Record<string, Object> = await HutaoCloudClient.request(`/GachaLog/EndIds?Uid=${uid}`, '', token) as Record<string, Object>;
    const pending: GachaItem[] = [];
    for (const item of items) {
      const end: string = String(endIds[String(HutaoCloudGacha.queryType(item.gachaType))] ?? '0');
      if (HutaoCloudJson.compareIds(item.gachaId, end) > 0) { pending.push(item); }
    }
    if (pending.length > 0) {
      await HutaoCloudClient.request('/GachaLog/Upload', HutaoCloudGacha.uploadBody(uid, pending), token);
    }
    return pending.length;
  }

  async retrieve(uid: string): Promise<number> {
    this.validateUid(uid);
    const local: GachaItem[] = await this.localItems(uid);
    const raw: Object = await HutaoCloudClient.request('/GachaLog/Retrieve', HutaoCloudGacha.retrieveBody(uid, local), await this.accessToken());
    if (!Array.isArray(raw)) { throw new Error('云祈愿列表结构无效，未写入本地'); }
    const known: Set<string> = new Set();
    for (const item of local) { known.add(`${item.gachaType}:${item.gachaId}`); }
    const pending: GachaItem[] = [];
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    for (const value of raw as Object[]) {
      const item: GachaItem = HutaoCloudGacha.parseItem(value, uid);
      const key: string = `${item.gachaType}:${item.gachaId}`;
      if (known.has(key)) { continue; }
      const localMatch: GachaItem | undefined = local.find((saved: GachaItem) => saved.itemId === item.itemId);
      const avatar: WikiAvatarMeta | undefined = avatars.find((entry: WikiAvatarMeta) => entry.id === item.itemId || entry.id === item.itemId + 10000000);
      const weapon: WikiWeaponMeta | undefined = weapons.find((entry: WikiWeaponMeta) => entry.id === item.itemId);
      if (localMatch !== undefined) {
        item.name = localMatch.name; item.rankType = localMatch.rankType; item.itemType = localMatch.itemType;
      } else if (avatar !== undefined) {
        item.name = avatar.name; item.rankType = avatar.quality === 5 || avatar.quality === 105 ? 5 : 4; item.itemType = '角色';
      } else if (weapon !== undefined) {
        item.name = weapon.name; item.rankType = weapon.rankLevel; item.itemType = '武器';
      } else {
        throw new Error(`缺少物品 ${item.itemId} 的名称与品质数据，请更新游戏数据后重试；本地记录未变更`);
      }
      known.add(key); pending.push(item);
    }
    if (pending.length === 0) { return 0; }
    const archive: GachaArchive = await GachaRepo.getOrCreateArchive(uid);
    for (const item of pending) { item.archiveId = archive.id; }
    return GachaRepo.insertItems(pending);
  }

  async deleteArchive(uid: string): Promise<void> {
    this.validateUid(uid);
    await HutaoCloudClient.request(`/GachaLog/Delete?Uid=${uid}`, '', await this.accessToken());
  }

  async statistics(kind: string, last: boolean = false): Promise<Object> {
    const paths: Record<string, string> = {
      'overview': '/Statistics/Overview', 'attendance': '/Statistics/Avatar/AttendanceRate',
      'utilization': '/Statistics/Avatar/UtilizationRate', 'holding': '/Statistics/Avatar/HoldingRate',
      'collocation': '/Statistics/Avatar/AvatarCollocation', 'weapon': '/Statistics/Weapon/WeaponCollocation',
      'team': '/Statistics/Team/Combination', 'roleCombat': '/RoleCombat/Statistics',
      'events': '/GachaLog/Statistics/CurrentEventStatistics',
      'avatarDistribution': '/GachaLog/Statistics/Distribution/AvatarEvent',
      'weaponDistribution': '/GachaLog/Statistics/Distribution/WeaponEvent',
      'standardDistribution': '/GachaLog/Statistics/Distribution/Standard',
      'chronicledDistribution': '/GachaLog/Statistics/Distribution/Chronicled',
      'beyondStandardDistribution': '/GachaLog/Statistics/Distribution/BeyondStandard',
      'beyondEventDistribution': '/GachaLog/Statistics/Distribution/BeyondEvent',
    };
    const path: string = paths[kind];
    if (path === undefined) { throw new Error('未知统计类型'); }
    const token: string = path.startsWith('/GachaLog/') ? await this.accessToken() : '';
    return HutaoCloudClient.request(path + (path.startsWith('/GachaLog/') ? '' : `?Last=${last}`), '', token);
  }
}
