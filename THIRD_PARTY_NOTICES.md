# Quillside 上游与许可证

Quillside 为独立的本地开发版本，与 ProNotes、Apple 和下列项目的作者没有隶属关系。

## NotesPlus

- Repository: https://github.com/sunhuaian2026/NotesPlus
- Commit: `518886fc42118ec913d44694d69549f38e3d9e4c`
- License: MIT，原始文本保存在 licenses/NotesPlus-MIT.txt；根目录 LICENSE 同时保留其版权声明。
- 使用范围：原生菜单栏、Accessibility/窗口跟踪、格式栏、Markdown/slash 基础、Notes 只读数据库、反链、Markdown 转换、权限与基础测试。
- 本地修改：独立命名与 bundle ID；AI 入口与原文批注；角色 Prompt、Skill 与模型配置；快捷键；局部触发删除保护；测试迁移为 Swift Testing。早期独立工作台与知识索引已经归档，不进入当前 App。

## NotesBridge

- Repository: https://github.com/peizh/NotesBridge
- Commit: `91bccb0d34205d9813508de8146ea07540ac161f`
- License: MIT，原文保存在 licenses/NotesBridge-MIT.txt。
- 使用范围：从 `AppleNotesNoteProtoDecoder.swift` 选取正文与属性解码结构、Protobuf 读取器，整理为 `src/Quillside/Services/NotesBridgeDecoder.swift`。
- 工具条布局规范化、排序与菜单路由的设计参考了该提交的 InlineToolbarItemSetting、InlineToolbarCustomizationSheet 和 FormattingCommandExecutor；本地采用独立的设置模型与原生 AX 菜单执行器。
- 本地修改：复用有解压大小限制的 gzip 路径；限制长度与 varint 溢出；不包含其 Obsidian 同步产品、Sparkle 和全部附件渲染依赖。

## 研究参考

Notechat 的本地检索与来源展示、NotesOllama 的选区 AI、apple-notes-mcp 的只读数据与写入边界帮助形成设计；本版本未复制这些项目的代码。ProNotes 安装包、图标和原厂提示词未纳入此 App。

系统使用 Swift、SwiftUI、AppKit、Foundation、ApplicationServices、Security、Carbon、NaturalLanguage、PDFKit、SQLite3 和 zlib。没有 Electron、WebView 产品界面、云端账号系统或遥测 SDK。

## Yams

- https://github.com/jpsim/Yams ，固定 6.0.2；MIT，完整许可在 licenses/Yams-MIT.txt。用于标准 YAML Skill 元数据解析。

## LibYAML（Yams 的间接依赖）

- Yams 6.0.2 在 Sources/CYaml 中包含 LibYAML，并在自身 Package.swift 中构建链接；其 README 明确 Yams 与 LibYAML 均为 MIT。
- 上游：https://github.com/yaml/libyaml 。Yams 变更记录引用的上游 acd6f6f 版本许可文本保存在 licenses/LibYAML-MIT.txt；这里不将该许可来源误报为全部 CYaml 文件的精确版本。
- Copyright (c) 2017-2020 Ingy döt Net；Copyright (c) 2006-2016 Kirill Simonov。
- 随 App 分发时同时附带 LibYAML 与 Yams 各自的许可，不能只附带 Swift 包外层许可证。

## Humanizer-zh

- https://github.com/op7418/Humanizer-zh ，固定提交 f4518a8eab97b8bfebc66a89d34320a89bef6930。
- 作为可选写作 Skill 随应用提供，默认未启用；原始 SKILL.md、MIT LICENSE 和 SOURCE.json 位于 resources/Skills/humanizer-zh。
- Copyright (c) 2026 歸藏；原始来源和参考说明保留在技能文件中。

## 分发核对

组件、固定来源和许可文件 SHA-256 记录在 [licenses/manifest.json](licenses/manifest.json)。所有许可文本随源码、应用 Licenses 目录和官网许可目录分发。应用品牌说明与上游版权声明分别处理，不能因为独立命名删除原始归属。

Apple 的系统框架、系统 SQLite3 与 zlib 由 macOS 提供，本项目没有将其系统二进制重新打包进应用。以后如改成自行编译或随包分发，需要重新审查对应许可。
# Pi runtime (0.7.0)

Quillside's application source remains MIT. The embedded Pi 1.2.0 engine and Node.js runtime include dependencies under MIT, Apache-2.0, BSD, ISC and Unlicense terms. Their exact versions, provenance, license texts and hashes are recorded in `licenses/pi-runtime/manifest.json` and the adjacent notice files, and distributed in the app's `Contents/Resources/Licenses/PiRuntime` directory. The inventory follows packages actually included by the bundled worker; the npm lockfile additionally records development/install dependencies. Node's notice includes its bundled third-party components.

