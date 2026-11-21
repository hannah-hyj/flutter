// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The part of the benchmark that differs between the two prototypes.
//
// This is the inline-span version. The painter version of this file lives on
// the `text-plugin-mvp` branch only for the duration of a benchmark run; it
// is kept in `benchmark_compat_painter.dart.txt` next to this file.

import 'package:flutter/widgets.dart';

import 'plugins/search_in_page_plugin.dart';

/// The name of the prototype, for the report.
const String branchLabel = 'span';

/// One way to run a plugin.
class Variant {
  const Variant(this.label, {this.layer, this.notify = false});

  final String label;
  final TextDecorationLayer? layer;

  /// Whether the search plugin notifies instead of naming the texts.
  final bool notify;
}

/// The ways to run a plugin on this branch.
const List<Variant> variants = <Variant>[
  Variant('A widget layer', layer: TextDecorationLayer.widget),
  Variant('B render layer', layer: TextDecorationLayer.render),
  Variant(
    'A widget layer, notify',
    layer: TextDecorationLayer.widget,
    notify: true,
  ),
  Variant(
    'B render layer, notify',
    layer: TextDecorationLayer.render,
    notify: true,
  ),
];

Widget wrapScope({
  required List<TextPlugin> plugins,
  required Variant variant,
  required Widget child,
}) {
  return TextPluginScope.multiple(
    plugins: plugins,
    decorationLayer: variant.layer,
    child: child,
  );
}

SearchInPagePlugin makeSearch(Variant variant) {
  return SearchInPagePlugin(notifyToRedecorate: variant.notify);
}

/// Highlights one word of a text and moves on with [step].
class KaraokePlugin extends TextPlugin {
  static final RegExp _word = RegExp(r'\S+');

  TextDelegate? _delegate;
  List<TextRange> _words = const <TextRange>[];
  int _index = 0;

  @override
  void didAddText(TextDelegate delegate) {
    _delegate = delegate;
    _words = <TextRange>[
      for (final Match match in _word.allMatches(delegate.text))
        TextRange(start: match.start, end: match.end),
    ];
  }

  void step() {
    _index = (_index + 1) % _words.length;
    _delegate!.markNeedsDecoration();
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    if (_words.isEmpty) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: _words[_index],
        style: const TextStyle(
          backgroundColor: Color(0x5500ACC1),
          decoration: TextDecoration.underline,
        ),
      ),
    ];
  }
}

int _decorate = 0;
int _buildDecorations = 0;
int _builderBuilds = 0;

/// What the framework did since the last call, for the report.
String counters() {
  final String result =
      'spans decorated ${TextDelegateSet.debugDecorateCount - _decorate}, '
      'buildDecorations ${TextDelegateSet.debugBuildDecorationsCount - _buildDecorations}, '
      'wrapper builds ${TextPluginSpanBuilder.debugBuildCount - _builderBuilds}';
  _decorate = TextDelegateSet.debugDecorateCount;
  _buildDecorations = TextDelegateSet.debugBuildDecorationsCount;
  _builderBuilds = TextPluginSpanBuilder.debugBuildCount;
  return result;
}

/// Highlights the first word of every text, with a color that changes on
/// every [tick]. This is an animated highlight, such as a fade or a pulse.
class PulsePlugin extends TextPlugin {
  final Set<TextDelegate> _delegates = <TextDelegate>{};
  int _tick = 0;

  @override
  void didAddText(TextDelegate delegate) => _delegates.add(delegate);

  @override
  void didRemoveText(TextDelegate delegate) => _delegates.remove(delegate);

  void tick() {
    _tick += 1;
    for (final TextDelegate delegate in _delegates) {
      delegate.markNeedsDecoration();
    }
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final int end = delegate.text.indexOf(' ');
    if (end <= 0) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: TextRange(start: 0, end: end),
        style: TextStyle(
          backgroundColor: Color.fromARGB(40 + _tick % 200, 255, 152, 0),
        ),
      ),
    ];
  }
}

/// The ways to show the selection of static text on this branch.
final List<(String, VoidCallback)> selectionModes = <(String, VoidCallback)>[
  (
    'built-in highlight',
    () {
      debugSelectionHighlightAsTextPlugin = false;
    },
  ),
  (
    'span plugin, A widget layer',
    () {
      debugSelectionHighlightAsTextPlugin = true;
      debugDefaultTextDecorationLayer = TextDecorationLayer.widget;
    },
  ),
  (
    'span plugin, B render layer',
    () {
      debugSelectionHighlightAsTextPlugin = true;
      debugDefaultTextDecorationLayer = TextDecorationLayer.render;
    },
  ),
];

/// A search plugin that gives new decorations to at most [perFrame] texts in
/// one frame.
SearchInPagePlugin makeBatchedSearch(int perFrame) {
  return SearchInPagePlugin(decorationsPerFrame: perFrame);
}
