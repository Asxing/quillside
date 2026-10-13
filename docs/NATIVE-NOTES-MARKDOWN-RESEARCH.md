# Apple Notes 原生链接与 Obsidian Markdown 边界

核查日期：2026-10-08，Asia/Shanghai。范围：Apple 与 Obsidian 官方文档；针对 macOS Tahoe 26，另列旧版和 macOS 27 的差异。本次为文档研究，未操作用户笔记，未做导入、导出、附件保真或正文写入的实机验收。

产品前提：OpenNotes 定位为 Apple Notes 增强；不新增独立知识库、全文搜索或 AI 跨笔记搜索。考虑保留反向链接，并让可点击链接出现在 Notes 正文；另评估当前笔记导出到 Obsidian，以及 Obsidian Markdown 插入当前 Notes 笔记。

## 1. 结论与原生基线

| 能力 | 官方证据与版本边界 | 对 OpenNotes 的含义 |
|---|---|---|
| 在 Notes 正文链接另一篇笔记 | macOS Sonoma 14 文档已支持；Tahoe 26 保留 `Edit > Add Link`、输入标题选择笔记，以及 `>>` 快捷入口。[A1][A2] | 单纯“插入另一篇笔记的链接”已有原生实现，不应作为新增独有能力。 |
| 链接标题跟随目标改名 | 勾选 `Use Note Title` 时使用目标笔记当前标题；`>>` 创建的链接采用此行为。[A1] | 正文原生笔记链接与一段固定文字 URL 不能直接视为同一种对象。 |
| 自动反向链接 | 查阅 Tahoe 26 的链接指南及官方检索后，未找到“创建 A→B 后，B 自动显示所有入链”的说明。[A1] | 官方证据仅确认主动创建的链接。不能把 `>>` 称为自动反链；也不以文档缺席当作已完成运行证明。 |
| 当前笔记导出 Markdown | Tahoe 26：选中笔记，`File > Export as > Markdown`，保存文件。[A3] | 原生已有单篇导出。增强价值应是选择 Obsidian 目标目录、命名、打开结果、明确处理重复导出等工作流。 |
| Markdown 导入 Notes | Apple 明确从 Tahoe 26 开始支持，将 Markdown 转成富文本；每个文本文件生成新笔记，导入结果放入 `Imported Notes`。[A4] | 文件导入与“将内容插入当前笔记”是两个验收目标。 |
| 分享文件到已有笔记 | Apple 的 Finder 分享流程允许选择已有笔记。[A4] | 文档没有承诺 `.md` 在此路径会被解析成正文，更未说明插入当前光标。不能据此宣布当前笔记导入已由原生完整覆盖。 |

Apple 说明指南功能在 iCloud Notes 可用，其他服务商账户可能缺少部分功能；不能直接把 iCloud 结论外推到全部账户。[A1]

## 2. 严格区分 macOS 15、26、27

- **macOS 15** 的版本化指南列出 TXT、RTF、RTFD、HTML、ENEX 导入，以及 PDF 导出，未列出 Markdown 导入导出。[A5] Apple 的 Tahoe 新功能列表明确把 Markdown 导入导出列为新功能。[A6]
- **macOS 26** 的版本化指南明确有 Markdown 文件导入导出。[A3] 本次所读页面未说明 `Copy as Markdown` 或直接粘贴 Markdown 自动格式化。
- **macOS 27** 的对应指南另外写有 `Edit > Copy as Markdown`，并提示粘贴 Markdown 可呈现格式化标题、列表等。[A7] 这不是 macOS 26 已验证能力，也不是一个已经在 26 验证的“Paste as Markdown”菜单名称。

版本取证说明：本次尝试 `/4.12/mac/26` 时 web 工具返回不可访问；从 Apple 页面实际点击 **macOS Tahoe 26** 版本选项后，官方返回 `/4.13/mac/26`，正文与 `/4.13/mac/27` 明显不同。因此报告以官方版本选择器和 URL 的 `/mac/26` 联合定位，不以中间指南版本号 `4.13` 单独推断操作系统版本。

## 3. Obsidian 互通所需的格式约定

| 对象 | Obsidian 官方行为 | 互通边界 |
|---|---|---|
| 笔记文件 | 笔记是本地 vault 文件夹中的 Markdown 纯文本文件；外部修改会被刷新。[O1] | 导出到已有 vault 是文件落盘工作流，不需要另建 OpenNotes 知识库。 |
| Markdown 方言 | 支持 CommonMark、GFM 等，也支持 wikilinks、嵌入、块引用、callouts 等扩展。[O2] | `.md` 只表示文件形式，不能证明 Apple 的解析器支持 Obsidian 扩展。 |
| 内部链接 | 支持 `[[Note]]` 和 `[Note](Note.md)`；Markdown 链接目标需 URL 编码。官方建议需要互操作时可关闭默认 Wikilinks。[O3] | 可优先输出标准 Markdown 链接，但把 Obsidian 笔记关系变为 Notes 原生笔记关系，仍需目标身份映射。 |
| 附件 | 图片、音频、PDF 等作为独立普通文件保存在 vault；附件目录可配置。[O4] | 仅复制 `.md` 不保证复制了附件。需要明确资产路径与实际文件。 |
| 嵌入 | `![[Note]]`、`![[image.jpg]]`、标题/块嵌入等用于内联显示源内容。[O5] | 必须决定导入 Notes 时是展开、保留链接还是降级；Apple 文档没有给出 Obsidian 嵌入转换保证。 |
| URI | `obsidian://open?vault=...&file=...` 可打开 vault 内已有文件；参数需要 URI 编码。[O6] | 可作为导出后的“在 Obsidian 打开”入口。URI 是定位机制，不承诺内容转换、附件迁移或双向同步。 |
| 反向链接 | Obsidian 的 Backlinks 核心插件列出当前笔记的入链，可在侧栏或笔记底部显示。[O7] | “显示在文档底部”不能被当作“把反向链接文字写入 Markdown 正文”的证据；Notes 正文持久化是另一种产品行为。 |

示例仅表示可采用的目标格式，不是已实现或实测结果：

```md
[相关笔记](Related%20note.md)
![插图](attachments/figure.png)
[在 Obsidian 打开](obsidian://open?vault=Example&file=Notes%2FExample.md)
```

## 4. 需要实测后才能承诺的内容

1. **Notes → Markdown 保真**：Apple 的导出指南没有列出附件打包、图片路径、笔记内链接、原生表格、扫描件、手写、清单状态的转换矩阵。[A3] 因而不能宣称原生导出完整保留附件、关系，或可无损往返。
2. **Obsidian → 当前 Notes 正文**：分别测试 `.md` 导入、Finder 分享到已有笔记、纯文本粘贴和富文本粘贴；记录新建/追加/当前选区插入、格式及附件的真实结果。macOS 27 的说明不能代替 26 的实测。
3. **正文反链语义**：若在 B 的正文写入“引用此笔记：A”，这是持久化的 B→A 链接。需要决定来源 A→B 被删除时如何更新、如何避免重复，以及是否把自动生成的 B→A 再当作新的用户引用。此处是设计推导，不是 Apple 官方行为声明。
4. **跨应用链接**：需验证 `obsidian://` 从 Notes 点击后的实际行为；需另验 Notes 原生链接导出成什么形式，不能预设会自动变成 Obsidian wikilink。

据此建议：先以“Notes 正文中的链接关系增强 + 单篇 Markdown 交换”为边界；优先复用原生笔记链接和 26 的文件导出。当前笔记 Markdown 插入、Obsidian 扩展转换和正文反链维护，应作为独立小范围验证项。此建议是基于上述证据的产品判断，本次未实施。

## 官方来源

- [A1：Apple — Add links in Notes on Mac，macOS 26](https://support.apple.com/guide/notes/add-links-apde615d29c2/4.13/mac/26)，`Link to another note`、`Edit and remove links`。
- [A2：Apple — Add links in Notes on Mac，macOS 14](https://support.apple.com/guide/notes/add-links-apde615d29c2/4.11/mac/14.0)，`Link to another note` 明确写出 Sonoma。
- [A3：Apple — Import, export, and print notes，macOS 26](https://support.apple.com/guide/notes/import-export-and-print-notes-not201900c07/4.13/mac/26)，`Export a note as a Markdown file`、`Import a Markdown file into Notes`。
- [A4：Apple — Import or share notes and files to the Notes app](https://support.apple.com/en-us/102223)，发布日 2026-04-02，`Import Markdown files (.md) to Notes`、`Share files to Notes with Finder`。
- [A5：Apple — Import, export, and print notes，macOS 15](https://support.apple.com/guide/notes/import-export-and-print-notes-not201900c07/4.11/mac/15.0)。
- [A6：Apple — All New Features, macOS Tahoe](https://images.apple.com/os/pdf/All_New_Features_macOS_Tahoe_Sept_2025.pdf)，Notes / Markdown Export and Import，PDF 印刷页码 13。
- [A7：Apple — Import, export, and print notes，macOS 27](https://support.apple.com/en-euro/guide/notes/not201900c07/4.13/mac/27)，`Copy a note as Markdown`。仅用于版本对比。
- [O1：Obsidian — How Obsidian stores data](https://help.obsidian.md/Files+and+folders/How+Obsidian+stores+data)。
- [O2：Obsidian — Obsidian Flavored Markdown](https://help.obsidian.md/obsidian-flavored-markdown)。
- [O3：Obsidian — Internal links](https://help.obsidian.md/links)，`Supported formats for internal links`。
- [O4：Obsidian — Attachments](https://help.obsidian.md/attachments)。
- [O5：Obsidian — Embed files](https://help.obsidian.md/embeds)。
- [O6：Obsidian — Obsidian URI](https://help.obsidian.md/uri)，`URI format`、`Open note`。
- [O7：Obsidian — Backlinks](https://help.obsidian.md/Plugins/Backlinks)，`Show backlinks`、`Show backlinks in a note`。
