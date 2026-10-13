# OpenNotes 0.1.2 验证记录

日期：2026-10-08，Asia/Shanghai。此记录只证明列出的检查。完整长期目标仍未完成。历史记录：[0.1.0](VERIFICATION-0.1.0.md)、[0.1.1](VERIFICATION-0.1.1.md)。

## 当前结果

- `./scripts/verify-stage1.sh` 成功：静态检查、Swift Testing、Debug 构建。
- 138 项测试中 **136 项执行通过，2 项可选测试跳过**；20 个 suite。
- 新增工具条测试覆盖默认功能集合、显隐和重新读取、拖动顺序算法、全部隐藏、布局迁移/去重、损坏/未来版本保护、窄屏尺寸和错误反馈尺寸。
- 原生命令测试覆盖菜单上下文、中文与省略号、Add/Edit Link 可用项、禁用/歧义、不同修饰位、无有效快捷键时不输入普通字符，以及触发串恢复的冲突条件。
- 视图模型测试确认 AI、字体、链接、对齐、清单与表格路由；失败不触发“格式已应用”回调。
- 原有四种模型协议仍通过 localhost 合成 HTTP 流，未使用真实 API Key 或付费模型。
- Release 构建成功。构建包与 `/Applications/OpenNotes.app` 均通过 `codesign --verify --deep --strict`。
- 安装版本 `0.1.2`，bundle ID `com.opennotes.app`；Apple Silicon，ad-hoc 本地签名。
- 应用包 `build/OpenNotes-0.1.2-macOS-arm64.zip`；源码包 `build/OpenNotes-0.1.2-source.zip`。

主程序 SHA-256：

```text
3722df5edeb910a6b53115bcda5c42979444a25bd5b392f2bfce2bc6661606ee
```

机器可读收据：[verification-0.1.2.json](verification-0.1.2.json)。日志为 `build/toolbar-verification.log`、`build/toolbar-release.log`。

## 尚未通过的门槛

安装后，电脑界面工具再次报告 Mac 锁屏且不能自动解锁。没有完成新版本 GUI、真实 Notes 格式读回、字体面板、拖动、撤销、中文输入法、特殊键盘布局、多屏、全屏与快速切换验证。菜单测试使用合成描述，不证明 Apple Notes 当前菜单一定可读；AXPress 成功也不单独等于正文格式正确。

跳过的两个可选测试为 `testGenerateReadmeScreenshots`、`testReadsBacklinksFromRealDatabaseSnapshotWhenProvided`。未读取真实用户笔记作为自动测试夹具。未做 Developer ID 公证、Intel 构建、公开发布或真实云端账号验证。

[持续对齐状态](GOAL-STATUS.md) 保留全部未完成要求；[工具条实现](TOOLBAR-IMPLEMENTATION.md) 记录本次代码与实机证据之间的边界。目标保持 active。
