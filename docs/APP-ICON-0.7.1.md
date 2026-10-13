# 0.7.1 应用图标调整

2026-10-13，build 1。

原图标把透明品牌标志放在一块圆角底板上，便笺与底板形成两层轮廓。新版将纸张本身作为唯一圆角底图：金色页眉铺满纸张宽度，羽毛笔直接叠在纸张上。保持原有外部尺寸和透明留白，并让笔尖收在圆角轮廓内。

## 资产

- `scripts/generate-icon.swift` 生成单层 App 图标与对应 SVG；羽毛笔共用 `resources/Brand/mark.json` 的矢量路径。
- `resources/AppIcon.icns` 包含 16–1024px、普通及 Retina 图像表示。
- `resources/Brand/Quillside-AppIcon.svg` / `.png` 为可复用资产；官网 `site/assets/app-icon.png` 与生产 PNG 相同。
- 透明品牌标志和状态栏模板的 SHA-256 与调整前一致，状态栏动画未改动。

## 验证

- 图标生成成功，ICNS 的 11 个图像表示均为尺寸正确的 PNG。
- 1024px 主图与 32px、64px 缩略图已人工视觉检查，无内层便笺边框，羽毛笔可辨认。
- release 构建、严格递归签名验证、安装包许可证检查与官网 5 页检查通过。
- 已安装到 `/Applications/Quillside.app`，应用“关于”及 Finder 信息面板均显示 0.7.1。
- Finder 实际预览已显示新图标。电脑控制工具无法独立获取 Dock 窗口，因此没有将 Dock 全屏截图列为已验证项。

本机证据位于忽略目录 `build/icon-refresh-0.7.1/`：`comparison.png` 是新旧资产对比，`finder-installed.jpg` 是系统实际预览。此次仅更新图形资源和版本信息，未重复发起真实模型请求。
