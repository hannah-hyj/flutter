// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Severity of a [SpellcheckIssue].
enum LintSeverity {
  /// A spelling mistake (painted with a red wavy underline).
  spellingError,

  /// A style-guide suggestion (painted with an amber/blue wavy underline).
  styleSuggestion,
}

/// Rule definition for [SpellcheckLinterPlugin].
@immutable
class SpellcheckRule {
  /// Creates a [SpellcheckRule].
  const SpellcheckRule({
    required this.incorrectWord,
    required this.suggestion,
    required this.message,
    required this.severity,
  });

  /// The lowercase word token to flag.
  final String incorrectWord;

  /// Recommended replacement text.
  final String suggestion;

  /// Diagnostic explanation for the author.
  final String message;

  /// Severity of the diagnostic.
  final LintSeverity severity;
}

/// Represents a single spelling or style issue detected in a [TextDelegate].
@immutable
class SpellcheckIssue {
  /// Creates a [SpellcheckIssue].
  const SpellcheckIssue({
    required this.delegate,
    required this.range,
    required this.matchedText,
    required this.rule,
  });

  /// The [TextDelegate] containing this issue.
  final TextDelegate delegate;

  /// The character range of the flagged word within [TextDelegate.text].
  final TextRange range;

  /// The exact substring matched in the text.
  final String matchedText;

  /// The [SpellcheckRule] that triggered this diagnostic.
  final SpellcheckRule rule;
}

/// Callback invoked when a user taps a squiggly-underlined word.
typedef SpellcheckTapCallback = void Function(SpellcheckIssue issue);

/// A [TextPlugin] that performs live spellchecking and editorial style-guide
/// linting across all [Text] and [RichText] widgets in its scope, painting
/// wavy squiggly underlines via [TextDelegate.foregroundPainter].
class SpellcheckLinterPlugin extends TextPlugin {
  /// Creates a [SpellcheckLinterPlugin].
  SpellcheckLinterPlugin({this.onIssueTapped});

  /// Optional callback invoked when a flagged word is tapped.
  final SpellcheckTapCallback? onIssueTapped;

  /// Built-in spelling and style-guide rules.
  static const Map<String, SpellcheckRule> defaultRules = <String, SpellcheckRule>{
    'recieve': SpellcheckRule(
      incorrectWord: 'recieve',
      suggestion: 'receive',
      message: 'Spelling: "i" before "e" except after "c".',
      severity: LintSeverity.spellingError,
    ),
    'seperate': SpellcheckRule(
      incorrectWord: 'seperate',
      suggestion: 'separate',
      message: 'Spelling: "separate" is spelled with "-par-", not "-per-".',
      severity: LintSeverity.spellingError,
    ),
    'occured': SpellcheckRule(
      incorrectWord: 'occured',
      suggestion: 'occurred',
      message: 'Spelling: double "r" in past tense "occurred".',
      severity: LintSeverity.spellingError,
    ),
    'teh': SpellcheckRule(
      incorrectWord: 'teh',
      suggestion: 'the',
      message: 'Spelling: common keyboard transposition typo.',
      severity: LintSeverity.spellingError,
    ),
    'utilize': SpellcheckRule(
      incorrectWord: 'utilize',
      suggestion: 'use',
      message: 'Style Guide: prefer concise "use" over "utilize".',
      severity: LintSeverity.styleSuggestion,
    ),
  };

  static final RegExp _wordTokenizer = RegExp(r'\b[A-Za-z]+\b');

  final Map<TextDelegate, List<SpellcheckIssue>> _issuesByDelegate =
      <TextDelegate, List<SpellcheckIssue>>{};

  @override
  void didAddText(TextDelegate delegate) {
    _lintDelegate(delegate);
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _lintDelegate(delegate);
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    if (_issuesByDelegate.containsKey(delegate)) {
      delegate.markNeedsPaint();
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.foregroundPainter = null;
    _issuesByDelegate.remove(delegate);
  }

  @override
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {
    if (event is! PointerDownEvent || onIssueTapped == null || !delegate.hasLayout) {
      return;
    }
    final List<SpellcheckIssue>? issues = _issuesByDelegate[delegate];
    if (issues == null || issues.isEmpty) {
      return;
    }
    final Offset localPosition = event.localPosition;
    for (final SpellcheckIssue issue in issues) {
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: issue.range.start, extentOffset: issue.range.end),
        includePlaceholders: false,
      );
      for (final box in boxes) {
        if (box.toRect().inflate(3.0).contains(localPosition)) {
          onIssueTapped!(issue);
          return;
        }
      }
    }
  }

  void _lintDelegate(TextDelegate delegate) {
    final String plainText = delegate.text;
    final issues = <SpellcheckIssue>[];
    for (final RegExpMatch match in _wordTokenizer.allMatches(plainText)) {
      final String word = match.group(0)!;
      final SpellcheckRule? rule = defaultRules[word.toLowerCase()];
      if (rule != null) {
        issues.add(
          SpellcheckIssue(
            delegate: delegate,
            range: TextRange(start: match.start, end: match.end),
            matchedText: word,
            rule: rule,
          ),
        );
      }
    }
    if (issues.isEmpty) {
      _issuesByDelegate.remove(delegate);
      delegate.foregroundPainter = null;
    } else {
      _issuesByDelegate[delegate] = issues;
      delegate.foregroundPainter = _SpellcheckSquigglePainter(delegate: delegate, issues: issues);
    }
  }
}

class _SpellcheckSquigglePainter extends CustomPainter {
  _SpellcheckSquigglePainter({required this.delegate, required this.issues});

  final TextDelegate delegate;
  final List<SpellcheckIssue> issues;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final errorPaint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final stylePaint = Paint()
      ..color = const Color(0xFFEF6C00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const waveStep = 3.0;
    const waveAmplitude = 1.6;

    for (final SpellcheckIssue issue in issues) {
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: issue.range.start, extentOffset: issue.range.end),
        includePlaceholders: false,
      );
      final paintToUse = issue.rule.severity == LintSeverity.spellingError
          ? errorPaint
          : stylePaint;
      for (final box in boxes) {
        final Rect rect = box.toRect();
        final double baseY = rect.bottom - 0.5;
        final path = Path()..moveTo(rect.left, baseY);
        var up = true;
        for (double x = rect.left + waveStep; x <= rect.right; x += waveStep) {
          path.lineTo(x, baseY + (up ? -waveAmplitude : waveAmplitude));
          up = !up;
        }
        canvas.drawPath(path, paintToUse);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpellcheckSquigglePainter oldDelegate) {
    return oldDelegate.issues != issues;
  }
}
