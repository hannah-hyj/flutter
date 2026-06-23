// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:a11y_assessments/use_cases/toggle_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  testWidgets('toggle buttons can run', (WidgetTester tester) async {
    await pumpsUseCase(tester, ToggleButtonsUseCase());
    expect(find.byType(ToggleButtons), findsOneWidget);
  });

  testWidgets('toggle buttons can toggle state', (WidgetTester tester) async {
    await pumpsUseCase(tester, ToggleButtonsUseCase());
    final Finder findBold = find.bySemanticsLabel('Bold');
    expect(findBold, findsOneWidget);

    final Finder findToggleButtons = find.byType(ToggleButtons);
    expect(findToggleButtons, findsOneWidget);

    ToggleButtons widget = tester.widget(findToggleButtons);
    expect(widget.isSelected[0], isTrue);

    await tester.tap(findBold);
    await tester.pumpAndSettle();

    widget = tester.widget(findToggleButtons);
    expect(widget.isSelected[0], isFalse);
  });

  // Verifies that the contrast ratio between the background of the selected state
  // and the background of the unselected/default state is at least 3:1.
  // This is required by WCAG 2.1 Success Criterion 1.4.11 (Non-text Contrast) to
  // ensure users can identify when a user interface component changes state:
  // https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
  testWidgets('toggle buttons selected and unselected backgrounds have at least 3:1 contrast ratio', (
    WidgetTester tester,
  ) async {
    await pumpsUseCase(tester, ToggleButtonsUseCase());

    final Finder findToggleButtons = find.byType(ToggleButtons);
    expect(findToggleButtons, findsOneWidget);

    final BuildContext context = tester.element(findToggleButtons);
    final ThemeData theme = Theme.of(context);
    final ToggleButtons widget = tester.widget(findToggleButtons);

    final Color unselectedBg = theme.scaffoldBackgroundColor;
    final Color selectedBg = widget.fillColor ?? theme.colorScheme.primary.withOpacity(0.12);

    final double l1 = unselectedBg.computeLuminance();
    final double l2 = selectedBg.computeLuminance();
    final double contrastRatio = (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);

    expect(
      contrastRatio,
      greaterThanOrEqualTo(3.0),
      reason:
          'Contrast ratio between selected background ($selectedBg) and unselected background ($unselectedBg) must be at least 3.0',
    );
  });
}
