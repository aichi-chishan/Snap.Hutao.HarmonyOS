# Native validation: checkpoint 7730474

> Correction after full native scan-log audit: the build and HAP checks passed, but lint coverage is INCOMPLETE. The JSON reports zero errors, yet the native checker logged internal getDeclaringMethod failures on 36 distinct files. A report count and successful canary do not prove complete per-file checking.

Source commit: `77304749bbb605108d05cf8c6f99f84d96ebdd2e`. Built from a separate git-archive snapshot, excluding active uncommitted work. All 4,105 frozen input hashes remained unchanged after dependency installation and build. Only the disposable snapshot received the CI unsigned build profile. The original repository and signing configuration were untouched.

## Results

- Clean: exit 0. All 33 subsequent assembly tasks executed, none up-to-date.
- Direct Hvigor assembleHap: exit 0, BUILD SUCCESSFUL in 23.540 s.
- Environment: verified CLT 26.0.0.821; Node 24.14.1; Hvigor 6.26.4; CodeLinter 6.0.240; OHPM 26.0.0.630; pnpm 10.28.2; installed OpenJDK 21.0.12.1. This is an actual successful Java 21 build, not a claim that the historical Java 17 environment was reproduced.
- Native CodeLinter scene included 182 source files; JSON reports 0 errors, 45 warnings and 1 suggestion. Internal file-check crashes affect 36 distinct files. Other checks continued, including 27 findings on five affected pages, but full coverage is unproven. The original JSON/count-only gate was insufficient and must also reject internal checker failures.
- Separate canary snapshot: official vendor MD5 example detected at line 2 as @security/no-unsafe-hash; 183 files scanned. Native checker misleadingly returned 0, while the independent JSON gate correctly returned 1. Temporary canary removed; evidence retained. Canary never entered the production build snapshot or HAP.
- HAP: 251633831 bytes; SHA256 `09ac0b0970d31839f2f79333f461c8f51271c972905a53b2286ace89f033dd74`; all archive CRCs passed.
- Actual packaged module.json: minAPIVersion 60101024, targetAPIVersion 260000026, apiReleaseType Release; deviceTypes phone/tablet/2in1.
- No device installation, signed build, emulator run, account login or UI rendering validation was performed.

## Warnings

562 ArkTS warnings:

- 418 exception-handling notices
- 72 deprecated API uses
- 19 system-capability notices
- 14 API 26 declaration notices above minimum 24
- 18 exported @Entry preview notices
- 17 @Entry/@Prop composition notices
- 2 device-platform notices
- 2 READ_PASTEBOARD permission notices

Additionally, the expected unsigned-build warning says no signingConfig was found.

Native lint 46 findings are all performance-related: 21 state reads in loops, 14 component overuse, 7 reuse recommendations, 2 Date allocation notices, 1 blur recommendation, 1 Swiper preload recommendation.

Caveats for warning triage: three Circle.fill ResourceColor warnings arise from the new CircleAttribute override annotated 26; the inherited CommonShapeMethod.fill(ResourceColor) is already annotated 11 in the same SDK. Do not infer actual API 24 runtime incompatibility from that overload warning alone. Material-specific warnings still require checking existing runtime gating. Window background/system-bar availability and clipboard permission behavior require platform review and device validation.
