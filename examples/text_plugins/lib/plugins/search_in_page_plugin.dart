// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
      includePlaceholders: false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SearchMatch &&
        other.delegate == delegate &&
        other.range == range;
  }

  @override
  int get hashCode => Object.hash(delegate, range);
}

/// A [TextPlugin] that implements browser-style "Find in Page" search and
/// highlighting across all [Text] and [RichText] widgets in a
/// [TextPluginScope].
///
/// The plugin has no user interface and does not depend on a design system.
/// It is a [ChangeNotifier]: a search bar sets [query] and [caseSensitive],
/// calls [nextMatch] and [previousMatch], and listens to show [matches] and
/// [activeMatchIndex]. The search bar is written by the app, or by a design
/// system library. The highlight colors are constructor parameters.
class SearchInPagePlugin extends TextPlugin with ChangeNotifier {
  /// Creates a [SearchInPagePlugin].
  SearchInPagePlugin({
    this.matchHighlightColor = const Color(0x66FFEB3B),
    this.activeMatchBackgroundColor = const Color(0x99FF9800),
    this.activeMatchBorderColor = const Color(0xFFE65100),
    this._eagerLoadOffscreenText = false,
  });

  /// Background highlight color for all matches.
  final Color matchHighlightColor;

  /// Background highlight color for the currently active match.
  final Color activeMatchBackgroundColor;

  /// Border color painted in the foreground around the active match.
  final Color activeMatchBorderColor;

  final Set<TextDelegate> _delegates = <TextDelegate>{};
  final Map<TextDelegate, List<SearchMatch>> _matchesByDelegate =
      <TextDelegate, List<SearchMatch>>{};
  final List<TextDelegate> _orderedMatchingDelegates = <TextDelegate>[];
  final List<SearchMatch> _matches = <SearchMatch>[];

  String _query = '';
  bool _caseSensitive = false;
  bool _eagerLoadOffscreenText;
  int _activeMatchIndex = -1;
  bool _hasExplicitActiveMatch = false;
  bool _notificationScheduled = false;
  bool _disposed = false;

  @override
  bool get needsOffscreenContent => _eagerLoadOffscreenText;

  /// Whether enclosing scrollable viewports should eagerly render offscreen
  /// sliver items so all text in the scroll view can be searched and scrolled
  /// to.
  bool get eagerLoadOffscreenText => _eagerLoadOffscreenText;
  set eagerLoadOffscreenText(bool value) {
    if (_eagerLoadOffscreenText == value) {
      return;
    }
    _eagerLoadOffscreenText = value;
    _notifyListenersSafely();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyListenersSafely() {
    if (_disposed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
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
    _activeMatchIndex = -1;
    _hasExplicitActiveMatch = false;
    _rescanAllDelegates();
  }

  /// Whether matching is case-sensitive.
  bool get caseSensitive => _caseSensitive;
  set caseSensitive(bool value) {
    if (_caseSensitive == value) {
      return;
    }
    _caseSensitive = value;
    _rescanAllDelegates();
  }

  /// All current matches across the scoped subtree, ordered in logical
  /// document order.
  List<SearchMatch> get matches => List<SearchMatch>.unmodifiable(_matches);

  /// The index of the currently focused match in [matches], or `-1` if there
  /// are no matches.
  int get activeMatchIndex => _activeMatchIndex;

  /// The currently focused [SearchMatch], or `null` if there are no matches.
  SearchMatch? get activeMatch =>
      (_activeMatchIndex >= 0 && _activeMatchIndex < _matches.length)
      ? _matches[_activeMatchIndex]
      : null;

  /// Advances focus to the next match and scrolls it into view.
  void nextMatch() {
    if (_matches.isEmpty) {
      return;
    }
    _setActiveMatchIndex((_activeMatchIndex + 1) % _matches.length);
  }

  /// Moves focus to the previous match and scrolls it into view.
  void previousMatch() {
    if (_matches.isEmpty) {
      return;
    }
    _setActiveMatchIndex(
      (_activeMatchIndex - 1 + _matches.length) % _matches.length,
    );
  }

  void _setActiveMatchIndex(int newIndex) {
    final SearchMatch? previousActive = activeMatch;
    _hasExplicitActiveMatch = true;
    _activeMatchIndex = newIndex;
    final SearchMatch? currentActive = activeMatch;
    if (previousActive != currentActive) {
      if (previousActive != null &&
          _delegates.contains(previousActive.delegate)) {
        _updatePainterForDelegate(previousActive.delegate);
      }
      if (currentActive != null &&
          currentActive.delegate != previousActive?.delegate &&
          _delegates.contains(currentActive.delegate)) {
        _updatePainterForDelegate(currentActive.delegate);
      }
    }
    scrollToActiveMatch();
    _notifyListenersSafely();
  }

  /// Scrolls any enclosing viewport so that [activeMatch] is visible on screen.
  void scrollToActiveMatch({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    final SearchMatch? current = activeMatch;
    if (current == null || !current.delegate.hasLayout) {
      return;
    }
    current.delegate.ensureVisible(
      current.range,
      duration: duration,
      curve: curve,
    );
  }

  @override
  void didAddText(TextDelegate delegate) {
    _delegates.add(delegate);
    _updateDelegateMatches(delegate, _computeMatchesForDelegate(delegate));
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _updateDelegateMatches(delegate, _computeMatchesForDelegate(delegate));
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    if (_matchesByDelegate.containsKey(delegate)) {
      delegate.markNeedsPaint();
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.backgroundPainter = null;
    delegate.foregroundPainter = null;
    _delegates.remove(delegate);
    if (_delegates.isEmpty) {
      _hasExplicitActiveMatch = false;
    }
    _updateDelegateMatches(delegate, const <SearchMatch>[]);
  }

  List<SearchMatch> _computeMatchesForDelegate(TextDelegate delegate) {
    if (_query.isEmpty) {
      return const <SearchMatch>[];
    }
    final String needle = _caseSensitive ? _query : _query.toLowerCase();
    final String rawText = delegate.text;
    final String haystack = _caseSensitive ? rawText : rawText.toLowerCase();
    final delegateMatches = <SearchMatch>[];
    var start = 0;
    while (start <= haystack.length - needle.length) {
      final int index = haystack.indexOf(needle, start);
      if (index == -1) {
        break;
      }
      delegateMatches.add(
        SearchMatch(
          delegate: delegate,
          range: TextRange(start: index, end: index + needle.length),
        ),
      );
      start = index + needle.length;
    }
    return delegateMatches;
  }

  int _findInsertionIndex(TextDelegate target) {
    var low = 0;
    var high = _orderedMatchingDelegates.length;
    while (low < high) {
      final int mid = (low + high) >>> 1;
      if (_orderedMatchingDelegates[mid].compareTo(target) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  int _matchOffsetForDelegateIndex(int delegateIndex) {
    var offset = 0;
    for (var i = 0; i < delegateIndex; i++) {
      offset += _matchesByDelegate[_orderedMatchingDelegates[i]]!.length;
    }
    return offset;
  }

  bool _isDelegateOutOfOrder(int index) {
    final TextDelegate delegate = _orderedMatchingDelegates[index];
    if (index > 0 &&
        _orderedMatchingDelegates[index - 1].compareTo(delegate) > 0) {
      return true;
    }
    if (index + 1 < _orderedMatchingDelegates.length &&
        delegate.compareTo(_orderedMatchingDelegates[index + 1]) > 0) {
      return true;
    }
    return false;
  }

  void _updateDelegateMatches(
    TextDelegate delegate,
    List<SearchMatch> newMatches,
  ) {
    final List<SearchMatch> oldMatches =
        _matchesByDelegate[delegate] ?? const <SearchMatch>[];
    if (oldMatches.isEmpty && newMatches.isEmpty) {
      return;
    }
    if (oldMatches.isNotEmpty && listEquals(oldMatches, newMatches)) {
      final int existingIndex = _orderedMatchingDelegates.indexOf(delegate);
      if (!_isDelegateOutOfOrder(existingIndex)) {
        if (_delegates.contains(delegate)) {
          delegate.markNeedsPaint();
        }
        return;
      }
    }

    final SearchMatch? oldActive = activeMatch;
    final SearchMatch? explicitPreviousActive = _hasExplicitActiveMatch
        ? oldActive
        : null;

    if (oldMatches.isEmpty) {
      final int insertIndex = _findInsertionIndex(delegate);
      final int matchOffset = _matchOffsetForDelegateIndex(insertIndex);
      _orderedMatchingDelegates.insert(insertIndex, delegate);
      _matchesByDelegate[delegate] = newMatches;
      _matches.insertAll(matchOffset, newMatches);
    } else if (newMatches.isEmpty) {
      final int existingIndex = _orderedMatchingDelegates.indexOf(delegate);
      final int matchOffset = _matchOffsetForDelegateIndex(existingIndex);
      _orderedMatchingDelegates.removeAt(existingIndex);
      _matchesByDelegate.remove(delegate);
      _matches.removeRange(matchOffset, matchOffset + oldMatches.length);
    } else {
      final int existingIndex = _orderedMatchingDelegates.indexOf(delegate);
      final bool movedOrder = _isDelegateOutOfOrder(existingIndex);
      _matchesByDelegate[delegate] = newMatches;
      if (!movedOrder) {
        final int matchOffset = _matchOffsetForDelegateIndex(existingIndex);
        _matches.replaceRange(
          matchOffset,
          matchOffset + oldMatches.length,
          newMatches,
        );
      } else {
        _orderedMatchingDelegates.sort();
        _matches
          ..clear()
          ..addAll(
            _orderedMatchingDelegates.expand(
              (TextDelegate d) => _matchesByDelegate[d]!,
            ),
          );
      }
    }

    _reconcileActiveMatch(explicitPreviousActive);
    final SearchMatch? newActive = activeMatch;

    if (_delegates.contains(delegate)) {
      _updatePainterForDelegate(delegate);
    }
    if (oldActive != newActive) {
      if (oldActive != null &&
          oldActive.delegate != delegate &&
          _delegates.contains(oldActive.delegate)) {
        _updatePainterForDelegate(oldActive.delegate);
      }
      if (newActive != null &&
          newActive.delegate != delegate &&
          _delegates.contains(newActive.delegate)) {
        _updatePainterForDelegate(newActive.delegate);
      }
    }

    _notifyListenersSafely();
  }

  void _rescanAllDelegates() {
    final SearchMatch? explicitPreviousActive = _hasExplicitActiveMatch
        ? activeMatch
        : null;
    final previousMatchingDelegates = Set<TextDelegate>.of(
      _orderedMatchingDelegates,
    );

    _matchesByDelegate.clear();
    _orderedMatchingDelegates.clear();
    _matches.clear();

    if (_query.isNotEmpty) {
      for (final TextDelegate delegate in _delegates) {
        final List<SearchMatch> delegateMatches = _computeMatchesForDelegate(
          delegate,
        );
        if (delegateMatches.isNotEmpty) {
          _matchesByDelegate[delegate] = delegateMatches;
          _orderedMatchingDelegates.add(delegate);
        }
      }
      _orderedMatchingDelegates.sort();
      for (final TextDelegate delegate in _orderedMatchingDelegates) {
        _matches.addAll(_matchesByDelegate[delegate]!);
      }
    }

    _reconcileActiveMatch(explicitPreviousActive);

    for (final TextDelegate delegate in previousMatchingDelegates) {
      if (!_matchesByDelegate.containsKey(delegate) &&
          _delegates.contains(delegate)) {
        delegate.backgroundPainter = null;
        delegate.foregroundPainter = null;
      }
    }
    for (final TextDelegate delegate in _orderedMatchingDelegates) {
      _updatePainterForDelegate(delegate);
    }

    _notifyListenersSafely();
  }

  void _reconcileActiveMatch(SearchMatch? explicitPreviousActive) {
    if (_matches.isEmpty) {
      _activeMatchIndex = -1;
      _hasExplicitActiveMatch = false;
    } else if (explicitPreviousActive != null) {
      final int preservedIndex = _matches.indexOf(explicitPreviousActive);
      if (preservedIndex != -1) {
        _activeMatchIndex = preservedIndex;
      } else if (_activeMatchIndex < 0 ||
          _activeMatchIndex >= _matches.length) {
        _activeMatchIndex = 0;
      }
    } else {
      _activeMatchIndex = 0;
    }
  }

  void _updatePainterForDelegate(TextDelegate delegate) {
    final List<SearchMatch>? delegateMatches = _matchesByDelegate[delegate];
    if (delegateMatches == null || delegateMatches.isEmpty) {
      delegate.backgroundPainter = null;
      delegate.foregroundPainter = null;
      return;
    }
    final SearchMatch? currentActive = activeMatch;
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
    return !listEquals(oldDelegate.matches, matches) ||
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
      final rrect = RRect.fromRectAndRadius(
        box.toRect().inflate(2.0),
        const Radius.circular(3.5),
      );
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SearchForegroundPainter oldDelegate) {
    return oldDelegate.activeMatch != activeMatch ||
        oldDelegate.borderColor != borderColor;
  }
}
