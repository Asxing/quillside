# Quillside 暂无 Apple Developer 会员时的分发与自动发布

核对日期：2026-10-13。范围：Apple、GitHub 官方资料。用户已选择个人 GitHub 账号发布；本轮未确认 Apple Developer Program 会员状态。本文提供暂无会员时的实现依据，没有创建远程资源、读取凭据或执行签名/公证。

## 实用建议

**先公开源码；自动发布管线可以同时准备 ad-hoc 测试包，但二进制只进入清楚标注“未公证、面向测试者”的 prerelease。** 测试者自行确认来源并按 macOS 官方界面允许此 App。正式默认安装路径等加入 Apple Developer Program 后再接 Developer ID 和公证。没有必要为了源码首发等待付费会员。

| 路径 | 当前可做 | 限制与实际验收 |
|---|---|---|
| 公开源码首发 | 公开代码、许可证、构建说明、Git 标签和源码 Release | 只提供源码不代表 App 下载包已发行；由开发者本机构建测试 |
| 未公证测试者预发布 | CI 构建 release 优化配置，ad-hoc 签名，上传明确命名的 App ZIP、校验值与说明 | macOS 默认可能阻止首次打开；测试者自行决定“仍要打开”；更新可能需要重新授权；不标成“Apple 已验证” |
| 正式直接发行 | Developer ID 签名全部可执行项，公证、staple，再发布普通下载 | 要具备付费会员对应资源；还要验证 Gatekeeper、权限、Pi/Node 启动和升级，不能只凭公证成功认定产品验收 |

以上是项目交付建议。Apple 的开发签名、公证和用户逐 App 例外是不同机制；GitHub prerelease 标签本身不会改变 Gatekeeper 行为。[Apple 签名发行](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)、[GitHub CLI prerelease](https://cli.github.com/manual/gh_release_create)

## 免费本机开发的边界

免费 Apple Account 可以在 Xcode 作为 Personal Team 进行个人设备测试。Apple 管理开发所需的身份/配置，部分 provisioning 资源需要定期重新生成。它不是 Developer ID，也不是免费公证通道。不要把 Personal Team 的 provisioning 期限直接套用到 macOS ad-hoc 签名包并宣称“所有 Mac 包只能运行七天”。[Apple：Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)

macOS ad-hoc 签名在 Xcode 名为“Sign to Run Locally”。它没有 Apple 认证的发行者身份；其 designated requirement 绑定特定代码版本，系统不能据此可靠跟踪跨版本身份。对 Quillside 的辅助功能、Notes 自动化等权限，更新后是否重授权必须实测，不能承诺“换包永久免授权”。[Apple：TN3127 Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

本项目本机自签名证书可用于既有本机开发；不应把该私钥、钥匙串或信任配置放进源码/CI，也不应要求测试者安装并信任开发者的本机根证书。推荐 CI 测试包采用显式 ad-hoc 模式，让发行状态可检查；这是基于项目的实施建议，ad-hoc 不能让 Gatekeeper 认可发行者。

## 测试者打开未公证 App：只采用 Apple 的界面流程

Apple 官方流程：先尝试打开下载的 App；如果系统因未识别发行者或未公证而阻止，且测试者确信来源可信、内容未被篡改，可进入“系统设置 → 隐私与安全性”，找到该 App 的“仍要打开 / Open Anyway”，再确认打开。系统为此 App 保存例外。[Apple：Safely open apps on your Mac](https://support.apple.com/en-us/102445)

说明中同时提供标签/提交、版本、架构、SHA-256、实际权限用途、合成笔记测试步骤。校验值能检查下载一致性，不代表 Apple 验证或完整安全审计。若系统报告已知恶意软件、撤销授权、文件已损坏，不能把它概括成普通“未公证提示”让用户继续；应核对包并修复。受组织管理的 Mac 可能限制用户更改这些设置。[Apple：警告类型与管理限制](https://support.apple.com/en-us/102445)

安装说明不包含全局关闭 Gatekeeper、删除 quarantine 属性、关闭 SIP 或导入本机开发信任的方法。也不承诺任何版本、任何组织管理策略下都能使用 Open Anyway；实际浏览器下载后的路径需要验证。

## 以后如何转成正式发行

Apple Developer Program 提供 Developer ID 与 Mac 软件公证资源，官方当前列出每年 99 美元会员费用，具体购买币种/税费以注册页面为准。[Apple：Developer Program](https://developer.apple.com/programs/)

公证明确要求 Developer ID、有效可执行项签名、Hardened Runtime 和安全时间戳，不能用 ad-hoc、Apple Development 或本机开发证书替代；使用 `notarytool` 获取结果，成功后 staple ticket。Quillside 包含独立 Node 可执行文件，其签名、最小 JIT 例外与运行验收需要一起纳入发行管线。[Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

两种管线必须显式区分：无正式发行身份时只产出未公证 prerelease；将来选择正式模式却缺少发行身份/公证配置，应直接失败，不可静默回退 ad-hoc 后发布成正式版。

## GitHub 自动 Release 管线建议

由维护者推送版本标签（例如 `v0.7.3`），或手动 `workflow_dispatch` 选择已经存在的标签。GitHub 支持标签 push 过滤；Release 与源码标签绑定。[GitHub：Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)

建议顺序：检出标签并核对 VERSION → Swift/Pi 合成回归 → 构建与许可包检查 → 生成源码包与可选 ad-hoc App ZIP → 计算 SHA-256 → 发布对应 Release。自动化验证不替代测试者机器的首次授权/安装验收。这是本项目管线设计，不是 GitHub 强制步骤。

普通检查 job 使用 `contents: read`；只有最终发布 job 使用 `contents: write`。`gh` 在 GitHub-hosted runner 已预装，可将仓库自动提供的 `GITHUB_TOKEN` 传给 `GH_TOKEN`，无需为同仓库 Release 创建个人长期 token。[GitHub：使用 CLI](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-github-cli)、[GitHub：最小 token 权限](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)、[GitHub：contents write 可创建 Release](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)

上传明确选定的资产，用 `--verify-tag` 防止 CLI 自动从默认分支创建意外标签。测试包用 `--prerelease --latest=false`，发布说明写明“ad-hoc 签名，未公证，面向自愿测试者”；可以先建 draft、上传并核对后发布。源码单独 Release 可以只附源码，不冒充已公证 App。[GitHub CLI：gh release create](https://cli.github.com/manual/gh_release_create)

不要依赖“使用 GITHUB_TOKEN 创建 Release 后触发另一个 release 工作流”来串联发布和官网。GitHub 默认不会因为这个 token 引发的新事件自动运行第二个工作流；可在同一工作流中按依赖执行，或显式 dispatch。普通外部 PR 不进入发布 job、不接触签名/公证秘密。[GitHub：Triggering a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

## 证据边界

本记录是当前官方文档核对与管线建议，不证明任何生成包在另一台 Mac 上已运行，不证明远程 GitHub Actions 已执行，也没有确认 Apple 付费账号或发行证书。实际自动化与首次发布由独立实施任务验收。
