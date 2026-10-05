# F14: native challenge upload, protocol and acceptance boundary

Date: 2026-10-05. Minimum platform remains HarmonyOS API 24. This is a client port, not a cloud server deployment. No Windows process injection or HardChallenge upload is introduced.

## Audited primary sources

Windows source is pinned to `SnapHutaoRemasteringProject/Snap.Hutao.Remastered@3f0d1f363a8226cccd76f0f66f599e729b0f214c`:

- [SpiralAbyssViewModel upload command](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/SpiralAbyss/SpiralAbyssViewModel.cs): the no-Passport dialog offers a continue branch
- [HutaoSpiralAbyssClient](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/SpiralAbyss/HutaoSpiralAbyssClient.cs): player preflight, complete character list/details, current abyss, upload
- [Abyss DTO folder](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/tree/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/SpiralAbyss/Post): SimpleRecord, SimpleAvatar, SimpleSpiralAbyss, SimpleRank, SimpleFloor, SimpleLevel, SimpleBattle
- [RoleCombatViewModel](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/RoleCombat/RoleCombatViewModel.cs), [HutaoRoleCombatClient](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/RoleCombat/HutaoRoleCombatClient.cs), [SimpleRoleCombatRecord](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/RoleCombat/Post/SimpleRoleCombatRecord.cs): player preflight and first/current API period; upload only the backup avatar IDs, not fabricated round-level analytics
- [Endpoint definitions](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/tree/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Endpoint/Hutao): IHomaSpiralAbyssEndpoints, IHomaRoleCombatEndpoints, HutaoEndpointsForRelease

Official backend source was independently inspected and pinned to `SnapHutaoRemasteringProject/Snap.Hutao.Server@0cb775a3e900b7709a1117556ef73cc84cbce708`:

- [RecordController](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Server/blob/0cb775a3e900b7709a1117556ef73cc84cbce708/src/Snap.Hutao.Server/Snap.Hutao.Server/Controller/RecordController.cs) and [RecordService](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Server/blob/0cb775a3e900b7709a1117556ef73cc84cbce708/src/Snap.Hutao.Server/Snap.Hutao.Server/Service/Legacy/RecordService.cs): explicit successful no-username branch, current-period checks, repeat-upload result, concurrency refusal
- [RoleCombatController](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Server/blob/0cb775a3e900b7709a1117556ef73cc84cbce708/src/Snap.Hutao.Server/Snap.Hutao.Server/Controller/RoleCombatController.cs) and [Program](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Server/blob/0cb775a3e900b7709a1117556ef73cc84cbce708/src/Snap.Hutao.Server/Snap.Hutao.Server/Program.cs): Upload has no authorization attribute; no global fallback authorization policy is installed; theater also accepts the public upload contract
- [SimpleRecord validation](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Server/blob/0cb775a3e900b7709a1117556ef73cc84cbce708/src/Snap.Hutao.Server/Snap.Hutao.Server.Model/Upload/SimpleRecord.cs) and [SimpleRoleCombatRecord validation](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Server/blob/0cb775a3e900b7709a1117556ef73cc84cbce708/src/Snap.Hutao.Server/Snap.Hutao.Server.Model/RoleCombat/SimpleRoleCombatRecord.cs)
- [PizzaHelperRecordService](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Server/blob/0cb775a3e900b7709a1117556ef73cc84cbce708/src/Snap.Hutao.Server/Snap.Hutao.Server/Service/Legacy/PizzaHelper/PizzaHelperRecordService.cs): optional downstream forwarding uses a salted/hashed UID with character ownership and, for qualifying full-star records, abyss data. The native review discloses this behavior before submission; deployment configuration and successful forwarding are not assumed

These are source contracts, not proof that a production deployment runs these exact revisions. There were no live authenticated game reads, account actions, upload probes, remote writes or server changes during implementation.

## Wire contract

Origin: `https://homa.snaphutaorp.org`. Both routes are JSON POST. Both deliberately omit Cookie and Authorization. They use the already isolated HutaoCloudClient transport, which disallows redirects and automatic endpoint fallbacks.

- `/Record/Upload`: `Uid`, `Identity` (`Snap Hutao`, matching the pinned port), nullable `ReservedUserName`, `SpiralAbyss`, `Avatars`
  - `SpiralAbyss`: `ScheduleId`, `TotalBattleTimes`, `TotalWinTimes`, `Damage`, nullable `TakeDamage`, `Floors`
  - rank: `AvatarId`, `Value`
  - floor: `Index`, `Star`, `Levels`; level: `Index`, `Star`, `Battles`; battle: `Index`, `Avatars` (numeric IDs)
  - avatar: `AvatarId`, `WeaponId`, `ReliquarySetIds`, `ActivedConstellationNumber`
- `/RoleCombat/Upload`: `Version` = 1, `Uid`, `Identity` = `Snap Hutao`, `BackupAvatars` (numeric IDs), `ScheduleId`

The abyss optional Passport account name is the only account association field. It is explicitly shown in the review and protected by cloud identity revision. No cloud token refresh is necessary for this public contract. Theater has no account-name field. Anonymous abyss is source-grounded in the backend's explicit successful null-username branch, rather than inferred from a missing client login gate. The UI offers Passport navigation or confirmation without association and makes no reward guarantee.

A fresh player `index` request precedes collection. BasicRoleInfo does not guarantee a UID echo and its `region` field is a localized name; ownership comes from the selected account's bound UID/server, captured User object and monotonically increasing UserService.sessionRevision(). Any optional UID/server echoes are checked. The collector uses only that captured account's explicit Cookie, first-party regional endpoints, fresh DS, established risk replay, and the account-owned cookie refresh wrapper. Every async boundary rechecks owner/revision/selected UID plus cancellation. No raw response or credential is inserted into a cloud DTO.

## Validation and confirmation

- Only freshly fetched current challenge data is uploadable. Historical/previous abyss UI disables preparation. Theater uses the first API period, matching Windows. The fetched period must equal the user-visible selected period; otherwise preparation fails and requires refresh
- Abyss collects all list IDs and exactly matching details; missing or duplicate details cannot become an empty/default loadout. Raw relic `set.id` is used because the older display model stores only set names
- Pinned backend checks are retained: more than eight owned avatars, exactly one traveler and all three starter characters, five-digit weapon IDs, seven-digit relic-set IDs and at least one relic, positive battle/win counts, complete upper/lower halves from floor 9, no repeated/unowned team avatars. Additional client bounds reject invalid integer types/ranges, missing required arrays, duplicate floors/levels/halves and absent damage records
- Theater requires at least eight distinct backup IDs. Missing records, missing detail, wrong period, incomplete collection, owner changes and backend refusal produce distinct messages
- Dedicated DTO whitelisting omits nickname, avatar images, battle timestamps and all unused game response fields. Semantic set arrays are normalized before hashing, preserving duplicate relic-set pieces; equivalent ordering does not generate spurious new submissions
- Preparation constructs a device-local preview only. It shows exact UID/server/period, content categories, destination, Passport association, server replacement/downstream behavior, complete JSON and SHA-256. Only the explicit confirmation button dispatches
- Preview tickets expire after ten minutes; changing account/UID/period, cancellation or disappearance invalidates them. The service retains a private copy; changes to displayed objects cannot alter the transmitted body
- Confirmation has a synchronous one-use latch and a shared per-kind/server/UID lock. Under that lock it rechecks durable success receipts and ownership, so two separately prepared previews cannot race into a second identical submission
- No automatic upload retries. HTTP/nonzero retcode/malformed envelope fail; only a strict numeric `retcode: 0` after successful HTTP counts as an acknowledged upload. Network uncertainty is explicitly identified as potentially already received by the server

## Receipt and backup semantics

The dedicated `challenge_cloud_receipts_v1` preferences store holds at most 100 recent acknowledged uploads across accounts. Each receipt contains local owner ID, UID, server, challenge kind, period, SHA-256, acknowledgment time and numeric zero retcode. It retains no original payload, Passport name/token, game Cookie or player profile. Writes are serialized and await durable flush; failures keep the truthful server-success message plus a local-save warning.

This store is deliberately excluded from the portable user-data backup schema. A restore therefore does not claim that uploads happened from this device, and duplicate detection cannot be guaranteed after reinstall/backup transfer/receipt eviction. The confirmation UI says so. Existing local history and account backup data are unchanged. These local receipts are not server-signed proof or a cross-device upload index.

If an already-dispatched upload succeeds after navigation/account switching, its receipt remains bound to the original captured owner; it never updates a new page's success state. Cancelling a preview prevents dispatch, but navigation cannot recall a request already sent. No server deletion or undo is implied.

## Verification

Run `NODE_PATH=ci/node_modules node tests/challenge-cloud.cjs`. The suite loads the actual production DTOs, collector, upload service, VM, isolated HutaoCloudClient and receipt store. Only SDK crypto/preferences/HTTP and the external game/account context are deterministic doubles. Fixtures are synthetic, not captured account records. It also type-checks the production graph with explicit external SDK/account declarations.

Covered: exact PascalCase DTOs/endpoints; anonymous and Passport-associated abyss; independent theater upload; no Cookie/Bearer leakage; preparation causes zero cloud writes; partial/missing/mismatched source data; risk cancellation/replay; account switches including away/back revisions; cloud identity change; cancellation at each read; duplicate taps and concurrent independent previews; expiry; HTTP/server/malformed-response refusal; transport uncertainty; success-only original-owner receipts; disk failure; bounded retention; stable semantic digest; no HardChallenge upload.

Existing `tests/cloud-protocol.cjs` and `tests/cloud-session-ownership.cjs` also pass after the transport extraction. Official native compiler/lint and device UI/live-account acceptance remain separate evidence; a host pass alone is not a native or live end-to-end pass.
