# OpenNotes 0.1 本地交付验证

日期：2026-10-07，Asia/Shanghai。当前环境：macOS 26.5.2，Swift 6.2.4，Command Line Tools，Apple Silicon。

## 已完成

- `./scripts/verify-stage1.sh`：静态检查、Swift Testing、Debug 构建成功。
- 测试 runner 报告 109 项测试、15 个 suite：107 项通过，2 项可选测试跳过。
- `realHTTPStreamingAcrossFourProtocols` 实際通过 localhost 合成 HTTP 服务测试 Chat Completions、Responses、Anthropic Messages、Ollama Native；包括传输时拆开的中文与 emoji 字节。
- SQLite 测试验证中文短词、集合范围、替换旧文本、删除后召回消失。
- 编辑保护测试验证 UTF-16、正文变化、错误范围、Markdown/slash 前缀范围。
- 配置测试验证 JSON 往返、无效引用、服务地址要求、凭据的 scheme/host/port 范围。
- Release 构建成功；`codesign --verify --deep --strict` 对构建包与安装包成功。
- 生成应用压缩包 `build/OpenNotes-0.1.0-macOS-arm64.zip`。
- 安装到 `/Applications/OpenNotes.app`，bundle ID `com.opennotes.app`，版本 `0.1.0`。

安装包主程序 SHA-256：

```text
32816d8ffc140b3fe4f65ceb54592647f16a793f5b22d1c4723813073bca15d6
```

## 未完成的实机边界

电脑界面工具在尝试启动 OpenNotes 时返回：Mac 已锁定且不能自动解锁。因此没有把“构建成功”当作“界面、权限、真实 Notes 编辑均已验收”。尚需用户解锁，并为新应用授予对应权限后测试：选区工具条、Markdown/slash、原生格式、反链、多窗口、写回和撤销。

两个跳过的测试分别为 `testGenerateReadmeScreenshots` 与 `testReadsBacklinksFromRealDatabaseSnapshotWhenProvided`，它们要求额外显式提供截图输出位置或数据库快照。本轮没有提供用户真实笔记库作为自动测试夹具。

未使用任何真实 API Key，没有调用收费模型；localhost 合成服务通过只证明客户端协议链路，不证明某个云端账号或模型可用。请在应用内配置后运行连接测试。

应用为 ad-hoc 本地签名，未做 Developer ID 公证、Intel 构建或公开发布。新增功能范围与仍缺少的完整对标功能见 README。

## 源码依据

NotesPlus `518886fc42118ec913d44694d69549f38e3d9e4c` 与 NotesBridge `91bccb0d34205d9813508de8146ea07540ac161f` 的来源、选取范围与 MIT 原文均已保留。所有配置示例只包含合成内容和默认指令。
