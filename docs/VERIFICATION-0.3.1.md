# OpenNotes 0.3.1 验证记录

2026-10-08，Asia/Shanghai。当前交付范围为编辑、模板、Notes原位AI与反链。用户确认排除账号计费、遥测、Floating notes/Vim和复杂模型路由；搜索与知识库不恢复，笔记文件导入导出延期。实现详情见 [本轮核心修复](CORE-IMPLEMENTATION-0.3.1.md)，历史记录见 [0.3.0](VERIFICATION-0.3.0.md)。

## 已执行的检查

- `verify-stage1.sh`：静态检查、Swift Testing、Debug构建全部通过。
- **177项测试，176项执行通过，1项旧宣传截图用例跳过，28个suite。**
- 新增回归覆盖真实行首检测、鼠标换行后不依赖旧输入buffer、emoji/无效范围、正文/表格单元格/对话框识别、IME不明时不消费候选键、多个面板独立占用、Markdown单项开关持久化、单次粘贴范围与剪贴板恢复策略。
- 新测试实际发现Foundation范围转换没有拒绝半个emoji的UTF-16范围；修复后正确拒绝，原文不被破坏。
- SSE多行data、UTF-8/BOM、CR/LF/CRLF、注释、截断和最大缓冲验证通过；localhost四协议服务改用真实多行SSE并拆分UTF-8网络字节，集成测试通过。NDJSON无末尾换行时单独处理，SSE的EOF不补空行。
- 保留当前AI原生视图渲染测试及两篇合成Notes实际编码正文的A→B解析测试，没有将真实用户正文发给外部模型。
- Release构建成功，构建包及安装目录 `codesign --verify --deep --strict` 通过。旧OpenNotes正常退出后安装0.3.1；本地arm64/ad-hoc包，尚未Developer ID公证或对外发布。

二进制 SHA-256（构建与安装一致）：

```text
75882bb66090a31b716eb3feea54b6538df1d2f709fcf319aaa19394f69173bf
```

[验证收据](verification-0.3.1.json)。日志 `build/core-verification.log`、`build/core-release.log`。应用包 `build/OpenNotes-0.3.1-macOS-arm64.zip`；源码包 `build/OpenNotes-0.3.1-source.zip`。

## 尚未通过的实机门槛

本轮开始时App仍显示辅助功能/完全磁盘访问未生效，Notes自动化已授权；系统认证窗口未完成。安装后再次尝试界面验证时，工具报告Mac已锁屏、不能自动解锁。用户已允许辅助功能授权，无需重复许可；后续须解锁并在macOS原生认证窗口完成验证。

因此，新版本实际Notes中的AI生成/替换/插入/撤销、Markdown/slash、模板、正文反链更新仍待验收。原生粘贴路径已经实现，但没有把“调用Paste”写成真实撤销通过；输入法组合态未知时保留系统按键，点选菜单是当前回退，不能宣称所有输入法的快捷提交都已验证。

Notes正文识别采用本机已观察到的稳定AX标识和祖先结构。未知编辑器拒绝操作，不猜测全文；其他系统版本/私有schema、多账户和复杂表格内链仍需样本。AI与模板写入纯文本，不承诺富文本/附件保真。

本轮未修改原有用户笔记、模型密钥或历史知识库文件。未通过的实机项仍在 [核心验收表](CORE-ACCEPTANCE.md)；不把代码/回归计数等同于完整交付完成。

## 追加诊断：用户授权后仍未生效

用户报告已授权后，重新检查系统开关确实开启，但App仍不可访问。只读检查确认三项TCC允许记录（辅助功能、完全磁盘访问、Notes自动化）均不匹配当前安装包的指定代码要求。原因是ad-hoc构建更新后旧授权仍绑定此前的CodeDirectory hash。详见 [授权诊断](AUTHORIZATION-DIAGNOSIS.md)。当前已从系统界面请求移除旧条目，但macOS再次要求管理员认证，仍待用户在系统窗口完成；未修改TCC数据库，二进制没有变化。此次本地测试服务已停止，请求数为0。
