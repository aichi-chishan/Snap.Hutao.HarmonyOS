/**
 * BackupService.ets
 * 全量本地备份/还原（Windows 云备份的本地等价物，无云依赖）：
 *   账号（展示信息 + Cookie 凭证 + 游戏角色）+ 祈愿全量 + 成就档案 + 关键偏好。
 * 备份文件为明文 JSON 且**包含登录凭证**，仅落用户自选位置，由用户自行保管。
 * 不备份设备指纹类键（device_id/device_fp 等，跨机还原会造成设备身份混乱）。
 */
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { GachaItem } from '../model/GachaItem';
import { AchievementRecord } from '../model/AchievementData';
import { UserRepo } from '../data/repo/UserRepo';
import { GachaRepo } from '../data/repo/GachaRepo';
import { AchievementRepo } from '../data/repo/AchievementRepo';
import { TokenVault } from '../data/local/TokenVault';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from '../common/Logger';

const TAG: string = 'BackupService';
/** 文件标识 + 格式版本（后续字段演进时据此兼容） */
const BACKUP_APP_TAG: string = 'snaphutao-harmonyos-backup';
const BACKUP_VERSION: number = 1;

export class BackupRole {
  gameUid: string = '';
  region: string = '';
  nickname: string = '';
  level: number = 0;
  isDefault: boolean = false;
  isChosen: boolean = false;
}

export class BackupUser {
  mid: string = '';
  aid: string = '';
  displayName: string = '';
  avatar: string = '';
  createdAt: number = 0;
  isSelected: boolean = false;
  /** TokenVault 中的完整 Cookie（含 ltoken/stoken，敏感） */
  cookie: string = '';
  roles: BackupRole[] = [];
}

export class BackupGachaItem {
  gachaId: string = '';
  gachaType: number = 0;
  itemId: number = 0;
  count: number = 0;
  time: string = '';
  name: string = '';
  itemType: string = '';
  rankType: number = 0;
  scheduleId: number = 0;
}

export class BackupGachaSection {
  uid: string = '';
  items: BackupGachaItem[] = [];
}

export class BackupAchievementRecord {
  achId: number = 0;
  current: number = 0;
  timestamp: number = 0;
}

export class BackupAchievementSection {
  name: string = '';
  isSelected: boolean = false;
  records: BackupAchievementRecord[] = [];
}

export class BackupPrefs {
  themeMode: string = '';
  refreshInterval: number = 0;
  autoRefresh: boolean = false;
  ambientStrength: number = 1;
  dailyBgEnabled: boolean = true;
  bgImageType: string = '';
  bgFolderPath: string = '';
  geetestUrl: string = '';
  currentUid: string = '';
}

export class BackupFile {
  app: string = BACKUP_APP_TAG;
  version: number = BACKUP_VERSION;
  exportedAt: number = 0;
  users: BackupUser[] = [];
  gacha: BackupGachaSection[] = [];
  achievements: BackupAchievementSection[] = [];
  prefs: BackupPrefs = new BackupPrefs();
}

export class BackupResult {
  ok: boolean = false;
  message: string = '';
}

export class BackupService {
  private static instance: BackupService = new BackupService();

  static getInstance(): BackupService {
    return BackupService.instance;
  }

  /** 汇总全部本地数据为备份 JSON（含 Cookie，敏感） */
  async buildBackupJson(): Promise<string> {
    const file: BackupFile = new BackupFile();
    file.exportedAt = Math.floor(Date.now() / 1000);

    // ---- 账号 ----
    const users: User[] = await UserRepo.getAllUsers();
    for (const u of users) {
      const bu: BackupUser = new BackupUser();
      bu.mid = u.mid;
      bu.aid = u.aid;
      bu.displayName = u.displayName;
      bu.avatar = u.avatar;
      bu.createdAt = u.createdAt;
      bu.isSelected = u.isSelected;
      try {
        bu.cookie = await TokenVault.loadCookie(u.id);
      } catch (e) {
        Logger.warn(TAG, `load cookie user=${u.id} fail: ${(e as Error).message}`);
      }
      const roles: UserGameRole[] = await UserRepo.getRolesByUserId(u.id);
      for (const r of roles) {
        const br: BackupRole = new BackupRole();
        br.gameUid = r.gameUid;
        br.region = r.region;
        br.nickname = r.nickname;
        br.level = r.level;
        br.isDefault = r.isDefault;
        br.isChosen = r.isChosen;
        bu.roles.push(br);
      }
      file.users.push(bu);
    }

    // ---- 祈愿 ----
    const gArchives = await GachaRepo.getAllArchives();
    for (const a of gArchives) {
      const section: BackupGachaSection = new BackupGachaSection();
      section.uid = a.uid;
      const items: GachaItem[] = await GachaRepo.getItemsByArchive(a.id);
      for (const it of items) {
        const bi: BackupGachaItem = new BackupGachaItem();
        bi.gachaId = it.gachaId;
        bi.gachaType = it.gachaType;
        bi.itemId = it.itemId;
        bi.count = it.count;
        bi.time = it.time;
        bi.name = it.name;
        bi.itemType = it.itemType;
        bi.rankType = it.rankType;
        bi.scheduleId = it.scheduleId;
        section.items.push(bi);
      }
      file.gacha.push(section);
    }

    // ---- 成就 ----
    const aArchives = await AchievementRepo.getAllArchives();
    for (const a of aArchives) {
      const section: BackupAchievementSection = new BackupAchievementSection();
      section.name = a.name;
      section.isSelected = a.isSelected;
      const records: Map<number, AchievementRecord> = await AchievementRepo.getRecords(a.id);
      records.forEach((rec: AchievementRecord) => {
        const br: BackupAchievementRecord = new BackupAchievementRecord();
        br.achId = rec.achId;
        br.current = rec.current;
        br.timestamp = rec.timestamp;
        section.records.push(br);
      });
      file.achievements.push(section);
    }

    // ---- 偏好（不含设备指纹）----
    file.prefs.themeMode = PreferencesStore.getThemeMode();
    file.prefs.refreshInterval = PreferencesStore.getRefreshIntervalMinutes();
    file.prefs.autoRefresh = PreferencesStore.getAutoRefreshEnabled();
    file.prefs.ambientStrength = PreferencesStore.getAmbientStrength();
    file.prefs.dailyBgEnabled = PreferencesStore.getDailyBgEnabled();
    file.prefs.bgImageType = PreferencesStore.getBackgroundImageType();
    file.prefs.bgFolderPath = PreferencesStore.getBackgroundFolderPath();
    file.prefs.geetestUrl = RiskVerify_getCustomUrl();
    file.prefs.currentUid = PreferencesStore.getCurrentUid();

    Logger.info(TAG, `backup built: users=${file.users.length} gacha=${file.gacha.length} ach=${file.achievements.length}`);
    return JSON.stringify(file, null, 2);
  }

  /**
   * 从备份 JSON 还原（**覆盖式**：先清空现有账号/祈愿/成就，再写入备份内容）。
   * 还原后建议重启应用使主题/背景等偏好完全生效。
   */
  async restoreFromText(text: string): Promise<BackupResult> {
    const result: BackupResult = new BackupResult();
    let root: Record<string, Object>;
    try {
      root = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      result.message = 'JSON 解析失败';
      return result;
    }
    const tag: Object | undefined = root['app'];
    if (tag === undefined || String(tag) !== BACKUP_APP_TAG) {
      result.message = '不是本应用的备份文件';
      return result;
    }

    // ---- 清空现有数据（账号删除会级联 Cookie）----
    const oldUsers: User[] = await UserRepo.getAllUsers();
    for (const u of oldUsers) {
      await UserRepo.deleteUser(u.id);
    }
    const oldGacha = await GachaRepo.getAllArchives();
    for (const a of oldGacha) {
      await GachaRepo.deleteArchive(a.id);
    }
    const oldAch = await AchievementRepo.getAllArchives();
    for (const a of oldAch) {
      await AchievementRepo.deleteArchive(a.id);
    }

    // ---- 账号 ----
    const usersRaw: Object | undefined = root['users'];
    const users: Object[] = usersRaw !== undefined && usersRaw !== null ? usersRaw as Object[] : [];
    let selectedNewId: number = 0;
    let selectedDefaultUid: string = '';
    let restoredUsers: number = 0;
    for (const raw of users) {
      const o: Record<string, Object> = raw as Record<string, Object>;
      const bu: BackupUser = new BackupUser();
      bu.mid = String(o['mid'] ?? '');
      bu.aid = String(o['aid'] ?? '');
      bu.displayName = String(o['displayName'] ?? '');
      bu.avatar = String(o['avatar'] ?? '');
      bu.createdAt = Number(o['createdAt'] ?? 0);
      bu.isSelected = (o['isSelected'] as boolean) ?? false;
      bu.cookie = String(o['cookie'] ?? '');
      const u: User = new User();
      u.mid = bu.mid;
      u.aid = bu.aid;
      u.displayName = bu.displayName;
      u.avatar = bu.avatar;
      u.createdAt = bu.createdAt;
      const newId: number = await UserRepo.insertUser(u);
      restoredUsers++;
      if (bu.cookie.length > 0) {
        await TokenVault.saveCookie(newId, bu.cookie);
      }
      const rolesRaw: Object | undefined = o['roles'];
      const roles: Object[] = rolesRaw !== undefined && rolesRaw !== null ? rolesRaw as Object[] : [];
      if (roles.length > 0) {
        const mapped: UserGameRole[] = [];
        for (const rr of roles) {
          const ro: Record<string, Object> = rr as Record<string, Object>;
          const role: UserGameRole = new UserGameRole();
          role.gameUid = String(ro['gameUid'] ?? '');
          role.region = String(ro['region'] ?? '');
          role.nickname = String(ro['nickname'] ?? '');
          role.level = Number(ro['level'] ?? 0);
          role.isDefault = (ro['isDefault'] as boolean) ?? false;
          role.isChosen = (ro['isChosen'] as boolean) ?? false;
          mapped.push(role);
        }
        await UserRepo.upsertRoles(newId, mapped);
      }
      if (bu.isSelected) {
        selectedNewId = newId;
        for (const r of bu.roles) {
          if (r.isDefault) {
            selectedDefaultUid = r.gameUid;
          }
        }
      }
    }
    if (selectedNewId > 0) {
      await UserRepo.selectUser(selectedNewId);
      if (selectedDefaultUid.length > 0) {
        PreferencesStore.setCurrentUid(selectedDefaultUid);
      }
    }

    // ---- 祈愿 ----
    const gachaRaw: Object | undefined = root['gacha'];
    const gacha: Object[] = gachaRaw !== undefined && gachaRaw !== null ? gachaRaw as Object[] : [];
    let restoredGacha: number = 0;
    for (const raw of gacha) {
      const o: Record<string, Object> = raw as Record<string, Object>;
      const uid: string = String(o['uid'] ?? '');
      if (uid.length === 0) {
        continue;
      }
      const archive = await GachaRepo.getOrCreateArchive(uid);
      const items: GachaItem[] = [];
      const listRaw: Object | undefined = o['items'];
      const list: Object[] = listRaw !== undefined && listRaw !== null ? listRaw as Object[] : [];
      for (const ir of list) {
        const io: Record<string, Object> = ir as Record<string, Object>;
        const it: GachaItem = new GachaItem();
        it.archiveId = archive.id;
        it.gachaId = String(io['gachaId'] ?? '');
        it.gachaType = Number(io['gachaType'] ?? 0);
        it.itemId = Number(io['itemId'] ?? 0);
        it.count = Number(io['count'] ?? 1);
        it.time = String(io['time'] ?? '');
        it.name = String(io['name'] ?? '');
        it.itemType = String(io['itemType'] ?? '');
        it.rankType = Number(io['rankType'] ?? 0);
        it.scheduleId = Number(io['scheduleId'] ?? 0);
        if (it.gachaId.length > 0) {
          items.push(it);
        }
      }
      if (items.length > 0) {
        await GachaRepo.insertItems(items);
        restoredGacha += items.length;
      }
    }

    // ---- 成就 ----
    const achRaw: Object | undefined = root['achievements'];
    const ach: Object[] = achRaw !== undefined && achRaw !== null ? achRaw as Object[] : [];
    let restoredAch: number = 0;
    for (const raw of ach) {
      const o: Record<string, Object> = raw as Record<string, Object>;
      const name: string = String(o['name'] ?? '');
      if (name.length === 0) {
        continue;
      }
      const archive = await AchievementRepo.createArchive(name);
      const records: AchievementRecord[] = [];
      const listRaw: Object | undefined = o['records'];
      const list: Object[] = listRaw !== undefined && listRaw !== null ? listRaw as Object[] : [];
      for (const rr of list) {
        const ro: Record<string, Object> = rr as Record<string, Object>;
        const rec: AchievementRecord = new AchievementRecord();
        rec.archiveId = archive.id;
        rec.achId = Number(ro['achId'] ?? 0);
        rec.current = Number(ro['current'] ?? 1);
        rec.timestamp = Number(ro['timestamp'] ?? 0);
        if (rec.achId > 0) {
          records.push(rec);
        }
      }
      if (records.length > 0) {
        await AchievementRepo.replaceRecords(archive.id, records);
        restoredAch += records.length;
      }
      if ((o['isSelected'] as boolean) ?? false) {
        await AchievementRepo.selectArchive(archive.id);
      }
    }

    // ---- 偏好 ----
    const prefsRaw: Object | undefined = root['prefs'];
    if (prefsRaw !== undefined && prefsRaw !== null) {
      const p: Record<string, Object> = prefsRaw as Record<string, Object>;
      const theme: string = String(p['themeMode'] ?? '');
      if (theme.length > 0) {
        PreferencesStore.setThemeMode(theme);
      }
      const interval: number = Number(p['refreshInterval'] ?? 0);
      if (interval > 0) {
        PreferencesStore.setRefreshIntervalMinutes(interval);
      }
      const auto: boolean | undefined = p['autoRefresh'] as boolean | undefined;
      if (auto !== undefined) {
        PreferencesStore.setAutoRefreshEnabled(auto);
      }
      const ambient: number = Number(p['ambientStrength'] ?? -1);
      if (ambient >= 0) {
        PreferencesStore.setAmbientStrength(ambient);
      }
      const dailyBg: boolean | undefined = p['dailyBgEnabled'] as boolean | undefined;
      if (dailyBg !== undefined) {
        PreferencesStore.setDailyBgEnabled(dailyBg);
      }
      const bgType: string = String(p['bgImageType'] ?? '');
      if (bgType.length > 0) {
        PreferencesStore.setBackgroundImageType(bgType);
      }
      const bgFolder: string = String(p['bgFolderPath'] ?? '');
      if (bgFolder.length > 0) {
        PreferencesStore.setBackgroundFolderPath(bgFolder);
      }
      const geetest: string = String(p['geetestUrl'] ?? '');
      PreferencesStore.setString(PreferencesStore.KEY_GEETEST_CUSTOM_URL, geetest);
    }

    result.ok = true;
    result.message = `还原完成：账号 ${restoredUsers}、祈愿 ${restoredGacha} 条、成就 ${restoredAch} 条，建议重启应用`;
    Logger.info(TAG, `restore done users=${restoredUsers} gacha=${restoredGacha} ach=${restoredAch}`);
    return result;
  }
}

/** 极验自定义接口偏好读取（独立函数避免循环依赖服务单例） */
function RiskVerify_getCustomUrl(): string {
  try {
    return PreferencesStore.getString(PreferencesStore.KEY_GEETEST_CUSTOM_URL, '');
  } catch (e) {
    return '';
  }
}
