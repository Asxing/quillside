# ProNotes 最新对标与当前功能取舍

> 当前状态更新（0.3.5）：固定本机开发签名已生效；主要原生编辑、AI、模板和正文反链闭环已实测。旧版本权限阻塞与待验文字仅为历史记录。当前结果与未覆盖边界统一见 [0.3.5 实机验收](NATIVE-ACCEPTANCE-0.3.5.md) 和 [验证记录](../VERIFICATION.md)。

> 当前固定构建0.3.4：整套实机验收尚未完成。最新真实结果见 [验收记录](NATIVE-COMMAND-ACCEPTANCE.md)；旧实现条目保留为历史基线。

2026-10-08，Asia/Shanghai。当前实现基线为 OpenNotes **0.3.1**（92行审计基于0.3.0，修复项已更新）；当前应交付 Apple Notes 编辑增强，而不是“官网列出什么就全部复制”。本报告重新读取历史矩阵全部 92 个 PN 行及对应当前实现。92 行包含官网能力、上游实现细节和用户早期扩展要求，**不等于 ProNotes 有 92 项稳定功能**。

**当前不能声称“全部准备完成”：核心功能大多已有代码和回归，Notes 内真实操作、写回与撤销仍需验收。搜索、知识库和 WIP 的缺失是产品取舍；文件导入导出是延期。三者不能混作尚未开发的核心缺项。**

取舍来源：搜索/知识库/MCP包装退出、文件导入导出延期、原位AI与正文反链，是用户明确方向；菜单栏隐藏、自动任务路由、原生AI表格、多语言/更新等的优先级，是本轮结合定位提出的建议，不表示用户曾逐项要求删除。保留现有用户配置，不因这份审计删除动作或模板。具体可执行验收见 [核心验收表](CORE-ACCEPTANCE.md)。

## 证据边界

- **官网承诺**：本轮实时读取 [ProNotes 官网](https://www.pronotes.app/)。网站说明选区工具条、Markdown、slash、反链、模板、快捷搜索和 Notes 内 AI；Floating notes/Vim 明标 WIP。网页是产品声明，不是运行证据。
- **本地原厂证据**：既有 [ProNotes 0.7.8.2 分析](../../ProNotes开源实现调研/research/local-inspection.md) 记录十项工具条、提示词/模型/通用设置及静态资源。既有模拟输入未触发其工具条/Markdown/slash，不能把失败直接归为产品缺陷，也不能假定原厂业务已实测。
- **模板协议未知**：官网链接的 [模板文档](https://dexterleng.notion.site/How-to-use-Templates-in-Apple-Notes-with-ProNotes-b35a196d29c54cd8a553723a1289f80f?pvs=4) 本轮仍获取失败（404）。不虚构原厂发现规则、变量或富文本保真合同。
- **OpenNotes 源码**：本轮读取当前入口、服务、模型和测试。下方逐项证据指向实际文件；旧审计的缺项不会自动继承。
- **测试基线**：既有 [0.3.0 验证收据](verification-0.3.0.json) 为 167 项/166 通过/1 可选截图跳过、26 个 suite；四协议为 localhost 合成服务，设置经 CUA 检查，两篇专门建立的 Notes 合成笔记证明 A→B 解析。
- **实机验收**：本报告没有新增 GUI 操作。格式、slash、模板、AI 写回及正文反链的完整真实流程默认仍待验收；[验证记录](../VERIFICATION.md) 若后续更新，应作为最新结果。测试和原生视图渲染不能替代真实 Notes 写回/撤销。源码快照 SHA-256 记录于 [机器可读矩阵](current-parity.json)。

本轮已安装 OpenNotes 0.3.1（SHA-256 `75882bb66090a31b716eb3feea54b6538df1d2f709fcf319aaa19394f69173bf`）；授权操作仍遇到系统管理员密码认证，尚不能宣布辅助功能生效。用户已经授权，无需再次请求许可，但系统认证需用户在本机完成。ProNotes本地样本最低版本14.6，与官网13.0+不同，不能据此把网页最低版本直接作为新应用兼容合同。

0.3.1 已补Markdown真实正文检测、单项开关、正文/单元格识别、面板独立输入隔离、统一原生粘贴与多行SSE。新基线为177项测试、176通过、1旧截图跳过。详见 [实施记录](CORE-IMPLEMENTATION-0.3.1.md)。用户已确认排除账号计费、遥测、Floating notes/Vim和复杂路由。

## 当前应交付的主功能

| 主功能 | ProNotes 对标依据 | 当前 OpenNotes | 产品决定与验收重点 |
|---|---|---|---|
| 选区工具条 | 官网＋十项既有UI | Ask AI、字体、B/I/U/删除线、高亮、链接、对齐、清单；显隐排序已接线 | **当前核心**。验证选中正文就地操作，原生菜单可用性、格式状态与撤销 |
| Markdown 快捷输入 | 官网精确符号合同 | 9 项全覆盖，含三反引号与短划线；总开关 | **当前核心**。核对行首/原生自动转换/输入法/失败恢复 |
| slash 命令 | 官网别名与原生表格 | 精确 aliases 已补齐，支持原生表格及模板；确认前核对 AX token | **当前核心**。键盘提交、中文候选态与非正文边界 |
| 模板 | 官网重复片段与slash插入 | 设置维护；自定义快捷词、/template选择器、日期变量；就地纯文本写回 | **当前核心**。无需跳后台插入；富文本模板后置 |
| 日常 AI 优化 | 官网＋九类既有UI动作 | Notes旁动作/要求/流式候选/编辑候选/替换或插入，取消与会话保护 | **当前核心**。真实当前选区、候选不自动写入、切换拒写、原生撤销 |
| AI 与模板设置 | 既有原厂Settings机制；自配模型是用户扩展 | 单一配置窗口，模型/提示词/写作偏好/模板/编辑开关 | **当前核心**。后台只配置；动作使用保存值；秘钥在Keychain |
| 反链＋正文保存 | 官网反链；正文生成是用户扩展 | 来源列表和正文预览就在Notes旁；末尾可点击链接区域、去重/修改保护/不完整合并 | **当前核心**。写入后可在Notes独立使用；更新由用户主动触发 |
| 原生链接/基础Markdown复制 | 官网更多功能 | 现有复制路径保留；Markdown附件只有占位 | **保留现有小工具**。不声称已经实现Obsidian完整导出 |
| Notes 原文搜索 | 官网有命令面板搜索 | 独立搜索实现已归档 | **当前不做**。使用Notes原生搜索，不新增全文索引 |
| 跨笔记AI/知识库/MCP包装 | 非当前原厂已证实合同；早期扩展 | 已从构建退出，用户历史资料未删除 | **当前不做**。外部MCP工作流承担 |
| Notes ↔ Obsidian Markdown | 用户提出后延期 | 方案保留，文件资源与内链转换未实现 | **后续阶段**。单篇主动转移，附件/冲突/链接保真另验收 |
| Floating notes/Vim、遥测商业后端 | 官网WIP/静态商业组件 | 未实现 | **当前不做**。无稳定合同或当前写作价值依据 |

旧审计中 Ask AI/Font/Link/Alignment/Checklist/显隐排序、三反引号、slash 别名与 table、模板 slash、错误不伪装空反链等已修复。不能继续把这些列为“功能缺失”；也不能只凭修复代码称其已验收。

## 真正需要补齐的门槛与取舍

| 优先级 | 项目 | 当前依据与处理 |
|---|---|---|
| P0 | AI 的真实输入范围与写回 | [SelectionTransaction](../src/Quillside/Workspace/SelectionTransaction.swift) 读取focused AXTextArea；[InlineAssistantController](../src/Quillside/Features/InlineAssistant/InlineAssistantController.swift) 无选区取body。表格单元格等子编辑器可能不代表整篇。验收正文/表格/标题及对象，必要时拒绝含糊范围或明确称当前编辑内容。验证替换/插入/撤销后实际正文，不把回调成功视为完成 |
| P0 | 就地面板键盘与焦点 | [InlineInteractionGate/NotesInlinePanel](../src/Quillside/Features/InlineAssistant/InlineAssistantController.swift) 有隔离；[SelectionTransaction](../src/Quillside/Workspace/SelectionTransaction.swift) 要求focused元素一致。非激活面板的实际焦点行为、菜单点击和关闭后回到原笔记必须用实机证明 |
| P0 | 正文反链首次写入/更新/撤销 | [BacklinkDocumentController](../src/Quillside/Features/Backlinks/BacklinkDocumentController.swift) 通过RTF局部粘贴、文字和链接回读；[区域规划](../src/Quillside/Features/Backlinks/BacklinkDocument.swift) 有所有权/修改保护。真实Notes保存的链接形态、重复更新、撤销、切换笔记以及生成边排除必须回读验证 |
| P1 | slash/Markdown 输入法安全 | 0.3.1仅在组合状态可确认时接管候选键；未知输入法状态交给系统，可点选菜单。实际中文输入体验仍待验收。 |
| P1 | Markdown触发实机可靠性 | 0.3.1已移除键盘buffer，按实际正文/光标检测；相关回归通过。剩余原生自动转换和实际输入验收。 |
| P1 | Native菜单兼容与格式真实读回 | [NotesMenuExecutor](../src/Quillside/Services/NativeNotesCommand.swift) AXPress成功或已暴露快捷键投递即返回成功，未逐动作证明格式效果。支持英/简/繁路径不等于所有版本/所有菜单可用。逐项真实操作后验证，不支持时给就地反馈 |
| P1 | 反链覆盖完整性 | [ActiveNoteLinkExtractor](../src/Quillside/Services/NotesBacklinksSnapshot.swift) 表格容器计为complex、锁定/无法解码明确跳过；[NotesDBReader](../src/Quillside/Services/NotesDBReader.swift) 用既有容器路径与schema。当前可披露部分覆盖；如承诺任意Notes关系，仍需表格内部链接和多账户/schema样本 |
| P2 | 真实模型协议兼容 | 0.3.1已补多行SSE与限长组帧，四协议合成HTTP服务通过；真实服务商账号与返回形式仍待验证。 |
| 暂非门槛 | 原生AI表格、富文本模板、多任务模型路由 | 文字编辑用纯文本有明确边界。表格摘要只是默认提示词，可删或标注纯文本；原厂原生表格输出未证实。当前无需路由/embedding层 |
| 后续发布 | 自动更新、其他语言、Developer ID/公证/Intel包、公开GitHub release | 尚未提供完整发布体系，属于开源对外分发阶段。当前本机运行与交互验收优先 |

这里的 P0/P1 是验收或代码风险的优先级，并不表示已观测到相应实机故障。发现可复现失败后，才给出修复结论。

## 全部 92 行重新判定

证据列是当前源码与相关测试的入口；测试均以既有0.3.0收据为执行基线。原厂证据等级列逐项区分官网、本地UI、静态线索、上游和早期扩展。**“代码实现”与“实机通过”保持分开。**

### 选区工具条

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:TB-01<br>选择正文后显示近旁浮层（P-WEB/P-UI） | 官网+本地UI | **当前核心，保留完善**<br>代码已接线，实机待验收。AX 选区监听→正文附近非激活 NSPanel；AI/模板面板出现时格式条隐藏。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-02<br>工具条 Ask AI（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。Ask AI 按钮已连接 InlineAssistantController，就地选择动作与预览，不再打开独立工作台。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-03<br>Font/字体大小入口（P-WEB/P-UI） | 官网+本地UI | **当前核心，保留完善**<br>代码已接线，实机待验收。字体菜单含标题/正文/等宽、增减字号及原生字体面板，非自造格式编辑器。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-04<br>Bold（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。粗体动作经当前 Notes 菜单解析并执行；混合选区状态用属性交集。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-05<br>Italic（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。斜体动作经当前 Notes 菜单执行。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-06<br>Underline（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。下划线动作经当前 Notes 菜单执行。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-07<br>Strikethrough（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。删除线动作经当前 Notes 菜单执行。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-08<br>Highlight（P-UI/P-RES 15.5+） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。高亮按钮调用当前可用菜单；不存在/禁用/歧义时显示错误，不盲发快捷键。没有自有颜色面板。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-09<br>Link 添加/编辑（P-UI/P-RES） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。添加/编辑链接菜单已接线；链接设置由 Notes 原生对话框完成。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-10<br>Alignment（P-UI），左/中/右/两端（P-RES） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。左/中/右/两端对齐菜单已接线。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-11<br>Checklist（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。清单按钮已接线，独立于 slash/Markdown 入口。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-12<br>工具条项目显示/隐藏（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。ToolbarSettingsStore 显隐持久化；全部隐藏时不显示浮层。 | [ToolbarConfiguration](../src/Quillside/Features/FloatingBar/ToolbarConfiguration.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-13<br>工具条排序（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>代码已接线，实机待验收。可拖拽/上下移动，保存次序；面板随可见项数和错误反馈调整尺寸。 | [ToolbarConfiguration](../src/Quillside/Features/FloatingBar/ToolbarConfiguration.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-14<br>格式状态随选区更新 | 上游实现/验收维度 | **当前核心，保留完善**<br>代码已接线，实机待验收。属性 runs 交集，非按按钮点击历史推断状态；字体名称/列表前缀仍属启发式。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
| PN:TB-15<br>多屏、全屏、切应用隐藏 | 上游实现/验收维度 | **当前核心，保留完善**<br>代码已接线，实机待验收。窗口跟踪/多屏坐标/切应用隐藏俱在；静态坐标测试不能证明 Spaces/全屏/缩放。 | [FloatingBarView](../src/Quillside/Features/FloatingBar/FloatingBarView.swift), [NativeNotesCommand](../src/Quillside/Services/NativeNotesCommand.swift), [FloatingBarViewModelTests](../tests/FloatingBarViewModelTests.swift)<br>Notes 正文选区→动作→格式读回与撤销；多窗口/输入法/全屏 |
### Markdown输入

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:MD-01<br>`# ` → Title | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-02<br>`## ` → Heading | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-03<br>`### ` → Subheading | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-04<br>`[] ` → Checklist | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-05<br>三反引号 + 空格 → Monostyled | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-06<br>`> ` → Block Quote | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-07<br>`- ` → Dashed List | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-08<br>`* ` → Bulleted List | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-09<br>`1. ` → Numbered List | 官网稳定承诺 | **当前核心，保留完善**<br>代码与上下文回归通过，实机待验。删除键盘buffer检测，空格前后核对实际正文、行首、UTF-16光标及相同编辑器；原生Notes已自行转换时不重复操作。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/MarkdownTriggerService.swift)<br>对应实机验收仍保留。 |
| PN:MD-10<br>已格式化行可转列表（P-WEB） | 官网稳定承诺 | **当前核心，保留完善**<br>代码路径存在，行为待验收。同一路径可请求列表操作，但“已格式化行转列表”尚没有真实标题/引用/等宽行的完整验证。 | [MarkdownTriggerService](../src/Quillside/Services/MarkdownTriggerService.swift), [InlineInputEdit](../src/Quillside/Services/InlineInputEdit.swift), [FeatureCatalogTests](../tests/FeatureCatalogTests.swift)<br>标题、引用、等宽行分别键入 -、*、1.；逐项回读 |
| PN:MD-11<br>Markdown 总开关（P-UI） | 本地UI | **当前核心，保留完善**<br>配置实现。通用设置总开关接入服务，UserDefaults 变化后刷新。 | [MarkdownTriggerService](../src/Quillside/Services/MarkdownTriggerService.swift), [InlineInputEdit](../src/Quillside/Services/InlineInputEdit.swift), [FeatureCatalogTests](../tests/FeatureCatalogTests.swift)<br>切换后立即生效/重启保持 |
| PN:MD-12<br>按触发类别开关（P-STR） | 二进制字符串，UI未证实 | **保留现有能力，不扩展**<br>配置与回归已补齐。快捷键设置现提供9类Markdown触发独立开关；保存到既有偏好，实时更新。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/App/MarkdownTriggerSettingsView.swift)<br>对应实机验收仍保留。 |
### Slash命令

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:SC-01<br>`/title`、`/h1` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-02<br>`/heading`、`/h2` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-03<br>`/subheading`、`/h3` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-04<br>`/body` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-05<br>`/monostyled`、`/code` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-06<br>`/checklist` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-07<br>`/bulletedlist` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-08<br>`/dashedlist` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-09<br>`/numberedlist` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-10<br>`/quote`、`/blockquote` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-11<br>`/table` | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。官网精确别名已在目录中，exact 匹配优先；原生菜单执行，旧审计中的别名缺失已修复。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>实际键入别名→选中→Return/Tab/空格→无残留字符；格式读回 |
| PN:SC-12<br>模板通过 slash 插入（P-WEB/P-STR） | 官网稳定承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。已连接 committed 模板库；自定义 /meeting 等直接插入；/template(s) 打开 Notes 旁模板选择器。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>修改模板后不重启即能用；取消不改正文；重复提交/切换目标保护 |
| PN:SC-13<br>列表上下选择、点击、Esc、Return、Tab | 实现/验收维度 | **当前核心，保留完善**<br>代码已接线，实机待验收。上下选择/点击/Return/Tab/Esc 接线；消费提交键前核对真实 AX token，不把 Return 先送进正文。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [KeyboardMonitorService](../src/Quillside/Services/KeyboardMonitorService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>中文候选态下不得截获候选确认或导航键 |
| PN:SC-14<br>slash 总开关（P-UI） | 本地UI | **当前核心，保留完善**<br>配置实现。通用设置 slash 总开关、停用时关闭菜单。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>即时生效/重启保持 |
| PN:SC-15<br>搜索/正文/IME 的正确触发边界 | 实现/验收维度 | **当前核心，保留完善**<br>边界实现与回归通过，实机待验。根据Notes正文标识/祖先结构区分正文与单元格；读取已提交token；输入法组合状态未知时不吞候选确认键，可点选菜单。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/NotesEditorContext.swift)<br>对应实机验收仍保留。 |
| PN:SC-16<br>顶部字样、空结果、分页定位等显示 | 上游/实现细节，非官网稳定承诺 | **保留现有能力，不扩展**<br>实现基础交互。现有命令分组、无结果显示、选中滚动跟随；原厂视觉细节未证明为合同，按可用性处理。 | [SlashCommandCatalog](../src/Quillside/Features/SlashCommand/SlashCommandCatalog.swift), [SlashCommandService](../src/Quillside/Features/SlashCommand/SlashCommandService.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>菜单不遮挡编辑、长列表可选 |
### 模板

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:TP-01<br>保存重复片段 | 官网模板承诺，具体协议未证实 | **当前核心，保留完善**<br>配置实现，配置界面已检查。设置独立列表/详情可增删改，JSON 原子提交；运行时只使用已保存配置。 | [ContentLibrarySettings](../src/Quillside/App/ContentLibrarySettings.swift), [TemplatePicker](../src/Quillside/Features/SlashCommand/TemplatePicker.swift), [TemplateInsertionTests](../tests/TemplateInsertionTests.swift)<br>重启/损坏设置/保存失败后保持原配置 |
| PN:TP-02<br>slash 里搜索并插入模板 | 官网模板承诺，具体协议未证实 | **当前核心，保留完善**<br>代码实现，实机待验。模板仍在Notes旁选择；改为统一原生粘贴写入纯文本；面板独立持有输入隔离，切换应用关闭。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Features/SlashCommand/TemplatePicker.swift)<br>对应实机验收仍保留。 |
| PN:TP-03<br>ProNotes 模板来源及命名协议 | 官网模板承诺，具体协议未证实 | **不承诺原厂未证实细节**<br>原厂协议未证实。官方模板文档当前仍无法获取（404）；本应用明确使用设置里的独立模板配置，非宣称从 Notes 按原厂命名协议发现。 | [ContentLibrarySettings](../src/Quillside/App/ContentLibrarySettings.swift), [TemplatePicker](../src/Quillside/Features/SlashCommand/TemplatePicker.swift), [TemplateInsertionTests](../tests/TemplateInsertionTests.swift)<br>不为未知命名协议新增复杂依赖 |
| PN:TP-04<br>模板变量 | 扩展/待证实细节 | **保留现有能力，不扩展**<br>已有扩展。{date} 单次替换；不执行脚本/递归替换。原厂变量支持尚未证实。 | [ContentLibrarySettings](../src/Quillside/App/ContentLibrarySettings.swift), [TemplatePicker](../src/Quillside/Features/SlashCommand/TemplatePicker.swift), [TemplateInsertionTests](../tests/TemplateInsertionTests.swift)<br>当前行为够用，不新增脚本/任意字段 |
| PN:TP-05<br>富文本、表格、附件模板 | 扩展/待证实细节 | **后续阶段**<br>纯文本边界保持。模板使用原生粘贴传入纯文本，不承诺富文本/附件模板；该扩展继续后置。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/NotesPasteTransaction.swift)<br>对应实机验收仍保留。 |
### 搜索（退出范围）

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:SR-01<br>Notes 内快捷键搜索 | 官网+本地UI | **当前不做**<br>已从当前构建移出。用 Apple Notes 原生搜索；相关历史源码归档 legacy/retired-features，当前没有独立笔记搜索入口/搜索热键。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不重新建设搜索窗口、索引或后台持续刷新 |
| PN:SR-02<br>系统范围搜索快捷键 | 官网+本地UI | **当前不做**<br>已从当前构建移出。用 Apple Notes 原生搜索；相关历史源码归档 legacy/retired-features，当前没有独立笔记搜索入口/搜索热键。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不重新建设搜索窗口、索引或后台持续刷新 |
| PN:SR-03<br>两个快捷键可自行配置（P-WEB/P-UI） | 官网+本地UI | **当前不做**<br>已从当前构建移出。用 Apple Notes 原生搜索；相关历史源码归档 legacy/retired-features，当前没有独立笔记搜索入口/搜索热键。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不重新建设搜索窗口、索引或后台持续刷新 |
| PN:SR-04<br>键盘友好的命令面板（P-WEB） | 官网+本地UI | **当前不做**<br>已从当前构建移出。用 Apple Notes 原生搜索；相关历史源码归档 legacy/retired-features，当前没有独立笔记搜索入口/搜索热键。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不重新建设搜索窗口、索引或后台持续刷新 |
| PN:SR-05<br>标题、摘要、文件夹搜索 | 上游扩展/未详述检索字段 | **当前不做**<br>已从当前构建移出。用 Apple Notes 原生搜索；相关历史源码归档 legacy/retired-features，当前没有独立笔记搜索入口/搜索热键。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不重新建设搜索窗口、索引或后台持续刷新 |
| PN:SR-06<br>全库完整正文搜索 | 上游扩展/未详述检索字段 | **当前不做**<br>已从当前构建移出。用 Apple Notes 原生搜索；相关历史源码归档 legacy/retired-features，当前没有独立笔记搜索入口/搜索热键。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不重新建设搜索窗口、索引或后台持续刷新 |
| PN:SR-07<br>新建/改名/删除后搜索刷新 | 上游扩展/未详述检索字段 | **当前不做**<br>已从当前构建移出。用 Apple Notes 原生搜索；相关历史源码归档 legacy/retired-features，当前没有独立笔记搜索入口/搜索热键。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不重新建设搜索窗口、索引或后台持续刷新 |
### 反向链接

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:BL-01<br>原生 note link → 反向来源 | 官网反链承诺 | **当前核心，保留完善**<br>代码实现；限定真实样本解析通过。事务内读取笔记+正文链接，按已使用属性 runs/原生链接附件建图；排除孤儿附件/删除项、自链/未知目标及可识别生成区域。 | [BacklinkDocumentController](../src/Quillside/Features/Backlinks/BacklinkDocumentController.swift), [NotesSnapshotReader](../src/Quillside/Services/NotesSnapshotReader.swift), [BacklinksGraphTests](../tests/BacklinksGraphTests.swift)<br>复杂表格容器链接明确不完整；不同账户/schema 实机验收 |
| PN:BL-02<br>展示当前笔记的反链 | 官网反链承诺 | **当前核心，保留完善**<br>代码实现，实机待验。正文反链RTF与AI/模板共用目标验证和原生粘贴事务；成功后核对链接，去重与修改保护保持。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Features/Backlinks/BacklinkDocumentController.swift)<br>对应实机验收仍保留。 |
| PN:BL-03<br>点击来源回到 Notes | 官网反链承诺 | **当前核心，保留完善**<br>代码已接线，实机待验收。来源用 applenotes:note/UUID 打开；正文保存的链接可直接在 Notes 使用，无需外部查看页。 | [BacklinksService](../src/Quillside/Services/BacklinksService.swift), [BacklinkDocument](../src/Quillside/Features/Backlinks/BacklinkDocument.swift), [BacklinksGraphTests](../tests/BacklinksGraphTests.swift)<br>点击来源与正文内链，核对确实跳到目标 |
| PN:BL-04<br>链接新增/移除及时更新 | 实现可靠性验收维度 | **当前核心，保留完善**<br>用户触发更新，不是持续同步。30 秒缓存+手动刷新+写入失效重建；同一事务快照；完整覆盖可移除旧来源，不完整仅合并保留旧来源。 | [BacklinksService](../src/Quillside/Services/BacklinksService.swift), [BacklinkDocument](../src/Quillside/Features/Backlinks/BacklinkDocument.swift), [BacklinksGraphTests](../tests/BacklinksGraphTests.swift)<br>链接增删/移动删除→刷新→正文更新；跨设备修改与原生撤销 |
| PN:BL-05<br>查询失败可区分真正无反链 | 实现可靠性验收维度 | **当前核心，保留完善**<br>错误/不完整状态已实现。loading/failed/targetMissing/ready 与 coverage 分开；读失败不伪装为空反链；未解密/腐败/表格容器显示覆盖不足。 | [BacklinksService](../src/Quillside/Services/BacklinksService.swift), [BacklinkDocument](../src/Quillside/Features/Backlinks/BacklinkDocument.swift), [BacklinksGraphTests](../tests/BacklinksGraphTests.swift)<br>真实拒绝权限、SQL不兼容、部分覆盖提示与重试 |
### 复制与Markdown交换

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:EX-01<br>复制整篇 Markdown | 官网更多功能 | **保留现有能力，不扩展**<br>已有基础复制。已有 HTML→Markdown→剪贴板，不是 Vault 文件导出；不扩展为本轮核心。 | [NoteActionsService](../src/Quillside/Features/NoteActions/NoteActionsService.swift), [NoteActionsTests](../tests/NoteActionsTests.swift)<br>保留已存在入口，不宣称导入导出已完成 |
| PN:EX-02<br>标题、粗斜体、下划线、删除线、链接、引用、列表、代码 | 转换保真/操作验收维度 | **后续阶段**<br>已有基础转换，完整互通延期。处理标准 HTML 标签，合成样本测试通过；原生 style-only、所有链接格式与富文本保真未穷尽。 | [NoteActionsService](../src/Quillside/Features/NoteActions/NoteActionsService.swift), [NoteActionsTests](../tests/NoteActionsTests.swift)<br>后续 Obsidian 转换验收 |
| PN:EX-03<br>清单/表格 | 转换保真/操作验收维度 | **后续阶段**<br>已有合成转换，实机保真未证实。合成 checklist/table 标签测试不能证明 AppleScript 原生 HTML 同样；跨应用转换延期。 | [NoteActionsService](../src/Quillside/Features/NoteActions/NoteActionsService.swift), [NoteActionsTests](../tests/NoteActionsTests.swift)<br>真实 Notes 清单/表格样本逐项核对 |
| PN:EX-04<br>附件/图片导出 | 转换保真/操作验收维度 | **后续阶段**<br>未实现附件转移。目前输出图片/附件占位文字，未复制资源/修复链接；不能把占位当完整导出。 | [NoteActionsService](../src/Quillside/Features/NoteActions/NoteActionsService.swift), [NoteActionsTests](../tests/NoteActionsTests.swift)<br>后续导入导出阶段处理资源和目标冲突 |
| PN:EX-05<br>复制 deeplink | 官网更多功能 | **保留现有能力，不扩展**<br>已有代码与测试。复制原生笔记链接为 string/URL，不创建公开分享链接。 | [NoteActionsService](../src/Quillside/Features/NoteActions/NoteActionsService.swift), [NoteActionsTests](../tests/NoteActionsTests.swift)<br>实际链接回到源笔记 |
| PN:EX-06<br>markdown/链接/反链快捷入口 | 转换保真/操作验收维度 | **保留现有能力，不扩展**<br>现有 Notes 内入口。动作条、菜单和 Notes 前台热键；不是全局搜索热键，快捷键目前固定。 | [NoteActionsService](../src/Quillside/Features/NoteActions/NoteActionsService.swift), [NoteActionsTests](../tests/NoteActionsTests.swift)<br>验证多入口都指向同一当前笔记；自定义热键暂非必需 |
### AI编辑

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:AI-01<br>续写、润色、纠错、摘要/列表摘要/表格摘要、变长、变短、解释（P-UI） | 官网+本地UI | **当前核心，保留完善**<br>预置动作已接线，实机闭环待验收。续写/润色/纠错/摘要/列表摘要/表格摘要/缩短/展开/解释，以及翻译/自定义/当前内容提问；可删改配置。表格摘要目前产出纯文本 Markdown。 | [InlineAssistantModel](../src/Quillside/Features/InlineAssistant/InlineAssistantModel.swift), [SelectionTransaction](../src/Quillside/Workspace/SelectionTransaction.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>优先保留高频润色/纠错/续写/摘要/长短/翻译/自定义；表格/解释可按需删除 |
| PN:AI-02<br>自定义动作与 `{text}`（P-UI） | 官网+本地UI | **当前核心，保留完善**<br>配置与渲染实现。提示词 CRUD、{text}/{instruction}/{language} 单次白名单替换，文本里的变量不递归执行。 | [InlineAssistantModel](../src/Quillside/Features/InlineAssistant/InlineAssistantModel.swift), [SelectionTransaction](../src/Quillside/Workspace/SelectionTransaction.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>已保存动作在 Notes 面板可选，未保存修改不影响请求 |
| PN:AI-03<br>可编辑系统提示词和模型（P-UI） | 官网+本地UI | **当前核心，保留完善**<br>统一设置实现并实机检查。模型连接、系统提示词、写作偏好和动作分段；不再后台生成笔记。 | [InlineAssistantModel](../src/Quillside/Features/InlineAssistant/InlineAssistantModel.swift), [SelectionTransaction](../src/Quillside/Workspace/SelectionTransaction.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>真实模型连接配置/验证；设置不包含日常写作操作 |
| PN:AI-04<br>对选区或整篇笔记工作（P-UI） | 官网+本地UI | **当前核心，保留完善**<br>输入范围保护实现，实机待验。无选区时仅接受已识别正文；表格单元格必须明确选中文字，未知编辑器拒绝，不再将任意AXTextArea称为整篇。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/NotesEditorContext.swift)<br>对应实机验收仍保留。 |
| PN:AI-05<br>原生贴近选区的 AI 体验 | 官网+本地UI | **当前核心，保留完善**<br>代码已接线，原生视图渲染通过。非激活面板贴近选区，动作→自由要求→流式候选→可改候选→替换/插入；关闭返回 Notes。独立工作台已归档。 | [InlineAssistantModel](../src/Quillside/Features/InlineAssistant/InlineAssistantModel.swift), [SelectionTransaction](../src/Quillside/Workspace/SelectionTransaction.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>完整真实 Notes 操作不跳后台、不误吞面板输入、不卡焦点 |
| PN:AI-06<br>流式预览、取消、完整结束校验 | 扩展/输出可靠性验收维度 | **当前核心，保留完善**<br>合成HTTP与会话回归通过。增加按字节限长组帧：UTF-8、BOM、CR/LF、注释和多行data；EOF不伪造SSE结束；四协议实际localhost服务通过。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/AI/ModelStreamFramer.swift)<br>对应实机验收仍保留。 |
| PN:AI-07<br>结果替换/插入、切换笔记拒绝写入 | 扩展/输出可靠性验收维度 | **当前核心，保留完善**<br>原生粘贴事务实现，实机待验。校验原目标、范围和正文后执行一次Notes粘贴，读回正文/身份；保留可恢复剪贴板；不自动重试；拒绝半个emoji与原生对象替换。 | [0.3.1实现](CORE-IMPLEMENTATION-0.3.1.md)、[源码](../src/Quillside/Services/NotesPasteTransaction.swift)<br>对应实机验收仍保留。 |
| PN:AI-08<br>表格摘要产生原生 Notes 表格 | 扩展/输出可靠性验收维度 | **当前不做**<br>未实现，当前不作为必需项。Markdown表格文本不会自动成为 Notes 原生表格；原厂端到端亦未证明。日常文字优化不要求自动生成原生表格。 | [InlineAssistantModel](../src/Quillside/Features/InlineAssistant/InlineAssistantModel.swift), [SelectionTransaction](../src/Quillside/Workspace/SelectionTransaction.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>默认表格摘要应明示纯文本或作为可删除动作，不虚称原生表格 |
### AI连接配置

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:CF-01<br>服务商/API URL/API Key 自配 | 用户早期扩展要求，非ProNotes已证实功能 | **当前核心，保留完善**<br>配置与Keychain机制实现。四协议、多连接，自填地址/model/key/output预算；远程 HTTPS、本地HTTP；凭证原子切换，密钥不进JSON。 | [AIConfiguration](../src/Quillside/AI/AIConfiguration.swift), [ConnectionsView](../src/Quillside/App/ConnectionsView.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>至少一个实际模型连接与 Notes 生成闭环 |
| PN:CF-02<br>多用途独立模型 | 用户早期扩展要求，非ProNotes已证实功能 | **当前不做**<br>现有多连接，但不建任务路由。可在面板选模型与设置默认连接；无 embedding/摘要/写作多用途自动路由，范围收敛后无需该复杂层。 | [AIConfiguration](../src/Quillside/AI/AIConfiguration.swift), [ConnectionsView](../src/Quillside/App/ConnectionsView.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>不把原研究提出的多用途路由当当前缺项 |
| PN:CF-03<br>连接测试/配置导入导出 | 用户早期扩展要求，非ProNotes已证实功能 | **保留现有能力，不扩展**<br>已实现合成文本测试与配置备份。测试不发送真实笔记；JSON导入迁移引用/不带Keychain密钥，保存失败保留原状态。此备份不是笔记Markdown导入导出。 | [AIConfiguration](../src/Quillside/AI/AIConfiguration.swift), [ConnectionsView](../src/Quillside/App/ConnectionsView.swift), [AIEditingTests](../tests/AIEditingTests.swift)<br>真实连接响应；文件损坏恢复与配置持久性 |
### 知识库（退出范围）

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:KB-01<br>主动选择 Notes/MD/TXT/PDF | 用户早期扩展要求，非ProNotes已证实功能 | **当前不做**<br>已从当前构建移出。用户已明确取消独立知识库、摄入/集合/检索/向量；跨笔记AI搜索由外部MCP承担，App不包装MCP。历史数据不自动删除。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不再列为缺项，不重新实现 |
| PN:KB-02<br>本地检索和来源 | 用户早期扩展要求，非ProNotes已证实功能 | **当前不做**<br>已从当前构建移出。用户已明确取消独立知识库、摄入/集合/检索/向量；跨笔记AI搜索由外部MCP承担，App不包装MCP。历史数据不自动删除。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不再列为缺项，不重新实现 |
| PN:KB-03<br>集合管理 | 用户早期扩展要求，非ProNotes已证实功能 | **当前不做**<br>已从当前构建移出。用户已明确取消独立知识库、摄入/集合/检索/向量；跨笔记AI搜索由外部MCP承担，App不包装MCP。历史数据不自动删除。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不再列为缺项，不重新实现 |
| PN:KB-04<br>来源变更/删除/锁定清理 | 用户早期扩展要求，非ProNotes已证实功能 | **当前不做**<br>已从当前构建移出。用户已明确取消独立知识库、摄入/集合/检索/向量；跨笔记AI搜索由外部MCP承担，App不包装MCP。历史数据不自动删除。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不再列为缺项，不重新实现 |
| PN:KB-05<br>embedding 模型与向量召回 | 用户早期扩展要求，非ProNotes已证实功能 | **当前不做**<br>已从当前构建移出。用户已明确取消独立知识库、摄入/集合/检索/向量；跨笔记AI搜索由外部MCP承担，App不包装MCP。历史数据不自动删除。 | [当前范围](CURRENT-FEATURES.md)，[范围回归](../tests/EditingScopeTests.swift)<br>不再列为缺项，不重新实现 |
### 系统与分发

| ID／要求 | 原厂证据等级 | 当前处理决定与代码状态 | 证据／剩余门槛 |
|---|---|---|---|
| PN:SYS-01<br>登录启动（P-UI） | 本地UI/静态线索 | **保留现有能力，不扩展**<br>已实现，登录行为待实测。SMAppService 注册/取消；ad-hoc 本机实际重登录尚未验收。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>仅按需启动，不影响Notes操作 |
| PN:SYS-02<br>菜单栏显示开关（P-UI） | 本地UI/静态线索 | **当前不做**<br>未实现隐藏开关，当前保留菜单栏。MenuBarExtra 常驻，提供设置/退出/权限入口；若隐藏需另做可靠唤起，不为对标强行加。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>当前不把未实现隐藏开关列为核心缺项 |
| PN:SYS-03<br>工具条/slash/Markdown 开关（P-UI） | 本地UI/静态线索 | **当前核心，保留完善**<br>总开关已接线。工具条/slash/Markdown 总开关可配置，与0.1历史缺项不同。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>即时停用与重启保持 |
| PN:SYS-04<br>语言选择（P-UI） | 本地UI/静态线索 | **后续阶段**<br>当前主要中文界面。没有语言选择/String Catalog；菜单匹配支持英/简中/繁中，不等于整App多语。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>公开发布到其他语言用户时再完善 |
| PN:SYS-05<br>权限/数据库连接诊断 | 本地UI/静态线索 | **当前核心，保留完善**<br>权限诊断实现。辅助功能/自动化/只读数据库访问分开；UI状态不是完整业务成功，使用合成笔记回读验收。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>当前权限生效检查，不重复向用户请求已授权许可 |
| PN:SYS-06<br>自动更新（P-UI/Sparkle 静态线索） | 本地UI/静态线索 | **后续阶段**<br>未实现发布更新体系。本机ad-hoc构建，没有签名feed/自动更新、公证、Intel发布包。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>对外开源发布阶段设置稳定渠道、签名和公证 |
| PN:SYS-07<br>匿名崩溃报告（P-UI/Sentry 静态线索） | 本地UI/静态线索 | **当前不做**<br>有意不实现远程遥测。保留本地日志，无账户/远程崩溃上报；无需复制商业后端/订阅体系。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>如有诊断需要先采用用户主动导出 |
| PN:SYS-08<br>原生栈 | 用户技术要求，非单独官网功能 | **当前核心，保留完善**<br>原生栈已实现。Swift/SwiftUI/AppKit、AX/CGEvent/AppleScript、SQLite/Security；没有Electron。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>旧版macOS和多语言兼容需要独立验收 |
| PN:SYS-09<br>可维护的开源代码/许可 | 用户开源要求 | **当前核心，保留完善**<br>本地源码与许可齐备，公开发布待办。保留NotesPlus MIT与NotesBridge声明；本地源码包存在。未证明已创建公开GitHub仓库/release。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>对外发布时核对许可、构建复现、安装与卸载 |
| PN:SYS-10<br>Floating notes、Vim（P-WEB 标 WIP） | 官网WIP | **当前不做**<br>未实现；原厂也是WIP。官网明示Floating notes/Vim为WIP；不是稳定功能复制合同，当前编辑增强定位也不需要。 | [OpenNotesApp](../src/Quillside/App/OpenNotesApp.swift), [FeatureParityRegressionTests](../tests/FeatureParityRegressionTests.swift)<br>不因官网列名加入本轮范围 |

## 继续验收的顺序

先完成已授权的辅助功能刷新与实际Notes选区操作：格式条和基础格式 → AI本地合成服务就地生成/替换/插入/取消/切换拒写/撤销 → slash与模板 → 正文反链首次写入/重复更新/修改保护/链接点击/撤销。反链单独检查完全磁盘访问状态。随后至少一个用户实际模型连接、中文输入法、多个Notes窗口/全屏与复杂笔记边界。

发布前以当前范围逐项填写真实证据，不按92行数量计算完成率。当前已取消的功能不重做，延期功能不阻止当前编辑增强的验收。

GitHub已有实现的固定版本和逐文件分析保留在 [NotesPlus历史对照](PRONOTES-NOTESPLUS-COMPARISON.md)、[NotesBridge全量对照](NOTESBRIDGE-COMPARISON.md)；当前产品取舍以本文件与 [CURRENT-FEATURES](CURRENT-FEATURES.md) 为准。
