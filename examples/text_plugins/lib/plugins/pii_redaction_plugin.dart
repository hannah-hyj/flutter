// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Category of sensitive Personally Identifiable Information (PII) or secret.
enum PiiKind {
  /// An API key or secret token (e.g. `sk-live-...`).
  apiKey('API Key'),

  /// A Social Security Number (`XXX-XX-XXXX`).
  ssn('SSN'),

  /// An email address.
  email('Email'),

  /// A credit card number.
  creditCard('Credit Card');

  const PiiKind(this.label);

  /// Human-readable label for the PII category.
  final String label;
}

/// Represents a detected sensitive text span within a [TextDelegate].
@immutable
class PiiMatch {
  /// Creates a [PiiMatch].
  const PiiMatch({
    required this.delegate,
    required this.range,
    required this.kind,
    required this.rawValue,
  });

  /// The [TextDelegate] containing this sensitive span.
  final TextDelegate delegate;

  /// The character range of the sensitive span within [TextDelegate.text].
  final TextRange range;

  /// The category of sensitive information.
  final PiiKind kind;

  /// The underlying sensitive text value.
  final String rawValue;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PiiMatch &&
        other.delegate == delegate &&
        other.range == range &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(delegate, range, kind);
}

/// Callback signature invoked when a redacted span is tapped to toggle reveal.
typedef PiiTapCallback = void Function(PiiMatch match, {required bool isRevealed});

/// A [TextPlugin] that detects sensitive PII (API keys, SSNs, credit cards,
/// and email addresses) across all [Text] and [RichText] widgets in its scope
/// and masks them using a [TextDelegate.foregroundPainter].
///
/// Tapping a redacted box toggles revealing or re-masking that specific span.
class PiiRedactionPlugin extends TextPlugin with ChangeNotifier {
  /// Creates a [PiiRedactionPlugin].
  PiiRedactionPlugin({this.onMatchTapped});

  /// Optional callback invoked when the user taps a redacted or revealed PII span.
  final PiiTapCallback? onMatchTapped;

  static final List<(PiiKind, RegExp)> _patterns = <(PiiKind, RegExp)>[
    (PiiKind.apiKey, RegExp(r'\bsk-[A-Za-z0-9_-]{8,}\b')),
    (PiiKind.ssn, RegExp(r'\b\d{3}-\d{2}-\d{4}\b')),
    (PiiKind.creditCard, RegExp(r'\b(?:\d{4}[-\s]){3}\d{4}\b')),
    (PiiKind.email, RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')),
  ];

  final Map<TextDelegate, List<PiiMatch>> _matchesByDelegate = <TextDelegate, List<PiiMatch>>{};
  final Set<PiiMatch> _revealedMatches = <PiiMatch>{};

  /// Total number of sensitive PII spans currently detected in the scope.
  int get totalRedactedCount {
    var count = 0;
    for (final List<PiiMatch> list in _matchesByDelegate.values) {
      count += list.length;
    }
    return count;
  }

  /// Whether the given [match] is currently revealed.
  bool isRevealed(PiiMatch match) => _revealedMatches.contains(match);

  /// Reveals all detected PII spans.
  void revealAll() {
    _matchesByDelegate.values.forEach(_revealedMatches.addAll);
    _markAllNeedsPaint();
    notifyListeners();
  }

  /// Masks (redacts) all detected PII spans.
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
    _revealedMatches.removeWhere((PiiMatch m) => m.delegate == delegate);
  }

  @override
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {
    if (event is! PointerDownEvent || !delegate.hasLayout) {
      return;
    }
    final List<PiiMatch>? matches = _matchesByDelegate[delegate];
    if (matches == null || matches.isEmpty) {
      return;
    }
    final Offset localPosition = event.localPosition;
    for (final PiiMatch match in matches) {
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: match.range.start, extentOffset: match.range.end),
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
    final found = <PiiMatch>[];
    for (final (PiiKind kind, RegExp pattern) in _patterns) {
      for (final RegExpMatch match in pattern.allMatches(plainText)) {
        found.add(
          PiiMatch(
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
      delegate.foregroundPainter = _PiiRedactionForegroundPainter(
        delegate: delegate,
        matches: found,
        revealedMatches: _revealedMatches,
      );
    }
  }
}

class _PiiRedactionForegroundPainter extends CustomPainter {
  _PiiRedactionForegroundPainter({
    required this.delegate,
    required this.matches,
    required this.revealedMatches,
  });

  final TextDelegate delegate;
  final List<PiiMatch> matches;
  final Set<PiiMatch> revealedMatches;

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
      ..color = const Color(0xFFD32F2F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final revealedTintPaint = Paint()
      ..color = const Color(0x22D32F2F)
      ..style = PaintingStyle.fill;

    for (final PiiMatch match in matches) {
      final bool isRevealed = revealedMatches.contains(match);
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: match.range.start, extentOffset: match.range.end),
        includePlaceholders: false,
      );
      for (final box in boxes) {
        final Rect rect = box.toRect().inflate(1.5);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4.0));
        if (isRevealed) {
          canvas.drawRRect(rrect, revealedTintPaint);
          canvas.drawRRect(rrect, revealedBorderPaint);
        } else {
          // Opaque foreground redaction bar completely hides the underlying glyphs.
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
  bool shouldRepaint(covariant _PiiRedactionForegroundPainter oldDelegate) {
    return true;
  }
}
