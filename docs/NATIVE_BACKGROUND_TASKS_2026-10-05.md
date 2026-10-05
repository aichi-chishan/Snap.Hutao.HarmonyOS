# F19/F20 native deferred tasks (API 24 minimum, API 26 target)

## Feasible scope and limits

Two independent, default-off switches opt into an OS WorkScheduler task for the account and UID selected when enabled:

- Daily note: fetch one owned UID's current note and refresh its local cache and desktop form snapshot
- Sign-in: query server sign-in state, then make at most one sign-in request when eligible; check again on a later run after an uncertain result

This checkpoint does **not** claim precise intervals, a midnight trigger, guaranteed daily completion, tracked-UID coverage, or execution after the user/system prohibits background activity. Native refresh does not invoke webhooks or request notification permission. Existing foreground notification/reminder behavior is separate.

Official sources checked on 2026-10-05:

- Huawei's supplied API 26 SDK `@ohos.resourceschedule.workScheduler.d.ts`: WorkInfo/startWork/stopWork are API 9, persisted registration can survive system restart; earliestStartTime is API 22. startWork acceptance means queuing, not execution
- Huawei's supplied SDK `@ohos.WorkSchedulerExtensionAbility.d.ts`: extension callbacks are API 9, extension context is API 10, onWorkStop occurs on cancellation or the two-minute timeout
- [Official OpenHarmony Work Scheduler](https://github.com/openharmony/resourceschedule_work_scheduler): requested repetition is at least 20 minutes, maximum execution is 120 seconds; system activity groups may restrict execution to much longer intervals or prohibit it. These implementation constraints support a best-effort description, not a delivery guarantee
- Huawei online reference pages were attempted but timed out; installed official SDK declarations were read directly. No non-public/privileged API is used

Work is network-constrained and requests a minimum 20-minute repetition (sign-in requests 30 minutes), with an 80-second app budget. An API 24 device does not need an API 26 feature gate for these APIs. Work registration adds no permission and no continuous/foreground-service background mode.

## Ownership and persistence

`BackgroundTaskRepo` uses the separate, version-1 `snap_hutao_background.db` operational RDB, not the portable backup table list. It uses API-11 `StoreConfig.customDir: 'hutao_background'`, placing all files beneath the verified entry-module RDB subdirectory. Initialization is transactional, operation retention is limited to 128 inactive rows, and no credentials are copied into it. Bindings contain the local account identity, owned UID and region; cookies remain in the existing secure vault.

OS WorkInfo contains fixed numeric feature IDs and one numeric configuration epoch only. No UID, account identifier or credential is placed in an OS work identifier, parameters, Want or new diagnostic log. Three existing downstream request/cache logs were made identifier-free.

Each run re-reads the selected account, identity (id/created-at/region/account identity), persisted default UID and owned role before and after network work. It never restores or switches the current session. A selection mismatch fails closed; it never silently rebinds consent to another account.

Durable SQL compare-and-set leases fence duplicate callbacks/processes and late completions. Per-account/UID/region sign-in state uses fixed server-region calendar days; already-signed is confirmed through the server. Failure cooldown is ten minutes (actual OS opportunities can be much less frequent). Captcha, missing credentials and device/server-date mismatch block that server day until an explicit manual retry; the next server day may recheck without opening UI; no risk UI, token exchange, login UI or permission request can execute from native work.

Cancellation prevents subsequent steps and local success-state publication. A request already sent to the server cannot be recalled; a later run queries server sign-in state before sending another sign-in request. Daily-note persistence checks the guard after its internal reads and inside an immediate main-DB transaction before writing and before commit; cancellation after a dispatched write rolls back. This also serializes publication against account deletion/data replacement.

## OS backup exclusion

The parent excludes the entire directory `/data/storage/el2/database/entry/rdb/hutao_background/` through the `excludes` string array in `backup_config.json`. A directory exclusion also covers `-wal`, `-shm`, double-write/recovery files and future companions without guessing suffix patterns. `onRestore` still resets the operational scheduler as defense in depth. Package-resource inspection proves the stanza was shipped; actual OS backup filtering remains device-deferred.

Evidence: the official [backup profile guide](https://github.com/openharmony/docs/blob/master/en/application-dev/file-management/app-file-backup-extension.md) defines directory excludes and default EL2 database inclusion. SDK `StoreConfig.customDir` (API 11) defines the directory as `context.databaseDir + '/rdb/' + customDir`. Huawei's [RDB file-descriptor examples](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-stability-fdleak-fault-mode-overreview) show the entry module path and additional double-write files. Application runtime code continues to use Context and StoreConfig, not hardcoded filesystem access.

## Parent integration contract

- `BackgroundTaskService.init(context)` initializes only local runtime; `reconcile()` registers or removes schedules after validating binding; neither makes account network calls
- `setEnabled(kind, enabled)` records the explicit user's binding consent; the OS may reject registration
- `getState(kind)` exposes saved `enabled` intent, separate `queued` OS acceptance, status/message, binding, last attempted run and last success
- `retryBlocked(kind)` clears the bound manual block and requeues; it does not perform the task immediately or open UI
- `stopAndInvalidate(): Promise<boolean>` is an awaited pre-session-transition fence. It stops native work, advances generations and invalidates leases while **preserving the original binding/opt-in and completed-day/cooldown/manual history**. Matching cold-start session restoration may then reconcile it
- `reset()` additionally disables both tasks and clears bindings/history. Portable data restoration/reset must call it after validation and before applying replacement data. OS BackupExtensionAbility restoration must also reset operational jobs (or exclude the DB using a verified backup policy)
- `invalidateAccount(userId): Promise<boolean>` disables matching bound tasks and deletes that account's operational ledger

The parent must await durable invalidation before account/UID replacement, logout/removal or restore writes. A `false` result is a blocker, not proof that fencing succeeded. Register the ownership service's pre-transition invalidation hook to prevent A→B→A races that happen entirely between two database reads. Ordinary startup session restoration must use the preserving fence, not reset consent every launch.

## Widget hardening

`DailyNoteFormExtensionAbility` no longer restores the global session or enters token-chain completion. Scheduled `onUpdateForm` is cached-only. An explicit refresh tap uses `BackgroundTaskService.refreshWidget()` as a bounded 15-second, explicit-owner read-only operation; it shares per-UID leases and operational epochs but does not enable periodic work. Duplicate taps, removal/re-add with a reused form ID, late responses and oversized events are fenced. Removed/completed IDs are deleted from the generation map; a monotonic instance token prevents old callbacks from matching a reused ID.

Snapshot files now carry local-only owner/UID/epoch metadata. Legacy/unbound, stale-epoch and wrong-owner snapshots render placeholders. The metadata is never sent in form display payloads. Foreground and native publication check guards around asynchronous form operations; a late old platform update is followed by a current safe snapshot. `clearCardSnapshot()` durably blanks the snapshot and updates existing forms, and its failure can abort a dependent session/data transition. These APIs never request notification permission. The older unused `refreshForCard` bypass was removed, and noninteractive tracked refresh cannot invoke token completion/auth retry.

## Verification

`tests/background-tasks.cjs` executes the production model, repository, scheduler, automatic sign-in, noninteractive daily-note method and extension with mocked platform/network boundaries and real SQLite. Covered cases include:

- Default-off consent, no automatic registration on initialization, duplicate reconciliation and opaque work parameters
- Atomic duplicate callback/foreground-auto/native sign-in exclusion, expired process leases, old-generation completion and persisted old work rejection
- Fixed-region midnight rollover, already-signed server truth, network cooldown and device-clock rollback
- Per-server-day captcha and login/manual blocks, typed explicit startup retry, pending-backup-journal blocking, malformed sign-state rejection, registration rejection and unavailable capability
- Disable/reset during a pending request, bounded timeout with late network completion, account/UID removal, and preserving cold-start intent
- Extension stop before runtime initialization completes, stale stop callbacks, zero interactive authentication/verification/permission/webhook calls

`tests/background-daily-persistence.cjs` covers cancellation after repository reads and after a dispatched transaction write, including rollback. `tests/runtime-init.cjs` covers concurrent opening, failure retry and no partial publication. Widget/cache tests also cover no periodic/network work on system form update, snapshot binding, late publication correction, failed snapshot writes and remove/re-add/oversize events.

Also rerun account transport and existing challenge/daily-note regression suites. These are host tests; native compilation and aggregate checks must be recorded by the parent for its final frozen snapshot. Actual OS scheduling, reboot/force-stop/power restrictions and real account behavior remain deferred to the user-authorized device/account checkpoint.
