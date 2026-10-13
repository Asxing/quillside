# Quillside 品牌图形

2026-10-12。产品主名：**Quillside**；官网组合：**Quillside Notes**。图形由羽毛笔、暖金色便笺和两条短横线组成，使用原创轮廓表达 Notes 写作增强。

## 交付资产

- `Quillside-Mark.svg` / `Quillside-Mark.png`：统一主标志，与 App 图标共用完整便笺图形，圆角区域以外透明；用于设置页、欢迎页与官网。
- `Quillside-Wordmark.svg`：主名组合。
- `Quillside-Notes-Lockup.svg`：官网组合。
- `Quillside-AppIcon.svg` / `Quillside-AppIcon.png`：App 图标矢量版 / 1024×1024 位图；ICNS 位于上级 `AppIcon.icns`。
- `Quillside-Monochrome.png`：与 App 图标共用便笺轮廓和羽毛笔构图的透明单色图形。
- `MenuBarTemplate.png`：上述单色图形的72×72 alpha 模板，图片元数据和 NSImage 均明确设为18×18pt，跟随系统前景色；72px仅用于高分辨率采样，不作为状态栏布局尺寸。
- `mark.json`：羽毛笔、镂空与便笺横线的矢量路径母版；纸张与页眉共用 `generate-icon.swift` 中的尺寸。所有生产图形由该脚本和 `scripts/create-icon.sh` 导出，旧小便笺路径已移除。

## 设计约定

色板：墨色 #2B3028、暖金 #D6AA45、纸白 #FFFDF7。主标志保持留白、长宽比例与羽毛笔尖，不额外叠加 Apple 标志或“官方”字样。图形图案与原生 Notes 的便笺联想结合；没有导入 Apple Notes 原始图标文件。

App 图标采用单层便笺：纸张本身铺满圆角图标，金色页眉延伸至纸张两侧，羽毛笔直接叠在纸张上，不再把小便笺放进第二层底板。1024 画布保留 82px 外侧透明空间，用于 Dock 与其他 macOS 图标对齐；这不是内层边框。App 图标底板的尺寸由 `generate-icon.swift` 定义，羽毛笔仍共用 `mark.json`。

状态栏与 App 图标共用纸张尺寸、圆角、页眉位置和羽毛笔相对位置，以单色轮廓和页眉分隔线表达同一构图。原生模板随菜单栏深浅色及选中状态着色。整体额外缩至82%，为现有18pt画布中的轻跳和摆动留出空间；外轮廓按小尺寸显示加粗，不新增嵌套边框。

设置页、欢迎页、主标志、应用图标、字标与官网组合使用同一个完整便笺图形。`Quillside-Mark.png` 与 `Quillside-AppIcon.png`、`AppIcon-1024.png` 内容一致，两个独立 SVG 也内容一致；字标只添加文字和整体缩放。`site/build.py` 自动同步官网资源，并为页面中的图标 URL 添加内容版本，避免浏览器继续显示旧图。

SVG 将原生绘图颜色显式转换为 sRGB，与既有 PNG 的色彩管理结果对齐。网页对应色为墨色 #393E35、暖金 #DFB756、纸白 #FFFDF9，避免同一个图形在 PNG 与 SVG 中出现色差；原生 PNG 外观保持不变。

SVG字标使用系统无衬线字体，跨系统字体替换可能影响字宽；图形母版本身是固定矢量路径。需要用于正式印刷或商标图样递交时，可在选定字体和尺寸后再制作固定字形版本。

当前交付是品牌图形设计，不代表已注册商标，也不承诺完成相同或近似图形商标清查。MIT与第三方许可证继续保留；软件许可证不代表 Apple 对本产品的授权。

## 生成与制作来源

先用内置 imagegen 工具生成位图构图参考，之后根据羽毛笔/便笺结构编写确定的矢量路径，清理边缘并生成小尺寸版本。生产资产不依赖临时生成目录。构图参考保留在本地忽略目录 `build/quillside-0.6.4/design-exploration/`。

构图提示词（内置工具，透明背景）：

```text
Use case: logo-brand. Asset type: production transparent brand symbol for Quillside, a native macOS writing companion used inside Apple Notes. Create ONE original centered symbol on a square canvas, with real transparent background. Combine a feather quill pen and a small note sheet. The note sheet has a warm ivory body, softly rounded corners, a narrow warm golden-yellow top tab and two short subtle ruled lines at lower left, evoking a familiar Notes pad. An elegant bold charcoal quill crosses the sheet diagonally from lower left toward upper right; its pointed nib and curved stem subtly hint at a Q, without spelling any letter. Distinct original geometry, not a tracing of the Apple Notes icon and no Apple logo. Flat vector-like shapes, precise edges, minimal detail, strong recognizable silhouette, readable at small menu-bar size. Use charcoal #2B3028, muted golden yellow #D6AA45, and warm ivory #FFFDF7. The feather should be the visual focus, with only one clean internal negative-space spine and very few cuts. Occupy about 78 percent of canvas, generous transparent margins. No text, no wordmark, no gradients, no 3D, no drop shadows, no background scene, no presentation board, no watermark. This is a single isolated brand mark ready for a website header or an app icon.
```

修整参考稿提示词（内置工具，透明背景）：

```text
Use case: precise-object-edit / logo-brand. This provided image is the Quillside brand mark and the edit target. Refine it into a production-quality FLAT logo on a genuinely transparent background. Preserve the existing concept, arrangement, warm-gold note header, ivory rounded note sheet, two short horizontal note lines, and charcoal diagonal feather quill with its pointed pen nib. Make the outer paper contour perfectly clean and smooth: remove every ragged paper fringe, stray white pixel, fuzzy halo and uneven edge around the bottom and sides. Make all fills solid and uniform, no texture, no gradient, no light shading. Preserve the elegant feather silhouette and two inner cuts. Use fewer fine details at the nib so it survives at 32px. Center the complete emblem including the quill tip with generous empty margins; nothing touches the canvas edges. A single isolated symbol, no text, no words, no mockup, no background tile. Transparent alpha must remain outside the symbol.
```

矢量母版与导出的实际尺寸检查以当前文件为准。上面的早期构图提示词是历史参考，当前生产图形由 `mark.json` 与 `generate-icon.swift` 中共享的整页便笺几何共同定义。


## 开源项目中的使用

图形用于识别Quillside项目。引用、介绍或贡献页面可使用原始图形并链接项目来源；不要以变体冒充官方发行或暗示Apple背书。此说明不增加MIT软件授权的使用、商用或修改限制，也不表示商标已经注册。
