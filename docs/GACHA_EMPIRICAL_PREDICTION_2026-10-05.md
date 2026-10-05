# Empirical wish prediction UI and cloud-session ownership

## Review scope

This increment replaces GachaLogPage's hard-coded 0.6% / 74-pull calculation with the existing `GachaPredictionService` conditional empirical distribution. It does not introduce another statistical model or claim that displayed frequencies guarantee future outcomes. The independently implemented `GachaPoolRules` and `GachaPredictionService` remain the source of pool limits, distribution mapping and bounded probability calculation.

The page now provides an explicit query button and a selected-pool control that also works in wide layouts. Rendering, page entry and pool selection do not fetch distributions. Local archive access and game-login state remain separate from the required Hutao Cloud passport session. Requests use the existing statistics endpoint mapping and bearer-token transport; no archive records or local UID are added to those requests.

## History and presentation

- The exact selected archive/pool must have a known recent five-star reset. There is no fallback to the character pool or a fabricated zero-pity value
- History inspection is bounded by the corresponding pool threshold, validates quality/pool identity, rejects duplicate or out-of-order cursors, and rejects pity at or beyond the threshold instead of relying on the pure helper's Windows-compatible clamp
- Request snapshots use a bounded primitive history key; they do not capture additional previous-history arrays when the view-model replaces its rows
- Only the selected pool has enough loaded raw rows to validate reset history. Other countdown cards explicitly say “选择该池后校验历史”; the UI does not manufacture per-pool confidence from aggregate counts
- Weapon five-star thresholds use 80, character-family thresholds use the rules module's 90, and standard Beyond has no finite five-star prediction while its four-star threshold uses 90. Unsupported pools avoid zero-total progress bars
- Confidence changes participate in card keys so a repaired or invalidated history does not reuse stale countdown content
- Results display next-draw conditional frequency, the conditional distribution's mode and its frequency, and a fixed small set of cumulative within-N frequencies
- Full distribution sample events and post-pity conditional sample events are labeled separately. Retrieval time is explicitly the device-recorded UTC fetch time, not a collection/cutoff date
- Missing history, unknown quality, unsupported pools, empty/zero tails, malformed distributions, login problems and transport failures remain unavailable states. The UI warns that the figures are neither theoretical odds, guarantees nor specified-UP probabilities
- New query/selector controls and affected pool switches have 44vp minimum targets. Source checks do not prove screen-reader behavior, typography or native layout on devices

## Request ownership

Prediction completion must still match its request generation, page epoch, local archive, selected pool, recorded pity/history, game-login context and cloud identity revision. Leaving the page, changing local archive/account/pool or replacing a request fences older results. Repeat clicks are ignored while the current request is pending. A stale completion cannot release the loading state of a newer request.

`HutaoCloudService.getSessionRevision()` exposes a nonsensitive identity counter. Login, logout, local forget, email-identity changes and unregister advance it. Ordinary access-token rotation does not. Authenticated statistics check ownership after token acquisition, before HTTP dispatch and after the response. Already-dispatched server requests/actions are not claimed to be cancelled.

## Vault mutation coordination

Cloud session writes/clears use a per-service-instance serialized mutation queue. Initial load and token refresh are coalesced; old initial loads and refresh/login responses cannot publish into a newer identity. Local forget invalidates in-memory identity immediately, then awaits its queued persistent clear. A logout or unregister completion checks its owner before clearing anything, protecting a newer login.

A save already in progress cannot be cancelled. If it finishes stale, the queue repairs persistence to the last committed in-memory session, or clears it when logged out, before advancing to later mutations. This also covers a newer login attempt that fails and would otherwise leave no later save to overwrite the stale one.

Storage operations can still fail. A failed clear is reported and the process stays logically logged out; persistent deletion and restart behavior cannot be promised when the native vault reports failure. A rejected mutation does not poison the queue for later authorized actions. This is not a cross-process AssetStore locking protocol.

New ownership errors use fixed text without embedding token/password/account values. Prediction failures use a generic UI message. The original cloud wire protocol and its existing error handling are not otherwise redesigned.

## Verification

- `tests/gacha-prediction-ui.cjs`: eight production-method tests cover manual-only requests, conditional results, duplicate clicks, missing/unknown/out-of-range history, pool-rule usage, confidence-key updates, stale page/archive/pool/history/account completion, cloud logout/relogin, honest labels and bounded primitive snapshots
- `tests/cloud-session-ownership.cjs`: fourteen tests cover delayed load/save/clear/login/refresh/email/logout/unregister interleavings, stale-save repair, natural refresh without identity-counter changes, authenticated statistics dispatch/result fences, failure recovery and a strict host type-check of the service/wire-model graph
- `tests/cloud-protocol.cjs`: original isolated bearer/RSA/Int64/wire regressions remain unchanged
- `tests/offline-gacha-access.cjs`: the narrow extracted-page fixture adds the prediction invalidation hook; existing F09/F10 assertions are retained
- The supplied `tests/gacha-prediction.cjs` continues to exercise the pure conditional distribution and per-pool rules

All tests use synthetic data and native/transport/vault doubles; no live account or HTTP requests are made. Current-increment official ArkTS/HAP compilation, native vault scheduling and device UI/accessibility validation must be reported separately by the checkpoint build. A previous F10 build is not evidence for this increment.
