# 工具条对齐实现与验收边界

日期：2026-10-08。对应 ProNotes 对照中的 TB-01 至 TB-15，以及 NotesBridge 的 A06、A15、A17。完整长期目标仍在进行；这里记录 0.1.2 的新增实现，实机验收仍待进行。

## 控件与真实执行路径

默认工具条按已观察到的 ProNotes 十项排列：AI、字体、粗体、斜体、下划线、删除线、高亮、链接、对齐、清单。原有项目符号、短划线、编号、引用、等宽以及表格作为可选项目保留。

| 控件 | 当前行为 | 对应代码 |
|---|---|---|
| AI | 在激活工作台前捕获 Notes 文字，进入现有生成预览流程；不会因点工具条就发模型请求 | FloatingBarViewModel.onAskAI → WorkspaceController.show |
| 字体 | 标题/副标题/正文/等宽，增大/减小字号，Notes 原生字体面板 | FloatingBarView.fontMenu → FormattingService → NativeNotesCommand |
| 链接 | 选择当前可用的 Add Link 或 Edit Link 操作 | NotesMenuMatcher.resolve(.link) |
| 对齐 | 左对齐、居中、右对齐、两端对齐 | NoteAlignment → Notes 原生菜单 |
| 清单 | 原生 Checklist 操作 | FloatingBarViewModel.perform(.checklist) |
| 其他格式 | 保留既有格式能力，统一走当前 Notes 菜单路由 | FormattingService.applyFormat |

不再仅凭固定虚拟键码假设命令存在。执行时先捕获进程、窗口、正文摘要和文字范围，再读取 Notes 菜单，通过英文/简繁中文菜单名称或菜单实际暴露的快捷键识别命令。匹配失败、禁用或歧义时给出反馈。优先执行菜单的 AXPress；只有菜单没有 AXPress 且公开了有效快捷键信息时，才向原 Notes PID 投递该快捷键。

菜单查找有节点数、深度和时间上限，已知语言先缩小到 Format/Edit 菜单。未知语言会尝试实际快捷键匹配；这不等于已经支持所有语言。菜单读取失败不会退回到盲目按默认快捷键。

菜单执行前再次验证窗口、编辑元素、选区和正文摘要，避免扫描期间的内容变化。相同内容的克隆笔记、系统菜单懒加载、特殊键盘布局仍需真实 Notes 样本验证。AX 返回 success 只表示接受操作；没有据此宣称格式读回和撤销成功。

## 显隐、排序与大小

[ToolbarConfiguration.swift](../src/Quillside/Features/FloatingBar/ToolbarConfiguration.swift) 定义 16 个项目和默认可见集合。设置中的工具条页使用 SwiftUI List.onMove，并提供可访问的上移/下移按钮、显隐复选框和恢复默认。

配置按版本编码到 `com.opennotes.toolbar.layout.v1` 的 UserDefaults 数据。规范化保留已知项目的次序和显隐、去掉重复项，补齐新项目。全部隐藏会关闭浮层；工具条按项目数调整宽度，窄屏可横向滚动。错误反馈增加面板高度，不覆盖按钮。

损坏或更高版本的布局不会在普通编辑时被重写；显式恢复默认前保存原数据。AI/模板 JSON 导入导出不包括工具条布局，界面文案已明确这一区别。

## 触发文本失败恢复

Markdown/slash 仍先严格验证正文中的精确触发串。若后续原生格式被拒绝，只有编辑元素、窗口、正文和光标均未发生后续变化时，才恢复本次删除的触发串。不会用全局 Cmd-Z 回滚，也不会重放可能已执行的格式动作。

这条恢复路径的范围和冲突策略有纯函数测试；真正 AX 写入与 Undo 分组仍待实机验收。`/link` 已加入 slash 目录，与 NotesBridge 的对应原生操作对齐。

## 当前验证

- ToolbarConfigurationTests：默认功能集合、显隐/重载、排序/批量移动、未知重复项目、损坏/未来版本、全部隐藏和尺寸约束。
- NativeNotesCommandTests：菜单上下文、中文与省略号、Add/Edit Link 的可用项、禁用命令、歧义、默认快捷键的不同修饰位、缺失快捷键不得输入普通字符、失败不盲目重试、触发串恢复冲突。
- FloatingBarViewModelTests：新控件确实路由到相应服务；AI 走工作台回调；错误反馈不伪装成格式已应用。
- 两项可选 GUI/真实数据库测试仍不能充当已执行证据；Mac 锁屏阻碍实际拖拽、菜单操作、中文输入、多窗口、全屏和撤销验收。

上游研究是设计依据，没有复制 ProNotes 的图标、提示词或本地化资源包。可核验来源与许可证继续保存在 THIRD_PARTY_NOTICES.md 和三个对照报告中。
