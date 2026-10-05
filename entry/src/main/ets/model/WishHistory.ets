/** Offline featured-item history. This never contains a user's personal wishes. */
export enum WishHistoryCategory {
  FiveStarAvatar = 0,
  FourStarAvatar = 1,
  FiveStarWeapon = 2,
  FourStarWeapon = 3
}

/** The destination Wiki page must resolve this ID against its own metadata. */
export interface WishHistoryWikiParams {
  itemId: number;
}

/** Keep each simultaneous pool even when its occurrence counts only once. */
export class WishHistoryPool {
  name: string = '';
  version: string = '';
  order: number = 0;
  type: number = 0;
}

export class WishHistoryOccurrence {
  from: number = 0;
  to: number = 0;
  pools: WishHistoryPool[] = [];
}

export class WishHistoryItem {
  id: number = 0;
  name: string = '';
  icon: string = '';
  iconCategory: string = '';
  category: WishHistoryCategory = WishHistoryCategory.FiveStarAvatar;
  known: boolean = false;
  /** LastTime is the most recent featured event's END, as in Windows CountdownHistory. */
  lastTime: number = 0;
  histories: WishHistoryOccurrence[] = [];
}

export class WishHistorySnapshot {
  items: WishHistoryItem[] = [];
  asOf: number = 0;
  sourceEventCount: number = 0;
  startedEventCount: number = 0;
  ignoredInvalidEvents: number = 0;
  ignoredFutureEvents: number = 0;
  ignoredItemIds: number = 0;
  unknownItemCount: number = 0;
  earliestFrom: number = 0;
  latestTo: number = 0;
  metadataAvailable: boolean = false;
}
