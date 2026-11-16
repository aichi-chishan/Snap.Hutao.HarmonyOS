export class RoleProfileIcon {
  id: number = 0;
  icon: string = '';
  unlockType: number = 0;
  unlockParameter: number = 0;
}

/** Public Enka playerInfo.profilePicture fields and the Snap.Metadata icon mapping. */
export class RoleProfilePicture {
  id: number = 0;
  avatarId: number = 0;
  costumeId: number = 0;

  private static positiveId(value: Object | undefined): number {
    return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? value : 0;
  }

  static fromResponse(text: string): RoleProfilePicture | undefined {
    const data: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const player: Record<string, Object> | undefined = data?.['playerInfo'] as Record<string, Object> | undefined;
    const picture: Record<string, Object> | undefined =
      player?.['profilePicture'] as Record<string, Object> | undefined;
    if (picture === undefined || picture === null) { return undefined; }
    const result: RoleProfilePicture = new RoleProfilePicture();
    result.id = RoleProfilePicture.positiveId(picture['id']);
    result.avatarId = RoleProfilePicture.positiveId(picture['avatarId']);
    result.costumeId = RoleProfilePicture.positiveId(picture['costumeId']);
    return result.id > 0 || result.avatarId > 0 || result.costumeId > 0 ? result : undefined;
  }

  static validIcon(icon: string): boolean {
    return /^[A-Za-z0-9_-]+$/.test(icon);
  }

  static readCatalog(text: string): RoleProfileIcon[] {
    const value: Object = JSON.parse(text) as Object;
    if (!Array.isArray(value)) { return []; }
    const icons: RoleProfileIcon[] = [];
    for (const item of value as Object[]) {
      if (item === null || typeof item !== 'object') { continue; }
      const data: Record<string, Object> = item as Record<string, Object>;
      const name: Object = data['Icon'];
      if (typeof name !== 'string' || !RoleProfilePicture.validIcon(name)) { continue; }
      const entry: RoleProfileIcon = new RoleProfileIcon();
      entry.id = RoleProfilePicture.positiveId(data['Id']);
      entry.icon = name;
      entry.unlockType = RoleProfilePicture.positiveId(data['UnlockType']);
      entry.unlockParameter = RoleProfilePicture.positiveId(data['UnlockParameter']);
      if (entry.id > 0) { icons.push(entry); }
    }
    return icons;
  }

  resolveIcon(catalog: RoleProfileIcon[]): string {
    if (this.id > 0) {
      const entry: RoleProfileIcon | undefined = catalog.find((icon: RoleProfileIcon): boolean => icon.id === this.id);
      if (entry !== undefined) { return entry.icon; }
    }
    if (this.avatarId > 0) {
      const entry: RoleProfileIcon | undefined = catalog.find((icon: RoleProfileIcon): boolean =>
        icon.unlockType === 2 && icon.unlockParameter === this.avatarId);
      if (entry !== undefined) { return entry.icon; }
    }
    if (this.costumeId > 0) {
      const entry: RoleProfileIcon | undefined = catalog.find((icon: RoleProfileIcon): boolean =>
        icon.unlockType === 3 && icon.unlockParameter === this.costumeId);
      if (entry !== undefined) { return entry.icon; }
    }
    return '';
  }
}
