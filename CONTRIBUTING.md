# 贡献指南

项目代码采用 [MIT](LICENSE)。提交前请确认自己有权贡献这些内容，并保留所使用第三方代码的版权与许可。贡献沿用本项目 MIT，不要求额外版权转让。

## 项目范围

主要改进 Apple Notes 内的编辑、原文批注、AI 写作、快捷格式、模板与明确触发的正文反链。模型连接、角色 Prompt 和 Skill 独立配置。独立知识库、独立搜索与后台全库同步不属于当前方向；MCP / Tools 和完整 Markdown 文件交换暂缓。

较大的功能或行为变化，先通过 Issue 说明具体场景和取舍。缺陷修复应给出可复现问题；维护者审核和测试通过后才合并。不承诺固定响应或合并时限。

当前使用与开发入口见[文档导航](docs/README.md)，发行规则见[自动发版](docs/development/RELEASING.md)。

## 开发环境

- macOS 14 或以上的构建目标；Swift 6.2 工具链。当前实机验证范围见 [README](README.md)。
- Xcode 或对应 Command Line Tools；Python 3.10+；静态检查脚本使用 ripgrep。
- Node.js版本固定在`.node-version`（Pi最低要求22.19.0），需要npm。Pi构建、测试与打包都会使用它；最终App自带Node。官网只用Python标准库，JS语法检查同样使用该Node。
- `Package.resolved`和`runtime/pi/package-lock.json`固定Swift/Pi依赖；升级时同步检查根许可清单与`licenses/pi-runtime/manifest.json`。

```sh
python3 scripts/check-open-source.py
./scripts/verify-stage1.sh
python3 site/build.py
python3 site/check.py
node --check site/assets/site.js
python3 scripts/test-release.py
```

自动回归使用临时 SQLite 数据和 localhost 模拟模型，不需要真实 API Key 或 Notes 正文。数据库实测与截图用例默认不启用；不要在公共 CI 中设置这些实测环境变量。

完整 Xcode 使用的测试 Framework 路径与 Command Line Tools 不同。可显式设置 `DEVELOPER_DIR` 为 `xcode-select -p` 返回的路径；CI 会这样做。Swift 编译告警应记录，不要将编译通过写成全功能实测通过。

本机试运行可以使用临时签名：

```sh
OPENNOTES_CODE_SIGN_IDENTITY=- ./scripts/bundle-app.sh debug
```

临时签名包不能当作正式发行包；签名身份改变可能要求重新授权。不要覆盖现有正式安装来跑测试。真实 Notes 验收只使用专门的合成笔记，覆盖预览、写回、一次撤销、取消、切换目标与权限失败。

## 代码约定

- 遵循相邻模块的 Swift / SwiftUI / AppKit 风格；新增代码使用四空格缩进，避免顺带重排整个文件。
- 保持主线程响应；避免在输入回调中反复读取整篇笔记或执行同步网络/钥匙串调用。
- 所有写回先验证目标，保留用户确认与撤销路径；失败时不扩大写入范围。
- 不在日志中记录笔记正文、Prompt 内容、API Key 或认证信息。
- 为行为变化增加能够复现问题的测试；文案、文档与简单样式变化使用合适的检查即可。
- 新增/升级依赖要说明用途、版本、许可证和分发方式，同时检查间接依赖。

## 提交 Pull Request

使用 PR 模板说明问题、最终行为、验证与剩余边界。UI 变化提供合成内容截图；写回变化提供原文、候选、写回和撤销一致性证据。不要提交个人笔记、账号、密钥、证书、数据库或诊断原始包。

本项目原始代码来自多个 MIT 项目。对外使用独立品牌时，仍需保留 [第三方声明](THIRD_PARTY_NOTICES.md) 与版权信息。遇到安全问题请遵循 [SECURITY.md](SECURITY.md)，不要在公开 Issue 披露可利用细节。
