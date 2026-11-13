// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The Material search bars for [SearchInPagePlugin].
//
// The plugin has no user interface. It is a [ChangeNotifier] that exposes the
// query, the matches, the active match and the navigation calls. The widgets
// in this file are ordinary Material widgets that listen to it and call it.
// Nothing here is known to the plugin, so an app can replace these bars with
// its own, in any design system, without touching the plugin.

import 'package:flutter/material.dart';

import '../plugins/search_in_page_plugin.dart';

/// A search bar that is docked in the page layout, as one row.
class DockedSearchInPageBar extends StatelessWidget {
  /// Creates a docked search bar that drives [plugin].
  const DockedSearchInPageBar({
    super.key,
    required this.plugin,
    required this.controller,
    required this.focusNode,
    required this.onClose,
    this.hintText = 'Find in page...',
    this.options = const <Widget>[],
  });

  /// The plugin that this bar shows and controls.
  final SearchInPagePlugin plugin;

  /// The controller of the query text field.
  final TextEditingController controller;

  /// The focus node of the query text field.
  final FocusNode focusNode;

  /// Called when the close button is pressed.
  final VoidCallback onClose;

  /// The hint shown in the empty query text field.
  final String hintText;

  /// Extra widgets shown after the built-in options, such as app settings.
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: plugin,
      builder: (BuildContext context, Widget? child) {
        return Container(
          key: const Key('top_search_bar'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.find_in_page_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: _QueryField(
                  plugin: plugin,
                  controller: controller,
                  focusNode: focusNode,
                  hintText: hintText,
                ),
              ),
              const SizedBox(width: 6),
              _CaseSensitiveChip(plugin: plugin, compact: true),
              const SizedBox(width: 6),
              _EagerLoadChip(plugin: plugin, compact: true),
              for (final Widget option in options) ...<Widget>[
                const SizedBox(width: 6),
                option,
              ],
              const SizedBox(width: 8),
              _MatchCount(plugin: plugin),
              _NavigationButtons(plugin: plugin, onClose: onClose),
            ],
          ),
        );
      },
    );
  }
}

/// A search bar shown as a floating card, with a handle to drag it.
///
/// The bar does not position itself. Place it in a [Stack], for example in a
/// [Positioned], and move it in [onDragUpdate].
class FloatingSearchInPageBar extends StatelessWidget {
  /// Creates a floating search bar that drives [plugin].
  const FloatingSearchInPageBar({
    super.key,
    required this.plugin,
    required this.controller,
    required this.focusNode,
    required this.onClose,
    this.onDragUpdate,
    this.hintText = 'Find in page...',
    this.options = const <Widget>[],
  });

  /// The plugin that this bar shows and controls.
  final SearchInPagePlugin plugin;

  /// The controller of the query text field.
  final TextEditingController controller;

  /// The focus node of the query text field.
  final FocusNode focusNode;

  /// Called when the close button is pressed.
  final VoidCallback onClose;

  /// Called with the distance moved when the drag handle is dragged.
  final ValueChanged<Offset>? onDragUpdate;

  /// The hint shown in the empty query text field.
  final String hintText;

  /// Extra widgets shown after the built-in options, such as app settings.
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: plugin,
      builder: (BuildContext context, Widget? child) {
        return Material(
          key: const Key('floating_search_bar'),
          elevation: 8,
          shadowColor: Colors.black38,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: SizedBox(
            width: 480,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      GestureDetector(
                        onPanUpdate: (DragUpdateDetails details) {
                          onDragUpdate?.call(details.delta);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.drag_indicator,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _QueryField(
                          plugin: plugin,
                          controller: controller,
                          focusNode: focusNode,
                          hintText: hintText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MatchCount(plugin: plugin),
                      _NavigationButtons(plugin: plugin, onClose: onClose),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _CaseSensitiveChip(plugin: plugin),
                      _EagerLoadChip(plugin: plugin),
                      ...options,
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The text field that sets [SearchInPagePlugin.query].
class _QueryField extends StatelessWidget {
  const _QueryField({
    required this.plugin,
    required this.controller,
    required this.focusNode,
    required this.hintText,
  });

  final SearchInPagePlugin plugin;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('search_input'),
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (String value) {
        plugin.query = value;
      },
      // Keep the focus in the field when the user presses enter.
      onEditingComplete: () {},
      onSubmitted: (_) {
        plugin.nextMatch();
      },
    );
  }
}

/// Shows the position of the active match and the number of matches.
class _MatchCount extends StatelessWidget {
  const _MatchCount({required this.plugin});

  final SearchInPagePlugin plugin;

  @override
  Widget build(BuildContext context) {
    final int total = plugin.matches.length;
    final int current = total == 0 ? 0 : plugin.activeMatchIndex + 1;
    return Text(
      '$current / $total',
      key: const Key('search_match_count'),
      style: const TextStyle(
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

/// The previous, next and close buttons.
class _NavigationButtons extends StatelessWidget {
  const _NavigationButtons({required this.plugin, required this.onClose});

  final SearchInPagePlugin plugin;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bool hasMatches = plugin.matches.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: const Key('search_prev_button'),
          visualDensity: VisualDensity.compact,
          tooltip: 'Previous match',
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: hasMatches ? plugin.previousMatch : null,
        ),
        IconButton(
          key: const Key('search_next_button'),
          visualDensity: VisualDensity.compact,
          tooltip: 'Next match',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: hasMatches ? plugin.nextMatch : null,
        ),
        IconButton(
          key: const Key('search_close_button'),
          visualDensity: VisualDensity.compact,
          tooltip: 'Close search (Ctrl+F / Cmd+F to reopen)',
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// Toggles [SearchInPagePlugin.caseSensitive].
class _CaseSensitiveChip extends StatelessWidget {
  const _CaseSensitiveChip({required this.plugin, this.compact = false});

  final SearchInPagePlugin plugin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
      labelPadding: compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
      label: const Text('Aa'),
      tooltip: 'Case sensitive',
      selected: plugin.caseSensitive,
      onSelected: (bool value) {
        plugin.caseSensitive = value;
      },
    );
  }
}

/// Toggles [SearchInPagePlugin.eagerLoadOffscreenText].
class _EagerLoadChip extends StatelessWidget {
  const _EagerLoadChip({required this.plugin, this.compact = false});

  final SearchInPagePlugin plugin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      key: const Key('eager_load_chip'),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
      labelPadding: compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
      avatar: Icon(Icons.bolt, size: compact ? 15 : 16),
      label: Text(
        'Cancel Lazy Load',
        style: compact ? const TextStyle(fontSize: 12) : null,
      ),
      tooltip:
          'Eagerly lay out offscreen SliverList items (auto-enabled on Ctrl+F)',
      selected: plugin.eagerLoadOffscreenText,
      onSelected: (bool value) {
        plugin.eagerLoadOffscreenText = value;
      },
    );
  }
}
