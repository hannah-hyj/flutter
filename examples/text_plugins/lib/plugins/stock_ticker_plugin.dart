// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
const Map<String, StockTickerInfo> kDefaultStockTickers =
    <String, StockTickerInfo>{
      'GOOG': StockTickerInfo(
        symbol: 'GOOG',
        companyName: 'Alphabet Inc.',
        price: 194.85,
        changePercent: 2.41,
        marketCap: r'$2.41T',
        summary: 'Global technology leader in search, cloud computing, AI, and Android/Flutter ecosystems.',
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
        summary: 'Designs and manufactures electric vehicles, battery energy storage, and solar products.',
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
  const _TickerOccurrence({
    required this.range,
    required this.info,
    required this.text,
  });

  final TextRange range;
  final StockTickerInfo info;
  final String text;
}

/// A [TextPlugin] that automatically identifies stock ticker symbols (e.g.
/// `GOOG`, `AAPL`, `NVDA`) in any [Text] widget and highlights them with a
/// color-coded badge and underline.
class StockTickerPlugin extends TextPlugin {
  /// Creates a [StockTickerPlugin].
  StockTickerPlugin({this.tickers = kDefaultStockTickers, this.badges = false});

  /// Whether a ticker is replaced by a badge widget (a [WidgetSpan]).
  ///
  /// If false, a ticker gets a background color and a dotted underline, which
  /// is what a [TextStyle] can do. A rounded badge with padding is not
  /// something a style can draw. With a badge the ticker is no longer text:
  /// it does not wrap, it is not part of a selection, and a text field
  /// ignores it.
  final bool badges;

  /// Map of recognized ticker symbols to their [StockTickerInfo].
  final Map<String, StockTickerInfo> tickers;

  final Map<TextDelegate, List<_TickerOccurrence>> _occurrencesByDelegate =
      <TextDelegate, List<_TickerOccurrence>>{};

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
  void didRemoveText(TextDelegate delegate) {
    _occurrencesByDelegate.remove(delegate);
  }

  void _analyzeDelegate(TextDelegate delegate) {
    if (tickers.isEmpty) {
      _occurrencesByDelegate.remove(delegate);
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
            text: text.substring(match.start, match.end),
          ),
        );
      }
    }
    if (found.isEmpty) {
      _occurrencesByDelegate.remove(delegate);
    } else {
      _occurrencesByDelegate[delegate] = found;
    }
  }

  static const TextStyle _upStyle = TextStyle(
    backgroundColor: Color(0x332E7D32),
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
    decorationColor: Color(0xFF2E7D32),
  );

  static const TextStyle _downStyle = TextStyle(
    backgroundColor: Color(0x33C62828),
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
    decorationColor: Color(0xFFC62828),
  );

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final List<_TickerOccurrence>? occurrences =
        _occurrencesByDelegate[delegate];
    if (occurrences == null) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      for (final _TickerOccurrence occurrence in occurrences)
        if (badges && !delegate.isEditable)
          TextSpanDecoration(
            range: occurrence.range,
            replacement: WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: _TickerBadge(occurrence: occurrence),
            ),
          )
        else
          TextSpanDecoration(
            range: occurrence.range,
            style: occurrence.info.isPositive ? _upStyle : _downStyle,
          ),
    ];
  }
}

class _TickerBadge extends StatelessWidget {
  const _TickerBadge({required this.occurrence});

  final _TickerOccurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final bool up = occurrence.info.isPositive;
    final color = up ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      // The badge is outside of the plugin scope, or the plugin would find
      // the ticker inside of its own badge.
      child: TextPluginScope.none(
        child: Text(
          '${occurrence.text} ${up ? '\u25B2' : '\u25BC'}',
          style: DefaultTextStyle.of(context).style.copyWith(color: color),
        ),
      ),
    );
  }
}
