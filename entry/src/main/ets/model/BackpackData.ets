/** Offline backpack records. UIIF v1.0 has no standard UID, instance ID or lock fields. */
export enum BackpackCategory {
  Weapon = 0, Reliquary = 1, UpgradeItem = 2, Food = 3, Material = 4,
  Gadget = 5, Quest = 6, PreciousItem = 7, Furniture = 8, Unknown = 9,
}

export class BackpackArchive {
  id: number = 0;
  name: string = '';
  uid: string = '';
  isSelected: boolean = false;
  createdAt: number = 0;
  updatedAt: number = 0;
  source: string = '';
  documentJson: string = '{"info":{"uiif_version":"v1.0"},"list":[]}';
}

export class BackpackItem {
  archiveId: number = 0;
  /** Local identity, never a rounded number or the shared itemId of duplicate equipment. */
  instanceId: string = '';
  itemId: number = 0;
  kind: string = '';
  category: BackpackCategory = BackpackCategory.Unknown;
  rawJson: string = '';
  guid: string = '';
  count: number = 1;
  level: number = 0;
  promoteLevel: number = 0;
  affixMap: Map<number, number> = new Map<number, number>();
  mainPropId: number = 0;
  appendPropIds: number[] = [];
  isLocked: boolean | undefined = undefined;
  isMarked: boolean | undefined = undefined;
  name: string = '';
  icon: string = '';
  iconCategory: string = 'ItemIcon';
  rarity: number = 0;
}

export class BackpackImport {
  documentJson: string = '';
  source: string = '';
  uid: string = '';
  items: BackpackItem[] = [];
  weaponCount: number = 0;
  reliquaryCount: number = 0;
  materialCount: number = 0;
  furnitureCount: number = 0;
  /** UI-only ownership fence. Never populated from an imported file or exported as UIIF. */
  targetArchiveId: number = 0;
  targetUid: string = '';
  targetUpdatedAt: number = 0;
}

export class BackpackFilter {
  keyword: string = '';
  category: number = -1;
  lockedOnly: boolean = false;
  sort: string = 'id';
}

export class BackpackManualInput {
  itemId: string = '';
  kind: string = 'material';
  count: string = '1';
  level: string = '1';
  promoteLevel: string = '0';
  /** UIIF affixMap values are zero based: 0 means refinement 1. */
  affixId: string = '';
  affixLevel: string = '0';
  mainPropId: string = '';
  appendPropIds: string = '';
  category: BackpackCategory = BackpackCategory.Unknown;
}
