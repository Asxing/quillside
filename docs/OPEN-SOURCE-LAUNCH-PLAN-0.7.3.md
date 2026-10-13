# Quillside 0.7.3 开源首发盘点与执行计划

核查日期：2026-10-13。基于当前工作区、实际构建产物、干净源码快照和官方公开文档。目标是让外部用户看得懂、开发者构建得出、问题有地方反馈。源码公开、App 下载和官网上线分别验收。

后续更新（同日）：官网已实现简体中文、繁體中文、English 三语言与15个本地化页面；同时修正官网Pi凭据保存说明、增加Pi/订阅登录介绍、补齐网站Pi/Node许可目录。见[多语言实施记录](WEBSITE-LANGUAGES-2026-10-13.md)。下文审计表保留发现时的状态；README、应用开发指南、远程仓库和正式发行事项仍需按批次推进。

托管决定（同日）：用户已选择 GitHub Pages 默认地址。部署工作流已在`.github/workflows/pages.yml`准备，首次手动从默认分支发布，只上传网站产物。GitHub连接显示当前账号为`Asxing`，但项目仓库归属/名称尚未确定，当前无remote，因此未填写或宣称任何线上地址。详见`site/README.md`的首次部署步骤。

实施更新（同日，0.7.4）：用户已确认个人账号，按`Asxing/quillside`准备发布。中文/英文README、当前文档导航/隐私/构建/架构、路径误报修复与锁文件刷新已完成，标签自动发版及Pages联动已实现，本地回归通过。下文“待办”保留审计时状态，当前实现与发布边界见`docs/development/RELEASING.md`和根`VERIFICATION.md`。远程仓库、CI和部署以实际回执为准。

## 结论

核心产品与品牌已有可交付基础，当前最值得做的是开源包装与发行收尾，不需要为首发重做功能、换技术栈或重画 Logo。

建议先发布 **MIT 源码 + 开发者预览**，随后开放经过签名、公证及新环境验收的 App 下载。源码首发无需等到 App 公证或完整官网；官网下载阶段则不能把本机开发签名包当成正式安装包。官方依据见[公开发行要求](research/OPEN-SOURCE-REQUIREMENTS-2026-10-13.md)。

## 当前状态

| 领域 | 本轮确认 | 还缺什么 |
|---|---|---|
| Git 仓库 | 已初始化；当前 main 无 HEAD、无 remote，文件尚未进入首个提交 | 确定归属、审阅公开范围、首个提交、远程仓库与标签 |
| 产品代码 | 97个原生Swift文件；App/Features/Services/AI/Agents/Skills 已有职责划分；Pi 在 runtime/pi | 当前架构说明、首次构建说明、清理或标记未使用的旧实现 |
| 构建与回归 | 干净源码快照完成Pi安装/构建、原生回归和临时签名App打包 | CI固定运行时环境、远程首次跑通、跨系统和新用户验证 |
| MIT 与上游 | 根MIT保留NotesPlus版权；五个原有组件与48个Pi/Node组件有分开清单；App内许可校验通过 | 官网的Pi说明与许可目录补齐，正式发布包再次核对 |
| Logo | Dock、菜单栏、设置、欢迎页、网站与字标已经统一；同源生成，彩色PNG内容一致 | 补简短对外品牌使用说明；未来印刷/商标图样按需固定字形 |
| README/文档 | 大量实现与验收证据保留 | README过于像开发流水账；当前说明仍指向旧版本；缺集中开发/用户入口 |
| 官网 | 五个静态页面、交互演示、统一Logo与构建检查已有 | Pi/订阅登录/凭据说明、正式地址、维护者联系方式、真实仓库/下载入口 |
| 安装包 | 本机0.7.3可用，签名为OpenNotes Local Development | Developer ID、公证、嵌入Node的发行签名、新机器下载安装与升级验收 |
| 社区 | CONTRIBUTING、SECURITY、行为准则、Issue/PR模板、CI已存在 | 远程启用安全报告、必需检查与分支规则；明确维护入口 |

## 源码公开前优先完成

### 1. 把 README 改成外部使用入口

保留当前产品定位，建议第一屏只包含：Logo、Quillside名称、一句话用途、当前发布状态、核心截图/GIF、安装/源码/文档入口。随后是核心功能、系统要求、快速上手、开发构建、权限与隐私、贡献及来源。

具体内容：

- 用“在 Apple Notes 原文中批注、统一优化、确认写回”解释独特用途。
- 以3–5项核心能力呈现：原文批注、快捷AI、Agent Prompt+Skill、Slash/编辑工具、正文反链。
- 技术说明写“SwiftUI/AppKit原生界面，内嵌Pi与Node运行时”。用户安装包不要求另装Node；开发者构建需要Node/npm。
- 旧版本连续说明移到CHANGELOG或版本文档，保留原证据链接，避免读者先读几屏历史才能找到安装方法。
- 若首发面向国际开发者，增加中英文README；这属于传播优化，不是MIT的强制条件。
- 仍需真实当前版本演示：选区 → 两处批注 → 整体意见 → 候选 → 写回 → 撤销。现有网站交互示意可保留“示例”标签。

### 2. 整理文档导航，保留现有代码模块

当前模块拆分足够支撑首发，不建议为了公开而大规模重构。建议以如下目录职责收敛，按批次移动并修复链接：

```text
src/Quillside/          原生应用：App、Features、Services、AI、Agents、Skills
runtime/pi/            Pi桥接、版本锁与运行时测试
resources/Brand/       唯一品牌图形来源与生成规范
resources/Skills/      随包技能及其来源/许可
tests/                 合成验收与可选实机用例
site/                  官网源码、发布数据与构建
docs/
  user/                安装、权限、模型、批注、FAQ
  development/         构建、架构、数据流、贡献与测试
  releases/            变更与当前验收结果
  research/            可公开研究资料
  archive/             明确标为历史的设计、比较与验收
licenses/              上游版权与Pi/Node独立清单
scripts/               构建、验证、品牌导出、发行
.github/               CI、模板与依赖更新
```

当前有101个docs文件和19个legacy文件，问题在于导航与当前口径，而非体积大（被测候选源码合计约3.9MB）。历史记录不必全部删除，也不应继续承担“当前使用指南”的职责。

已发现的具体过期入口：

- `VERIFICATION.md`标题仍为AppleNotesPro 0.6.3。
- `docs/CURRENT-FEATURES.md`最近主要更新为0.6.3，表格还混有0.3.x待验状态。
- `DESIGN.md`仍以0.3.8为视觉基线；应指向0.6.7统一主题与0.7.3品牌。
- `SECURITY.md`仍写0.6.x开发版本。
- `docs/source-inventory.json`仍列`src/AppleNotesPro/`旧路径。
- `docs/images/settings-0.3.0.png`仍展示OpenNotes与旧设置结构，适合放历史资料，不应作为当前宣传截图。

`com.opennotes.app`、旧数据目录与Keychain服务名是升级兼容标识，不能为了视觉改名直接替换。`ModelClient`旧发送实现值得单独审查；`WritingSession`部分仍被原文批注复用，不能按目录名称直接删除。

### 3. 修正构建说明与贡献者环境

`CONTRIBUTING.md`目前只在网站语法检查处提Node 20+；实际`runtime/pi/package.json`要求Node >=22.19.0，构建和测试都会运行npm与Node。需明确Swift、Python、Node/npm、ripgrep要求，并给一条从clone到构建App的完整路径。

建议CI显式固定Node版本并使用锁文件。已有CI定义尚未在远程runner执行，不能据本机通过就显示“CI已通过”徽章。Dependabot目前只配置GitHub Actions，可补npm和Swift依赖更新审阅流程。

本轮发现一个可复现脚本问题：`scripts/check-open-source.py`使用绝对路径的`path.parts`判断是否位于`build`等生成目录。将仓库放在名称含`build`的父目录下时，所有正常源码会被误报。应改为检查仓库内的相对路径。本轮将测试快照移到独立临时目录后，原命令通过；未把第一次误报解释为源码真的含生成文件。

另外，`prepare-pi-runtime.py`仅在node_modules不存在时执行npm ci，依赖锁更新后的旧安装目录可能未重建；后续应按锁文件变化刷新。截图脚本也应跟随统一的Swift Testing启动参数，避免只编译却没有实际执行截图用例。

### 4. 校准隐私与来源说明

这是公开前应优先修正的事实错误：

- 官网首页、指南和隐私页仍称API Key存入macOS钥匙串。
- 实际新Pi连接由`AuthStorage`写入本应用独立的`OpenNotes/Pi/auth.json`，包括API Key或OAuth凭据；旧兼容连接继续走Keychain。
- 文案需分别说明保存方式、退出授权、卸载后残留与清理入口。保留现有“不自动搜索其他笔记、主动生成才发送、取消不能撤回远端已接收内容”的边界。
- 官网开源页列出了NotesPlus、NotesBridge、Yams/LibYAML和Humanizer，却没有Pi/Node；首页技术说明也未完整解释内嵌运行时。
- `site/build.py`只复制根目录`licenses/*.txt`；`site/dist/licenses/pi-runtime/`不存在。App已经包含这部分许可，但网站关于“完整许可”的展示与承诺需要补齐。

源码继续MIT，上游版权仍保留在LICENSE、THIRD_PARTY_NOTICES和许可目录。Pi/Node依赖分别遵循MIT、Apache-2.0、BSD、ISC、Unlicense等自身条款，不能宣传成所有依赖都只有MIT。[MIT正文](https://opensource.org/license/mit)

## Logo 与官网还需要什么

Logo本身已经完成统一，不列入重新设计事项。已有SVG、1024PNG、ICNS、18pt菜单栏模板、明暗适配、动画留白与可重复生成脚本。

对外品牌包建议补足：用途/尺寸/背景的简短规范、带名字的横向组合、社交分享图、官网OG图；如果希望规定官方品牌身份的使用方式，单独写品牌说明，不修改MIT的软件授权。现有SVG字标依赖系统字体，跨平台会替换；转固定路径属于印刷或商标图样准备，可后续做。图形完成不等于商标注册已完成，源码公开也不必等待注册。

官网建议按此顺序收尾：

1. 更新Pi、API Key与ChatGPT订阅登录说明，区分订阅额度和API账户额度，不承诺所有账户/地区/模型都可用。
2. 更新当前版本的真实产品截图；现有0.6.3示例可作为明确标注的历史验收材料。
3. 配置真实GitHub、支持入口；源码公开状态与App可下载状态分别表达。
4. 决定托管。首次可用GitHub Pages的默认地址，自定义域名非必要；选定托管后补访问日志说明。[GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
5. 正式开放索引时再配置canonical、OG图、sitemap和robots；当前noindex是预览状态，不是资源故障。
6. 验收HTTPS、手机/桌面、真实入口和中国/海外网络下的页面与下载可达性。

继续借鉴Magpie的内容顺序、真实演示、清楚的下载/源码/文档入口即可。首发维持一个仓库承载代码、官网与Release，不必先复制其双发布仓库、赞助体系或社区平台。

## 普通用户下载 App 前另行完成

当前安装版本为0.7.3，签名身份是本机开发证书，TeamIdentifier未设置。已有DMG、公证脚本，但不等于已经取得正式发行结果。

需要：

1. Apple Developer归属与Developer ID Application签名身份、公证权限。
2. 修正并实测嵌入Node的发行签名：当前外层App可加`--options runtime --timestamp`，Node的单独重签命令未沿用这些参数。核对其最小必要JIT entitlement，避免不必要地放宽权限。[Apple公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[Apple JIT entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit)
3. 取得实际公证Accepted结果及staple ticket，核对最终包的版本、架构和SHA-256。
4. 从浏览器下载最终包，在没有旧开发授权的新用户或另一台Mac上首次启动；走正常Gatekeeper和权限流程。
5. 验收选区、批注保留、真实模型、写回/一次撤销、取消、退出及升级配置保留。
6. 首发如只实测Apple Silicon，就只提供该架构，并区分最低构建目标与实际已测系统。Intel、多语言Notes、IME、多显示器等按覆盖结果声明。

自动更新、App Store、收费、云端账号、遥测、MCP/Tools、知识库和完整导入导出均不应成为此次源码首发的前置条件。

## 推荐执行批次与验收条件

| 批次 | 动作 | 完成条件 | 依赖用户信息 |
|---|---|---|---|
| A：整理公开内容 | README、当前功能/架构/验证、指南与隐私、Pi许可网站同步、公开文件分类 | 读者能找到当前说明，事实与0.7.3实现相符 | 无 |
| B：构建收尾 | 修复路径误报，补Node/npm要求与CI固定版本，独立快照复验 | 按贡献指南从无项目缓存开始构建和回归成功 | 无 |
| C：源码首发 | 首个提交、远程仓库、公开标签、源码Release、Issue与私密报告、必需检查 | 真实公开链接、远程CI成功、标签可复现 | GitHub归属、仓库名、维护者联系入口 |
| D：官网上线 | 部署五页站点、真实GitHub/支持入口、版本状态与托管说明 | 实际HTTPS访问与链接验收通过 | 托管归属；域名可选 |
| E：App发行 | Developer ID、Node嵌套签名、公证、新用户安装/升级、真实Notes验收 | 可下载最终包通过完整验收，再启用下载按钮 | Developer Program/发行身份及可用测试环境 |

建议社区先接受问题报告、文档改进和可复现修复；较大功能先通过Issue对齐范围。暂不承诺固定响应时限，不需要一开始就建立Discord或赞助平台。

## 用户需要确定的最少信息

- **GitHub归属**：个人账号还是组织；建议仓库名`quillside`。
- **维护者身份与联系入口**：公开署名、支持邮箱或长期维护的联系渠道。
- **官网归属**：先用GitHub Pages默认地址，或使用已有域名/托管账号。域名是否可注册需在选择时重新查询。
- **若同步发布App下载**：Apple Developer会员与Developer ID是否就绪，以及可用于首次安装验收的另一台Mac或干净用户。

不需要在聊天里提供任何账户密码、API Key、签名私钥或OAuth令牌。发布账户上的授权使用各自正规流程。

## 本轮已执行的核查与证据

- 被测快照包含406个拟公开文件，未复制项目`.build`、`node_modules`或用户配置；在独立临时目录建立本地Git快照进行构建。没有读取个人Notes或模型凭据。
- `./scripts/verify-stage1.sh`完成：Pi集成8项通过；Swift runner报告261项，其中257项执行通过、4项因截图/真实数据库条件跳过；debug构建成功。仍有actor隔离、弃用API等告警，不能称为无告警构建。
- 独立快照临时签名App打包成功，包内项目与第三方许可检查通过。此包用于构建验收，没有安装替换用户应用，也不是Developer ID发行包。
- `check-open-source.py --online`通过：五份原有组件许可与固定上游文本一致；Pi/Node的48项清单通过锁文件/notice哈希核对。没有在本轮逐个重新从上游下载48份许可。
- 当前生产依赖`npm audit --omit=dev`返回0项已知漏洞；这不覆盖源码逻辑、所有历史漏洞或未来公告。
- 当前拟公开文本未命中脚本选定的私钥/Token/凭据字面量规则；额外路径扫描未发现个人用户绝对路径或已选私有地址模式。静态规则不是完整泄露审计，历史文档与图片仍需按公开范围审阅。
- 官网五页链接、图片、锚点、状态及JavaScript语法检查通过；Logo资源一致性检查通过。旧页面中的事实错误由人工对照实现发现，链接检查不会捕获这些错误。
- 当前没有Git HEAD、remote或远程CI结果；本轮没有公开仓库、部署官网或提交公证。

日志保存在忽略目录`build/open-source-audit-0.7.3/`：`clean-regression.log`、`clean-bundle.log`、`license-online.log`、`npm-audit.json`、`source-inventory.json`。官方规范与规则边界另见[研究记录](research/OPEN-SOURCE-REQUIREMENTS-2026-10-13.md)。
