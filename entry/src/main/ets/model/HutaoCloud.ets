/** The cloud passport is independent of every miHoYo/HoYoLAB account. */
export class HutaoCloudSession {
  userName: string = '';
  accessToken: string = '';
  refreshToken: string = '';
  expiresAt: number = 0;
}

export class HutaoCloudEntry {
  uid: string = '';
  count: number = 0;
  excluded: boolean = false;
}

export class HutaoCloudMetric {
  label: string = '';
  value: string = '';
  static of(label: string, value: string): HutaoCloudMetric {
    const row: HutaoCloudMetric = new HutaoCloudMetric();
    row.label = label;
    row.value = value;
    return row;
  }
}

export class HutaoCloudJson {
  static field(object: Record<string, Object>, key: string): Object | undefined {
    const lower: string = key.charAt(0).toLowerCase() + key.substring(1);
    return object[key] ?? object[lower];
  }

  /** System.Text.Json emits Int64 IDs as numbers; preserve the exact decimal digits. */
  static preserveIds(text: string): string {
    return text.replace(/("(?:[Ii]d|100|200|301|302|500|1000|2000)"\s*:\s*)([0-9]+)(?=\s*[,}])/g, '$1"$2"');
  }

  static compareIds(left: string, right: string): number {
    if (left.length !== right.length) { return left.length > right.length ? 1 : -1; }
    return left === right ? 0 : (left > right ? 1 : -1);
  }

  static validId(value: string): boolean {
    return /^[1-9][0-9]{0,18}$/.test(value) &&
      HutaoCloudJson.compareIds(value, '9223372036854775807') <= 0;
  }
}
