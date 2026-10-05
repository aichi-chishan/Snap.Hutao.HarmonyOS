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

Fresh aggregate: 15 host suites passed with TypeScript5.9.3 and NODE_PATH cleared. Focused coverage includes 17 offline-gacha tests and 22 StandardIconService cases, plus production preference/startup/settings and raw-cache short-write regressions. New cache tests use actual host filesystem operations with HTTP doubles. App-resource references in changed ArkTS files resolve; diff whitespace checks pass. Official native compiler/lint/HAP/device/account checks remain unrun.

Additional API evidence: [file I/O](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-core-file-kit/js-apis-file-fs.md), [HTTP](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-network-kit/js-apis-http.md), [curves](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/js-apis-curve.md). Used additions remain below minimum API24; maxRedirects is API23 and stepsCurve is API9.
