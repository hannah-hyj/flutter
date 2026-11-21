// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'text_painter.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'inline_span.dart';
import 'placeholder_span.dart';
import 'text_span.dart';
import 'text_style.dart';

/// What should be done to one range of a text.
///
/// A list of decorations is applied to an [InlineSpan] tree with
/// [decorateTextSpan]. The [range] is in the plain text of the undecorated
/// tree (`toPlainText(includeSemanticsLabels: false)`), in which a
/// [PlaceholderSpan] is one code unit.
///
/// This is part of the inline-span prototype of text plugins.
@immutable
class TextSpanDecoration {
  /// Creates a decoration for [range].
  const TextSpanDecoration({
    required this.range,
    this.style,
    this.recognizer,
    this.mouseCursor,
    this.onEnter,
    this.onExit,
    this.semanticsLabel,
    this.replacement,
  });

  /// The range of the undecorated plain text that this decoration applies to.
  ///
  /// A collapsed range is only meaningful together with a [replacement],
  /// which is then inserted at that offset without removing any text.
  final TextRange range;

  /// A style that is merged onto the style of the text in [range].
  final TextStyle? style;

  /// A recognizer for the text in [range].
  ///
  /// It replaces the recognizer that the span had. The caller owns the
  /// recognizer and has to keep the same instance for as long as the
  /// decoration is wanted.
  final GestureRecognizer? recognizer;

  /// The mouse cursor over the text in [range].
  final MouseCursor? mouseCursor;

  /// Called when a mouse pointer enters the text in [range].
  ///
  /// When the range is split into several spans, each of them reports its own
  /// enter and exit.
  final PointerEnterEventListener? onEnter;

  /// Called when a mouse pointer leaves the text in [range].
  final PointerExitEventListener? onExit;

  /// What is spoken instead of the text in [range].
  final String? semanticsLabel;

  /// A placeholder that takes the place of the text in [range].
  ///
  /// The plain text of the decorated tree is then different from the plain
  /// text of the original: the whole range becomes one placeholder code unit.
  final PlaceholderSpan? replacement;

  bool get _affectsText =>
      style != null ||
      recognizer != null ||
      mouseCursor != null ||
      onEnter != null ||
      onExit != null ||
      semanticsLabel != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TextSpanDecoration &&
        other.range == range &&
        other.style == style &&
        other.recognizer == recognizer &&
        other.mouseCursor == mouseCursor &&
        other.onEnter == onEnter &&
        other.onExit == onExit &&
        other.semanticsLabel == semanticsLabel &&
        other.replacement == replacement;
  }

  @override
  int get hashCode => Object.hash(
    range,
    style,
    recognizer,
    mouseCursor,
    onEnter,
    onExit,
    semanticsLabel,
    replacement,
  );

  @override
  String toString() =>
      '${objectRuntimeType(this, 'TextSpanDecoration')}($range'
      '${style != null ? ', style' : ''}'
      '${recognizer != null ? ', recognizer' : ''}'
      '${replacement != null ? ', replacement' : ''})';
}

/// The result of [decorateTextSpan].
@immutable
class DecoratedTextSpan {
  const DecoratedTextSpan._(this.span, this._edits);

  /// The decorated tree. It is the original tree, by identity, if no
  /// decoration touched it.
  final InlineSpan span;

  // Sorted by offset. An edit with start == end is an insertion.
  final List<TextRange> _edits;

  /// Whether the plain text of [span] differs from the plain text of the
  /// original, which is the case when a [TextSpanDecoration.replacement] was
  /// applied.
  bool get changesText => _edits.isNotEmpty;

  /// Converts an offset in the original plain text to the offset of the same
  /// character in the plain text of [span].
  ///
  /// An offset inside a replaced range maps to the offset of the placeholder.
  int toDecoratedOffset(int offset) {
    var shift = 0;
    for (final TextRange edit in _edits) {
      if (edit.isCollapsed) {
        if (edit.start > offset) {
          break;
        }
        shift += 1;
      } else {
        if (edit.start > offset) {
          break;
        }
        if (offset < edit.end) {
          return edit.start + shift;
        }
        shift += 1 - (edit.end - edit.start);
      }
    }
    return offset + shift;
  }

  /// Converts an offset in the plain text of [span] to an offset in the
  /// original plain text.
  ///
  /// The offset of a placeholder that replaced a range maps to the start of
  /// that range. The offset of an inserted placeholder maps to the offset at
  /// which it was inserted.
  int toOriginalOffset(int offset) {
    var shift = 0;
    for (final TextRange edit in _edits) {
      final int decoratedStart = edit.start + shift;
      if (decoratedStart > offset) {
        break;
      }
      if (edit.isCollapsed) {
        if (decoratedStart == offset) {
          return edit.start;
        }
        shift += 1;
      } else {
        if (decoratedStart == offset) {
          return edit.start;
        }
        shift += 1 - (edit.end - edit.start);
      }
    }
    return offset - shift;
  }
}

/// Applies [decorations] to [span] and returns the decorated tree.
///
/// The decorations are applied in one pass. Each [TextSpanDecoration.range]
/// is in the plain text of [span], whatever the other decorations do. Where
/// decorations overlap, a later one in the list wins: its style is merged on
/// top, and its recognizer, cursor, hover callbacks and label are used.
///
/// The structure of the tree is kept. A [TextSpan] whose text is touched by a
/// decoration is turned into a span without text that has one child for each
/// piece of the text, followed by the original children. Styles are therefore
/// inherited exactly as before.
///
/// A [TextSpan.recognizer], [TextSpan.mouseCursor], [TextSpan.onEnter] and
/// [TextSpan.onExit] are not inherited by children, so they are copied to each
/// piece. A span with a [TextSpan.semanticsLabel] or a
/// [TextSpan.semanticsIdentifier] is never split, because neither can be
/// copied: a decoration that covers part of such a span is applied to all of
/// it. A [PlaceholderSpan] is never changed by a style.
///
/// Returns [span] itself, by identity, if no decoration touches it.
DecoratedTextSpan decorateTextSpan(InlineSpan span, List<TextSpanDecoration> decorations) {
  if (decorations.isEmpty) {
    return DecoratedTextSpan._(span, const <TextRange>[]);
  }
  final decorator = _Decorator(decorations);
  if (decorator.isEmpty) {
    return DecoratedTextSpan._(span, const <TextRange>[]);
  }
  return decorator.run(span);
}

class _Decorator {
  _Decorator(List<TextSpanDecoration> decorations) {
    // Replacements: a later decoration wins over an earlier one it overlaps.
    for (int i = decorations.length - 1; i >= 0; i -= 1) {
      final TextSpanDecoration decoration = decorations[i];
      final TextRange range = decoration.range;
      if (!range.isValid || !range.isNormalized) {
        continue;
      }
      if (decoration.replacement != null && !range.isCollapsed) {
        if (!_replacements.any(
          (TextSpanDecoration other) =>
              other.range.start < range.end && other.range.end > range.start,
        )) {
          _replacements.add(decoration);
        }
      }
    }
    for (final decoration in decorations) {
      final TextRange range = decoration.range;
      if (!range.isValid || !range.isNormalized) {
        continue;
      }
      if (range.isCollapsed) {
        if (decoration.replacement != null &&
            !_replacements.any(
              (TextSpanDecoration other) =>
                  other.range.start < range.start && other.range.end > range.start,
            )) {
          _insertions.add(decoration);
        }
        continue;
      }
      if (decoration._affectsText) {
        _styles.add(decoration);
      }
    }
    _replacements.sort(
      (TextSpanDecoration a, TextSpanDecoration b) => a.range.start.compareTo(b.range.start),
    );
    // mergeSort is stable, so insertions at the same offset keep the order of
    // the list.
    mergeSort<TextSpanDecoration>(
      _insertions,
      compare: (TextSpanDecoration a, TextSpanDecoration b) =>
          a.range.start.compareTo(b.range.start),
    );
    final cuts = <int>{};
    for (final TextSpanDecoration decoration in _styles) {
      cuts.add(decoration.range.start);
      cuts.add(decoration.range.end);
    }
    for (final TextSpanDecoration decoration in _replacements) {
      cuts.add(decoration.range.start);
      cuts.add(decoration.range.end);
    }
    for (final TextSpanDecoration decoration in _insertions) {
      cuts.add(decoration.range.start);
    }
    _cuts = cuts.toList()..sort();
  }

  final List<TextSpanDecoration> _styles = <TextSpanDecoration>[];
  final List<TextSpanDecoration> _replacements = <TextSpanDecoration>[];
  final List<TextSpanDecoration> _insertions = <TextSpanDecoration>[];
  late final List<int> _cuts;

  bool get isEmpty => _styles.isEmpty && _replacements.isEmpty && _insertions.isEmpty;

  int _offset = 0;
  int _nextInsertion = 0;
  final List<TextRange> _edits = <TextRange>[];

  DecoratedTextSpan run(InlineSpan span) {
    final List<InlineSpan> result = _visit(span);
    // Insertions at or after the end of the text.
    final trailing = <InlineSpan>[];
    _emitInsertionsUpTo(_offset, trailing, atEnd: true);
    if (trailing.isEmpty && result.length == 1) {
      return DecoratedTextSpan._(result.first, _sortedEdits());
    }
    return DecoratedTextSpan._(
      TextSpan(children: <InlineSpan>[...result, ...trailing]),
      _sortedEdits(),
    );
  }

  List<TextRange> _sortedEdits() {
    if (_edits.isEmpty) {
      return const <TextRange>[];
    }
    mergeSort<TextRange>(_edits, compare: (TextRange a, TextRange b) => a.start.compareTo(b.start));
    return List<TextRange>.unmodifiable(_edits);
  }

  bool _touches(int start, int end) {
    for (final TextSpanDecoration decoration in _styles) {
      if (decoration.range.start < end && decoration.range.end > start) {
        return true;
      }
    }
    for (final TextSpanDecoration decoration in _replacements) {
      if (decoration.range.start < end && decoration.range.end > start) {
        return true;
      }
    }
    for (final TextSpanDecoration decoration in _insertions) {
      if (decoration.range.start >= start && decoration.range.start < end) {
        return true;
      }
    }
    return false;
  }

  TextSpanDecoration? _replacementCovering(int start, int end) {
    for (final TextSpanDecoration decoration in _replacements) {
      if (decoration.range.start < end && decoration.range.end > start) {
        return decoration;
      }
    }
    return null;
  }

  // Emits the insertions whose offset is at most [offset].
  void _emitInsertionsUpTo(int offset, List<InlineSpan> out, {bool atEnd = false}) {
    while (_nextInsertion < _insertions.length &&
        (atEnd || _insertions[_nextInsertion].range.start <= offset)) {
      final TextSpanDecoration insertion = _insertions[_nextInsertion];
      out.add(insertion.replacement!);
      final int offset = insertion.range.start;
      _edits.add(TextRange.collapsed(atEnd && offset > _offset ? _offset : offset));
      _nextInsertion += 1;
    }
  }

  // Emits the replacements that start in [start, end).
  void _emitReplacementsStartingIn(int start, int end, List<InlineSpan> out) {
    for (final TextSpanDecoration decoration in _replacements) {
      if (decoration.range.start >= start && decoration.range.start < end) {
        out.add(decoration.replacement!);
        _edits.add(decoration.range);
      }
    }
  }

  List<InlineSpan> _visit(InlineSpan span) {
    if (span is! TextSpan) {
      // A placeholder, or an unknown kind of span that is treated like one.
      final int length = span is PlaceholderSpan ? 1 : span.toPlainText().length;
      final int start = _offset;
      final int end = start + length;
      final replaced = _replacementCovering(start, end) != null;
      if (!replaced && _noInsertionIn(start, end)) {
        _offset = end;
        return <InlineSpan>[span];
      }
      final out = <InlineSpan>[];
      _emitInsertionsUpTo(start, out);
      _emitReplacementsStartingIn(start, end, out);
      if (!replaced) {
        out.add(span);
      }
      _offset = end;
      return out;
    }

    List<InlineSpan>? pieces;
    final String? text = span.text;
    if (text != null && text.isNotEmpty) {
      final int start = _offset;
      final int end = start + text.length;
      if (_touches(start, end)) {
        pieces = <InlineSpan>[];
        final bool atomic = span.semanticsLabel != null || span.semanticsIdentifier != null;
        if (atomic) {
          _emitInsertionsUpTo(end - 1, pieces);
          _emitReplacementsStartingIn(start, end, pieces);
          if (_replacementCovering(start, end) == null) {
            pieces.add(_piece(span, text, start, start, end, atomic: true));
          }
        } else {
          var pieceStart = start;
          int cutIndex = _lowerBound(start + 1);
          while (pieceStart < end) {
            var pieceEnd = end;
            if (cutIndex < _cuts.length && _cuts[cutIndex] < end) {
              pieceEnd = _cuts[cutIndex];
              cutIndex += 1;
              // A range of a plugin can end between the two code units of a
              // surrogate pair. A span that ends there would be drawn as two
              // broken characters, so the cut moves to after the pair.
              final int local = pieceEnd - start;
              if (local > 0 &&
                  local < text.length &&
                  (text.codeUnitAt(local) & 0xFC00) == 0xDC00 &&
                  (text.codeUnitAt(local - 1) & 0xFC00) == 0xD800) {
                pieceEnd += 1;
                while (cutIndex < _cuts.length && _cuts[cutIndex] <= pieceEnd) {
                  cutIndex += 1;
                }
              }
            }
            _emitInsertionsUpTo(pieceStart, pieces);
            _emitReplacementsStartingIn(pieceStart, pieceEnd, pieces);
            if (_replacementCovering(pieceStart, pieceEnd) == null) {
              pieces.add(_piece(span, text, start, pieceStart, pieceEnd, atomic: false));
            }
            pieceStart = pieceEnd;
          }
        }
      }
      _offset = end;
    }

    List<InlineSpan>? newChildren;
    final List<InlineSpan>? children = span.children;
    if (children != null) {
      for (var i = 0; i < children.length; i += 1) {
        final InlineSpan child = children[i];
        final List<InlineSpan> result = _visit(child);
        final bool same = result.length == 1 && identical(result.first, child);
        if (newChildren == null && !same) {
          // Not sublist: the list of the app may be a List<TextSpan>, which
          // cannot hold a placeholder.
          newChildren = <InlineSpan>[...children.take(i)];
        }
        newChildren?.addAll(result);
      }
    }

    if (pieces == null && newChildren == null) {
      return <InlineSpan>[span];
    }
    if (pieces == null) {
      return <InlineSpan>[
        TextSpan(
          text: span.text,
          children: newChildren,
          style: span.style,
          recognizer: span.recognizer,
          mouseCursor: span.mouseCursor,
          onEnter: span.onEnter,
          onExit: span.onExit,
          semanticsLabel: span.semanticsLabel,
          semanticsIdentifier: span.semanticsIdentifier,
          locale: span.locale,
          spellOut: span.spellOut,
        ),
      ];
    }
    return <InlineSpan>[
      TextSpan(
        style: span.style,
        locale: span.locale,
        spellOut: span.spellOut,
        children: <InlineSpan>[...pieces, ...?(newChildren ?? children)],
      ),
    ];
  }

  bool _noInsertionIn(int start, int end) {
    for (final TextSpanDecoration decoration in _insertions) {
      if (decoration.range.start >= start && decoration.range.start < end) {
        return false;
      }
    }
    return true;
  }

  // The index of the first cut that is at least [value].
  int _lowerBound(int value) {
    var min = 0;
    int max = _cuts.length;
    while (min < max) {
      final int mid = min + ((max - min) >> 1);
      if (_cuts[mid] < value) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return min;
  }

  TextSpan _piece(
    TextSpan span,
    String text,
    int spanStart,
    int start,
    int end, {
    required bool atomic,
  }) {
    TextStyle? style;
    GestureRecognizer? recognizer;
    MouseCursor? mouseCursor;
    PointerEnterEventListener? onEnter;
    PointerExitEventListener? onExit;
    String? semanticsLabel;
    for (final TextSpanDecoration decoration in _styles) {
      final TextRange range = decoration.range;
      // A piece is never cut by a decoration, so a decoration that overlaps
      // it covers it. An atomic span is the exception: it is one piece that a
      // decoration may only partly cover.
      if (range.start >= end || range.end <= start) {
        continue;
      }
      if (decoration.style != null) {
        style = style?.merge(decoration.style) ?? decoration.style;
      }
      if (decoration.recognizer != null) {
        recognizer = decoration.recognizer;
        // The cursor of a lower decoration belonged to its recognizer.
        mouseCursor = null;
      }
      mouseCursor = decoration.mouseCursor ?? mouseCursor;
      onEnter = decoration.onEnter ?? onEnter;
      onExit = decoration.onExit ?? onExit;
      if (decoration.semanticsLabel != null) {
        // The label is spoken once: on the first piece of the range. The
        // other pieces are silent.
        semanticsLabel = atomic || range.start >= start ? decoration.semanticsLabel : '';
      }
    }
    final ownRecognizer = recognizer != null;
    return TextSpan(
      text: start == spanStart && end == spanStart + text.length
          ? text
          : text.substring(start - spanStart, end - spanStart),
      style: style,
      recognizer: recognizer ?? span.recognizer,
      mouseCursor: mouseCursor ?? (ownRecognizer ? null : span.mouseCursor),
      onEnter: onEnter ?? span.onEnter,
      onExit: onExit ?? span.onExit,
      semanticsLabel: semanticsLabel ?? span.semanticsLabel,
      semanticsIdentifier: span.semanticsIdentifier,
    );
  }
}
