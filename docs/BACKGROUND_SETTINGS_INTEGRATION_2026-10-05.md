# Background settings, session lifecycle, and restore integration

## Implemented contracts

- Settings exposes separate, default-off OS background controls for daily notes and sign-in. Each enable action shows an explanation and reviewed UID/region. A single-use consent ticket carries the captured account/session revision to service admission. Cancellation, duplicate callbacks, account changes, page hide, and detach invalidate that ticket.
- The UI distinguishes saved enable intent from accepted OS scheduling, displays bound UID/region and last run/success, and provides explicit refresh, requeue, disable, and noninteractive current-UID sign-in retry. Opening Settings does not initiate sign-in or request notification permission.
- Controls use native 44-vp buttons, theme resources, and their own 840-vp content-width breakpoint. Account identity tokens and credentials are never rendered.
- Runtime initialization is coalesced. Preferences and main database initialize before background storage. The single session invalidation hook is installed before interrupted-backup recovery and account restoration. A successful matching session restore allows reconciliation; ordinary cold start preserves saved intent.
- Logout, deletion, and local replacement reset background tasks; ordinary session restoration/switch/default-role refresh stop and invalidate operational work while retaining its original binding. A failed fence aborts dependent account mutation. Card snapshots are cleared after the successful fence, before account mutation.
- Backup import fully validates the payload before session invalidation. The replacement fence drains before preference capture, account SQL mutation, or vault writes. Successful commit reloads locally; only a confirmed rollback and empty journal release the old session. Uncertain rollback or unfinished committed vault cleanup keeps the recovery journal/barrier.
- Operational background database files are excluded from OS backup with the exact directory `/data/storage/el2/database/entry/rdb/hutao_background/`, including SQLite companions. OS restore initializes and resets background work, then clears card snapshots before completion, without restoring login/network activity.
- Settings application updates now navigate to the registered `pages/UpdatePage`; the old direct release request/unsafe URL opening is removed. Help navigation and game-data cancellation remain intact.

## Verification

- `tests/background-settings-integration.cjs`: production VM and component callbacks, copied-subscriber detach, duplicate/single-use confirmation, switch-away-and-back, page hide/detach, stale async outcomes, read-only activation, lifecycle initialization/failure/retry, invalidation mode/failure, OS restore failure, exact route/resources/backup configuration
- `tests/backup-roundtrip.cjs`: invalid input does not invoke invalidation; failed invalidation writes no SQL/vault data; drain-before-capture ordering; success/rollback; uncertain rollback; committed cleanup journal retention
- `tests/backup-sqlite.cjs`: real SQLite production migration/restore/lossless data preservation and rollback checks
- Existing `tests/game-data-page-integration.cjs`: all 19 cases pass after Settings integration

Native compiler/HAP verification is performed by the integration owner against the final frozen snapshot. Real OS backup/restore, scheduler timing, notifications, account/network behavior, and phone/tablet/2in1 layout remain device-deferred; host mocks do not establish those results. No live accounts, permission dialogs, installer, or external writes were used for these tests.
