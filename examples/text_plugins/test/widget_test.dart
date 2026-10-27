// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_plugins/main.dart';
import 'package:text_plugins/plugins/search_in_page_plugin.dart';

void main() {
  testWidgets(
    'TextPluginsDemoApp showcases search, stock tickers, linkify, and SEO plugins',
    (WidgetTester tester) async {
      await tester.pumpWidget(const TextPluginsDemoApp());
      await tester.pump();

      expect(find.byKey(const Key('plugin_overview_note')), findsOneWidget);

      // 0. Verify animated moving text card and dynamic changing text card (a -> ab -> ... -> a..z -> a).
      final Finder movingCardFinder = find.byKey(const Key('moving_text_card'));
      final Finder changingTextFinder = find.byKey(
        const Key('changing_alphabet_text'),
      );
      expect(movingCardFinder, findsOneWidget);
      expect(changingTextFinder, findsOneWidget);
      expect(tester.widget<Text>(changingTextFinder).data, 'a');

      final Offset initialMovingOffset = tester.getCenter(movingCardFinder);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(changingTextFinder).data, 'ab');
      expect(
        tester.getCenter(movingCardFinder),
        isNot(equals(initialMovingOffset)),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(changingTextFinder).data, 'abc');

      // Advance 23 more ticks to reach 'abcdefghijklmnopqrstuvwxyz' (26 chars).
      for (var i = 0; i < 23; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        tester.widget<Text>(changingTextFinder).data,
        'abcdefghijklmnopqrstuvwxyz',
      );

      // Next tick wraps back to 'a'.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(changingTextFinder).data, 'a');

      // Pause both continuous animations so pumpAndSettle can be used for subsequent interactions.
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('moving_card_toggle_button'))),
        alignment: 0.85,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('moving_card_toggle_button')));
      await tester.pump();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('changing_text_toggle_button'))),
        alignment: 0.85,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('changing_text_toggle_button')));
      await tester.pumpAndSettle();

      // 1. SearchInPagePlugin: verify the Ctrl+F search widget is initially hidden,
      // then enable it and verify search for "Flutter" finds 5 matches.
      expect(find.byKey(const Key('floating_search_bar')), findsNothing);
      expect(find.byKey(const Key('top_search_bar')), findsNothing);

      await tester.tap(find.byKey(const Key('chip_search_plugin')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('floating_search_bar')), findsOneWidget);
      expect(find.byKey(const Key('top_search_bar')), findsNothing);
      expect(find.byKey(const Key('search_match_count')), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);

      // Switch search bar between "Floating" and "At Top" widget modes.
      await tester.tap(find.byKey(const Key('search_position_top_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('top_search_bar')), findsOneWidget);
      expect(find.byKey(const Key('floating_search_bar')), findsNothing);

      // Navigate to next match.
      await tester.tap(find.byKey(const Key('search_next_button')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);

      // Enable case-sensitive search ("Aa") -> excludes lowercase "flutter.dev".
      await tester.tap(find.text('Aa'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      // 2. StockTickerPlugin & LinkifyPlugin: tap on "GOOG" and "https://flutter.dev"
      // inside the standard Text widget.
      final Finder reportParagraphFinder = find.byKey(
        const Key('market_report_text'),
      );
      await tester.ensureVisible(reportParagraphFinder);
      await tester.pumpAndSettle();
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: reportParagraphFinder,
          matching: find.byType(RichText),
        ),
      );
      final String plainText = paragraph.text.toPlainText();

      // Tap on "GOOG" in the paragraph.
      final int googIndex = plainText.indexOf('GOOG');
      final List<TextBox> googBoxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: googIndex, extentOffset: googIndex + 4),
      );
      final Offset googGlobalCenter = paragraph.localToGlobal(
        googBoxes.first.toRect().center,
      );
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
        TextSelection(
          baseOffset: urlIndex,
          extentOffset: urlIndex + 'https://flutter.dev'.length,
        ),
      );
      final Offset urlGlobalCenter = paragraph.localToGlobal(
        urlBoxes.first.toRect().center,
      );
      await tester.tapAt(urlGlobalCenter);
      await tester.pumpAndSettle();

      // Verify LinkifyPlugin handled the tap.
      expect(find.byKey(const Key('last_tapped_url')), findsOneWidget);
      expect(
        find.text('Last tapped link: https://flutter.dev'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(tester.element(reportParagraphFinder))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // 3. SeoExtractorPlugin: record initial widget count and verify adding a note increments it.
      // (includes static paragraphs + EditableText / TextField in TextPluginScope).
      final Text initialSeoChip = tester.widget<Text>(
        find.byKey(const Key('seo_widget_count')),
      );
      final int initialCount = int.parse(initialSeoChip.data!.split(': ').last);
      expect(initialCount, greaterThanOrEqualTo(8));

      final Finder noteInput = find.byKey(const Key('custom_note_input'));
      final Finder addNoteButton = find.byKey(const Key('add_note_button'));
      await tester.ensureVisible(addNoteButton);
      await tester.pumpAndSettle();

      await tester.enterText(
        noteInput,
        'Flutter update from GOOG at https://flutter.dev',
      );
      await tester.tap(addNoteButton);
      await tester.pumpAndSettle();

      // Match count for case-sensitive "Flutter" and SEO widget count both increment.
      expect(find.text('2 / 4'), findsOneWidget);
      expect(find.text('Text Widgets: ${initialCount + 1}'), findsOneWidget);

      // 4. Lazy Loading & Scroll-to-Match:
      // While lazy loading is active, offscreen "Lazy Archive #20" is not yet built.
      expect(find.byKey(const Key('lazy_archive_text_20')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('search_input')),
        'Deep Offscreen Target',
      );
      await tester.pumpAndSettle();
      expect(find.text('0 / 0'), findsOneWidget);

      // Cancel lazy loading (or press Ctrl+F) to materialize all 19 remaining offscreen SliverList items.
      await tester.tap(find.byKey(const Key('eager_load_chip')));
      await tester.pumpAndSettle();

      // Now all 20 SliverList items are materialized and item #20 is matched!
      expect(find.text('1 / 1'), findsOneWidget);
      expect(
        find.text('Text Widgets: ${initialCount + 1 + 19}'),
        findsOneWidget,
      );

      // Trigger nextMatch() / scrollToActiveMatch() and verify the scroll view scrolls to item #20.
      await tester.tap(find.byKey(const Key('search_next_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lazy_archive_text_20')), findsOneWidget);

      // 5. ReadAloudPlugin: step word-by-word through the document in true visual order.
      expect(find.byKey(const Key('read_aloud_status')), findsOneWidget);
      expect(find.textContaining('Idle ('), findsOneWidget);
      await tester.tap(find.byKey(const Key('read_aloud_next_word_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Speaking: "Composable" (1/'), findsOneWidget);
      await tester.tap(find.byKey(const Key('read_aloud_next_word_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Speaking: "Text" (2/'), findsOneWidget);

      // 6. SpellcheckLinterPlugin & SpoilerMaskPlugin on custom_note_text_0:
      final Finder customNote0Finder = find.byKey(
        const Key('custom_note_text_0'),
      );
      await tester.ensureVisible(customNote0Finder);
      await tester.pumpAndSettle();
      final RenderParagraph noteParagraph = tester
          .renderObject<RenderParagraph>(
            find.descendant(
              of: customNote0Finder,
              matching: find.byType(RichText),
            ),
          );
      final String notePlainText = noteParagraph.text.toPlainText();

      // Tap on misspelled word "recieve".
      final int recieveIndex = notePlainText.indexOf('recieve');
      final List<TextBox> recieveBoxes = noteParagraph.getBoxesForSelection(
        TextSelection(
          baseOffset: recieveIndex,
          extentOffset: recieveIndex + 'recieve'.length,
        ),
      );
      final Offset recieveGlobalCenter = noteParagraph.localToGlobal(
        recieveBoxes.first.toRect().center,
      );
      await tester.tapAt(recieveGlobalCenter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('last_tapped_spellcheck')), findsOneWidget);
      expect(find.text('Lint "recieve" → "receive"'), findsOneWidget);

      // Tap on masked spoiler "||Rosebud is the sled||" to reveal it, then tap again to mask it.
      final int spoilerIndex = notePlainText.indexOf('||Rosebud is the sled||');
      final List<TextBox> spoilerBoxes = noteParagraph.getBoxesForSelection(
        TextSelection(
          baseOffset: spoilerIndex,
          extentOffset: spoilerIndex + '||Rosebud is the sled||'.length,
        ),
      );
      await tester.tapAt(
        noteParagraph.localToGlobal(spoilerBoxes.first.toRect().center),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('last_tapped_spoiler')), findsOneWidget);
      expect(
        find.text('Spoiler: Revealed (||Rosebud is the sled||)'),
        findsOneWidget,
      );

      await tester.tapAt(
        noteParagraph.localToGlobal(spoilerBoxes.first.toRect().center),
      );
      await tester.pumpAndSettle();
      expect(find.text('Spoiler: Masked (••••••••)'), findsOneWidget);

      // 7. Verify SelectionArea coexistence zone under the Opt-Out Zone.
      final Finder selectionAreaZoneFinder = find.byKey(
        const Key('selection_area_zone'),
      );
      await tester.ensureVisible(selectionAreaZoneFinder);
      await tester.pumpAndSettle();
      expect(selectionAreaZoneFinder, findsOneWidget);
      expect(
        find.byKey(const Key('selection_area_paragraph_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('selection_area_paragraph_2')),
        findsOneWidget,
      );

      // Verify SearchInPagePlugin matches text inside SelectionArea.
      await tester.enterText(
        find.byKey(const Key('search_input')),
        'Second selectable paragraph',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);

      // 8. Verify closing the search widget and pressing Ctrl+F to reopen and focus it.
      await tester.tap(find.byKey(const Key('search_position_floating_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_search_bar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('search_close_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_search_bar')), findsNothing);
      expect(find.byKey(const Key('top_search_bar')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_search_bar')), findsOneWidget);
      final TextField searchField = tester.widget<TextField>(
        find.byKey(const Key('search_input')),
      );
      expect(searchField.focusNode!.hasFocus, isTrue);

      // Verify pressing Enter repeatedly advances through matches while keeping focus.
      await tester.enterText(find.byKey(const Key('search_input')), 'Flutter');
      await tester.pumpAndSettle();
      expect(find.text('1 / 4'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);
      expect(searchField.focusNode!.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('3 / 4'), findsOneWidget);
      expect(searchField.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'SearchInPagePlugin updates only the changed delegate on didUpdateText',
    (WidgetTester tester) async {
      final plugin = SearchInPagePlugin()..query = 'Flutter';
      addTearDown(plugin.dispose);
      final middleText = ValueNotifier<String>('Unrelated middle paragraph');
      addTearDown(middleText.dispose);
      final bottomExtra = ValueNotifier<String>('Bottom Flutter item');
      addTearDown(bottomExtra.dispose);

      var notifications = 0;
      plugin.addListener(() {
        notifications += 1;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextPluginScope(
              plugin: plugin,
              child: Column(
                children: <Widget>[
                  const Text('Top Flutter item'),
                  ValueListenableBuilder<String>(
                    valueListenable: middleText,
                    builder:
                        (BuildContext context, String value, Widget? child) {
                          return Text(value);
                        },
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: bottomExtra,
                    builder:
                        (BuildContext context, String value, Widget? child) {
                          return Text(value);
                        },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(plugin.matches, hasLength(2));
      // Focus the second match ("Bottom Flutter item") explicitly.
      plugin.nextMatch();
      await tester.pump();
      expect(plugin.activeMatchIndex, 1);

      final TextDelegate topDelegate = plugin.matches.first.delegate;
      final TextDelegate bottomDelegate = plugin.matches.last.delegate;
      final CustomPainter? initialTopPainter = topDelegate.backgroundPainter;
      final CustomPainter? initialBottomBgPainter =
          bottomDelegate.backgroundPainter;
      final CustomPainter? initialBottomFgPainter =
          bottomDelegate.foregroundPainter;
      expect(initialTopPainter, isNotNull);
      expect(initialBottomBgPainter, isNotNull);
      expect(initialBottomFgPainter, isNotNull);

      // 1. Updating a paragraph with 0 -> 0 matches does no work and does not
      // rebuild painters or notify listeners.
      notifications = 0;
      middleText.value = 'Still no match here';
      await tester.pump();
      expect(notifications, 0);
      expect(plugin.matches, hasLength(2));
      expect(plugin.activeMatchIndex, 1);
      expect(topDelegate.backgroundPainter, same(initialTopPainter));
      expect(bottomDelegate.backgroundPainter, same(initialBottomBgPainter));
      expect(bottomDelegate.foregroundPainter, same(initialBottomFgPainter));

      // 2. Updating a matching paragraph where match ranges stay identical
      // preserves painters on other delegates and skips redundant notifications.
      bottomExtra.value = 'Bottom Flutter item with trailing text';
      await tester.pump();
      expect(notifications, 0);
      expect(plugin.matches, hasLength(2));
      expect(plugin.activeMatchIndex, 1);
      expect(topDelegate.backgroundPainter, same(initialTopPainter));
      expect(bottomDelegate.backgroundPainter, same(initialBottomBgPainter));

      // 3. Middle paragraph gains 1 match: spliced in document order between
      // top and bottom without recreating painters on top or bottom!
      middleText.value = 'Middle Flutter match';
      await tester.pump();
      expect(notifications, 1);
      expect(plugin.matches, hasLength(3));
      expect(plugin.matches[0].delegate, same(topDelegate));
      expect(plugin.matches[2].delegate, same(bottomDelegate));
      expect(plugin.activeMatchIndex, 2);
      expect(plugin.activeMatch!.delegate, same(bottomDelegate));
      expect(topDelegate.backgroundPainter, same(initialTopPainter));
      expect(bottomDelegate.backgroundPainter, same(initialBottomBgPainter));
      expect(bottomDelegate.foregroundPainter, same(initialBottomFgPainter));

      // 4. Middle paragraph expands to 2 matches in place: only middle painter
      // updates, top and bottom painters remain untouched, activeMatch shifts to 3.
      final TextDelegate middleDelegate = plugin.matches[1].delegate;
      final CustomPainter? middlePainterWithOne =
          middleDelegate.backgroundPainter;
      expect(middlePainterWithOne, isNotNull);

      middleText.value = 'Middle Flutter and second Flutter';
      await tester.pump();
      expect(notifications, 2);
      expect(plugin.matches, hasLength(4));
      expect(plugin.matches[1].delegate, same(middleDelegate));
      expect(plugin.matches[2].delegate, same(middleDelegate));
      expect(plugin.activeMatchIndex, 3);
      expect(plugin.activeMatch!.delegate, same(bottomDelegate));
      expect(
        middleDelegate.backgroundPainter,
        isNot(same(middlePainterWithOne)),
      );
      expect(topDelegate.backgroundPainter, same(initialTopPainter));
      expect(bottomDelegate.backgroundPainter, same(initialBottomBgPainter));

      // 5. Middle paragraph loses all matches: its painters clear, top and
      // bottom painters remain untouched, and activeMatch shifts back to 1.
      middleText.value = 'Cleared middle paragraph';
      await tester.pump();
      expect(notifications, 3);
      expect(plugin.matches, hasLength(2));
      expect(plugin.activeMatchIndex, 1);
      expect(plugin.activeMatch!.delegate, same(bottomDelegate));
      expect(middleDelegate.backgroundPainter, isNull);
      expect(middleDelegate.foregroundPainter, isNull);
      expect(topDelegate.backgroundPainter, same(initialTopPainter));
      expect(bottomDelegate.backgroundPainter, same(initialBottomBgPainter));
    },
  );
}
