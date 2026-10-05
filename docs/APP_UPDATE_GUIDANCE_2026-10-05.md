# F22 · 原生应用更新比较与安全指引

## 状态与实证

本次完成 HarmonyOS API24+ 的更新检查、通道选择、可信发布页入口以及明确的安装边界。没有移植 Windows 部署器，没有配置虚构的 AppGallery 应用 ID，没有下载或安装任何包。

2026-10-05 只读查询 [鸿蒙项目公开 Release API](https://api.github.com/repos/aichi-chishan/Snap.Hutao.HarmonyOS/releases?per_page=20) 返回 `[]`。因此当前真实在线结果应为“项目尚无可用的公开发布版本”。无签名分发、升级覆盖、最低 API 包安装或商店上架的真实证据，不能宣称这些已经验证。

基线差距见 [F22](FUNCTION_GAP_ANALYSIS_2026-10-02.md#f22--应用版本比较与升级入口--部分--平台替代p1)。原 Settings 以 tag 字符串“不相等”判断新版，并采用响应中未经校验的 `html_url`，本机较新或旧分支新发版都会误报。

## 实现与集成

- `model/AppUpdate.ets`：纯版本/发布通道/来源/元数据/最低 API 策略
- `service/AppUpdateService.ets`：只读公开 HTTP、自己持有请求取消对象、本机版本/API 读取及明确点击后的系统 `openLink`
- `viewmodel/UpdateViewModel.ets`：检查、取消、切换通道、页面失活、重复点击、陈旧结果及打开链接的状态归属
- `pages/UpdatePage.ets`：原生手机/平板/2in1 页面，组件内容宽度 840vp 起双栏，主题色、44vp 操作按钮及鼠标 hover
- `tests/app-update.cjs`：19 项生产代码回归与严格类型检查

集成入口：注册 `pages/UpdatePage`，使用 `UpdatePage({ embedMode: true })` 可内嵌宽屏壳；手机使用此路由。Settings 的应用更新动作应导航至此页面，移除旧 `checkAppUpdate` / `confirmOpenUrl` 逻辑，避免两条更新链同时保留。页面显示不会自动发请求；仅点击“检查更新”时读公开元数据。

## 比较语义

- 支持 1–4 段数字版本、可选 `v/V` 前缀、SemVer 预发布及 build 后缀；缺失数字段视为 0
- 数字段按十进制字符串比较，避免大整数精度损失；拒绝前导零、空白和不能比较的标签
- 预发布数值标识按数值比较，数字标识低于非数字标识；正式版高于相同核心版本的预发布；build 后缀不影响排序
- 稳定通道同时排除 GitHub `prerelease=true` 和带预发布标签的版本；预发布通道包含稳定版
- 按可比较版本最大值选择，不按发布时间选择，因此旧分支新发布不能导致降级提示
- 相同、本机较新、发布较新、未知标签、仅预发布、草稿、空数组分别处理
- 候选元数据不足或分页未覆盖全部时，不说“已经最新”；确定发现新版仍可报告发现结果并展示范围警告
- 读取最多 3 页 × 100 条，不接受响应给出的任意 next URL；检查范围不足时明确标识
- 合格更新元数据的 `versionCode` 可区分同名 rebuild；与非零版本名称比较方向冲突时标为未知，不擅自建议升级

## 来源、网络及生命周期边界

唯一网络端点是固定项目 `https://api.github.com/repos/aichi-chishan/Snap.Hutao.HarmonyOS/releases?per_page=100&page=N`，N 为 1–3。独立 HTTP 请求不读取账号、Cookie、Authorization、游戏客户端会话或持久登录配置。请求使用 GET、15 秒连接/读取超时、2 MiB 单次响应上限、无缓存、`maxRedirects: 0`。

`html_url` 必须严格等于同项目 `https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/releases/tag/{encodeURIComponent(tag)}`；其他域、项目、用户信息、查询参数和 scheme 均拒绝。只允许显式点击打开此发布详情页或固定项目发布列表；发布说明当纯文本展示，不执行其中的 URL。不存在包下载按钮或安装 API。

空发布数组是无发布；404 是仓库/发布接口不可访问，不能误报为无发布；403/429、网络异常、非 JSON、非数组及非预期 HTTP 响应分别保留可重试状态。失败不会保留旧版本并伪装为本次检查成功。

每次检查由页面 VM 持有独立 `AppUpdateRequest`。取消、切换通道、hide/disappear 都销毁当前网络句柄，并递增请求归属序号；旧成功、失败及 finally 不能覆盖新状态。`aboutToAppear` 与 `onPageShow` 幂等；页面失活再激活不自动重试。系统链接已有调用无法撤回，但重复点击不再次启动，旧错误不会污染新页面。返回时本机版本/API/应用身份变化会清除旧比较。

## 可选的项目更新元数据约定

当前仓库没有 Release，也没有现成签名分发配置。以下是本次客户端支持的可选项目发布约定，**不是已经部署的上游协议，也不是签名清单**。仅当维护者之后在该项目确切 Release 的说明中附加唯一一段时解析：

```text
<!-- hutao-harmony-update:v1
{"schema":1,"bundleName":"com.example.snaphutaoharmonyos","tagName":"v1.22.0","versionName":"1.22.0","versionCode":1002200,"minimumApi":24,"channel":"stable"}
-->
```

上例只说明格式，不表示 1.22.0 已发布。字段绑定：schema=1、当前固定 bundleName、当前 Release 的精确 tagName、可比较为相同版本的 versionName、对应 stable/preview 通道、正安全整数 versionCode 与 minimumApi。无效/重复/超长块拒绝。元数据来自固定项目的 HTTPS GitHub API，只有“项目来源元数据”的信任程度，不能替代包签名认证。任何 `signed` 或 `signatureVerified` 等额外声明都不会产生安装资格。

只有本机 bundleName 匹配时，才应用 `versionCode` 与最低 API。最低 API 高于本机时明确“请勿在此设备安装”。满足数字要求只显示“满足项目声明的最低 API”，**不称为兼容或可安装**。缺失最低 API、无效清单、未知本机 API、不同 bundle 均保持未知。

已知同项目同 Release 的 `.hap` / `.app` 正大小附件仅计数，不下载、不验证签名、不据文件名认定可安装。没有包时明确提示源码压缩包/Windows 安装器不可作为鸿蒙更新。`installable` 始终为 false，直到未来另行加入可验证的实际分发配置与其授权流程；没有虚构商店回退。

## 官方 SDK 依据与验收

检验已部署 SDK `26.0.0.105` 的声明：

- `openharmony/ets/api/application/UIAbilityContext.d.ts` 的 `openLink` 标记 `@since 12`，适用于 API24；显式 UI 点击使用当前页面 host context，处理平台拒绝/失活
- `openharmony/ets/api/@ohos.net.http.d.ts` 的 `maxRedirects` 标记 `@since 23`，0 禁止重定向；`maxLimit` 标记 `@since 11`
- 无 API26 专属接口，无绕过系统安装或签名检查的调用

验证命令：`node tests/app-update.cjs`，19 项通过，包含数字/SemVer、旧分支、各通道/状态、exact-source trust、最低 API、无元数据/伪签名/无包、响应错误、分页边界、取消/重复/新旧请求归属、陈旧 context、链接重复/拒绝、原生页面生命周期及严格类型检查。主任务负责将页面接入路由后运行整项目原生编译、lint 和全部主机回归；本文件不将 host tests 冒充设备安装验证。

仍需真实设备检查系统浏览器返回、旋转/窄宽窗口、网络断开/恢复以及实际维护者分发发布。当前无 Release，无法声称真实升级安装已通过。
