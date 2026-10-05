# Public-baseline reconstruction: 2026-10-05

## Provenance and limits

This is new local work based on the public task branch commit `eeb58a9eff6dba94c031eeb30751cbbd86d37b20` (tree `afd3c36c6947c1f442bda2041d2e9aa10103d656`). The prior local `53a813e` baseline and `5cdbff00` final tree are not restored. The preserved later replay kit requires missing earlier implementation, including LocalizationService, RawIconCache and costume-art models; it cannot be applied wholesale to this older baseline. Historical 110-suite results and native build results do not describe this checkout.

Current user scope excludes Windows-only functions. Work remains local; no remote push, PR mutation or CI dispatch. API24 minimum and API26 target in the existing CI build profile are unchanged. Device/account acceptance remains deferred.

## Checkpoint 1: metadata-icon lifecycle

- Invalidate pending image work when the component detaches; a replaced input immediately clears the old image.
- Observe remote-fallback changes and prevent stale/detached requests from starting later fallback stages.
- Catch rejected remote fallback promises instead of producing unhandled rejections.
- Preserve absolute sandbox paths when recursively creating cache directories.
- Convert paths through the native file URI API instead of constructing `file://` strings.
- Remove per-icon informational logging from the scrolling path, preserving failure diagnostics.

`tests/meta-icon-lifecycle.cjs` executes the real component methods with deterministic native doubles. It covers rapid replacement, detach, stale failed reads, CDN-to-resource fallback cancellation, late remote success, rejected network requests, native URI conversion and absolute cache paths.

Validation: TypeScript5.9.3 from the repository lockfile, installed with lifecycle scripts disabled. The focused test passed. The baseline runner plus this new test passed 10 host suites. Host transpilation is not an ArkTS build. SDK/lint/HAP/device checks were not run for this reconstructed checkpoint.

Official API evidence checked 2026-10-05:
- [File URI](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-core-file-kit/js-apis-file-fileuri.md): getUriFromPath, initial API9
- [Custom component lifecycle](https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-page-custom-components-lifecycle.md): invalidate ordinary lifecycle fields on disappearance without changing decorated state

The separate shared-control and splash-art changes are still being developed and are not part of checkpoint 1.

## Checkpoint 2: native controls and resilient art loading

- Nine shared controls now react to parent-provided values. Native button semantics replace clickable layout containers for the primary action and account card; actions have 44vp minimum targets and flexible text layouts. The back button uses a bundled theme-tinted SVG.
- QTapButton suppresses pressed-state effects while disabled and exposes caller-controlled reduced motion. There is no restored system reduced-motion integration. Back accessibility text defaults to Chinese, with an overridable label; multilingual service infrastructure is still absent.
- Existing SplashArtView now observes icon changes, clears old images immediately and fences detached/stale work before disk writes or further fallbacks. This baseline still has no costume selector/service; the historically named costume-art-lifecycle test covers existing splash handling only.
- Metadata icon names are constrained to safe path segments. Detached raw reads no longer write cache files. Raw byte-array views in both icon and splash paths are copied with their exact offset/length. Native file URI conversion is used consistently.
- Positive metadata cache entries are checked for eviction; transient failures are no longer permanently cached, and a late failed reader cannot replace a valid cached result with a negative entry.

Fresh validation after the final edits: 12 host suites passed with pinned TypeScript5.9.3 and NODE_PATH cleared; `git diff --check` passed. The SVG was parsed and its rendered preview inspected. The new tests execute real component methods under native doubles and cover request replacement/detach, byte views, invalid names, failure races and cache eviction. Official SDK/lint/HAP/device, keyboard and screen-reader checks remain unrun.

Additional official references: [Button](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-button.md), [accessibility](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-accessibility.md), [Prop synchronization](https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-prop.md).

## Checkpoint 3: offline archives, safer caches and persisted reduced motion

### Offline gacha

The local archive view and UIGF import/export are accessible without login. Explicit archive selection persists independently of the authenticated refresh UID; ordinary loads do not create empty or logged-in archives. Page/account/archive generations fence stale progress, history and picker callbacks. Import/export have a 32MiB bound and exact I/O byte-count checks; UTF-8 output is checked before reporting success. The real existing UIGF service is exercised under repository/native doubles, including long string IDs. This does not restore selective/versioned UIGF workflows, atomic multi-archive transactions or background parsing; the baseline synchronous codec remains.

### Cache reliability

StandardIconService now validates path segments, checks directory/file types, coalesces in-flight requests, retries transient failures and revalidates evictable cache files. HTTP responses are bounded at 8MiB with PNG signature/size checks (not full image decoding). OS-unique staging directories, checked writes, fsync and same-filesystem rename avoid publishing partial downloads. Raw metadata/splash writes also stage checked, closed files before publication; a failing second write cannot truncate an existing image. Only each operation's own staging directory is cleaned.

### App-level reduced motion

A persisted app.reduce_motion switch is restored after backup recovery and before Index loads. Central Motion transitions/delays/spring interpolation, PageContainer and QTapButton honor it. This is an app preference, not OS-setting integration. Direct effects in PressCard, portions of Index/HomeGachaCard, RiskVerifyModal and WallpaperLayer still need reactive integration; the setting is accurately worded as reducing effects rather than disabling every animation.

### Verification

Fresh aggregate: 15 host suites passed with TypeScript5.9.3 and NODE_PATH cleared. Focused coverage includes 18 offline-gacha tests and 22 StandardIconService cases, plus production preference/startup/settings and raw-cache short-write regressions. New cache tests use actual host filesystem operations with HTTP doubles. App-resource references in changed ArkTS files resolve; diff whitespace checks pass. Official native compiler/lint/HAP/device/account checks remain unrun.

Additional API evidence: [file I/O](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-core-file-kit/js-apis-file-fs.md), [HTTP](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-network-kit/js-apis-http.md), [curves](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/js-apis-curve.md). Used additions remain below minimum API24; maxRedirects is API23 and stepsCurve is API9.


## Checkpoint 4: motion consumers and public game-launch lifecycle

Reduced-motion preference now reaches PressCard, Index navigation/sidebar/visual transitions, HomeGachaCard paging/indicators, RiskVerifyModal visual effects and wallpaper fades. Risk verification HTML, protocol and Web-controller callbacks remain unchanged. WikiAvatarPage paging also uses zero-duration non-physical curves when reduced. Native animation interruption still needs device observation. Other scroll edge effects, background video and system-native defaults are not claimed disabled.

Public game-entry editing/clearing is disabled during a launch request. Duplicate launch requests, stale results after page detach/remount and unexpected launch rejection are handled. Bounded text fields are enforced in both UI and service validation; no game scheme, installed-package discovery or Windows launch support is invented. Theme resources now own the edited card shadows and verification-panel colors.

The exact staged snapshot for this checkpoint passed 17 host suites, independently of simultaneous uncommitted UIGF/snapshot work. Focused new tests execute launch interruption/repeated-action paths and motion consumer policies. Full-resource reference checks and diff whitespace checks pass.

Native build and HAP validation succeeded for the earlier exact checkpoint `77304749bbb605108d05cf8c6f99f84d96ebdd2e`: clean official SDK build and verified unsigned HAP minimum API24/target26. Correction: native lint JSON reports 0 errors, 45 warnings and 1 suggestion, but the complete scan log contains internal checker failures on 36 distinct files. Lint coverage is incomplete; this must not be described as a clean lint pass. The full count/canary/warning evidence is recorded in NATIVE_VALIDATION_RECONSTRUCTION_2026-10-05.md. That result does not automatically validate this later checkpoint or device behavior.

## Checkpoint 5: selected UIGF transactions, asset repair and truthful lint enforcement

UIGF preview parses once, retains bounded validated data until confirmation, supports UID selection and commits all selected archives in one synchronous transaction. Cancellation/account/page changes dispose the preparation. Selected v4.2 export preserves records; all seven existing input versions remain supported. Seventeen focused selective-import tests and twenty-one offline tests pass. Seven target-version exporters, background parsing and additional Beyond subpool modeling remain later work.

Eight previously corrupt bundled .png files are repaired with validated exact/canonical source assets; two unavailable monster-art paths containing 404 HTML are removed instead of substituting a wrong monster. Metadata identity remains unchanged, so missing artwork uses existing fallback behavior. All 3,752 remaining PNGs passed full CRC, inflate and image decode audits. Canonical white element glyphs have a theme-aware dark backplate for contrast; actual device rendering is still unverified. Producer repository fixes are separate local changes, not yet published.

The public-launch/motion code now uses the correct Swiper.effectMode API; official compiler checking caught and corrected the earlier uncompiled edgeEffect typo. The staged production candidate including selected UIGF passed native compilation after this fix. Exact commit-level revalidation is recorded separately after commit.

CI now verifies the exact approved CLT downloads and HAP metadata, and rejects missing/stale/malformed scan evidence and internal scanner crashes. The original native lint report remains explicitly INCOMPLETE: zero reported errors did not establish complete coverage because the SDK rule crashed on 36 files. No other rules/files are hidden to turn that original report green. A separately tested equivalent replacement for the broken rule is being developed in a following checkpoint.

Checkpoint 5 candidate verification: 19 frozen host suites passed; clean official assembly succeeded in 23.170 seconds, all 33 tasks executed. All staged production changes were byte-compared with that built snapshot before committing. Native lint for these later edits is not claimed complete.

## Checkpoint 6: atomic game-data cohorts and verified CDN routing

The old in-place updater is replaced. One trusted Git revision is pinned per operation; required metadata and every declared PNG are bounded/validated, and raw-byte SHA256 receipts are checked before publishing an immutable cohort through an atomic pointer. Existing live files are never unlinked before replacement. Startup pins one verified cohort for the whole process, so consumer caches and multi-await readers cannot mix versions. Reset schedules the bundled cohort for next startup; rollback revalidates the previous cohort; both preserve immutable and legacy bytes. Writer/source/reset admission, disk quota (including orphan staging), symlink checks and late read-only worker receipts are enforced.

Startup awaits cohort selection after backup recovery and before metadata consumers. Settings separates active versus saved-next versions, requires restart, shows source errors, fences detached/duplicate actions, and offers explicit reset/rollback confirmation. There is no process-death queue/resume, reuse, old-snapshot garbage collection or download cancellation yet; updates remain foreground operations. Local integrity receipts are not publisher signatures.

The corrected local data repository commit `4cd6f6fe0e9fae5e8a0cd7cb936ca3bd6d898398` validates as 3,769 payloads / 241,295,126 bytes, with raw size/hash and PNG/model checks. It has not been published. Existing public main `c53167c9` contains bad PNG bytes and is correctly rejected while the old active/bundled cohort remains usable. Publishing the separately delivered data repair is necessary before the default online release passes strict validation.

StandardIconService now follows only the verified one-hop HTTPS api.snaphutaorp.org → static.snaphutaorp.org redirect with the exact same path; arbitrary redirects remain rejected. It uses the seven canonical upstream element filenames while retaining compatible local names. Live read-only GET confirmed the 302→200 source behavior; 69 deterministic service cases cover acceptance/refusal/cache cases.

Verification: 21 frozen host suites pass, including 33 cohort cases, nine settings/startup flow checks and 69 icon cases. Independent review passed five extra Store fault groups covering ten publication fault placements. Official clean assembly succeeded in 25.060 seconds (33 tasks:32 executed,1 up-to-date). All 4,045 staged production input files were byte-compared with that successful snapshot. HAP CRC and packaged API24/26/device types passed; unsigned HAP SHA256 `1b2ba4542e422a9f52db1658a44e1b84f4548dd15892bc987db44d6d95de350c`. Native lint coverage remains subject to the separately documented SDK defect; no device/account/animation interruption test is claimed.

## Checkpoint 7: empirical wish prediction and cloud-session ownership

The selected wish pool can request the same empirical distribution used by the pinned Windows implementation. Predictions condition on the observed remaining sample tail and show next-pull probability, modal pull and bounded cumulative probability. Weapon pity is 80; the supported other five-star pools use 90. Unknown pools, invalid distributions and exhausted samples are unavailable rather than replaced with invented theory. Pool/archive/history/session ownership prevents stale results, and the UI states that this is a sample-based estimate, not an UP guarantee.

Cloud session loading/refresh is coalesced, durable writes are serialized, and login/logout/unregister races cannot restore or clear a newer session. Pure prediction, production UI and controlled cloud race tests cover these paths; no real account or live cloud write was used.

The SDK's broken no-dynamic-delete rule has one mandatory equivalent-or-stricter AST gate using the actual ArkTS parser. It rejects ambiguous syntax and missing parsers, includes valid/invalid/class-initializer mutations, and runs in the real CI lint workflow. No other native rule is disabled. The next native rule, NoUnsafeAssignmentCheck, still crashes on 39 of the 189 scanned production files. Native lint therefore correctly exits with failure and remains INCOMPLETE. The runner preserves old evidence across filesystems and rejects concurrent ownership rather than losing logs.

Verification: 25 frozen host suites passed. Clean official assembly succeeded in 23.907 seconds with all 33 tasks executed; staged production inputs were byte-compared with that built snapshot. HAP CRC and minimum API24/target26 validation passed. The final log-preservation helper changes were separately retested after that build and do not change production code. Device, account and full native-lint acceptance remain outstanding. The accompanying 32-item reconstruction matrix separates current functionality, partial work, missing work and the five explicitly excluded Windows-only groups; it is not a percentage of the entire application.
