/**
 * UserGameRole.ets
 * 绑定游戏角色实体：uid/region/nickname/level，从属某账号。
 */
export class UserGameRole {
  id: number = 0;
  userId: number = 0;
  gameUid: string = '';
  region: string = '';
  nickname: string = '';
  level: number = 0;
  isDefault: boolean = false;
  isChosen: boolean = false;

  static of(uid: string, region: string, nickname: string, level: number): UserGameRole {
    const role: UserGameRole = new UserGameRole();
    role.gameUid = uid;
    role.region = region;
    role.nickname = nickname;
    role.level = level;
    return role;
  }
}
