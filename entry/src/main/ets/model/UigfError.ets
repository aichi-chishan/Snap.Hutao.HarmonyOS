/** Only explicit application diagnostics may cross the worker boundary; never SDK/provider errors. */
export class UigfError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UigfError';
  }
}
