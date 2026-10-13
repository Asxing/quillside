# 自动发版

仓库使用个人账号[`Asxing/quillside`](https://github.com/Asxing/quillside)，官网使用GitHub Pages默认地址。源码公开、官网上线、正式App发行分别验收。维护者配置与本机授权不进入源码。

## 触发与产物

更新`VERSION`、`BUILD_NUMBER`、`CHANGELOG.md`和`docs/releases/<version>.md`，完成提交后推送一致的标签：

```sh
git tag v0.7.5
git push origin main
git push origin v0.7.5
```

`.github/workflows/release.yml`由`v*`标签触发；也可手动指定已存在标签。标签必须指向被构建提交且与VERSION完全一致，工作区必须干净。整个流程：源码与网站检查 → 8项Pi及原生合成回归 → 可选App构建 → 校验资产 → GitHub草稿上传 → 确认资产完整后发布 → 调用Pages部署。

默认不需要Apple证书。仓库变量`RELEASE_DISTRIBUTION`决定标签自动发版模式，未设置时为`preview`；手动运行可明确选择：

| 模式 | 产物 | GitHub状态 | 所需Apple凭据 |
|---|---|---|---|
| `source` | 源码ZIP、文件清单、SHA256SUMS、版本说明 | 预发布，不上传App | 无 |
| `preview` | 以上内容及`UNNOTARIZED-macOS-arm64.dmg`、ZIP、各自SHA-256 | 预发布，明确未公证 | 无，ad-hoc签名 |
| `notarized` | 源码、Developer ID签名DMG、公证Accepted回执、校验值 | 正常版本为正式发布；带后缀标签仍为预发布 | Developer ID与公证授权 |

无证书时默认使用`preview`生成可安装测试包；确需仅公开源码时手动选`source`。测试者包不能解决Gatekeeper信任或稳定跨版本权限问题；可信来源的单App打开方式见[用户指南](../user/GETTING-STARTED.md)。正式模式缺少凭据、签名或公证失败会停止，不会回退成未签名App。

已经存在的Release不会被脚本覆盖。如果上传失败，草稿保留供排查；维护者处理草稿后再重试。流水线会再次检查远程标签SHA，阻止构建期间标签被移动后的发布。

## GitHub设置

1. 启用Actions和Pages（Source: GitHub Actions），`github-pages`环境允许默认分支与`v*`版本标签（复用workflow的身份来自调用标签）。
2. 创建`release-signing`环境；当前源码/预览模式不使用Apple秘密，正式发布前可设置维护者审核。
3. 主分支规则要求`repository-and-site`与`native`检查；允许维护者按项目实际情况管理首个提交。
4. 启用Security → Private vulnerability reporting。普通Issue用于合成复现；敏感细节只进私密报告。
5. Pages在默认分支CI成功后自动更新；发版workflow显式调用Pages，因为GITHUB_TOKEN创建Release不会可靠触发另一个发布事件workflow。

Pages只上传`site/dist`，不会上传应用数据、整个工作区或签名目录。源码预发布只提供GitHub入口；测试预发布提供明确标注“未公证”的DMG/ZIP下载；只有notarized稳定版的公开资产与校验值一致时才启用官网正式下载按钮。网站构建不会写回仓库，避免发布bot循环提交。

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
