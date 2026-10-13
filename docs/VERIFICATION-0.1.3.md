# OpenNotes 0.1.3 验证记录

日期：2026-10-08，Asia/Shanghai。此记录仅证明列出的检查；完整长期目标仍未完成。历史记录：[0.1.0](VERIFICATION-0.1.0.md)、[0.1.1](VERIFICATION-0.1.1.md)、[0.1.2](VERIFICATION-0.1.2.md)。

## 当前结果

- `./scripts/verify-stage1.sh` 成功：静态检查、Swift Testing、Debug 构建。
- 157 项测试中 **155 项执行通过，2 项可选测试跳过**；23 个 suite。
- 模板新增验证：旧 JSON、快捷词冲突、私有 ID 不作为别名、中文名称检索、日期、IME marked-text 路由、重复失败提交、实际选区改变拒绝写入。
- 搜索新增验证：标题优先、多词/重音、选择身份、错误与零结果区分、取消后旧结果失效、真实 SQLite schema 和锁定摘要。
- 热键新增验证：冲突保留旧绑定、写盘失败只清理新绑定、清除/重载、独立修改、双路避免、录入暂停/恢复、未来版本保护。
- 四种模型协议仍使用 localhost 合成 HTTP 服务，未调用真实付费模型或读取真实 API Key。
- Release 构建成功。构建包与安装包均通过 `codesign --verify --deep --strict`。
- 安装位置 `/Applications/OpenNotes.app`，版本 `0.1.3`，bundle ID `com.opennotes.app`，Apple Silicon、ad-hoc 本地签名。
- 应用包 `build/OpenNotes-0.1.3-macOS-arm64.zip`；源码包 `build/OpenNotes-0.1.3-source.zip`。

主程序 SHA-256：

```text
4d277f4379b271cdffb8e4296eb9b11aacac51194205d0f77eade13b209efa6b
```

机器可读收据：[verification-0.1.3.json](verification-0.1.3.json)。日志为 `build/templates-search-verification.log` 与 `build/templates-search-release.log`。

## 未通过的实机门槛

安装后电脑界面工具再次报告 Mac 锁屏且不能自动解锁，因此没有完成真实模板插入/撤销、输入法候选、初始焦点、Carbon 占用/恢复、快捷键录入和笔记链接打开的 GUI 验收。

两项可选测试 `testGenerateReadmeScreenshots`、`testReadsBacklinksFromRealDatabaseSnapshotWhenProvided` 仍跳过。模板写入回调和 hotkey registrar 在测试中为合成替身，不能代替 AX/Carbon 实机证据；SQLite 测试使用临时合成库。没有把源码路径与测试计数当作完整功能完成证明。

原厂模板发现协议、富文本模板、反链/schema、知识集合身份及其他剩余要求见 [持续对齐状态](GOAL-STATUS.md)。未做 Developer ID 公证、Intel 包、公开发布或真实服务商账号验证。长期目标保持 active。
