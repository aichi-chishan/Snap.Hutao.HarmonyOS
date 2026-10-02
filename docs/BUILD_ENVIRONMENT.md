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
