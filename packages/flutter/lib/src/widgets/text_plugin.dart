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
      );
      final DecoratedTextSpan decorated = _set.decorate();
      return widget.builder(decorated.span, _set);
    } finally {
      _building = false;
    }
  }
}
