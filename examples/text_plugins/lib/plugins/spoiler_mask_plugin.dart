// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Category of interactive visual text mask (spoiler tag or flashcard cloze).
enum SpoilerMaskKind {
  /// A forum/chat spoiler span (e.g. `||Darth Vader||`).
  spoiler('Spoiler'),

  /// A flashcard cloze-deletion study answer (e.g. `{{RenderParagraph}}`).
  cloze('Cloze Study');

  const SpoilerMaskKind(this.label);

  /// Human-readable label for the mask category.
  final String label;
}

/// Represents a detected spoiler or cloze-study text span within a [TextDelegate].
@immutable
class SpoilerMaskMatch {
  /// Creates a [SpoilerMaskMatch].
  const SpoilerMaskMatch({
    required this.delegate,
    required this.range,
    required this.kind,
    required this.rawValue,
  });

  /// The [TextDelegate] containing this masked span.
  final TextDelegate delegate;

  /// The character range of the masked span within [TextDelegate.text].
  final TextRange range;

  /// The category of masked span.
  final SpoilerMaskKind kind;

  /// The underlying masked text value.
  final String rawValue;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SpoilerMaskMatch &&
        other.delegate == delegate &&
        other.range == range &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(delegate, range, kind);
}

/// Callback signature invoked when a masked span is tapped to toggle reveal.
typedef SpoilerMaskTapCallback = void Function(
  SpoilerMaskMatch match, {
  required bool isRevealed,
});

/// A [TextPlugin] that detects spoiler tags (`||...||`) and flashcard
/// cloze-deletion study markers (`{{...}}`) across all [Text], [RichText], and
/// [EditableText] widgets in its scope and masks them using a
/// [TextDelegate.foregroundPainter].
///
/// Tapping a masked box toggles revealing or re-masking that specific span.
class SpoilerMaskPlugin extends TextPlugin with ChangeNotifier {
  /// Creates a [SpoilerMaskPlugin].
  SpoilerMaskPlugin({this.onMatchTapped});

  /// Optional callback invoked when the user taps a masked or revealed span.
  final SpoilerMaskTapCallback? onMatchTapped;

  static final List<(SpoilerMaskKind, RegExp)> _patterns =
      <(SpoilerMaskKind, RegExp)>[
        (SpoilerMaskKind.spoiler, RegExp(r'\|\|[^|\n]+\|\|')),
        (SpoilerMaskKind.cloze, RegExp(r'\{\{[^}\n]+\}\}')),
      ];

  final Map<TextDelegate, List<SpoilerMaskMatch>> _matchesByDelegate =
      <TextDelegate, List<SpoilerMaskMatch>>{};
  final Set<SpoilerMaskMatch> _revealedMatches = <SpoilerMaskMatch>{};

  /// Total number of spoiler or cloze spans currently detected in the scope.
  int get totalMaskedCount {
    var count = 0;
    for (final List<SpoilerMaskMatch> list in _matchesByDelegate.values) {
      count += list.length;
    }
    return count;
  }

  /// Whether the given [match] is currently revealed.
  bool isRevealed(SpoilerMaskMatch match) => _revealedMatches.contains(match);

  /// Reveals all detected spoiler and cloze spans.
  void revealAll() {
    _matchesByDelegate.values.forEach(_revealedMatches.addAll);
    _markAllNeedsPaint();
    notifyListeners();
  }

  /// Masks all detected spoiler and cloze spans.
  void maskAll() {
    if (_revealedMatches.isEmpty) {
      return;
    }
    _revealedMatches.clear();
    _markAllNeedsPaint();
    notifyListeners();
  }

  void _markAllNeedsPaint() {
    for (final TextDelegate delegate in _matchesByDelegate.keys) {
      delegate.markNeedsPaint();
    }
  }

  @override
  void didAddText(TextDelegate delegate) {
    _scanDelegate(delegate);
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _scanDelegate(delegate);
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    if (_matchesByDelegate.containsKey(delegate)) {
      delegate.markNeedsPaint();
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.foregroundPainter = null;
    _matchesByDelegate.remove(delegate);
    _revealedMatches.removeWhere(
      (SpoilerMaskMatch m) => m.delegate == delegate,
    );
  }

  @override
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {
    if (event is! PointerDownEvent || !delegate.hasLayout) {
      return;
    }
    final List<SpoilerMaskMatch>? matches = _matchesByDelegate[delegate];
    if (matches == null || matches.isEmpty) {
      return;
    }
    final Offset localPosition = event.localPosition;
    for (final SpoilerMaskMatch match in matches) {
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(
          baseOffset: match.range.start,
          extentOffset: match.range.end,
        ),
        includePlaceholders: false,
      );
      for (final box in boxes) {
        if (box.toRect().inflate(2.0).contains(localPosition)) {
          final bool nowRevealed = !_revealedMatches.remove(match);
          if (nowRevealed) {
            _revealedMatches.add(match);
          }
          delegate.markNeedsPaint();
          notifyListeners();
          onMatchTapped?.call(match, isRevealed: nowRevealed);
          return;
        }
      }
    }
  }

  void _scanDelegate(TextDelegate delegate) {
    final String plainText = delegate.text;
    final found = <SpoilerMaskMatch>[];
    for (final (SpoilerMaskKind kind, RegExp pattern) in _patterns) {
      for (final RegExpMatch match in pattern.allMatches(plainText)) {
        found.add(
          SpoilerMaskMatch(
            delegate: delegate,
            range: TextRange(start: match.start, end: match.end),
            kind: kind,
            rawValue: match.group(0)!,
          ),
        );
      }
    }
    if (found.isEmpty) {
      _matchesByDelegate.remove(delegate);
      delegate.foregroundPainter = null;
    } else {
      _matchesByDelegate[delegate] = found;
      delegate.foregroundPainter = _SpoilerMaskForegroundPainter(
        delegate: delegate,
        matches: found,
        revealedMatches: _revealedMatches,
      );
    }
  }
}

class _SpoilerMaskForegroundPainter extends CustomPainter {
  _SpoilerMaskForegroundPainter({
    required this.delegate,
    required this.matches,
    required this.revealedMatches,
  });

  final TextDelegate delegate;
  final List<SpoilerMaskMatch> matches;
  final Set<SpoilerMaskMatch> revealedMatches;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final maskFillPaint = Paint()
      ..color = const Color(0xFF263238)
      ..style = PaintingStyle.fill;
    final maskStripePaint = Paint()
      ..color = const Color(0xFF455A64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    final revealedBorderPaint = Paint()
      ..color = const Color(0xFF5E35B1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final revealedTintPaint = Paint()
      ..color = const Color(0x225E35B1)
      ..style = PaintingStyle.fill;

    for (final SpoilerMaskMatch match in matches) {
      final bool isRevealed = revealedMatches.contains(match);
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(
          baseOffset: match.range.start,
          extentOffset: match.range.end,
        ),
        includePlaceholders: false,
      );
      for (final box in boxes) {
        final Rect rect = box.toRect().inflate(1.5);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4.0));
        if (isRevealed) {
          canvas.drawRRect(rrect, revealedTintPaint);
          canvas.drawRRect(rrect, revealedBorderPaint);
        } else {
          // Opaque foreground bar covers the spoiler or cloze-study answer until tapped.
          canvas.drawRRect(rrect, maskFillPaint);
          canvas.save();
          canvas.clipRRect(rrect);
          for (double x = rect.left - rect.height; x < rect.right; x += 6.0) {
            canvas.drawLine(
              Offset(x, rect.bottom),
              Offset(x + rect.height, rect.top),
              maskStripePaint,
            );
          }
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpoilerMaskForegroundPainter oldDelegate) {
    return true;
  }
}
