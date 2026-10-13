# OpenNotes 0.2.0 验证记录

2026-10-08，Asia/Shanghai。[当前功能清单](CURRENT-FEATURES.md) 是本轮范围：编辑、模板、当前内容 AI、反链；独立搜索与知识库退出，笔记文件导入导出延期。历史记录：[0.1.3](VERIFICATION-0.1.3.md)。

## 已验证

- `./scripts/verify-stage1.sh`：静态检查、Swift Testing 与 Debug 构建通过。
- 最终 **159 项测试，158 项执行通过，1 项可选截图测试跳过，24 个 suite**。历史搜索/知识库用例已随代码归档，不计入当前目标。
- 新增：旧默认指令精确迁移、用户自定义与密钥引用保持、历史资料文件不变；请求仅使用本次材料、旧 sources 指令明确拒绝；Notes 搜索/打印键不被路由消费。
- 正文反链：重复更新无变化、部分覆盖保留旧来源、完整覆盖更新来源、UTF-16/emoji、用户修改/移动/重复区域拒绝、链接目标变化拒绝、损坏记录不覆盖、跨重启与撤销历史、生成边排除。
- 实际 Notes 中创建两篇专用合成笔记，验证可点击链接插入、撤销及 A 点击链接打开 B。只提取这两篇测试记录及实际编码正文，在真实库可选测试中断言 A → B 反链关系；未复制其他用户笔记。
- 四类模型协议使用 localhost 合成 HTTP 服务，没有调用真实付费模型或读取真实 API Key。
- Release 构建、构建包与安装包 `codesign --verify --deep --strict` 通过。版本 `0.2.0`，arm64，ad-hoc 签名。
- 安装到 `/Applications/OpenNotes.app`；最后一次保护逻辑补充已更新磁盘文件，正在运行的先前实例需退出并重新打开以加载最终二进制。

主程序 SHA-256（构建与安装一致）：

```text
85278912296ac8c84aaeeb82f232d9988af81655842c90fc8a8aacb9ccf5fc42
```

[机器可读收据](verification-0.2.0.json)。日志：`build/scope-verification.log`、`build/scope-release.log`。应用包：`build/OpenNotes-0.2.0-macOS-arm64.zip`；源码包：`build/OpenNotes-0.2.0-source.zip`。

## 仍未验收

界面工具能读取 Notes，但读取新版 OpenNotes 时多次报告 `Sky Computer Use native pipe closed before response`，重置会话后仍复现。没有绕过此限制用其他自动化驱动界面。原生 Notes 的 HTML 链接插入验证不能代替 OpenNotes RTF 粘贴按钮的完整验收。

因此，正文反链“预览 → 写入 → 再更新 → 撤销 → 打开来源”的完整 App 流程仍待验证；浮条/模板/AI 写回的焦点、中文输入法、多窗口、全屏与复杂富文本也未全面验收。复杂表格内链接、旧系统 schema、跨设备修改仍有覆盖边界。

本次两篇 `OpenNotes 验证 20261008 A/B` 暂留在 Notes 的普通 Notes 文件夹供复测。旧应用正常退出后进行了安装；没有修改其他原有笔记或删除用户索引/配置。

未做 Developer ID 公证、Intel 包、公开发布或真实服务商账号验证。完整项目保持进行中，不把本轮范围收敛和回归通过视为全部完成。
