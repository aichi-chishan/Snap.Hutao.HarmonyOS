# 阶段验证记录（2026-10-02）

本记录对应 `codex/api24-port-2026-10-02` 的收尾代码。验证只针对已落地部分，不证明全部 Windows 功能移植完成。

## 宿主回归

```bash
npm ci --prefix ci --ignore-scripts
TYPESCRIPT_PATH="$(pwd)/ci/node_modules/typescript" node tests/run.cjs
```

Node 24.19.0、TypeScript 5.9.3。结果：**9 组全部通过**。

| 套件 | 主要验收点 |
|---|---|
| `account-protocol.cjs` | 区域、v2 Cookie、端点、HTTPS精确域与凭据隔离、重定向/缓存限制 |
| `backup-roundtrip.cjs` | 完整快照、v1、错误拒绝、凭据暂存、事务/偏好失败、提交状态不确定与启动恢复 |
| `character-cache.test.mjs` | UID持久缓存、模型还原、部分失败保留、未知突破不猜测 |
| `cloud-protocol.cjs` | 独立Bearer、RSA契约、Int64、云祈愿增量/时间/错误 |
| `data-port.test.mjs` | 祈愿时区/归档/统计、离线养成及评分等生产逻辑 |
| `inventory.test.mjs` | UIIF、手工库存、计算器余量、项目隔离与事务失败 |
| `ui-platform-contracts.cjs` | 服务器日期、材料窗口、启动Want、百科枚举、视频契约、切号异步竞争 |
| `uiaf.test.mjs` | 四种状态、进度/时间、三种合并策略、完整往返和原子写入 |
| `test-challenge-regressions.cjs` | 模型、复合归属、真实SQLite迁移、便笺通知、签到事实、提醒估算 |

使用Node Test Runner的四套数据域测试合计30项，其他为顺序断言套件；不把9组错误地称为9个用例。

## 官方工具链

- CLT 26.0.0.821、SDK 26.0.0.105、Hvigor 6.26.4、JDK17；详细获取、摘要与运行说明见 [BUILD_ENVIRONMENT](BUILD_ENVIRONMENT.md)。
- 原始基线直接 Hvigor：退出码0，`BUILD SUCCESSFUL`。
- 收尾 CodeLinter：退出码0，**0 error / 46 warning / 1 suggestion**。基线为0 error / 36 warning / 1 suggestion；告警尚未清零。
- CodeLinter存在已验证的 `@kit` 导入规则覆盖限制，CLI汇总亦曾显示错误扫描数；本记录采用底层实际报告，不能用“0错误”代替类型检查或设备验收。
- 收尾 Hvigor：退出码0，`BUILD SUCCESSFUL`，21.561秒；仍有542条编译警告，未宣称零警告。
- 未签名 HAP：251548793字节，SHA256 `44897cda1e842fce2900fef8d28e59a2aae60a7b39689f65430fff489a9c9a72`。产物清单实际最低API为`60101024`（API24），目标为`260000026`（API26），支持phone/tablet/2in1。

## 提交前检查与限制

- `git diff --check` 通过；变更源码/文档的私人邮箱和用户路径扫描无命中。
- 未提交 SDK、构建缓存、HAP、签名、密钥、账号凭据或机器绝对路径。
- 无可用签名或连接设备，宿主无 `/dev/kvm`。未做API24设备安装、ArkUI交互、视频解码、系统通知/卡片/提醒、真实登录与云同步验收。
- 网络fixture使用虚构凭据，云公开统计的无凭据GET验证不能代替账号功能测试。
