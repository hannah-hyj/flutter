// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'basic.dart';
/// @docImport 'editable_text.dart';
/// @docImport 'overlay.dart';
/// @docImport 'scroll_view.dart';
/// @docImport 'text.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'basic.dart';
import 'framework.dart';
import 'overlay.dart';
import 'viewport.dart';

/// A widget that installs one or more [TextPlugin]s for all [Text],
/// [RichText], and [EditableText] widgets in its [child] subtree.
///
/// When multiple [TextPluginScope] widgets are nested, their plugins are
/// composed in installation order: plugins from outer [TextPluginScope]s
/// (closer to the root of the widget tree) are applied and painted before
/// plugins from inner [TextPluginScope]s.
///
/// To exclude a subtree from any ancestor [TextPluginScope]s, wrap the subtree
/// in [TextPluginScope.none].
///
/// Text in a route that is covered by an opaque route is not given to any
/// plugin, even though the route is still mounted. The [Overlay] suspends
/// plugins for an [OverlayEntry] below an [OverlayEntry.opaque] entry, and
/// gives the text back when the entry is uncovered. A plugin gets
/// [TextPlugin.didRemoveText] and [TextPlugin.didAddText] for it.
///
/// If any installed [TextPlugin] has [TextPlugin.needsOffscreenContent] set to
/// `true`, [TextPluginScope] configures descendant
/// scrollable viewports (such as [ListView], [CustomScrollView], and
/// [Viewport]) via [OffscreenContentRenderingStrategy] with
/// [OffscreenRenderingPolicy.eager] so that offscreen sliver children are
/// eagerly rendered. Applications can also place an
/// [OffscreenContentRenderingStrategy] directly inside a [TextPluginScope] to
/// override the policy for a specific scrollable subtree.
///
/// See also:
///
///  * [TextPlugin], the interface implemented by text plugins.
///  * [TextDelegate], the handle given to a [TextPlugin] for each text widget
///    in its scope.
///  * [OffscreenContentRenderingStrategy], which controls how descendant
///    viewports render offscreen sliver content.
class TextPluginScope extends StatefulWidget {
  /// Creates a scope that installs [plugin] for all [Text], [RichText], and
  /// [EditableText] widgets in [child], composing with any ancestor
  /// [TextPluginScope]s.
  const TextPluginScope({
    super.key,
    required TextPlugin this.plugin,
    this.decorationLayer,
    required this.child,
  }) : plugins = null,
       types = null,
       _disabled = false;

  /// Creates a scope that installs multiple [plugins] for all [Text],
  /// [RichText], and [EditableText] widgets in [child], composing with any
  /// ancestor [TextPluginScope]s.
  const TextPluginScope.multiple({
    super.key,
    required List<TextPlugin> this.plugins,
    this.decorationLayer,
    required this.child,
  }) : plugin = null,
       types = null,
       _disabled = false;

  /// Creates a scope that excludes any ancestor [TextPlugin]s whose
  /// [Object.runtimeType] is in [types] for [child].
  const TextPluginScope.exclude({super.key, required Set<Type> this.types, required this.child})
    : plugin = null,
      plugins = null,
      decorationLayer = null,
      _disabled = false;

  /// Creates a scope that disables any ancestor [TextPluginScope]s for [child].
  const TextPluginScope.none({super.key, required this.child})
    : plugin = null,
      plugins = null,
      decorationLayer = null,
      types = null,
      _disabled = true;

  /// The single [TextPlugin] installed by this scope, if created with
  /// [TextPluginScope.new].
  final TextPlugin? plugin;

  /// The list of [TextPlugin]s installed by this scope, if created with
  /// [TextPluginScope.multiple].
  final List<TextPlugin>? plugins;

  /// The set of [TextPlugin] runtime types excluded by this scope, if created
  /// with [TextPluginScope.exclude].
  final Set<Type>? types;

  final bool _disabled;

  /// Where the decorations of the plugins are turned into a span, for the
  /// texts below this scope.
  ///
  /// Experiment only. If null, the layer of the enclosing scope is used, and
  /// [debugDefaultTextDecorationLayer] if there is none.
  final TextDecorationLayer? decorationLayer;

  /// The [TextDecorationLayer] for a text at [context].
  static TextDecorationLayer decorationLayerOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_InheritedTextPluginScope>()
            ?.decorationLayer ??
        debugDefaultTextDecorationLayer;
  }

  /// A number that changes when a plugin with
  /// [TextPlugin.notifiesDecorationChanges] notifies its listeners.
  static int decorationVersionOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_InheritedTextPluginScope>()
            ?.decorationVersion ??
        0;
  }

  /// The widget below this widget in the tree.
  final Widget child;

  /// Returns the list of active [TextPlugin]s enclosing the given [context],
  /// ordered by [TextPlugin.paintOrder] and installation order (outermost
  /// first), or `null` if no [TextPluginScope] is present (or if disabled via
  /// [TextPluginScope.none]).
  static List<TextPlugin>? maybeOf(BuildContext context) {
    final _InheritedTextPluginScope? scope = context
        .dependOnInheritedWidgetOfExactType<_InheritedTextPluginScope>();
    if (scope == null || scope.plugins.isEmpty) {
      return null;
    }
    return scope.plugins;
  }

  /// Returns the list of active [TextPlugin]s enclosing the given [context],
  /// ordered by [TextPlugin.paintOrder] and installation order (outermost
  /// first), or an empty list if no [TextPluginScope] is present.
  static List<TextPlugin> of(BuildContext context) {
    return maybeOf(context) ?? const <TextPlugin>[];
  }

  @override
  State<TextPluginScope> createState() => _TextPluginScopeState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (_disabled) {
      properties.add(FlagProperty('disabled', value: true, ifTrue: 'disabled'));
    } else if (plugin != null) {
      properties.add(DiagnosticsProperty<TextPlugin>('plugin', plugin));
    } else if (plugins != null) {
      properties.add(IterableProperty<TextPlugin>('plugins', plugins));
    } else if (types != null) {
      properties.add(IterableProperty<Type>('excludedTypes', types));
    }
  }
}

class _TextPluginScopeState extends State<TextPluginScope> {
  final List<Listenable> _listenedPlugins = <Listenable>[];
  bool _localRequiresOffscreenScan = false;
  int _decorationVersion = 0;

  List<TextPlugin> get _ownPlugins => <TextPlugin>[
    if (widget.plugin != null) widget.plugin!,
    ...?widget.plugins,
  ];

  bool _computeLocalRequiresOffscreenScan() {
    if (widget._disabled) {
      return false;
    }
    for (final TextPlugin item in _ownPlugins) {
      if (item.needsOffscreenContent) {
        return true;
      }
    }
    return false;
  }

  void _subscribeToPlugins() {
    for (final TextPlugin item in _ownPlugins) {
      if (item is Listenable) {
        final listenable = item as Listenable;
        listenable.addListener(_handlePluginChanged);
        _listenedPlugins.add(listenable);
      }
    }
    _localRequiresOffscreenScan = _computeLocalRequiresOffscreenScan();
  }

  void _unsubscribeFromPlugins() {
    for (final Listenable listenable in _listenedPlugins) {
      listenable.removeListener(_handlePluginChanged);
    }
    _listenedPlugins.clear();
  }

  void _handlePluginChanged() {
    final bool updated = _computeLocalRequiresOffscreenScan();
    final bool redecorate = _ownPlugins.any((TextPlugin item) => item.notifiesDecorationChanges);
    if (updated == _localRequiresOffscreenScan && !redecorate) {
      return;
    }
    assert(() {
      if (context.owner?.debugBuilding ?? false) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('A TextPlugin notified its listeners while widgets were being built.'),
          ErrorDescription(
            'The lifecycle callbacks of a TextPlugin (didAddText, didUpdateText and '
            'didRemoveText) run during build. A TextPluginScope that listens to the '
            'plugin cannot rebuild at that point.',
          ),
          ErrorHint(
            'Notify through TextPlugin.deferToEndOfFrame, which waits for the end of '
            'the frame when one is being produced.',
          ),
        ]);
      }
      return true;
    }());
    setState(() {
      _localRequiresOffscreenScan = updated;
      if (redecorate) {
        _decorationVersion += 1;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _subscribeToPlugins();
  }

  @override
  void didUpdateWidget(TextPluginScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unsubscribeFromPlugins();
    _subscribeToPlugins();
  }

  @override
  void dispose() {
    _unsubscribeFromPlugins();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _InheritedTextPluginScope? ancestorScope = context
        .dependOnInheritedWidgetOfExactType<_InheritedTextPluginScope>();
    // While an ancestor suspends plugins, this scope does not install its own
    // either. The widgets built here stay the same, so that the subtree keeps
    // its state when the suspension starts and ends.
    final bool suspended = ancestorScope?.suspended ?? false;
    if (widget._disabled || suspended) {
      return OffscreenContentRenderingStrategy(
        policy: const OffscreenRenderingPolicy.lazy(),
        child: _InheritedTextPluginScope(
          pluginMap: const <Type, TextPlugin>{},
          plugins: const <TextPlugin>[],
          suspended: suspended,
          decorationLayer: ancestorScope?.decorationLayer,
          child: widget.child,
        ),
      );
    }
    final OffscreenRenderingPolicy inheritedPolicy = OffscreenContentRenderingStrategy.of(context);
    final Set<Type>? excludedTypes = widget.types;
    final pluginMap = <Type, TextPlugin>{};
    if (ancestorScope != null) {
      for (final MapEntry<Type, TextPlugin> entry in ancestorScope.pluginMap.entries) {
        if (excludedTypes == null || !excludedTypes.contains(entry.key)) {
          pluginMap[entry.key] = entry.value;
        }
      }
    }
    for (final TextPlugin item in _ownPlugins) {
      pluginMap[item.runtimeType] = item;
    }
    final List<TextPlugin> orderedPlugins = pluginMap.values.toList(growable: false);
    mergeSort<TextPlugin>(
      orderedPlugins,
      compare: (TextPlugin a, TextPlugin b) => a.paintOrder.compareTo(b.paintOrder),
    );
    final bool activePluginsRequireScan = orderedPlugins.any(
      (TextPlugin item) => item.needsOffscreenContent,
    );
    final effectivePolicy = excludedTypes != null
        ? (activePluginsRequireScan
              ? const OffscreenRenderingPolicy.eager()
              : const OffscreenRenderingPolicy.lazy())
        : ((inheritedPolicy.isEager || _localRequiresOffscreenScan)
              ? (inheritedPolicy.isEager ? inheritedPolicy : const OffscreenRenderingPolicy.eager())
              : const OffscreenRenderingPolicy.lazy());
    return OffscreenContentRenderingStrategy(
      policy: effectivePolicy,
      child: _InheritedTextPluginScope(
        pluginMap: Map<Type, TextPlugin>.unmodifiable(pluginMap),
        plugins: List<TextPlugin>.unmodifiable(orderedPlugins),
        decorationLayer: widget.decorationLayer ?? ancestorScope?.decorationLayer,
        decorationVersion: (ancestorScope?.decorationVersion ?? 0) + _decorationVersion,
        child: widget.child,
      ),
    );
  }
}

/// Withholds every [TextPlugin] from [child] while [suspended] is true.
///
/// This is for text that is still mounted but cannot be seen, such as a route
/// that is covered by an opaque route. Unlike [TextPluginScope.none], a
/// [TextPluginScope] inside [child] does not install its plugins either, so
/// the text is left out no matter where the scope is.
///
/// The widget builds the same subtree in both states. Toggling [suspended]
/// keeps the state of [child]; the plugins get [TextPlugin.didRemoveText] when
/// it becomes true and [TextPlugin.didAddText] when it becomes false.
///
/// Plugins passed directly to [RichText.textPlugins] or
/// [EditableText.textPlugins] are not affected.
///
/// The [Overlay] uses this for an [OverlayEntry] below an opaque entry.
@internal
class TextPluginSuspension extends StatelessWidget {
  /// Creates a widget that withholds text plugins from [child] while
  /// [suspended] is true.
  const TextPluginSuspension({super.key, required this.suspended, required this.child});

  /// Whether the text in [child] is withheld from plugins.
  final bool suspended;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _InheritedTextPluginScope? ancestorScope = context
        .dependOnInheritedWidgetOfExactType<_InheritedTextPluginScope>();
    final bool effectiveSuspended = suspended || (ancestorScope?.suspended ?? false);
    if (effectiveSuspended || ancestorScope == null) {
      return _InheritedTextPluginScope(
        pluginMap: const <Type, TextPlugin>{},
        plugins: const <TextPlugin>[],
        suspended: effectiveSuspended,
        decorationLayer: ancestorScope?.decorationLayer,
        child: child,
      );
    }
    return _InheritedTextPluginScope(
      pluginMap: ancestorScope.pluginMap,
      plugins: ancestorScope.plugins,
      decorationLayer: ancestorScope.decorationLayer,
      decorationVersion: ancestorScope.decorationVersion,
      child: child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('suspended', value: suspended, ifTrue: 'suspended'));
  }
}

class _InheritedTextPluginScope extends InheritedWidget {
  const _InheritedTextPluginScope({
    required this.pluginMap,
    required this.plugins,
    this.suspended = false,
    this.decorationLayer,
    this.decorationVersion = 0,
    required super.child,
  });

  final TextDecorationLayer? decorationLayer;
  final int decorationVersion;

  final Map<Type, TextPlugin> pluginMap;
  final List<TextPlugin> plugins;

  /// Whether an ancestor [TextPluginSuspension] withholds plugins. A
  /// [TextPluginScope] below does not install plugins while this is true.
  final bool suspended;

  @override
  bool updateShouldNotify(_InheritedTextPluginScope oldWidget) {
    return suspended != oldWidget.suspended ||
        decorationLayer != oldWidget.decorationLayer ||
        decorationVersion != oldWidget.decorationVersion ||
        !listEquals(plugins, oldWidget.plugins);
  }
}

/// Builds the decorated span of one text (Option A of the inline-span
/// experiment), and owns the [TextDelegate]s of that text.
///
/// [Text] and [EditableText] put this around their render object widget when a
/// [TextPlugin] is in scope and the [TextDecorationLayer] is
/// [TextDecorationLayer.widget]. In `build` it first tells the plugins about
/// the text ([TextPlugin.didAddText], [TextPlugin.didUpdateText]), then asks
/// them for their decorations, and then builds the text with the decorated
/// span.
///
/// It is not part of the plugin API.
class TextPluginSpanBuilder extends StatefulWidget {
  /// Creates a widget that decorates [text] for [plugins].
  const TextPluginSpanBuilder({
    super.key,
    required this.plugins,
    required this.text,
    required this.textDirection,
    this.isEditable = false,
    this.allowReplacements = true,
    required this.decorationVersion,
    required this.builder,
  });

  /// Returns what [builder] returns, with a [TextPluginSpanBuilder] around it
  /// if a plugin is in scope at [context] and the layer is
  /// [TextDecorationLayer.widget].
  ///
  /// Without one, [builder] is called with [text] itself and without
  /// delegates.
  static Widget wrap(
    BuildContext context, {
    required InlineSpan text,
    required TextDirection? textDirection,
    bool isEditable = false,
    bool allowReplacements = true,
    bool enabled = true,
    required Widget Function(InlineSpan text, TextDelegateSet? delegates) builder,
  }) {
    final List<TextPlugin>? plugins = enabled ? TextPluginScope.maybeOf(context) : null;
    if (plugins == null ||
        TextPluginScope.decorationLayerOf(context) != TextDecorationLayer.widget) {
      return builder(text, null);
    }
    return TextPluginSpanBuilder(
      plugins: plugins,
      text: text,
      textDirection: textDirection ?? Directionality.of(context),
      isEditable: isEditable,
      allowReplacements: allowReplacements,
      decorationVersion: TextPluginScope.decorationVersionOf(context),
      builder: builder,
    );
  }

  /// How many of these widgets were built, for tests and benchmarks.
  static int debugBuildCount = 0;

  /// The plugins of the text, in paint order.
  final List<TextPlugin> plugins;

  /// The undecorated span.
  final InlineSpan text;

  /// The directionality of the text.
  final TextDirection textDirection;

  /// Whether the text is editable.
  final bool isEditable;

  /// Whether a [TextSpanDecoration.replacement] is applied. False for a text
  /// field, whose text has to stay the same string.
  final bool allowReplacements;

  /// See [TextPluginScope.decorationVersionOf]. It is only here so that the
  /// widget is different when the version is.
  final int decorationVersion;

  /// Builds the text with the decorated span.
  final Widget Function(InlineSpan text, TextDelegateSet? delegates) builder;

  @override
  State<TextPluginSpanBuilder> createState() => _TextPluginSpanBuilderState();
}

class _TextPluginSpanBuilderState extends State<TextPluginSpanBuilder> {
  late final TextDelegateSet _set = TextDelegateSet(onNeedsDecoration: _handleNeedsDecoration);
  bool _building = false;

  void _handleNeedsDecoration() {
    // While this text is being built, the decorations are about to be asked
    // for anyway.
    if (_building || !mounted) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _set.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TextPluginSpanBuilder.debugBuildCount += 1;
    _building = true;
    try {
      _set.update(
        plugins: widget.plugins,
        span: widget.text,
        textDirection: widget.textDirection,
        isEditable: widget.isEditable,
        allowReplacements: widget.allowReplacements,
      );
      final DecoratedTextSpan decorated = _set.decorate();
      final Widget text = widget.builder(decorated.span, _set);
      // Stage 3, way S3: widgets on the text, without changing the text.
      if (!widget.plugins.any((TextPlugin plugin) => plugin is TextWidgetPlugin)) {
        return text;
      }
      return _buildWidgetHost(context, text);
    } finally {
      _building = false;
    }
  }

  final LayerLink _overlayLink = LayerLink();
  final OverlayPortalController _overlayController = OverlayPortalController();
  final GlobalKey _hostKey = GlobalKey();

  List<Widget> _widgetsFor(BuildContext context, TextWidgetLayer layer) {
    return <Widget>[
      for (final TextPlugin plugin in widget.plugins)
        if (plugin is TextWidgetPlugin)
          ...plugin.buildTextWidgets(context, _set.delegateFor(plugin)!, layer),
    ];
  }

  Widget _buildWidgetHost(BuildContext context, Widget text) {
    final Widget host = _TextWidgetHostBody(
      key: _hostKey,
      delegates: _set,
      background: _widgetsFor(context, TextWidgetLayer.background),
      text: text,
      foreground: _widgetsFor(context, TextWidgetLayer.foreground),
    );
    if (Overlay.maybeOf(context) == null) {
      return host;
    }
    // The overlay layer is always there, also without a widget in it, so that
    // the text is not created again when the first menu opens.
    if (!_overlayController.isShowing) {
      _overlayController.show();
    }
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (BuildContext overlayContext) {
        return CompositedTransformFollower(
          link: _overlayLink,
          showWhenUnlinked: false,
          child: _TextWidgetOverlayBody(
            delegates: _set,
            hostKey: _hostKey,
            children: _widgetsFor(overlayContext, TextWidgetLayer.overlay),
          ),
        );
      },
      child: CompositedTransformTarget(link: _overlayLink, child: host),
    );
  }
}

/// Where a widget of a [TextWidgetPlugin] is, relative to the text.
enum TextWidgetLayer {
  /// Behind the glyphs.
  background,

  /// In front of the glyphs, and clipped and scrolled with the text.
  foreground,

  /// In the [Overlay]: over everything else in the route, and not clipped
  /// with the text. It follows the text when the text moves.
  overlay,
}

/// Stage 3 of the text plugin design, way S3: a plugin that builds widgets
/// and places them on ranges of a text, without changing the text.
///
/// This is a small version of the design on the `text-plugin-with-widget`
/// branch, rebuilt on the inline-span prototype. It needs
/// [TextDecorationLayer.widget]: the widget that owns the delegates of a text
/// is also the host of these widgets.
mixin TextWidgetPlugin on TextPlugin {
  /// Returns the widgets for [layer] of the text of [delegate].
  ///
  /// Each widget has to be a [TextPositioned]. The plugin gives a range, and
  /// the framework reads the layout of the text. The plugin does not see it.
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  );
}

/// Parent data of a child of the host of a [TextWidgetPlugin].
class TextWidgetParentData extends ContainerBoxParentData<RenderBox> {
  /// The range that the child is placed on. Null for the text itself.
  TextRange? range;

  /// Whether the child covers the bounding box of [range] exactly.
  bool fill = true;

  /// The point of the bounding box of [range] that [followerAnchor] is lined
  /// up with.
  Alignment targetAnchor = Alignment.bottomLeft;

  /// The point of the child that is lined up with [targetAnchor].
  Alignment followerAnchor = Alignment.topLeft;

  /// A shift after the anchors are lined up.
  Offset shift = Offset.zero;

  /// Whether the child has a place. False until the text has a layout.
  bool placed = false;
}

/// Places [child] on a range of the text of a [TextWidgetPlugin].
class TextPositioned extends ParentDataWidget<TextWidgetParentData> {
  /// Lines up [followerAnchor] of [child] with [targetAnchor] of the bounding
  /// box of [range], then shifts the child by [offset].
  const TextPositioned({
    super.key,
    required this.range,
    this.targetAnchor = Alignment.bottomLeft,
    this.followerAnchor = Alignment.topLeft,
    this.offset = Offset.zero,
    required super.child,
  }) : fill = false;

  /// Sizes and positions [child] to cover the bounding box of [range].
  const TextPositioned.fill({super.key, required this.range, required super.child})
    : fill = true,
      targetAnchor = Alignment.topLeft,
      followerAnchor = Alignment.topLeft,
      offset = Offset.zero;

  /// The range, in [TextDelegate.text].
  final TextRange range;

  /// Whether the child covers the bounding box of the range.
  final bool fill;

  /// The point of the bounding box of [range] that the child is lined up
  /// with.
  final Alignment targetAnchor;

  /// The point of the child that is lined up with [targetAnchor].
  final Alignment followerAnchor;

  /// A shift after the anchors are lined up.
  final Offset offset;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as TextWidgetParentData;
    parentData
      ..range = range
      ..fill = fill
      ..targetAnchor = targetAnchor
      ..followerAnchor = followerAnchor
      ..shift = offset;
    // The text may have a new layout even if the range is the same, so the
    // child is always placed again.
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => TextWidgetPlugin;
}

class _TextWidgetHostBody extends MultiChildRenderObjectWidget {
  _TextWidgetHostBody({
    super.key,
    required this.delegates,
    required List<Widget> background,
    required Widget text,
    required List<Widget> foreground,
  }) : backgroundCount = background.length,
       super(children: <Widget>[...background, text, ...foreground]);

  final TextDelegateSet delegates;
  final int backgroundCount;

  @override
  _RenderTextWidgetHost createRenderObject(BuildContext context) {
    return _RenderTextWidgetHost(delegates: delegates, textIndex: backgroundCount);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTextWidgetHost renderObject) {
    renderObject
      ..delegates = delegates
      ..textIndex = backgroundCount;
  }
}

class _TextWidgetOverlayBody extends MultiChildRenderObjectWidget {
  const _TextWidgetOverlayBody({required this.delegates, required this.hostKey, super.children});

  final TextDelegateSet delegates;
  final GlobalKey hostKey;

  @override
  _RenderTextWidgetHost createRenderObject(BuildContext context) {
    return _RenderTextWidgetHost(delegates: delegates, textIndex: -1, hostKey: hostKey);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTextWidgetHost renderObject) {
    renderObject
      ..delegates = delegates
      ..hostKey = hostKey;
  }
}

// Lays out the text and the widgets that plugins place on it.
//
// With a [textIndex], the child at that index is the text, and this box has
// its size. The children before it are behind the text, the ones after it in
// front. Without one ([textIndex] is -1) this is the overlay layer: it has no
// size, and its children are placed relative to the box of [hostKey].
class _RenderTextWidgetHost extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, TextWidgetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, TextWidgetParentData> {
  _RenderTextWidgetHost({required this.delegates, required this.textIndex, this.hostKey});

  TextDelegateSet delegates;
  int textIndex;
  GlobalKey? hostKey;

  bool get _isOverlay => textIndex < 0;

  RenderBox? get _text {
    if (_isOverlay) {
      return null;
    }
    RenderBox? child = firstChild;
    for (var i = 0; i < textIndex && child != null; i += 1) {
      child = childAfter(child);
    }
    return child;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! TextWidgetParentData) {
      child.parentData = TextWidgetParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => _text?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _text?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) => _text?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) => _text?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return _text?.getDistanceToActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return _text?.getDryLayout(constraints) ?? constraints.smallest;
  }

  // The rectangle of a range, in the coordinates of this box. This is the one
  // place where the widgets layer reads the layout of the text. A plugin only
  // gives the range.
  Rect? _rectFor(TextRange range) {
    final TextDelegateHostMixin? text = delegates.host;
    if (text == null || !text.attached) {
      return null;
    }
    final Rect? rect = text.debugRectForUndecoratedRange(range);
    if (rect == null) {
      return null;
    }
    final RenderObject? reference = _isOverlay ? hostKey?.currentContext?.findRenderObject() : this;
    if (reference == null) {
      return null;
    }
    return MatrixUtils.transformRect(text.getTransformTo(reference), rect);
  }

  @override
  void performLayout() {
    final RenderBox? text = _text;
    if (text != null) {
      text.layout(constraints, parentUsesSize: true);
      (text.parentData! as TextWidgetParentData).offset = Offset.zero;
      size = text.size;
    } else {
      size = constraints.smallest;
    }
    RenderBox? child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as TextWidgetParentData;
      if (!identical(child, text)) {
        final TextRange? range = parentData.range;
        final Rect? rect = range == null ? null : _rectFor(range);
        if (rect == null) {
          child.layout(BoxConstraints.tight(Size.zero));
          parentData.placed = false;
        } else if (parentData.fill) {
          child.layout(BoxConstraints.tight(rect.size));
          parentData.offset = rect.topLeft;
          parentData.placed = true;
        } else {
          child.layout(const BoxConstraints(), parentUsesSize: true);
          parentData.offset =
              rect.topLeft +
              parentData.targetAnchor.alongSize(rect.size) -
              parentData.followerAnchor.alongSize(child.size) +
              parentData.shift;
          parentData.placed = true;
        }
      }
      child = parentData.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    final RenderBox? text = _text;
    while (child != null) {
      final parentData = child.parentData! as TextWidgetParentData;
      if (identical(child, text) || parentData.placed) {
        context.paintChild(child, parentData.offset + offset);
      }
      child = parentData.nextSibling;
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // The overlay layer has no size. Its children are where the text is.
    if (_isOverlay) {
      return hitTestChildren(result, position: position);
    }
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? text = _text;
    RenderBox? child = lastChild;
    while (child != null) {
      final parentData = child.parentData! as TextWidgetParentData;
      if (identical(child, text) || parentData.placed) {
        final bool isHit = result.addWithPaintOffset(
          offset: parentData.offset,
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return child!.hitTest(result, position: transformed);
          },
        );
        if (isHit) {
          return true;
        }
      }
      child = parentData.previousSibling;
    }
    return false;
  }
}
