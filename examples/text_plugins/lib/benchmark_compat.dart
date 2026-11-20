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
  Variant('A widget layer, notify', layer: TextDecorationLayer.widget, notify: true),
  Variant('B render layer, notify', layer: TextDecorationLayer.render, notify: true),
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
