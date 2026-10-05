# Account session ownership hardening

## Contract

`UserService.sessionRevision()` is a monotonic in-process ownership generation. Capture it before an asynchronous operation and reject publication when it changes, even if the selected account ID or `User` object appears unchanged after switching away and back.

Restore, local reload, login, switch, logout, delete, default-UID changes and selected-role refresh increment the generation synchronously before any await. Completing or rejecting the current transition increments it again. Ordinary successful token refresh does **not** increment it or replace the selected `User` object: private credential work is copied back into the still-owned object so existing retry consumers observe its refreshed cookies.

The committed object remains private while a transition is pending (`getCurrentUser()` returns `undefined`; `isSessionTransitionPending()` exposes only the boolean fence). Failed login/switch/background-fence operations retain the last committed account. Session-derived callers must capture both revision and owner and must not infer ownership from account ID alone.

## Persistence and asynchronous boundaries

- Network preparation works on detached `User` and role snapshots, including deep-copying role defaults; the model's shallow `clone()` remains unchanged
- UserService account/vault/role mutations share one queue. In-flight stale writes are rolled back before later queued selection reads proceed
- Selection writes are repaired to the last committed session after cancellation or failure; logout clears both selected database flags and preferences
- Token/profile/role callbacks check ownership before writes and before publishing. Delayed token saves cannot overwrite a same-ID restored identity or republish an old global ApiClient cookie
- Default-UID updates for nonselected accounts affect that account's role flags only. Account-page loading is read-only and cannot write global UID state
- A stale inserted login account is removed during rollback. Deletion and replacement wait behind already-dispatched writes rather than claiming such writes were cancelled
- Endpoint paths, signing protocols, the User model and vault/schema formats are unchanged. Modified account/profile logs omit account IDs, UIDs, profile values and raw error text

## Application-owned background fence

`setSessionInvalidationHook((reason: string) => Promise<boolean>)` installs one asynchronous pre-mutation fence. Reasons are `restore`, `reload`, `login`, `switch`, `logout`, `delete`, `defaultUid`, `refreshRoles` and `localReplacement`. The hook receives no account data or credentials. A false result aborts mutation and preserves the committed foreground session.

`restoreSession(): Promise<boolean>` reports true only after a valid saved account is committed; empty, failed and superseded restores report false. The application must distinguish ordinary cold-start restore from destructive replacement/logout. A normal restore should fence old background epochs while preserving persisted opt-in. A bounded synchronous `addSessionRevisionListener()` is also available (maximum 16 callbacks, explicit unsubscribe), but it does not replace the awaited fence.

## Backup integration

After validating a backup, but before capturing rollback preferences or writing account/vault data:

1. Await `beginLocalSessionReplacement()` and retain its numeric token. It fences background work, blocks new account operations, and drains/rolls back stale UserService writes
2. Perform the existing transaction/journal workflow
3. After a successful commit, await `reloadLocalSession()` to publish the restored identity using only local data
4. After a failed import and a **confirmed completed rollback**, call `cancelLocalSessionReplacement(token)` to expose the preserved old session again

A failed post-commit local reload fails closed instead of exposing the old, potentially deleted account object. A selected-account delete that fails after dispatch also leaves that identity logged out. Do not cancel the barrier while rollback remains incomplete. The service alone cannot coordinate arbitrary direct external account writes; restore callers must use this barrier before writing.

## Verification

`tests/account-session-ownership.cjs` executes production UserService/UserViewModel code through deterministic repository, vault, background-hook and network gates. It covers out-of-order login/switch/default-UID requests, logout/delete during restore, same-ID replacement, A→B→A token callbacks, in-flight write rollback, background-fence failures, backup drain/cancel/reload, failed transitions and repeated actions, profile/role callback ownership, listener bounds, read-only account-page loading, and successful same-session token refresh/retry. It includes strict host TypeScript checking at explicit platform boundaries.

The existing 15 regional-content contract tests continue to cover CN/HoYoLAB retries and cards with an updated repository/session fake boundary. Host execution is offline and supplements, rather than replaces, the parent-owned API 24 native ArkTS build and device checks.
