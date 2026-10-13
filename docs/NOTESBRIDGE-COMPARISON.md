# NotesBridge 全源码功能对比与 OpenNotes 整合边界

> 历史实现/审计记录。2026-10-08 最新范围与当前状态见 [功能清单](CURRENT-FEATURES.md)；搜索与知识库已退出，笔记文件导入导出延期。

> 本文记录此次修复前的审计基线。2026-10-08 的修复与剩余验收见 [持续对齐状态](GOAL-STATUS.md)；旧差距行保留作为问题依据，不能当作最新实现状态。

审阅开始日期：2026-10-07。目标：为“原生、开源、完整对标 ProNotes，并能配置模型、API Key、提示词和个人知识库”的长期任务提供可追溯差距清单；这份文件只负责 NotesBridge 这一上游，不代替 ProNotes 本体及其他项目的对照。

上游：`https://github.com/peizh/NotesBridge`，固定提交 **`91bccb0d34205d9813508de8146ea07540ac161f`**。本地只读检视路径：`/tmp/pronotes-github-research/NotesBridge`；审阅开始时 `git status --short` 为空。OpenNotes 以本次读到的工作目录为准；其所在 Git 仓库尚无有效 HEAD，不能把工作区内容冒充某个已提交版本。

审阅覆盖 62 个 `Sources/NotesBridge/**/*.swift`、23 个测试文件、Package/锁文件、README/CHANGELOG/架构与自动同步文档、发布脚本和 CI 配置。依据包括实际分支、调用点、UI 绑定和测试断言。**未运行上游测试、未启动应用、未读取用户笔记、未修改上游；本报告的“已实现”表示代码路径存在，不表示实机验收完成。** 后附全部源文件及测试文件清单，避免把未提及文件误认成没有功能。

## 结论和复用策略

NotesBridge 有两条独立产品链：一条通过 Accessibility 和键盘／菜单操作增强 Notes；另一条从 Notes 私有数据库及附件目录读取，导出为 Obsidian 风格 Markdown 文件。它并没有 LLM 连接、API Key、提示词编辑器、RAG 问答、模板库或反链面板。OpenNotes 目前从 NotesBridge 移植的主要部分是 **Protobuf 正文与属性解码结构**，没有移植它的富文本渲染、表格／扫描附件解析、导出器、同步调度或 Sparkle。[NB-decoder] [NB-app] [ON-notices]

优先补齐与 ProNotes 编辑体验直接相关的：原生表格和链接命令、三反引号触发、slash 边界与精确命令提交、工具条和 slash 项目显隐与排序。富文本／附件解码可增强 Markdown 导出和知识库的材料完整性。Obsidian 全量／增量同步是值得保留的上游扩展清单，**不能仅因上游有它就把它自动算作 ProNotes 的必备功能，也不能用完成同步来代替 ProNotes 功能对标**。

同样不能把有同名函数当作产品已具备该功能：上游存在 `AppleNotesScriptClient.updateNote` 和 `MarkdownTransformer.markdownToHTML`，但当前生产 UI／同步路径未调用它们；它们不证明双向同步或 Markdown 原生粘贴已完成。`rg` 调用点检查显示 `MarkdownTransformer` 的构造只见于测试，正文同步使用数据库解码路径。[NB-script] [NB-transform] [NB-app]

状态含义：**已实现**＝OpenNotes 有对应可达代码；**部分**＝只有子集或不同交互；**缺失**＝产品目录未找到对应实现；**上游辅助代码**＝存在源码但不是现有可达产品功能。每项另列验收，避免把源码和运行证据混在一起。

## A. 编辑增强：直接影响同类 App 的功能对标

| ID | NotesBridge 实际行为与依据 | OpenNotes 当前对应 | 状态／具体差距 | 验收证据要求 |
|---|---|---|---|---|
| A01 | 选中文字后浮动格式栏；选区消失、权限／开关不可用则隐藏。`FloatingFormattingBarController.update` [NB-float] | `FloatingBarWindowController`、`FloatingBarView` | 已实现同类入口，样式与定位实现不同 | Notes 正文选择／取消选择、切 App、切笔记、权限撤回、真实点击后格式变化和撤销 |
| A02 | Title、Heading、Subheading、Body；快捷键与菜单优先路径 [NB-format] [NB-executor] | `FormattingService.setHeading` | 已实现命令；不表示所有语言 Notes 菜单已验证 | 4 种段落格式逐个读回，不只检查发出 CGEvent |
| A03 | Bold、Strikethrough；上游枚举没有 Italic／Underline [NB-format] | `FormattingService`、`FloatingBarViewModel` | 已实现，OpenNotes 另有斜体、下划线、高亮 | 混合格式选区、连续切换、菜单状态、撤销；不要因为 README 提及 italic 就记作上游实际枚举 |
| A04 | Checklist、Bulleted、Dashed、Numbered list [NB-format] | `.todoList/.bulletList/.dashList/.numberedList` | 格式服务已实现；当前 slash 缺 dashed 的入口 | 行首／段落中／多行选区、嵌套列表、取消列表、撤销 |
| A05 | Block Quote、Monostyled [NB-format] | `.quote/.codeBlock`，另有 monospaced 浮条操作 | 已实现同类命令；Monostyled 是 Notes 段落样式，不等于真正的代码编辑器 | 中文和英文输入法下应用、跨段落选区及撤销 |
| A06 | Insert Link：Edit → Add Link 或 ⌘K [NB-format] [NB-executor] | `FormatAction` 不含 link；复制笔记链接属于不同动作 [ON-format] [ON-actions] | **缺失原生插入链接命令** | 浮条和 slash 均可打开 Notes 原生链接操作；文本和目标 URL 正确 |
| A07 | Table：Format → Table 或 ⌥⌘T [NB-format] [NB-executor] | `FormatAction` 和 slash 目录均无 table [ON-format] [ON-slash] | **缺失原生插入表格命令**；HTML 转 Markdown 能读表格不能代替创建表格 | `/table` 后真实插入可编辑 Notes 原生表格；邻接正文保持、单步撤销 |
| A08 | Markdown 行首匹配 9 项：`# `、`## `、`### `、`[] `、三反引号＋空格、`> `、`- `、`* `、`1. ` [NB-markdown] | `MarkdownTriggerDefinition.all` 8 项 [ON-markdown] | 部分：**缺三反引号＋空格** | 全部模式＋负例：段落中、已格式化列表、中文／emoji 前文、粘贴、快速切窗 |
| A09 | Markdown 通过 120ms AX 轮询识别已落到编辑器的触发文本，再逐次 Delete [NB-markdown] [NB-executor] | `KeyboardMonitorService` 事件流；`InlineInputEdit.remove` 验证局部文本再写入 | 部分／实现不同；OpenNotes 的局部校验值得保留，不能直接回退成盲删 | 准确删除触发串，前后文字不变；AX 写失败不格式化；Unicode 范围和撤销验证 |
| A10 | slash 目录为 14 类命令；别名、大小写无关前缀匹配；菜单标题随语言变化，token 不翻译 [NB-catalog] | 当前 13 项，用 ID／英文名／中文说明 contains 搜索 [ON-slash] | 部分：缺 table、link、dashed；上游别名如 `/title`、`/heading`、`/checklist`、`/bulletedlist`、`/numberedlist` 等并非一概可用；OpenNotes 另有 italic、underline | 固定目录表＋所有别名、中文搜索、无命中和选择索引测试，随后实机提交 |
| A11 | slash 仅识别空白分隔 token；忽略词内 `hello/title`、URL、未知路径；光标前有换行仍可定位 [NB-parser] | 键盘流看到 `/` 就 activate，执行时再由 `InlineInputEdit` 保护 [ON-slash] | 部分：**菜单触发边界不等价**；不能仅凭最终写入保护说不会误弹 | URL、路径、`a/b` 不弹；段落中空白后 `/` 弹；剪贴／鼠标移动后状态准确 |
| A12 | 完整别名＋Space 自动提交，并删除 token 和尾空格；或鼠标、Return／Tab／小键盘 Enter 提交 [NB-parser] [NB-slash] | Return／Tab／Enter／鼠标存在，Space 不执行精确匹配 [ON-slash] | 部分：缺 **exact command + Space** | 匹配时删除范围正确；未知命令保留原文；不同提交键不会多留换行／Tab |
| A13 | ↑↓ 循环选择、Escape 关闭；对同一 token 记录 dismiss signature，避免下一轮立即重弹 [NB-slash] | ↑↓、Escape、鼠标存在；基于按键 buffer 生命周期 [ON-slash] | 部分／交互策略不同，当前上游早期 README “鼠标驱动”不完整 | Esc 后不重弹、再次输入可唤起；字符透传、IME 和焦点保持 |
| A14 | slash 非激活 NSPanel 可以取得键盘，未知键转发 Notes；不以 Input Monitoring 作为核心功能前提 [NB-panel] [NB-availability] | CGEvent tap 路径，在 Notes 前台处理按键 [ON-keyboard] | 已有键盘实现，但权限和焦点路径不同；上游不是唯一正确方式 | 仅 Accessibility 权限时可用性、事件 tap 失效恢复；不能模拟“权限已授予”代替真实权限运行 |
| A15 | 浮条逐项显隐、拖拽排序、恢复默认；默认 11 可见／14 可选；存储去重并补回新增命令 [NB-toolbar-settings] | `FloatingToolbarAction` 固定枚举、`FloatingBarView` 固定布局 [ON-float] | **缺失自定义配置与 UI** | 拖拽后次序、重启持久化、隐藏全部、旧设置升级、新命令补齐、可访问性 |
| A16 | slash 命令逐项显隐、拖拽排序、恢复默认；隐藏项同时退出精确匹配 [NB-slash-settings] [NB-catalog] | `allCommands` 固定数组 [ON-slash] | **缺失配置与 UI** | 隐藏命令既不出现在菜单，也不会用隐藏 alias 偷偷执行；顺序重启后保留 |
| A17 | 全局行内增强总开关＋浮条／Markdown／slash 独立开关 [NB-settings] [NB-availability] | Markdown service 有逐触发开关；其余设置须按 AppDelegate 实际绑定复核 [ON-settings] | 部分；“Settings 有 Toggle”不能等于后台服务已停 | 每个开关关闭后，不拦按键、不显示浮层、不执行转换；再次开启恢复 |
| A18 | 共用面板定位：上下翻转、visibleFrame 限制、0.5px 抖动容差、Space/fullscreen 辅助、透明材质、横向浮条滚动 [NB-surface] [NB-layout] | WindowTrackService、WindowGeometry、各 WindowController [ON-geometry] | 同类已实现；多屏和焦点行为未由本次研究验证 | 主屏上／下／左／右副屏、缩放、全屏、跨 Space、边缘大工具条；无抢焦／闪烁 |

上游完整 slash token 对照（来自 `SlashCommandCatalog.defaultEntries`）：

| 上游主 token／别名 | OpenNotes 现有主要入口 | 应采取的处理 |
|---|---|---|
| `/title`、`/h1` | `/h1` | 保留现有短名，补明确 alias |
| `/heading`、`/h2` | `/h2` | 同上 |
| `/subheading`、`/h3` | `/h3` | 同上 |
| `/body`、`/bold` | 同名 | 核实精确匹配和 Space 提交 |
| `/strikethrough`、`/strike` | `/strike`，名称模糊搜索可能命中 | 增加稳定别名语义，不能把 contains 当完整兼容 |
| `/link` | 无 | 新增原生命令 |
| `/monostyled`、`/code` | `/code` | 补别名 |
| `/checklist` | `/todo` | 补别名 |
| `/bulletedlist` | `/bullet` | 补别名 |
| `/dashedlist` | 无 | 为已有 `.dashList` 补入口 |
| `/numberedlist` | `/number` | 补别名 |
| `/quote`、`/blockquote` | `/quote` | 补别名 |
| `/table` | 无 | 新增原生命令 |

## B. 笔记读取、富文本和知识来源完整性

| ID | NotesBridge 实际实现与依据 | OpenNotes 当前对应 | 状态／差距 | 验收证据要求 |
|---|---|---|---|---|
| B01 | 用户选择 `group.com.apple.notes`，保存 security-scoped bookmark；解析失效回退 path；访问周期中成对 start/stop [NB-app] | 固定根 `NoteStore.sqlite`＋FDA 状态探测 [ON-db] | 部分／授权模型不同；没有可选容器和持久 bookmark 流程 | 授权／取消／重启／失效／受限账户目录，显示真实错误；无需为追求同实现强行要求双重授权 |
| B02 | 扫描 root、LocalAccount、Accounts 下 DB；择可读正文最多的一份，manifest 记录选择供定向加载 [NB-db] | 固定 root DB [ON-db] | 部分：缺候选发现与 schema 适配；注意上游是选一份，**不是所有库合并** | root 空、account 有数据；两库同 Z_PK；manifest 和正文必须来自一致来源 |
| B03 | 复制 DB／WAL／SHM 到 Caches 临时目录，只读 SQLite 查询，defer 清理 [NB-db] [NB-sqlite] | 原库使用 `SQLITE_OPEN_READONLY` 与 `FULLMUTEX`，busy timeout，专用串行队列 [ON-db] | 原数据库只读已实现；快照策略不同，不能仅凭“复制了文件”保证并发一致性 | 真实编辑并发读取、WAL 创建／轮换；验证读取一致、清理失败及权限错误处理 |
| B04 | 查询 `z_primarykey` entity ID、PRAGMA 列，优先标题／folder 引用列并回退有数据列 [NB-db] | SQL 固定 `ZTITLE1/ZTITLE2/ZFOLDER/ZNOTEDATA` [ON-db] | 部分：跨 schema 兼容不足 | 合成不同列布局＋实际支持系统版本；缺列应报不支持，不能静默“0 篇” |
| B05 | 账户名、父子文件夹、default folder 省略、smart/trash 过滤、共享标记与创建／修改时间 [NB-db] [NB-document] | NoteInfo 标题／摘要／单 folderName／修改时间／置顶 | 部分：无完整账户／层级／共享元数据模型 | 同名跨账户 folder、嵌套 folder、默认 folder、Trash、异常父链 |
| B06 | gzip＋Protobuf 正文、attribute runs、段落样式、列表缩进、checklist、字重、下划线／上标、链接、附件描述；直接／包裹／递归查找（深度 6） [NB-decoder] | `NotesBridgeDecoder.swift` 移植对应解码结构 [ON-decoder] | 正文解码已复用；本地另做长度／varint 限制和有上限 gzip 路径 | 空、截断、恶意长度、非 BMP、直接与包裹消息、属性长度不匹配，保留失败语义 |
| B07 | 原生属性 → Markdown：标题、列表、勾选、quote、code fence、粗／斜／粗斜、删除线、外链；段落样式补全、相邻同属性合并 [NB-render] | 知识导入只取 `note.noteText`；“复制 Markdown”走 HTML converter [ON-db] [ON-convert] | 部分：**能解码 attribute 不代表它进入知识库或导出**；原生渲染链未移植 | 用同一复杂笔记比对 Notes 视觉、HTML 路径、protobuf 路径与知识片段 |
| B08 | 转换 attribute 中的内链和内嵌 note-link 为 token；后续导出按目标真实路径解析 [NB-render] [NB-db] | 原生反链有独立 parser/graph；复制链接可用；知识正文未渲染占位 token | 部分：反链图与正文语义材料不是同一实现 | 内链显示文字不丢失；UUID／x-coredata 两种目标；目标不存在时可解释降级 |
| B09 | hashtag／mention 的 `zalttext`；URL card 读取 title/url [NB-db] | 知识导入未用 attachmentResolver，`noteText` 可能只含对象占位 | 部分／缺失内嵌对象文本补全 | 文本标签、mention、URL 卡片导入后可检索；不把 U+FFFC 当完整材料 |
| B10 | `zmergeabledata1` → CRDT table，解行列排序和 cell note；cell 中换行用 `<br>`、竖线转实体，嵌套链接／附件 token 唯一化 [NB-mergeable] | HTML converter 支持可见 HTML table；无 mergeable table decoder [ON-convert] | 部分：HTML 中有表格不等于 DB 原生表格已处理；知识库尤其缺此路径 | 2×2、空 cell、多行、pipe、嵌套链接／图片、中文、异常 object index；原生表格实际读回 |
| B11 | 扫描 gallery page IDs → 页预览 JPEG，失败时 media fallback；部分页失败独立诊断 [NB-mergeable] [NB-db] | 无扫描 gallery 解析／OCR | 缺失；上游导出图片，**没有 OCR 识字** | 多页排序、缺页、失败计数、真实文件存在性；OCR 要独立实现验证 |
| B12 | modified scan 导出 FallbackPDF；3 类 drawing 导出 fallback JPG/PNG；一般 media 取 filename/generation [NB-db] | HTML converter 将附件标明占位；知识文件选择可导入有文本 PDF | 部分：没有 Notes 原生附件解析／复制链 | PDF／绘图／音频／视频／普通文件逐类；账户路径与 generation、未下载附件 |
| B13 | 锁定笔记不解码，计数；云端缺本地 body 不进入 manifest；异常表格／scan 返回明确占位并累计诊断 [NB-db] | 知识导入跳过 locked/deleted/trash；刷新移除已锁／删快照 [ON-db] [ON-workspace] | 部分：安全过滤存在；当前一种正文解码抛错可终止所选批次，缺逐源诊断 | 锁定、删除、坏正文混合批次；可解释每一篇是成功、跳过或失败 |

## C. Obsidian 同步与导出：上游扩展能力，不能冒充当前已整合

以下在 OpenNotes 均没有产品入口和对应完整管线；“复制 Markdown”和“刷新知识快照”不等于向 Vault 同步。是否全部进入最终 App 应由完整 ProNotes 需求矩阵及用户选定扩展范围决定，清单保留到决定落地，不默认删掉。

| ID | 上游实际能力／依据 | OpenNotes 状态 | 如果纳入，必须证明的行为 |
|---|---|---|---|
| C01 | 选择 Vault、设置 export folder、自定义 attachment folder、Finder reveal [NB-settings] [NB-vault] | 缺失 | 取消选择不改状态，路径可写、冲突处理正确 |
| C02 | 全量同步；按 folder ID 优先、folder path/name 回退分组，未匹配笔记也进入 fallback group [NB-app] | 缺失 | 不漏孤立 folder 笔记；真实导出数量和跳过数量可追溯 |
| C03 | manifest＋SyncRecord：时间（容差 1 秒）、名称、路径变化决定增量；未变不解码正文 [NB-plan] | 缺失 | 新建／改文／重命名／移动／删除；目标文件丢失恢复，不只对比时间戳 |
| C04 | changed IDs 定向加载；缺少预期正文时回退 full sync 并保留原因 [NB-app] | 缺失 | fallback 可复现且不会把未读出的笔记静默算作导出成功 |
| C05 | 周期自动同步 30 分、1h、6h、1d；旧 5/15 分配置归并到 30 分 [NB-interval] [NB-settings-model] | 缺失 | 时间驱动用可控 clock 测试；睡眠／恢复、重启、关开后的计划明确 |
| C06 | onChange：2s 轮询 DB/WAL mtime＋默认 5s debounce；持续保存访问 session [NB-watcher] [NB-app] | 缺失 | 快速变更多次合并；同步期间变更完成后补跑；原库创建／WAL 新建／替换均可靠 |
| C07 | 同步进度、当前 folder、added/updated/unchanged/removed/skipped、计时、菜单栏旋转 [NB-progress] [NB-app] | 缺失 | 空库 100%、失败清理、变化数与真实文件写入一致 |
| C08 | 按 folder 层级和干净文件名导出；重名加序号；旧 hash path 迁移、稳定 ID/path alias、从 frontmatter 恢复 [NB-vault] [NB-record] | 缺失 | 重名／改名／跨 folder／手动已有文件；路径不得逃逸目标根目录 |
| C09 | YAML source、原生 deep link、sync ID、legacy ID、folder、created_at、updated_at、shared [NB-vault] | 缺失 | created_at 来自 Notes；此上游的 updated_at 是**导出更新时间**，不能当作原笔记修改时间 |
| C10 | Wiki 内链用目标最终路径＋alias，处理碰撞路径、x-coredata fallback；目标缺失降为文字并计数 [NB-vault] | 缺失 | 目标重命名后未变来源笔记的链接也要修复；不能只测试初次导出 |
| C11 | 图片／音频／视频／PDF 为 `![[...]]`，普通文件 `[[...]]`；统一附件根下按笔记层级放置 [NB-vault] [NB-db] | 缺失 | 文件真实复制、每个 token 替换正确、同名附件不覆盖 |
| C12 | 读 `.obsidian/app.json` 的 attachmentFolderPath；不支持当前文件相对目录时降回自定义并警告 [NB-vault] | 缺失 | 自定义根、配置损坏、`./`、非标准路径；不得误读配置为具有权限 |
| C13 | 附件按大小＋时间避免重复复制，清理失效附件；重命名时移动附件目录并迁移旧存储 [NB-vault] | 缺失 | 内容变而大小/时间不变、复制中断、权限失败、用户自放文件；清理不误删 |
| C14 | source 消失／trash 后 Markdown 和附件移动 `_Removed`；冲突时加序号 [NB-plan] [NB-vault] | 缺失 | 重复删除／恢复、同名 removed、既有文件保持；原 Notes 永远不删除 |
| C15 | `settings.json` 和 `sync-index.json` 原子持久化；旧字段 decode 默认／path aliases 迁移 [NB-persistence] [NB-record] | 缺失同步记录；OpenNotes 自己的 AI 配置持久化不等价 | 配置损坏可告知、部分导出后重试、一致恢复；批量结果不会只有内存状态 |

## D. App、权限、发布以及 LLM 功能对照

| ID | 上游功能／依据 | OpenNotes 映射和状态 | 后续验证／决策 |
|---|---|---|---|
| D01 | Swift 6.2、macOS 14、SwiftUI/AppKit 菜单栏 accessory app [NB-package] [NB-main] | 已实现原生 SwiftUI/AppKit；还提供工作台 | 对支持最低版本和 Apple Silicon／Intel 明确建立构建与实机矩阵，不能从 target 版本推断已测 |
| D02 | EN／简中／FR／system，词典本地化、带参数进度文案 [NB-localization] | 中文 UI＋部分英文，未见完整语言配置与资源层 | 部分；UI 本地化与 AI 输出语言是两个配置 |
| D03 | Accessibility、Input Monitoring、App Management 设置入口；显示 bundle vs CLI、relaunch 为固定 app bundle [NB-permission] [NB-app] | AX/FDA/Notes Automation 诊断与引导已存在 [ON-settings] | 部分／权限需求不同；真正 bundle 的 TCC 授权与各依赖功能需实机验收 |
| D04 | `BuildFlavor.appStore` 关闭行内增强且关闭 Sparkle；directDownload 启用 [NB-flavor] [NB-updating] | 当前只做直接分发，无 App Store flavour | 非 ProNotes 编辑功能必需；不因它存在就增加无需求的发布分支 |
| D05 | Sparkle 手动检查、自动检查默认开、自动下载默认关，关闭检查时关下载 [NB-updating] | 缺失，当前本地 zip／ad-hoc 包 | 发布级能力：自有 feed、密钥、签名、更新可回滚；不要复制上游公钥/feed 作为自己的更新系统 |
| D06 | bundle/release/notarize/appcast/release-notes；嵌 Sparkle framework；CI Xcode test [NB-release] [NB-ci] | 已有自己的 bundle/verify 脚本；无在线发布链 | 部分；本报告不证明上游或 OpenNotes 某个 release 真正完成公证或跑过 CI |
| D07 | OSLog 分类、同步诊断、slash 最近 8 条诊断；部分包含光标附近文本 [NB-slash] [NB-log] | OpenNotes 日志策略声称不记正文／密钥，已有状态展示 [ON-readme] | 不照搬上游正文 snippet 诊断，避免用户知识材料进入日志 |
| D08 | HTML→Markdown、Markdown→HTML、AttributedString preview 作为辅助函数 [NB-transform] | HTML→Markdown 更丰富的独立 converter；AI 插入纯文本 | 部分；上游 markdownToHTML 仅有限行解析，没有原生表格／完整 CommonMark 回写能力，也未接通产品 |
| D09 | AppleScript/JXA 读 folder/summary/document 和全 body 写回辅助 API [NB-script] | CurrentNoteResolver＋Automation access＋SelectionTransaction 局部回写 | 部分／设计不同；不采用全 body 覆盖来“补齐”AI 选区功能，它会改变原生结构和附件边界 |
| D10 | 原生 test-launch mode，注入 fixtures、伪更新器／伪数据源、输出状态与窗口就绪文件 [NB-launch] | 模拟模型服务和可选截图测试，原生 UI 实机仍独立 | 部分；上游 UI tests 不验证真实 Apple Notes、AX 输入、授权、真实更新网络 |
| D11 | NotesBridge 无 LLM／Keychain／RAG／提示词配置模块 | OpenNotes `AIConfiguration`、`ModelClient`、`KnowledgeIndex`、`WorkspaceModel` | OpenNotes 已新增四协议连接、Keychain、提示词、流式结果、取消、FTS5、来源编号、模板 [ON-ai] [ON-model] [ON-knowledge] [ON-workspace] |
| D12 | NotesBridge 无反链 UI、全局搜索、模板、Vim、独立浮动笔记管理 | OpenNotes 已有反链、搜索、模板子集；Vim／独立浮动笔记等仍需整体对标矩阵处理 | **不能凭 NotesBridge 没有它们就从 ProNotes 最终目标排除** |

LLM 相关的具体增量：保留 OpenNotes 的模型／Keychain／提示词配置，并把 NotesBridge 的读取能力接到“用户明确选择的来源 → 可解释文档快照 → 分块检索”之间。不要把“已导出 Markdown 文件供 agent 使用”描述为内置个人知识问答。原生表格的单元格、内链显示文字、mention/tag、附件可提取文字，目前都可能不在 `noteText` 的知识输入里；这影响回答依据的完整性，即使模型流式请求成功也不能弥补。[ON-db] [ON-knowledge] [NB-db]

## E. 上游自身的边界与不可直接搬用之处

1. **自动同步的忙碌后补跑未成立。** `handleDatabaseChange` debounce 后调用 `runAutomaticSyncIfNeeded`，后者在 `isSyncing` 时返回；没有 pending-dirty 标记或完成后的追赶逻辑。需求文档“同步期间变化应再跑一次”是目标，不是代码证据。现有两项自动同步测试只覆盖 debounce 合并及 access session 生命周期。[NB-app] [NB-auto-tests]
2. **不能笼统说“多数据库全支持”。** `loadManifest/loadSnapshot` 挑选一份候选库；并未合并多个账户数据库。`attachmentCandidateURLs` 虽接受 ownerID，却遍历账户目录再选 first existing，未按 ownerID 优先。若复用应补跨账户 fixture 验证。[NB-db]
3. **“解析字段”不等于“保留格式”。** `underlined`、`superscript` 被解码，但 `formattedText` 没有输出它们；知识导入仅用 noteText 更不会带格式。渲染和解码必须分开计完成。[NB-decoder] [NB-render] [ON-db]
4. **DB+WAL+SHM 逐个文件复制没有在代码里建立一致性快照事务。** 它保证原库只读，不等于并发写入时每次副本一致；采用此链需要针对 WAL 并发行为验证，必要时换 SQLite 一致性 backup 或只读事务实现。[NB-db]
5. **增量同步的链接依赖未全面传播。** planner 只按自身 timestamp/name/path 决定是否导出，目标改名而来源未变时来源可能被判 unchanged，其旧 wiki target 不重写。若引入 Vault 同步，要补受影响入链重渲染。[NB-plan] [NB-vault]
6. **解压和整型边界要保留 OpenNotes 的改进。** 上游 Gzip.inflate 未设输出大小上限；`readLengthDelimited` 直接 UInt64→Int 再加 index。移植其表格解码时应复用本地受限 reader，不复制回较弱版本。[NB-decoder] [ON-decoder]
7. **编辑命令需要验证目标身份和字符索引。** 上游 Markdown 的 caret 为 AX UTF-16 范围，却用 `Array(String)` 索引，含 emoji／组合字符的前文可能令行首判断偏移；其删除为重复 Delete。上游格式菜单名写死英文并回退 shortcut，strikethrough 没有 shortcut fallback。保留 OpenNotes 的 `InlineInputEdit` 局部保护并补真实中文系统验收。[NB-markdown] [NB-executor] [ON-inline]
8. **导出器不是任意用户目录的安全同步引擎。** 它会移除失效附件、迁移／删除目录；路径清理替换 `/ : \\` 等但未显式拒绝 `..`。如果引入，先明确导出目录所有权、规范化路径必须仍在根内、保护外来文件，并对异常名称／symlink 作测试。[NB-vault]
9. **文档时间和源代码不完全一致。** onChange 文档写“当前 interval-only”，实际已有 watcher；README 写 slash 鼠标驱动，实际已有面板键盘导航；CHANGELOG 说 table blank padding 已消除，但固定提交的 `AppleNotesTableConverter.renderFragment` 仍从 `"\n"` 开始并追加空行。最终以具体路径实际输出验收，不能只引用发布说明。[NB-change-request] [NB-slash] [NB-mergeable]
10. **辅助写接口不是双向同步。** JXA 的 `updateNote` 直接设置 body，未见生产调用链；没有合并、冲突解决或附件保真的逆向协议。用户要求原生回写应坚持明确操作、局部事务、读回及撤销的验收边界。[NB-script] [ON-transaction]

这些是从可见控制流得到的审阅结论；没有宣称已复现所有上游缺陷。

## F. 实施顺序和完成证据

| 顺序 | 应实现的工作 | 主要参考 | 不能省略的完成证据 |
|---|---|---|---|
| 1 | 原生 Table/Link，dash slash 入口；完整 alias 目录；三反引号触发 | A06–A10 | 合成解析用例＋真实 Notes 中格式变化和撤销；不能只断言枚举新增 |
| 2 | slash 字符串范围 parser、空白边界、exact+Space、Escape 状态；保留局部编辑校验 | A11–A14、E07 | URL／路径／emoji／IME／快速切窗；失败不误删文字；鼠标和键盘两条路径 |
| 3 | 工具条与 slash 自定义显隐、拖拽排序、默认恢复和迁移 | A15–A17 | UI 操作后立即生效；重启保持；旧配置新增命令可恢复；隐藏项不执行 |
| 4 | 提升 Notes 材料完整性：schema adapter、富文本 renderer、内嵌文字、table decoder | B02–B10 | 合成 SQLite/protobuf/table fixture＋用户授权测试笔记逐段对照；中文检索真的命中表格内容 |
| 5 | 若完整需求矩阵需要 Notes 附件导出／知识提取，补附件与扫描链 | B11–B13 | 逐附件类型实际文件和可提取文字；图片导出和 OCR 单独计完成 |
| 6 | 若纳入扩展，做 Vault 同步而不是直接整份 AppModel 合并 | C01–C15 | 全量、增量、依赖更新、删除恢复、并发与中断恢复、真实导出文件读回 |
| 7 | 正式分发时补自有更新／签名／公证与支持系统矩阵 | D01–D06 | 当前构建包实际安装、启动、权限、干净机器、更新到新包；CI 配置文件不是通过证据 |

这份研究不宣布长期目标完成。最少还需要把上述直接编辑差距、ProNotes 其他已确认功能，以及 OpenNotes 新增 LLM/知识配置的完整端到端验收统一到总矩阵中。没有用“可运行首版”“单元测试很多”或“上游已开源”降低用户原先的完整功能目标。

## G. 测试覆盖盘点：存在测试不等于已通过或已实机验证

下面逐测试文件记录其断言覆盖。全部 23 个文件都在固定 SHA 下；本次只审阅，没有执行。

| 测试文件（`Tests/NotesBridgeTests/`） | 主要断言／fixture 边界 | 对 OpenNotes 的借鉴与不能证明的部分 |
|---|---|---|
| `AppLocalizationTests.swift` | 简中文案、法文进度、slash 标题与 token 分离 | 可移植配置行为；不证明真实窗口无截断 |
| `AppModelAutomaticSyncTests.swift` | manual watcher 双通知合并；bookmark session 持续至关闭 | 没覆盖同步忙碌期间修改补跑 |
| `AppModelDirectorySelectionTests.swift` | 注入 picker：选取／取消／bookmark；accessory→regular→恢复 | 不证明真实 TCC 系统授权成功 |
| `AppModelSyncProgressTests.swift` | 注入 data source/sync engine；成功失败、full fallback、指定 DB、无变化不加载 | 不证明真实 Notes DB schema 兼容 |
| `AppSettingsTests.swift` | 默认值、旧配置、重复项归一化、缺项补齐、旧间隔迁移 | 自定义设置可直接借鉴 |
| `AppUpdateSettingsTests.swift` | bundle version、fake updater 调用与开关、App Store 隐藏、folder count 缓存 | 不证明 Sparkle feed／签名／实际安装更新 |
| `AppleNotesDatabaseSyncSourceTests.swift` | 容器候选路径／空文件 fixture、访问等级、SQL 片段、Caches 路径 | 不是多种真实私有数据库完整导出测试 |
| `AppleNotesMarkdownRendererTests.swift` | 合成 attribute：标题/list/checklist/quote/code/link；首字符补样式；CRLF；相邻 mailto/strike；附件和内链 token；table-cell 转义 | 很有用的 renderer 回归集；不证明 AX 编辑 |
| `AppleNotesMergeableDataConversionTests.swift` | 人工组装 table model、嵌套链接、page ID 提取 | 不等于真实扫描页文件／压缩 blob 全流程 |
| `AppleNotesNoteProtoDecoderTests.swift` | 合成 gzip 直接文档、未知外层包裹 | 只有这两种，不代表所有坏消息／长度安全 |
| `ContextualSurfacePositioningTests.swift` | 坐标数学、上下翻转、边缘 clamp、panel 阴影属性 | 不证明多屏 AX 坐标原点／实时焦点 |
| `FormattingBarLayoutTests.swift` | 分组保序、宽度上限、外层 inset | 不证明拖拽或真实滚动可用 |
| `IncrementalSyncPlannerTests.swift` | new/update/remove、unchanged、path alias 优先 | 不覆盖全部依赖重命名／损坏目标恢复 |
| `InteractionAvailabilityTests.swift` | 核心 slash/Markdown 不要求 Input Monitoring 的 Boolean 条件 | 不证明系统确实准许合成按键 |
| `MarkdownTransformerTests.swift` | HTML↔Markdown 子集、plain fallback、段落/列表/quote/code | 辅助转换器测试，不是双向同步产品 |
| `NotesBridgeUITests.swift` | 启动临时签名 bundle，test mode 自动调用 sync，检查状态文件和 Markdown；fake update settings | 注入假 Notes 源且关闭 inline enhancements；不能称真实 Notes UI 编辑验收 |
| `NotesDatabaseWatcherTests.swift` | 临时目录 mtime、baseline 后新 WAL/DB 创建 | 不覆盖 DB 替换、时间回退、真实 iCloud 写入时序 |
| `ObsidianVaultClientTests.swift` | 临时 vault：干净名/重名/层级/改名、附件复制/移动/清理、timestamp、内链/未知目标、Removed | 可复用输出契约；仍须补路径根限制、外来文件保护、并发中断 |
| `SQLiteDatabaseTests.swift` | 内存构造 SQLiteRow 的 NULL Bool 为 false | 不等于真实 sqlite3 打开／WAL／事务测试 |
| `SlashCommandKeyboardActionTests.swift` | keyCode→action | 不证明面板获焦或按键没进入正文 |
| `SlashCommandParserTests.swift` | 裸 `/`、alias/case、空白中途、换行、URL/词内/path 负例、Space 精确提交、隐藏项 | 应移植语义用例并补 UTF-16、selection/context 变化 |
| `SyncIndexTests.swift` | 旧 payload aliases 默认空、Codable roundtrip | 不验证磁盘 crash consistency |
| `SyncProgressTests.swift` | 比例／summary、0 篇、skipped、clamp | 不等于真实导出数量正确 |

[完整固定版本测试目录][NB-tests]；[UI 测试注入实现][NB-launch]。源码 CI 当前执行 `xcodebuild ... test`，开发文档还建议 `swift test`；本报告没有把配置文件当作任何一次通过记录。[NB-ci]

## H. 引用索引

上游链接全部绑定同一 SHA；OpenNotes 链接指向当前仓库文件，随后实现修改后应重审此对比。

[NB-decoder]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesNoteProtoDecoder.swift#L96
[NB-render]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesNoteProtoDecoder.swift#L320
[NB-db]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesDatabaseSyncSource.swift
[NB-mergeable]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesMergeableDataConverter.swift#L331
[NB-app]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/AppModel.swift
[NB-main]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/NotesBridgeApp.swift
[NB-launch]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/AppLaunchMode.swift#L79
[NB-float]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FloatingFormattingBarController.swift
[NB-format]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FormattingCommand.swift
[NB-executor]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FormattingCommandExecutor.swift
[NB-markdown]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/MarkdownTriggerEngine.swift
[NB-catalog]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandCatalog.swift
[NB-parser]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandParser.swift
[NB-slash]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandEngine.swift
[NB-panel]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandMenuController.swift
[NB-availability]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/InteractionAvailability.swift
[NB-toolbar-settings]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/InlineToolbarCustomizationSheet.swift
[NB-slash-settings]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/SlashCommandCustomizationSheet.swift
[NB-settings]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/SettingsView.swift
[NB-surface]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/ContextualSurfaceController.swift
[NB-layout]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FormattingBarLayout.swift
[NB-sqlite]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/SQLiteDatabase.swift
[NB-document]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppleNotesSyncDocument.swift
[NB-plan]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/IncrementalSyncPlanner.swift
[NB-watcher]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/NotesDatabaseWatcher.swift
[NB-vault]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/ObsidianVaultClient.swift
[NB-record]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/SyncRecord.swift
[NB-persistence]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/PersistenceStore.swift
[NB-interval]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AutomaticSyncInterval.swift
[NB-settings-model]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppSettings.swift
[NB-progress]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/SyncProgress.swift
[NB-transform]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/MarkdownTransformer.swift
[NB-script]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesClient.swift
[NB-package]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Package.swift
[NB-localization]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/AppLocalization.swift
[NB-permission]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/PermissionsManager.swift
[NB-flavor]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/BuildFlavor.swift
[NB-updating]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/SparkleAppUpdater.swift
[NB-release]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/scripts/notesbridge.sh
[NB-ci]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/.github/workflows/ci.yml
[NB-log]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/AppLog.swift
[NB-tests]: https://github.com/peizh/NotesBridge/tree/91bccb0d34205d9813508de8146ea07540ac161f/Tests/NotesBridgeTests
[NB-auto-tests]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Tests/NotesBridgeTests/AppModelAutomaticSyncTests.swift
[NB-change-request]: https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/docs/feature-request-change-triggered-auto-sync.md
[ON-notices]: ../THIRD_PARTY_NOTICES.md
[ON-readme]: ../README.md
[ON-format]: ../src/Quillside/Services/FormattingService.swift
[ON-actions]: ../src/Quillside/Features/NoteActions/NoteActionsService.swift
[ON-markdown]: ../src/Quillside/Services/MarkdownTriggerService.swift
[ON-slash]: ../src/Quillside/Features/SlashCommand/SlashCommandService.swift
[ON-keyboard]: ../src/Quillside/Services/KeyboardMonitorService.swift
[ON-float]: ../src/Quillside/Features/FloatingBar/FloatingBarView.swift
[ON-settings]: ../src/Quillside/App/SettingsView.swift
[ON-geometry]: ../src/Quillside/Services/WindowGeometry.swift
[ON-db]: ../src/Quillside/Services/NotesDBReader.swift
[ON-decoder]: ../src/Quillside/Services/NotesBridgeDecoder.swift
[ON-convert]: ../src/Quillside/Services/AppleNotesMarkdownConverter.swift
[ON-workspace]: ../legacy/standalone-workspace/WorkspaceModel.swift
[ON-ai]: ../src/Quillside/AI/AIConfiguration.swift
[ON-model]: ../src/Quillside/AI/ModelClient.swift
[ON-knowledge]: ../legacy/retired-features/src/Quillside/Knowledge/KnowledgeIndex.swift
[ON-transaction]: ../src/Quillside/Workspace/SelectionTransaction.swift
[ON-inline]: ../src/Quillside/Services/InlineInputEdit.swift


## I. 全部 Sources 文件盘点

所有路径相对 `Sources/NotesBridge/`。此清单逐一绑定上面的行为矩阵；辅助模型和样式没有被凭空当作新产品功能。

| 源文件 | 功能归属／审阅结果 |
|---|---|
| [App/AppDelegate.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/AppDelegate.swift) | D01、D10：accessory 启动；测试窗口、自动 sync hook。 |
| [App/AppLaunchMode.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/AppLaunchMode.swift) | D10：环境驱动 test mode、虚拟 Notes 数据、虚拟 updater、状态 artifact。 |
| [App/AppModel.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/AppModel.swift) | A01/A15–A17、B01、C02–C07/C15：settings 绑定、权限、读库、同步编排、debounce、进度和状态。 |
| [App/AppWindowID.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/AppWindowID.swift) | D01：Settings Window 稳定标识。 |
| [App/NotesBridgeApp.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/App/NotesBridgeApp.swift) | D01：MenuBarExtra 和设置 Window 场景。 |
| [Domain/AppLanguage.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppLanguage.swift) | D02：system/EN/简中/FR 枚举。 |
| [Domain/AppSettings.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppSettings.swift) | A15–A17、C01/C05/C06/C15：开关、显隐排序、Vault/附件/书签、同步方式、旧配置迁移。 |
| [Domain/AppUpdateState.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppUpdateState.swift) | D05：更新启用、版本和检查/下载状态。 |
| [Domain/AppVersion.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppVersion.swift) | D05：读取 bundle 版本和 build。 |
| [Domain/AppleNote.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppleNote.swift) | B05、D09：Script 层 folder/summary/document 与锁定占位数据模型。 |
| [Domain/AppleNotesSyncDocument.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppleNotesSyncDocument.swift) | B08/B12、C09–C11：文档/附件/内链/快照、ID 归一化与 deep link。 |
| [Domain/AppleNotesSyncManifest.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AppleNotesSyncManifest.swift) | B02、C03：可供增量判定的条目、selected database、locked/trash 元数据。 |
| [Domain/AutomaticSyncInterval.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AutomaticSyncInterval.swift) | C05：30m/1h/6h/1d，旧 5m/15m 迁移。 |
| [Domain/AutomaticSyncTrigger.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/AutomaticSyncTrigger.swift) | C06：periodic 与 onChange。 |
| [Domain/BuildFlavor.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/BuildFlavor.swift) | D04：directDownload 与 appStore 功能开关。 |
| [Domain/InlineToolbarItemSetting.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/InlineToolbarItemSetting.swift) | A15：14 项默认目录、11 项默认可见、去重/补项/保序。 |
| [Domain/InteractionAvailability.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/InteractionAvailability.swift) | A01/A14/A17：AX、Notes 前台、可编辑焦点和设置组合判定。 |
| [Domain/SlashCommandItemSetting.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/SlashCommandItemSetting.swift) | A16：命令可见状态、去重和补项。 |
| [Domain/SyncProgress.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/SyncProgress.swift) | C07：当前 folder、notes/folders/skipped、比例 clamp、本地化。 |
| [Domain/SyncRecord.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Domain/SyncRecord.swift) | C03/C08/C15：稳定记录、path aliases、last sync 元数据与旧配置 decode。 |
| [Interaction/ContextualSurfaceController.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/ContextualSurfaceController.swift) | A18：NSPanel、坐标转换、上下回避、clamp、jitter。 |
| [Interaction/FloatingFormattingBarController.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FloatingFormattingBarController.swift) | A01：选区+权限+命令可见性决定浮条显示。 |
| [Interaction/FloatingToolPaletteStyle.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FloatingToolPaletteStyle.swift) | A18：slash 调色板原生材质、尺寸和共用图标样式。 |
| [Interaction/FormattingBarLayout.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FormattingBarLayout.swift) | A18：命令相邻组、34px 按钮、宽度 160–464、横向布局。 |
| [Interaction/FormattingBarView.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FormattingBarView.swift) | A01/A18：按目录渲染、横向滚动、hover/help/accessibility label。 |
| [Interaction/FormattingCommand.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FormattingCommand.swift) | A02–A07：14 类命令及快捷键、标签、图标。 |
| [Interaction/FormattingCommandExecutor.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/FormattingCommandExecutor.swift) | A02–A09/A12：Notes 前台检查、菜单/shortcut、Delete、AX 局部替换、按键转发。 |
| [Interaction/MarkdownTriggerEngine.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/MarkdownTriggerEngine.swift) | A08/A09：120ms 轮询、9 个行首模式、去重签名。 |
| [Interaction/NotesContextMonitor.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/NotesContextMonitor.swift) | A01/A18：250ms AX 状态、缓存可编辑元素、选区与光标 bounds fallback。 |
| [Interaction/PermissionsManager.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/PermissionsManager.swift) | D03：AX/Input Monitoring 探测与请求、App Management 系统设置入口。 |
| [Interaction/SelectionContext.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SelectionContext.swift) | A01：选区文本、range、rect 和 hasSelection。 |
| [Interaction/SlashCommandCatalog.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandCatalog.swift) | A10/A16：14 类命令、别名、前缀/精确匹配、隐藏项过滤。 |
| [Interaction/SlashCommandEngine.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandEngine.swift) | A11–A14：轮询解析、Space 提交、↑↓/Enter/Tab/Esc、dismiss token、诊断。 |
| [Interaction/SlashCommandKeyboardInterceptor.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandKeyboardInterceptor.swift) | A13：文件名虽叫 interceptor，实际仅 keyCode→action 枚举；事件处理在 Panel。 |
| [Interaction/SlashCommandMenuController.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandMenuController.swift) | A14/A18：panel 取得键盘、透传未知键、菜单尺寸与 frame callback。 |
| [Interaction/SlashCommandMenuView.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandMenuView.swift) | A10/A13：鼠标选择、hover、高亮、稳定 token 显示。 |
| [Interaction/SlashCommandParser.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Interaction/SlashCommandParser.swift) | A11/A12：UTF-16 token 范围、空白边界、精确 Space 替换范围。 |
| [Services/AppUpdating.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppUpdating.swift) | D04/D05：AppUpdating facade、Sparkle/NoOp factory。 |
| [Services/AppleNotesClient.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesClient.swift) | D09：AppleScript/JXA folder/read/body write；生产只用 folder fallback。 |
| [Services/AppleNotesDatabaseSyncSource.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesDatabaseSyncSource.swift) | B01–B05/B08–B13：DB 候选、snapshot/schema、folder、note、附件/表格/扫描解析。 |
| [Services/AppleNotesMergeableDataConverter.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesMergeableDataConverter.swift) | B10/B11：mergeable protobuf object 图、table cell、scan page identifier。 |
| [Services/AppleNotesNoteProtoDecoder.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/AppleNotesNoteProtoDecoder.swift) | B06–B08：gzip/Protobuf、属性渲染、内链/附件 token、诊断。 |
| [Services/IncrementalSyncPlanner.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/IncrementalSyncPlanner.swift) | C03/C08/C10/C14：changed/unchanged/removed 计划、路径冲突、alias lookup。 |
| [Services/MarkdownTransformer.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/MarkdownTransformer.swift) | D08：HTML/Markdown/plain/preview 辅助转换，当前仅测试构造。 |
| [Services/NotesDatabaseWatcher.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/NotesDatabaseWatcher.swift) | C06：DB/WAL mtime 轮询、首轮 baseline、新建文件检测。 |
| [Services/ObsidianVaultClient.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/ObsidianVaultClient.swift) | C01/C08–C14：文件/附件/frontmatter/内链/Removed 与变更分类。 |
| [Services/PersistenceStore.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/PersistenceStore.swift) | C15：Application Support 设置和 sync-index JSON 原子保存。 |
| [Services/ProcessRunner.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/ProcessRunner.swift) | D03/D09：Process 执行、stdin、并行管道读取、退出码错误；不提供超时。 |
| [Services/SQLiteDatabase.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/SQLiteDatabase.swift) | B03/B04：READONLY 查询封装、绑定、类型转换、PRAGMA 列名。 |
| [Services/SparkleAppUpdater.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/SparkleAppUpdater.swift) | D05：Sparkle KVO→Combine 状态、自动检查/下载设置与手动检查。 |
| [Services/SyncEngine.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Services/SyncEngine.swift) | C02/C03：导出结果→SyncRecord/changeKind/unresolved count。 |
| [Support/AppKitDirectoryPanel.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/AppKitDirectoryPanel.swift) | B01/C01：NSOpenPanel、accessory 临时提升 regular 并恢复、可注入 panel runner。 |
| [Support/AppLocalization.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/AppLocalization.swift) | D02：语言选择、本地化字典及参数格式化。 |
| [Support/AppLog.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/AppLog.swift) | D07：sync/apple-notes/export/access 四类 OSLog。 |
| [Support/BundledAppLauncher.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/BundledAppLauncher.swift) | D03：将 CLI executable 包成 app、ad-hoc 签名后重启；没有证明发布包完整性。 |
| [Support/FoundationExports.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/FoundationExports.swift) | 开发辅助：导出 Foundation，无独立用户功能。 |
| [Support/NotesBridgeGlassStyle.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Support/NotesBridgeGlassStyle.swift) | A18/D01：SwiftUI 材质、圆角、边框、shadow 共用样式。 |
| [Views/InlineToolbarCustomizationSheet.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/InlineToolbarCustomizationSheet.swift) | A15：逐项显隐、拖拽重排、恢复默认和完成。 |
| [Views/MenuBarContentView.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/MenuBarContentView.swift) | D01、C03/C07：当前状态、打开 Notes、增量同步、设置、重启 bundle、退出与错误。 |
| [Views/MenuBarIconView.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/MenuBarIconView.swift) | C07：同步旋转动画和可访问性名称。 |
| [Views/SettingsView.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/SettingsView.swift) | A15–A17、B01、C01/C05–C07、D02–D05：完整设置入口和状态展示。 |
| [Views/SlashCommandCustomizationSheet.swift](https://github.com/peizh/NotesBridge/blob/91bccb0d34205d9813508de8146ea07540ac161f/Sources/NotesBridge/Views/SlashCommandCustomizationSheet.swift) | A16：显隐、拖拽重排、恢复默认；保持 alias 文本。 |

## J. 版本、依赖与本次证据边界

- 上游固定 SHA、62 个 Swift 源文件、23 个测试文件已逐目录核对；源文件清单集合与磁盘实际集合完全相同。
- OpenNotes 为正在被主任务修改的工作区，没有可固定的提交 SHA；本报告记录本次审阅读到的行为，不声称所有文件来自同一原子快照。后续实现修改后，应按相关矩阵行重审，不能把旧“缺失”状态当作新版本结论。
- 上游 Package exact dependencies：SwiftSoup 2.9.6（锁定 `dee225a3da7b68d34936abc4dc8f34f2264db647`），Sparkle 2.9.0（锁定 `21d8df80440b1ca3b65fa82e40782f1e5a9e6ba2`）；OpenNotes 当前 Package 没引入它们，已有 zlib 链接。
- 上游 LICENSE 为 MIT，版权 Pete Pei 2026；当前 OpenNotes 已在 THIRD_PARTY_NOTICES 和 licenses/NotesBridge-MIT.txt 记录既有移植。新增移植须保持相应归属，不能将上游发行密钥、feed 和品牌当自己的配置。
- 已读 README 多语言文件名及主 README、CHANGELOG、架构、onChange 需求、Sparkle 配置、CONTRIBUTING、SECURITY；文档中的步骤和历史状态没有转化成本次运行结果。源码行的证据优先于旧说明。
- 本次交付只新增此报告。没有运行上游测试、没有修改产品代码、没有打开 Apple Notes／ProNotes／OpenNotes、没有访问真实 Notes 数据库或密钥、没有发送任何模型请求。
