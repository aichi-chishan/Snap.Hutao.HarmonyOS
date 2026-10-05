# Linux 构建环境与 API 24 兼容基线

本次验证日期：2026-10-02。工程采用 API 26 SDK 编译，最低运行版本为 **HarmonyOS 6.1.1（API 24）**，并不是 Android API 24。

## 固定版本

| 组件 | 验证版本 |
| --- | --- |
| Linux 主机 | x86_64 |
| HarmonyOS Command Line Tools | 26.0.0.821 Release |
| 内置 HarmonyOS SDK | 26.0.0 Release / Ohos_sdk_public 26.0.0.105 |
| Hvigor | 6.26.4 |
| CodeLinter | 6.0.240 |
| OHPM | 26.0.0.630 |
| 工具包内置 Node.js | 24.14.1 |
| DevEco CLI | 1.3.4 |
| HarmonyOS Emulator 命令行工具 | 26.0.0.400 |
| JDK | OpenJDK 17.0.20 |
| Hvigor 包管理器 | pnpm 10.28.2 |

工具包版本从解压后的 `command-line-tools/version.txt` 核对；Node、Hvigor、CLI 和 Java 均已实际执行版本命令。

华为官方 [API 24 版本概览](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-611) 确认：API 24 Release 对应 HarmonyOS 6.1.1，SDK 基于 OpenHarmony 6.1.1.125，发布于 2026-05-26。工程现有 API 26 代码采用运行时判断与 API 24 回退，不能把最低版本改成 API 26 来掩盖兼容问题。

## 工具获取与完整性

常规安装从华为 [Command Line Tools 下载说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-commandline-get) 进入官方站下载。SDK 已包含在工具包内，Linux 使用 x86_64 版本。当前下载中心要求华为开发者登录，应通过正常登录下载，不能以未核验镜像代替。

本次复用了项目已成功运行的 CI 工具包：`aichi-chishan/snap-hutao-data` 的 `clt-26.0.0.821` release。来源由本项目 GitHub Actions 构建日志核对，分片经 GitHub release asset 的 SHA-256 校验后拼接解压。此包仅用于该项目构建，不随应用或源码分发。

| 分片 | SHA-256 |
| --- | --- |
| `clt-part-00` | `2cb88715aa489620da78bd664660af97fc3b645320e998ae4fedd33e8b2c736d` |
| `clt-part-01` | `5f44978744f1c3d8ef82175963fb0087a7e831ac48f5b7cbe36668b8b3e41838` |

DevEco CLI 使用华为官网公布的 `@deveco/deveco-cli` npm 包，锁定 1.3.4；安装到独立工具目录，不修改仓库源文件或系统全局工具。

## 构建命令

将下列占位路径替换为自己的工具位置。在项目根目录执行；如果已有本地签名配置，保留已有 `build-profile.json5`，不要覆盖。

```bash
# 仅首次、且不存在本地构建配置时执行。
test -f build-profile.json5 || cp ci/build-profile.ci.json5 build-profile.json5

export DEVECO_CLI_CLT_PATH="<工具包解压目录>/command-line-tools"
export DEVECO_SDK_HOME="$DEVECO_CLI_CLT_PATH/sdk"
export JAVA_HOME="<JDK17目录>"
export PATH="$DEVECO_CLI_CLT_PATH/bin:$DEVECO_CLI_CLT_PATH/tool/node/bin:$JAVA_HOME/bin:$PATH"

ohpm install --all
hvigorw assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

也可以使用 `devecocli build --product default --modules entry@default --build-mode debug` 完成依赖安装和构建。首次运行需要联网下载 OHPM 测试依赖及 pnpm。受限工作区可将 `HVIGOR_USER_HOME`、`TMPDIR` 指向工具目录中预先创建的可写子目录；不需要覆盖用户的 `HOME`。

仓库的 `ci/build-profile.ci.json5` 无签名凭据；产物为 `entry/build/default/outputs/default/entry-default-unsigned.hap`。签名配置、密钥、设备证书和本地绝对路径均不得提交。

## 本次验证与环境问题

### 本次收尾工作树验证

2026-10-02，对 `codex/api24-port-2026-10-02` 收尾工作树执行直接 Hvigor 和原生 CodeLinter：

| 检查 | 结果 |
| --- | --- |
| `assembleHap` | `BUILD SUCCESSFUL`，退出码 0，21.561 秒 |
| ArkTS 编译警告 | 542 条，仍需后续整理；不代表零警告 |
| CodeLinter JSON 报告 | 0 个 error、46 个 warn、1 个 suggestion |
| 未签名 HAP 大小 | 251548793 字节 |
| 未签名 HAP SHA-256 | `44897cda1e842fce2900fef8d28e59a2aae60a7b39689f65430fff489a9c9a72` |
| HAP 实际最低 / 目标 API | `60101024` / `260000026`，`Release` |
| HAP 设备类型 | `phone`、`tablet`、`2in1` |

CodeLinter 的 47 项非错误结果均为性能警告或建议，涉及状态访问、组件封装/复用、日期对象、模糊和 Swiper 预加载。HAP 内 `module.json` 已实际读取核对，未把构建配置文本当作产物验证。上面的哈希仅标识本次本地产物，重新构建可能因调试信息或时间戳变化产生不同哈希。构建日志、完整 lint 报告和 HAP 留在构建工作区，不加入源码仓库。

### 基线与工具限制

- 在独立工作树验证了原始提交 `7153f7050083275d174ce63fa0a60d5b7094e628`：ArkTS 编译和 HAP 打包完成，直接 Hvigor 命令退出码 0，日志为 `BUILD SUCCESSFUL`。基线未签名 HAP 约 240 MiB。
- 已打开基线 HAP 内的 `module.json` 核对实际打包结果：`minAPIVersion=60101024`、`targetAPIVersion=260000026`、`apiReleaseType=Release`，设备类型为 `phone / tablet / 2in1`；这些编码由对应的 `6.1.1(24)` 与 `26.0.0` 构建配置生成。
- 此运行环境的解压器将 ZIP 中的 Unix 符号链接落成了纯文本，导致工具包内 `npm` 无法运行。按照 ZIP 中的链接属性恢复了 128 个包内链接；恢复前检查了文件内容匹配，且所有链接目标均限制在工具包根目录内。遇到同类问题，应使用保留 Unix 链接的解压器，不能把链接目标文本当脚本执行。
- 首次解压中两个较大的二进制不完整，已从校验通过的 ZIP 重新提取。随后对工具包全部 104374 个普通文件核对 ZIP CRC，全部匹配；符号链接另行验证。
- 本环境 OpenJDK 首次启动未找到 `libjli.so`，设置局部 `LD_LIBRARY_PATH="$JAVA_HOME/lib"` 后正常运行。
- 严格沙箱没有提供 Hvigor 查询进程内存所需的接口，会报 `uv_resident_set_memory`；在获准的构建环境运行同一命令后成功。不能将该环境错误解释为源码编译失败。
- DevEco CLI 1.3.4 的包装构建在实际 `BUILD SUCCESSFUL` 后曾返回 1；因此本次以直接 Hvigor 退出码、完整日志和实际 HAP 三项联合判断构建成功，不只读取 CLI 尾部信息。
- 在可运行原生检查器的构建环境复核基线 CodeLinter：0 个 error、36 个 warn、1 个 suggestion；底层场景日志确认扫描 158 个源码文件。严格沙箱曾生成不可靠的 `[]` 空报告，不能据此宣称通过。另在隔离工作树临时放入官方 MD5 违规样例，准确得到 `@security/no-unsafe-hash` 错误，验证检查器确实执行；探针已移除。该 SDK 的安全规则未识别同调用的 `@kit.CryptoArchitectureKit` 命名导入写法，因此安全规则结果仍需要代码审阅补充。
- Emulator 命令行工具已实际运行；官方镜像列表可查询到 2in1 的 `HarmonyOS 6.1.1(24)` Release（SoftwareVersion `6.1.0.125`）。当前未连接鸿蒙设备，没有可用签名材料，没有模拟器实例，且宿主没有 `/dev/kvm`。未下载镜像或接受模拟器协议。本次构建通过不等同于 API 24 真机或模拟器运行通过；安装、布局、网络登录、通知和后台行为仍需设备验收。

## 检查与验收

```bash
devecocli check lint
# 也可直接调用工具包内 codelinter，并保存完整报告。
codelinter --exit-on error -c code-linter.json5 -f json -o lint-report.json .
```

检查报告必须确认实际扫描了源码，并统计 JSON 报告中的 error 项；本版工具出现过报告含 error 而进程退出 0 的情况，不能只依赖退出码。DevEco CLI 1.3.4 对空报告曾显示 `Files checked: 0`，应结合原生 CodeLinter 场景日志中的 `File count` 和违规探针判断，不能单凭该汇总宣称完整检查通过。API 26 材质、枚举和设备能力调用必须检查运行时门控，并在 API 24 设备验证回退。未经运行验证的设备能力应在验收记录中明确标记，不能由编译结果推断成功。

仓库未跟踪的官方开发说明可以通过 `devecocli skills add --skill <名称> --path <独立工具目录>` 获取；本次获取了 `hmos-arkts-syntax-checker`、`hmos-arkui-develop-skill`、`hmos-arkui-mvvm-pattern`，按官方 OpenHarmony skill API 的 SHA-256 校验后放在工具目录，不写入仓库的 `skills/` 或修改 AI 工具配置。

## 2026-10-05：恢复环境与 fail-closed CI 门禁

对固定提交 `77304749bbb605108d05cf8c6f99f84d96ebdd2e` 的隔离快照，以同一 CLT 26.0.0.821 和已安装的 OpenJDK 21.0.12.1 完成了实际 clean + Hvigor 构建：退出码 0，33 个任务全部执行，23.540 秒。该结果验证 Java 21 可用于此次构建，不表示复现了历史 JDK 17 环境。实际 HAP 最低/目标 API 仍为 `60101024` / `260000026`，设备类型仍为 phone/tablet/2in1。真机、模拟器、签名和账号流程没有因此获得运行验收。

原生 lint JSON 返回 0 个 error、45 个 warn、1 个 suggestion，日志记录 182 个源码文件；但进一步审查发现 36 个文件检查发生 `getDeclaringMethod` 内部异常，因此**完整 lint 验证不通过**。独立官方 MD5 探针确实触发安全错误，工具仍返回 0；正数文件计数、完成提示、部分规则结果和进程退出码均不能掩盖扫描器内部异常。没有删除规则或忽略受影响源码来制造通过结果。

本次补充的 CI 工具：

- `ci/install-clt.sh` 只接受本节上方已经审核的 release 的完整 `clt-part-00` URL；不会从任意用户配置字符串盲目推导第二个分片 URL。其他来源或版本必须重新审核固定值
- 两个分片大小固定为 `1992294400` / `355587885` 字节，SHA-256 沿用上方记录；顺序拼接后实际核验的 ZIP SHA-256 为 `58da7359019e9360a8bb82da0cd1d3b3b26fedc338379f257849f2162e3ac1fc`。`ci/verify-clt.py` 在执行工具前核对大小、哈希、ZIP CRC、安全路径、包内符号链接及提取后 CRC
- `ci/run-native-lint.cjs <全新证据目录>` 直接运行原生 CodeLinter，隔离旧日志，并为当前项目与源码数量创建时间标记；`ci/check-lint-report.cjs` 拒绝缺失、空白、畸形、过期、其他项目、扫描不足、内部错误以及含 error 的报告。性能警告和建议本身不阻断
- `ci/check-hap.py` 拒绝缺失、空文件、损坏 ZIP 或最低 API、目标 API、设备类型不符的产物；构建直接使用 OHPM 与 Hvigor，不再依赖 DevEco CLI 包装器的返回码
- CI 的 lint/build 仍按 `DEVECO_CLT_URL` 配置选择性启用；未配置时跳过，不能把这种跳过称为原生验证通过。这里仅修改工作流源码，没有触发远程 Actions

`tests/lint-report-gate.cjs` 包含伪造成功退出码的错误报告、内部扫描异常、空/坏/旧报告及固定下载来源等回归；这些离线测试不替代真实原生扫描。

当前门禁保守拒绝空 findings 数组，包括实际上可能没有任何问题的工程；这是为避免把本版工具的不可靠空报告误判为通过。未来若要允许真正的零 findings，必须先增加与同次检查绑定的成功安全探针和完整扫描证据；不能仅放宽为空数组就通过。该限制不会改变内部检查异常必须阻断的规则。

### 单条规则的等价 AST 补充检查

进一步捕获原始异常栈后，确认本版 HomeCheck 0.9.0 的 `NoDynamicDeleteCheck` 在处理类字段初始化语句时，直接访问不存在的 CFG。只有这一条 `@typescript-eslint/no-dynamic-delete` 获准使用等价补充检查：配置中关闭该损坏的原生 matcher，`ci/run-native-lint.cjs` 必须先执行 `ci/check-dynamic-delete.cjs`，通过后才启动其余原生规则。

补充检查遵循 [TypeScript-ESLint 官方规则说明](https://typescript-eslint.io/rules/no-dynamic-delete/) 和[官方规则实现](https://github.com/typescript-eslint/typescript-eslint/blob/main/packages/eslint-plugin/src/rules/no-dynamic-delete.ts)：允许直接属性及字符串/数字字面量键，拒绝动态计算键；额外防止 TypeScript 类型断言包装绕过检查。它逐节点检查原始源码，不用正则删掉 struct、装饰器、UI body 或删除表达式。普通 TS/JS 使用固定 TypeScript 5.9.3，ETS 使用已校验 SDK 的原生 ArkTS parser，并合并 SDK 自身 OpenHarmony/HMS 语法配置以正确解析 HdsTabs。任何缺失的原生 parser 或语法歧义都会阻断生产 ETS 检查。

离线测试会明确跳过仅依赖原生 parser 的成功案例，并验证缺少 parser 时生产门禁确实拒绝；启用 CLT 的 lint job 会实际运行这些原生语法案例。有效/无效删除、类字段初始化、嵌套 UI 回调、畸形语法、字面量变动态键的变异以及真实 runner 的阻断链均有回归。

这个替代方案**尚未恢复完整原生 lint 覆盖**：移除第一个 matcher 的阻塞后，下一个 `NoUnsafeAssignmentCheck` 也出现相同 CFG 解引用错误。该规则和其他原生规则没有被关闭；内部错误门禁仍会失败。不得把补充 AST 检查通过或 JSON 的 0 error 写成完整 lint 通过。
