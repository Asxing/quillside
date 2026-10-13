# MIT 开源与仓库规范核查

日期：2026-10-12。范围：当前工作区、拟纳入 Git 的文件、明确记录的第三方组件与新生成的开发包。不是远程 GitHub 设置验收，也不将自动检测通过解释为完整安全或法律审计。

## 结论

项目以 MIT 开放。根目录采用标准 MIT 授权与免责正文，保留 NotesPlus 原始版权，并注明本项目修改和新增模块的版权。MIT 允许使用、修改、商用及再分发，也允许闭源衍生；分发副本或实质部分时须保留版权和许可声明。不能在宣称标准 MIT 的同时加上禁止商用、禁止竞品或强制公开全部修改的限制。[OSI MIT 正文](https://opensource.org/license/mit)

仓库推荐规范与许可证义务是不同的要求。贡献指南、行为准则、安全报告说明和模板有助于协作，但不会改变 MIT 授权。[GitHub 社区规范说明](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories)

## 本轮修复与补齐

| 项目 | 结果 |
|---|---|
| 根许可证 | 整理成 MIT 标题、项目与上游版权、标准授权与免责正文。保留 NotesPlus 的完整原始许可副本 |
| 第三方直接来源 | NotesPlus、NotesBridge、Yams、Humanizer-zh 的许可逐项比对固定上游文本 |
| 间接依赖 | 发现 Yams 构建了内部 CYaml，但原分发遗漏 LibYAML 独立许可；现已补齐其版权和 MIT 文本 |
| 许可清单 | 新增 `licenses/manifest.json`，记录组件、使用范围、固定来源和 SHA-256 |
| App 与官网分发 | App 复制全部五份组件许可、项目许可、第三方说明与清单；Skill 内也保留原许可证。官网许可目录同步包含五份组件文本 |
| 社区规范 | 新增 CONTRIBUTING、SECURITY、CODE_OF_CONDUCT、Issue 与 PR 模板 |
| 开发约定 | 新增 EditorConfig 和 Git 文本/二进制属性；增加证书、凭据、环境配置、数据库、日志与生成包的忽略规则 |
| 自动化 | 新增 macOS 原生回归与 Linux 仓库/网站检查工作流；Action 固定 SHA、只读仓库权限、不保存 checkout 凭据；不向普通 PR 提供签名秘密 |
| 回归资源 | 将 `tests/Fixtures` 声明为 SwiftPM 测试资源，用 Bundle.module 读取，去掉对源文件绝对位置的依赖 |
| 源码包 | 新增可核验的源码导出脚本；正式包要求已提交且干净的 Git 状态；本地未提交快照只能显式生成 `source-preview.zip` |

LibYAML 的许可来源是 Yams 变更记录中引用的上游 `acd6f6f`。该条记录用于证明许可来源，不把它误报为 Yams 6.0.2 内全部 C 文件的精确版本。Yams 自身 README 明确其与 LibYAML 均采用 MIT。[Yams 固定 README](https://github.com/jpsim/Yams/blob/f4d4d6827d36092d151ad7f6fef1991c1b7192f6/README.md)、[LibYAML 许可](https://github.com/yaml/libyaml/blob/acd6f6f/License)

## 验证结果

- `python3 scripts/check-open-source.py --online`：全部五份组件许可证与固定上游内容逐字一致；根 MIT 授权正文与原始标准文本一致，原版权未丢失。
- 当前拟提交文件中的私钥、常见厂商 Token、JSON 凭据字面量检测没有命中。检测仅覆盖选定规则和文本，不分析图片中的文字，也不声称覆盖全部凭据形式。
- `./scripts/verify-stage1.sh`：250 项测试，247 项执行通过，3 项因未配置实机数据库/截图环境而跳过；原生 debug 编译通过。既有 actor 隔离告警仍存在，不宣称无警告构建。
- `OPENNOTES_CODE_SIGN_IDENTITY=- ./scripts/bundle-app.sh debug`：生成本地开发包，严格 codesign 验证通过。临时签名仅用于此次检查，不是 Developer ID 正式发行。
- `python3 scripts/check-open-source.py --bundle build/AppleNotesPro.app`：根许可、五份组件许可、声明、清单与 Skill 许可实际进入 App 且与源码一致。
- 官网构建与五页面资源/链接检查通过。YAML 文件通过本地解析；GitHub 工作流还未在远程 runner 执行。
- 在临时仓库强行加入被忽略的 `.env`，检测正确失败；在临时 App 中移除 LibYAML 许可，包检查正确失败；在当前未提交仓库执行正式源码导出，脚本正确拒绝。没有修改用户凭据或系统权限。

## 公开前仍要完成

1. **首个正式 Git 提交与远程仓库。** 当前还没有 HEAD 或 remote。审阅历史调研、验收文档与截图的公开范围，再建立初始提交、标签和源码 Release。
2. **远程首次 CI。** 发布到 GitHub 后观察两个工作流任务实际结果，再设置主分支保护、PR 审查和必需检查；本地执行不替代远程环境验证。
3. **私密报告渠道。** 维护者启用 GitHub 私密漏洞报告，并补齐正式联系渠道；SECURITY.md 已明确当前入口尚未启用。[GitHub 设置说明](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)
4. **凭据保护。** 根据远程仓库可用设置开启 Secret scanning / Push protection；首次公开前做最终文件和图片内容审阅。忽略规则不会自动保护被强行跟踪的文件。
5. **正式发行包。** Developer ID 签名、公证、干净机器安装与升级验收仍待完成。当前 `/Applications` 中的旧安装和此前生成的旧 ZIP 不会被本轮自动更新；公开时必须重新生成并核对完整许可。

MIT 不替代第三方商标、远程模型服务条款与隐私说明。正式对外名称及发布主体继续按发布方案确定。

## 可复用命令

```sh
python3 scripts/check-open-source.py
python3 scripts/check-open-source.py --online
./scripts/verify-stage1.sh
OPENNOTES_CODE_SIGN_IDENTITY=- ./scripts/bundle-app.sh debug
python3 scripts/check-open-source.py --bundle build/AppleNotesPro.app
python3 site/build.py
python3 site/check.py
python3 scripts/package-source.py --working-tree
# 正式源码包：完成审阅与提交，并确保工作区干净之后
python3 scripts/package-source.py
```

正式包与本地审阅快照均包含 SOURCE_MANIFEST.json 和单独的 ZIP SHA-256。不要将未提交快照描述为已发布的 Git 标签或完整的发行验收。
