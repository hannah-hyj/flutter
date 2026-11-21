// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Renders what only the inline-span prototype can do, with a real font, and
// writes an image:
//
//     flutter test --update-goldens test/visual_span_only_test.dart
//
// It is not a test of anything. It exists to look at the result.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_plugins/plugins/spoiler_mask_plugin.dart';
import 'package:text_plugins/plugins/stock_ticker_plugin.dart';

Future<void> _loadRoboto() async {
  final String root = Platform.environment['FLUTTER_ROOT']!;
  for (final file in <String>['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
    final loader = FontLoader('Roboto')
      ..addFont(
        File(
          '$root/bin/cache/artifacts/material_fonts/$file',
        ).readAsBytes().then((Uint8List bytes) => ByteData.sublistView(bytes)),
      );
    await loader.load();
  }
}

/// Applies one style to every occurrence of a word.
class _StylePlugin extends TextPlugin {
  _StylePlugin(this.word, this.style);

  final String word;
  final TextStyle style;

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    return <TextSpanDecoration>[
      for (final Match match in word.allMatches(delegate.text))
        TextSpanDecoration(
          range: TextRange(start: match.start, end: match.end),
          style: style,
        ),
    ];
  }
}

/// Colors the words up to [spoken], the way a karaoke line fills in.
class _KaraokePlugin extends TextPlugin {
  _KaraokePlugin(this.spoken);

  final int spoken;

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: TextRange(start: 0, end: spoken),
        style: const TextStyle(color: Color(0xFFD81B60), fontWeight: FontWeight.bold),
      ),
    ];
  }
}

Widget _row(String label, Widget child) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextPluginScope.none(
          child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
        ),
        const SizedBox(height: 3),
        child,
      ],
    ),
  );
}

void main() {
  testWidgets('what only a span can do, rendered', (WidgetTester tester) async {
    await _loadRoboto();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final spoiler = SpoilerMaskPlugin();
    final revealed = SpoilerMaskPlugin();
    addTearDown(spoiler.dispose);
    addTearDown(revealed.dispose);
    const key = Key('visual');

    // The known trick for a rounded, padded background: a background Paint
    // that strokes with round joins. It is a layout-level change of the
    // style.
    final rounded = Paint()
      ..color = const Color(0xFFFFE082)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20,
                height: 1.4,
                color: Color(0xFF000000),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _row(
                      'the glyphs themselves: color and weight of the spoken words',
                      TextPluginScope(
                        plugin: _KaraokePlugin(19),
                        child: const Text('The quick brown fox jumps over the lazy dog.'),
                      ),
                    ),
                    _row(
                      'white text on a dark match',
                      TextPluginScope(
                        plugin: _StylePlugin(
                          'match',
                          const TextStyle(
                            color: Color(0xFFFFFFFF),
                            backgroundColor: Color(0xFF1A237E),
                          ),
                        ),
                        child: const Text('A match is easier to read when the match inverts.'),
                      ),
                    ),
                    _row(
                      'a rounded background from a stroked Paint',
                      TextPluginScope(
                        plugin: _StylePlugin('rounded', TextStyle(background: rounded)),
                        child: const SizedBox(
                          width: 330,
                          child: Text(
                            'A rounded match, and a second rounded one that is rounded too.',
                          ),
                        ),
                      ),
                    ),
                    _row(
                      'stock tickers as inline badge widgets',
                      TextPluginScope(
                        plugin: StockTickerPlugin(badges: true),
                        child: const Text('Buy GOOG and AAPL, sell TSLA and MSFT today.'),
                      ),
                    ),
                    _row(
                      'a spoiler, hidden: the || take no room',
                      TextPluginScope(
                        plugin: spoiler,
                        child: const Text('The butler ||did it|| in the library.'),
                      ),
                    ),
                    _row(
                      'the same text without a plugin',
                      const Text('The butler ||did it|| in the library.'),
                    ),
                    _row(
                      'strike-through and a different size for deleted words',
                      TextPluginScope(
                        plugin: _StylePlugin(
                          'deleted words',
                          const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            fontSize: 14,
                            color: Color(0xFF9E9E9E),
                          ),
                        ),
                        child: const Text('A review plugin can shrink deleted words in place.'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(find.byKey(key), matchesGoldenFile('visual/span_only.png'));
  });
}
