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
- `GameDataService.updateStatus()` returns a copy of `GameDataUpdateStatus`: invocation `id`, `state`, `done`, `total`, `current`, verified `bytes`, `activeFiles`, `error`, `canCancel` and `settled`
- `GameDataService.subscribeUpdate(listener)` returns an idempotent unsubscribe function and emits a copied current status immediately. Subscribe on page appearance and unsubscribe on disappearance so reopening Settings observes an existing update. Registrations are capped at 16; listener exceptions are isolated, the dispatch list is snapshotted, and reentrant state changes cannot replay stale outer status. Unsubscribing does not cancel work
- `GameDataService.cancelUpdate(expectedId?)` requests cancellation and resolves with that invocation's terminal status only after its started promise boundaries drain and writer ownership is released. Pass the captured status ID after a delayed confirmation; a stale ID cannot cancel a replacement invocation
- Phase states are `idle`, `preparing`, `downloading`, `validating`, `cancelling`, `cancelled`, `completed` and `failed`. Keep update/source/reset/rollback controls busy whenever `settled` is false, including `failed` while outstanding work drains. `canCancel` controls the cancel action
- Existing progress callbacks also notify phase and active-file changes. Query `updateStatus()` there; completed-file counts are monotonic, but file order is intentionally nondeterministic. Progress callback errors cannot abort the updater

## Verified input at planning time

Public data `main` was read at commit `c53167c9af159ea46cf7a4221d988a8f1729e1ae`, manifest blob `d517366268301af9ddc3131f7a7f995b6f076e54`: BOM, channel `hutao-cn`, version `2026.09.18.1`, 17 metadata files, 3,754 icons, no size/SHA256/schema fields. `gen-manifest.ps1` also provides no publisher hashes. The default branch must resolve afresh per operation; this commit is evidence, not a permanently hardcoded update target.

## Validation status

Foundation implemented and integrated at checkpoint `753c48d`. The bounded parallel/cancellation extension below has separate host coverage; its native integration results belong to the parent validation record. No device claim is made here.

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

## Bounded foreground parallel downloads and cancellation

A single invocation owns at most four file lanes. Each lane covers one HTTP request, asynchronous digest, checked staging write and read-only per-file verification before claiming another file. Mutable branch resolution and the manifest request still complete before the lanes begin; every payload remains pinned to that same immutable revision. Full-cohort verification and main-runtime-only publication are unchanged.

Every lane reserves its declared size, or the 8 MiB item limit for hashless/size-less v1 items, before its first await. One operation-wide ledger accounts for received bytes, successful staging writes and all outstanding cohort/disk reservations. Reservation pressure reduces spare lanes instead of multiplying limits. If even the remaining lane cannot safely reserve an item, the update fails closed. At most four network response buffers, each limited to 8 MiB, are admitted by this updater; this is not a claim about total native HTTP/crypto/taskpool process memory.

Cancellation is checked before and after every operation-owned await, before staging writes and at publication boundaries. The first non-cancellation failure stops further file admission; later cancellation does not overwrite its cause. The updater requests `HttpRequest.destroy()` only on its own active handles, then awaits the original request promises, native digest promises and caller-side taskpool waits. Every lane catches its own failure, so the final `Promise.all` drains all lanes instead of returning on the first rejection. Source/reset/rollback and another update remain fenced until that drain finishes. Destroy errors are recorded and cleanup is retried at request settlement; no synthetic promise race releases writer ownership early.

Native abort settlement timing is not guaranteed by these host tests. A request that has not settled keeps the UI in its draining state; cancellation is not advertised as instantaneous. A taskpool timeout may leave a native worker running after its caller-side wait has rejected. Those workers remain read-only, their unique staging trees are retained, and late receipts cannot publish or alter another invocation. Cancelled/failed staging is inert and counts toward the existing workspace quota; there is no new deletion path or restart-resume promise.

The active-pointer rename is the publication point. A cancellation observed before it preserves the selected old cohort; cancellation arriving after a successful commit cannot undo it and reports `completed`. For an exceptional native return after rename, a bounded pointer readback distinguishes a committed invocation from an uncommitted one. If the pointer cannot be classified, the result explicitly asks for restart verification instead of claiming cancellation or success. Process-visible metadata and icon paths remain pinned until restart in every case.

## Bounds and retained storage

Manifest: 4 MiB; item: 8 MiB; cohort: 512 MiB; 10,000 items maximum. Existing bytes in the new cohort root, including abandoned staging and orphan snapshots, count toward a 1.5 GiB workspace cap. Admission also checks free space and reserves a manifest plus 16 MiB. Legacy bytes remain outside this new-root cap but still consume actual disk space checked by the free-space floor.

Metadata worker result text is bounded at 32 Mi UTF-16 units. Startup and per-file worker waits use 15 seconds; final cohort/rollback verification uses 60 seconds. These are caller wait bounds, not proof that native workers are terminated or that a device will complete within them. File writes/fsync and small pointer operations remain bounded synchronous I/O; real-device latency and memory profiling are not replaced by host results.

Quota enumeration uses an iterative stack of validated directories and nonrecursive `listFileSync` calls. Before each scan it rechecks the directory's sandbox ancestry; returned symlink/special entries are rejected before enqueueing. A shared 100,000-entry limit bounds the entire walk, not each directory separately. This avoids the former recursive enumeration following an unsafe child before its type check. `tests/snapshot-quota-traversal.cjs` independently covers nine adapter-only cases, including ancestor/file/directory symlinks, a cycle, replacement after enqueue eligibility, entry limits and 96-level depth; it does not depend on the parallel updater. As with other pathname-based operations, this does not promise an atomic defense against an uncooperative actor changing the filesystem between individual native calls.

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

`NODE_PATH='' TYPESCRIPT_PATH="$PWD/ci/node_modules/typescript" node tests/game-data-cohort.cjs`: 53 production-path host cases passed. The original 33 remain, including ten before/after publication fault placements, old-or-complete-new recovery, bad pointers/bytes, reset tombstones, rollback, process pins, unsafe paths/URLs, short writes/fsync, retained-staging quota, source changes, cross-runtime/progress admission, startup/final/per-file worker timeouts, receipt identity, malformed PNG/UTF-8 and native URI conversion.

The additional 16 implementation cases cover four-lane overlap/out-of-order completion, cancellation before admission and at branch/manifest/network/hash/per-file/final verification phases, native abort and abort failures, stop-and-drain on first error, progress-callback reentrancy, cancellation racing publication/post-rename errors, shared reservation pressure, copied/invocation-bound status, stale cancel IDs, page-lifecycle status subscriptions/reentrancy/bounds and a mocked-latency comparison. In one host run of 34 files with a fixed 25 ms mock response delay, serial mode took 951 ms (peak one item request) and four lanes took 295 ms (peak four). These are repeatable synthetic overlap measurements, not a device/network speed estimate or acceptance criterion.

`tests/game-data-page-integration.cjs`: 19 production-method host cases cover lifecycle observer cleanup, reopening an active update, phase/count presentation, cancellation confirmation bound to the displayed invocation ID, duplicate actions, draining busy state, stale dialogs/callbacks, pre-admission rejection after an older success, commit-wins and unknown-commit wording, source/reset/rollback guards, restart-only state and no game-data `@State` writes after disappearance. These are UI boundary mocks, not rendered-device checks.

Independent review ran the original 49-case checkpoint and four additional fault probes; all four are now preserved directly in `tests/game-data-cohort.cjs` using its shared portable harness: write failure with blocked file workers retains writer ownership until drain; post-rename pointer-read denial reports unknown commit and restart recovers the complete cohort; cancellation after the directory move keeps the old pointer; progress invariants are asserted outside callbacks whose exceptions production code deliberately isolates. The combined 53-case suite passed. Review found no production blocker. In-suite progress/admission assertions were likewise moved outside isolated callbacks and re-run successfully.

Native SDK integration is tracked separately by the parent validation record. Host mocks do not establish native abort timing, filesystem durability under power loss, memory/performance acceptance, a device run, a real account or remote update success. Pointer rename gives process-interruption atomicity; parent-directory fsync/power-loss behavior has not been established.

## API references

- [File I/O and nonblocking locks](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.file.fs.d.ts): NOFOLLOW/tryLock API9, bounded enumeration options API11, optional nanosecond timestamps API15
- [Crypto digest APIs](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.security.cryptoFramework.d.ts): native asynchronous update/digest API9 and worker synchronous digest API12
- [Taskpool](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.taskpool.d.ts): Configs/timeout execute overload is API24, matching the minimum; timeout is not a worker-termination guarantee
- [HTTP](https://github.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.net.http.d.ts): destroy API6, maxLimit API11 and maxRedirects API23; destroy requests stop/releases resources but this implementation still drains the original request promise
