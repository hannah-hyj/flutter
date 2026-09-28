// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Market quote metadata for a recognized stock ticker symbol.
@immutable
class StockTickerInfo {
  /// Creates a [StockTickerInfo].
  const StockTickerInfo({
    required this.symbol,
    required this.companyName,
    required this.price,
    required this.changePercent,
    required this.marketCap,
    required this.summary,
  });

  /// The stock ticker symbol (e.g., `GOOG`, `AAPL`).
  final String symbol;

  /// Full company name.
  final String companyName;

  /// Current simulated share price in USD.
  final double price;

  /// Daily percentage change (positive or negative).
  final double changePercent;

  /// Formatted market capitalization string.
  final String marketCap;

  /// Brief company description.
  final String summary;

  /// Whether the stock is up for the day.
  bool get isPositive => changePercent >= 0;
}

/// Default catalog of stock tickers recognized by [StockTickerPlugin].
const Map<String, StockTickerInfo> kDefaultStockTickers = <String, StockTickerInfo>{
  'GOOG': StockTickerInfo(
    symbol: 'GOOG',
    companyName: 'Alphabet Inc.',
    price: 194.85,
    changePercent: 2.41,
    marketCap: r'$2.41T',
    summary:
        'Global technology leader in search, cloud computing, AI, and Android/Flutter ecosystems.',
  ),
  'AAPL': StockTickerInfo(
    symbol: 'AAPL',
    companyName: 'Apple Inc.',
    price: 229.40,
    changePercent: 1.15,
    marketCap: r'$3.48T',
    summary: 'Designs consumer electronics, software, and services including iPhone, Mac, and iOS.',
  ),
  'MSFT': StockTickerInfo(
    symbol: 'MSFT',
    companyName: 'Microsoft Corporation',
    price: 446.20,
    changePercent: -0.62,
    marketCap: r'$3.31T',
    summary: 'Develops enterprise cloud infrastructure (Azure), productivity software, and developer tools.',
  ),
  'NVDA': StockTickerInfo(
    symbol: 'NVDA',
    companyName: 'NVIDIA Corporation',
    price: 138.60,
    changePercent: 4.18,
    marketCap: r'$3.39T',
    summary: 'Pioneers accelerated computing, GPUs, and data-center AI hardware & software.',
  ),
  'TSLA': StockTickerInfo(
    symbol: 'TSLA',
    companyName: 'Tesla, Inc.',
    price: 254.10,
    changePercent: -1.84,
    marketCap: r'$802B',
    summary:
        'Designs and manufactures electric vehicles, battery energy storage, and solar products.',
  ),
  'AMZN': StockTickerInfo(
    symbol: 'AMZN',
    companyName: 'Amazon.com, Inc.',
    price: 211.75,
    changePercent: 1.73,
    marketCap: r'$2.22T',
    summary: 'Multinational e-commerce, cloud computing (AWS), digital streaming, and AI company.',
  ),
};

@immutable
class _TickerOccurrence {
  const _TickerOccurrence({required this.range, required this.info});

  final TextRange range;
  final StockTickerInfo info;
}

/// A [TextPlugin] that automatically identifies stock ticker symbols (e.g.
/// `GOOG`, `AAPL`, `NVDA`) in any [Text] widget, highlights them with a
/// color-coded badge and underline, and makes them interactive on tap.
class StockTickerPlugin extends TextPlugin {
  /// Creates a [StockTickerPlugin].
  StockTickerPlugin({this.tickers = kDefaultStockTickers, this.onTickerTapped});

  /// Map of recognized ticker symbols to their [StockTickerInfo].
  final Map<String, StockTickerInfo> tickers;

  /// Callback invoked when the user taps a highlighted ticker symbol.
  final ValueChanged<StockTickerInfo>? onTickerTapped;

  final Map<TextDelegate, List<_TickerOccurrence>> _occurrencesByDelegate =
      <TextDelegate, List<_TickerOccurrence>>{};
  final Map<TextDelegate, Offset> _pointerDownPositions = <TextDelegate, Offset>{};

  RegExp get _tickerPattern {
    final String joined = tickers.keys.map(RegExp.escape).join('|');
    return RegExp(r'(?:\b|\$)(' + joined + r')\b');
  }

  @override
  void didAddText(TextDelegate delegate) {
    _analyzeDelegate(delegate);
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _analyzeDelegate(delegate);
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    if (_occurrencesByDelegate.containsKey(delegate)) {
      delegate.markNeedsPaint();
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.backgroundPainter = null;
    delegate.foregroundPainter = null;
    _occurrencesByDelegate.remove(delegate);
    _pointerDownPositions.remove(delegate);
  }

  @override
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {
    final List<_TickerOccurrence>? occurrences = _occurrencesByDelegate[delegate];
    if (occurrences == null || occurrences.isEmpty || !delegate.hasLayout) {
      return;
    }

    if (event is PointerDownEvent) {
      _pointerDownPositions[delegate] = event.localPosition;
    } else if (event is PointerUpEvent) {
      final Offset? downPos = _pointerDownPositions.remove(delegate);
      if (downPos == null || (event.localPosition - downPos).distance > kTouchSlop) {
        return;
      }
      for (final _TickerOccurrence occurrence in occurrences) {
        final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
          TextSelection(baseOffset: occurrence.range.start, extentOffset: occurrence.range.end),
        );
        final bool hit = boxes.any(
          (ui.TextBox box) => box.toRect().inflate(3.0).contains(event.localPosition),
        );
        if (hit) {
          onTickerTapped?.call(occurrence.info);
          break;
        }
      }
    } else if (event is PointerCancelEvent) {
      _pointerDownPositions.remove(delegate);
    }
  }

  void _analyzeDelegate(TextDelegate delegate) {
    if (tickers.isEmpty) {
      _occurrencesByDelegate.remove(delegate);
      delegate.backgroundPainter = null;
      delegate.foregroundPainter = null;
      return;
    }
    final String text = delegate.text;
    final found = <_TickerOccurrence>[];
    for (final RegExpMatch match in _tickerPattern.allMatches(text)) {
      final String? symbol = match.group(1);
      if (symbol != null && tickers.containsKey(symbol)) {
        found.add(
          _TickerOccurrence(
            range: TextRange(start: match.start, end: match.end),
            info: tickers[symbol]!,
          ),
        );
      }
    }

    if (found.isEmpty) {
      _occurrencesByDelegate.remove(delegate);
      delegate.backgroundPainter = null;
      delegate.foregroundPainter = null;
    } else {
      _occurrencesByDelegate[delegate] = found;
      delegate.backgroundPainter = _StockTickerBackgroundPainter(
        delegate: delegate,
        occurrences: found,
      );
      delegate.foregroundPainter = _StockTickerForegroundPainter(
        delegate: delegate,
        occurrences: found,
      );
    }
  }
}

class _StockTickerBackgroundPainter extends CustomPainter {
  _StockTickerBackgroundPainter({required this.delegate, required this.occurrences});

  final TextDelegate delegate;
  final List<_TickerOccurrence> occurrences;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final upPaint = Paint()
      ..color = const Color(0x332E7D32)
      ..style = PaintingStyle.fill;
    final downPaint = Paint()
      ..color = const Color(0x33C62828)
      ..style = PaintingStyle.fill;

    for (final _TickerOccurrence occurrence in occurrences) {
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: occurrence.range.start, extentOffset: occurrence.range.end),
      );
      for (final box in boxes) {
        final pill = RRect.fromRectAndRadius(box.toRect().inflate(2.0), const Radius.circular(4.0));
        canvas.drawRRect(pill, occurrence.info.isPositive ? upPaint : downPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StockTickerBackgroundPainter oldDelegate) {
    return oldDelegate.occurrences != occurrences;
  }
}

class _StockTickerForegroundPainter extends CustomPainter {
  _StockTickerForegroundPainter({required this.delegate, required this.occurrences});

  final TextDelegate delegate;
  final List<_TickerOccurrence> occurrences;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final upStroke = Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final downStroke = Paint()
      ..color = const Color(0xFFC62828)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final _TickerOccurrence occurrence in occurrences) {
      final paint = occurrence.info.isPositive ? upStroke : downStroke;
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: occurrence.range.start, extentOffset: occurrence.range.end),
      );
      for (final box in boxes) {
        final Rect rect = box.toRect();
        final double y = rect.bottom;
        double x = rect.left;
        while (x < rect.right) {
          final double segEnd = (x + 3.0).clamp(rect.left, rect.right);
          canvas.drawLine(Offset(x, y), Offset(segEnd, y), paint);
          x += 5.0;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StockTickerForegroundPainter oldDelegate) {
    return oldDelegate.occurrences != occurrences;
  }
}
