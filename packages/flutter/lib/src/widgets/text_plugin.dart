// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'basic.dart';
/// @docImport 'editable_text.dart';
/// @docImport 'scroll_view.dart';
/// @docImport 'text.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'actions.dart';
import 'focus_manager.dart';
import 'focus_scope.dart';
import 'framework.dart';
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
/// ## Keyboard focus for annotated text
///
/// [TextPluginScope] also makes interactive [TextAnnotation]s (ranges with a
/// tap action, see [TextDelegate.annotations]) on static text in its subtree
/// part of focus traversal: each one gets a [FocusNode] attached to this scope,
/// ordered by its position on screen, so users can reach plugin links with Tab
/// and activate them with Enter or Space ([ActivateIntent]). A focus ring is
/// painted around the focused range when
/// [FocusManager.highlightMode] is [FocusHighlightMode.traditional]. Ranges
/// inside editable text ([EditableText]) are not focusable individually; Tab
/// moves to the next field, following editor conventions.
///
/// See also:
///
///  * [TextPlugin], the interface implemented by text plugins.
///  * [TextDelegate], the handle given to a [TextPlugin] for each text widget
///    in its scope.
///  * [TextAnnotation], which describes the behavior and meaning of a range of
///    text decorated by a plugin.
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
  final _TextAnnotationFocusPlugin _focusPlugin = _TextAnnotationFocusPlugin();
  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: _ActivateTextAnnotationAction<ActivateIntent>(),
    ButtonActivateIntent: _ActivateTextAnnotationAction<ButtonActivateIntent>(),
  };

  List<TextPlugin> get _ownPlugins => <TextPlugin>[
    if (widget.plugin != null) widget.plugin!,
    ...?widget.plugins,
    // Installed last so that nested scopes override it for their subtree and
    // its focus ring paints above every other plugin.
    if (!widget._disabled) _focusPlugin,
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
    _focusPlugin.dispose();
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
      child: Actions(
        actions: _actions,
        child: _TextAnnotationFocusHost(
          plugin: _focusPlugin,
          child: _InheritedTextPluginScope(
            pluginMap: Map<Type, TextPlugin>.unmodifiable(pluginMap),
            plugins: List<TextPlugin>.unmodifiable(orderedPlugins),
            child: widget.child,
          ),
        ),
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

/// Activates the focused [TextAnnotation] in response to [ActivateIntent] or
/// [ButtonActivateIntent] (Enter, Space, gamepad select, ...).
///
/// Only enabled while a [_TextAnnotationFocusNode] has primary focus, so that
/// other actions in the tree keep handling the intent otherwise.
class _ActivateTextAnnotationAction<T extends Intent> extends Action<T> {
  @override
  bool isEnabled(T intent) => primaryFocus is _TextAnnotationFocusNode;

  @override
  Object? invoke(T intent) {
    (primaryFocus! as _TextAnnotationFocusNode).activate();
    return null;
  }
}

/// Provides the [BuildContext] that the focus nodes of [plugin] attach to.
///
/// It sits below the scope's [Actions] so that [Actions.maybeInvoke], which
/// starts its lookup at `primaryFocus.context`, finds
/// [_ActivateTextAnnotationAction].
class _TextAnnotationFocusHost extends StatefulWidget {
  const _TextAnnotationFocusHost({required this.plugin, required this.child});

  final _TextAnnotationFocusPlugin plugin;
  final Widget child;

  @override
  State<_TextAnnotationFocusHost> createState() => _TextAnnotationFocusHostState();
}

class _TextAnnotationFocusHostState extends State<_TextAnnotationFocusHost> {
  @override
  void initState() {
    super.initState();
    widget.plugin._attachHost(this);
  }

  @override
  void didUpdateWidget(_TextAnnotationFocusHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.plugin, widget.plugin)) {
      oldWidget.plugin._detachHost(this);
      widget.plugin._attachHost(this);
    }
  }

  @override
  void dispose() {
    widget.plugin._detachHost(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Depending on the enclosing focus scope re-parents the nodes whenever it
    // changes, like the Focus widget does.
    widget.plugin._reparentFocusNodes(Focus.maybeOf(context, scopeOk: true));
    return widget.child;
  }
}

/// The internal [TextPlugin] installed by every [TextPluginScope] that mirrors
/// interactive [TextAnnotation]s as [FocusNode]s and paints the focus ring.
///
/// Being a plugin, it discovers text widgets through the regular
/// [TextPlugin.didAddText] / [TextPlugin.didRemoveText] pipeline, needs no
/// plumbing through [RichText] or [EditableText], and is naturally scoped:
/// nested scopes dedupe it by type, so the innermost scope owns the focus
/// nodes of its subtree.
class _TextAnnotationFocusPlugin extends TextPlugin {
  _TextAnnotationFocusPlugin() {
    FocusManager.instance.addHighlightModeListener(_handleHighlightModeChanged);
  }

  _TextAnnotationFocusHostState? _host;
  final Map<TextDelegate, _TextAnnotationFocusGroup> _groups =
      <TextDelegate, _TextAnnotationFocusGroup>{};

  BuildContext? get _hostContext {
    final _TextAnnotationFocusHostState? host = _host;
    return host != null && host.mounted ? host.context : null;
  }

  // Above every other plugin so that the focus ring is never covered.
  @override
  int get paintOrder => 1 << 30;

  void _attachHost(_TextAnnotationFocusHostState host) {
    _host = host;
    for (final _TextAnnotationFocusGroup group in _groups.values) {
      group.reconcile();
    }
  }

  void _detachHost(_TextAnnotationFocusHostState host) {
    if (!identical(_host, host)) {
      return;
    }
    _host = null;
    for (final _TextAnnotationFocusGroup group in _groups.values) {
      group.disposeNodes();
    }
  }

  void _reparentFocusNodes(FocusNode? parent) {
    for (final _TextAnnotationFocusGroup group in _groups.values) {
      group.reparent(parent);
    }
  }

  void _handleHighlightModeChanged(FocusHighlightMode mode) {
    for (final _TextAnnotationFocusGroup group in _groups.values) {
      group.updateHighlight();
    }
  }

  @override
  void didAddText(TextDelegate delegate) {
    if (delegate.isEditable) {
      // Editor convention: Tab leaves the field; ranges inside are reached
      // through the field's own navigation and assistive technology.
      return;
    }
    final group = _TextAnnotationFocusGroup(this, delegate);
    _groups[delegate] = group;
    // Fires on text, layout, selection, and annotation changes of this text
    // widget, including annotations installed by other plugins.
    delegate.addListener(group.reconcile);
    group.reconcile();
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    final _TextAnnotationFocusGroup? group = _groups.remove(delegate);
    if (group == null) {
      return;
    }
    delegate.removeListener(group.reconcile);
    group.dispose();
  }

  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightModeChanged);
    for (final MapEntry<TextDelegate, _TextAnnotationFocusGroup> entry in _groups.entries) {
      if (!entry.key.isDisposed) {
        entry.key.removeListener(entry.value.reconcile);
      }
      entry.value.dispose();
    }
    _groups.clear();
  }
}

/// The focus nodes of one text widget, keyed by [TextAnnotation.identity].
class _TextAnnotationFocusGroup {
  _TextAnnotationFocusGroup(this.plugin, this.delegate);

  final _TextAnnotationFocusPlugin plugin;
  final TextDelegate delegate;
  final Map<Object, _TextAnnotationFocusNode> _nodes = <Object, _TextAnnotationFocusNode>{};

  /// Creates, rebinds, or disposes focus nodes so that they mirror the
  /// focusable annotations currently installed on [delegate].
  void reconcile() {
    final BuildContext? hostContext = plugin._hostContext;
    if (delegate.isDisposed || hostContext == null) {
      return;
    }
    final List<TextAnnotation> all = delegate.allAnnotations;
    if (all.isEmpty && _nodes.isEmpty) {
      return;
    }
    // Focusable: activatable, and the topmost annotation where it starts.
    final focusable = <TextAnnotation>[
      for (final TextAnnotation annotation in all)
        if (annotation.activationCallback != null &&
            identical(delegate.annotationsAt(annotation.range.start).first, annotation))
          annotation,
    ]..sort((TextAnnotation a, TextAnnotation b) => a.range.start.compareTo(b.range.start));

    final previous = Map<Object, _TextAnnotationFocusNode>.of(_nodes);
    _nodes.clear();
    final FocusNode? parent = Focus.maybeOf(hostContext, scopeOk: true, createDependency: false);
    for (final annotation in focusable) {
      final Object identity = annotation.identity;
      if (_nodes.containsKey(identity)) {
        continue;
      }
      _TextAnnotationFocusNode? node = previous.remove(identity);
      if (node == null) {
        node = _TextAnnotationFocusNode(this);
        node.attachment = node.attach(hostContext);
        node.attachment!.reparent(parent: parent);
      }
      node.annotation = annotation;
      _nodes[identity] = node;
    }
    for (final _TextAnnotationFocusNode stale in previous.values) {
      stale.dispose();
    }
    updateHighlight();
  }

  void reparent(FocusNode? parent) {
    for (final _TextAnnotationFocusNode node in _nodes.values) {
      node.attachment?.reparent(parent: parent);
    }
  }

  /// Paints a focus ring around the focused annotation, if any, in
  /// traditional (keyboard) highlight mode.
  void updateHighlight() {
    if (delegate.isDisposed) {
      return;
    }
    TextAnnotation? focused;
    for (final _TextAnnotationFocusNode node in _nodes.values) {
      if (node.hasPrimaryFocus) {
        focused = node.annotation;
        break;
      }
    }
    final bool show =
        focused != null && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    delegate.foregroundPainter = show
        ? _TextAnnotationFocusPainter(delegate: delegate, annotation: focused)
        : null;
  }

  /// The global bounds of [annotation], used to order focus traversal.
  Rect? globalBoundsFor(TextAnnotation? annotation) {
    if (annotation == null || delegate.isDisposed || !delegate.attached || !delegate.hasLayout) {
      return null;
    }
    final Rect? bounds = delegate.getBoundsForAnnotation(annotation);
    if (bounds == null) {
      return null;
    }
    return MatrixUtils.transformRect(delegate.getTransformTo(null), bounds);
  }

  void disposeNodes() {
    for (final _TextAnnotationFocusNode node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }

  void dispose() {
    disposeNodes();
    if (!delegate.isDisposed) {
      delegate.foregroundPainter = null;
    }
  }
}

/// A [FocusNode] standing in for one [TextAnnotation].
///
/// Its [rect] is the on-screen bounds of the annotated range rather than the
/// bounds of the widget it is attached to, so that
/// [ReadingOrderTraversalPolicy] orders links among their neighbors.
class _TextAnnotationFocusNode extends FocusNode {
  _TextAnnotationFocusNode(this.group) : super(debugLabel: 'TextAnnotation') {
    addListener(_handleFocusChanged);
  }

  final _TextAnnotationFocusGroup group;
  FocusAttachment? attachment;

  // Stored once so that identity comparisons against the annotation's current
  // handler are reliable (tear-offs are not guaranteed to be identical).
  late final VoidCallback _requestFocusHandler = requestFocus;

  TextAnnotation? get annotation => _annotation;
  TextAnnotation? _annotation;
  set annotation(TextAnnotation? value) {
    if (identical(_annotation, value)) {
      return;
    }
    final TextAnnotation? previous = _annotation;
    if (previous != null && identical(previous.focusRequestHandler, _requestFocusHandler)) {
      previous
        ..focusRequestHandler = null
        ..isFocused = false;
    }
    _annotation = value;
    if (value != null) {
      value
        ..focusRequestHandler = _requestFocusHandler
        ..isFocused = hasPrimaryFocus;
      assert(() {
        debugLabel = 'TextAnnotation(${value.range.start}, ${value.range.end})';
        return true;
      }());
    }
  }

  void _handleFocusChanged() {
    _annotation?.isFocused = hasPrimaryFocus;
    group.updateHighlight();
  }

  void activate() {
    _annotation?.activate();
  }

  @override
  Rect get rect => group.globalBoundsFor(_annotation) ?? super.rect;

  @override
  Offset get offset => rect.topLeft;

  @override
  void dispose() {
    annotation = null;
    super.dispose();
  }
}

class _TextAnnotationFocusPainter extends CustomPainter {
  _TextAnnotationFocusPainter({required this.delegate, required this.annotation});

  final TextDelegate delegate;
  final TextAnnotation annotation;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    // Text resolves selectionColor from DefaultSelectionStyle, which Material
    // and Cupertino derive from the theme, so the ring follows the app's
    // accent without a widgets-layer theme dependency.
    final Color color = (delegate.selectionColor ?? const Color(0xFF808080)).withValues(alpha: 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color;
    for (final TextBox box in delegate.getBoxesForSelection(
      TextSelection(baseOffset: annotation.range.start, extentOffset: annotation.range.end),
    )) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.toRect().inflate(2.0), const Radius.circular(3.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TextAnnotationFocusPainter oldDelegate) {
    return !identical(oldDelegate.annotation, annotation) ||
        !identical(oldDelegate.delegate, delegate);
  }
}
