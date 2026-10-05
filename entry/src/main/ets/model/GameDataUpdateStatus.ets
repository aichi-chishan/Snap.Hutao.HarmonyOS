/** Copyable state for one foreground update. settled=false means ownership is still draining. */
export class GameDataUpdateStatus {
  id: number = 0;
  state: string = 'idle';
  done: number = 0;
  total: number = 0;
  current: string = '';
  bytes: number = 0;
  activeFiles: number = 0;
  error: string = '';
  canCancel: boolean = false;
  settled: boolean = true;
}
