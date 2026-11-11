// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'editable_text.dart';
/// @docImport 'scroll_view.dart';
/// @docImport 'text.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'basic.dart';
import 'framework.dart';
import 'layout_builder.dart';
import 'overlay.dart';
import 'selection_container.dart';
import 'slotted_render_object_widget.dart';
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
  const TextPluginScope({super.key, required TextPlugin this.plugin, required this.child})
    : plugins = null,
      types = null,
      _disabled = false;

  /// Creates a scope that installs multiple [plugins] for all [Text],
  /// [RichText], and [EditableText] widgets in [child], composing with any
  /// ancestor [TextPluginScope]s.
  const TextPluginScope.multiple({
    super.key,
    required List<TextPlugin> this.plugins,
    required this.child,
  }) : plugin = null,
       types = null,
       _disabled = false;

  /// Creates a scope that excludes any ancestor [TextPlugin]s whose
  /// [Object.runtimeType] is in [types] for [child].
  const TextPluginScope.exclude({super.key, required Set<Type> this.types, required this.child})
    : plugin = null,
      plugins = null,
      _disabled = false;

  /// Creates a scope that disables any ancestor [TextPluginScope]s for [child].
  const TextPluginScope.none({super.key, required this.child})
    : plugin = null,
      plugins = null,
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
    if (updated != _localRequiresOffscreenScan) {
      setState(() {
        _localRequiresOffscreenScan = updated;
      });
    }
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
    if (widget._disabled) {
      return OffscreenContentRenderingStrategy(
        policy: const OffscreenRenderingPolicy.lazy(),
        child: _InheritedTextPluginScope(
          pluginMap: const <Type, TextPlugin>{},
          plugins: const <TextPlugin>[],
          child: widget.child,
        ),
      );
    }
    final _InheritedTextPluginScope? ancestorScope = context
        .dependOnInheritedWidgetOfExactType<_InheritedTextPluginScope>();
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
        child: widget.child,
      ),
    );
  }
}

class _InheritedTextPluginScope extends InheritedWidget {
  const _InheritedTextPluginScope({
    required this.pluginMap,
    required this.plugins,
    required super.child,
  });

  final Map<Type, TextPlugin> pluginMap;
  final List<TextPlugin> plugins;

  @override
  bool updateShouldNotify(_InheritedTextPluginScope oldWidget) {
    return !listEquals(plugins, oldWidget.plugins);
  }
}

/// A layer in which a [TextWidgetPlugin] builds widgets for a text widget.
///
/// From back to front, a text widget and its layers are stacked like this:
///
///  1. [background]
///  2. The text itself, including the [TextDelegate.backgroundPainter] and
///     [TextDelegate.foregroundPainter] of every [TextPlugin].
///  3. [foreground]
///  4. Everything else in the same route that is painted after the text.
///  5. [overlay]
enum TextWidgetLayer {
  /// Behind the text, in the coordinate space of the text widget.
  ///
  /// Widgets in this layer move with the text and are clipped by the same
  /// ancestors as the text. They do not receive pointer events, because the
  /// text widget is in front of them.
  background,

  /// In front of the text, in the coordinate space of the text widget.
  ///
  /// Widgets in this layer move with the text, are clipped by the same
  /// ancestors as the text, and are hit tested before the text. A widget that
  /// extends past the bounds of the text widget is painted there, but cannot
  /// be hit there.
  foreground,

  /// In the nearest [Overlay], above the route that contains the text widget.
  ///
  /// Widgets in this layer follow the text widget when it moves, but they are
  /// not clipped by its ancestors and they paint above everything else in the
  /// route. Use this layer for content that floats, such as a hover card or a
  /// menu.
  ///
  /// The widgets are shown with an [OverlayPortal], which only exists while a
  /// plugin has widgets in this layer. The layer is not built when the text
  /// widget has no [Overlay] ancestor.
  overlay,
}

/// A [TextPlugin] that builds widgets behind, in front of, or floating above
/// the text widgets it covers.
///
/// [TextDelegate.backgroundPainter] and [TextDelegate.foregroundPainter] can
/// only draw. A plugin that mixes in [TextWidgetPlugin] can place real widgets
/// on the text as well, for example a button next to a range, an animated
/// widget, or a card that appears on hover.
///
/// [Text] and [EditableText] host these widgets automatically. A [RichText] or
/// a custom text render object has to be wrapped in a [TextPluginWidgetHost].
///
/// The widgets are ordinary widgets below the text widget in the widget tree.
/// Gestures, focus, semantics and inherited widgets work for them like for
/// any other widget. Text plugins and [SelectionContainer]s above the text
/// widget do not apply to them.
///
/// ## When the widgets are built
///
/// [buildTextWidgets] is called during layout, right after the text widget
/// has been laid out. The widgets are therefore laid out and painted in the
/// same frame as the text they decorate, and [TextDelegate] layout queries
/// are valid inside the method.
///
/// This is earlier than [didAddText], [didUpdateText] and [didLayoutText],
/// which are called once the whole layout phase is over. In the frame in
/// which a text widget appears or changes, [buildTextWidgets] runs before
/// those callbacks. Treat it like [State.build]: derive the widgets from the
/// [TextDelegate] it is given, not from state that the callbacks collect.
///
/// The method is called again whenever the text widget is rebuilt or laid
/// out, and when its selection changes. To also rebuild the widgets when the
/// plugin's own state changes, make the plugin a [Listenable] (for example
/// with [ChangeNotifier]) and notify its listeners. If that happens while a
/// frame is being produced, the widgets are rebuilt in the next frame.
///
/// {@tool snippet}
/// This plugin puts a small marker above the end of every `@mention`.
///
/// ```dart
/// class MentionMarkerPlugin extends TextPlugin with TextWidgetPlugin {
///   const MentionMarkerPlugin();
///
///   static final RegExp _mention = RegExp(r'@\w+');
///
///   @override
///   Iterable<Widget> buildTextWidgets(
///     BuildContext context,
///     TextDelegate delegate,
///     TextWidgetLayer layer,
///   ) {
///     return <Widget>[
///       for (final RegExpMatch match in _mention.allMatches(delegate.text))
///         TextPositioned(
///           delegate: delegate,
///           range: TextRange(start: match.start, end: match.end),
///           targetAnchor: Alignment.topRight,
///           followerAnchor: Alignment.bottomRight,
///           child: const SizedBox.square(
///             dimension: 6.0,
///             child: ColoredBox(color: Color(0xFF2196F3)),
///           ),
///         ),
///     ];
///   }
/// }
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [TextPositioned], which positions a widget relative to a range of text.
///  * [TextWidgetLayer], which describes the layers a plugin can build in.
mixin TextWidgetPlugin on TextPlugin {
  /// The layers this plugin builds widgets in.
  ///
  /// [buildTextWidgets] is only called for these layers, and a text widget
  /// only creates the layers that one of its plugins asks for. The value is
  /// read when the text widget is built, so it should not change over the
  /// lifetime of the plugin.
  ///
  /// Defaults to [TextWidgetLayer.foreground].
  Set<TextWidgetLayer> get widgetLayers => const <TextWidgetLayer>{TextWidgetLayer.foreground};

  /// Builds the widgets to show in [layer] for the text widget represented by
  /// [delegate].
  ///
  /// The coordinate space of every layer has its origin at the top left of the
  /// text widget. Wrap a widget in [TextPositioned] to place it relative to a
  /// range of text. A widget that is not wrapped in [TextPositioned] covers
  /// the text widget.
  ///
  /// See the class documentation for when this method is called.
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  );
}

/// Parent data used by [TextPositioned] to position a widget in a layer of a
/// [TextWidgetPlugin].
class TextWidgetParentData extends ContainerBoxParentData<RenderBox> {
  /// Whether the child is wrapped in a [TextPositioned].
  ///
  /// A child that is not positioned covers the text widget.
  bool isPositioned = false;

  /// The rectangle the child is positioned against, in the coordinate space
  /// of the text widget.
  ///
  /// Null when the range of a [TextPositioned] is not valid or has no boxes,
  /// for example because the text was truncated before it. The child is then
  /// not painted and cannot be hit.
  Rect? rect;

  /// Whether the child is sized to cover [rect] exactly.
  bool fill = false;

  /// The point of [rect] that [followerAnchor] is lined up with.
  Alignment targetAnchor = Alignment.topLeft;

  /// The point of the child that is lined up with [targetAnchor].
  Alignment followerAnchor = Alignment.topLeft;

  /// An additional offset applied after the anchors are lined up.
  Offset positionOffset = Offset.zero;

  /// Whether the child takes part in painting, hit testing and semantics.
  bool get isVisible => !isPositioned || rect != null;

  @override
  String toString() {
    if (!isPositioned) {
      return '${super.toString()}; covers the text';
    }
    return '${super.toString()}; rect=$rect; '
        '${fill ? 'fill' : 'targetAnchor=$targetAnchor; followerAnchor=$followerAnchor'}';
  }
}

/// Positions [child] relative to a range of text, in a layer built by a
/// [TextWidgetPlugin].
///
/// Use this widget for the widgets returned from
/// [TextWidgetPlugin.buildTextWidgets].
///
/// The default constructor lines up a point of the child ([followerAnchor])
/// with a point of the bounding box of [range] ([targetAnchor]) and lets the
/// child choose its own size. [TextPositioned.fill] sizes the child to cover
/// the bounding box. [TextPositioned.fromRect] does the same for a rectangle
/// that the plugin computed itself, for example one of the boxes returned by
/// [TextDelegate.getBoxesForSelection].
///
/// When [range] is collapsed, the child is positioned against the caret at
/// that offset, which is a rectangle without width. This is how to place a
/// handle or a cursor.
///
/// When [range] is not valid, or it has no boxes because the text was
/// truncated before it, the child is kept in the tree but is not painted and
/// cannot be hit.
class TextPositioned extends ParentDataWidget<TextWidgetParentData> {
  /// Lines up [followerAnchor] of [child] with [targetAnchor] of the bounding
  /// box of [range], then shifts the child by [offset].
  ///
  /// The child is given unbounded constraints, so it has to have a size of
  /// its own.
  const TextPositioned({
    super.key,
    required TextDelegate this.delegate,
    required TextRange this.range,
    this.targetAnchor = Alignment.topLeft,
    this.followerAnchor = Alignment.topLeft,
    this.offset = Offset.zero,
    required super.child,
  }) : rect = null,
       fill = false;

  /// Sizes and positions [child] to cover the bounding box of [range].
  const TextPositioned.fill({
    super.key,
    required TextDelegate this.delegate,
    required TextRange this.range,
    required super.child,
  }) : rect = null,
       fill = true,
       targetAnchor = Alignment.topLeft,
       followerAnchor = Alignment.topLeft,
       offset = Offset.zero;

  /// Sizes and positions [child] to cover [rect], which is in the coordinate
  /// space of the text widget.
  const TextPositioned.fromRect({super.key, required Rect this.rect, required super.child})
    : delegate = null,
      range = null,
      fill = true,
      targetAnchor = Alignment.topLeft,
      followerAnchor = Alignment.topLeft,
      offset = Offset.zero;

  /// The delegate of the text widget that [range] refers to.
  ///
  /// Null when this widget was created with [TextPositioned.fromRect].
  final TextDelegate? delegate;

  /// The range of text the child is positioned against, in UTF-16 offsets of
  /// [TextDelegate.text].
  ///
  /// Null when this widget was created with [TextPositioned.fromRect].
  final TextRange? range;

  /// The rectangle the child covers, in the coordinate space of the text
  /// widget.
  ///
  /// Only set by [TextPositioned.fromRect].
  final Rect? rect;

  /// Whether the child is sized to cover the rectangle exactly.
  final bool fill;

  /// The point of the bounding box of [range] that [followerAnchor] is lined
  /// up with.
  final Alignment targetAnchor;

  /// The point of [child] that is lined up with [targetAnchor].
  final Alignment followerAnchor;

  /// An additional offset applied after the anchors are lined up.
  final Offset offset;

  Rect? _resolveRect(Rect? previous) {
    if (rect != null) {
      return rect;
    }
    final TextDelegate delegate = this.delegate!;
    if (delegate.isDisposed || !delegate.hasLayout) {
      // The text is being laid out again. Keep the previous position until
      // the layer is rebuilt with the new layout.
      return previous;
    }
    final TextRange range = this.range!;
    if (!range.isValid) {
      return null;
    }
    if (range.isCollapsed) {
      final position = TextPosition(offset: range.start);
      final Offset caret = delegate.getOffsetForCaret(position, Rect.zero);
      return Rect.fromLTWH(caret.dx, caret.dy, 0.0, delegate.getFullHeightForCaret(position));
    }
    final List<TextBox> boxes = delegate.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    if (boxes.isEmpty) {
      return null;
    }
    Rect bounds = boxes.first.toRect();
    for (var i = 1; i < boxes.length; i += 1) {
      bounds = bounds.expandToInclude(boxes[i].toRect());
    }
    return bounds;
  }

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as TextWidgetParentData;
    final Rect? resolvedRect = _resolveRect(parentData.rect);
    var needsLayout = false;
    if (!parentData.isPositioned) {
      parentData.isPositioned = true;
      needsLayout = true;
    }
    if (parentData.rect != resolvedRect) {
      parentData.rect = resolvedRect;
      needsLayout = true;
    }
    if (parentData.fill != fill) {
      parentData.fill = fill;
      needsLayout = true;
    }
    if (parentData.targetAnchor != targetAnchor) {
      parentData.targetAnchor = targetAnchor;
      needsLayout = true;
    }
    if (parentData.followerAnchor != followerAnchor) {
      parentData.followerAnchor = followerAnchor;
      needsLayout = true;
    }
    if (parentData.positionOffset != offset) {
      parentData.positionOffset = offset;
      needsLayout = true;
    }
    if (needsLayout) {
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _TextWidgetLayerBody;

  @override
  String get debugTypicalAncestorWidgetDescription =>
      'the list returned from TextWidgetPlugin.buildTextWidgets';

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<TextRange>('range', range, defaultValue: null));
    properties.add(DiagnosticsProperty<Rect>('rect', rect, defaultValue: null));
    properties.add(FlagProperty('fill', value: fill, ifTrue: 'fill'));
    properties.add(
      DiagnosticsProperty<Alignment>('targetAnchor', targetAnchor, defaultValue: Alignment.topLeft),
    );
    properties.add(
      DiagnosticsProperty<Alignment>(
        'followerAnchor',
        followerAnchor,
        defaultValue: Alignment.topLeft,
      ),
    );
    properties.add(DiagnosticsProperty<Offset>('offset', offset, defaultValue: Offset.zero));
  }
}

/// Hosts the widgets that [TextWidgetPlugin]s build for one text widget.
///
/// [Text] and [EditableText] insert this widget around their render object
/// when a [TextWidgetPlugin] is in scope, so most code never uses it directly.
/// Wrap a [RichText], or a widget whose render object mixes in
/// [TextDelegateHostMixin], in a [TextPluginWidgetHost] to give it the same
/// support.
///
/// The host takes the size of [child]. Its other children are the layers that
/// the plugins ask for (see [TextWidgetLayer]). Each layer builds its widgets
/// while it is laid out, and the layers are always laid out after [child], so
/// that [TextWidgetPlugin.buildTextWidgets] can read the layout of the text.
///
/// [child] should be the text widget itself. If its render object is not a
/// [RenderParagraph], a [RenderEditable] or a [TextDelegateHostMixin], the
/// first such render object below it is taken to be the text. In that case
/// the plugin widgets can be one frame late when the text is laid out again
/// without [child] being laid out.
class TextPluginWidgetHost extends StatefulWidget {
  /// Creates a host for the widgets that [plugins] build for [child].
  const TextPluginWidgetHost({
    super.key,
    this.plugins,
    this.clipBehavior = Clip.none,
    this.rebuildListenable,
    required this.child,
  });

  /// Wraps [child] in a [TextPluginWidgetHost] if one of [plugins] is a
  /// [TextWidgetPlugin], and returns [child] unchanged otherwise.
  ///
  /// If [plugins] is null, the plugins of the enclosing [TextPluginScope] are
  /// used. Text widgets call this from their build method, so a text widget
  /// without widget plugins only pays for the lookup.
  static Widget maybeWrap(
    BuildContext context, {
    List<TextPlugin>? plugins,
    Clip clipBehavior = Clip.none,
    Listenable? rebuildListenable,
    required Widget child,
  }) {
    final List<TextPlugin>? effectivePlugins = plugins ?? TextPluginScope.maybeOf(context);
    if (effectivePlugins == null ||
        !effectivePlugins.any((TextPlugin plugin) => plugin is TextWidgetPlugin)) {
      return child;
    }
    return TextPluginWidgetHost(
      plugins: effectivePlugins,
      clipBehavior: clipBehavior,
      rebuildListenable: rebuildListenable,
      child: child,
    );
  }

  /// The plugins of the text widget, in paint order.
  ///
  /// This must be the list that the text render object was given. If null,
  /// the plugins of the enclosing [TextPluginScope] are used.
  final List<TextPlugin>? plugins;

  /// How the [TextWidgetLayer.background] and [TextWidgetLayer.foreground]
  /// layers are clipped to the bounds of [child].
  ///
  /// Defaults to [Clip.none]. Text that scrolls inside its own bounds, like
  /// [EditableText], should clip.
  final Clip clipBehavior;

  /// Rebuilds the plugin widgets whenever it notifies.
  ///
  /// Use this for changes that move the text without laying it out again,
  /// such as the scroll offset of an [EditableText].
  final Listenable? rebuildListenable;

  /// The text widget.
  final Widget child;

  @override
  State<TextPluginWidgetHost> createState() => _TextPluginWidgetHostState();
}

class _TextPluginWidgetHostState extends State<TextPluginWidgetHost> {
  final _TextWidgetHostController _controller = _TextWidgetHostController();

  // What each layer showed the last time it was built.
  final Map<TextWidgetLayer, Widget> _builtLayers = <TextWidgetLayer, Widget>{};

  List<TextWidgetPlugin> _plugins = const <TextWidgetPlugin>[];
  List<Listenable> _listenables = const <Listenable>[];
  TextDelegate? _observedDelegate;
  bool _rebuildScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePlugins();
  }

  @override
  void didUpdateWidget(TextPluginWidgetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePlugins();
  }

  @override
  void dispose() {
    for (final Listenable listenable in _listenables) {
      listenable.removeListener(_scheduleRebuild);
    }
    _stopObserving();
    super.dispose();
  }

  void _updatePlugins() {
    final List<TextPlugin> allPlugins = widget.plugins ?? TextPluginScope.of(context);
    _plugins = <TextWidgetPlugin>[
      for (final TextPlugin plugin in allPlugins)
        if (plugin is TextWidgetPlugin) plugin,
    ];
    final listenables = <Listenable>[
      for (final TextWidgetPlugin plugin in _plugins)
        if (plugin case final Listenable listenable) listenable,
      ?widget.rebuildListenable,
    ];
    if (listEquals(listenables, _listenables)) {
      return;
    }
    for (final Listenable listenable in _listenables) {
      listenable.removeListener(_scheduleRebuild);
    }
    for (final listenable in listenables) {
      listenable.addListener(_scheduleRebuild);
    }
    _listenables = listenables;
  }

  // Rebuilds this widget, which gives every layer a new builder and so makes
  // it rebuild during the next layout.
  void _scheduleRebuild() {
    if (!mounted) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    // A frame is being built, laid out or painted. This widget cannot be
    // marked dirty now, and layout must not be dirtied once it is over, so
    // look again when the frame is done.
    if (_rebuildScheduled) {
      return;
    }
    _rebuildScheduled = true;
    final int buildCount = _controller.buildCount;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _rebuildScheduled = false;
      // Nothing is left to do if the layers were built later in that frame,
      // which is what happens when the request came before layout.
      if (mounted && !_controller.layersBuiltSince(buildCount)) {
        setState(() {});
      }
    }, debugLabel: 'TextPluginWidgetHost.rebuild');
  }

  // Called when the text or its layout changed, once the layout phase is over,
  // and when the selection changed.
  void _handleDelegateChanged() {
    if (_controller.layersBuiltInThisPass) {
      // The layers were built after the text was laid out, in the layout
      // phase that just ended. They are up to date.
      return;
    }
    // The selection changed, or the text was laid out without its layers
    // (which can only happen when the text is not the child of the host
    // render object). Catch up.
    _scheduleRebuild();
  }

  void _observe(TextDelegate delegate) {
    final TextDelegate? observed = _observedDelegate;
    if (observed != null && !observed.isDisposed) {
      // All delegates of one text widget change together, so one is enough.
      return;
    }
    _stopObserving();
    _observedDelegate = delegate..addListener(_handleDelegateChanged);
    if (identical(delegate.renderObject, _controller.host?.textChild)) {
      // When the text is marked as needing layout, mark the layers as well.
      // They are then rebuilt in the same layout phase, after the text,
      // because they are deeper than the text (see
      // _RenderTextPluginWidgetHost).
      //
      // During the layout phase, the text can only be marked from the layout
      // callback of one of its ancestors. Marking the layers at that moment
      // is allowed when that ancestor is also an ancestor of the layers,
      // which is only certain when the text is the child of the host render
      // object.
      delegate.onLayoutInvalidated = _controller.markLayersNeedBuild;
    }
  }

  void _stopObserving() {
    final TextDelegate? observed = _observedDelegate;
    if (observed == null) {
      return;
    }
    observed.removeListener(_handleDelegateChanged);
    observed.onLayoutInvalidated = null;
    _observedDelegate = null;
  }

  // Called while the layer is being laid out.
  Widget _buildLayer(BuildContext context, TextWidgetLayer layer) {
    final delegates = <TextWidgetPlugin, TextDelegate>{};
    if (_controller.textRenderObject case final RenderObject text) {
      for (final TextWidgetPlugin plugin in _plugins) {
        if (!plugin.widgetLayers.contains(layer)) {
          continue;
        }
        final TextDelegate? delegate = _textDelegateFor(text, plugin);
        if (delegate != null && !delegate.isDisposed) {
          delegates[plugin] = delegate;
        }
      }
    }
    if (delegates.isNotEmpty) {
      final TextDelegate delegate = delegates.values.first;
      _observe(delegate);
      if (!delegate.hasLayout) {
        // The text is waiting to be laid out and this layer was reached
        // first, which can only happen when the text is not the child of the
        // host render object. Keep what the layer shows. It is rebuilt when
        // the text reports its new layout (see _handleDelegateChanged).
        return _builtLayers[layer] ?? const SizedBox.shrink();
      }
    }

    final Widget built = _buildLayerContent(context, layer, delegates);
    _builtLayers[layer] = built;
    _controller.didBuildLayer(context.findRenderObject()! as _RenderTextWidgetLayer);
    return built;
  }

  Widget _buildLayerContent(
    BuildContext context,
    TextWidgetLayer layer,
    Map<TextWidgetPlugin, TextDelegate> delegates,
  ) {
    if (delegates.isEmpty) {
      // None of the plugins is installed on the text render object.
      return const SizedBox.shrink();
    }
    // A copy, because in debug mode the size of a render object remembers its
    // owner and cannot be used to lay out another render object.
    final textSize = Size.copy(delegates.values.first.size);
    // One body per plugin, so that the keys of different plugins cannot
    // collide and the plugins stack in paint order.
    final bodies = <Widget>[];
    final typeCounts = <Type, int>{};
    for (final MapEntry<TextWidgetPlugin, TextDelegate> entry in delegates.entries) {
      final TextWidgetPlugin plugin = entry.key;
      final TextDelegate delegate = entry.value;
      final int index = typeCounts.update(
        plugin.runtimeType,
        (int count) => count + 1,
        ifAbsent: () => 0,
      );
      final List<Widget> widgets = plugin
          .buildTextWidgets(context, delegate, layer)
          .toList(growable: false);
      if (widgets.isEmpty) {
        continue;
      }
      bodies.add(
        _TextWidgetLayerBody(
          // Keeps the state of a plugin's widgets when another plugin starts
          // or stops showing widgets.
          key: delegates.length == 1 ? null : ValueKey<(Type, int)>((plugin.runtimeType, index)),
          textSize: textSize,
          children: widgets,
        ),
      );
    }
    if (bodies.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget content = delegates.length == 1
        ? bodies.single
        : _TextWidgetLayerBody(textSize: textSize, children: bodies);
    if (layer == TextWidgetLayer.overlay) {
      content = _TextOverlayPortal(child: content);
    }
    // The widgets are decorations of this text widget. They are not text for
    // the plugins to decorate in turn (a plugin that shows a Text would
    // otherwise be asked for the widgets of that Text, and so on), and they
    // are not part of the text that is being selected.
    return TextPluginScope.none(child: SelectionContainer.disabled(child: content));
  }

  Widget _layer(TextWidgetLayer layer) {
    final Widget result = _TextWidgetLayer(
      controller: _controller,
      layerBuilder: (BuildContext context) => _buildLayer(context, layer),
    );
    if (layer == TextWidgetLayer.overlay || widget.clipBehavior == Clip.none) {
      return result;
    }
    return ClipRect(clipBehavior: widget.clipBehavior, child: result);
  }

  @override
  Widget build(BuildContext context) {
    final layers = <TextWidgetLayer>{
      for (final TextWidgetPlugin plugin in _plugins) ...plugin.widgetLayers,
    };
    if (layers.contains(TextWidgetLayer.overlay) && Overlay.maybeOf(context) == null) {
      layers.remove(TextWidgetLayer.overlay);
    }
    _builtLayers.removeWhere((TextWidgetLayer layer, Widget _) => !layers.contains(layer));
    return _TextPluginWidgetHostBox(
      controller: _controller,
      text: widget.child,
      layers: <TextWidgetLayer, Widget>{
        for (final TextWidgetLayer layer in layers) layer: _layer(layer),
      },
    );
  }
}

TextDelegate? _textDelegateFor(RenderObject textRenderObject, TextPlugin plugin) {
  return switch (textRenderObject) {
    final RenderParagraph paragraph => paragraph.textDelegateFor(plugin),
    final RenderEditable editable => editable.textDelegateFor(plugin),
    final TextDelegateHostMixin host => host.textDelegateFor(plugin),
    _ => null,
  };
}

/// What the host render object, its layers and the host state share.
class _TextWidgetHostController {
  _RenderTextPluginWidgetHost? host;

  final Set<_RenderTextWidgetLayer> layers = <_RenderTextWidgetLayer>{};

  /// Changes every time the host render object is laid out, which makes the
  /// layers rebuild.
  int generation = 0;

  /// How many times a layer has been built from an up-to-date text layout.
  int buildCount = 0;

  // The value of buildCount when the current layout phase began.
  int _buildCountAtPassStart = 0;
  bool _passEndScheduled = false;

  RenderObject? get textRenderObject {
    RenderObject? node = host?.textChild;
    while (node != null) {
      if (node is RenderParagraph || node is RenderEditable || node is TextDelegateHostMixin) {
        return node;
      }
      RenderObject? firstChild;
      node.visitChildren((RenderObject child) {
        firstChild ??= child;
      });
      node = firstChild;
    }
    return null;
  }

  void markLayersNeedBuild() {
    generation += 1;
    for (final _RenderTextWidgetLayer layer in layers) {
      if (layer.attached) {
        layer.scheduleLayoutCallback();
      }
    }
  }

  void didBuildLayer(_RenderTextWidgetLayer layer) {
    buildCount += 1;
    layer.lastBuild = buildCount;
    if (_passEndScheduled) {
      return;
    }
    _passEndScheduled = true;
    // Runs when the layout phase is over. The text widget schedules its own
    // callback, which notifies its plugins and delegates, no later than when
    // it is laid out. That is before any layer is built from that layout, so
    // this callback runs after the text has sent its notifications.
    layer.owner!.schedulePostLayoutCallback(() {
      _passEndScheduled = false;
      _buildCountAtPassStart = buildCount;
    });
  }

  /// Whether every layer has been built since [buildCount] had the given
  /// value.
  bool layersBuiltSince(int buildCount) {
    return layers.every((_RenderTextWidgetLayer layer) => layer.lastBuild > buildCount);
  }

  /// Whether every layer has been built in the current layout phase.
  ///
  /// This stays true until the post-layout callbacks of that phase have run.
  bool get layersBuiltInThisPass => layersBuiltSince(_buildCountAtPassStart);
}

// In paint order.
enum _TextHostSlot { background, text, foreground, overlay }

class _TextPluginWidgetHostBox
    extends SlottedMultiChildRenderObjectWidget<_TextHostSlot, RenderBox> {
  const _TextPluginWidgetHostBox({
    required this.controller,
    required this.text,
    required this.layers,
  });

  final _TextWidgetHostController controller;
  final Widget text;
  final Map<TextWidgetLayer, Widget> layers;

  @override
  Iterable<_TextHostSlot> get slots => _TextHostSlot.values;

  @override
  Widget? childForSlot(_TextHostSlot slot) {
    return switch (slot) {
      _TextHostSlot.background => layers[TextWidgetLayer.background],
      _TextHostSlot.text => text,
      _TextHostSlot.foreground => layers[TextWidgetLayer.foreground],
      _TextHostSlot.overlay => layers[TextWidgetLayer.overlay],
    };
  }

  @override
  _RenderTextPluginWidgetHost createRenderObject(BuildContext context) {
    return _RenderTextPluginWidgetHost(controller);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTextPluginWidgetHost renderObject) {
    assert(identical(renderObject.controller, controller));
  }
}

/// Lays out the text widget, takes its size, and then lays out the plugin
/// layers with that size.
///
/// The layers are built from the layout of the text, so they must be laid out
/// after it. There are two ways in which a layer gets laid out, and this
/// render object keeps the order in both:
///
///  * When this render object is laid out, [performLayout] lays out the text
///    first.
///  * A layer is a relayout boundary, and the text can be one too. When they
///    are dirty without this render object being dirty, the [PipelineOwner]
///    lays them out in order of depth. The layers are therefore kept deeper
///    than the text (see [_redepthLayers]).
class _RenderTextPluginWidgetHost extends RenderBox
    with SlottedContainerRenderObjectMixin<_TextHostSlot, RenderBox> {
  _RenderTextPluginWidgetHost(this.controller);

  final _TextWidgetHostController controller;

  RenderBox? get textChild => childForSlot(_TextHostSlot.text);

  // In paint order.
  @override
  Iterable<RenderBox> get children {
    return <RenderBox>[for (final _TextHostSlot slot in _TextHostSlot.values) ?childForSlot(slot)];
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller.host = this;
  }

  @override
  void detach() {
    if (identical(controller.host, this)) {
      controller.host = null;
    }
    super.detach();
  }

  @override
  void adoptChild(RenderObject child) {
    super.adoptChild(child);
    _redepthLayers();
  }

  @override
  void redepthChildren() {
    super.redepthChildren();
    _redepthLayers();
  }

  void _redepthLayers() {
    final RenderBox? text = textChild;
    if (text == null) {
      return;
    }
    for (final RenderBox child in children) {
      if (!identical(child, text)) {
        text.redepthChild(child);
      }
    }
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;
    if (controller.layers.isNotEmpty) {
      // The text may be about to change, so the layers have to be rebuilt.
      // They are laid out below, after the text, or later by the
      // PipelineOwner.
      invokeLayoutCallback<BoxConstraints>((BoxConstraints _) {
        controller.markLayersNeedBuild();
      });
    }
    final RenderBox? text = textChild;
    if (text == null) {
      size = constraints.smallest;
    } else {
      text.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(text.size);
    }
    final layerConstraints = BoxConstraints.tight(size);
    for (final RenderBox child in children) {
      if (!identical(child, text)) {
        child.layout(layerConstraints);
      }
    }
  }

  // The layers do not take part in intrinsic sizes, dry layouts or baselines:
  // they have the size of the text, and they cannot be built speculatively.

  @override
  double computeMinIntrinsicWidth(double height) {
    return textChild?.getMinIntrinsicWidth(height) ?? 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return textChild?.getMaxIntrinsicWidth(height) ?? 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return textChild?.getMinIntrinsicHeight(width) ?? 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return textChild?.getMaxIntrinsicHeight(width) ?? 0.0;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return textChild?.getDryLayout(constraints) ?? constraints.smallest;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return textChild?.getDistanceToActualBaseline(baseline);
  }

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) {
    return textChild?.getDryBaseline(constraints, baseline);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Front to back.
    for (final RenderBox child in children.toList(growable: false).reversed) {
      if (child.hitTest(result, position: position)) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final RenderBox child in children) {
      context.paintChild(child, offset);
    }
  }
}

/// Builds one layer of plugin widgets during layout.
class _TextWidgetLayer extends AbstractLayoutBuilder<int> {
  const _TextWidgetLayer({required this.controller, required this.layerBuilder});

  final _TextWidgetHostController controller;
  final WidgetBuilder layerBuilder;

  @override
  Widget Function(BuildContext context, int generation) get builder {
    return (BuildContext context, int generation) => layerBuilder(context);
  }

  @override
  RenderAbstractLayoutBuilderMixin<int, RenderBox> createRenderObject(BuildContext context) {
    return _RenderTextWidgetLayer(controller);
  }
}

class _RenderTextWidgetLayer extends RenderProxyBox
    with RenderObjectWithLayoutCallbackMixin, RenderAbstractLayoutBuilderMixin<int, RenderBox> {
  _RenderTextWidgetLayer(this._controller);

  final _TextWidgetHostController _controller;

  /// The value of [_TextWidgetHostController.buildCount] when this layer was
  /// last built from an up-to-date text layout.
  int lastBuild = 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.layers.add(this);
  }

  @override
  void detach() {
    _controller.layers.remove(this);
    super.detach();
  }

  // The layer always has the size of the text, so that it is a relayout
  // boundary and rebuilding it never lays out the text again.
  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @protected
  @override
  int get layoutInfo => _controller.generation;

  @override
  void performLayout() {
    runLayoutCallback();
    child?.layout(BoxConstraints.tight(size));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0.0;

  @override
  double computeMinIntrinsicHeight(double width) => 0.0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0.0;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => null;
}

/// Shows [child] in the nearest [Overlay], with its origin at the top left of
/// this widget.
///
/// This widget is only in the tree while a plugin has widgets in
/// [TextWidgetLayer.overlay], so text widgets without such widgets do not pay
/// for an [OverlayPortal].
class _TextOverlayPortal extends StatefulWidget {
  const _TextOverlayPortal({required this.child});

  final Widget child;

  @override
  State<_TextOverlayPortal> createState() => _TextOverlayPortalState();
}

class _TextOverlayPortalState extends State<_TextOverlayPortal> {
  final LayerLink _link = LayerLink();
  // Shown from the start and never hidden. The overlay child goes away when
  // this widget is removed from the tree.
  final OverlayPortalController _controller = OverlayPortalController()..show();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (BuildContext context) {
          return CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// Lays out the widgets of one plugin in one layer.
///
/// The origin of this widget is the top left of the text widget.
class _TextWidgetLayerBody extends MultiChildRenderObjectWidget {
  const _TextWidgetLayerBody({super.key, required this.textSize, super.children});

  /// The size of the text widget, which children that are not wrapped in a
  /// [TextPositioned] are given.
  ///
  /// This is the size of this widget in the local layers. In the overlay
  /// layer this widget has the size of the [Overlay].
  final Size textSize;

  @override
  _RenderTextWidgetLayerBody createRenderObject(BuildContext context) {
    return _RenderTextWidgetLayerBody(textSize);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTextWidgetLayerBody renderObject) {
    renderObject.textSize = textSize;
  }
}

class _RenderTextWidgetLayerBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, TextWidgetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, TextWidgetParentData> {
  _RenderTextWidgetLayerBody(this._textSize);

  Size get textSize => _textSize;
  Size _textSize;
  set textSize(Size value) {
    if (value == _textSize) {
      return;
    }
    _textSize = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! TextWidgetParentData) {
      child.parentData = TextWidgetParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(textSize);

  @override
  void performLayout() {
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      final parentData = child.parentData! as TextWidgetParentData;
      final Rect? rect = parentData.rect;
      if (!parentData.isPositioned) {
        child.layout(BoxConstraints.tight(textSize));
        parentData.offset = Offset.zero;
      } else if (rect == null) {
        child.layout(BoxConstraints.tight(Size.zero));
        parentData.offset = Offset.zero;
      } else if (parentData.fill) {
        child.layout(BoxConstraints.tight(rect.size));
        parentData.offset = rect.topLeft;
      } else {
        child.layout(const BoxConstraints(), parentUsesSize: true);
        parentData.offset =
            parentData.targetAnchor.withinRect(rect) -
            parentData.followerAnchor.alongSize(child.size) +
            parentData.positionOffset;
      }
    }
  }

  // Plugin widgets may be placed outside the bounds of this render object. In
  // the overlay layer that is how a card ends up above or to the left of the
  // text, so the bounds are not checked.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    return hitTestChildren(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (RenderBox? child = lastChild; child != null; child = childBefore(child)) {
      final parentData = child.parentData! as TextWidgetParentData;
      if (!parentData.isVisible) {
        continue;
      }
      final RenderBox hitChild = child;
      final bool isHit = result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          return hitChild.hitTest(result, position: transformed);
        },
      );
      if (isHit) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      final parentData = child.parentData! as TextWidgetParentData;
      if (parentData.isVisible) {
        context.paintChild(child, parentData.offset + offset);
      }
    }
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      if ((child.parentData! as TextWidgetParentData).isVisible) {
        visitor(child);
      }
    }
  }
}
