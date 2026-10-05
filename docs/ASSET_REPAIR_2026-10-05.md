# 本地 PNG 修复与资源发布校验（2026-10-05）

## 已确认问题

基线：`aichi-chishan/snap-hutao-data@c53167c9af159ea46cf7a4221d988a8f1729e1ae`。

10 个 `.png` 实际都是相同的 139 字节 nginx 404 HTML：

- SHA256：`5d1d75b702f13e1bb14ff8d52cac1690acacec3a15821af7fe482a79afda5b99`
- Git blob：`99d83c01fdda6bed7056676265f0fa7d1f715478`

原始内容仍可从该基线的 Git 历史恢复；另外保存了原始坏字节与检索响应证据。没有放宽客户端 PNG 校验。

## 八张有来源的修复

七元素的根因是把显示用元素名直接当成游戏文件名。Windows 端真实映射见：

[ElementNameIconConverter.cs，固定提交 3f0d1f3](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/Metadata/Converter/ElementNameIconConverter.cs)

| 应用现有文件名后缀 | 真实 CDN 名后缀 |
| --- | --- |
| Anemo | Wind |
| Cryo | Ice |
| Dendro | Grass |
| Electro | Electric |
| Geo | Rock |
| Hydro | Water |
| Pyro | Fire |

源地址规则：`https://api.snaphutaorp.org/static/raw/IconElement/UI_Icon_Element_{真实后缀}.png`。该地址合法重定向到 `static.snaphutaorp.org`，七张均返回 PNG。应用现有文件名作为明确的兼容别名保留；图片原始字节未重绘、未改色。它们是 128×128 白色透明底元素符号，已在深色底上逐一目视核对。浅色主题的 UI 色彩呈现仍需原生界面检查。

`Bg/UI_Icon_None.png` 从公开 Windows 分支配置的对应静态资源地址恢复：

- [分支静态资源地址定义，固定提交 9200f44](https://github.com/wangdage12/Snap.Hutao/blob/9200f44e337fd5d417e82c85be1db526b739dd87/src/Snap.Hutao/Snap.Hutao/Web/Endpoint/Hutao/StaticResourcesEndpoints.cs)
- [精确同名源图](https://htserver.wdg12.work/static/raw/Bg/UI_Icon_None.png)

该图片为 44×44 透明底禁止/空图标，保留下载原始字节。配置的主要 CDN 同名路径当时仍返回 404。没有将 fork CDN 设为生产下载器的默认信任源。

每个修复文件的完整下载 URL、来源代码链接、SHA256、大小与尺寸都在 `asset-repair-provenance.json`。

## 两张仍无精确来源的怪物图

仅移除以下已确认 HTML 的伪 PNG，并从重新生成的清单中排除：

- `MonsterIcon/UI_MonsterIcon_LavaTitan_01.png`
  - describeId 62704：「微末」/熔岩游像·蚀土者
  - describeId 62801：巴窟纳瓦
- `MonsterIcon/UI_MonsterIcon_Samurai_Kairagi_05.png`
  - describeId 51103：厄灵·炎之魔蝎
  - describeId 51104：厄灵·草之灵蛇

配置的 Snap Hutao CDN、Enka 和上述 Windows fork CDN 的精确路径均返回 HTTP 404。不能由这些结果断言所有地方都没有原图，但现有核实来源中没有可用图。

没有改动怪物元数据身份，也没有用现有 `LavaTitan`（熔岩辉龙像）或 `Samurai_Kairagi_01/_02`（普通海乱鬼）替代。客户端应走明确的缺图回退。这是记录在案的美术缺口，不是已恢复这两张怪物图。修复不删除任何元数据条目。

## 防止再次发布伪 PNG

- `asset_pipeline.py`：安全名称、明确元素别名、路径边界、允许的 HTTPS CDN 重定向、8 MiB 上限、PNG chunk CRC/IHDR/IDAT/IEND 检查、有限完整解压和扫描行校验、原子替换
- `fetch-assets.py`：不再按“大于 500 字节”跳过已有文件；修复 repo-local 元数据回填，导入模块无网络或写入副作用，任何批次失败使流程失败
- `generate_manifest.py`：只读验证整个已知文件队列后生成 schema 1 清单，为每个原始文件写入 `size` 与 `sha256`；不编造 upstream/source revision，不降低客户端规则
- `gen-manifest.ps1`：保留 Windows 入口，调用同一个 Python 生成器，错误会向上传播，版本号必须显式传入
- 生成器不会按魔法名单默默跳过坏 PNG。将来再出现 HTML，生成应失败，必须先调查

## 本地验证与边界

- 3,752 张应用 PNG 与 3,752 张数据仓库 PNG：全部通过签名、逐 chunk CRC、完整 zlib、Pillow `verify()` 和实际 decode
- 两处全部图标路径及原始 SHA256 相同
- 17 个元数据原始文件未改动
- 3,769 项主清单的每个 `size`、`sha256` 与实际文件一致，资源清单 3,752 项
- 14 个标准库离线回归测试通过，覆盖大 HTML、WebP 伪装、CRC、截断、过滤器、压缩流、原子写失败、坏缓存、重定向与路径边界、别名、BOM 原始字节哈希、元数据缺失、导入副作用和本仓库回填
- `fetch-assets.py --elements-only` 本地运行：`ok=0 skip=7 fail=0`
- 完整上游下载管线未在真实 `.local/upstream/Snap.Metadata` 上运行；元数据回填使用离线夹具验证
- PowerShell 包装入口未在 PowerShell 主机运行；其 Python 实现已实际执行
- 本地清单为 `2026.10.05.1`，没有提交或推送远端；GitHub main 仍是旧的发布内容
- 这些资源检查不能代替 HarmonyOS 原生构建、解码和界面验收
