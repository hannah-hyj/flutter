// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
/// highlighting across all [Text] and [EditableText] widgets in a
/// [TextPluginScope].
///
/// This is the inline-span version. A match is a [TextSpanDecoration] with a
/// background color. The plugin does not paint.
///
/// The plugin has no user interface and does not depend on a design system.
/// It is a [ChangeNotifier]: a search bar sets [query] and [caseSensitive],
/// calls [nextMatch] and [previousMatch], and listens to show [matches] and
/// [activeMatchIndex].
class SearchInPagePlugin extends TextPlugin with ChangeNotifier {
  /// Creates a [SearchInPagePlugin].
  SearchInPagePlugin({
    this.matchHighlightColor = const Color(0x66FFEB3B),
    this.activeMatchBackgroundColor = const Color(0x99FF9800),
    this.activeMatchBorderColor = const Color(0xFFE65100),
    this._eagerLoadOffscreenText = false,
    this.notifyToRedecorate = false,
    this.decorationsPerFrame,
  });

  /// Background highlight color for all matches.
  final Color matchHighlightColor;

  /// Background highlight color for the currently active match.
  final Color activeMatchBackgroundColor;

  /// Color of the lines above and below the active match.
  ///
  /// A span cannot have a border. An overline and an underline are the
  /// closest that a [TextStyle] can do.
  final Color activeMatchBorderColor;

  /// Experiment only. If true, the plugin does not say which texts changed:
  /// it notifies, and every text in the scope asks for its decorations again
  /// ([TextPlugin.notifiesDecorationChanges]). If false, it calls
  /// [TextDelegate.markNeedsDecoration] on the texts whose matches changed.
  final bool notifyToRedecorate;

  @override
  bool get notifiesDecorationChanges => notifyToRedecorate;

  /// Experiment only. If not null, at most this many texts get new
  /// decorations in one frame. The others wait for the next frames, so a
  /// query that changes hundreds of texts shows its highlights over several
  /// short frames instead of in one long frame.
  final int? decorationsPerFrame;

  final Set<TextDelegate> _pending = <TextDelegate>{};
  bool _pendingScheduled = false;

  void _flushPending(Duration timeStamp) {
    _pendingScheduled = false;
    var count = 0;
    while (_pending.isNotEmpty && count < decorationsPerFrame!) {
      final TextDelegate delegate = _pending.first;
      _pending.remove(delegate);
      if (_delegates.contains(delegate)) {
        delegate.markNeedsDecoration();
        count += 1;
      }
    }
    if (_pending.isNotEmpty && !_pendingScheduled) {
      _pendingScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(_flushPending);
    }
  }

  final Set<TextDelegate> _delegates = <TextDelegate>{};
  final Map<TextDelegate, List<SearchMatch>> _matchesByDelegate =
      <TextDelegate, List<SearchMatch>>{};

  // The matches in document order. The order is not known while texts are
  // being built, so this list is made when it is asked for, or at the end of
  // the frame.
  List<SearchMatch> _matches = <SearchMatch>[];
  bool _orderDirty = false;

  String _query = '';
  bool _caseSensitive = false;
  bool _eagerLoadOffscreenText;
  SearchMatch? _activeMatch;
  bool _hasExplicitActiveMatch = false;
  bool _reconcileScheduled = false;
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
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    TextPlugin.deferToEndOfFrame(() {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  void _redecorate(TextDelegate delegate) {
    if (notifyToRedecorate || !_delegates.contains(delegate)) {
      return;
    }
    if (decorationsPerFrame == null) {
      delegate.markNeedsDecoration();
      return;
    }
    _pending.add(delegate);
    if (!_pendingScheduled) {
      _pendingScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(_flushPending);
    }
  }

  /// The current search query string.
  String get query => _query;
  set query(String value) {
    if (_query == value) {
      return;
    }
    _query = value;
    _activeMatch = null;
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

  void _ensureOrdered() {
    if (!_orderDirty) {
      return;
    }
    _orderDirty = false;
    final List<TextDelegate> ordered = _matchesByDelegate.keys.toList();
    TextDelegate.sortInDocumentOrder(ordered);
    _matches = <SearchMatch>[
      for (final TextDelegate delegate in ordered)
        ..._matchesByDelegate[delegate]!,
    ];
  }

  /// All current matches across the scoped subtree, in document order.
  ///
  /// The order is only right once the current frame has been laid out.
  List<SearchMatch> get matches {
    _ensureOrdered();
    return List<SearchMatch>.unmodifiable(_matches);
  }

  /// The number of matches. Unlike [matches], this does not need the order.
  int get matchCount {
    var count = 0;
    for (final List<SearchMatch> list in _matchesByDelegate.values) {
      count += list.length;
    }
    return count;
  }

  /// The index of the currently focused match in [matches], or `-1` if there
  /// are no matches.
  int get activeMatchIndex {
    final SearchMatch? active = _activeMatch;
    if (active == null) {
      return -1;
    }
    _ensureOrdered();
    return _matches.indexOf(active);
  }

  /// The currently focused [SearchMatch], or `null` if there are no matches.
  SearchMatch? get activeMatch => _activeMatch;

  /// Advances focus to the next match and scrolls it into view.
  void nextMatch() {
    _ensureOrdered();
    if (_matches.isEmpty) {
      return;
    }
    _setActiveMatch(
      _matches[(activeMatchIndex + 1) % _matches.length],
      explicit: true,
    );
    scrollToActiveMatch();
    _notify();
  }

  /// Moves focus to the previous match and scrolls it into view.
  void previousMatch() {
    _ensureOrdered();
    if (_matches.isEmpty) {
      return;
    }
    _setActiveMatch(
      _matches[(activeMatchIndex - 1 + _matches.length) % _matches.length],
      explicit: true,
    );
    scrollToActiveMatch();
    _notify();
  }

  void _setActiveMatch(SearchMatch? match, {bool explicit = false}) {
    final SearchMatch? previous = _activeMatch;
    if (explicit) {
      _hasExplicitActiveMatch = true;
    }
    if (previous == match) {
      return;
    }
    _activeMatch = match;
    if (previous != null) {
      _redecorate(previous.delegate);
    }
    if (match != null && match.delegate != previous?.delegate) {
      _redecorate(match.delegate);
    }
  }

  /// Scrolls any enclosing viewport so that [activeMatch] is visible on screen.
  void scrollToActiveMatch({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    final SearchMatch? current = activeMatch;
    if (current == null) {
      return;
    }
    current.delegate.ensureVisible(
      current.range,
      duration: duration,
      curve: curve,
    );
  }

  // The lifecycle callbacks run while the text is being built. They only
  // record the matches. The decorations of this text are asked for right
  // after, so there is nothing to invalidate. What needs the document order
  // (which match is the first one) waits for the end of the frame.

  @override
  void didAddText(TextDelegate delegate) {
    _delegates.add(delegate);
    _setMatches(delegate, _computeMatchesForDelegate(delegate));
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _setMatches(delegate, _computeMatchesForDelegate(delegate));
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    _delegates.remove(delegate);
    _pending.remove(delegate);
    if (_delegates.isEmpty) {
      _hasExplicitActiveMatch = false;
    }
    _setMatches(delegate, const <SearchMatch>[]);
  }

  void _setMatches(TextDelegate delegate, List<SearchMatch> newMatches) {
    final List<SearchMatch> oldMatches =
        _matchesByDelegate[delegate] ?? const <SearchMatch>[];
    if (oldMatches.isEmpty && newMatches.isEmpty) {
      return;
    }
    if (listEquals(oldMatches, newMatches)) {
      return;
    }
    if (newMatches.isEmpty) {
      _matchesByDelegate.remove(delegate);
    } else {
      _matchesByDelegate[delegate] = newMatches;
    }
    _orderDirty = true;
    if (_activeMatch?.delegate == delegate &&
        !newMatches.contains(_activeMatch)) {
      _activeMatch = null;
    }
    if (!_reconcileScheduled) {
      _reconcileScheduled = true;
      TextPlugin.deferToEndOfFrame(() {
        _reconcileScheduled = false;
        if (_disposed) {
          return;
        }
        _reconcileActiveMatch();
        notifyListeners();
      });
    }
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
    return delegateMatches.isEmpty ? const <SearchMatch>[] : delegateMatches;
  }

  // Runs when the query changes, which is outside of a frame: the tree of the
  // last frame is complete, so the order is known right away.
  void _rescanAllDelegates() {
    final SearchMatch? explicitPreviousActive = _hasExplicitActiveMatch
        ? _activeMatch
        : null;
    for (final TextDelegate delegate in _delegates) {
      final List<SearchMatch> oldMatches =
          _matchesByDelegate[delegate] ?? const <SearchMatch>[];
      final List<SearchMatch> newMatches = _computeMatchesForDelegate(delegate);
      if (oldMatches.isEmpty && newMatches.isEmpty) {
        continue;
      }
      if (newMatches.isEmpty) {
        _matchesByDelegate.remove(delegate);
      } else {
        _matchesByDelegate[delegate] = newMatches;
      }
      if (!listEquals(oldMatches, newMatches)) {
        _redecorate(delegate);
      }
    }
    _orderDirty = true;
    _activeMatch = explicitPreviousActive;
    _reconcileActiveMatch();
    _notify();
  }

  void _reconcileActiveMatch() {
    _ensureOrdered();
    if (_matches.isEmpty) {
      _hasExplicitActiveMatch = false;
      _setActiveMatch(null);
    } else if (_activeMatch == null || !_matches.contains(_activeMatch)) {
      _setActiveMatch(_matches.first);
    } else if (!_hasExplicitActiveMatch && _activeMatch != _matches.first) {
      _setActiveMatch(_matches.first);
    }
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final List<SearchMatch>? delegateMatches = _matchesByDelegate[delegate];
    if (delegateMatches == null) {
      return const <TextSpanDecoration>[];
    }
    final SearchMatch? active = _activeMatch;
    return <TextSpanDecoration>[
      for (final SearchMatch match in delegateMatches)
        TextSpanDecoration(
          range: match.range,
          style: match == active ? _activeStyle : _matchStyle,
        ),
    ];
  }

  late final TextStyle _matchStyle = TextStyle(
    backgroundColor: matchHighlightColor,
  );
  late final TextStyle _activeStyle = TextStyle(
    backgroundColor: activeMatchBackgroundColor,
    decoration: TextDecoration.combine(<TextDecoration>[
      TextDecoration.underline,
      TextDecoration.overline,
    ]),
    decorationColor: activeMatchBorderColor,
  );
}
