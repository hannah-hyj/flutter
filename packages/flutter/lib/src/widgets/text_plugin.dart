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
/// See also:
///
///  * [TextPlugin], the interface implemented by text plugins.
///  * [TextDelegate], the handle given to a [TextPlugin] for each text widget
///    in its scope.
class TextPluginScope extends StatelessWidget {
  /// Creates a scope that installs [plugin] for all [Text] and [RichText]
  /// widgets in [child], composing with any ancestor [TextPluginScope]s.
  const TextPluginScope({super.key, required TextPlugin this.plugin, required this.child})
    : plugins = null,
      _disabled = false;

  /// Creates a scope that installs multiple [plugins] for all [Text] and
  /// [RichText] widgets in [child], composing with any ancestor
  /// [TextPluginScope]s.
  const TextPluginScope.multiple({
    super.key,
    required List<TextPlugin> this.plugins,
    required this.child,
  }) : plugin = null,
       _disabled = false;

  /// Creates a scope that disables any ancestor [TextPluginScope]s for [child].
  const TextPluginScope.none({super.key, required this.child})
    : plugin = null,
      plugins = null,
      _disabled = true;

  /// The single [TextPlugin] installed by this scope, if created with
  /// [TextPluginScope.new].
  final TextPlugin? plugin;

  /// The list of [TextPlugin]s installed by this scope, if created with
  /// [TextPluginScope.multiple].
  final List<TextPlugin>? plugins;

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

  @override
  Widget build(BuildContext context) {
    if (_disabled) {
      return _InheritedTextPluginScope(plugins: const <TextPlugin>[], child: child);
    }
    final List<TextPlugin> inheritedPlugins = TextPluginScope.of(context);
    final combined = <TextPlugin>[...inheritedPlugins, if (plugin != null) plugin!, ...?plugins];
    final uniquePlugins = <TextPlugin>[];
    final seen = <TextPlugin>{};
    for (final item in combined) {
      if (seen.add(item)) {
        uniquePlugins.add(item);
      }
    }
    return _InheritedTextPluginScope(
      plugins: List<TextPlugin>.unmodifiable(uniquePlugins),
      child: child,
    );
  }

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
