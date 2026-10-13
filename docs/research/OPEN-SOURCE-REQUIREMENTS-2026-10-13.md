# Quillside 公开发行要求：官方依据核对

日期：2026-10-13。范围：GitHub 官方文档、Apple 官方直接发行文档、OSI MIT 正文与 FAQ；辅以当前工作区的只读核对。没有创建远程仓库、签名、公证、发布 Release 或部署网站。

## 结论

可以分三步交付：先公开可复现的源码，再发行经过签名、公证和安装验证的 macOS 下载包，最后把网站接到实际仓库与下载入口。源码公开不需要等待 Apple 公证、完整官网或注册商标。当前主要缺口是公开内容审阅、官网对现有运行时的许可/隐私说明同步、正式 Git 提交与远程仓库，以及独立的 App 发行验收。

| 交付目标 | 实质阻塞项 | 可以随后完善 |
|---|---|---|
| MIT 源码仓库 | 明确可公开文件；保留实际引用/分发组件的版权与许可；提供足够构建说明；正式提交到确定归属的公开仓库 | 自定义域名、自动更新、完整官网、商标注册、复杂社区治理 |
| 普通用户可下载的 macOS App | 核对最终包依赖许可；Developer ID 签名与公证；验收实际下载包、首次安装、权限授予与升级 | DMG 装饰、自动更新、Intel 版、App Store |
| 正式产品网站 | 选择托管和地址；内容与真实发布状态一致；验证实际页面和链接；说明托管方日志边界 | 自定义域名、分析服务、SEO 增强 |

表中“提供构建说明”和“安装验收”是本项目交付质量门槛，不是 GitHub 对创建公开仓库的技术强制条件。“正式产品网站”也可先只有源码入口，并写明 App 暂未公开下载。

## 源码：许可要求与社区建议分开

GitHub 说明，仅让仓库可见不等于授予使用、修改和分发权；真正开源需要许可证。MIT 允许修改、分发和销售，其明确条件是保留版权与许可声明。项目根 `LICENSE` 当前保留 NotesPlus 版权，不应因改名而删除上游声明。[GitHub：Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)、[OSI：MIT 正文](https://opensource.org/license/mit)

README、贡献指南、行为准则和 Issue 模板属于 GitHub 推荐的社区健康文件；没有要求在源码首次开放前完成复杂治理。当前已存在这些文件，重点应转为校准实际版本、仓库地址和维护承诺。[GitHub：Community profiles](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories)

`SECURITY.md` 描述报告方法，但不会自动启用私密漏洞报告。GitHub 需要仓库管理员在远程设置启用，之后才出现私密报告入口。当前项目自身 `SECURITY.md` 已规定首次公开前启用，因此这是本项目的发布承诺，不是 MIT 条款。[GitHub：添加安全政策](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)、[GitHub：启用私密报告](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)

GitHub Release 基于标签，可以附发行说明与二进制；GitHub 会提供标签对应源码 ZIP/TAR。因此源码 Release 与 App 下载可以分开，不必为了创建首个源码版本上传开发签名的 App。[GitHub：About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

## macOS App：本机开发签名不能替代发行签名

Apple 的直接分发路径使用 Developer ID Application 身份；公证需要有效签名、Hardened Runtime、安全时间戳等条件。分发内嵌可执行文件也要核对签名；本项目包含 Node 运行时，不能只检查外层 `.app`。使用当前 `notarytool` 流程，成功后保留公证结果并 staple ticket。公证不是 App Review。[Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Developer ID 身份与 Apple 公证票据供 Gatekeeper 核查发行者及篡改/已知恶意软件风险。本机自签名身份只能说明本机开发签名状态，不能替代此路径；源码自行构建是另一种交付方式。[Apple：Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)

Apple 说明 Hardened Runtime 默认限制 JIT 的可写/可执行内存；使用 `MAP_JIT` 的 JIT 运行时需要对应 `com.apple.security.cs.allow-jit` 例外。本项目的 Node 应独立检查其最终签名、时间戳、runtime flag 与必要的最小 entitlement，再验证 Pi worker 实际启动和模型任务。不从 Apple 通用文档直接断言当前 Node 构建具体需要哪一组额外 entitlement，也不以扩大全部例外作为默认修复。[Apple：Allow execution of JIT-compiled code](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit)

本项目建议的验收证据：最终下载包的版本、架构、SHA-256；嵌套签名验证；公证 Accepted 记录与 ticket；浏览器下载后默认 Gatekeeper 路径下首次启动；从空权限状态完成授权；用合成笔记验证读取、预览、写回和撤销；从旧版本升级后的权限、配置与数据验证。这是结合 Notes 数据修改能力与嵌入运行时提出的项目验收，官方公证成功本身不会证明这些功能正确。

## 网站与品牌：不强制绑定 App 发行

GitHub Pages 可托管静态 HTML/CSS/JS，可使用默认 `github.io` 地址；自定义域名不是前置条件。若采用 Pages，访问者 IP 会被托管方记录用于安全用途；网站“无分析服务”不等于“托管方不留日志”。[GitHub：What is GitHub Pages?](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)

当前 `site/content/release.json` 是 `preview`，仓库、下载、发布时间、SHA-256、支持邮箱均为空，`notarized=false`。源码先公开时，可以仅填真实仓库入口、写明二进制尚未发行；不应为了上线网站把这些空字段填成假链接。当前 `site/README.md` 把 `status=published` 与正式 App 下载元数据绑定；这是本地实现约束，若先上源码介绍站，需要明确调整相应状态定义和文案。只有确认要被搜索收录时才解除 `noindex`，不把它视为源码公开要求。

软件许可证与品牌身份是不同范围。OSI 说明，开源代码不自动授予他人使用项目商标/身份的权利。若希望限定 Quillside 标志的官方使用，应独立说明品牌使用政策和图形文件的授权范围；不要在 MIT 源码授权中添加禁止商用或禁止竞品的条件。[OSI FAQ：名称与标志](https://opensource.org/faq)

Apple 允许符合条件的兼容性文字引用，要求不造成官方背书或关联印象；Apple 自有图标与 Logo 则有独立限制。“用于 Apple Notes 的写作伴侣”应是兼容性描述，Quillside 应作为主产品名。当前品牌说明写明没有导入 Apple Notes 原始图标，但这不是图形商标检索或相似性审查结论。[Apple：商标与版权使用指南](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)

## 2026-10-13 本地观察与优先级

只读核对结果：`VERSION=0.7.3`；`git status --short --branch` 显示 main 尚无提交；`git remote -v` 为空。以下均未验证远程状态或重新执行构建：

1. **官网同步 Pi/Node 许可与隐私事实。** 根 `licenses/manifest.json` 管五个原有组件，独立 `licenses/pi-runtime/manifest.json` 已列出 48 个 Pi/Node 组件；`check-open-source.py` 调用专门检查器，`bundle-app.sh` 复制 PiRuntime 许可目录。不能据根清单只有五项就判漏审。当前真正需要处理的是 `site/build.py` 只复制根 `licenses/*.txt`，未复制独立 PiRuntime 目录；官网开源页未介绍 Pi，隐私页仍需要对齐实际凭据保存方式。已有分清单不等于本任务完成了全部依赖上游比对。
2. **决定公开范围并制作正式提交。** 审阅历史文档、截图与日志中的真实笔记、身份和凭据；已有忽略规则和历史静态扫描不能替代实际候选文件检查。正式源码导出要求干净提交属于项目已有脚本约束。
3. **同步对外文档。** `SECURITY.md` 仍写 0.6.x，而当前为 0.7.3；更新支持版本、正式入口与清楚的运行时构建说明。已存在 CI 文件不等于远程 CI 已通过。
4. **App 发行单独完成。** 已有文档明确本机证书不是 Developer ID，网站仍记录未公证。脚本为外层 App 配置 runtime/时间戳，但单独重签 Node 的命令未沿用这些参数，因此内嵌 Node 是发行路径的重点待验证项。没有在本任务读取任何私钥，也没有检查用户 Apple Developer 会员或发行证书，因此这些资格不能声称已确认。
5. **网站部署单独记录凭证。** 本地静态产物不等于公开站点。选择域名/托管之后核对实际 HTTPS、路径资源、真实仓库/下载链接和日志说明。

本记录只核对官方规则与有限本地状态，不复用旧报告中的“全许可通过”作为当前 0.7.3 的结论；也不把 logo 完成、官网生成或本机 codesign 成功解释为发行完成。
