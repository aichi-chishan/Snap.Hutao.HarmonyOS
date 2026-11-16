# 维护者交接

工程对照 Snap.Hutao.Remastered 2.0.2.0（`3b7475e`），最低和目标系统均为 HarmonyOS API 26，设备类型为 phone、tablet、2in1。先从[工程地图](ARCHITECTURE.md)找到页面与服务；涉及导入、导出、账号或还原时查[数据与互通](DATA_AND_INTERCHANGE.md)。

## 新环境构建

安装 DevEco Studio 或 HarmonyOS Command Line Tools，准备 API 26 SDK、OHPM、Hvigor、Node.js 24 和 Python 3.11+。CI 使用 JDK 21，主机测试编译器固定在 [ci/package-lock.json](../ci/package-lock.json)。日常编译需要当前源码和随包资源，更新资源时再检出参考仓。

Windows PowerShell，在仓库根目录运行：

```powershell
# 将占位符改为维护者自己的安装位置，仅设置当前进程环境。
$env:DEVECO_HOME = '<DevEco Studio 安装目录>'
$env:DEVECO_CLI_STUDIO_PATH = $env:DEVECO_HOME
$env:DEVECO_SDK_HOME = Join-Path $env:DEVECO_HOME 'sdk'
$env:JAVA_HOME = Join-Path $env:DEVECO_HOME 'jbr'
$Ohpm = Join-Path $env:DEVECO_HOME 'tools/ohpm/bin/ohpm.bat'
$Hvigor = Join-Path $env:DEVECO_HOME 'tools/hvigor/bin/hvigorw.bat'

if (!(Test-Path -LiteralPath 'build-profile.json5')) {
  Copy-Item -LiteralPath 'ci/build-profile.ci.json5' -Destination 'build-profile.json5'
}
& $Ohpm install --all                     # 首次准备；离线且依赖齐全时跳过
& $Hvigor assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

Linux / CLT：

```bash
export DEVECO_CLI_CLT_PATH='<command-line-tools 根目录>'
export DEVECO_SDK_HOME="$DEVECO_CLI_CLT_PATH/sdk"
export JAVA_HOME='<JDK 21 根目录>'
export PATH="$DEVECO_CLI_CLT_PATH/bin:$DEVECO_CLI_CLT_PATH/tool/node/bin:$JAVA_HOME/bin:$PATH"
test -f build-profile.json5 || cp ci/build-profile.ci.json5 build-profile.json5
ohpm install --all                        # 首次准备；离线且依赖齐全时跳过
hvigorw assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

构建输出在 `entry/build/default/outputs/default/`。如需设备调试，在 DevEco Studio 的 Signing Configs 中配置自己的调试证书、Profile 和密钥，并将签名配置关联到 `default`。根目录构建配置、签名文件和 `local.properties` 由 Git 忽略。

Windows 若提示资源转码库装载错误 126，先确认资源文件在当前用户下可读，并在当前 PowerShell 会话补充 SDK 的 DLL 目录后重新运行 Hvigor。

```powershell
$SdkDefault = Join-Path $env:DEVECO_SDK_HOME 'default'
$env:Path = (Join-Path $SdkDefault 'hms/toolchains/lib') + ';' +
  (Join-Path $SdkDefault 'openharmony/previewer/common/bin') + ';' + $env:Path
```

## 验证和交付

1. 首次准备主机测试环境时执行 `npm ci --prefix ci --ignore-scripts`。此后用 [TESTING.md](TESTING.md) 中的命令运行全部 Node/SQLite 回归。
2. 运行原生 ArkTS 检查和 Hvigor 构建。从当次生成的无签名 HAP 执行 `python ci/check-hap.py entry/build/default/outputs/default/entry-default-unsigned.hap`，检查 CRC、API 和设备类型。
3. 推送前核对 `git diff --cached --stat` 和 `git diff --cached --check`。将自己的照片、文件选择器转储、数据库和导出备份留在 `.local/`。软件源带来的公共资源在对应目录记录版本、来源与许可。
4. GitHub Actions 的 `logic`、`meta` 检查随 main 推送和 PR 运行；配置 `DEVECO_CLT_URL` 后还会运行 `lint`、`build`。Linux CLT 的实际版本和校验值见 [install-clt.sh](../ci/install-clt.sh) 与 [verify-clt.py](../ci/verify-clt.py)。

## 更新游戏数据

以下是对已准备在本地的来源做离线检查；`--source` 分别要求 Genshin 根目录或 CHS 目录，不能混用：

```bash
python3 scripts/update-compact-metadata.py --source '<Snap.Metadata 导出>/Genshin' --revision '<40位提交号>' --include-challenges --check
python3 scripts/generate-game-locales.py --source '<Snap.Metadata 导出>/Genshin' --windows-strings '<Windows源码>/Resource/Localization' --upstream-revision '<40位提交号>' --check
```

`--check` 返回差异时先审查来源、ID/曲线/材料引用及缺项。确认后，compact 脚本用 `--apply` 写回；语言脚本去掉 `--check` 生成。导出来源需要包含所有脚本要求的语言表、`ProfilePicture.json` 与 `Chapter.json`。完整规则见 [15 语言元数据说明](LOCALIZED_GAME_DATA_2026-11-11.md)。

通用素材/热更发布由独立的 [snap-hutao-data 数据仓](https://github.com/aichi-chishan/snap-hutao-data)维护：先对固定来源增量生成，再检查清单版本、大小与哈希，经审查后发布；不要在客户端占位页补胡桃云功能。仓内 [fetch-metadata-icons.py](../scripts/fetch-metadata-icons.py) 是针对固定角色/武器集合的补图工具，`--source` 要传 `Genshin/CHS`，不是任意新版本的全量同步器；它会联网，不属于离线回归。新增版本要先审查其固定 ID 和采集范围，不能裸跑默认的 ignored 路径。

语言/显示投影只改显示文本，不改业务 ID、原名、数值、归档或文件互通字段。保留未知条目和可解释占位，不能因上游缺翻译或缺图删用户记录。成就/祈愿数量是版本数据，不把旧测试清单中的固定数量当永久断言。

## 已验证与后续复测

- 发布时的主机测试、原生构建和 Linux CodeLinter 已知问题记录在[本轮验证记录](TESTING.md#2026-11-16-验证记录)。

- 在 MatePad Pro API 26 上复验了国服祈愿增量刷新、导出保存及重新读取。测试档案由 2,559 行归并为 1,616 条逻辑记录，其中常规祈愿 1,601 条、颂愿 15 条。读取视图保留了存档里的原始行。
- 性能对照各采集 10 次冷启动和 10 次预热后的祈愿页切换。系统冷启首帧中位数由 274 ms 变为 267.5 ms，祈愿卡数据发布中位数由 637.899 ms 变为 495.707 ms。测量所用包与原始口径见[性能复测记录](PERFORMANCE_RETEST.md)。
- 首次进入祈愿、角色和设置的懒加载，以及最近调整的图鉴、账号弹层、周期统计和小窗布局，是下一轮交互复测的重点。[测试说明](TESTING.md) 有对应步骤。
- 当前怪物图标回退涉及 `UI_ActivityIcon_GamblingChess_Hachi`、`UI_MonsterIcon_LavaTitan_01`、`UI_MonsterIcon_Samurai_Kairagi_05`。更新素材时随上游检查这些文件。武器背景和怪物掉落的 DisplayItem 映射已在仓内。
- [Linux 构建记录](BUILD_ENVIRONMENT.md) 保存 API 24 时期的环境；现行兼容版本以 [CI 工程模板](../ci/build-profile.ci.json5) 和打包清单为准。
