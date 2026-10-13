# 授权开关开启但应用仍无权限：原因与验证

> 当前状态更新（0.3.5）：固定本机开发签名已生效；主要原生编辑、AI、模板和正文反链闭环已实测。旧版本权限阻塞与待验文字仅为历史记录。当前结果与未覆盖边界统一见 [0.3.5 实机验收](NATIVE-ACCEPTANCE-0.3.5.md) 和 [验证记录](../VERIFICATION.md)。

2026-10-08，OpenNotes 0.3.1。用户已完成授权，系统开关显示开启，但应用里的 AXIsProcessTrusted 返回未授权，数据库读取也失败。

## 已验证的原因

只读查询本应用的 TCC 记录，auth_value 为允许；提取记录的 code requirement，并调用 codesign 验证当前 /Applications/OpenNotes.app 是否满足。结果：辅助功能、完全磁盘访问及 Notes 自动化对应的允许记录都不匹配当前二进制签名。

复现命令：

```sh
python3 scripts/check-authorization-signature.py
```

初次实际输出：三个服务的 `allowed_in_record` 都为 true，而 `current_signature_matches_allowed_record` 都为 false，退出码1。

当前本地包采用 ad-hoc 签名，其默认指定要求绑定 CodeDirectory hash；重建改变 hash，旧记录并不授权新二进制。该机器没有可用的 Apple Development / Developer ID Application 签名身份。这解释了系统开关开启而实际访问仍被拒绝，不能归因于用户没有打开开关。

## 修复边界

通过系统设置移除旧应用条目，再选择当前 /Applications/OpenNotes.app 添加并授权；需要系统管理员认证时由用户在原生窗口完成。不直接修改 TCC 数据库、不调用绕过授权的私有路径、不降低安全设置。当前应用二进制保持不变，先验证本轮已签名构建。

脚本只用于诊断，记录不可读时报告 unavailable，不以读取失败猜测授权状态。修复之后同时检查：记录是否匹配当前签名、App自身权限状态、真实Notes编辑与读回。这三层证据缺一不可。

后续频繁开发应使用稳定的开发签名身份，以避免每个构建反复重新授权；公开分发还需 Developer ID/公证。不能用不绑定签名的宽泛授权要求来规避系统检查。

## 当前进度

已通过系统设置选择移除旧 OpenNotes 辅助功能条目，macOS 弹出管理员密码窗口，等待用户在系统完成认证。尚未据此宣布授权修复成功。已准备 localhost 合成模型，实际编辑验收随后继续。

## 后续核验

0.3.1曾通过正常系统界面修复辅助功能和完全磁盘访问，应用实际显示可用。后续实机修复构建再次改变签名，最终0.3.4已重新登记，这两项记录与当前签名匹配。Notes自动化记录仍旧，不能仅以系统开关断言真实行为。该问题是开发签名与验收流程管理问题，不是用户漏开权限。最新状态以VERIFICATION.md为准。
