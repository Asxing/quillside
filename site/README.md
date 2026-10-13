# Quillside Notes 官网

本地可预览的静态产品官网，使用标准 HTML、CSS、JavaScript 和 Python 标准库构建，无外部运行时依赖、远程字体或分析服务。设计参考 Magpie 的信息组织方式，文案和页面由本项目独立实现。

## 构建与预览

从仓库根目录运行：

```sh
python3 site/build.py
python3 site/check.py
python3 -m http.server 4173 --bind 127.0.0.1 --directory site/dist
```

访问 http://127.0.0.1:4173 。不要直接打开源模板；`site/dist/` 是完整可独立托管的构建产物。

## 多语言

当前提供English（`/en/`）、简体中文（`/zh-CN/`）、繁體中文（`/zh-TW/`），每种语言包含首页、指南、下载、隐私和开源五页。根路径五页默认使用英文，首次访问无需跳转或等待JavaScript翻译。语言菜单跳转到同一页面并保留当前位置；浏览器只保存用户手动选择的语言，访问根入口时恢复该选择。显式语言链接优先于保存的偏好。无JavaScript或存储不可用时，英文默认页面及各语言链接仍可使用。

HTML模板中的简体中文是翻译键，`locales/en.json`与`locales/zh-TW.json`维护译文；布局共用，不为每种语言复制HTML。`i18n.py`管理语言列表、文本/属性翻译和交互文案。缺少翻译会使构建失败。语言目录内采用相对链接，兼容部署到子目录；每页输出`lang`和对应页的`hreflang`。

`DEFAULT_LANGUAGE=en`决定网站入口语言；`SOURCE_LANGUAGE=zh-CN`决定翻译键和模型验收材料来源，两者独立。GitHub主README也使用英文，中文入口为根目录`README.zh-CN.md`。

`locales/*.examples.json`是中文验收材料的英文译文/繁体转写，页面明确标注它们不是另外一次模型实测。文件记录原始材料摘要，原始证据变化会要求重新审阅译文。原生App截图保留真实中文界面，并标明其语言；官网语言不代表App已完成同样的本地化。

新增语言时，在`i18n.py`的`LANGUAGES`中登记代码与本地名称，补齐消息和示例文件，再运行构建与检查。需另外检查长文字、导航和表格在手机端的呈现。`site/check.py`覆盖15个语言页面及5个根兼容页的链接、语言目标、交互数据与发布状态。

## 内容与来源

- `templates/index.html`：首页、原文批注网页示意、角色切换和快捷编辑示例。
- `content/*.html`：上手、下载、隐私、开源与反馈页面。
- `content/release.json`：公开发布状态、架构、兼容性、下载及仓库入口；应用版本从根目录 `VERSION` 读取。
- 三场景正文与角色 Prompt 从 `docs/real-agent-scenes-0.6.3.json` 选择性读取，只嵌入合成原文、Prompt、候选与说明，不嵌入模型服务地址、密钥或内部 ID。
- `assets/inline-result.png`：从 `build/inline-screenshots-0.6.3/inline-result.png` 复制的本项目原生 SwiftUI 组件渲染，使用 `tests/InlineAppearanceTests.swift` 中的合成文本。不是实际 Notes 录屏，也不是实时模型结果。
- `assets/app-icon.png`、`assets/brand-mark.png` / `.svg`：统一新版图标，构建时自动从 `resources/AppIcon-1024.png` 和 `resources/Brand/Quillside-Mark.*` 同步；页眉、页脚、下载页和 favicon 的资源 URL 带内容版本，避免旧图缓存。
- `licenses/pi-runtime/`：随官网构建复制Pi/Node的许可清单与原文，保持来源说明完整。
- 首页 Notes 窗口是用 HTML 编写的交互示意；没有调用系统 Notes，没有向模型发送请求。自定义批注只保留在网页内存中，预览结果为固定示例，不声称依照输入动态生成。

## 首次公开前

已确定官网先使用 **GitHub Pages 默认域名**，不需要购买域名或配置 DNS。项目站点的地址格式为 `https://<owner>.github.io/<repository>/`；实际地址以仓库归属与 Pages 部署结果为准。

`.github/workflows/pages.yml` 支持手动部署、默认分支CI成功后部署，以及Release流水线显式调用。检查通过后仅上传`site/dist/`，由官方Pages Actions部署。Actions固定提交SHA，构建与部署权限分开；PR本身不发布网站。部署始终检出默认分支的可信网站源码。

首次部署步骤：

1. 确定仓库归属与名称，完成公开内容审阅、首个提交和远程 CI。
2. 在仓库 **Settings → Pages → Build and deployment** 中选择 **GitHub Actions**。检查 `github-pages` 环境的部署分支限制与默认分支一致。
3. 等待默认分支CI通过后自动部署，或手动运行 **Deploy website to GitHub Pages**。发版流程在Release发布成功后显式调用同一工作流。
4. 取得 deploy job 给出的真实 `page_url`，检查三个语言目录、静态资源、许可文件、语言记忆与链接；随后把该地址填入仓库 About。

网站使用相对路径，语言切换也保留仓库子路径，不需要把源码改成根域名路径。构建包含 `.nojekyll`；不生成 `CNAME`。网站仍可先上线开发版介绍，App 的 `release.json` 在签名、公证和正式下载准备好前维持 `preview`，不会因为网页上线而启用下载按钮。

Actions通过`scripts/site-release.py`读取已经发布的GitHub版本与元数据，生成临时release.json并传入`site/build.py --release-metadata`。源码预发布只显示GitHub版本入口；未公证预发布显示专门标注的DMG/ZIP测试版按钮和SHA-256；具备正确DMG/校验值与公证回执资产的notarized稳定版才启用正式下载。不会回写源码配置或把预发布默认为正式下载。

GitHub Pages 会记录访问者 IP 用于安全；托管事实已同步到三种语言的隐私说明。已于2026-10-13部署至 https://asxing.github.io/quillside/ ，实际发布记录见`docs/releases/PUBLICATION-0.7.4.md`。参考：[GitHub Pages 地址与数据记录](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)、[官方部署工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。

当前 `status=preview`，所有页面 `noindex`，没有可下载开发包、虚假仓库地址或占位联系方式。产品主名为Quillside，官网展示为Quillside Notes；源码仓库与官网已公开，App仍为开发者预览。

1. 确定发布者、GitHub 归属及支持邮箱；官网已选择 GitHub Pages 默认地址。
2. 完成 Developer ID 签名、公证、干净机器安装及升级测试。
3. 更新经过验收的系统范围、真实下载地址、SHA-256、发布日期，填入仓库和联系渠道。
4. 将发布进度页中对应状态按证据更新，并完成最终隐私说明。实际部署时如产生服务器日志，要在隐私说明中说明。
5. `status=published` 构建会校验正式下载的基本元数据，但不能替代实际证书和 Gatekeeper 验证。公开时还需移除模板中的 `noindex`、配置正式 canonical / 分享 URL，核对页脚预览提示。
6. 先预览验收，再部署构建产物。中国与海外访问、下载速度需在实际托管位置确认。

后续如加入自动更新，复用同一发布记录。当前站点不具备账号、收费、云端 AI 或后台管理服务。
