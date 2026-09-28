// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_plugins/main.dart';

void main() {
  testWidgets('TextPluginsDemoApp showcases search, stock tickers, linkify, and SEO plugins', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TextPluginsDemoApp());
    await tester.pumpAndSettle();

    // 1. SearchInPagePlugin: verify initial case-insensitive search for "Flutter"
    // finds 4 matches (3 "Flutter" + 1 "https://flutter.dev").
    expect(find.byKey(const Key('search_match_count')), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);

    // Navigate to next match.
    await tester.tap(find.byKey(const Key('search_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);

    // Enable case-sensitive search ("Aa") -> excludes lowercase "flutter.dev".
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    // 2. StockTickerPlugin & LinkifyPlugin: tap on "GOOG" and "https://flutter.dev"
    // inside the standard Text widget.
    final Finder reportParagraphFinder = find.byKey(const Key('market_report_text'));
    await tester.ensureVisible(reportParagraphFinder);
    await tester.pumpAndSettle();
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: reportParagraphFinder, matching: find.byType(RichText)),
    );
    final String plainText = paragraph.text.toPlainText();

    // Tap on "GOOG" in the paragraph.
    final int googIndex = plainText.indexOf('GOOG');
    final List<TextBox> googBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: googIndex, extentOffset: googIndex + 4),
    );
    final Offset googGlobalCenter = paragraph.localToGlobal(googBoxes.first.toRect().center);
    await tester.tapAt(googGlobalCenter);
    await tester.pumpAndSettle();

    // Verify the Stock Quote bottom sheet and banner appear for GOOG.
    expect(find.text('Alphabet Inc.'), findsOneWidget);
    expect(find.byKey(const Key('last_tapped_ticker')), findsOneWidget);

    // Dismiss the bottom sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Tap on "https://flutter.dev" in the paragraph.
    await tester.ensureVisible(reportParagraphFinder);
    await tester.pumpAndSettle();
    final int urlIndex = plainText.indexOf('https://flutter.dev');
    final List<TextBox> urlBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: urlIndex, extentOffset: urlIndex + 'https://flutter.dev'.length),
    );
    final Offset urlGlobalCenter = paragraph.localToGlobal(urlBoxes.first.toRect().center);
    await tester.tapAt(urlGlobalCenter);
    await tester.pumpAndSettle();

    // Verify LinkifyPlugin handled the tap.
    expect(find.byKey(const Key('last_tapped_url')), findsOneWidget);
    expect(find.text('Last tapped link: https://flutter.dev'), findsOneWidget);

    // 3. SeoExtractorPlugin: record initial widget count and verify adding a note increments it.
    final Text initialSeoChip = tester.widget<Text>(find.byKey(const Key('seo_widget_count')));
    final int initialCount = int.parse(initialSeoChip.data!.split(': ').last);
    expect(initialCount, 7);

    final Finder noteInput = find.byKey(const Key('custom_note_input'));
    final Finder addNoteButton = find.byKey(const Key('add_note_button'));
    await tester.ensureVisible(addNoteButton);
    await tester.pumpAndSettle();

    await tester.enterText(noteInput, 'Flutter update from GOOG at https://flutter.dev');
    await tester.tap(addNoteButton);
    await tester.pumpAndSettle();

    // Match count for case-sensitive "Flutter" and SEO widget count both increment by 1.
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('Text Widgets: ${initialCount + 1}'), findsOneWidget);
  });
}
