# Quillside 0.6.7 统一界面主题

2026-10-13，构建2。用户要求以Slash为基准，统一斜杠菜单、原文批注、整体优化三个弹窗，并补充设置控制面板也使用同一套macOS风格。

## 统一内容

三种弹窗共用FloatingSurface：10pt圆角、中性浮层、0.5pt边框和同一套阴影，去掉批注独立的material背景及整体优化偏黄的另一套外观。NSPanel不再叠加系统阴影。

EditorPanelHeader统一38pt标题栏、12pt标题字、12pt横向内边距和Esc关闭提示；正文12pt、辅助说明10pt、输入区域6pt圆角与统一边框。批注窗宽320pt，与Slash一致；整体优化保留370pt以容纳预览及写回操作。

设置窗口使用原生NavigationSplitView和sidebar List，保留可隐藏、可调整的侧栏以及系统标题栏、分组表单和控件。详情区沿用相同标题样式与中性背景。八个原有设置页、模型/Agent/Skill分区和数据存储保持不变。

所有界面强调色统一使用NSColor.controlAccentColor，避免原生侧栏使用系统颜色、弹窗强制金色。支持系统浅色、深色外观；浮层遵循减少透明度。品牌Logo本身不改色。

采用系统原生侧栏与材料，保留macOS14兼容，没有把正文内容全部覆盖成玻璃。参考[Apple侧栏指南](https://developer.apple.com/design/human-interface-guidelines/sidebars)与[材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)的导航/内容分层原则。

## 验证

- 257项测试中254项执行通过，3项旧截图/实机数据库环境用例跳过。新增的是可选的实际视图渲染夹具，没有用颜色常量断言代替目视验收。
- 用真实SwiftUI视图渲染并检查三个弹窗的浅色、深色、减少透明度、长引用和收起/展开状态；最后调整系统强调色后又运行并检查同一渲染夹具。
- 设置原生侧栏的离屏渲染不完整，因此未用离屏设置截图冒充完整验收；安装后实际逐页切换通用、编辑工具条、模型连接、Agent、Skill、模板、快捷键和关于，配置内容与编辑控件可见。
- 在专用合成笔记中实机打开Slash，截图确认新标题栏及系统强调色；Esc关闭后撤销临时输入，读回HTML与此前完全相同。
- 在既有验收笔记中打开批注气泡、整体意见与候选预览，实际看到相同浮层主题；5条批注、原句/意见与已有候选完整恢复，插入后方和应用到原文控件可见且可用。
- 本轮验证界面与存量草稿兼容，不重新调用模型或写回候选；AI生成和原生写回/撤销的实测仍见0.6.5记录。未读取模型密钥。
- release/debug构建、严格签名及随包MIT许可检查通过；已安装/启动0.6.7构建2。

## 证据

本地目录：build/unified-theme-0.6.7/。

- previews/panels-light.png、panels-dark.png、panels-opaque.png：实际组件并排渲染。
- slash-live.jpg、comment-live.jpg、composer-live.jpg、preview-live.jpg：原生Notes中的弹窗截图。
- settings-live.jpg、settings-Agent-live.jpg等：实际设置窗口截图。
- regression.log、previews-final.log、build-release-final.log：检查日志。
- Quillside-0.6.6-backup.app：修改前安装备份。

上版菜单栏动画已获得用户目视确认“能看到动画，菜单正常”。本版保留该动画。
