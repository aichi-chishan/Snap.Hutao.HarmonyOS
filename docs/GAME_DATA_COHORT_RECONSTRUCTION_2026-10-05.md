# Foreground game-data cohort reconstruction

## Approved scope and implementation plan

This is a new bounded implementation for the public `eeb58a9` reconstruction, not a replay or claim of recovery of the unavailable `53a813e` implementation.

1. Introduce strict trusted-repository manifest/path/size policies and operation-local Git commit pinning. Keep hashless publisher v1 compatible, with local SHA256 receipts clearly distinguished from publisher authentication.
2. Stage every declared file in a unique directory; verify exact writes, fsync, complete cohort structure and bytes before atomically publishing a small pointer to an immutable snapshot. Never unlink live data before publication.
3. Validate current/previous snapshots off the UI runtime at startup, then pin one complete metadata/icon cohort for the entire process. New updates, reset and rollback apply after restart.
4. Preserve legacy cache bytes without claiming they form a verified snapshot. Use bundled data when no new verified cohort exists. Protect update/source/reset admission with a nonblocking writer lock.
5. Add production-path host fault tests for malformed manifests, byte/model errors, interrupted publication, corruption recovery, reset tombstones, process pins, writer admission and legacy preservation; then request independent review and official SDK validation.

Excluded: persistent resume, byte reuse, history/staging garbage collection, a killed-process whole-queue scheduler, producer-repository changes, real-device/account testing and remote publication. Failed staging stays inert and counted against quota. Read-only workers cannot publish; a timeout cannot grant a late worker write access.

## Integration contract

- Await `GameDataService.initializeSnapshot()` after backup recovery and before metadata consumers/Index load
- `updateAll(progress)` still resolves to the saved version, which takes effect after restart
- `remoteVersion()` is process-visible; `pendingVersion()` describes a saved-next version
- `setManifestUrl` rejects malformed/untrusted sources and changes while updating; the settings caller must catch errors
- `clearRemote()` is a post-initialization pointer reset, not recursive deletion

## Verified input at planning time

Public data `main` was read at commit `c53167c9af159ea46cf7a4221d988a8f1729e1ae`, manifest blob `d517366268301af9ddc3131f7a7f995b6f076e54`: BOM, channel `hutao-cn`, version `2026.09.18.1`, 17 metadata files, 3,754 icons, no size/SHA256/schema fields. `gen-manifest.ps1` also provides no publisher hashes. The default branch must resolve afresh per operation; this commit is evidence, not a permanently hardcoded update target.

## Validation status

Foundation implemented; the current scoped host checkpoint is recorded below. No native build or device claim is made here.

## Implemented architecture

`GameDataManifestPolicy`, `GameDataSnapshotStore`, `HarmonySnapshotIo` and `GameDataSnapshotWorker` are new foundation files. `GameDataUpdater` now uses this foundation; `GameDataService` preserves its read/update facade. The former lifecycle replay package remains untouched.

- Default branch/tag resolution is repeated per operation through the exact trusted repository commits endpoint; direct 40-hex revision sources avoid that lookup. Manifest and payload requests stay on the same resolved Git tree. An embedded main URL is a path hint, never a moving payload request. HTTP redirects, third-party mirrors, user information, ports, traversal and unknown metadata paths are rejected
- The 17 required metadata files are mandatory. Text roots/IDs, skill text, material references, curve values, achievement relationships, tower floor references and gacha/combat identity references receive explicit checks. This is not a full formal model of all game semantics
- PNG validation checks signature, IHDR, bounded dimensions, legal depth/color fields, bounded chunk extents/CRC, palette/data ordering and final IEND. It is structural/transport validation, not full raster decompression or a guarantee of platform image-renderer acceptance
- Downloads and checked/fsynced writes use unique `gamedata/cohort-v1/staging/{id}` trees. Received bytes are hashed with the native asynchronous digest API. A read-only worker checks staged bytes against that exact digest, publisher declarations when present, and JSON/PNG structure. Its small receipt binds root, invocation ID, the full item descriptor, exact byte count and digest
- After all items finish, a second read-only worker reads and hashes the complete cohort again, validates its metadata graph, and checks file identities. Main runtime alone can move the directory and publish pointers. A timed-out/late worker has no write, rename, cleanup or publication capability
- Same-root metadata rename publishes `active.json` only after the snapshot directory is complete. `active.previous.json` and the previous ID support recovery. Startup hashes every selected file off the UI runtime; invalid current data falls back to a verified previous cohort, then bundled data. Orphan directories never activate
- Current metadata text, icon paths and `remoteVersion()` remain pinned for the process; no cache invalidation attempts to swap half of Wiki/BaseValue/Tower/Achievement state. `pendingState()` distinguishes `none`, `remote` and reset-to-`bundled`; `pendingVersion()` names the saved remote version. `canRollback()` is only an availability hint; actual rollback validates the full candidate under the writer lock
- A nonblocking filesystem lock serializes update/source/reset/rollback admission. Process-local admission also fences duplicate clicks and progress-callback reentrancy. Restored preferences changing the source abort the operation before publication
- NOFOLLOW and ancestor type checks apply to file reads/writes, including pointer `.next` paths. There is no recursive deletion path. Reset publishes a tombstone; it does not delete either the selected or legacy directories. A published reset remains visible in pending state even if refreshing its backup subsequently fails

## Bounds and retained storage

Manifest: 4 MiB; item: 8 MiB; cohort: 512 MiB; 10,000 items maximum. Existing bytes in the new cohort root, including abandoned staging and orphan snapshots, count toward a 1.5 GiB workspace cap. Admission also checks free space and reserves a manifest plus 16 MiB. Legacy bytes remain outside this new-root cap but still consume actual disk space checked by the free-space floor.

Metadata worker result text is bounded at 32 Mi UTF-16 units. Startup and per-file worker waits use 15 seconds; final cohort/rollback verification uses 60 seconds. These are caller wait bounds, not proof that native workers are terminated or that a device will complete within them. File writes/fsync and small pointer operations remain bounded synchronous I/O; real-device latency and memory profiling are not replaced by host results.

No old or failed tree is removed to create space. Repeated interrupted updates can therefore exhaust the workspace limit and fail closed; a future, separately reviewed cleanup lifecycle is required before promising automatic storage reclamation.

## Producer data and current availability

The previously published `c53167c9...` manifest includes malformed image payloads (nginx 404 HTML with `.png` names). A whole-cohort update of that published version correctly fails validation; no declared file is silently skipped.

The separately repaired local data working tree passed this client's implemented shape/reference and all-file size/SHA256/PNG checks:

- Version `2026.10.05.1`; schema 1 with size/SHA256 declarations
- 3,769 items: 17 metadata files + 3,752 PNGs
- Payload bytes: 241,295,126
- Manifest bytes: 1,313,032
- Manifest SHA256: `1f4bcfe52538942f38fc61cf340efb60c86e9621cb97afa4ed1e5cd7ca2aff2b`

This is local working-tree validation, not publication or commit-qualified remote validation. The remote default remains blocked until a corrected data commit is published through a separately authorized flow. Client-generated receipts never become publisher authentication.

## Current verification checkpoint

`node tests/game-data-cohort.cjs`: 33 production-path host cases passed, including ten before/after publication fault placements, old-or-complete-new recovery, bad pointers/bytes, reset tombstones, rollback, process pins, unsafe paths/URLs, short writes/fsync, retained-staging quota, source changes, cross-runtime/progress admission, startup/final/per-file worker timeouts, receipt identity, malformed PNG/UTF-8 and native URI conversion.

Independent review also ran the focused suite and separate policy/store fault tests; final integration and native SDK results belong to the parent validation record. This document does not claim a native build, HAP, device run, real account or remote update success.

## API references

- [File I/O and nonblocking locks](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.file.fs.d.ts): NOFOLLOW/tryLock API9, bounded enumeration options API11, optional nanosecond timestamps API15
- [Crypto digest APIs](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.security.cryptoFramework.d.ts): native asynchronous update/digest API9 and worker synchronous digest API12
- [Taskpool](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.taskpool.d.ts): Configs/timeout execute overload is API24, matching the minimum; timeout is not a worker-termination guarantee
- [HTTP](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.net.http.d.ts): maxLimit API11 and maxRedirects API23
