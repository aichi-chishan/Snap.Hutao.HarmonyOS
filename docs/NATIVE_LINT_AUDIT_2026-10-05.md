# Native lint audit and Promise binding verification

## Outcome

The 12 `@security/no-unsafe-*` names are **correct vendor identifiers**. Renaming or deleting them is not a justified fix. The approved CodeLinter 6.0.240 package has inconsistent engine registries; full native lint remains **INCOMPLETE / FAILED**.

The three checkpoint-12 `@typescript-eslint/await-thenable` errors were caused by the checker retaining optional Promise types despite synchronous source guards. `AwaitThenableCheck.isNonPromise()` accepts only a direct `ClassType` named `Promise` or `PromiseConstructor` (vendor lines 99–101), not a union. Two services now bind an explicitly non-optional Promise before awaiting, preserving the original request, coalescing, revision checks, and identity-based cleanup. No assertion, extra Promise wrapper, rule suppression, or SDK modification was used.

## Exact identifier mapping

Every configured identifier maps to itself. Huawei's [official recommended rule list](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-coderlinter-recommended-rules) and installed vendor documentation agree. The semantics below are summarized from the installed vendor rule documentation, not an assertion of exhaustive runtime detection.

| Existing and official ID | Intended check |
| --- | --- |
| `@security/no-unsafe-aes` | AES ECB mode |
| `@security/no-unsafe-hash` | MD5/SHA1 hashing |
| `@security/no-unsafe-mac` | Weak MAC digest, such as SHA1 |
| `@security/no-unsafe-dh` | Weak DH agreement, including DH_modp1536 |
| `@security/no-unsafe-dsa` | DSA modulus below 2048 or MD5/SHA1 digest |
| `@security/no-unsafe-ecdsa` | ECDSA with SHA1 digest |
| `@security/no-unsafe-rsa-encrypt` | Weak RSA modulus, PKCS1 padding, or weak OAEP digest/MGF digest |
| `@security/no-unsafe-rsa-sign` | Weak RSA modulus or MD5/SHA1 digest/MGF digest |
| `@security/no-unsafe-rsa-key` | RSA modulus below 2048 |
| `@security/no-unsafe-dsa-key` | Weak DSA key, including DSA1024 |
| `@security/no-unsafe-dh-key` | Weak DH key, including DH_modp1536 |
| `@security/no-unsafe-3des` | 3DES ECB, DES, and RC4 |

All 12 exist in `performanceAgent/tsauditrules.json` and its security registry. All 12 are absent from `arkPerfCheck/ruleSet.json`, which `homecheck/lib/utils/common/ConfigUtils.js:167–171` uses to validate explicit names. HomeCheck's `CheckerIndex.js:341–351` still includes implementations for the first 11; it has no 3DES entry. This is an inconsistent vendor bundle, not evidence of 12 invalid project names. Those registry/validator files, the unsafe-assignment checker, and the ESLint dispatcher were compared byte-for-byte with the already downloaded approved CLT ZIP; checked bytes matched. The bundled ESLint dispatcher disables these migrated rules; its presence alone does not prove that engine runs them. Existing MD5 detection is consistent with the separate performanceAgent/HPAudit implementation.

The existing exceptions remain unchanged: hash is off only in `DsSigner.ets`; RSA key/encryption checks are off only in `RsaEncryptor.ets`; MAC stays warning-level. No unrelated HUKS/KDF/SM2 rule is an equivalent replacement. Replacing explicit rules with a security preset would not preserve all severity and override behavior and is not a demonstrated repair.

## Reproduction and evidence

Audit workspace, adjacent to the repository: `native-lint-audit-20261005/`.

- `baseline-evidence/` preserves original checkpoint-12 JSON, logs, process marker, the two original sources, and source SHA-256 values. Original JSON: 3 errors, 44 warnings, 4 suggestions. Original errors: AnnouncementService lines 106/146 and HutaoCloudService line 113
- `await-bindings-snapshot/` is an isolated copy of frozen `precommit-12`, excluding old `build` and `.hvigor` output; only the two service refactors and focused host tests were added
- `promise-bindings.patch` preserves the minimal production-source change
- `native-await-bindings/` and `native-await-bindings.log`: 231 source files; 0 JSON errors, 44 warnings, 4 suggestions; native process exit 0 but independent gate exit 1 because all 59 internal/configuration errors remain (41 file crashes + 18 invalid-rule occurrences)
- `native-build.log`: clean-output isolated build passed, 34 tasks executed, none up-to-date, `BUILD SUCCESSFUL` in 29.503 s. No signed/device/runtime claim
- `regional-host-focused-final.log`: 16/16 tests pass, including list/body request sharing, rejection cleanup, fresh retry, and retaining a replacement Promise after an older completion
- `cloud-ownership-host-focused.log`: 15/15 tests pass, including coalesced refresh rejection, cleanup, retry, revision preservation, and strict host type checking
- `cloud-protocol-host.log`: PASS
- `hap-check.json`: isolated unsigned HAP passed CRC/API/device validation; 254479798 bytes, SHA-256 `51f34ba82c93d7147ba6df4970cef7e028d9b0d63e3e1ce9bf7fecdc8e51b210`
- The focused rejection/cleanup/coalescing cases are now also included in the working-tree test sources without replacing prior mocks. `working-regional-host-focused-final.log`: 16/16 pass; `working-cloud-ownership-host-focused-final.log`: 15/15 pass. Earlier 15/14 baseline runs remain preserved separately

One initial added announcement fixture expected its raw synthetic transport error; the real ApiClient correctly wrapped it in a network error. The assertion was corrected to accept the production error boundary, and the final 16-test run passed. The initial failure log is preserved.

## Remaining native scanner and gate limits

Preserved diagnostic stacks in the SDK evidence directory identify `NoUnsafeAssignmentCheck.js:74`: field-initializer statements emitted by `File2Check.js:186` can lack a CFG. The matcher dereferences it before checking assignment kind or language. Its error reporter then repeats the same unguarded dereference in `matchCommon.js:143`, escaping to the per-file catch in `CheckEntry.js:125`. This explains lost per-file coverage; it is not repaired by the Promise refactor. No additional matcher was disabled.

The current gate correctly rejects stale/missing/malformed/empty evidence, foreign projects, low source counts, scanner errors, and JSON errors, while allowing warnings/suggestions. Its existing report-canary fixtures use synthetic JSON; the separately preserved real MD5 canary proves only that example was detected. Full coverage still requires fresh positive/negative native canaries for all 12 rules, exact file-override isolation, and both legacy default imports and the app's named `@kit.CryptoArchitectureKit` imports. A previous named-import detection gap remains unproven as fixed. The gate currently reads HomeCheck's scan log, not complete independent per-engine success records, so a nonempty JSON report is not proof of every configured engine/rule having completed.
