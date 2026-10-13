# AppleNotesPro 品牌与升级兼容

2026-10-09，0.3.7。用户指定产品名为AppleNotesPro，主要对标ProNotes。产品界面、关于页和README不再展示NotesPlus开源介绍；第三方版权与许可声明保留在LICENSE、THIRD_PARTY_NOTICES.md和App的Resources/Licenses目录，不作为产品宣传内容。

## 改名范围

应用包/进程/Swift模块：AppleNotesPro；安装路径：/Applications/AppleNotesPro.app。活跃源码位于src/AppleNotesPro，图标字样由ON改为ANP，配置导出默认名称为AppleNotesPro-settings.json。欢迎、设置、菜单、退出、权限和诊断文案统一。旧应用从Applications移出，备份在开发目录build/OpenNotes-0.3.6-before-branding.app。

## 升级兼容

bundle ID继续为com.opennotes.app，沿用专用签名证书；API Key服务名、UserDefaults键、Application Support/OpenNotes数据目录和窗口状态键保留。这些是既有数据/授权标识，不是界面品牌。用户无需重新建立模型连接或重授辅助功能/FDA。现有配置和反链历史文件的改名前后指纹完全相同。

BacklinkDocumentRegion增加可选headingText。历史记录没有此字段时使用旧标题，以精确识别已有生成区；新生成或主动更新使用“引用此笔记 · AppleNotesPro”。更新替换原区域，保留用户正文，部分覆盖保留旧来源，历史版本继续支持撤销和生成边排除。不在改名安装时自动修改用户笔记。

## 验证

新增回归覆盖旧JSON加载、旧反链范围识别、只替换生成区、保留来源、用户正文/emoji不变、新记录再解码。193项中192执行通过、1项旧宣传截图跳过。实机确认系统菜单、设置/关于新名称、三项权限正常、原模型载入。未改变0.3.6功能与性能边界。
