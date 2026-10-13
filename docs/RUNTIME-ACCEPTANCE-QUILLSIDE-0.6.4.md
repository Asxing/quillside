# Quillside 0.6.4 构建3：安装与运行验收

2026-10-12，本机 Apple silicon。用户要求启动验收，随后反馈顶部菜单栏图标过大。

## 菜单栏图标修复

复现检查：对已安装构建2的 MenuBarTemplate.png 使用 AppKit 读取，NSImage.size 为72×72pt，位图为72×72px。SwiftUI的18pt frame未在此路径上可靠约束原生状态栏图像。

修复：生成PNG时将 NSBitmapImageRep.size 设为18×18pt；运行时缓存一份NSImage，并明确设置size为18×18pt及isTemplate=true。去掉仅依靠resizable/frame的布局。位图仍为72×72px，保留高分辨率采样。Dock和关于页面图标没有调整尺寸。

对安装后的构建3重新执行同一检查，得到18×18pt、72×72px，通过。构建、签名验证及随包许可证核对通过。电脑截图工具本次仅返回应用窗口，未取得整个系统菜单栏截图；不把资源检查写成像素级屏幕验收。

## 已验证

- 已安装到 /Applications/Quillside.app，版本0.6.4、构建3，进程正常启动。
- 设置和关于页显示Quillside、新品牌图标与0.6.4；菜单项含Quit Quillside。
- 通用设置显示辅助功能、完全磁盘访问、Apple Notes自动化已授权。
- 原模型连接保留且可进入编辑；默认助手（原配置）、公众号、个人笔记、汇报四个Agent与humanizer-zh关联保留。
- 安装前后Application Support/OpenNotes的16个文件哈希全部一致。未读取或输出API Key。
- 使用专用笔记“Quillside 0.6.4 验收 20261012”执行/h1和/block。读回原生结构：标题验收为title；块引用文本blockQuote=true。
- 合成模型测试进入钥匙串读取；本轮未收到完成授权，已点击停止测试。设置显示没有运行中的AI任务，并提示笔记未改变。

## 本轮未确认

- 选区浮层的自动化定位未成功，未宣称已完成工具条、批注保留和AI写回/撤销的新一轮验收。
- 真实模型输出没有在本轮完成。历史0.6.3的验收记录仍只代表当时版本。
- 251项回归是此前构建2的结果；本次菜单栏尺寸修复执行的是针对性资源尺寸检查和release构建，没有重跑无关的AI测试。

## 本地证据与回退

- 结果：build/quillside-0.6.4/runtime-acceptance/results.json
- 构建：build/quillside-0.6.4/runtime-acceptance/build-3.log
- 尺寸检查：build/quillside-0.6.4/runtime-acceptance/check-menu-image.swift
- 数据核对：build/quillside-0.6.4/runtime-acceptance/data-comparison.json
- 旧版备份：build/quillside-0.6.4/AppleNotesPro-0.6.3-backup.app

这是本机开发签名安装，未完成Developer ID公证或公开发布。
