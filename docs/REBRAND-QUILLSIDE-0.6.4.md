# Quillside 0.6.4：名称与品牌图形

2026-10-12。用户确定产品主名为 Quillside，官网附带 Notes；要求羽毛笔结合 Notes 笔记图形。

## 已完成

- Swift Package、可执行文件、App 名称、当前界面与开发脚本统一为 Quillside。活跃源码移至 src/Quillside。
- 官网导航、页脚和页面标题展示 Quillside Notes；使用说明中的软件名称为 Quillside，Apple Notes 仅作为兼容对象描述。
- 生成羽毛笔与便笺设计参考，再编写矢量母版，导出透明 Logo、主名字标、官网组合、App 图标和单色菜单栏模板。
- 版本0.6.4，构建号3（修正菜单栏图标逻辑尺寸）；增加独立 BUILD_NUMBER，避免此前构建号长期固定为1。
- 项目版权新增 Quillside 当前名称，保留 AppleNotesPro 和 NotesPlus 原有版权，以及五项组件的MIT许可。

## 数据与旧名称兼容

bundle ID 继续使用 com.opennotes.app；Keychain service、UserDefaults 标识、Application Support/OpenNotes 与已有配置/批注/反链历史保留。AppleNotesProtobufLinkParser 是 Apple Notes 的 Protobuf 解析器，类名并非旧品牌，未被错误替换。

反链同时识别 OpenNotes、AppleNotesPro 和 Quillside 三代标题。旧记录的 headingText 原样保留；只有用户主动更新生成区域时才使用新标题，不在改名时自动修改笔记正文。新增回归覆盖旧AppleNotesPro区域读取、局部替换、未知标记拒绝和来源标题冲突保护。

历史版本文档保留当时名称，只修复指向当前源码的路径。官网三个角色的例文仍明确标为0.6.3真实模型验收，没有将其改写为0.6.4新实测。

## 验证与边界

- 251项回归，248项执行通过，3项因截图/实机数据库环境未启用而跳过；debug和release构建通过。
- Quillside.app 已使用既有本机开发身份签名，严格codesign和随包MIT许可核对通过。不是Developer ID公证发行包。
- 图标母版生成、1024PNG与ICNS、72PNG菜单模板通过；官网五页面构建与链接检查通过。
- 浏览器实际查看了品牌版面、16/24/32像素显示与深色单色模板，修正窄视口横向溢出；官网名称与图标资源已加载。
- 16个既有本地数据文件改名前后哈希一致。未读取或输出API Key。
- 只读比较旧安装包与新构建：辅助功能、完全磁盘访问记录均匹配签名；AppleEvents记录在旧版和新版均存在既有签名不匹配。该项未在本轮重新授权或进行真实Notes自动化写回，不将静态检查当成全部权限可用。

已安装并启动 `/Applications/Quillside.app` 0.6.4（构建3）。原0.6.3安装保留于 `build/quillside-0.6.4/AppleNotesPro-0.6.3-backup.app`。安装后的验证见 [运行验收记录](RUNTIME-ACCEPTANCE-QUILLSIDE-0.6.4.md)；本轮未完成AI写回验收。

## 产物

- [品牌文件说明](../resources/Brand/README.md)
- 矢量主标志：resources/Brand/Quillside-Mark.svg
- 应用图标：resources/Brand/Quillside-AppIcon.png、resources/AppIcon.icns
- 品牌版面截图：build/quillside-0.6.4/brand-board.jpg
- 官网截图：build/quillside-0.6.4/website.jpg

未购买域名、提交商标注册、创建远程仓库或公开网站。Quillside与相近名称/图形的最终商标核验仍是公开前事项。
