<p align="center"><img src="resources/Brand/Quillside-Mark.png" width="112" alt="Quillside"></p>

# Quillside

**留在 Apple Notes，把想法写清楚。**

[English](README.en.md) · [GitHub](https://github.com/Asxing/quillside) · [Website](https://asxing.github.io/quillside/) · [Releases](https://github.com/Asxing/quillside/releases) · [使用指南](docs/user/GETTING-STARTED.md) · [开发构建](docs/development/BUILDING.md) · [发布方式](docs/development/RELEASING.md) · [MIT](LICENSE)

Quillside 是原生 macOS Apple Notes 写作伴侣：在原文中划线批注，把多处意见交给 AI 统一处理，检查候选后写回，必要时使用 Notes 原生撤销。笔记仍由 Apple Notes 管理。

当前版本 **0.7.4，开发者预览**。正式 Developer ID 签名、公证和新环境安装验收尚未完成。可以从源码构建；未公证测试包（如 Release 提供）会明确标注 `UNNOTARIZED`，不能视作正式发行。

## 核心能力

- **在原文旁批注**：选中句子写意见，多处批注保留，再补整体要求一起优化。
- **选区 AI**：润色、纠错、翻译、续写和自定义要求；检查后替换或插入。
- **Agent + Skill**：一份角色 Prompt 搭配 Skills，内置公众号、个人笔记和汇报场景。
- **原生编辑**：Slash 命令、Markdown 快捷格式、可配置工具条与模板。
- **正文反向链接**：查看引用来源，确认后把链接写入笔记，手动触发更新。
- **自选模型**：内嵌 Pi Agent，使用 API Key、兼容服务或提供方支持的订阅登录。服务可用性与额度取决于账户和地区。

SwiftUI/AppKit 原生界面，内嵌 Pi/Node 运行时；完整 App 用户不需要另外安装 Node。当前 App 主要使用中文界面，官网提供简体中文、繁體中文和 English。

## 开始使用

构建目标为 macOS 14+，当前实机覆盖 Apple Silicon、macOS 26.5.2。最低构建版本不代表已实测所有系统、输入法和显示器组合；Intel 包暂不发布。

1. 按[开发指南](docs/development/BUILDING.md)构建并启动，或阅读 Release 对测试包的说明。
2. 根据引导授予 Accessibility、Automation → Notes；反链与原生笔记定位需要 Full Disk Access。
3. 在设置中配置模型连接，选择 Agent 和 Skill。
4. 回到 Notes，选中文字后点击 AI 或使用 `⌥⌘A`；多处修改使用原文批注。
5. 检查候选后再应用，使用 Notes 撤销恢复。

独立知识库、全文搜索、后台同步、MCP/Tools 与完整 Obsidian 文件交换不在当前交付范围。详情见[当前功能](docs/CURRENT-FEATURES.md)。

## 从源码构建

需要 macOS、Swift 6.2+、Python 3.10+、Node.js（版本见`.node-version`）、npm 和 ripgrep。

```sh
npm ci --prefix runtime/pi --ignore-scripts
./scripts/verify-stage1.sh
OPENNOTES_CODE_SIGN_IDENTITY=- ./scripts/bundle-app.sh release
open build/Quillside.app
```

不要覆盖已有正式安装来调试。临时签名更新后可能需要重新授予权限；源码构建不要求购买 Apple Developer 会员。完整说明与故障排查见[构建指南](docs/development/BUILDING.md)。

## 数据与权限

- 笔记正文保留在 Apple Notes；批注、引用原句和候选草稿可能包含正文，保存在本机。
- 新 Pi 连接的 API Key/OAuth 凭据保存在应用独立的本机文件中；旧兼容连接继续使用 macOS Keychain。
- 主动生成时才发送本轮选区/笔记、意见、角色与启用的 Skill，不自动检索其他笔记。
- 停止、切换笔记、休眠或退出会取消本地任务；不能撤回远端已经收到的内容。
- 为升级兼容，数据目录与权限标识保留 `OpenNotes` / `com.opennotes.app`，它们不是产品展示名称。

详情见[数据流和隐私](docs/user/PRIVACY.md)。请使用合成材料报告问题，不提交私人笔记或凭据。

## 开发与协作

[文档导航](docs/README.md) · [架构](docs/development/ARCHITECTURE.md) · [贡献指南](CONTRIBUTING.md) · [安全报告](SECURITY.md) · [验证记录](VERIFICATION.md) · [更新记录](CHANGELOG.md)

CI 运行合成回归和官网检查。推送与 VERSION 一致的`v*`标签触发自动发布；默认仅生成源码预发布。正式签名、公证失败不会退回未签名包。详见[发布流水线](docs/development/RELEASING.md)。

本机测试与真实 Notes 验收分开记录。历史设计与测试记录用于追溯，不等同于当前版本或完整兼容性承诺。

## 官网

官网源码在`site/`，采用 GitHub Pages 默认域名。三个语言版本共用图形与模板；构建方式见[官网说明](site/README.md)。源码、网站部署与正式 App 下载分别管理发布状态。

## 许可与致谢

源码采用 **MIT**。保留实际使用的 NotesPlus、NotesBridge、Yams/LibYAML、Humanizer-zh 的版权及许可；Pi/Node 组件保留各自许可证，详见[第三方声明](THIRD_PARTY_NOTICES.md)和[许可清单](licenses/pi-runtime/manifest.json)。

Quillside 独立开发，与 Apple、ProNotes 及上述上游作者没有隶属关系。品牌展示采用独立设计，不包含 ProNotes 安装包、图标或原厂提示词。
