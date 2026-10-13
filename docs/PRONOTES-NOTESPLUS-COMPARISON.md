# ProNotes、NotesPlus 与 OpenNotes 功能源码对照

> 历史实现/审计记录。2026-10-08 最新范围与当前状态见 [功能清单](CURRENT-FEATURES.md)；搜索与知识库已退出，笔记文件导入导出延期。

> 本文记录此次修复前的审计基线。2026-10-08 的修复与剩余验收见 [持续对齐状态](GOAL-STATUS.md)；旧差距行保留作为问题依据，不能当作最新实现状态。

审计日期：2026-10-07 至 2026-10-08，Asia/Shanghai。本文是继续实现与最终验收的输入，不是发布完成声明。审计只读取公开资料、已保存的研究材料、本机 ProNotes 应用资源及项目源码；没有访问用户笔记、操作 GUI 或调用模型。

**结论：OpenNotes 0.1 保留了 NotesPlus 的主要编辑架构，并新增了可配置模型、模板工作台、搜索和文本知识库；仍有可由源码直接证明的 ProNotes 稳定功能缺项。上游测试通过不能证明完整对标，尤其当前测试固定了不完整的 8 个 Markdown 触发和 13 个 slash 命令。**

## 证据与状态定义

- **P-WEB**：[ProNotes 官网](https://www.pronotes.app/)，本次实时读取。官网明确列出 Markdown 输入、slash 别名、模板通过 slash 插入、键盘友好搜索、两个可配置搜索快捷键和 WIP 边界。产品声明不等于本机行为验证。
- **P-UI**：[已保存的本机分析](../../ProNotes开源实现调研/research/local-inspection.md)。ProNotes 0.7.8.2 build 20，主程序 SHA-256 `54265355634cc9e3239aea324fb7fa28502b83ba8f8210ffe046393b7f5a934c`。十项工具条的排序/显隐、系统提示词、自定义提示词及通用设置有既往 UI 观察。此前合成笔记试验没有成功触发 ProNotes 工具条、Markdown、slash；不得据此宣称这些功能可用或必然损坏。
- **P-RES**：本次直接读取 `/Applications/ProNotes.app/Contents/Resources/{13.5-14E6097d-1751696242.402196,14.6-15E6079e-1751671530.219496,15.5-16E6052g-1752727212.408136,26.0-17A6231r-1752725549.2056}.json`。分别有 20、21、22、22 个本地化菜单映射；这些资源证明实现包含相应菜单适配，不证明每项分支运行成功。
- **P-STR**：[二进制字符串快照](../../ProNotes开源实现调研/evidence/binary-strings.txt)，包括 `expand-markdown-monostyled`、`is-slash-enabled`、`is-markdown-enabled`、模板说明和 Markdown 附件/表格转换器名称。仅作机制线索。
- **N-SRC**：[NotesPlus 固定 commit 518886fc42118ec913d44694d69549f38e3d9e4c](https://github.com/sunhuaian2026/NotesPlus/tree/518886fc42118ec913d44694d69549f38e3d9e4c)，本机 checkout `/tmp/pronotes-github-research/NotesPlus`。以源码及测试为准，不把 README 的功能名视为运行证明。
- **O-SRC**：本次读取的 `src/OpenNotes` 44 个 Swift 文件快照（9,739 行），含 23 个仅品牌替换后与上游相同文件、12 个已修改上游文件、9 个新增文件。文末逐文件清单可追踪覆盖面。后续产品修改需更新本文状态。

状态约定：**代码实现**＝存在接线完整的源码路径，但未据此声称 GUI 通过；**部分**＝主要机制存在而明确合同缺项；**缺失**＝相关入口/路径未实现；**待验证**＝源码不足以确认端到端结果；**扩展**＝用户要求的新增能力，不虚构成 ProNotes 现成功能。涉及 Notes 编辑的所有“代码实现”均仍需真实笔记回读和撤销验收。

## 1. 选区工具条与格式操作

ProNotes 的十项为 Ask AI、Font、Bold、Italic、Underline、Strikethrough、Highlight、Link、Alignment、Checklist（P-UI）。OpenNotes 的十个按钮为粗体、斜体、下划线、删除线、项目符号、短划线、编号、引用、等宽、高亮。两者数量相同但能力集合不同，不能用“十项工具条”宣称完整相当。

| ID | 对标要求与证据 | NotesPlus 固定版本 | OpenNotes 本次状态、定位与剩余门槛 |
|---|---|---|---|
| TB-01 | 选择正文后显示近旁浮层（P-WEB/P-UI） | AX 选区 + 非激活 NSPanel | **代码实现/待验证**：[FloatingBarWindowController](../src/Quillside/Features/FloatingBar/FloatingBarWindowController.swift) 99 行起；[AccessibilityBridge](../src/Quillside/Services/AccessibilityBridge.swift) 144 行起。需检查正文、搜索框、笔记标题不同 AX 元素，不是任意可选文本均可弹格式栏。 |
| TB-02 | 工具条 Ask AI（P-UI） | 无；底部笔记动作栏为禁用占位 | **部分**：底部 NoteActionsBar 和菜单可捕获并打开独立工作台；[FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift) 没有 Ask AI。 |
| TB-03 | Font/字体大小入口（P-WEB/P-UI） | 无 | **缺失**：仅 slash/FormattingService 提供标题/正文，无工具条字体控制。不能把等宽按钮当作 Font。 |
| TB-04 | Bold（P-UI） | `⌘B` | **代码实现/待验证**：[FormattingService](../src/Quillside/Services/FormattingService.swift) 75 行起；选中状态来自 AX 字体名称启发式。 |
| TB-05 | Italic（P-UI） | `⌘I` | **代码实现/待验证**，与上游一致。 |
| TB-06 | Underline（P-UI） | `⌘U` | **代码实现/待验证**，与上游一致。 |
| TB-07 | Strikethrough（P-UI） | `⇧⌘X` | **代码实现/待验证**，与上游一致。 |
| TB-08 | Highlight（P-UI/P-RES 15.5+） | `⇧⌘E` | **部分**：存在动作但无按系统版本/菜单可用性禁用；macOS 14 部署目标不代表高亮存在。P-UI 未验证颜色选择，不能额外声称原厂存在颜色面板。 |
| TB-09 | Link 添加/编辑（P-UI/P-RES） | 无 | **缺失**：无添加/编辑链接入口与动作。复制笔记 deeplink 是不同功能。 |
| TB-10 | Alignment（P-UI），左/中/右/两端（P-RES） | 无 | **缺失**：无对齐控件、动作和状态。 |
| TB-11 | Checklist（P-UI） | 仅 slash/Markdown | **部分**：FormattingService 有 checklist，但浮动工具条无按钮。 |
| TB-12 | 工具条项目显示/隐藏（P-UI） | 无 | **缺失**：固定 SwiftUI 三组 HStack；无用户配置模型。 |
| TB-13 | 工具条排序（P-UI） | 无 | **缺失**：没有拖拽/上下移及持久化次序；固定面板 310×34 也未按项目变化适配。 |
| TB-14 | 格式状态随选区更新 | 有 AX attributed string 分析 | **代码实现/待验证**：[SelectionFormattingAnalyzer](../src/Quillside/Features/FloatingBar/SelectionFormattingAnalyzer.swift) 对多个 runs 取交集；字体用英文名称识别 bold/italic/mono，高亮以背景色存在判断。没有 quote 状态识别，列表任意非数字/非横线前缀均归类 bullet；不能假设所有原生属性均准确。 |
| TB-15 | 多屏、全屏、切应用隐藏 | 有窗口跟踪和坐标转换 | **代码实现/待验证**：继承 WindowTrackService/WindowGeometry；测试覆盖策略和坐标算式，未覆盖实际 Spaces、滚动、缩放、可见性。 |

格式实现对比：ProNotes 的资源包含 `addLink/editLink/alignLeft/center/alignRight/justify/table`，OpenNotes FormatAction 均无对应 case。ProNotes 13.5 使用 `Monospaced`，14.6+ 改为 `Monostyled`，14.6 添加 `blockQuote`，15.5 添加 `highlight`。OpenNotes 原样继承 NotesPlus 的虚拟键码，未读取菜单能力、当前菜单快捷键或本地化路径。公开源码可以重新实现菜单能力适配；不需要照搬厂商资源文本。

## 2. 精确 Markdown 触发合同

P-WEB 明确要求行首符号后空格；下表逐项对照。OpenNotes 实际目录来自 [MarkdownTriggerDefinition](../src/Quillside/Services/MarkdownTriggerService.swift)；键盘监视器仅在其内存 buffer **等于** pattern 时发事件，之后才由 InlineInputEdit 验证真实正文的行首。

| ID | 输入 → 原厂定义 | NotesPlus | OpenNotes |
|---|---|---|---|
| MD-01 | `# ` → Title | 有 | **代码实现/待验证** |
| MD-02 | `## ` → Heading | 有 | **代码实现/待验证** |
| MD-03 | `### ` → Subheading | 有 | **代码实现/待验证** |
| MD-04 | `[] ` → Checklist | 有 | **代码实现/待验证** |
| MD-05 | 三反引号 + 空格 → Monostyled | 无 | **缺失**，官网明确稳定功能；设置字符串亦有 `expand-markdown-monostyled`。 |
| MD-06 | `> ` → Block Quote | 有 | **代码实现/待验证** |
| MD-07 | `- ` → Dashed List | 错映射 bullet | **已修正目录**为 dashList；需实机确认原生动作结果。 |
| MD-08 | `* ` → Bulleted List | 有 | **代码实现/待验证** |
| MD-09 | `1. ` → Numbered List | 有 | **代码实现/待验证** |
| MD-10 | 已格式化行可转列表（P-WEB） | 只有按键路径 | **待验证**：需在标题/引用/等宽行内分别测试 `- `、`* `、`1. `。Apple Notes 自带普通行转换不能代替此要求。 |
| MD-11 | Markdown 总开关（P-UI） | service setter，无 UI 接线 | **缺失用户入口**：setEnabled/loadPreferences 存在，但 App/Settings/Menu 无调用。 |
| MD-12 | 按触发类别开关（P-STR） | service setter，无 UI 接线 | **机制部分**：8 项 Set 持久化，但没有设置控件；ProNotes 每个字符串对应的可见 UI 尚需复查。 |

原厂没有在本次证据里承诺 `#### `、`[ ] `、行内 `**bold**`、行内反引号或任意编号触发；可作为额外能力，但不要把未核实的别名归为原厂已知稳定要求。

## 3. 精确 slash 命令合同与状态机

OpenNotes 当前 catalog 有 `h1,h2,h3,body,bullet,number,todo,quote,code,bold,italic,underline,strike`。筛选为 id/name/中文 description 的子串匹配，没有独立 aliases。下面结果是对当前源码 catalog 和过滤表达式做的确定性对照，不是模拟输入实测。

| ID | 官网输入 | 当前匹配和执行结果 | 状态 |
|---|---|---|---|
| SC-01 | `/title`、`/h1` | `title` 无匹配；`h1` → title | **部分，缺 title alias** |
| SC-02 | `/heading`、`/h2` | `heading` 同时匹配 h1/h2/h3，默认 selectedIndex=0 → **title**；`h2` 正确 | **错误的精确别名优先级** |
| SC-03 | `/subheading`、`/h3` | `subheading` 无匹配；`h3` → subheading | **部分** |
| SC-04 | `/body` | body | **代码实现/待验证** |
| SC-05 | `/monostyled`、`/code` | monostyled 无匹配；code → monostyled shortcut | **部分** |
| SC-06 | `/checklist` | 无匹配；仅 `/todo` 可命中 | **缺失原厂 alias** |
| SC-07 | `/bulletedlist` | 无匹配；名称为 `Bullet List`，含空格、无 `ed` | **缺失原厂 alias** |
| SC-08 | `/dashedlist` | 无对应 slash action，虽 FormattingService 有 dashList | **缺失** |
| SC-09 | `/numberedlist` | 无匹配；仅 number/Numbered List 子串 | **缺失原厂 alias** |
| SC-10 | `/quote`、`/blockquote` | quote 正确；blockquote 无匹配 | **部分** |
| SC-11 | `/table` | 没有 catalog 或格式 action | **缺失原生表格插入** |
| SC-12 | 模板通过 slash 插入（P-WEB/P-STR） | catalog 不连接模板 | **缺失**；工作台模板不满足此交互要求。 |
| SC-13 | 列表上下选择、点击、Esc、Return、Tab | service 分支俱在；菜单滚动跟随选中 | **部分/待验证**；事件拦截实际只消费上下箭头。 |
| SC-14 | slash 总开关（P-UI） | 无 enabled 字段或设置入口 | **缺失** |
| SC-15 | 搜索/正文/IME 的正确触发边界 | 只判断 Notes frontmost | **缺少边界实现**，详见 R-01/R-02。 |
| SC-16 | 顶部字样、空结果、分页定位等显示 | 两类别 SwiftUI ScrollView/固定非激活面板 | **代码实现/待验证**；是上游交互，不是对原厂菜单视觉的一比一确认。 |

额外 slash 粗体、斜体、下划线、删除线是 NotesPlus 已有扩展，不能拿这四个数目抵消 table、dashedlist 和原厂 aliases 缺失。[当前命令与执行路径](../src/Quillside/Features/SlashCommand/SlashCommandService.swift)；[键盘拦截路径](../src/Quillside/Services/KeyboardMonitorService.swift)。

## 4. 模板、搜索、反链与导出

| ID | 对标能力 | OpenNotes 现状与边界 |
|---|---|---|
| TP-01 | 保存重复片段 | **代码实现（新增）**：[SnippetTemplate](../src/Quillside/AI/AIConfiguration.swift) 与 [TemplateLibraryView](../legacy/standalone-workspace/WorkspaceView.swift) 可增删改，JSON 持久化，初始会议/阅读模板。 |
| TP-02 | slash 里搜索并插入模板 | **缺失**：工作台只预览，用户须先捕获，再从写作页局部插入/替换。 |
| TP-03 | ProNotes 模板来源及命名协议 | **原厂行为未证实**：[原厂模板文档](https://dexterleng.notion.site/How-to-use-Templates-in-Apple-Notes-with-ProNotes-b35a196d29c54cd8a553723a1289f80f?pvs=4) 本次仍 404。不能将本地独立模板库写成原厂完全相同发现机制。 |
| TP-04 | 模板变量 | **扩展已实现**：单次 `{date}` 替换；没有任意输入字段、cursor placeholder、脚本执行。原厂具体变量支持未证实。 |
| TP-05 | 富文本、表格、附件模板 | **当前缺失/原厂范围未完全证实**：SnippetTemplate 是 String，SelectionTransaction 只写纯文本。需要合成样本确认原厂合同后再评估完整保真。 |
| SR-01 | Notes 内快捷键搜索 | **代码实现**：硬编码 `⌘P`，打开大工作台并读取标题/摘要。[AppShortcutMatcher](../src/Quillside/Services/AppShortcutMatcher.swift)。 |
| SR-02 | 系统范围搜索快捷键 | **代码实现**：Carbon 注册 `⌥⌘P`，[GlobalSearchShortcut](../legacy/retired-features/src/Quillside/Services/GlobalSearchShortcut.swift)；没有注册错误/冲突反馈。 |
| SR-03 | 两个快捷键可自行配置（P-WEB/P-UI） | **缺失**：Settings 只显示文本。ProNotes 该用户实例曾为 Not set，不应该误读成强制默认热键。 |
| SR-04 | 键盘友好的命令面板（P-WEB） | **部分**：Workspace List 无 selection binding、无上下/Return 行为、无打开即聚焦搜索的 FocusState；用户可点行右侧“打开”，这不等同 command palette。 |
| SR-05 | 标题、摘要、文件夹搜索 | **代码实现（新增）**：[WorkspaceModel.filteredNotes](../legacy/standalone-workspace/WorkspaceModel.swift) 对三字段拼接做 case-insensitive contains；数据库顺序为置顶+修改时间，不是标题匹配优先。 |
| SR-06 | 全库完整正文搜索 | **缺失**：Notes 搜索仅 metadata；已主动导入的知识库可以搜正文。官网“search notes”未详述字段，不宜把全库 FTS 当成原厂已验证细节。 |
| SR-07 | 新建/改名/删除后搜索刷新 | **部分**：快捷键或“加载 Notes”重新读库；非持续索引/增量更新。 |
| BL-01 | 原生 note link → 反向来源 | **代码实现（继承）**：attachment token URL 与 gzip/protobuf 链接双路径解析，BacklinkGraphBuilder 排除自己和未知目标。 |
| BL-02 | 展示当前笔记的反链 | **代码实现/待验证**：AX 候选标题匹配 + AppleScript 兜底、panel request generation、权限状态；不靠正文纯字符串标题识别链接。 |
| BL-03 | 点击来源回到 Notes | **代码实现/待验证**：`applenotes:note/<UUID>`，需要 macOS 14/15/26 上确认跳转与独立窗口行为。 |
| BL-04 | 链接新增/移除及时更新 | **部分**：缓存 30 秒后按查询重建，有刷新和失效路径；无数据库变更监听。两个 SELECT 阶段不共享显式事务，不能声明一致时点的全库图。 |
| BL-05 | 查询失败可区分真正无反链 | **部分**：权限/数据库打开失败有 UI；SQL schema/prepare/step 错误仍可能返回空数组，见 R-07。 |
| EX-01 | 复制整篇 Markdown | **代码实现（继承）**：AppleScript HTML → XMLDocument 转换 → 延迟提交剪贴板；不走新增 NotesBridge decoder。[NoteActionsService](../src/Quillside/Features/NoteActions/NoteActionsService.swift)。 |
| EX-02 | 标题、粗斜体、下划线、删除线、链接、引用、列表、代码 | **代码实现**：converter 处理相应 HTML 标签，有合成 HTML 单测；实际 Notes HTML 表示未实机穷尽。style-only 格式没有专门解析。 |
| EX-03 | 清单/表格 | **部分/待验证**：支持合成 `<li data-checked>` 和 `<table>`；不能证明 AppleScript 返回的原生 checklist/table 与这些合成标签相同。 |
| EX-04 | 附件/图片导出 | **降级实现**：当前明确输出 `[图片]`/`[附件: 文件名]` 占位，不复制附件、不生成可用资源链接。原厂有 exporter/attachment converter 线索，实际保真水平待采样。 |
| EX-05 | 复制 deeplink | **代码实现/待验证**：UUID 原生链接写 `.string` 和 `.URL` 两种 pasteboard 类型；没有联网分享链接、未创建公开笔记。 |
| EX-06 | markdown/链接/反链快捷入口 | **代码实现**：菜单与 Notes event tap；Settings 把若干项称“全局快捷键”，但只有搜索注册 Carbon 全局键，其他 matcher 在 Notes frontmost 才触发。 |

## 5. AI 与用户明确要求的配置/知识层

| ID | 要求 | OpenNotes 本次状态与准确边界 |
|---|---|---|
| AI-01 | 续写、润色、纠错、摘要/列表摘要/表格摘要、变长、变短、解释（P-UI） | **代码实现**：9 项语义对应预置指令；额外翻译、自定义、知识问答共 12 项。提示词独立编写，不复制原厂私有文本。 |
| AI-02 | 自定义动作与 `{text}`（P-UI） | **代码实现**：本地增删改 PromptAction，renderer 单次白名单替换；没有对递归正文大括号再执行。 |
| AI-03 | 可编辑系统提示词和模型（P-UI） | **代码实现**：系统提示词、写作偏好、模型 ID、协议和最大输出 token；与原厂曾只显示两个模型的界面不同，是用户要求的扩展。 |
| AI-04 | 对选区或整篇笔记工作（P-UI） | **代码实现/待验证**：有选区用选区，无选区用捕获元素 body；需要确认实际 focused AXTextArea 是否确实整篇而非单元格等子编辑器。 |
| AI-05 | 原生贴近选区的 AI 体验 | **部分**：捕获后切到 1040×760 独立工作台，没有 FloatingBar 的 Ask AI/内联指令菜单。 |
| AI-06 | 流式预览、取消、完整结束校验 | **代码实现（新增）**：[ModelClient](../src/Quillside/AI/ModelClient.swift)、[WorkspaceModel](../legacy/standalone-workspace/WorkspaceModel.swift)；源码拒绝截断/提前 EOF，不把已收到部分文本自动应用。真实服务商兼容性需真实连接验证。 |
| AI-07 | 结果替换/插入、切换笔记拒绝写入 | **代码实现/待验证**：PID/窗口/AppleScript identity/全文 equality/UTF-16 选区校验后 AXSelectedText 替换，读回文本。没有实际原生 undo 证据，也没有富文本输入转换。 |
| AI-08 | 表格摘要产生原生 Notes 表格 | **缺失**：指令让模型生成 Markdown table，应用仍纯文本。生成表格语法与插入原生表格是两层要求。原厂此输出端到端亦未验。 |
| CF-01 | 服务商/API URL/API Key 自配 | **扩展代码实现**：四协议、多 ModelConnection、Keychain，密钥不进入配置 JSON；是用户明确需求，非原厂已证实功能。 |
| CF-02 | 多用途独立模型 | **部分**：每连接仅一个 model，UI 一个默认 selectedConnectionID；没有独立写作/摘要/知识/embedding routing profile。原研究提出此方案，尚未落实。 |
| CF-03 | 连接测试/配置导入导出 | **代码实现**：固定合成文本生成，流式结束后提示；导入重建连接 UUID 防止自动继承旧密钥。不能由 mock 测试推断真实账号有效。 |
| KB-01 | 主动选择 Notes/MD/TXT/PDF | **扩展代码实现**：只导入选中 Notes，PDFKit 提取页文字；无扫描 OCR、图片理解、附件正文递归导入。 |
| KB-02 | 本地检索和来源 | **扩展代码实现**：SQLite FTS5+NaturalLanguage 分词+短语 substring，800 字片段/100 重叠，最多 8 个命中；来源可打开，`[S1]` 有编号范围验证，不能保证答案与证据语义一致。 |
| KB-03 | 集合管理 | **部分**：Notes 文件夹名及统一“文件”分组，选择集合检索；没有集合对象增删改、同一来源多集合、用户自定义来源规则。 |
| KB-04 | 来源变更/删除/锁定清理 | **部分**：用户按“更新 Notes 快照”时同步更新/移除，文件重导入按路径替换；没有后台监听、授权范围持续同步、删除文件自动失效。 |
| KB-05 | embedding 模型与向量召回 | **缺失（研究方案中可后置）**：当前 FTS，不是向量 RAG；不要把 NotesBridge 的属性解码或模型选项当成 embedding 配置。 |

本节列出新增模块为保证全代码功能视野，不代替协议/知识库的独立测试审计；不能因新增 AI/知识能力多于原厂，就从“完全对标”中移除缺失的编辑功能。

## 6. 系统与设置

| ID | 原厂证据/用户目标 | OpenNotes 状态 |
|---|---|---|
| SYS-01 | 登录启动（P-UI） | **代码实现**：SMAppService register/unregister；ad-hoc 包实际登录项状态尚需验。 |
| SYS-02 | 菜单栏显示开关（P-UI） | **缺失**：MenuBarExtra 总是构造，无 isInserted binding。 |
| SYS-03 | 工具条/slash/Markdown 开关（P-UI） | **缺失用户控制**；初始化获取 AX 权限后全部启动。 |
| SYS-04 | 语言选择（P-UI） | **缺失**：当前硬编码中文/部分英文；无 String Catalog、本地化资源或语言偏好。 |
| SYS-05 | 权限/数据库连接诊断 | **代码实现**：AX、Automation、Full Disk Access 分开；数据库能 open 不等于私有 schema 可读。 |
| SYS-06 | 自动更新（P-UI/Sparkle 静态线索） | **缺失**：没有更新 feed、签名更新或检查 UI；公开发布/公证也尚未完成。 |
| SYS-07 | 匿名崩溃报告（P-UI/Sentry 静态线索） | **未实现远程上报**：目前本地日志、无账户/遥测。无需为开源替代强行复制账号/商业后端，但完整产品差异须披露。 |
| SYS-08 | 原生栈 | **代码实现**：Swift/SwiftUI/AppKit、原生 AX/Carbon/SQLite/Security，没有 Electron web shell。 |
| SYS-09 | 可维护的开源代码/许可 | **文件存在**：MIT 与第三方 notices；公开 GitHub 仓库/release 不是由本次源码审计证明。 |
| SYS-10 | Floating notes、Vim（P-WEB 标 WIP） | **没有实现**；必须继续列在完整对照里，不能伪造稳定合同。实现同类稳定版无需把原厂 WIP 当成已发布能力；若最终用户要求也纳入，须另立明确行为验收。 |

## 7. 源码风险与上游移植变化

以下是能解释具体失效场景的发现。没有把推断写成已经发生的用户事故。

| ID / 来源 | 场景与源码证据 | 影响、修复或验证要求 |
|---|---|---|
| R-01 / 继承 | SlashCommandService 72–90 行只检查 Notes frontmost；输入任意 `/` 激活，KeyboardMonitorService 193–197 行随后吞上下箭头；未检查正文编辑角色或组合输入。 | 在 Notes 搜索框、对话框或输入法候选期间输入 `/` 也能劫持上下键。应先绑定正文会话、检查实际前缀和组合状态，焦点/光标改变立即取消。仅在执行删除时做 AXTextArea guard 已晚于吞键。 |
| R-02 / 继承+本地改动 | KeyboardMonitorService 只吞上下，Return/Tab 会传给 Notes。执行新 InlineInputEdit 时 Return 允许 `trigger+\n`，Tab 不允许 trailing tab，且焦点可能已移动。 | Tab 分支声称执行，但原编辑器插入 tab/跳焦点后很可能无法删除前缀。需要统一在可确认安全时消费确认键；未知/IME 状态放行并取消菜单。必须验 Return、numeric Enter、Tab、Shift-Tab 和中文候选。 |
| R-03 / 本地兼容性变化 | 上游用合成 backspace 删除；OpenNotes 改为 InlineInputEdit AXSelectedTextRange+AXSelectedText，且立即回读比较。 | 明显减少盲删风险，但 Notes 若不支持 selectedText set 或异步提交，触发会静默失败；需要 real AX 能力探测、可验证原生局部编辑路径与 undo。不能把安全失败当成功复刻。第二步失败还可能留下选中的触发文本，下一按键有不同效果。 |
| R-04 / 继承 | KeyboardMonitorService buffer 仅随 key events 清理；鼠标重定位、focusedElementChanged、focusedWindowChanged 不清理；Markdown 检测 `inputBuffer == pattern`。 | 用户先打普通文字，再鼠标点到新行键入 `## `，buffer 可能仍含旧字符，真实行首也不触发。反向场景新 InlineInputEdit 会拒绝非行首，防误删但不解决漏触发。应从正文/caret 推导已提交前缀。 |
| R-05 / 继承 | FormattingService 所有动作只检查 Notes frontmost，发 CGEvent 后返回 Void；没有菜单 enabled/capability 或执行结果。Markdown/slash 先移除触发文本再按格式键。 | 不支持的格式、改过的快捷键、非正文焦点会导致删掉命令后无格式或执行别的动作；需先证实可执行菜单路径，并在同一会话完成，可恢复或有明确失败反馈。 |
| R-06 / 继承 | AccessibilityBridge.getSelectionSnapshot 无正文角色限制；FloatingBarViewModel 点击直接调用当前 Notes 快捷键，无 captured selection identity。 | 选择搜索框文本也可能出现栏；从显示浮层到点击期间更换笔记/选区可能作用于不同文本。生成保护只存在于新 AI SelectionTransaction，没有保护旧格式栏路径。 |
| R-07 / 继承及新增复用 | NotesDBReader.accessStatus 仅尝试 SQLite open；getAllNotes/getAllNoteLinks prepare 失败返回 `[]`，step 循环没有区分 DONE/error。Backlinks 构建把返回值提交，Workspace loadNotes 报“已读取 0”。 | schema 不兼容/读取错误可伪装成空库/无反链。应使读取返回 typed failure，保留旧成功状态或显示不可用，并用缺列/step 错误合成库验。当前测试 `testReadableSQLiteDatabaseIsAvailable` 不能证明业务 schema。 |
| R-08 / 继承 | BacklinksService 115/128 行分别读 notes 和 links，没有共享读事务，30 秒缓存。 | 并发 Notes 保存可产生不同快照拼接/短时漏链；需要一致事务和真实链接新增/删除时序测试。不是每个只读 SELECT 都自动构成全流程一致快照。 |
| R-09 / 继承 | Markdown converter 基于 AppleScript HTML，img/object 仅占位，未读取 CSS 格式；NotesBridgeDecoder 只用于知识导入。 | “整合 NotesBridge 解码器”并未增强 Copy Markdown 的原生对象保真；必须分开验 API HTML、protobuf、附件和表格。 |
| R-10 / 新增 | GlobalSearchShortcut 忽略 InstallEventHandler/RegisterEventHotKey OSStatus；搜索没有 focus/selection/Return UI。 | 快捷键冲突时设置仍展示可用且无诊断；键盘入口不等于键盘友好完成搜索。 |
| R-11 / 新增 | SelectionTransaction.capture 先读取 AX body/window，再同步 AppleScript 获取 Notes selection identity；apply 独立检查 identity、window 和 body。 | 不同 Notes 窗口的 AppleScript selection 是否与 focused AXTextArea 一致仍须实机证实；无 identity 时只允许预览/复制是合理失败，但不是已验证写回。重复文本/独立窗口/表格编辑和 undo 为必验项。 |

移植的正向变化也需保留：`- ` 已从 bullet 修为 dash；slash 不再把任何物理 44 键都当 `/`，并排除 Cmd/Ctrl/Option；新 InlineInputEdit 使用 UTF-16 精确正文范围替代按键计数；API Key 与 endpoint origin 分离保护；AI 生成和 Notes 写入拆开。这些变化改进可靠性，但仍需上述真实路径验收。

## 8. 测试证据究竟覆盖什么

本次只阅读测试，没有重复运行测试；先前交付的“107 通过、2 跳过”是先前轮次结果，不能覆盖本文新增发现或后来代码变更。

| 测试文件/断言 | 可证明 | 不能证明 |
|---|---|---|
| FeatureCatalogTests：固定 8 patterns、13 commands | 当前数组没有意外改变 | ProNotes 全目录覆盖；相反会把已知缺项固化为预期。需改用官网合同 aliases/action fixtures。 |
| FloatingBarViewModelTests / SelectionFormattingAnalyzerTests | mock formatter 调用、合成 AX 属性映射及 runs 交集 | AX 实际角色、真实菜单执行、字体全语言识别、原生 undo。 |
| AIAndKnowledgeTests 的 `markdownAndSlashDeletionRequireVisibleExactTrigger` | 几个 String/NSRange 计算样本 | 实际 event tap 吞键、Tab、IME、组合输入、多窗口、AX 写入支持和实时序列。 |
| CurrentNoteResolverTests / NoteActionsTests | 注入环境下 identity、permission、timeout、异步结果丢弃和剪贴板提交 | 系统 AppleScript selection 与 focused window 对应、真实 Notes HTML 完整性。 |
| BacklinksGraphTests | 合成 gzip/protobuf/sqlite 图结构、删除文件夹过滤、缓存 generation | 本机数据库/真实编辑更新；真实快照测试由环境变量控制，默认跳过。 |
| AppleNotesMarkdownConverterTests | 构造 HTML 的标题/列表/表格/代码转换与占位结果 | Apple Notes 所有内容的实际导出形态；测试已经明示附件只输出占位。 |
| WindowTrackingTests | lifecycle/坐标策略与 health check 逻辑 | 实际 AX notifications、Spaces/全屏/滚动、多个显示器的 UI 稳定性。 |
| ReadmeScreenshotTests | 可选离屏样式截图 | 用户操作端到端；默认跳过。 |
| AIAndKnowledgeTests 的 localhost provider loop | 固定模拟服务与协议解析闭环（仅设置 env 时） | 云端模型 ID/认证/限流/服务商版本、真实质量、真实 Notes 应用。 |

建议验收按真实要求组织，不按当前模块数组长度组织：官网输入合同 → 编辑目标有效性 → 操作/回读/undo → 配置重启持久化 → 不支持系统/权限的可诊断失败。每个稳定功能至少一个成功样本与一个相关失败/切换样本。

## 9. 全部源码文件差异索引

“同上游”指把 `NotesPlus/notesplus` 品牌替换为 `OpenNotes/opennotes` 后字节文本相同；不是独立证明代码正确。新增 NotesBridgeDecoder 有另外的 MIT 来源，不是全新原创解析器。

| 文件（src/OpenNotes 下） | 与 NotesPlus 对照 | 本次关注的功能 |
|---|---|---|
| AI/AIConfiguration.swift | 新增 | 协议、连接、提示词、模板、JSON、Keychain |
| AI/ModelClient.swift | 新增 | 请求构造、流式结束语义、取消/网络 |
| App/AppDelegate.swift | 修改 | 服务装配、权限刷新、搜索/AI 快捷入口 |
| App/AppState.swift | 同上游 | 权限与 Notes 状态 |
| App/MenuBarView.swift | 修改 | 增加工作台/AI/搜索，保留动作与诊断 |
| App/OnboardingView.swift | 修改 | 说明 AI 数据流，原权限操作保留 |
| App/OpenNotesApp.swift | 同上游 | MenuBarExtra/Settings/onboarding scene |
| App/OpenNotesStyle.swift | 修改 | 品牌样式，非功能扩展 |
| App/SettingsView.swift | 修改 | 登录启动、快捷键说明；缺功能开关/排序/语言 |
| Features/Backlinks/BacklinksPanelView.swift | 同上游 | 反链面板状态、来源跳转 |
| Features/Backlinks/BacklinksPanelViewModel.swift | 同上游 | 当前 note、刷新和构建订阅 |
| Features/Backlinks/BacklinksPanelWindowController.swift | 同上游 | 跟踪、定位、权限/切换 generation |
| Features/FloatingBar/FloatingBarView.swift | 同上游 | 固定十个格式按钮 |
| Features/FloatingBar/FloatingBarViewModel.swift | 同上游 | 格式委托、选中动作状态 |
| Features/FloatingBar/FloatingBarWindowController.swift | 同上游 | 选区浮层显示/定位 |
| Features/FloatingBar/SelectionFormattingAnalyzer.swift | 同上游 | AX 字体/列表/高亮启发式 |
| Features/NoteActions/NoteActionsBarView.swift | 修改 | 启用 Ask AI 工作台捕获 |
| Features/NoteActions/NoteActionsBarViewModel.swift | 同上游 | 异步 note resolve、反馈、剪贴板提交保护 |
| Features/NoteActions/NoteActionsBarWindowController.swift | 同上游 | 底部动作栏跟随 Notes |
| Features/NoteActions/NoteActionsService.swift | 修改 | AI catalog 变可用，复制/反链路径保留 |
| Features/SlashCommand/SlashCommandService.swift | 修改 | slash 触发字符 guard 与精确删前缀；目录仍上游 13 项 |
| Features/SlashCommand/SlashMenuView.swift | 同上游 | 分组/列表/选中滚动/点击 |
| Features/SlashCommand/SlashMenuWindowController.swift | 同上游 | 非激活浮层、光标/鼠标定位 |
| Knowledge/KnowledgeIndex.swift | 新增 | FTS5、中文分词、集合、upsert/delete |
| Knowledge/NotesBridgeDecoder.swift | 新增（引自 NotesBridge） | note proto 文本/属性解析；当前消费者只索引 noteText |
| Services/AccessibilityBridge.swift | 同上游 | AX 进程/窗口/选区与权限 |
| Services/AppShortcutMatcher.swift | 修改 | 新增 ⌘P/⌥⌘A，保留原动作 |
| Services/AppleNotesAutomationAccess.swift | 同上游 | Apple Events 许可状态 |
| Services/AppleNotesIdentifierParser.swift | 同上游 | Core Data/native UUID/标题候选匹配 |
| Services/AppleNotesMarkdownConverter.swift | 同上游 | HTML→Markdown、附件占位 |
| Services/AppleNotesProtobufLinkParser.swift | 修改 | gunzip 暴露给新增 decoder，链接解析逻辑保留 |
| Services/BacklinksService.swift | 同上游 | 反链图、缓存、构建失效保护 |
| Services/CurrentNoteResolver.swift | 同上游 | AX 标题/AppleScript 识别与 HTML body |
| Services/FormattingService.swift | 同上游 | 固定 Notes 格式快捷键 |
| Services/GlobalSearchShortcut.swift | 新增 | Carbon 搜索热键 |
| Services/InlineInputEdit.swift | 新增 | 精确 UTF-16 前缀选择/删除与读回 |
| Services/KeyboardMonitorService.swift | 同上游 | CGEvent tap、输入 buffer、上下键拦截 |
| Services/MarkdownTriggerService.swift | 修改 | dash 映射修正、使用 InlineInputEdit |
| Services/NotesDBReader.swift | 修改 | 增加主动 Notes 知识导入；旧 query/权限路径保留 |
| Services/WindowGeometry.swift | 同上游 | 多屏 AX/Cocoa 坐标转换 |
| Services/WindowTrackService.swift | 同上游 | AX 观察、恢复、窗口与选区 snapshot |
| Workspace/SelectionTransaction.swift | 新增 | 捕获身份/全文/UTF-16、局部 AX 替换及回读 |
| Workspace/WorkspaceModel.swift | 新增 | 写作/检索/导入/快照/模板编排 |
| Workspace/WorkspaceView.swift | 新增 | 工作台、连接/指令/模板设置 |

## 10. 后续实现与完成门槛

1. **先补确定性合同差异**：三反引号触发；官方 slash 别名与精确优先级；dashedlist/table；工具条 Ask AI、Font、Link、Alignment、Checklist；排序/显隐；三个功能开关；两种搜索快捷键配置。
2. **完成原厂核心交互**：slash 模板、键盘导航搜索面板、默认焦点/上下/Return/Escape。当前独立工作台可保留，但不能充作已经完成内联体验。
3. **使旧编辑路径可靠**：正文会话与输入法边界、生命周期取消、按菜单能力执行、命令删除与应用一致、真实回读和原生 undo。保留精确范围验证，不能退回无目标的按键计数删除来“让测试过”。
4. **验证数据能力**：真实合成 Notes 的反链新增/删除、复制原生表格/清单/附件；SQL 失败不伪装零结果；确认哪些内容只能降级并在产品中披露。
5. **落实用户配置终态**：已有 BYOK/提示词/FTS 是有效进展；独立模型用途、集合管理与向量配置是否属于最终合同，应按原研究与用户需求逐项确认/实现，不能默默删减。
6. **最终声明前做完整证据审计**：每项 TB/MD/SC/TP/SR/BL/EX/AI/CF/KB/SYS 关联当前代码、必要单测和实机结果。测试数、安装包存在、锁屏导致的测试中断、原厂 WIP 和模板文档 404 都不是“全功能已完成”的证据。

本次没有执行发布、改产品代码或更改用户 Notes。后续若实现发生变化，应保留这里的发现来源，并将对应行更新为新的代码与验证结果，避免本报告变成过期缺陷列表。
