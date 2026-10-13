# 固定本机开发签名

用户已明确允许信任专用于 OpenNotes 的本机开发证书。当前用户的信任设置只包含 CodeSigning 策略，不包含 TLS 全局信任。证书指纹 `9F39E87C70295CF5B89225E2CB136421D4FF584D`；身份为 OpenNotes Local Development。

`./scripts/bundle-app.sh release` 自动使用 `~/Library/Application Support/OpenNotesDevelopmentSigning/identity.json` 指向的独立钥匙串。私钥、密码、钥匙串不在仓库和源码包中。helper 仅在签名期间把该钥匙串加入用户搜索列表，结束恢复列表；不创建信任、不更改 TCC。`--check` 只检查该身份可用。

默认指定要求绑定 `com.opennotes.app` 和证书叶指纹；不同二进制用同证书签名仍满足同一身份。两份内容不同的探针已交叉验证；安装多个实际修复构建后，辅助功能/FDA记录也持续匹配且真实编辑、数据库读取可用。

从旧 ad-hoc 切换证书的首次迁移已通过系统设置重新登记 AX/FDA，不需要每次构建重做。保持 bundle ID 与此证书；更换证书、重建钥匙串或明确选择 ad-hoc 可能再次需要迁移。证书有有效期，不能承诺永久免授权。

本机证书不是 Developer ID 公证身份；公开分发需要独立发布签名与公证流程，不把本机信任分发给其他用户。

只读诊断：`python3 scripts/check-authorization-signature.py`。当前 AX/FDA匹配；历史 AppleEvents 的保存要求仍不匹配，但本轮运行的 Notes 自动化实际连续成功，因此二者分别记录。设置 UI 已修复为绑定真实 AppState，不再从 AI 入口创建空状态造成误报。
