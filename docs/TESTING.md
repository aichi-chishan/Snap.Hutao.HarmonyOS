# 测试与验收

## 主机回归

在仓库根目录运行 Node.js 24。测试编译实际的 ArkTS 业务方法、模型和页面事件，并使用 SQLite 或系统 API 替身覆盖导入、计算、切换和取消等分支。

```powershell
npm ci --prefix ci --ignore-scripts
$env:TYPESCRIPT_PATH = (Resolve-Path 'ci/node_modules/typescript').Path
node tests/run.cjs
```

Linux 和 macOS 可执行 `TYPESCRIPT_PATH="$PWD/ci/node_modules/typescript" node tests/run.cjs`。已安装依赖后，整套主机回归可离线运行。单独运行某个 `tests/*.cjs` 或 `tests/*.mjs` 可缩短定位时间。例如，`node tests/gacha-logical-records.cjs` 覆盖 64 位 ID、历史重复、命名空间和超过十万条的分页边界。新增套件会由 [run.cjs](../tests/run.cjs) 自动发现。

## 原生验证

1. 使用 [API 26 工程模板](../ci/build-profile.ci.json5) 初始化新检出的本地构建配置，执行 `ohpm install --all`。
2. 运行 `hvigorw assembleHap --mode module -p module=entry@default -p product=default --no-daemon`。Windows 使用 `hvigorw.bat`。本地签名配置控制签名包的生成。
3. 在无签名构建环境执行 `python ci/check-hap.py entry/build/default/outputs/default/entry-default-unsigned.hap`，校验包完整性、最低/目标 API 与设备类型。
4. 原生 ArkTS 本地用例见 [entry/src/test](../entry/src/test)，设备侧用例见 [entry/src/ohosTest](../entry/src/ohosTest)。在 DevEco Studio 选择对应测试运行配置。

[CI](../.github/workflows/ci.yml) 在推送到 main 或提交 PR 时运行主机测试和仓库检查。配置了 `DEVECO_CLT_URL` 的仓库还会运行原生 lint 和无签名 HAP 构建。工具源及摘要固定在 [install-clt.sh](../ci/install-clt.sh) 与 [verify-clt.py](../ci/verify-clt.py)，lint 验收使用 [run-native-lint.cjs](../ci/run-native-lint.cjs) 的完整扫描报告。

## 交互复测

| 场景 | 观察点 |
| --- | --- |
| 冷启动、首次进入页面、返回 | 分开观察系统首帧、本地数据首次展示、后台数据补齐。快速切换或退出后，旧回调不能覆盖当前账号和选择 |
| 壳层及外观 | 手机底部页签、平板侧栏、分栏和菜单在各窗口宽度下可用。系统栏不遮挡工具栏，主题和材质强度切换即时可见 |
| 祈愿 | 在已有测试档案中分别刷新常规祈愿与颂愿，检查每池结果。导出到新文件后重新预览，总数、池分类与唯一 ID 一致 |
| 成就、养成与背包 | 切换档案、同类多选/跨类筛选、编辑与取消、既有数据导入及再次导出。对破坏性操作使用专用测试档 |
| 实时便笺 | 核对所追踪角色、阈值、树脂和派遣数值、刷新时间。开启自动刷新后退后台再回来，只补过期项 |
| 挑战和图鉴 | 切换期次、层/间、阵容和统计，比较已记录战绩与公告数据。图鉴检查属性等级、突破前后、技能与掉落 |
| 备份和资源 | 在专用测试账号验证备份恢复及中断重试，比较实际记录和偏好。验证素材更新成功后的下次启动与回滚 |

性能对照的采样口径和已有结果见[维护者交接](HANDOFF.md)。
