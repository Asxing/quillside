# AI、个人知识库和工作台：源码逐项比较

> 历史实现/审计记录。2026-10-08 最新范围与当前状态见 [功能清单](CURRENT-FEATURES.md)；搜索与知识库已退出，笔记文件导入导出延期。

> 本文记录此次修复前的审计基线。2026-10-08 的修复与剩余验收见 [持续对齐状态](GOAL-STATUS.md)；旧差距行保留作为问题依据，不能当作最新实现状态。

审计日期：2026-10-08，Asia/Shanghai。审计对象为当前 OpenNotes 0.1 开发源码，以及固定 commit 的公开上游源码。本报告完成的是下述范围的代码比较，不是这些产品的全功能实机验收，也不表示 OpenNotes 已实现完整 ProNotes 等价功能。

结论：OpenNotes 已把“捕获文字 → 自选模型 → 流式预览 → 局部应用”和“主动导入资料 → 本地检索 → 带来源问答”接成原生 Swift 工作流。与 NotesOllama 相比，增加了多协议、Keychain 和预览；与 Notechat 相比，增加了文件导入与中文关键词检索，但尚无向量检索、聊天历史和 Markdown 渲染。当前仍有配置保存、来源绑定、读取失败与快照删除之间的具体错误，不能用已有单元测试全部通过替代这些门槛。

## 1. 审计范围和证据边界

完整读取的 OpenNotes 文件如下；同时读取了 `NotesDBReader.readKnowledgeDocuments`、`getAllNotes` 的边界、当前 README、第三方声明和已有 AI/知识库测试。

| 文件 | 审计的行为与入口 |
|---|---|
| [AIConfiguration.swift](../src/Quillside/AI/AIConfiguration.swift) | `ModelProtocol` 的名称/默认地址；`ModelConnection.hasSameCredentialOrigin/endpoint`；默认动作；配置校验；单次变量替换；目录与 JSON 保存；`ConfigurationStore.init/save/selectedConnection`；Keychain 读、写、删 |
| [ModelClient.swift](../src/Quillside/AI/ModelClient.swift) | 四协议请求构造；四协议逐行流解析；拒答/截断/完成判断；拒绝重定向；HTTP 状态、超时、取消、最大结果大小 |
| [KnowledgeIndex.swift](../legacy/retired-features/src/Quillside/Knowledge/KnowledgeIndex.swift) | 资料与命中模型；分词、切块、哈希；SQLite 建表/版本；prepare/bind/read/execute；事务 upsert/remove；documents/search；中文子串和 FTS 合并 |
| [NotesBridgeDecoder.swift](../src/Quillside/Services/NotesBridgeDecoder.swift) | 直接/包装/递归文档解析；正文/属性/段落/清单/附件信息解码；protobuf 字段、长度、字符串、int32、跳过、varint；解压复用边界 |
| [SelectionTransaction.swift](../src/Quillside/Workspace/SelectionTransaction.swift) | AX 属性读取；捕获正文/选区/窗口/进程/笔记身份；UTF-16 范围验证；替换/下方插入；原生对象拒绝；写后读回 |
| [WorkspaceModel.swift](../legacy/standalone-workspace/WorkspaceModel.swift) | 资料集合与笔记过滤；capture/输入变更；generate/引用检查/cancel/apply/copy/openSource；加载 Notes、选择导入、快照刷新；文件导入；删除/检索/模板；工作台窗口创建与显示 |
| [WorkspaceView.swift](../legacy/standalone-workspace/WorkspaceView.swift) | 写作、搜索、知识库、来源列表；连接新建/编辑/默认/删除/密钥清除/合成测试；配置导入导出；提示词 CRUD；模板 CRUD；设置窗口 |

上游依据：

- NotesOllama：`7941647773ed75e33cf0a948e74cf828b00942b0`。读了 `NotesWatcher`、`OllamaService`、`PasteService`、`MenuViewModel`、`MenuView`、`commands.swift/json`、`AppDelegate` 和告警入口。checkout 的 HEAD 已核验；没有运行其应用或 Ollama。
- Notechat：`43a1ca8d15e9d1cdf005d653743afad1dff56d5f`。从 GitHub 下载该 commit 的完整源码归档，读了 `extractAndEmbedNotes`、`CharChunker`、`databaseService`、`Chat`、`SourcesList`、`main`、`ollamaSetup`、`App`、`Header`。没有运行安装脚本、全库提取或模型下载。
- RafalWilinski MCP：读取已保存的固定 commit `b95a40ae858d791cd54e2a52700041bb2728fbe6` 的 `index.ts`。其他 MCP、parser、exporter 仅做选定模块的角色核查，见第 7 节；没有穷尽审计其全部工具。
- 运行证据仅来自临时合成 SQLite 的隔离探针；未读取用户 Notes 正文或模型凭据，未调用云端推理，未进行真实 Notes 写回。

## 2. 哪些是用户要求，哪些是上游的额外能力

用户明确要求是：参考 GitHub 已有实现，采用原生技术栈构建 ProNotes 同类软件，并能在软件内配置模型、API Key、提示词和个人知识库。已有实施方案还提出了选区保护、资料范围、来源引用与失败恢复。这些应当成为产品的可验收行为。

“比较所有已有代码功能”要求把差异说明白，不自动意味着复制每个参考项目的全部产品。Notechat 的 Homebrew 自动安装、MCP 服务、Ruby 取证解密、exporter 的双向目录同步，并非用户逐项指定的功能。它们可作为后续能力或模块来源，不能因未移植这些产品就机械判定所有开发未完成，也不能把这些功能从比较表中隐去。

已有 [实施报告](../../ProNotes开源实现调研/实施报告.md) 明确把向量检索放在关键词闭环之后，并把 embedding 描述为可选。因此“个人知识库”不等于必须先有 embedding。不过，要宣称与 Notechat 的语义问答能力等价，就必须补齐向量召回并用同义词/跨语言样本证明，不能把 FTS 当成已完成该能力。

| 验收层级 | 当前证据 | 尚需证明 |
|---|---|---|
| 原生技术栈 | SwiftUI/AppKit 窗口、Foundation 网络、SQLite、Security；此路径无 Electron UI | 真实窗口、焦点、权限、快捷键和 Notes 行为 |
| 模型/API Key/提示词可配置 | 已有 CRUD、默认连接、Keychain、JSON 导出和单次变量渲染 | 保存失败保持一致；重启恢复；实际服务商生成/取消/限额错误 |
| 个人知识库可使用 | 已导入快照、集合选择、子串/FTS、来源打开、删除 | 失败不能误删除；来源绑定准确；检索质量和规模；重启后的正确性 |
| 完整 ProNotes 功能等价 | 此报告只覆盖 AI/KB/工作台 | 原厂完整行为矩阵和其他模块验收由总表负责，不能由本报告代替 |
| 上游额外能力 | 第 3、4、7 节记录 | 选择纳入后再成为该版本的验收项 |

## 3. AI：逐项比较 NotesOllama 与 OpenNotes

| 功能 | NotesOllama 固定源码 | OpenNotes 当前源码 | 差异与判断 |
|---|---|---|---|
| 输入来源 | `NotesWatcher` 收 AX 选区变化；有选中文字才显示动作 | 手工输入，或捕获选区；无选区时取全文正文 | 当前稿件可检查；尚无独立“选区/整篇/相关笔记”上下文切换器 |
| Notes 内入口 | 笔记窗口右下角 nonactivating panel | AI 入口打开可激活工作台，捕获先发生 | 工作流不同；完整内联交互对标仍须验收 |
| 模型列表 | `OllamaService.fetchModels()` → `ollamaKit.models()`，菜单刷新和选择 | 模型 ID 手填；四种连接协议 | **未实现拉取可用模型**；现有手填是实际能力，不能称模型发现完成 |
| 本地服务地址 | 环境变量 `NOTESOLLAMA_OLLAMA_BASE_URL` 或 localhost | 软件内 Base URL | OpenNotes 配置更完整；HTTP 限 loopback，远端要求 HTTPS |
| 云模型和密钥 | 所读路径只有 Ollama，无云 provider 设置 | Chat Completions、Responses、Anthropic、Ollama；Keychain | 有代码和合成协议测试，不等于所有兼容服务/具体模型均可用 |
| Prompt | bundle `commands.json` 的 9 个动作；运行中加载 | 12 个初始动作；系统提示词、写作偏好、自定义动作编辑、JSON 导入导出 | 不需要修改 app bundle；语气改写可用自定义动作，但未单独提供 NotesOllama 的全部预设 |
| 上下文装配 | `prompt + 两个换行 + selectedText` | system + 写作偏好；用户模板变量；可追加 KB 片段 | 仅有单轮请求；没有聊天历史、每动作模型与能力配置 |
| 流式 | OllamaKit publisher | URLSession AsyncBytes，SSE/NDJSON → 正文增量 | OpenNotes 会验证结束状态；逐行解析没有通用 SSE 多 data 行组帧支持 |
| 取消 | 移动光标/切换前台会取消生成；取消全部 publisher | 显式取消 Task、运行 ID 拦截迟到正文；生成时不写 Notes | OpenNotes 对取消/截断保留预览且禁用应用；真实慢流和取消网络仍需端到端验收 |
| 写回 | 用方向键取消选区，再把流逐段 ⌘V 插入；100 ms 排队 | 完整生成后用户替换/插入；检查身份/窗口/正文；AX 局部写入 | 未复制实时贴流；这是清晰的产品选择，不能声称交互相同 |
| 剪贴板 | 每段清空后填纯文本 | 只有用户复制才覆盖；AX 写回不借剪贴板 | 避免生成过程覆盖用户剪贴板 |
| 富文本 | 粘贴纯文本；针对 NotesCmdr 三反引号特殊排队 | 纯文本 TextEditor 预览和 AXSelectedText | **两者都不能据此声称生成 Markdown 原生表格/清单**；OpenNotes 表格摘要只是 Markdown 字符串 |
| 完成/错误 | publisher completion 统一通知 `nil`；失败仅 print | HTTP 错误、异常 finish reason、拒答、EOF 不完整显式失败 | OpenNotes 的错误终态更明确；具体供应商错误正文被统一简化 |
| token/耗时/价格 | 未见 | 只有最大输出 token 与文本字节上限 | usage、实际/估算费用、token 预算均未实现；不宜标记“成本管理已完成” |
| 登录启动/更新 | SMAppService；“Get latest version”网页链接 | 当前总应用另有登录启动；该层未做自动更新 | 不能把 NotesOllama 网页链接当其自动更新实现 |

源码：[NotesWatcher](https://github.com/andersrex/notesollama/blob/7941647773ed75e33cf0a948e74cf828b00942b0/NotesOllama/NotesWatcher.swift)、[OllamaService](https://github.com/andersrex/notesollama/blob/7941647773ed75e33cf0a948e74cf828b00942b0/NotesOllama/Services/OllamaService.swift)、[MenuViewModel](https://github.com/andersrex/notesollama/blob/7941647773ed75e33cf0a948e74cf828b00942b0/NotesOllama/Menu/MenuViewModel.swift)、[PasteService](https://github.com/andersrex/notesollama/blob/7941647773ed75e33cf0a948e74cf828b00942b0/NotesOllama/Services/PasteService.swift)、[命令文件](https://github.com/andersrex/notesollama/blob/7941647773ed75e33cf0a948e74cf828b00942b0/NotesOllama/commands.json)；本地证据见第 1 节 AI/Workspace 文件。

上游本身也有需要避免照搬的行为：`PasteService.done()` 的末尾三反引号粘贴不再调用 `canNotesReceivePaste`；`OllamaService` 对失败和完成都用 `nil` 通知上层；`fetchModels` 失败吞成空数组。它们说明“已有源码”不是“无需重新设计错误语义”。这些为源码发现，未在上游 app 实机复现。

## 4. 知识库：逐项比较 Notechat 与 OpenNotes

| 功能 | Notechat 固定源码 | OpenNotes 当前源码 | 差异与判断 |
|---|---|---|---|
| 摄入授权范围 | AppleScript 遍历 `every note`；没有逐篇选择入口 | 主动勾选 Notes 或选择文件 | OpenNotes 的导入范围更细；实际回调与数据读取失败仍需修正 |
| 获取正文 | AppleScript HTML，正则移除标签/图片、压平空白 | 只读 SQLite + NotesBridge protobuf 解码；只使用 `noteText` | 已解出的属性/附件信息没有进入 KB；原生表格、图片、附件正文未摄入 |
| 文件资料 | 本次路径未见文件导入 | Markdown、UTF-8 文本、文本 PDF | PDF 有页码字符串，无 OCR、DOCX/网页抓取；50 MB 文件和 5 MB 文本限制 |
| 切块 | 500 JS 字符，50 overlap；带标题；按空格找边界 | 800 Swift Character，100 overlap；标题加入索引词 | OpenNotes 中文长文可定长切分；没有段落/标题结构切块、用户参数或 token 预算 |
| Embedding | 固定 localhost `/api/embeddings`，固定 `nomic-embed-text` | 没有 | 属语义召回差距；不能把 NaturalLanguage 分词称 embedding |
| 索引 | Notes/Chunks + sqlite-vec `float[768]` | documents/chunks + SQLite FTS5；内容 SHA-256 | OpenNotes 无向量维度/模型指纹，也无需为当前 FTS 假装配置这些字段 |
| 检索 | 查询向量，默认 top 5、distance < 19、folderName 过滤 | 原句子串优先；分词取前 32 个唯一词 OR；不足 8 条再 FTS BM25 | 当前无向量、rerank、检索阈值、跨语言语义保证；多词 OR 可能带来低相关片段 |
| 集合 | folderName 单选 | Notes 文件夹名或“文件”，加“全部” | 不是完整集合管理；不支持创建/重命名/移动/多集合归属；同名文件夹和保留名会碰撞 |
| 更新 | 每次清空三表后全库重建；固定 500 ms 等待 | Notes 手工刷新已导入 IDs；文件重导入同路径替换 | OpenNotes 只更新选定快照；未使用存储 hash 跳过未变文本，也无后台同步 |
| 移除 | 全库重建可能移除旧记录；未见逐资料删除 UI | 单篇事务删除 documents/chunks/FTS；刷新中移除不再出现的 Notes | 本地单篇删除合理；错误扫描误认为不存在会误删，见 B1 |
| 回答上下文 | 召回正文 + 最近 4 条 messages | 所选动作 + 输入/问题 + 命中片段 | OpenNotes 当前单轮；用户明确要求知识库，不自动要求长期聊天历史 |
| 回答来源 | 每条 assistant message 固定保存 sources；标题、时间、hover 正文 | `[S1]` 编号、片段、原文链接；共享 `hits` 状态 | OpenNotes 有原文跳转但来源与结果未冻结，见 B3；编号校验不证明论据支持结论 |
| 展示 | ReactMarkdown 渲染聊天；没有 Notes 写回 | SwiftUI TextEditor，可编辑，复制/局部写回 | 原生实现完成；渲染保真尚欠缺 |
| 本地模型准备 | 自动寻找/安装 Homebrew/Ollama，pull 两个固定模型 | 用户已有服务，手填模型并测试 | 自动安装是上游额外能力，尚无必须移植的用户要求 |
| 运行记录 | React 临时 state；没有持久聊天记录路径 | 写作输入/结果/命中也是内存；配置和索引落盘 | 二者都不能宣称完整历史管理；保存不含秘密的 job 元数据可作为后续设计 |

源码：[摄入/embedding](https://github.com/arnestrickmann/Notechat/blob/43a1ca8d15e9d1cdf005d653743afad1dff56d5f/src/electron/noteProcessing/extractAndEmbedNotes.ts)、[CharChunker](https://github.com/arnestrickmann/Notechat/blob/43a1ca8d15e9d1cdf005d653743afad1dff56d5f/src/electron/noteProcessing/CharChunker.ts)、[databaseService](https://github.com/arnestrickmann/Notechat/blob/43a1ca8d15e9d1cdf005d653743afad1dff56d5f/src/electron/database/databaseService.ts)、[Chat](https://github.com/arnestrickmann/Notechat/blob/43a1ca8d15e9d1cdf005d653743afad1dff56d5f/src/ui/components/Chat.tsx)、[SourcesList](https://github.com/arnestrickmann/Notechat/blob/43a1ca8d15e9d1cdf005d653743afad1dff56d5f/src/ui/components/SourcesList.tsx)、[Ollama setup](https://github.com/arnestrickmann/Notechat/blob/43a1ca8d15e9d1cdf005d653743afad1dff56d5f/src/electron/ollamaSetup.ts)。

不能从 Notechat 直接移植的错误模式：

1. `process.stderr.on("data", async ...)` 对每个数据块直接 split 行，没有保留跨块残行；处理一个块时 `await processNote`，下个事件仍可同时修改共享的 `note/body/currentSection`。进程 close 再固定等待 500 ms，不等于所有 embedding 作业已经完成。单 chunk 失败会被 catch 后继续；最后 osascript code 0 即可 resolve，不能据此说全部资料索引成功。
2. Chat 流对每次 reader.read 的字节分别 `new TextDecoder().decode` 和 JSON.parse 行，不缓存残缺 UTF-8/JSON 行。TCP 分块并不保证 JSON 行完整。没有 AbortController、HTTP status 检查、终态 done 必须存在的验证。
3. 数据库固定加载 arm64 sqlite-vec；维度固定 768。更换 embedding 模型不能仅改 model 字符串。
4. `CharChunker` 无空格时可能把剩余整个中文长文作为一个块；标题占去大部分预算时，overlap 可能导致位置不前进。OpenNotes 应保留自身有进度保证的切块，不直接翻译该循环。
5. `ollamaSetup.stopOllama()` 杀掉 `lsof -i :11434 -t` 返回的进程；main 在应用启动和退出时调用它。这是共享本地服务的破坏性生命周期假设，原生版本无需复制。
6. 代码会打印笔记正文、检索上下文及命中记录。OpenNotes 当前不记录正文和密钥的做法值得保留。

上述为精确源码路径发现，未启动 Notechat 或扰动用户本地模型服务。

## 5. 需要修复的 OpenNotes 具体错误

以下行号对应审计开始时的 0.1 源码，基线哈希在附录。后续修复应记录新验证，不能只删掉发现文字就视为已解决。

### B1 · P1：读取失败被当成成功空集，刷新可能误删资料

`NotesDBReader.readKnowledgeDocuments`（103–112）只在 `sqlite3_step == SQLITE_ROW` 时循环，不检查结束结果是否为 `SQLITE_DONE`。prepare 成功后若 step 返回 BUSY/IOERR/CORRUPT，会返回空/部分数组。`WorkspaceModel.refreshNotesSnapshots`（178–182）据此删除旧索引中所有未出现的 ID，并报告“删除或锁定的来源已移除”。这是失败到删除的错误转换，并非正常删除同步。

`KnowledgeIndex.documents`（113–116）和 search 内 read（128–133）同样吞掉 step 错误，可能让暂时锁库看起来像“没有资料/没有相关片段”。本轮用实际未修改的 KnowledgeIndex.swift 编译了只含合成资料的临时探针，实际输出：

```text
before lock documents=1
locked documents returned=0
locked search returned=0
after unlock documents=1
```

临时数据库由第二连接执行 `BEGIN EXCLUSIVE`，随后回滚；没有改用户索引。复现文件为 `/tmp/opennotes-ai-audit-probe/Probe.swift`。该探针直接证明 KnowledgeIndex 的吞错；Notes 读取链路的误删除为上面的源码组合证据，没有对用户库制造错误。

修复验收：所有查询检查最终返回码；来源扫描失败时完全保留旧快照；只有完成的权威扫描才能计算删除集合；更新、删除最好在一次索引事务提交。新增 BUSY、部分扫描失败、锁定/删除的区别测试。

### B2 · P1：配置文件和 Keychain 更新顺序可使凭据对应到错误主机

`WorkspaceView` 保存连接（229–241）先用原连接 UUID 替换 Keychain secret，然后修改 `store.value`，最后 `store.save()`。如果用户把连接 A 改为连接 B 的地址和新密钥，Keychain 成功而 JSON 写入失败，磁盘仍保留 A 地址，Keychain 却已经是 B 的密钥；重启后可能向 A 发送 B 的密钥。同源检查只挡空 key 的复用，不能修复这条失败路径。

删除连接（207–213）先删 secret 再保存，保存失败则磁盘仍引用已删除的密钥。其他 prompt/template/import/default edits 先修改 live store 后保存，失败没有恢复原内存状态。该问题依据真实调用顺序；本轮未故意修改任何用户密钥或配置。

修复验收：用候选配置提交；新的凭据绑定使用独立引用或新 ID，不能先覆盖旧引用；配置提交成功后清理失效 secret；失败回滚 live state。使用可注入的临时文件存储和假 Keychain 模拟每一步失败，证明重启后 endpoint/key 对应关系不变。简单交换先后顺序仍可能把旧密钥绑定到新地址，不能算完整修复。

### B3 · P2：完成答案的来源编号会被下一次检索重标

`WorkspaceModel.hits` 同时承担“本地检索预览”和“本次 AI 答案来源”。generate（97–111）赋值并校验；previewRetrieval（220–221）再次赋值；removeDocument（216–218）清空；两处 UI 都用同一 `sourceList`（WorkspaceView 173–181）。生成结果 `[S1]` 保留时，在知识库页检索其他词再回写作页，其 `[S1]` 按钮指向另一片段。模板也不会清理旧来源。

修复验收：每个生成结果保存不可变 `GenerationResult.sources` 和索引版本；检索预览用另一 state。改变预览/集合/删除来源不会偷偷改变旧答案编号。可以提示原来源已移除，但不能把相同编号重新绑定。

### B4 · P2：知识库问题放在主输入框时，问题没有发送给模型

默认“知识库问答”模板只有 `{instruction}` 和 `{sources}`（AIConfiguration）。generate 允许 input 非空、instruction 为空，并按 input 检索（WorkspaceModel 82、94）。但装配模板仍使用空 instruction（100–103），从而发送“问题：”空白和资料，没有发送用户实际问题。

修复验收：显式计算 effectiveQuestion 并统一用于检索和问答模板，或 UI 清晰要求独立问题字段；以只有主输入、只有问题、二者都有的三种情况做请求体测试。

### B5 · P2：集合范围用显示名和保留字判断，可能扩大检索范围

`collections`（WorkspaceModel 55）为 `["全部"] + Set(document.collection)`，而生成/预览把字符串“全部”转为 nil 全库（94、221）。真实 Notes 文件夹若就叫“全部”，会出现重复选项且永远不能只检索该文件夹。“文件”又是文件导入集合名；不同账户/父目录同名 Notes 文件夹也合并。

修复验收：集合使用独立稳定 ID，all 是枚举状态，显示名与身份分开；Notes scope 保留 account/folder ID。用同名文件夹、名为“全部/文件”的合成资料验证集合隔离。

### B6 · P2：索引版本被无条件覆写，读失败后的设置缺少恢复状态

KnowledgeIndex.init 在 CREATE IF NOT EXISTS 后无条件 `PRAGMA user_version=1`，从不检查旧版本。临时探针把自建库版本设为 99，重新打开后实际输出 `future schema version after reopen=1`。未来版本的库被降版本标记，即使 schema 已经变化；缺少拒绝、迁移或重建选项。

ConfigurationStore.init 解码失败后保留默认内存配置，只设置 status；之后任意普通“保存系统配置/模板/连接”操作都可把故障原文件覆写成默认值和当前局部修改，缺少备份恢复状态。初次 catch 的“原文件未改动”本身正确，但不代表后续保存保护完整。

修复验收：识别 schema version；拒绝未知版本并保留源文件；显式迁移或可重建派生索引；加载失败的设置进入可恢复状态，不让普通编辑静默覆盖故障文件。

### B7 · P2：异步操作状态缺乏统一边界

Notes 搜索页的导入按钮只看 indexing，生成过程可以通过侧栏进入该页继续摄入；previewRetrieval 有独立 Task，但没有 request ID 保护快速连续查询；apply 发起 Task 前关 writeAvailable，却没有 applying 状态统一锁定输入/结果/导航。Swift actor 可避免同时执行一个 SQLite 操作，但不能自动让多步工作流原子化。主要可观察风险是旧查询覆写新预览、半批次索引状态和错误状态覆盖；不应将其泛化成已经证实的错笔记写回。

修复验收：明确生成、检索、摄入、应用各自的作业状态与取消规则；按运行 ID 丢弃迟到的预览结果；摄入批次失败报告实际完成数，并刷新与磁盘一致的列表；AI result 及来源冻结。对 UI 的迟到任务测试优先于继续增加静态按钮数量。

## 6. 已有保护、现有测试和缺失的验证

本轮保留的正确机制：endpoint 检查 scheme/host/userinfo/query/fragment；远程 HTTPS；导入配置给连接换 UUID；不跟随网络重定向；Responses `store:false`；输出上限；取消后运行 ID 隔离；拒绝空/截断/错误生成；单次模板替换；只写派生索引；单文档 upsert/delete 事务；Notes 身份、窗口、全文快照和 UTF-16 范围的写前验证；选区含 U+FFFC 原生对象时拒写。这些是代码中存在的机制，不能扩大成“已完成所有系统与隐私保证”。

现有 [AIAndKnowledgeTests.swift](../legacy/retired-features/tests/AIAndKnowledgeTests.swift) 覆盖四协议路由、synthetic-key 不进入 body、端点限制、凭据 origin、流完成/截断、模板非递归、选区边界、中文集合替换删除、来源编号与配置 JSON 往返。可选本地 HTTP 测试证明合成服务下的流处理。它没有覆盖 B1–B7 的失败序列、配置持久化故障、真实 Notes AX 写回、撤销、切换窗口、实际服务商模型或真实大型资料库。

进一步验证应匹配用户行为：

| 门槛 | 应保留的可审查证据 |
|---|---|
| 配置与凭据一致 | 创建/编辑/导入/删除在文件失败、Keychain 失败、重启后仍保持原绑定；全部用合成 secret |
| 检索与引用正确 | 来源 ID 稳定；切换集合/检索/移除后旧答案仍映射原来源；无命中和查询故障明确区分 |
| 来源更新正确 | 改正文/删笔记/锁笔记更新；权限丢失、BUSY、解析失败不误删；单篇解析失败能定位原因 |
| 模型真实闭环 | 每实际采用协议的合成文本请求、流结束、用户取消、超时、429、截断；不靠模型名能选择就判断支持 |
| Notes 编辑 | 临时合成笔记中捕获中文/emoji/复杂文字，生成期间切换/改正文拒绝应用；替换/插入后读回；⌘Z 是否一个可理解的撤销步骤 |
| 索引质量与规模 | 中文短词、同义词、跨语言、无关词、同名文件夹；大文件/多资料的延迟和内存；分别记录 FTS 与未来向量效果 |
| 富文本 | 先定义支持的 Markdown 结构，再验证原生标题/列表/表格/链接/代码的生成、写回与撤销，不能只比较纯文本 |

模板、普通 prompt、AI 结果目前均是纯文本；正文统计不等于 token 预算；编号有效不等于回答有事实依据；本地 SQLite 不等于云模型不会收到选定资料。这些应继续在产品说明中明确。

## 7. MCP、parser、exporter 应放在架构的什么位置

这些项目不是可直接合并的另一套原生 GUI。它们分别提供工具 API、私有数据格式知识和迁移工作流；原生实现应提取必要行为与测试样本，保留一个 Notes 适配层、一个索引层和一个编辑协调器。

| 参考 | 本轮实际核对 | 可借鉴的模块职责 | 不能直接得出的结论 |
|---|---|---|---|
| [sweetrb/apple-notes-mcp](https://github.com/sweetrb/apple-notes-mcp/tree/ae27e7bfdc7ea120732b01242c683e3d1f45703f) | 固定源码的 searchScope、searchContentDb、notesExport 选定路径；index.ts 仅作入口定位 | 搜索明确说明标题/正文范围；数据库正文搜索/扫描上限；Markdown/HTML 导出适配；将来可选 MCP 入口 | **未审计所有工具，更未验证“80 工具全部可用”**；不是 App 内模型/KB GUI 的替代品 |
| [RafalWilinski/mcp-apple-notes](https://github.com/RafalWilinski/mcp-apple-notes/blob/b95a40ae858d791cd54e2a52700041bb2728fbe6/index.ts) | 完整 index.ts | MiniLM 384 维本地 embedding、LanceDB vector+FTS、RRF 排序；JXA 数据获取 | 代码实际有 `create-note` 实现，不能只据 README TODO 说无写入；其 list-notes 实际回索引行数、get-note 字符串化问题也说明不能照搬；无原生 UX |
| [apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser/tree/4754a2b62686570cca46690d101079e80cf6ae66) | 固定 README/树，`AppleNotesEmbeddedTable.rb` 的行列、单元格、重建/HTML/JSON路径 | Notes 表格、嵌入对象、版本化 fixture 和解析参照 | 未移植完整 Ruby parser；README 的解密/取证能力不是用户要求；不应对活跃 Notes DB 运行修改表的取证流程 |
| [notes-exporter](https://github.com/storizzi/notes-exporter/tree/3043f28d3cba4712e7452261f0ef44da1031f892) | README + `sync_to_notes.py` 的 hash/冲突/创建更新，`query_notes.py` 的文本/日期/语义入口，tracking 辅助 | 导出、Markdown→Notes 同步、冲突侧文件、增量 tracking、Qdrant 检索适配的设计参考 | 不是“仅导出、无 AI”；但 Qdrant 实现、所有格式和调度脚本本轮没有穷尽运行；其双向同步尚不是 OpenNotes 已有功能 |
| NotesBridge | 当前引入的是 `NotesBridgeDecoder.swift`，见第三方声明 | 正文/属性 protobuf 解析；后续富文本/附件解析可继续参考原工程 | 引入解码器不等于已经拥有其附件、Obsidian 导出、增量同步和更新器 |

选定源文件：[MCP 搜索范围](https://github.com/sweetrb/apple-notes-mcp/blob/ae27e7bfdc7ea120732b01242c683e3d1f45703f/src/utils/searchScope.ts)、[MCP 正文搜索](https://github.com/sweetrb/apple-notes-mcp/blob/ae27e7bfdc7ea120732b01242c683e3d1f45703f/src/utils/searchContentDb.ts)、[MCP 导出](https://github.com/sweetrb/apple-notes-mcp/blob/ae27e7bfdc7ea120732b01242c683e3d1f45703f/src/services/notesExport.ts)、[parser 表格](https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/4754a2b62686570cca46690d101079e80cf6ae66/lib/AppleNotesEmbeddedTable.rb)、[exporter 同步](https://github.com/storizzi/notes-exporter/blob/3043f28d3cba4712e7452261f0ef44da1031f892/sync_to_notes.py)、[exporter 检索](https://github.com/storizzi/notes-exporter/blob/3043f28d3cba4712e7452261f0ef44da1031f892/query_notes.py)。

原 [GitHub 比较](../../ProNotes开源实现调研/research/github-alternatives.md) 将 notes-exporter 的能力写得过窄，也用 Rafal MCP README TODO 描述其写入缺口。应以上述固定源码补正；本报告没有修改原报告或产品代码。

## 8. 原生实现下一步的优先顺序

1. 先完成 B1–B6 的数据/引用一致性修复及失败路径验证，建立 `ConfigurationCommit`、`GenerationResult`、稳定 collection/source ID、明确 snapshot scan result。它们直接关系到用户配置和个人资料是否可信。
2. 对已经宣称支持的四协议做真实合成文本验收；补齐列表发现、usage 事件、能力参数与上下文 token 预算。把 `Connection` 与可选 `ModelProfile` 分开后，才能支持每个动作选不同模型而不重复保存密钥。
3. 完成 Notes 真机闭环，保留捕获→生成→应用之间的稳定身份与正文保护；对纯文本之外的输出建立明确支持集并逐项实现。不能让“生成了 Markdown”充当“原生格式已写入”的证据。
4. 先量化 FTS 的召回边界，再按需要增加原生 embedding adapter、向量索引与融合排序。向量模型指纹、维度、重建、删除同步必须与索引一起交付；不要直接硬编码 Notechat 的 768 维假设。
5. 选定是否需要聊天历史、自动资料同步、MCP、双向目录同步等额外能力；一旦纳入某个版本，再把其故障与冲突语义纳入验收。保留完整差异表，避免把所有参考项目拼成互相抢窗口、抢剪贴板和重复索引的应用。

## 附录：审计基线

OpenNotes 工作目录当时尚未形成可引用的独立产品 commit，故记录 SHA-256；以下是审计时读到的文件，不代表后续修复后的当前值。

```text
d131d83459908427119fcc8af1e7986271421aa557f04ea0c39e683b8c3ec2b6  AI/AIConfiguration.swift
cc28eaafd3b699b2723a24763a82ca0c4f1d3695350ae3228c94f3c9056eebb6  AI/ModelClient.swift
568043d66e71c6a29807a736c29e042cf218d7fc17ae8b923a0161d55a978bb5  Knowledge/KnowledgeIndex.swift
d5df0e882107cfa176ca49c55d68afcaa6a5b7dad033fa085086dd5fc3ea7c1e  Knowledge/NotesBridgeDecoder.swift
0ed669551ace2c70913651b35a5019db91ab356fd65a1b2a76468fcebd818a12  Workspace/SelectionTransaction.swift
b1f3348d1e7b385bdecbc44af25ccdacf1762050601f7863d97e1bbd6791249c  Workspace/WorkspaceModel.swift
ccaa1b77e11e13f6491ac7b96d2b1587a9d515cdb4a996bc7dd7f33d48086d72  Workspace/WorkspaceView.swift
```

本报告未改变产品代码、用户 Notes、配置或密钥。上游源码下载与隔离探针均位于 `/tmp/pronotes-github-research/` 和 `/tmp/opennotes-ai-audit-probe/`；除报告外没有增加项目文件。
