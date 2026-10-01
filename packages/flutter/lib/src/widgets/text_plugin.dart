// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'basic.dart';
/// @docImport 'text.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'framework.dart';

/// A widget that installs one or more [TextPlugin]s for all [Text] and
/// [RichText] widgets in its [child] subtree.
///
/// When multiple [TextPluginScope] widgets are nested, their plugins are
/// composed in installation order: plugins from outer [TextPluginScope]s
/// (closer to the root of the widget tree) are applied and painted before
/// plugins from inner [TextPluginScope]s.
///
/// To exclude a subtree from any ancestor [TextPluginScope]s, wrap the subtree
/// in [TextPluginScope.none].
///
/// If [disableLazyLoading] is `true`, or if any installed [TextPlugin] has
/// [TextPlugin.disableLazyLoading] set to `true`, scrollable viewports (such as
/// [ListView], [CustomScrollView], and [Viewport]) within the scope expand
/// their cache extent to eagerly materialize offscreen sliver children.
///
/// See also:
///
///  * [TextPlugin], the interface implemented by text plugins.
///  * [TextDelegate], the handle given to a [TextPlugin] for each text widget
///    in its scope.
class TextPluginScope extends StatefulWidget {
  /// Creates a scope that installs [plugin] for all [Text] and [RichText]
  /// widgets in [child], composing with any ancestor [TextPluginScope]s.
  const TextPluginScope({
    super.key,
    required TextPlugin this.plugin,
    this.disableLazyLoading,
    required this.child,
  }) : plugins = null,
       _disabled = false;

  /// Creates a scope that installs multiple [plugins] for all [Text] and
  /// [RichText] widgets in [child], composing with any ancestor
  /// [TextPluginScope]s.
  const TextPluginScope.multiple({
    super.key,
    required List<TextPlugin> this.plugins,
    this.disableLazyLoading,
    required this.child,
  }) : plugin = null,
       _disabled = false;

  /// Creates a scope that disables any ancestor [TextPluginScope]s for [child].
  const TextPluginScope.none({super.key, required this.child})
    : plugin = null,
      plugins = null,
      disableLazyLoading = false,
      _disabled = true;

  /// The single [TextPlugin] installed by this scope, if created with
  /// [TextPluginScope.new].
  final TextPlugin? plugin;

  /// The list of [TextPlugin]s installed by this scope, if created with
  /// [TextPluginScope.multiple].
  final List<TextPlugin>? plugins;

  /// Whether scrollable viewports within this scope should disable lazy loading
  /// and eagerly lay out offscreen sliver children.
  ///
  /// When `null`, defaults to `true` if any active [TextPlugin] in this scope
  /// (or an ancestor scope) returns `true` for [TextPlugin.disableLazyLoading],
  /// and `false` otherwise.
  final bool? disableLazyLoading;

  final bool _disabled;

  /// The widget below this widget in the tree.
  final Widget child;

  /// Returns the list of active [TextPlugin]s enclosing the given [context],
  /// ordered from outermost (closest to the root) to innermost, or `null` if
  /// no [TextPluginScope] is present (or if disabled via
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
  /// ordered from outermost (closest to the root) to innermost, or an empty
  /// list if no [TextPluginScope] is present.
  static List<TextPlugin> of(BuildContext context) {
    return maybeOf(context) ?? const <TextPlugin>[];
  }

  /// Returns whether scrollable viewports enclosing the given [context] should
  /// disable lazy loading and eagerly lay out offscreen sliver children.
  static bool shouldDisableLazyLoadingOf(BuildContext context) {
    final _InheritedTextPluginLazyLoading? scope = context
        .dependOnInheritedWidgetOfExactType<_InheritedTextPluginLazyLoading>();
    return scope?.disableLazyLoading ?? false;
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
    }
    properties.add(
      DiagnosticsProperty<bool?>('disableLazyLoading', disableLazyLoading, defaultValue: null),
    );
  }
}

class _TextPluginScopeState extends State<TextPluginScope> {
  final List<Listenable> _listenedPlugins = <Listenable>[];
  bool _localDisableLazyLoading = false;

  List<TextPlugin> get _ownPlugins => <TextPlugin>[
    if (widget.plugin != null) widget.plugin!,
    ...?widget.plugins,
  ];

  bool _computeLocalDisableLazyLoading() {
    if (widget._disabled) {
      return false;
    }
    if (widget.disableLazyLoading != null) {
      return widget.disableLazyLoading!;
    }
    for (final TextPlugin item in _ownPlugins) {
      if (item.disableLazyLoading) {
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
    _localDisableLazyLoading = _computeLocalDisableLazyLoading();
  }

  void _unsubscribeFromPlugins() {
    for (final Listenable listenable in _listenedPlugins) {
      listenable.removeListener(_handlePluginChanged);
    }
    _listenedPlugins.clear();
  }

  void _handlePluginChanged() {
    final bool updated = _computeLocalDisableLazyLoading();
    if (updated != _localDisableLazyLoading) {
      setState(() {
        _localDisableLazyLoading = updated;
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
      return _InheritedTextPluginLazyLoading(
        disableLazyLoading: false,
        child: _InheritedTextPluginScope(plugins: const <TextPlugin>[], child: widget.child),
      );
    }
    final List<TextPlugin> inheritedPlugins = TextPluginScope.of(context);
    final bool inheritedDisableLazyLoading = TextPluginScope.shouldDisableLazyLoadingOf(context);
    final combined = <TextPlugin>[...inheritedPlugins, ..._ownPlugins];
    final uniquePlugins = <TextPlugin>[];
    final seen = <TextPlugin>{};
    for (final item in combined) {
      if (seen.add(item)) {
        uniquePlugins.add(item);
      }
    }
    final bool effectiveDisableLazyLoading =
        widget.disableLazyLoading ?? (inheritedDisableLazyLoading || _localDisableLazyLoading);
    return _InheritedTextPluginLazyLoading(
      disableLazyLoading: effectiveDisableLazyLoading,
      child: _InheritedTextPluginScope(
        plugins: List<TextPlugin>.unmodifiable(uniquePlugins),
        child: widget.child,
      ),
    );
  }
}

class _InheritedTextPluginScope extends InheritedWidget {
  const _InheritedTextPluginScope({required this.plugins, required super.child});

  final List<TextPlugin> plugins;

  @override
  bool updateShouldNotify(_InheritedTextPluginScope oldWidget) {
    return !listEquals(plugins, oldWidget.plugins);
  }
}

class _InheritedTextPluginLazyLoading extends InheritedWidget {
  const _InheritedTextPluginLazyLoading({required this.disableLazyLoading, required super.child});

  final bool disableLazyLoading;

  @override
  bool updateShouldNotify(_InheritedTextPluginLazyLoading oldWidget) {
    return disableLazyLoading != oldWidget.disableLazyLoading;
  }
}
