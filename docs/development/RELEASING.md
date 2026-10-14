# 自动发版

仓库使用个人账号[`Asxing/quillside`](https://github.com/Asxing/quillside)，官网使用GitHub Pages默认地址。源码公开、官网上线、正式App发行分别验收。维护者配置与本机授权不进入源码。

## 触发与产物

更新`VERSION`、`CHANGELOG.md`和`docs/releases/<version>.md`，按需递增`BUILD_NUMBER`（新版本可从1开始），完成提交后推送一致的标签：

```sh
git tag v0.7.7
git push origin main
git push origin v0.7.7
```

`.github/workflows/release.yml`由`v*`标签触发；也可手动指定已存在标签。标签必须指向被构建提交且与VERSION完全一致，工作区必须干净。整个流程：源码与网站检查 → 8项Pi及原生合成回归 → 可选App构建 → 校验资产 → GitHub草稿上传 → 校验GitHub附件名称、大小与SHA-256 → 自动生成顶部下载链接并发布 → Pages在默认分支自动部署 → 核对公开版本与三语言下载页。

默认不需要Apple证书。仓库变量`RELEASE_DISTRIBUTION`决定标签自动发版模式，未设置时为`preview`；手动运行可明确选择：

| 模式 | 产物 | GitHub状态 | 所需Apple凭据 |
|---|---|---|---|
| `source` | 源码ZIP、文件清单、SHA256SUMS、版本说明 | 预发布，不上传App | 无 |
| `preview` | 以上内容及`UNNOTARIZED-macOS-arm64.dmg`、ZIP、各自SHA-256 | 预发布，明确未公证 | 无，ad-hoc签名 |
| `notarized` | 源码、Developer ID签名DMG、公证Accepted回执、校验值 | 正常版本为正式发布；带后缀标签仍为预发布 | Developer ID与公证授权 |

无证书时默认使用`preview`生成可安装测试包；确需仅公开源码时手动选`source`。测试者包不能解决Gatekeeper信任或稳定跨版本权限问题；可信来源的单App打开方式见[用户指南](../user/GETTING-STARTED.md)。正式模式缺少凭据、签名或公证失败会停止，不会回退成未签名App。

App Release的标题自动标明DMG/ZIP，正文顶部自动生成对应版本的直链、实际大小与SHA256SUMS入口，不依赖用户展开Assets。源码模式仅显示源码下载；未公证包始终保留Pre-release标识。

已经存在的Release不会被脚本覆盖。如果上传失败，草稿保留供排查；维护者处理草稿后再重试。流水线会再次检查远程标签SHA，阻止构建期间标签被移动后的发布。

## GitHub设置

1. 启用Actions和Pages（Source: GitHub Actions），`github-pages`环境须允许默认分支。官网不再从版本标签身份部署。
2. 创建`release-signing`环境；当前源码/预览模式不使用Apple秘密，正式发布前可设置维护者审核。
3. 主分支规则要求`repository-and-site`与`native`检查；允许维护者按项目实际情况管理首个提交。
4. 启用Security → Private vulnerability reporting。普通Issue用于合成复现；敏感细节只进私密报告。
5. Pages通过`workflow_run`监听本仓库`CI`与`Release`成功完成：CI仅接受默认分支push，Release接受tag push或手动发版。始终运行默认分支的可信代码，PR与失败流程不发布官网。这样无需额外PAT，也不依赖GITHUB_TOKEN创建Release后的`release`事件。

Pages只上传`site/dist`，不会上传应用数据、整个工作区或签名目录。源码预发布只提供GitHub入口；测试预发布提供明确标注“未公证”的DMG/ZIP下载；只有notarized稳定版的公开资产与校验值一致时才启用官网正式下载按钮。网站构建不会写回仓库，避免发布bot循环提交。自动部署按发布时间选择已公开版本（有稳定版则优先稳定版），不把旧tag重跑误当成最新版本。所有Pages运行共享并发组，部署后最长等待7分钟，逐字节核对线上`release.json`和根路径、`en`、`zh-CN`、`zh-TW`下载页；超时则失败，不把部署API成功当作官网已更新。

## 正式签名秘密

在`release-signing`环境配置以下Secrets，不在Issue、聊天或仓库文件里传递：

- `DEVELOPER_ID_P12_BASE64`：Developer ID Application证书与私钥的P12编码。
- `DEVELOPER_ID_P12_PASSWORD`：P12导出密码。
- `APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD`：notarytool公证身份。

发布job创建临时Keychain，导入证书，仅为外层App和Node添加Hardened Runtime/安全时间戳，Node使用`allow-jit`最小例外。构建后提交公证、验证Accepted、staple票据、检查签名与许可。临时Keychain和P12在job结束时清理，秘密不进入普通PR或发布资产。

这些代码路径已准备不等于Apple正式验收完成。配置证书后必须运行一次真实公证，并从浏览器下载最终DMG，在干净用户/另一台Mac验证Gatekeeper、首次权限、Pi启动、选区、批注、写回/一次撤销和升级。

## 本地检查

```sh
python3 scripts/test-release.py
python3 scripts/check-open-source.py
./scripts/verify-stage1.sh
python3 site/build.py
python3 site/check.py
```

`prepare`只生成本地元数据；`publish`会实际发布GitHub Release，应只在已检查的tag上执行。详细规则与临时方案依据见[Apple/GitHub官方来源核对](../research/TEMPORARY-DISTRIBUTION-2026-10-13.md)。

## 一次发版的完成条件与重试

1. `Release`工作流成功：DMG/ZIP及校验值已上传、顶部下载直链存在、预发布状态正确。
2. 随后自动触发的`Deploy website to GitHub Pages`成功：包括最后的`Verify public version and download links`，Actions摘要提供下载页地址。
3. 如果仅官网失败，重跑该Pages工作流或手动运行`gh workflow run pages.yml --repo Asxing/quillside --ref main`，无需重打包或修改已发布tag。已有Release不会被覆盖。
4. Release失败时先查看对应job；附件验证未通过会保留草稿。不要移动已经公开的tag。

触发机制依据：[GitHub workflow_run](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)、[GITHUB_TOKEN触发限制](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)。
