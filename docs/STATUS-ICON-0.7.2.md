# 0.7.2 状态栏图标统一

2026-10-13，build 1。状态栏改用与0.7.1 Dock图标一致的整页便笺与羽毛笔构图，纸张轮廓、圆角、页眉高度及羽毛笔位置共用生成参数。

以单色外轮廓和页眉分隔线适配macOS模板着色，保留18×18pt逻辑尺寸与72×72px采样。整幅图形缩至82%，为轻跳、摆动及抗锯齿边缘留白。Dock图标的PNG和ICNS哈希保持不变。

验证：

- 现有4项`StatusIconAnimationTests`执行通过：23帧固定尺寸和透明边界、菜单跟踪时播放和复位、减少动态效果、菜单动作与权限限制。
- release构建、严格递归签名和包内许可证检查通过；已安装到`/Applications/Quillside.app`，关于页面显示0.7.2。
- 已核对安装后的`MenuBarTemplate.png`与源资产相同；浅色与深色的单色合成预览及18pt缩略图已视觉检查。
- 本机证据保存在`build/status-icon-0.7.2/`：`tests.log`、`comparison.png`与`animation.gif`。动图由实际`StatusIconAnimation`渲染器导出，是放大预览，不是系统菜单栏录像。

没有改变菜单逻辑或动画曲线，也未发起模型请求。图标生成方式见`resources/Brand/README.md`。
