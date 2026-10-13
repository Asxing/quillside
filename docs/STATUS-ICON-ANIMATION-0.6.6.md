# Quillside 0.6.6 菜单栏点击动画

2026-10-13。需求：像Magpie点击小喜鹊一样，让Quillside菜单栏标志有自己的短动画。

## 交互

- 点击菜单栏图标，原生菜单立即展开；标志轻压、上跳、摆动、回弹，约0.72秒后恢复静态。
- 图形使用Quillside自己的羽毛笔和便笺，没有复制Magpie的图片、动画帧或代码。
- 18×18pt逻辑画布保持不变，72×72px高分辨率模板图，系统自动处理浅色、深色与菜单选中状态的着色。
- 关闭菜单立即回到静态；连续打开不会叠加计时器。
- 尊重macOS“减少动态效果”：开启时跳过动画，播放中改变该设置也会停止。静止时无动画定时器。

## 实现

AppDelegate持有原生NSStatusItem和NSMenu。NSMenuDelegate.menuWillOpen触发动画，menuDidClose停止。点击、菜单定位、高亮和Command拖动继续由AppKit处理，不拦截全局鼠标事件。

StatusIconAnimation统一定义18pt画布、变换曲线与23个图像帧。StatusIconAnimator仅在播放期间每秒最多30次更新按钮图像，将计时器加入common及eventTracking模式，避免系统菜单跟踪时动画暂停。

原有菜单内容、快捷键和权限限制复用MenuBarContent及MenuBarCommands，AI、复制Markdown/链接、反链、诊断、设置和退出入口均保留。

SwiftUI使用不自动打开文稿窗口的Settings场景，设置命令仍指向原有SettingsWindowController。欢迎页由AppDelegate显式创建并在完成后关闭，兼容macOS14，无需更高系统版本的默认启动行为API。

## 验证

- 4项新增测试覆盖实际渲染帧、固定尺寸/透明边界、eventTracking模式下的播放与回到静态、减少动态效果及原生菜单命令/快捷键/权限限制。
- 256项回归中253项执行通过，3项因截图/实机数据库条件未启用而跳过。debug、release和严格签名检查通过，随包MIT许可检查通过。
- 已安装0.6.6构建1；本机窗口能打开设置、读取旧模型配置，显示没有运行中的AI任务。安装前后17个既有本地数据文件哈希一致。
- 本机首次展示了此前未完成标记的欢迎页，确认现有两项权限已授予后点击“开始使用”，完成标记并关闭欢迎页，没有重新请求权限。
- 同一渲染器导出23帧PNG和放大GIF，检查静止帧、上跳帧及无裁边。GIF是实际图像帧的放大演示，不是系统菜单栏录屏；实际程序只在打开菜单时播放。
- 电脑工具只能返回应用窗口截图，尚未取得系统菜单栏播放录像；用户随后确认“能看到动画，菜单正常”，实际点击的目视验收通过。

## 产物与回退

- 安装：/Applications/Quillside.app
- 旧版备份：build/status-animation-0.6.6/Quillside-0.6.5-backup.app
- 动图：build/status-animation-0.6.6/quillside-click.gif
- 测试日志：build/status-animation-0.6.6/regression.log
- 发布候选：build/Quillside-0.6.6-macOS-arm64.zip

本版没有改动模型、批注或写回逻辑，也没有发出新的模型请求。既有真实模型验收见0.6.5记录。本机开发签名包尚未Developer ID公证或公开发布。

## 参考

- [Magpie点击托盘动画实现](https://github.com/yetone/magpie/blob/main/internal/gui/app.go)：参考点击反馈的交互节奏。
- [Apple NSStatusItem.menu](https://developer.apple.com/documentation/appkit/nsstatusitem/menu)：系统处理状态栏菜单。
- [Apple RunLoop.Mode](https://developer.apple.com/documentation/foundation/runloop/mode)：菜单跟踪期间的定时器模式。
- [Apple Reduce Motion](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)：遵循系统减少动态效果设置。
