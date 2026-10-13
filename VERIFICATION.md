# Quillside 当前验证

2026-10-13，源码版本0.7.4，开发者预览。当前正式下载仍未完成Developer ID、公证与干净用户安装验收。

## 本轮实际执行

- `./scripts/verify-stage1.sh`：原生runner报告261项，257项执行通过，4项截图/真实数据库条件用例跳过；Pi集成8项通过；debug构建成功。
- 显式使用Command Line Tools的`DEVELOPER_DIR`运行回归，修复后的Framework路径可用。
- `scripts/test-release.py`的8项保护测试通过：标签版本/模式、缺少资产、错误SHA、混入文件、源提交不匹配、公证回执、官网预发布与正式下载边界。
- 源码检查在`build/`父目录下复制的独立仓库中通过，原路径误报已修复。
- actionlint 1.7.12校验三份GitHub工作流通过，脚本语法与文档本地链接检查通过。
- 官网三语言15页及5个兼容页的资源、锚点、翻译、语言切换目标与JS语法检查通过。
- 许可/选定凭据规则检查通过。此扫描不等于完整安全审计；Swift仍有隔离和弃用告警。

## 已有实机证据

[Pi真实订阅与Notes闭环](docs/PI-REAL-ACCEPTANCE-0.7.0.md)：单句和整篇生成、写回与一次撤销，五条批注保留；[三场景](docs/REAL-AGENT-SCENES-0.6.3.md)：公众号、个人笔记、汇报的实际差异与事实限制；[批注恢复](docs/NATIVE-LOOP-ACCEPTANCE-0.6.5.md)。本轮发行脚本修改未重新调用用户真实模型。

品牌与网站：[全局Logo](docs/BRAND-SYNC-0.7.3.md)、[多语言网站](docs/WEBSITE-LANGUAGES-2026-10-13.md)。

## 远程发布验收

- 个人仓库[Asxing/quillside](https://github.com/Asxing/quillside)已公开，MIT识别正确，私密安全报告已启用。
- [CI](https://github.com/Asxing/quillside/actions/runs/38406996913)两个job通过；首次runner缺少ripgrep与模拟服务DNS启动等待问题已修复。
- [v0.7.4自动发版](https://github.com/Asxing/quillside/actions/runs/38407914028)完成源码发布和Pages联动。Pages环境已允许默认分支与版本标签，失败的部署段重试后成功。
- [源码Release](https://github.com/Asxing/quillside/releases/tag/v0.7.4)已下载核对，433项文件哈希、归档完整性和tag提交一致；当前没有对外发布未公证App包。
- [三语言官网](https://asxing.github.io/quillside/)已上线，15页及4项关键资源/许可HTTPS检查通过，实际语言切换保留仓库子路径。

## 仍需独立确认

- Developer ID身份、内嵌Node正式签名、公证Accepted与staple票据、浏览器下载后的Gatekeeper验证。
- 新用户权限、更新后的权限/配置/草稿保留，以及更广泛系统、IME、多屏和文档结构。

本地日志位于忽略目录`build/release-preparation/`。当前已安装App不会因源码版本变化自动升级。
