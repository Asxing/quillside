# OpenNotes 0.1.1 验证记录

日期：2026-10-08，Asia/Shanghai。此记录仅证明当前列出的检查，不证明完整功能目标完成。上一版记录保存在 [0.1.0 验证](VERIFICATION-0.1.0.md)。

## 当前结果

- `./scripts/verify-stage1.sh` 成功：静态检查、Swift Testing、Debug 构建。
- 121 项测试中 **119 项执行通过，2 项可选测试跳过**；18 个 suite。
- 4 种模型协议通过本机合成 HTTP 流测试；未使用真实 API Key 或收费模型。
- 新增测试覆盖：官网 slash 输入的正确动作；精确别名排序；URL/词内斜杠与 UTF-16；功能开关持久化；失败写盘后旧凭据和重启状态；密钥清理失败；损坏配置保留与恢复；SQLite 排它锁；整批快照回滚；缺失 Notes 正文；未来 schema 版本保护。
- Release 构建成功，构建包和安装包均通过 `codesign --verify --deep --strict`。
- 安装位置 `/Applications/OpenNotes.app`；版本 `0.1.1`，bundle ID `com.opennotes.app`；Apple Silicon 本地 ad-hoc 签名。
- 应用包：`build/OpenNotes-0.1.1-macOS-arm64.zip`；源码包：`build/OpenNotes-0.1.1-source.zip`。

主程序 SHA-256：

```text
178c0dbbfd681c82f518b8c673d9745f9ceda596e31c72878d86e0d30e2dfbcf
```

机器可读检查收据：[verification-0.1.1.json](verification-0.1.1.json)。测试与构建日志位于本地 `build/audit-verification.log` 和 `build/audit-release.log`，不随源码包分发。

## 尚未通过的门槛

电脑界面工具本轮再次报告 Mac 锁屏且不能自动解锁；未启动新版本进行 GUI、真实 Notes 编辑/写回、撤销、中文输入法、多窗口、多显示器验收。没有把纯函数与模拟模型通过视为实机行为证明。

跳过的可选测试为 `testGenerateReadmeScreenshots`、`testReadsBacklinksFromRealDatabaseSnapshotWhenProvided`。没有提供用户真实笔记库作为夹具。Keychain 事务回归使用合成凭据存储器，尚需单独验证真实系统授权拒绝、锁定、升级和重启行为。

未做 Developer ID 公证、Intel 构建、公开发布或真实服务商账号验证。完整对标缺口保留在 [持续对齐状态](GOAL-STATUS.md) 及三个源码审计中。长期目标保持 active。
