# F10: bounded native UIGF preparation and explicit export versions

## Implemented path

The page passes the selected document URI, a boolean and a deadline into an API24 `taskpool.Task`. The `@Concurrent` worker opens the URI read-only, checks size before allocation, reads exactly that size, verifies the size again, closes the handle, and decodes UTF-8 with `fatal: true`. Invalid UTF-8 is rejected rather than replaced with U+FFFD. File preflight, JSON parsing, all-UID validation, time normalization and duplicate conflict detection run in the worker. It has no repository, account, UI or database dependency.

The worker returns a versioned flat `string[]`, containing normalized record fields and UID/count headers. It never returns the source JSON, a Map, a model instance, a database handle or a document handle. The main thread validates the envelope and restores real `GachaItem` instances in slices of at most 256 rows or 64 Ki code units. The zero-delay yield is only for hydration; it does not simulate background parsing. Preview summaries are built during hydration and cached, so rendering the confirmation does not rescan every record.

The view model retains the validated preparation, never the original file. Confirmation selects UID arrays from that preparation and calls the existing `GachaRepo.importArchives` synchronous transaction. There is no JSON parse, second worker parse or await inside the transaction. Failures on a later archive/batch roll back every selected UID. A failed commit can retry the retained preparation without parsing again. A post-commit reload failure is reported as a successful import with a view-refresh warning.

`UigfService.prepareImport` remains a pure synchronous compatibility adapter for trusted/host consumers. The native page exclusively uses `prepareImportFile`/`UigfImportJob`; it cannot fall back to that synchronous adapter if taskpool fails.

## Bounds and cancellation

- File input: 32MiB; direct text: 32Mi UTF-16 code units
- JSON nesting: 32 levels, checked before `JSON.parse`
- Raw input rows: 262,144, counting exact duplicates before deduplication
- Unique UIDs: 1,024; string fields: 4,096 code units
- Worker result:at most3 + 2×1,024 + 9×262,144 strings and 48 Mi code units
- Diagnostics: 512 code units; only explicitly constructed application errors cross the worker boundary; unknown provider/SDK failures become a generic safe message
- Native wait deadline: 30 seconds, checked cooperatively during scanning and record conversion

These are application admission/retention bounds, not a promise of constant memory or a device performance benchmark. JSON parsing and native structured cloning are indivisible work inside their respective runtimes. The bounds constrain their input; cancellation does not promise to interrupt `JSON.parse` in the middle.

Cancel immediately invalidates the owner and rejects its waiter, asks taskpool to cancel, and disposes retained/partially adopted data. Admission remains occupied until the native promise and hydration settle. Timeout behaves the same way. There is no retry queue multiplying copies in memory. Account changes, new files and page disposal fence stale results through generations. A cancellation after the synchronous database transaction committed cannot undo that already committed transaction; the stale completion cannot clear a newer preview or change login authority.

## Format compatibility

Supported explicit exports:v2.2/v2.3/v2.4/v3.0/v4.0/v4.1/v4.2. The default is v4.2.

| Requested format | Representation boundary |
| --- | --- |
| v2.2 | One UID; regular pools except500; conservatively requires known Chinese item-type text and no Latin-letter item names; inferred UID timezone |
| v2.3 | One UID; regular pools except500; inferred UID timezone |
| v2.4 | One UID; regular pools except500; explicit `region_time_zone` |
| v3.0 | One UID; includes pool 500; explicit `region_time_zone` |
| v4.0/v4.1 | Multiple UIDs, regular pools; no `hk4e_ugc` field, even empty |
| v4.2 | Multiple UIDs, regular and Beyond partitions |

Unsupported selections/fields fail before opening the destination picker. They are not filtered out. Nonzero regular-pool `scheduleId`, unknown enumerable local-model fields, noncanonical stored timestamps, unknown versions and v4 cursor IDs longer than 19 digits are refused. IDs are never shortened or passed through Number. Imports remain tolerant of longer exact decimal string IDs; such records can still be represented in legacy versions that have no 19-character schema limit.

Exports use decimal strings for item IDs and Beyond schedule IDs. v4.2 retains Beyond quantity as a documented `count` extension; consumers that ignore unknown fields may not preserve non-unit quantities. Beyond subpool enumeration has not been changed by this work.

This is a projection of known local Genshin record fields, not a byte-for-byte JSON backup or a general UIGF document transcoder. Input exporter metadata, language labels, foreign-game partitions and unknown source extensions are not persisted by the existing local record schema. Names/type strings are preserved; exports do not invent an archive language label. Source timestamps are normalized once to UID-inferred server wall time; instants, not the original spelling/offset, are preserved. Version downgrade operates on those persisted records. It does not claim to recover previously discarded source metadata. The preview explicitly states the known-record projection boundary.

Detailed UIGF validation diagnostics remain Simplified Chinese. They are bounded safe application messages; this implementation does not claim complete Traditional Chinese/English diagnostic localization or UIGF certification.

## Primary-source audit

- [Official current UIGF specification](https://uigf.org/en/standards/uigf.html):v4 multi-account envelope, string item/schedule identifiers,19-digit record-ID limit and v4.2 Beyond addition
- [Official legacy specification](https://uigf.org/en/standards/uigf-legacy-v3.0.html):single `info.uid` + `list`; timezone introduced in v2.4; pool 500 introduced in v3.0; UID inference6→−5,7→+1, others→+8; explicit source timezone takes precedence on import
- Pinned Windows commit `3f0d1f363a8226cccd76f0f66f599e729b0f214c`:[UIGF42ExportService](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/UIGF/UIGF42ExportService.cs),[UIGF42ImportService](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/UIGF/UIGF42ImportService.cs),[Hk4eUGCItem](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/InterChange/GachaLog/Hk4eUGCItem.cs),[UIGFEntry](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/InterChange/GachaLog/UIGFEntry.cs)
- Installed HarmonyOS SDK `@ohos.taskpool.d.ts`:Task/execute/cancel are available before API24; `Task.isCanceled()` supports cooperative cancellation. Running-task cancellation reports the execution outcome through the native promise rejection; it is not a guaranteed hard preemption.

## Verification

`node tests/uigf-background.cjs`: 16 host tests execute the production worker, codec, transfer, view model and real in-memory SQLite repository transaction with narrow native SDK doubles. Cases cover URI-only admission, parse-once confirmation, cancellation before completion/during hydration, stale account/page owners, timeout admission, UTF-8/file closure failures, size/depth/row/field limits, malformed and oversized envelopes, all seven exporter roundtrips, downgrade refusals, exact long IDs and rollback/retry.

`node tests/uigf-selective-import.cjs`: 17 production service/preparation/repository tests, including real SQLite rollback and strict host types.

`node tests/offline-gacha-access.cjs`: 21 production page/VM tests; native picker/taskpool/file boundaries are doubled. `node tests/data-port.test.mjs`: 11 broader regression tests.

Host tests do not prove native worker scheduling, API24 device performance, document-provider permission behavior or visual accessibility. Parent-coordinated native build/lint and aggregate verification are reported separately; no device, live account, cloud upload, GitHub write or CI execution was used here.
