# AppleNotesPro 写作 Skills 与 Agent 内核调研

核验日期：2026-10-09（Asia/Shanghai）。仅阅读官方规范、仓库 README／SKILL.md／LICENSE 与 GitHub API；没有安装技能或执行第三方脚本。本文件的“源码核验”指第三方仓库文件核验，不表示功能已在 AppleNotesPro 实现或实机验收。当前应用仍为一次性 `generate(system,user)` 是主任务提供的现状，本子任务没有独立审计应用源码。

## 结论

可以以原生 Swift 构建支持 Agent Skills 的写作内核，尤其适合接入 humanizer 类纯指令技能。标准定义的是技能文件格式与宿主加载契约，宿主仍需提供会话、工具、状态和执行循环。`SKILL.md` 加载、连续对话、十处批注统一修订是三个相互关联但独立的能力，应分别实现与验证。

产品建议：保留在 Apple Notes 中选区、添加批注、预览和应用的流程；设置页配置模型、启用技能和选定技能目录。写作会话只服务当前文稿，无需独立知识库、全文搜索或跨笔记索引。

## 官方规范：已核验事实

技能最低结构是目录中的 `SKILL.md`，包含 YAML frontmatter 和 Markdown 指令；可带 `references/`、`assets/`、`scripts/`。必填字段是 `name`、`description`，可选字段有 `license`、`compatibility`、`metadata` 与实验性的 `allowed-tools`。`allowed-tools` 官方定义为空格分隔字符串，宿主支持程度可以不同。技能通过元数据、完整指令、所需资源三个层次加载。[Agent Skills specification](https://agentskills.io/specification)

官方集成指南允许程序注入技能内容或提供专门的 `activate_skill` 工具；没有要求 Node／Python Agent 框架。用户可以显式启用，模型也可以依据技能目录选择。跨客户端 `~/.agents/skills/` 是常用目录约定，并非格式强制要求。会话应去重激活、保持技能指令，资源按需读取。[官方宿主集成指南](https://agentskills.io/client-implementation/adding-skills-support)

技能可能要求执行命令或下载依赖；即使没有 `scripts/`，正文也可能直接要求 `npx`／`uvx` 等命令。运行这些技能需要宿主另外提供执行能力和依赖，不能以“能够读取 Markdown”宣称可执行所有技能。[官方脚本说明](https://agentskills.io/skill-creation/using-scripts)

## humanizer：源码与许可核验

| 项目 | 本次 GitHub API 快照 | 运行时与适配结论 |
| --- | --- | --- |
| [blader/humanizer](https://github.com/blader/humanizer) | 未归档；55,000 stars；默认 main；提交 `225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8`，2026-09-28 | 英文为主；Markdown 指令；适合加载，无需执行项目维护脚本 |
| [op7418/Humanizer-zh](https://github.com/op7418/Humanizer-zh) | 未归档；19,186 stars；默认 main；提交 `f4518a8eab97b8bfebc66a89d34320a89bef6930`，2026-09-23 | 中文候选；单文件编辑规则；更适合当前用户的中文文稿 |

热度是检索时快照，会变化；不代表效果得到独立验证。API 原始事实来源：[blader 仓库](https://api.github.com/repos/blader/humanizer)、[blader 提交](https://api.github.com/repos/blader/humanizer/commits/main)、[中文仓库](https://api.github.com/repos/op7418/Humanizer-zh)、[中文提交](https://api.github.com/repos/op7418/Humanizer-zh/commits/main)。

### 英文版本

README 宣称支持 Claude Code、Codex 和其他兼容技能宿主，提供作者样稿匹配；明确以人类阅读体验为目标，不保证 AI 检测器结果。[README 固定提交](https://github.com/blader/humanizer/blob/225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8/README.md)

`SKILL.md` 元数据版本 3.1.0；编辑流程是通读识别、重写、核对事实与剩余表达问题、最终成稿。支持嵌入模式只返回最终文本。英文标点和连接号等部分规则不宜机械套用中文。库中 `scripts/validate-package.py` 用于包验证，读取的技能指令不要求执行它；运行时规则主要在 Markdown 文件。[SKILL.md 固定提交](https://github.com/blader/humanizer/blob/225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8/SKILL.md)，[固定目录树](https://api.github.com/repos/blader/humanizer/git/trees/225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8?recursive=1)

MIT 许可证，版权 2025 Siqi Chen。复制或改编实质内容时必须保留相应版权及许可声明；可以放第三方许可文件而非日常编辑界面。[LICENSE 固定提交](https://github.com/blader/humanizer/blob/225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8/LICENSE)

### 中文版本

中文规则强调保留事实、信息独立性、否定、时间、条件、归因和确定程度，不新增经历或数据；文体与作者声音优先，31 类模式只是上下文检查线索，正常词语和句式不机械删除。默认粘贴文本输出最终稿，修改文件需明确请求。适合“去套话、保留意思”的 Notes 工作流；它不是 AI 文本来源检测器。[SKILL.md 固定提交](https://github.com/op7418/Humanizer-zh/blob/f4518a8eab97b8bfebc66a89d34320a89bef6930/SKILL.md)

实际文件 `allowed-tools` 是 YAML 数组 `Read`／`Write`／`Edit`／`AskUserQuestion`，与官方实验字段的字符串形式不同。兼容加载器应容忍常见表示，并将工具名称映射到宿主支持能力；该声明不能自行授予文件写权限。仓库根目录无运行时 scripts；README 描述这是 Agent 编辑指导，无法证明作者身份或保证过检测。[README](https://github.com/op7418/Humanizer-zh/blob/f4518a8eab97b8bfebc66a89d34320a89bef6930/README.md)，[文件列表](https://api.github.com/repos/op7418/Humanizer-zh/contents)

MIT 许可证，版权 2026 歸藏。其文件明确记录英文上游与其他参考来源；发行适配版时保留中文项目许可和已复制上游的相应声明。[LICENSE 固定提交](https://github.com/op7418/Humanizer-zh/blob/f4518a8eab97b8bfebc66a89d34320a89bef6930/LICENSE)

## 兼容能力应分层声明

以下分层是本项目工程建议，不是标准规定的产品等级。

| 层次 | 宿主提供什么 | 可支持的技能 | 必须说明的边界 |
| --- | --- | --- | --- |
| 指令 | 解析 frontmatter、启用 SKILL.md、保持会话 | humanizer、中文润色、结构编辑 | 不能假装已执行不存在的工具 |
| 资源 | 技能目录内只读 references／文本 assets；相对路径解析 | 风格手册、多文件编辑指南 | 二进制／超大文件说明不支持；目录外访问不隐式允许 |
| 执行 | 工具路由、受控进程、依赖、超时、输出与操作权限 | 调脚本或网络工具的技能 | 需要专门执行运行时，首版不应声称全兼容 |

目录里存在维护脚本并不自动意味着运行时必须执行。反过来，目录里没有脚本也不等于技能纯指令，应看 `compatibility`、工具声明和正文要求。

## 原生 Swift 有界加载器：实现建议

1. 默认应用专属 `Application Support/AppleNotesPro/Skills`，设置支持用户选择目录；是否扫描共享 `~/.agents/skills` 由用户开启，避免把大量无关开发技能塞进写作菜单。缓存元数据，只有编辑会话启动或目录改变时扫描，不挂到每次 Notes 按键／选区监听。
2. 用真正 YAML 解析器处理字符串、数组、块标量和 metadata；不要用“每行冒号分割”冒充 YAML。原生 Swift [Yams](https://github.com/jpsim/Yams) 提供 YAML 支持，MIT [许可证](https://github.com/jpsim/Yams/blob/main/LICENSE)；使用时遵循项目依赖和许可规范。若零依赖仅实现子集，应在 UI 明确提示不支持字段，而不是静默读错。
3. 将 `SkillDescriptor`（身份、描述、根目录、来源、许可、兼容诊断）和 `SkillContent` 分离。仅已启用写作技能进入目录；加载完整指令以用户选择或 Agent 的明确工具请求触发。每个会话固定内容哈希，目录更新从下次会话生效，避免生成中途换规则。
4. 建议首版 128 个技能、单文件 128 KiB、资源合计 512 KiB、可控递归深度；UTF-8 文本读取，真实路径必须仍在技能根目录内，拒绝 `../` 和符号链接逃逸。具体值是建议，需根据样例调节；防护属于加载器契约而非用户额外操作。
5. 初始工具只需 `activate_skill`、`read_skill_resource`、`ask_clarification`、`propose_revision`。模型不能直接写 Notes；现有预览、用户应用、文稿版本检查和撤销负责落笔。对不支持的宿主专属工具名称给兼容诊断，不静默忽略必需动作。
6. Apple 文档给出：采用 App Sandbox 的 macOS 应用可用 NSOpenPanel 选择目录，使用只读 security-scoped bookmark 持久访问，并在解析后启动／停止受控访问。[Apple 沙盒文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?language=objc)。这仅在采用沙盒时适用，不据此宣称当前 AppleNotesPro 已沙盒化。

## 对“十处划线评论后整体优化”的建议

这属于文稿编辑会话。建议每条意见保存文稿身份、正文版本、UTF-16 范围、原文引用、前后文锚点、用户评论和状态。用户在 Notes 中依次选区并添加评论，浮层积累意见而不立即改正文；“整体优化”把同一份正文和全部意见交给一个会话，技能参与编辑规则，先提出整体修订，再核对十条意见、人物／术语／时间／因果与段落衔接，最后交付一份可预览的稿件。

这可以是有界的 `分析 → 修订 → 核对 → 成稿` 多步骤 Agent，也可允许用户追问继续修订。避免逐段独立生成再拼接，因为冲突意见、交叉引用和前后语气需要共同上下文。此项是设计推断，不能据本次资料调研保证模型每次逻辑自洽；需要包含重复文本、重叠评论、冲突要求、编辑后锚点失效、取消和撤销的验收样例。

“划线”显示不应默认为把删除线或高亮永久写入 Notes 正文，否则用户正文、格式、同步与导出都会混入审阅标记。建议首版选区后加入锚定批注，并在紧凑审阅浮层提供定位与编号。直接在 Notes 编辑器坐标上绘制跨行注释需要另行验证可访问性范围矩形、滚动及换行；本报告没有证明能获得可靠的原生评论 API。

## 验收边界

至少分别验证：正确解析真实 humanizer 文件、加载到模型上下文、技能规则确实影响输出、引用资源不越界、同一会话保留技能、十条意见都被处理、原文改动时停止写回、一次 Notes 撤销恢复。格式解析通过与静态示例通过都不能代替真实 Notes 编辑验证。
