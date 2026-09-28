// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Represents a single search match within a [TextDelegate].
@immutable
class SearchMatch {
  /// Creates a [SearchMatch].
  const SearchMatch({required this.delegate, required this.range});

  /// The [TextDelegate] containing this match.
  final TextDelegate delegate;

  /// The character range of the match within [TextDelegate.text].
  final TextRange range;

  /// Returns the bounding [ui.TextBox]es for this match.
  List<ui.TextBox> getBoxes() {
    if (!delegate.hasLayout) {
      return const <ui.TextBox>[];
    }
    return delegate.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
  }
}

/// A [TextPlugin] that implements browser-style "Find in Page" search and
/// highlighting across all [Text] and [RichText] widgets in a
/// [TextPluginScope].
class SearchInPagePlugin extends TextPlugin with ChangeNotifier {
  /// Creates a [SearchInPagePlugin].
  SearchInPagePlugin({
    this.matchHighlightColor = const Color(0x66FFEB3B),
    this.activeMatchBackgroundColor = const Color(0x99FF9800),
    this.activeMatchBorderColor = const Color(0xFFE65100),
  });

  /// Background highlight color for all matches.
  final Color matchHighlightColor;

  /// Background highlight color for the currently active match.
  final Color activeMatchBackgroundColor;

  /// Border color painted in the foreground around the active match.
  final Color activeMatchBorderColor;

  final Set<TextDelegate> _delegates = <TextDelegate>{};
  final List<SearchMatch> _matches = <SearchMatch>[];

  String _query = '';
  bool _caseSensitive = false;
  int _activeMatchIndex = -1;
  bool _notificationScheduled = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyListenersSafely() {
    if (_disposed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (!_notificationScheduled) {
        _notificationScheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _notificationScheduled = false;
          if (!_disposed) {
            notifyListeners();
          }
        });
      }
    } else {
      notifyListeners();
    }
  }

  /// The current search query string.
  String get query => _query;
  set query(String value) {
    if (_query == value) {
      return;
    }
    _query = value;
    _rebuildMatches();
  }

  /// Whether matching is case-sensitive.
  bool get caseSensitive => _caseSensitive;
  set caseSensitive(bool value) {
    if (_caseSensitive == value) {
      return;
    }
    _caseSensitive = value;
    _rebuildMatches();
  }

  /// All current matches across the scoped subtree.
  List<SearchMatch> get matches => List<SearchMatch>.unmodifiable(_matches);

  /// The index of the currently focused match in [matches], or `-1` if there
  /// are no matches.
  int get activeMatchIndex => _activeMatchIndex;

  /// The currently focused [SearchMatch], or `null` if there are no matches.
  SearchMatch? get activeMatch => (_activeMatchIndex >= 0 && _activeMatchIndex < _matches.length)
      ? _matches[_activeMatchIndex]
      : null;

  /// Advances focus to the next match and scrolls it into view.
  void nextMatch() {
    if (_matches.isEmpty) {
      return;
    }
    _activeMatchIndex = (_activeMatchIndex + 1) % _matches.length;
    _updatePainters();
    _scrollToActiveMatch();
    _notifyListenersSafely();
  }

  /// Moves focus to the previous match and scrolls it into view.
  void previousMatch() {
    if (_matches.isEmpty) {
      return;
    }
    _activeMatchIndex = (_activeMatchIndex - 1 + _matches.length) % _matches.length;
    _updatePainters();
    _scrollToActiveMatch();
    _notifyListenersSafely();
  }

  void _scrollToActiveMatch() {
    final SearchMatch? current = activeMatch;
    if (current == null || !current.delegate.hasLayout) {
      return;
    }
    final List<ui.TextBox> boxes = current.getBoxes();
    Rect? targetRect;
    for (final box in boxes) {
      final Rect rect = box.toRect().inflate(8.0);
      targetRect = targetRect == null ? rect : targetRect.expandToInclude(rect);
    }
    current.delegate.showOnScreen(
      rect: targetRect,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  void didAddText(TextDelegate delegate) {
    _delegates.add(delegate);
    _rebuildMatches();
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _rebuildMatches();
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    delegate.markNeedsPaint();
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.backgroundPainter = null;
    delegate.foregroundPainter = null;
    _delegates.remove(delegate);
    _rebuildMatches();
  }

  void _rebuildMatches() {
    _matches.clear();
    if (_query.isNotEmpty) {
      final String needle = _caseSensitive ? _query : _query.toLowerCase();
      for (final TextDelegate delegate in _delegates) {
        final String rawText = delegate.text;
        final String haystack = _caseSensitive ? rawText : rawText.toLowerCase();
        var start = 0;
        while (start <= haystack.length - needle.length) {
          final int index = haystack.indexOf(needle, start);
          if (index == -1) {
            break;
          }
          _matches.add(
            SearchMatch(
              delegate: delegate,
              range: TextRange(start: index, end: index + needle.length),
            ),
          );
          start = index + needle.length;
        }
      }
    }

    if (_matches.isEmpty) {
      _activeMatchIndex = -1;
    } else if (_activeMatchIndex < 0 || _activeMatchIndex >= _matches.length) {
      _activeMatchIndex = 0;
    }

    _updatePainters();
    _notifyListenersSafely();
  }

  void _updatePainters() {
    final SearchMatch? currentActive = activeMatch;
    for (final TextDelegate delegate in _delegates) {
      final List<SearchMatch> delegateMatches = _matches
          .where((SearchMatch m) => m.delegate == delegate)
          .toList(growable: false);
      if (delegateMatches.isEmpty) {
        delegate.backgroundPainter = null;
        delegate.foregroundPainter = null;
      } else {
        final SearchMatch? activeInDelegate = currentActive?.delegate == delegate
            ? currentActive
            : null;
        delegate.backgroundPainter = _SearchBackgroundPainter(
          delegate: delegate,
          matches: delegateMatches,
          activeMatch: activeInDelegate,
          matchColor: matchHighlightColor,
          activeMatchColor: activeMatchBackgroundColor,
        );
        delegate.foregroundPainter = activeInDelegate != null
            ? _SearchForegroundPainter(
                delegate: delegate,
                activeMatch: activeInDelegate,
                borderColor: activeMatchBorderColor,
              )
            : null;
      }
    }
  }
}

class _SearchBackgroundPainter extends CustomPainter {
  _SearchBackgroundPainter({
    required this.delegate,
    required this.matches,
    required this.activeMatch,
    required this.matchColor,
    required this.activeMatchColor,
  });

  final TextDelegate delegate;
  final List<SearchMatch> matches;
  final SearchMatch? activeMatch;
  final Color matchColor;
  final Color activeMatchColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final matchPaint = Paint()
      ..color = matchColor
      ..style = PaintingStyle.fill;
    final activePaint = Paint()
      ..color = activeMatchColor
      ..style = PaintingStyle.fill;

    for (final SearchMatch match in matches) {
      final isActive = match == activeMatch;
      final List<ui.TextBox> boxes = match.getBoxes();
      for (final box in boxes) {
        final rrect = RRect.fromRectAndRadius(
          box.toRect().inflate(1.5),
          const Radius.circular(3.0),
        );
        canvas.drawRRect(rrect, isActive ? activePaint : matchPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SearchBackgroundPainter oldDelegate) {
    return oldDelegate.matches != matches ||
        oldDelegate.activeMatch != activeMatch ||
        oldDelegate.matchColor != matchColor ||
        oldDelegate.activeMatchColor != activeMatchColor;
  }
}

class _SearchForegroundPainter extends CustomPainter {
  _SearchForegroundPainter({
    required this.delegate,
    required this.activeMatch,
    required this.borderColor,
  });

  final TextDelegate delegate;
  final SearchMatch activeMatch;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75;

    for (final ui.TextBox box in activeMatch.getBoxes()) {
      final rrect = RRect.fromRectAndRadius(box.toRect().inflate(2.0), const Radius.circular(3.5));
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SearchForegroundPainter oldDelegate) {
    return oldDelegate.activeMatch != activeMatch || oldDelegate.borderColor != borderColor;
  }
}
