// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Renders the stage 1 demo plugins with a real font and writes an image.
//
// This file only uses what the plugins have in common on the painter branch
// (`text-plugin-mvp`) and on the inline-span branch, so the same file runs on
// both and the two images can be put side by side:
//
//     flutter test --update-goldens --dart-define=VISUAL_PREFIX=span \
//         test/visual_test.dart
//
// It is not a test of anything. It exists to look at the result.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_plugins/plugins/read_aloud_plugin.dart';
import 'package:text_plugins/plugins/search_in_page_plugin.dart';
import 'package:text_plugins/plugins/spellcheck_linter_plugin.dart';
import 'package:text_plugins/plugins/stock_ticker_plugin.dart';

const String _prefix = String.fromEnvironment(
  'VISUAL_PREFIX',
  defaultValue: 'span',
);

Future<void> _loadRoboto() async {
  final String root = Platform.environment['FLUTTER_ROOT']!;
  final loader = FontLoader('Roboto')
    ..addFont(
      File('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
          .readAsBytes()
          .then((Uint8List bytes) => ByteData.sublistView(bytes)),
    );
  await loader.load();
}

Widget _row(String label, Widget child) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextPluginScope.none(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
          ),
        ),
        const SizedBox(height: 3),
        child,
      ],
    ),
  );
}

void main() {
  // Real file access does not complete inside the fake clock of testWidgets.
  setUpAll(_loadRoboto);

  testWidgets('stage 1 plugins, rendered', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1120);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final search = SearchInPagePlugin()..query = 'flutter';
    final wrapped = SearchInPagePlugin()
      ..query = 'wraps over the end of the line and goes';
    final field = SearchInPagePlugin()..query = 'field';
    final spellcheck = SpellcheckLinterPlugin();
    final ticker = StockTickerPlugin();
    final readAloud = ReadAloudPlugin();
    addTearDown(search.dispose);
    addTearDown(wrapped.dispose);
    addTearDown(field.dispose);
    addTearDown(readAloud.dispose);
    final controller = TextEditingController(
      text: 'A text field with a match in the field.',
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    const key = Key('visual');

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
                      'search: three matches, the second is the active one',
                      TextPluginScope(
                        plugin: search,
                        child: const Text(
                          'Flutter draws text. A plugin finds flutter, and Flutter again.',
                        ),
                      ),
                    ),
                    _row(
                      'search: one match that wraps',
                      TextPluginScope(
                        plugin: wrapped,
                        child: const SizedBox(
                          width: 330,
                          child: Text(
                            'A match that wraps over the end of the line and goes on.',
                          ),
                        ),
                      ),
                    ),
                    _row(
                      'search in a text field',
                      TextPluginScope(
                        plugin: field,
                        child: EditableText(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 20,
                            height: 1.4,
                            color: Color(0xFF000000),
                          ),
                          cursorColor: const Color(0xFF000000),
                          backgroundCursorColor: const Color(0xFF888888),
                        ),
                      ),
                    ),
                    _row(
                      'spell check: two errors, one style suggestion',
                      TextPluginScope(
                        plugin: spellcheck,
                        child: const Text(
                          'Please recieve the seperate package and utilize it.',
                        ),
                      ),
                    ),
                    _row(
                      'stock tickers: two up, two down',
                      TextPluginScope(
                        plugin: ticker,
                        child: const Text(
                          'Buy GOOG and AAPL, sell TSLA and MSFT today.',
                        ),
                      ),
                    ),
                    _row(
                      'read aloud: the fourth word is spoken',
                      TextPluginScope(
                        plugin: readAloud,
                        child: const SizedBox(
                          width: 420,
                          child: Text(
                            'The quick brown fox jumps over the lazy dog, twice a day.',
                          ),
                        ),
                      ),
                    ),
                    _row(
                      'search over styled text: a match across bold, italic and a larger size',
                      TextPluginScope(
                        plugin: SearchInPagePlugin()
                          ..query = 'bold italic large',
                        child: const Text.rich(
                          TextSpan(
                            text: 'Plain ',
                            children: <InlineSpan>[
                              TextSpan(
                                text: 'bold',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(text: ' '),
                              TextSpan(
                                text: 'italic',
                                style: TextStyle(fontStyle: FontStyle.italic),
                              ),
                              TextSpan(text: ' '),
                              TextSpan(
                                text: 'large',
                                style: TextStyle(fontSize: 30),
                              ),
                              TextSpan(text: ' plain.'),
                            ],
                          ),
                        ),
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
    search.nextMatch();
    for (var i = 0; i < 4; i += 1) {
      readAloud.stepNextWord();
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    await expectLater(
      find.byKey(key),
      matchesGoldenFile('visual/${_prefix}_stage1.png'),
    );
  });
}
