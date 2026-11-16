# 游戏元数据的 15 语言显示

当前内置游戏数据为 7.2，取自 Snap.Metadata 提交 `fb3e2692579495c6b181403da01fde1e5b8f9193` 的 `Genshin/`。15 个语言目录沿用 Windows 的 CHS、CHT、DE、EN、ES、FR、ID、IT、JP、KR、PT、RU、TH、TR、VI。旅行者名称和生日格式取自 Snap.Hutao.Remastered 2.0.2 的 `SH.*.resx`（提交 `3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5`）。[Snap.Metadata 随包许可](../entry/src/main/resources/rawfile/wiki/monster/LICENSE.txt)

`scripts/generate-game-locales.py` 生成 `rawfile/metadata/locale_{语言}.json`。语言包覆盖角色（技能、命座、语音、故事、服装）、武器、怪物、材料、成就、名片、祈愿期次、深渊祝福与地脉异常、幽境期次和魔神任务章节，并提供背包材料、圣遗物、套装和摆设的名称表。

角色/武器按 ID，怪物按 `describeId`，名片按图标，祈愿按 `Type+From+To+Order` 匹配。语音与故事的上游结构没有 ID，语言文件记录位置编号和对应中文标题；同名语音额外核对中文原文，避免不同版本排序变化时串位。数值、图标、ID、材料关系和进度不参与覆盖。富文本中的旅行者、流浪者、时区和性别代词使用 Windows 同语言资源词条，语音/故事恢复上游完整文本。

## 离线校验角色图鉴

从工程根目录运行以下命令。生成器默认读取 `scripts/data/` 的两份快照和应用内置的中英文角色数据。安装 `ci` 目录的 TypeScript 依赖后，主机回归也使用同一批输入。

```powershell
python scripts/generate-wiki-avatar-filter-labels.py --check
python scripts/generate-avatar-guide-reference.py --check
node --test tests/wiki-avatar-filter.cjs tests/wiki-avatar-guides.cjs tests/wiki-route-ownership.cjs
```

去掉 `--check` 即可从相同输入重建两份 ArkTS 文件。维护译文时，给筛选生成器传 `--windows <Windows 仓库目录>`，它会读取固定提交的 Git 对象。维护攻略编号时，给攻略生成器传 `--refresh`，它会重新采集米游社与 HoYoLAB 公开目录的编号和标题。

图鉴最多接受五个条件。同类条件取并集，不同类取交集。选择角色按 ID 精确匹配，自由文本匹配显示名和中文原名。切换语言后，已选条件保留原来的角色或枚举值。15 种语言的 33 个筛选词和 4 个攻略文案保留 Windows 资源键及提交来源，随包附上原作者的 MIT 声明。[译文快照](../scripts/data/wiki-avatar-labels.json) · [上游许可全文](../entry/src/main/resources/rawfile/wiki/weapon/LICENSE.txt)

米游社目录对应 122 个图鉴角色和两个共用旅行者频道的身份。B 站入口仅在简体中文下按角色中文原名打开。HoYoLAB 公开目录能对应申鹤、神里绫华、迪希雅、赛诺、米卡五个角色，其余角色显示当前语言的缺少攻略提示。应用使用内置编号打开发布方页面，攻略正文由发布方提供。[攻略目录快照与来源](../scripts/data/wiki-avatar-guides.json)

## 更新整套游戏元数据

准备上述固定提交的两个上游源码目录。以下示例将两份源码放在本工程的同级目录，从本工程根目录校验紧凑元数据、15 份译文、头像和章节表。

```powershell
$revision = 'fb3e2692579495c6b181403da01fde1e5b8f9193'
$genshin = '../Snap.Metadata/Genshin'
$strings = '../Snap.Hutao.Remastered/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Resource/Localization'
python scripts/update-compact-metadata.py --source $genshin --revision $revision --include-challenges --check
python scripts/generate-game-locales.py --source $genshin --upstream-revision $revision --windows-strings $strings --check
```

向独立数据仓生成译文时，使用相同来源参数，并指定 `--output snap-hutao-data/metadata --base-metadata snap-hutao-data/metadata`。数据仓的 `gen-manifest.ps1` 按 `channelVersion` 为 `metadata/*.json` 生成清单。

## 公开角色头像接线

生成脚本同时输出 `metadata/ProfilePicture.json`。7.2 包含 191 条记录，按上游 Git 文件的 LF 换行保存（28,733 字节）。`RoleProfilePictureService` 通过 `GameDataService.readMetadataFile('ProfilePicture.json')` 读取当前快照，旧远端包缺少头像表时使用内置文件。

保留 `Id / Icon / Name / UnlockType / UnlockParameter`。例如 ID `1` → `UI_AvatarIcon_PlayerBoy_Circle`，服装头像 ID `11` 的 `UnlockType=3`、`UnlockParameter=200501`。图标原名交给 `MetaIcon` 的 `AvatarIconCircle` 类目或 `StandardIconService.ensure('AvatarIconCircle', icon)`，不截掉 `_Circle`，也不从头像 ID 拼接文件名。ID `900004` 的自定义头像图标为空，维持占位。Enka 的请求、角色身份确认与 15 日缓存由账号服务负责。

若需要显示头像名称，使用 `LocalizedGameDataService.readMetadataFile('ProfilePicture.json')` 或 `names('ProfilePicture.json')`；只覆盖名称，图标与解锁关系不变。旅行者名称中的 `{0}` 是上游格式占位符，原样保留供调用方代入昵称。

## 生产读取与刷新

- `GameDataService.readMetadataFile` 提供原始数据。语言包、各语言技能参数、头像、章节等均为远端可选项，完整清单由 `GameDataManifestPolicy` 定义。头像表校验 ID 唯一性和原始字段类型。
- 语言文件单文件上限 16 MiB，普通文件仍为 8 MiB。快照逐一验证语言文件，当前语言需要时通过只读 TaskPool 按固定快照的 SHA-256 再次读取。全部语言不驻留快照文本缓存，不扩大原有 32 Mi 文本传输上限。
- `LocalizedGameDataService.readMetadataFile(name)` / `readJson(name)` 提供显示解析入口；`names(table)` 提供按 ID 的名称 Map，支持 `material_meta.json`、`Reliquary.json`、`ReliquarySet.json`、`Furniture.json`。译文优先级为已验证远端字段、内置字段、原始中文字段；稀疏远端包不清空其他内置译文，坏表/坏行被拒绝。CV 和精炼文本保留原有位置及数量。
- `WikiMetaService` 现有 getter 按 `AppLocaleService.current()` 隔离缓存；角色/武器/怪物同时读取合并为一次加载。异步完成比较缓存实例，避免“英→日→英”后旧请求覆盖新缓存；占位词目录同样按请求实例发布。显式读取旧语言的批次不替换当前目录。`AchievementService.getCategories()` 在每次等待后重新检查在途加载，串行更新语言缓存。
- `canonicalName` 保存原始中文名。角色的 `vision` 与 `birth` 保持元素键及 `M/D`，展示使用 `visionName`、`birthText`。`displayNameOfItem(id, originalName, itemType)` 给祈愿行提供译名，不能改写持久化的 `GachaItem`。

## 页面及其他所有者接线

| 消费方法 | 接线约定 |
| --- | --- |
| `SkillLevelService.forMetaSkill` | 将名称和图标的联合条件改为 `skill.name === (meta.canonicalName \|\| meta.n) && skill.icon === meta.i`。英文「Secret Spear of Wangsheng」因此仍能匹配中文天赋表的等级。 |
| `GachaCollectionService.count` | 角色和武器分别以 `角色:${名称}`、`武器:${名称}` 为键，把非空的 `canonicalName` 和 `name` 索引到同一个 `GachaItemCount`。`itemId > 0` 只走 `catalog.get(item.itemId)`；无 ID 才先查中文原名、再查显示名，避免同名但不同 ID 的记录被合并。 |
| `GachaHistoryService.metaLookupMaps`、`buildFromItems` | 在 `HistoryUpItem` 传递角色或武器的 `canonicalName`。`registerUp` 把两个名字索引到同一个 `up`。有 ID 的记录走 `upIndex`，无 ID 的记录先查原名，再查显示名。`WishHistoryService.track` 在同起止时间内用类型、原名、版本和期数判断重复，`pool.name` 用译名。 |
| `HomeSignInCard.aboutToAppear` | 对图标非空的材料，在 `rewardIcons` 登记 `material.n` 和 `material.canonicalName`，跳过空名称。`awardCell` 继续用国服返回的 `reward.name` 查图标。 |
| `CharacterPage` 的名片、天赋区及 `skillLevelAt` | `ensureIconMaps()` 后从 `WikiMetaService.avatarOf(detail.id)` 取得 `nameCardPic`、`skills`，需要时用现有的 `nameCardPicOf(detail.name)`、`skillsOfAvatar(detail.name)` 兜底。切语言时只重载元数据并刷新详情状态。 |
| `GachaLogPage.itemRow`、`fiveStarArea`、最近记录 | 先预载 `ensureIconMaps()` 和 `ensureBeyondItemMaps()`，再用 `WikiMetaService.displayNameOfItem(itemId, name, itemType)` 生成显示文案。五星和最近记录的展示模型应透传可用的物品 ID。原始 `GachaItem` 供 UIGF 导入导出。切换语言后重算 `vm.reloadStats()`，用 `syncAll()` 同步展示，并用 `loadHistoryWishes()` 刷新已打开的历史期次。 |
| 图鉴三个页面的 `load`、`WishHistoryPage.reload`、`AchievementPage.refreshData` | 用本地加载入口刷新数据源。图鉴按选中 ID 绑定新详情对象，怪物用 `describeId`。角色详情显示 `visionName`、`birthText`。米游社与 HoYoLAB 角色攻略按角色 ID 查表，B 站攻略按 `canonicalName` 构造链接。 |
| `TowerMetadataService.loadAll`、`HardChallengeService.publishedPeriods` | 用 `LocalizedGameDataService.readMetadataFile(name)` 读深渊和幽境的展示元数据。深渊缓存按语言刷新，`toWaveViews` 用原名合并怪物，名称列显示译名。 |

页面监听 `helpLocaleVersion` 触发本地重载，保存选中 ID、筛选键和当前档案。替换数组后通知数据源，将语言版本追加到 `LazyForEach` 或 `ForEach` 的稳定行键，例如 `` `${item.describeId}_${this.localeVersion}` ``。手动选择由 `AppLocaleService.select` 发布语言变化。跟随系统时，`EntryAbility` 将 `newConfig.language` 传给 `AppLocaleService.onConfigurationUpdate`，实际语言改变后更新版本号。

`BackpackPage.localeChanged` 和 `CultivationPage.localeChanged` 已调用各自的 `refreshDisplay()`。背包通过 `LocalizedGameDataService.names(table, locale)` 按 ID 取得材料、圣遗物、套装和摆设译名。`CalendarPage` 和 `HomeCalendarCard` 已监听语言版本并重载本地周视图。

`tests/game-metadata-localization.cjs` 验证译文匹配、跨语言缓存与中文回退，`tests/game-data-cohort.cjs` 验证远端文件边界和固定快照读取。两者可用 `node --test tests/game-metadata-localization.cjs tests/game-data-cohort.cjs` 运行。
