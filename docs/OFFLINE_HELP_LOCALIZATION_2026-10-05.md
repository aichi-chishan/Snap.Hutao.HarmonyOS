# Offline help and safe diagnostics reconstruction

## Implemented scope

This is a current-tree implementation, not a replay of the missing `53a813e` baseline or proof that a lost commit was recovered. The preserved help bundle was inspected, but its old article bodies describe unavailable global shortcuts, web windows, declarative data tools and other features. Those claims were deliberately not copied.

Seven accurate app-authored articles are packaged in Simplified Chinese, Traditional Chinese and English: accounts/sign-in, local imports, game-data updates, backups/recovery, daily notes/widgets, device/game-entry limits, and diagnostics/privacy. Each contains four actionable steps. Current-source references include `UserPage`, `UigfService`, `UIIFCodec`, `BackupService`, `FormSnapshot`, `GameDataUpdater` and `GameLauncherService`.

The language preference applies only to help and explicitly integrated common outcome messages. It does not claim whole-application localization or translate all third-party game text. Unsupported system languages fall back to English with an explicit visible notice. The 12 other historical article languages remain deferred until their bodies are rewritten against current functionality.

## Parent integration contract

- Named component export: `HelpPage` from `entry/src/main/ets/pages/HelpPage.ets`
- Route: `pages/HelpPage`; page supports `embedMode`
- Parent owns route registration, Index navigation/wide-content integration and Settings entry
- Replace the old direct Settings diagnostic-copy action with navigation to HelpPage to retain preview-before-copy behavior
- `AppLocaleService.preference()` returns `system`, `zh-Hans`, `zh-Hant` or `en`
- `AppLocaleService.current()` resolves to the three packaged locales; `usingFallback()` discloses an unsupported system language
- `AppLocaleService.select(value)` validates the exact selection, uses the existing preferences store and increments `helpLocaleVersion` in AppStorage
- The saved preference uses `app.help_locale`. The existing preferences helper flushes asynchronously; persistent-storage failures follow that helper's existing logging behavior. This setting intentionally does not claim to change the whole app or the system language
- `i18n.System.getSystemLanguage()` is available from API 9 in the local SDK declarations; no API 26-only dependency or extra permission is introduced
- `CommonOutcomeId` / `CommonOutcome` and `CommonOutcomeText.text(outcome, locale)` are pure, typed APIs. They do not infer translations from arbitrary server/exception strings. The import-completion count is bounded and substituted once

## Search and ownership

Search is offline with no repository, account or network dependency. Locale normalization caps cached indexes at three and shares seven common-language text entries. Every returned article and its steps array are detached. Search is case/diacritic/letter folded, ANDs up to 12 terms and processes at most 120 query code units. Display text and IDs are never folded. Chinese, Traditional Chinese and English text plus stable protocol terms are searchable regardless of display locale.

Locale changes preserve the query and article identity. Changing query, selection, issue type or environment inclusion invalidates an obsolete preview. Hide/disappear discards the preview and invalidates asynchronous results. Duplicate clipboard writes are blocked, including while an earlier copy is settling across detach/remount. Success/failure from stale requests is not presented on a newer page session. Routes resolve from the canonical catalog, not a caller-mutated search result.

## Diagnostic privacy

Opening help, searching and selecting an article do not collect diagnostics or read accounts, device diagnostic fields, clipboard contents or raw logs. Locale preference/system-language lookup is the only contextual read on opening. No wallpaper component is mounted, so opening help does not initiate wallpaper network work.

The user selects a problem type, optionally enables environment fields, then explicitly generates a preview. The default payload contains fixed feature/outcome codes and generation time. Optional fields are limited to sanitized app version, API level, device category and theme. Full OS identifiers, serial numbers, package version codes, credentials, UIDs, personal records, network account data and logs are excluded. Missing or invalid optional data is shown as `unknown`.

Copying is a separate explicit action. The payload is reconstructed from an allowlist again immediately before clipboard writing; arbitrary text and extra object fields cannot be copied through this API. Clipboard read and automatic upload are absent. No external feedback is submitted. The existing `SupportService.openIssues` remains an explicit external-link action; the help page does not call it.

The legacy `SupportService.copyDiagnostics` is sanitized for compatibility; the parent Settings integration must route users into the preview UI instead. Full data backups remain credential-bearing exports and are clearly distinguished from diagnostics in the help text.

## Verification

`node tests/help-documentation-localization.cjs`: 15 tests passed at the source handoff. Coverage includes seven-article locale completeness, fallback/script precedence, search bounds/accent folding, detached-result isolation, typed message coverage, malicious diagnostic-field inputs, opening side effects, optional environment reads, duplicate copies, delayed/rejected requests, detach/remount, page navigation, and strict TypeScript checking against typed platform stubs.

`git diff --check`: passed at the source handoff.

These host tests do not prove native ArkTS compilation or real-device behavior. Native builds are coordinated by the parent. Clipboard permission prompts, OS background behavior, phone/tablet/2in1 layout, focus/accessibility and persistent preference failures still need device acceptance. No live account, network dependency, GitHub write, device operation or commit was used for this implementation.
