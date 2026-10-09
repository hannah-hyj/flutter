# 设计文档：Flutter 可组合文本插件系统 (Composable Text Plugins in Flutter)

**作者**: Antigravity & User  
**状态**: 已实现原型 (`packages/flutter` + `examples/text_plugins`)  
**参考**: [Text-Plugins-One-Pager.md](Text-Plugins-One-Pager.md) | [英文原版文档](text_plugins_design_doc.md)

---

## 1. 问题背景与动机 (Problem Statement & Motivation)

Flutter 应用程序经常需要跨页面的横向文本能力，这些能力需要对整个页面或子树中的文本进行检查、装饰或附加交互：

1. **页面内查找 / 搜索高亮 (Find-in-Page / Search Highlighting)**：在分散的 [Text](widgets/text.dart)、[RichText](widgets/basic.dart) 和 [EditableText](widgets/editable_text.dart) (`TextField`) 组件中查找所有匹配项，绘制当前/非当前匹配高亮，并将当前匹配项平滑滚动到屏幕中央。
2. **实体与模式装饰 (Entity & Pattern Decoration)**：高亮股票代码（`GOOG`, `AAPL`）、标签 (Hashtag)、@提及 (Mentions) 或引用，并赋予其交互能力，而无需修改源字符串或要求调用方提前对 `TextSpan` 树进行分词处理。
3. **自动超链接识别 (Automatic Linkification)**：自动识别普通 [Text](widgets/text.dart) 或输入框组件中的 URL（`https://...`, `www....`），绘制链接下划线，并响应点击手势。
4. **实时内容提取与 SEO (Live Content & SEO Extraction)**：索引子树中可见的文本，生成 Schema.org JSON-LD 元数据、字数/阅读时间分析或搜索引擎抓取快照。

### 为什么自定义 `Text` 子类方案会失败？

过去，第三方软件包作者通常通过创建替代组件（如 `LinkifyText`, `SearchableText`, `ParsedText`）来解决这些问题。这种方案在实际项目中存在严重的局限性：

- **零可组合性 (Zero Composability)**：开发者无法在同一个段落上同时使用软件包 A 的 `LinkifyText` 和软件包 B 的 `StockTickerText`。
- **侵入性重构 (Invasive Refactoring)**：必须替换应用中的每一个 [Text](widgets/text.dart) 组件——包括嵌套在第三方组件或 Material/Cupertino 组件（如 [ListTile](material/list_tile.dart), [Card](material/card.dart), [DataTable](material/data_table.dart)）内部的文本。
- **缺乏文档级别的协调机制 (No Document-Level Coordination)**：单个自定义文本组件之间无法共享协调器，除非额外引入复杂的全局状态管理。

> [!IMPORTANT]
> **核心架构洞察**：横向文本交叉关注点属于环境上下文，应该通过 `InheritedWidget` ([TextPluginScope](widgets/text_plugin.dart)) 附加，并由 [RenderParagraph](rendering/paragraph.dart) / [RenderEditable](rendering/editable.dart) 直接执行的可组合**插件流水线**，保持标准 [Text](widgets/text.dart)、[RichText](widgets/basic.dart) 和 [EditableText](widgets/editable_text.dart) 代码零修改。

---

## 2. 设计目标与 API 划界战略 (Design Goals & Framework/Community Taxonomy)

### 2.1 设计目标与非目标 (Design Goals & Non-Goals)

### 设计目标 (Goals)
- **零样板代码接入 (Zero-boilerplate adoption)**：现有的 `Text('...')`、`Text.rich(...)` 和 `EditableText` (`TextField`) 组件放置在 [TextPluginScope](widgets/text_plugin.dart) 内部时自动参与插件扩展。
- **全面支持静态与可编辑文本 (Full support for static & editable text)**：无缝支持 [RenderParagraph](rendering/paragraph.dart) (`Text` / `RichText`) 和 [RenderEditable](rendering/editable.dart) (`EditableText` / `TextField`)，打字编辑时装饰效果实时更新。
- **确定性的多插件组合 (Deterministic multi-plugin composition)**：多个插件可以按照确定的“从根到叶”的安装顺序，在同一个 RenderObject 上进行检查、绘制背景/前景以及处理指针事件。
- **RenderObject 内部封装 (Encapsulation of RenderObjects)**：插件通过一个能力封装的 [TextDelegate](rendering/text_plugin.dart)（包裹 `RenderParagraph` 或 `RenderEditable`）进行交互，而不是直接修改 RenderObject 内部状态。
- **子树局部排除 (Subtree opt-out)**：子树（如工具栏、搜索输入框或装饰性 UI Chrome）可以通过 [TextPluginScope.none](widgets/text_plugin.dart) 保护自己不受上层祖先插件的影响。
- **严格的分层架构 (Strict layer separation)**：渲染原语位于 `package:flutter/rendering.dart` ([rendering/text_plugin.dart](rendering/text_plugin.dart))；Widget 作用域位于 `package:flutter/widgets.dart` ([widgets/text_plugin.dart](widgets/text_plugin.dart))。均不依赖 Material 或 Cupertino 库。

### 非目标 (Non-Goals)
- **修改输入 `InlineSpan` 树或改变文本排版度量**：插件通过 [CustomPainter](rendering/custom_paint.dart) (`backgroundPainter` / `foregroundPainter`) 对已排版的文本进行观察和装饰；插件不会在布局阶段重写字号或插入导致排版偏移的内联 Widget。
- **一次性实现所有的文本插件**：本设计的核心目标是提供一个通用、可扩展的底层架构 API，并在框架内提供极少数最核心的插件（如搜索和选区高亮）。大量特定领域的插件（如自动链接、拼写检查等）将交由开源社区去开发和维护。

---


### 2.2 框架内置 vs 社区 Package 划界与通用 API 设计

在架构层面，一个关键问题是明确：**哪些插件应该作为核心内置在 Flutter 框架中 (`package:flutter`)**，**哪些插件应该交给社区以包的形式存在 (`pub.dev`)**，以及**如何设计 API 使其足够通用**。

#### 2.2.1 框架内置插件 (`package:flutter`)

只有满足全平台通用、属于系统标配功能且零外部依赖的插件才适合内置在框架中：

1. **`_SelectionHighlightTextPlugin`**：作为 `SelectionArea` / `SelectableRegion` 的底层依赖，全平台通用文本选择高亮。
2. **`SearchInPagePlugin`**：桌面端/Web 端标配的 `Ctrl+F` 页面内查找高亮、平滑跳转及视口懒加载管理。

#### 2.2.2 社区 Package 插件 (`pub.dev`)

特定领域、带有业务偏向或依赖第三方库的功能应当由社区作为独立 Package 维护：

1. **`SpellCheckPlugin` (`package:flutter_spellcheck`)**：对接原生 IME 拼写检查与波浪线错误提示。
1. **`LinkifyPlugin` (`package:flutter_linkify_plugin`)**：复杂的 URL 正则解析、超链接样式及 `url_launcher` 调用。
2. **`StockTickerPlugin` / 财经文本插件**：股票代码 (`GOOG`)、加密货币地址、外币汇率实时转换。
3. **`PiiRedactionPlugin` (`package:flutter_pii_redaction`)**：符合安全合规要求的 API Key、身份证、信用卡脱敏黑块遮罩与点击解密。
4. **`ReadAloudPlugin` (`package:flutter_read_aloud`)**：结合 `flutter_tts` 或云端语音 API 的卡拉 OK 逐字高亮朗读同步器。
5. **`SeoExtractorPlugin` (`package:flutter_seo_text`)**：提取 Schema.org JSON-LD 结构化文本供搜索引擎抓取。
6. **`AiGroundingPlugin` / `SpoilerBlurPlugin`**：AI 问答引用来源高亮、剧透打码与 120fps 动态特效。

#### 2.2.3 如何设计更通用的 API 架构

为了让同一个 `TextPlugin` 体系既能支撑框架内置的基础选择，又能支撑社区成百上千种创意 Package，API 设计遵循以下四个通用维度：

1. **通用能力原语而非特定业务假设**：
   - 不为超链接或搜索单独设计特化 API，而是提供原语级别的基础能力：`getBoxesForSelection`、`getPositionForOffset`、`getWordBoundary`、`getLineBoundary`、`getOffsetForCaret`、`backgroundPainter` 与 `foregroundPainter`。
2. **分层组合与精准筛选机制**：
   - `TextPluginScope` 支持任意数量的插件分层叠加（背景高亮在最底，超链接在顶）。
   - 提供 `TextPluginScope.exclude(types: {...})` 允许开发者在 UI 按钮上精准排除特定插件，而不破坏底层的选择高亮。
3. **响应式视口控制协议**：
   - 暴露 `disableLazyLoading` 协议，使任何需要全局检索的插件（如搜索、SEO 提取）均可以与 `ListView.builder` 视口无缝联动，临时拓宽缓存区并自动恢复。
4. **无障碍与语义对齐**：
   - 提供 `TextPluginSemanticAnnotation` 语义标注扩展路径，使社区插件在视觉上绘制的元素（如链接、股票代码、敏感词）能同步映射为 VoiceOver / TalkBack 屏幕朗读器可识别的独立语义节点。

---

## 3. 架构与组件设计 (Architecture & Component Design)

![Mermaid Diagram](https://mermaid.ink/img/eyJjb2RlIjogImdyYXBoIFREXG4gICAgc3ViZ3JhcGggV2lkZ2V0c1tcIldpZGdldHMgXHU1YzQyIChwYWNrYWdlOmZsdXR0ZXIvd2lkZ2V0cy5kYXJ0KVwiXVxuICAgICAgICBTY29wZU91dGVyW1wiVGV4dFBsdWdpblNjb3BlIChcdTU5MTZcdTVjNDI6IFx1NTk4MiBTZWFyY2hQbHVnaW4pXCJdXG4gICAgICAgIFNjb3BlSW5uZXJbXCJUZXh0UGx1Z2luU2NvcGUubXVsdGlwbGUgKFx1NTE4NVx1NWM0MjogU3RvY2tQbHVnaW4sIExpbmtpZnlQbHVnaW4pXCJdXG4gICAgICAgIFNjb3BlTm9uZVtcIlRleHRQbHVnaW5TY29wZS5ub25lIChcdTYzOTJcdTk2NjRcdTViNTBcdTY4MTEpXCJdXG4gICAgICAgIFRleHRXaWRnZXRbXCJUZXh0IC8gVGV4dC5yaWNoXCJdXG4gICAgICAgIFJpY2hUZXh0V2lkZ2V0W1wiUmljaFRleHRcIl1cbiAgICAgICAgRWRpdGFibGVXaWRnZXRbXCJFZGl0YWJsZVRleHQgLyBUZXh0RmllbGRcIl1cbiAgICBlbmRcblxuICAgIHN1YmdyYXBoIFJlbmRlcmluZ1tcIlJlbmRlcmluZyBcdTVjNDIgKHBhY2thZ2U6Zmx1dHRlci9yZW5kZXJpbmcuZGFydClcIl1cbiAgICAgICAgUlBbXCJSZW5kZXJQYXJhZ3JhcGhcIl1cbiAgICAgICAgUkVbXCJSZW5kZXJFZGl0YWJsZVwiXVxuICAgICAgICBURDFbXCJUZXh0RGVsZWdhdGUgKFNlYXJjaFBsdWdpbilcIl1cbiAgICAgICAgVEQyW1wiVGV4dERlbGVnYXRlIChTdG9ja1BsdWdpbilcIl1cbiAgICAgICAgVEQzW1wiVGV4dERlbGVnYXRlIChMaW5raWZ5UGx1Z2luKVwiXVxuICAgIGVuZFxuXG4gICAgU2NvcGVPdXRlciAtLT4gU2NvcGVJbm5lclxuICAgIFNjb3BlSW5uZXIgLS0-IFRleHRXaWRnZXRcbiAgICBTY29wZUlubmVyIC0tPiBFZGl0YWJsZVdpZGdldFxuICAgIFNjb3BlSW5uZXIgLS0-IFNjb3BlTm9uZVxuICAgIFRleHRXaWRnZXQgLS0-IFJpY2hUZXh0V2lkZ2V0XG4gICAgUmljaFRleHRXaWRnZXQgLS0-fFwidGV4dFBsdWdpbnMgPSBbU2VhcmNoLCBTdG9jaywgTGlua2lmeV1cInwgUlBcbiAgICBFZGl0YWJsZVdpZGdldCAtLT58XCJ0ZXh0UGx1Z2lucyA9IFtTZWFyY2gsIFN0b2NrLCBMaW5raWZ5XVwifCBSRVxuICAgIFJQIC0tPiBURDFcbiAgICBSRSAtLT4gVEQxXG4gICAgUlAgLS0-IFREMlxuICAgIFJFIC0tPiBURDJcbiAgICBSUCAtLT4gVEQzXG4gICAgUkUgLS0-IFREMyIsICJtZXJtYWlkIjogeyJ0aGVtZSI6ICJkZWZhdWx0In19)


### 3.1 分层架构与文件组织

| 分层 | 文件 | 公开符号 | 核心职责 |
| :--- | :--- | :--- | :--- |
| **Rendering** | [rendering/text_plugin.dart](rendering/text_plugin.dart) | [TextPlugin](rendering/text_plugin.dart), [TextDelegate](rendering/text_plugin.dart#L108) | 定义插件生命周期接口，以及包裹 `RenderParagraph` 或 `RenderEditable` 的统一代理句柄。 |
| **Rendering** | [rendering/paragraph.dart](rendering/paragraph.dart) | [RenderParagraph.textPlugins](rendering/paragraph.dart#L565-L575) | 对接代理，派发生命周期与指针事件，并在静态文本底层/顶层执行绘制。 |
| **Rendering** | [rendering/editable.dart](rendering/editable.dart) | [RenderEditable.textPlugins](rendering/editable.dart#L285) | 对接代理，派发输入/布局与指针事件，并在输入框底层/顶层执行绘制。 |
| **Widgets** | [widgets/text_plugin.dart](widgets/text_plugin.dart) | [TextPluginScope](widgets/text_plugin.dart) | 通过 `_InheritedTextPluginScope` 向下沿 Widget 树传递并合并 `TextPlugin` 列表。 |
| **Widgets** | [widgets/basic.dart](widgets/basic.dart) | [RichText.textPlugins](widgets/basic.dart#L8035) | 解析 `textPlugins ?? TextPluginScope.maybeOf(context)` 并转发至 `RenderParagraph`。 |
| **Widgets** | [widgets/editable_text.dart](widgets/editable_text.dart) | [EditableText.textPlugins](widgets/editable_text.dart#L947) | 解析 `textPlugins ?? TextPluginScope.maybeOf(context)` 并转发至 `_Editable` / `RenderEditable`。 |

### 3.2 `TextPlugin` 生命周期契约

定义于 [rendering/text_plugin.dart](rendering/text_plugin.dart)，`TextPlugin` 暴露了五个回调钩子：

```dart
abstract class TextPlugin {
  const TextPlugin();

  void didAddText(TextDelegate delegate) {}
  void didUpdateText(TextDelegate delegate) {}
  void didLayoutText(TextDelegate delegate) {}
  void didRemoveText(TextDelegate delegate) {}
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {}
}
```

![Mermaid Diagram](https://mermaid.ink/img/eyJjb2RlIjogInNlcXVlbmNlRGlhZ3JhbVxuICAgIHBhcnRpY2lwYW50IFcgYXMgUmljaFRleHQgLyBFZGl0YWJsZVRleHQgKFdpZGdldClcbiAgICBwYXJ0aWNpcGFudCBSIGFzIFJlbmRlclBhcmFncmFwaCAvIFJlbmRlckVkaXRhYmxlXG4gICAgcGFydGljaXBhbnQgVEQgYXMgVGV4dERlbGVnYXRlXG4gICAgcGFydGljaXBhbnQgVFAgYXMgVGV4dFBsdWdpblxuXG4gICAgVy0-PlI6IGNyZWF0ZVJlbmRlck9iamVjdCAvIHVwZGF0ZVJlbmRlck9iamVjdCAodGV4dFBsdWdpbnMpXG4gICAgUi0-PlREOiBuZXcgVGV4dERlbGVnYXRlKHRoaXMsIHBsdWdpbilcbiAgICBSLT4-VFA6IGRpZEFkZFRleHQoZGVsZWdhdGUpXG4gICAgTm90ZSBvdmVyIFIsVFA6IFx1NmNlOFx1NjEwZlx1ZmYxYVx1NTIxZFx1NmIyMVx1NjMwMlx1OGY3ZFx1NjVmNlx1NWUwM1x1NWM0MFx1NWMxYVx1NjcyYVx1NjI2N1x1ODg0YyAoaGFzTGF5b3V0ID09IGZhbHNlKVxuXG4gICAgUi0-PlI6IHBlcmZvcm1MYXlvdXQoKVxuICAgIFItPj5URDogbm90aWZ5Q2hhbmdlZCgpXG4gICAgUi0-PlRQOiBkaWRMYXlvdXRUZXh0KGRlbGVnYXRlKVxuICAgIE5vdGUgb3ZlciBSLFRQOiBcdTVlMDNcdTVjNDBcdTY3ZTVcdThiZTIgKGdldEJveGVzRm9yU2VsZWN0aW9uLCBzaXplKSBcdTczYjBcdTU3MjhcdTVkZjJcdTViODlcdTUxNjhcdTY3MDlcdTY1NDhcblxuICAgIFItPj5SOiBwYWludChjb250ZXh0LCBvZmZzZXQpXG4gICAgUi0-PlREOiBiYWNrZ3JvdW5kUGFpbnRlcj8ucGFpbnQoY2FudmFzLCBzaXplKVxuICAgIFItPj5SOiBfdGV4dFBhaW50ZXIucGFpbnQoY2FudmFzLCBvZmZzZXQpXG4gICAgUi0-PlREOiBmb3JlZ3JvdW5kUGFpbnRlcj8ucGFpbnQoY2FudmFzLCBzaXplKVxuXG4gICAgVy0-PlI6IHVwZGF0ZVJlbmRlck9iamVjdCAoXHU2NTg3XHU2NzJjXHU2NTM5XHU1M2Q4L1x1NjI1M1x1NWI1N1x1OGY5M1x1NTE2NSlcbiAgICBSLT4-VEQ6IG5vdGlmeUNoYW5nZWQoKVxuICAgIFItPj5UUDogZGlkVXBkYXRlVGV4dChkZWxlZ2F0ZSlcbiAgICBSLT4-UjogcGVyZm9ybUxheW91dCgpXG4gICAgUi0-PlRQOiBkaWRMYXlvdXRUZXh0KGRlbGVnYXRlKVxuXG4gICAgVy0-PlI6IGRpc3Bvc2UoKSBcdTYyMTYgXHU2M2QyXHU0ZWY2XHU3OWJiXHU1ZjAwXHU0ZjVjXHU3NTI4XHU1N2RmXG4gICAgUi0-PlREOiBkZXRhY2hQYWludGVycygpXG4gICAgUi0-PlRQOiBkaWRSZW1vdmVUZXh0KGRlbGVnYXRlKVxuICAgIFItPj5URDogZGlzcG9zZSgpIiwgIm1lcm1haWQiOiB7InRoZW1lIjogImRlZmF1bHQifX0=)


### 3.3 `TextDelegate`：RenderObject 的能力受限安全代理

为了避免将 `RenderParagraph` / `RenderEditable` 直接暴露给插件（否则插件可能破坏布局状态、修改约束或互相覆盖画笔），每个 `(RenderObject, TextPlugin)` 对都有专属的 [TextDelegate](rendering/text_plugin.dart) 实例：

- **独立的画笔槽位 (Isolated Painter Slots)**：每个 [TextDelegate](rendering/text_plugin.dart) 拥有独立的 [backgroundPainter](rendering/text_plugin.dart) 和 [foregroundPainter](rendering/text_plugin.dart)。设置或替换画笔时会检查 `shouldRepaint`，自动绑定/解绑画笔的 `Listenable`（`addListener(renderObject.markNeedsPaint)`），仅在必要时触发重新绘制。
- **文本内容检查 (Content Inspection)**：
  - [delegate.text](rendering/text_plugin.dart)：返回不含语义标签覆盖的纯文本字符串，确保插件观察到的 UTF-16 字符流与 `TextPainter` 的字符偏移量完全一致。
  - [delegate.textSpan](rendering/text_plugin.dart)：暴露原始 `InlineSpan` 树，供需要检查样式或 Span 结构的插件使用。
- **布局与坐标查询 (Layout & Coordinate Queries)**：
  - [hasLayout](rendering/text_plugin.dart)、[hasSize](rendering/text_plugin.dart) 和 [size](rendering/text_plugin.dart)。
  - [getBoxesForSelection](rendering/text_plugin.dart)、[getPositionForOffset](rendering/text_plugin.dart)、[getWordBoundary](rendering/text_plugin.dart)、[getOffsetForCaret](rendering/text_plugin.dart) 和 [getFullHeightForCaret](rendering/text_plugin.dart)。
  - 坐标转换与滚动辅助函数：[localToGlobal](rendering/text_plugin.dart)、[globalToLocal](rendering/text_plugin.dart)、[getTransformTo](rendering/text_plugin.dart) 以及 [showOnScreen](rendering/text_plugin.dart)（支持搜索插件自动将匹配文字滚动至视口内部）。

### 3.4 `TextPluginScope` 与层级合并

[TextPluginScope](widgets/text_plugin.dart) 使用内部 `InheritedWidget` (`_InheritedTextPluginScope`)，在 `build` 阶段预先计算从根到叶合并且去重的插件列表：

1. **单项与多项注册**：`TextPluginScope(plugin: p, child: ...)` 和 `TextPluginScope.multiple(plugins: [p1, p2], child: ...)` 查找 `TextPluginScope.of(context)` 并将自己的插件追加到祖先插件之后。
2. **从根到叶去重**：如果祖先作用域中已存在某个插件实例，则保留其最外层位置，确保每个 `(RenderObject, TextPlugin)` 对保持 1 对 1。
3. **子树局部排除 (`TextPluginScope.none`)**：安装一个 `plugins: const <TextPlugin>[]` 的作用域，屏蔽其 `child` 子树的所有祖先插件。

### 3.5 渲染图层与 Z 轴顺序 (Z-Order Pipeline)

在 `RenderParagraph.paint` / `RenderEditable._paintContents` 中，图层严格按照以下 Z 轴顺序（从后到前）绘制：

1. **插件 `backgroundPainter`**（按根到叶的插件安装顺序绘制，在剪裁区域内绘制）。
2. **系统文本选择区域**（`SelectionArea` / `SelectableRegion` 选区蓝框）。
3. **文本字形与内联子节点**（`_textPainter.paint` 与 `paintInlineChildren`）。
4. **插件 `foregroundPainter`**（按根到叶的插件安装顺序绘制）。
5. **选择拖拽手柄**（移动端选区拖拽小球）。

---

## 4. 更广泛的生态应用场景 (Broader Ecosystem Use Cases)

`TextPlugin` 将**文本检查**、**子区间几何坐标**、**合成绘制**、**手势路由**和**视口控制**融为一体，为 Flutter 生态解锁了一系列“即插即用”的强大插件能力：

### 4.1 无障碍、朗读辅助与语言学习
- **TTS 朗读卡拉 OK 同步器**：按阅读顺序朗读文本，高亮当前朗读单词，并在跨段落时自动平滑滚动。
- **划词翻译 / 假名 (Furigana) 标注**：悬浮/长按显示单词释义 popover。
- **阅读障碍辅助视线尺**：暗化背景行，聚焦当前阅读行。

### 4.2 安全、隐私与合规
- **实时 PII 敏感信息脱敏打码**：自动识别 API Key、身份证、手机号并绘制黑块遮罩，点击可解密查看。

### 4.3 编辑、多语言 (l10n) 与 QA 工具
- **拼写检查与写作风格 Lint**：在错别字下方绘制红色波浪线，点击弹出修改建议。
- **未翻译文本 / 占位符泄露检测**：开发模式下高亮未翻译的 `auth.login.title` 或 `{userName}` 占位符。

### 4.4 协同标注与多用户光标
- **Kindle 式持久化高亮与边注**：在文章上绘制荧光笔高亮并标记评论。
- **多人在线协同光标与选区**：实时渲染队友的光标标志与选择区域。

### 4.5 领域特定智能实体
- **股票代码实时高亮**：自动将 `GOOG`、`AAPL` 变成可点击的行情卡片。
- **自动超链接识别**：自动将 `https://...` 变成可点击链接。
- **SEO 结构化元数据提取**：提取全页展示文本生成搜索引擎索引。

---

## 5. 高阶特性深度探讨 (Feature Deep Dives)

### 5.1 滚动、文档顺序排序与取消懒加载 (`Ctrl+F`)

要在 Flutter 中实现浏览器级别的 **"页面内查找 (Find in Page)"**，需要在渲染层与 Widget 层解决三个核心问题：

![Mermaid Diagram](https://mermaid.ink/img/eyJjb2RlIjogInNlcXVlbmNlRGlhZ3JhbVxuICAgIHBhcnRpY2lwYW50IFVzZXIgYXMgXHU3NTI4XHU2MjM3XG4gICAgcGFydGljaXBhbnQgUGx1Z2luIGFzIFNlYXJjaEluUGFnZVBsdWdpblxuICAgIHBhcnRpY2lwYW50IFNjb3BlIGFzIFRleHRQbHVnaW5TY29wZVxuICAgIHBhcnRpY2lwYW50IFZQIGFzIFZpZXdwb3J0IC8gUmVuZGVyVmlld3BvcnRcbiAgICBwYXJ0aWNpcGFudCBTbGl2ZXIgYXMgUmVuZGVyU2xpdmVyTGlzdFxuICAgIHBhcnRpY2lwYW50IFBhcmEgYXMgUmVuZGVyUGFyYWdyYXBoIC8gUmVuZGVyRWRpdGFibGUgKFx1NWM0Zlx1NWU1NVx1NTkxNilcblxuICAgIFVzZXItPj5QbHVnaW46IFx1NjMwOVx1NGUwYiBDdHJsK0YgKGVhZ2VyTG9hZE9mZnNjcmVlblRleHQgPSB0cnVlKVxuICAgIFBsdWdpbi0-PlNjb3BlOiBub3RpZnlMaXN0ZW5lcnMoKSAoZGlzYWJsZUxhenlMb2FkaW5nID09IHRydWUpXG4gICAgU2NvcGUtPj5WUDogX0luaGVyaXRlZFRleHRQbHVnaW5MYXp5TG9hZGluZyBcdTkwMWFcdTc3ZTVcdTg5YzZcdTUzZTNcbiAgICBWUC0-PlZQOiBzY3JvbGxDYWNoZUV4dGVudCA9IFNjcm9sbENhY2hlRXh0ZW50LnBpeGVscygxZTkpXG4gICAgVlAtPj5TbGl2ZXI6IHBlcmZvcm1MYXlvdXQocmVtYWluaW5nQ2FjaGVFeHRlbnQ6IDFlOSlcbiAgICBTbGl2ZXItPj5QYXJhOiBcdTY3ODRcdTVlZmFcdTMwMDFcdTYzMDJcdThmN2RcdTVlNzZcdTYzOTJcdTcyNDhcdTYyNDBcdTY3MDlcdTVjNGZcdTVlNTVcdTU5MTZcdTUyMTdcdTg4NjhcdTk4NzlcbiAgICBQYXJhLT4-UGx1Z2luOiBhdHRhY2goKSAtPiBkaWRBZGRUZXh0KGRlbGVnYXRlKVxuICAgIFBhcmEtPj5QbHVnaW46IHBlcmZvcm1MYXlvdXQoKSAtPiBkaWRMYXlvdXRUZXh0KGRlbGVnYXRlKVxuICAgIFBsdWdpbi0-PlBsdWdpbjogXHU5MDFhXHU4ZmM3IGRlbGVnYXRlLmNvbXBhcmVUbygpIFx1NjMwOVx1NjU4N1x1Njg2M1x1OTg3YVx1NWU4Zlx1NjM5Mlx1NWU4ZlxuICAgIFVzZXItPj5QbHVnaW46IFx1NzBiOVx1NTFmYlx1NGUwYlx1NGUwMFx1NGUyYVx1NTMzOVx1OTE0ZFx1OTg3OSAvIEVudGVyXG4gICAgUGx1Z2luLT4-UGFyYTogZGVsZWdhdGUuZW5zdXJlVmlzaWJsZShtYXRjaC5yYW5nZSlcbiAgICBQYXJhLT4-VlA6IHNob3dPblNjcmVlbihyZWN0OiB0YXJnZXRSZWN0KSAtPiBcdTVlNzNcdTZlZDFcdTZlZGFcdTUyYThcdTgxZjNcdTUzMzlcdTkxNGRcdTY1ODdcdTViNTciLCAibWVybWFpZCI6IHsidGhlbWUiOiAiZGVmYXVsdCJ9fQ==)


#### 5.1.1 精确滚动至指定字符区间 (`TextDelegate.ensureVisible`)
`TextDelegate.ensureVisible(range)` 计算任意 `TextRange` 的字符包围盒矩形，并向上逐级唤醒父级视口（`RenderViewportBase.showInViewport`）进行平滑滚动。支持多层嵌套滚动视图（横向+纵向）自动双轴滚动定位。

#### 5.1.2 真正的文档顺序排序 (`TextDelegate.compareTo`)
当用户向上滚动列表时，组件的挂载顺序与文档顺序相反。`TextDelegate.compareTo` 通过寻找两者的**最近公共祖先 (Lowest Common Ancestor, LCA)**，并遍历祖先节点的子节点链，保证无论滑动和挂载顺序如何，“下一个/上一个”匹配项始终严格按照从上到下的阅读顺序排列。

#### 5.1.3 取消懒加载 (`TextPlugin.disableLazyLoading`)
当激活搜索时，`TextPluginScope` 仅向视口通知 `disableLazyLoading = true`，使视口将 `cacheExtent` 扩展至 `1e9` 像素，强制 `SliverList` 将所有屏幕外项构建入内存；关闭搜索时自动恢复 `250.0` 像素默认视口缓存，回收屏幕外组件。

---


### 5.2 深度探讨：文本选择高亮是否应该作为一个 `TextPlugin`？

一个自然的架构思考是：Flutter 内置的文本选择高亮 ([_SelectableFragment.paintSelection](rendering/paragraph.dart#L3865)) 是否应该本身迁移为一个由 `SelectableRegion` 安装的 `TextPlugin`？

#### 5.2.1 收益
1. **可组合的 Z 轴顺序**：由作用域安装顺序决定选择高亮与插件画笔的层级。
2. **自定义选择视觉效果**：无需修改 `RenderParagraph` 即可实现圆角选区、渐变选区或**多用户协同光标/选区**（如 Google Docs）。
3. **精简 `RenderParagraph`**：将 `paragraph.dart` 中数千行选择逻辑解耦。

#### 5.2.2 迁移时发现的 5 个边界情况 (`text-plugins-alt` 原型分析)
1. **根与叶绘制顺序反转**：`SelectableRegion` 通常在页面根部，而业务插件在内层。若外层后画，选择蓝框会盖住内层插件的前景装饰。
2. **单组件 `Text(selectionColor: ...)` 覆盖**：单个组件覆盖选择颜色的属性需要显式暴露至 `TextDelegate`。
3. **不连续选区与 `WidgetSpan` 占位符**：需过滤 `\uFFFC` 占位符矩形。
4. **回退绘制抑制标志**：需要明确的 `handlesSelectionHighlight` 标志防止双重绘制。
5. **排除作用域偶合**：`TextPluginScope.none` 不应意外屏蔽选择高亮的绘制。

#### 5.2.3 为什么完整的文本选择 (`_SelectableFragment`) 仅仅依靠 `CustomPainter` 是不够的？

虽然**选择高亮蓝框的绘制**可以完美放入 `TextDelegate.backgroundPainter`，但在不扩展 `TextDelegate` 的情况下，[_SelectableFragment](rendering/paragraph.dart#L1752) 的其余能力无法直接从 `RenderParagraph` / `RenderEditable` 中剥离到纯粹的 `TextPlugin` 中：

1. **移动端选择拖拽手柄需要 `PaintingContext.pushLayer`**：
   [_SelectableFragment.paintHandles](rendering/paragraph.dart#L3883) 通过 `context.pushLayer(LeaderLayer(link: _startHandleLayerLink!, ...))` 提交合成好的 `LeaderLayer` 图层，并要求 [RenderParagraph.alwaysNeedsCompositing](rendering/paragraph.dart#L684) 返回 `true`。而 `CustomPainter` 仅接收 `Canvas` 绘制上下文，无法向渲染流水线提交合成图层。
2. **跨 RenderObject 的 `SelectionRegistrar` 注册协议**：
   `SelectionArea` 能够同时跨越文本组件（`RenderParagraph`）和非文本可选组件（如可选择的 Image）。任何选择插件都必须继续将其片段桥接到 `SelectionRegistrar` 注册中心。

#### 5.2.4 干净解耦选择功能至 `TextPlugin` 的蓝图规格

| 所需能力 | 在 `TextDelegate` / `TextPluginScope` 上所需的 API 扩展 |
| :--- | :--- |
| **多片段选区与颜色** | 在 `TextDelegate` 上暴露 `List<TextSelection> get selections` 与 `Color? get selectionColor`。 |
| **跳过 `WidgetSpan` 矩形** | 通过 [TextDelegate.placeholderRanges](rendering/text_plugin.dart) 以及在 [TextDelegate.getBoxesForSelection](rendering/text_plugin.dart) 中传入 `includePlaceholders: false` 实现。 |
| **移动端拖拽手柄图层** | 允许 `TextDelegate` 注册拖拽手柄的 `LeaderLayer` 链接 `(LayerLink, Offset)`，在 `RenderParagraph.paint` / `RenderEditable._paintContents` 期间统一绘制并反映在 `alwaysNeedsCompositing` 中。 |
| **正交排除作用域** | 引入 `TextPluginScope.exclude(types: {...})`，避免 `TextPluginScope.none` 意外抑制 `SelectionHighlightPlugin`。 |

#### 5.2.5 后续演进路线图：将 `SelectionArea` / `SelectionContainer` 迁移为 `TextPlugin`

基于原型实验 [`Renzo-Olivares:text-plugins-alt` (commit 55f5d0af4503fe7950374addd625a5fd9ae8efb5)](https://github.com/Renzo-Olivares/flutter/commit/55f5d0af4503fe7950374addd625a5fd9ae8efb5) 的设计分析，将 Flutter 内置的文本选择高亮完全重构成一个标准的 `TextPlugin` 已规划为以下四个阶段的后续 Action / Roadmap 项：

#### 阶段 1：内部 `_SelectionHighlightTextPlugin` 原型化
- `SelectionContainer` / `SelectableRegion` 在其子树中自动安装私有的 `_SelectionHighlightTextPlugin`。
- `_SelectionHighlightTextPlugin` 监听来自 `SelectionRegistrar` 的选区变化，通过 `delegate.getBoxesForSelection(selection, includePlaceholders: false)` 读取选区物理矩形，并利用 `delegate.backgroundPainter` 进行高亮绘制。
- `RenderParagraph` 与 `RenderEditable` 在检测到选择高亮插件存在时，自动抑制传统的 `_SelectableFragment.paintSelection` 回退绘制，防止重复叠加颜色。

#### 阶段 2：移动端选择手柄图层注册 (Handle Layer Registration)
- 扩展 `TextDelegate` 暴露 `delegate.registerHandleLayers(startLink, endLink)` 方法，允许选择插件在 `RenderParagraph` / `RenderEditable` 绘制时提交用于移动端选区拖拽小球的合成 `LeaderLayer` 图层。

#### 阶段 3：按类型精准排除子树 (`TextPluginScope.exclude`)
- 在 `TextPluginScope.none` 之外新增 `TextPluginScope.exclude(types: {SearchInPagePlugin, StockTickerPlugin})` 语法，允许开发者仅屏蔽业务层插件（如在 UI 按钮上），而不会误将底层的 `_SelectionHighlightTextPlugin` 屏蔽导致选择高亮失效。

#### 阶段 4：框架解耦与全面迁移
- 弃用 `RenderParagraph` 和 `RenderEditable` 内部的硬编码选区绘制逻辑，使 `_SelectionHighlightTextPlugin` 成为 Flutter 全平台统一的文本选择渲染引擎。

---

## 6. 极端边界情况与架构深度分析 (12 个 Corner Cases)

以下是设计和实现过程中识别出的 12 个关键边界情况、当前的解决方案以及相关权衡：

### 边界 1：Build、Layout 与 Dispose 期间的 `ChangeNotifier` / `setState` 重入

**问题**：  
`TextPlugin` 回调在渲染流水线各阶段中同步调用：
- `didAddText` 与 `didUpdateText` 在 `RichText.createRenderObject` / `updateRenderObject`（**Build 阶段**）执行。
- `didLayoutText` 在 `performLayout` 结尾（**Layout 阶段**）执行。
- `didRemoveText` 在 `dispose`（**Tree Finalize 阶段**）执行。

若 `TextPlugin` 继承了 `ChangeNotifier` 并在这些回调中同步调用 `notifyListeners()` 触发祖先 Widget `setState`，框架会抛出断言错误：`setState() or markNeedsBuild() called during build.`

**解决方案**：
- **画笔更新同步进行**：设置 `delegate.backgroundPainter = ...` 仅调用 `renderObject.markNeedsPaint()`，这在 Build 和 Layout 阶段（绘制前）完全合规。
- **外部 UI 通知合并至帧后**：在有状态插件（如 `SearchInPagePlugin`, `SeoExtractorPlugin`）中，若当前处于 `SchedulerPhase.persistentCallbacks` 阶段，将 `notifyListeners()` 合并延迟至 `addPostFrameCallback` 中执行。

---

### 边界 2：在 `didAddText` 或 `didUpdateText` 中调用布局查询 (`!delegate.hasLayout`)

**问题**：  
当 `didAddText(delegate)` 被调用时，`performLayout()` 尚未执行 (`!hasSize`)。若此时在回调中立即调用 `delegate.getBoxesForSelection(...)` 或 `delegate.size`，会触发断言异常。

**解决方案**：
1. 暴露 [TextDelegate.hasLayout](rendering/text_plugin.dart)。
2. 增加明确的 [TextPlugin.didLayoutText](rendering/text_plugin.dart) 布局完成生命周期回调。
3. 插件在 `CustomPainter.paint` 中懒查询 `getBoxesForSelection`（受 `if (!delegate.hasLayout) return;` 保护），此时布局保证最新。

---

### 边界 3：内联 `WidgetSpan` (`PlaceholderSpan`) 与 UTF-16 偏移对齐

**问题**：  
在 `TextPainter` 内部，每个 `PlaceholderSpan` 占据 1 个 UTF-16 代码单元（Unicode 替换字符 `\uFFFC`）。如果 `delegate.text` 忽略占位符或包含了 `semanticsLabel` 覆盖文本，字符串索引将与 `TextPainter` 的字符偏移量失去同步！

**解决方案**：
- [TextDelegate.text](rendering/text_plugin.dart) 明确调用 `_paragraph.text.toPlainText(includeSemanticsLabels: false)`，保留 `\uFFFC` 占位符并排除语义标签，保证 `delegate.text` 索引与 `TextPainter` 中的 `TextSelection` 偏移量保持 **1 对 1 精确映射**。

---

### 边界 4：文本截断 (`maxLines`, `TextOverflow.ellipsis`, `TextOverflow.clip`, `TextOverflow.fade`)

**问题**：  
当文本设置了 `maxLines: 1, overflow: TextOverflow.ellipsis` 时，被截断隐藏在 `...` 后面的字符在 `delegate.text` 中依然存在，此时插件绘制的超界装饰可能会溢出。

**解决方案**：
- 在 `RenderParagraph.paint` 和 `RenderEditable._paintContents` 中，当 `_needsClipping` 为 `true` 时，框架会对 `backgroundPainter` 和 `foregroundPainter` 的绘制做矩形剪裁 (`context.canvas.clipRect(offset & size)`)。

---

### 边界 5：多行折行、双向文本 (BiDi) 与 UTF-16 代理对

**问题**：  
长 URL 跨多行折行或包含 RTL 阿拉伯文/希伯来文时，一个逻辑子串不对应单个 `Rect`，而是对应多个 `TextBox`。

**解决方案**：
- 插件迭代 `delegate.getBoxesForSelection(...)` 返回的**每一个** `ui.TextBox` 进行绘制与手势命中测试。自动处理折行与双向文本。

---

### 边界 6：动态插件列表 Reconciliation 与 Delegate 状态保留

**问题**：  
当作用域中的插件列表从 `[stockPlugin, linkifyPlugin, searchPlugin]` 动态切换为 `[stockPlugin, linkifyPlugin]` 时，不能简单地销毁重建所有 Delegate。

**解决方案**：
- 框架在 RenderObject 中对新旧插件列表进行 Diff 比对：仅移除的插件会接收到 `didRemoveText` 并销毁；保留的插件继续维持其现有的 `TextDelegate` 实例及画笔。

---

### 边界 7：嵌套 `TextPluginScope` 中的重复插件实例

**问题**：  
若同一个 `TextPlugin` 实例在嵌套作用域中被重复注册，可能会导致回调重复执行或双重绘制。

**解决方案**：
- `TextPluginScope` 在 Widget 树层级和 RenderObject 层级双重执行去重检查，确保每个 `(RenderObject, TextPlugin)` 对唯一。

---

### 边界 8：指针手势路由、多插件冲突与滚动滑动容差 (Touch Slop)

**问题**：  
在 `ListView` 中拖拽滚动时，手指按在超链接或股票代码上不应误触发点击事件。

**解决方案**：
- 插件在 `handlePointerEvent` 中记录按下位置，校验 `(event.localPosition - downPos).distance <= kTouchSlop` 且未收到 `PointerCancelEvent` 时才触发点击回调。

---

### 边界 9：与 `SelectionArea` / `SelectableRegion` 共存

**问题**：  
文本同时处于 `SelectionArea` 和 `TextPluginScope` 内部时，高亮背景与选区蓝框的层级不能错乱。

**解决方案**：
- 插件背景画笔在选区蓝框**底层**绘制；插件前景画笔在字形**顶层**绘制但在拖拽手柄**底层**绘制。

---

### 边界 10：意外捕获 UI Chrome 与 `TextPluginScope.none`

**问题**：  
`AppBar` 标题、按钮文字或搜索框提示语也是文本组件，若全局包裹插件，可能导致按钮文字被误搜索高亮。

**解决方案**：
- 推荐将 `TextPluginScope` 仅包裹正文区域，或对按钮/工具栏使用 `TextPluginScope.none` 进行局部屏蔽。

---

### 边界 11：懒加载列表 (`ListView.builder`) 与屏幕外视口回收

**问题**：  
屏幕外的列表项默认不会被创建，按 `Ctrl+F` 搜索时搜不到屏幕外的文字。

**解决方案**：
- 引入 `TextPlugin.disableLazyLoading` 机制。按 `Ctrl+F` 时触发视口临时将 `cacheExtent` 放大至 `1e9` 像素，强制列表生成全量子节点参与搜索与滚动；关闭搜索时自动恢复省电懒加载。

---

### 边界 12：插件 `CustomPainter` 中的 Canvas 状态污染

**问题**：  
错误插件如果调用了 `canvas.save()` 但未调用 `restore()`，会污染后续组件的 Canvas 坐标系。

**解决方案**：
- RenderObject 在调用插件 Painter 前后自动执行 `canvas.save()` / `restore()` 保护，并在 Debug 模式下校验 `getSaveCount()`，发现不匹配时抛出清晰的 `FlutterError` 指出有问题的插件。

---
