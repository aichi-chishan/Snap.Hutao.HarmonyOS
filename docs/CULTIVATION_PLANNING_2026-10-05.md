# F05/F06 · Native cultivation planning

## Delivered workflow

- Character list: explicitly select several characters, plan those selections or the entire loaded list, and review each character before saving. The current character also has a separate equipped-weapon planning action; role and weapon targets are independent.
- Character, weapon wiki and saved-plan entries share one draft editor: project selection, current/target levels, exact current/target ascension stages, three independently editable base talent levels, material preview, and explicit save.
- Existing entries reopen the persisted inputs and can refresh current progress from the selected UID. Refresh changes current values only. If current progress already exceeds a chosen target, the saved target is retained exactly; calculation uses the greater current value and charges no negative or already-completed upgrade cost.
- Duplicate targets explicitly default to skip; users may choose overwrite. The report lists added, updated and skipped entries. A failed batch rolls back all input/material writes, including a newly created default project.
- Input JSON and material results commit in one SQLite transaction. An existing entry retains its ID. Material completion flags survive only if material ID and required quantity are unchanged; changed quantities require reconfirmation. An optimistic input token rejects stale editors.
- Local plans and offline wiki planning remain available without login. Character-list refresh does not hide or delete saved plans. Character and cultivation content switch at the 840vp content-width breakpoint; new editor actions use 44vp controls.

## Unknown/manual behavior

- New offline plans explicitly begin at level 1. These values remain editable. Verified skill group IDs are used, not array-position guesses; unsupported/ambiguous skill mappings are refused.
- Current equipped weapon progress without a verifiable ascension stage opens with that stage unknown. The user must explicitly enter it before calculation/save. A failed refresh of an existing plan never substitutes a manual draft or overwrites any saved values.
- Legacy entries without input snapshots preserve their original materials and known level range. Their missing current ascension and talent current/target values are blank and require confirmation. Nonempty malformed or future-version snapshots are rejected for editing and retained unchanged.
- Manual edits to current levels/ascension/talents clear the synchronized timestamp; target-only edits do not. UID identity remains attached to synchronized drafts.
- Missing selected characters/talents, changed equipped weapons, incomplete calculations, or account changes cannot partially refresh a batch. Cancel, dismissal, Back/navigation, stale asynchronous completion and repeated Save are guarded before persistence.
- One- and two-star weapon plans stop at level 70 and ascension stage 4. Target ascension is explicit, including same-level ascension at a level cap.
- Calculator inventory sync consumes complete saved inputs belonging to the current UID, updates only returned material counts, and is labeled as plan-material inventory, not a full backpack.

## Persistence and verification

DB v8 adds `cultivate_entries.input_json TEXT NOT NULL DEFAULT ''`. Draft schema version 1 is bounded to 65,536 characters. Backups preserve opaque snapshots; earlier backups restore legacy empty snapshots. See the separately maintained v8 SQLite backup regressions.

`tests/cultivation-planning.cjs` executes production draft codec, offline arithmetic, repository and editor VM. SQLite is real; network/OS and metadata delivery are fixtures. Covered cases include independent target roundtrip, current progress overtaking targets, partial/malformed refresh, explicit cap ascension, low-star caps, atomic batch/retry, stable entry ID, material completion retention/reset, rollback after injected disk failure, native negative/short insert/delete returns and merged-quantity overflow, stale editor rejection, cancel/account switch, legacy/future input handling, source provenance, and bounded snapshots. Existing `tests/data-port.test.mjs` still exercises the original arithmetic and transactional entry-save path.

The aggregate host run passed 29 suites with the repository-pinned TypeScript 5.9.3 and empty `NODE_PATH`. The focused cultivation suite passes 16 cases after the bounded persistence review. The parent’s official SDK compile of the corrected editor succeeded (33 tasks); final repository insert-result/overflow guard changes require the parent’s final frozen suite/build before delivery. Real-account API calls and on-device visual/interaction verification remain deferred; host tests are not device evidence.

## Primary Windows evidence

Pinned upstream commit: `3f0d1f363a8226cccd76f0f66f599e729b0f214c`.

- [AvatarPropertyViewModel](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/AvatarProperty/AvatarPropertyViewModel.cs): target-dialog-first character/weapon planning, selected/all batch commands, per-entry save strategy
- [CultivationViewModel](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Cultivation/CultivationViewModel.cs): persisted `LevelInformation`, `ModifyEntryCommand`, current-progress resynchronization

No injection, game-memory access, Windows process control, or cloud service is introduced by this workflow.
