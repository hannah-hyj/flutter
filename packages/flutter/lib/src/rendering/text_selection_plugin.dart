// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/widgets.dart';
library;

import 'dart:math' as math;
import 'dart:ui' as ui show LineMetrics;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'custom_paint.dart';
import 'layer.dart';
import 'object.dart';
import 'paragraph.dart';
import 'selection.dart';
import 'text_plugin.dart';

/// The start and end positions for a text boundary.
typedef _TextBoundaryRecord = ({TextPosition boundaryStart, TextPosition boundaryEnd});

/// Signature for a function that determines the [_TextBoundaryRecord] at the given
/// [TextPosition].
typedef _TextBoundaryAtPosition = _TextBoundaryRecord Function(TextPosition position);

/// Signature for a function that determines the [_TextBoundaryRecord] at the given
/// [TextPosition], for the given [String].
typedef _TextBoundaryAtPositionInText = _TextBoundaryRecord Function(
  TextPosition position,
  String text,
);

/// The [TextPlugin] that makes static text selectable.
///
/// Inside a [SelectableRegion] (which is what a material `SelectionArea`
/// creates) every [Text] is given a [SelectionRegistrar]. This plugin is
/// what turns such a text into [Selectable]s: it creates one per run of text
/// between [PlaceholderSpan]s, registers them with
/// [TextDelegate.selectionRegistrar], answers the [SelectionEvent]s the
/// region dispatches, paints the selection highlight with a
/// [TextDelegate.backgroundPainter], and positions the selection handles
/// with [TextDelegate.anchors].
///
/// The region keeps everything that is not specific to text: the gestures,
/// the handle and toolbar widgets, the clipboard, and the coordination of
/// the selection across widgets.
///
/// Selectable text always has exactly one [TextSelectionPlugin]. By default
/// the text installs `const TextSelectionPlugin()` itself, so
/// [SelectableRegion] works without a [TextPluginScope] and
/// [TextPluginScope.none] does not make text unselectable (use
/// [SelectionContainer.disabled] for that). Text without a
/// [SelectionRegistrar] has none, and neither has editable text, which owns
/// its selection. A [TextPluginScope] can provide a subclass instead of the
/// default, for example to change how the highlight looks:
///
/// ```dart
/// class RoundedSelectionPlugin extends TextSelectionPlugin {
///   const RoundedSelectionPlugin();
///
///   @override
///   void paintSelectionHighlight(Canvas canvas, TextDelegate delegate, TextSelection selection) {
///     final Paint paint = Paint()..color = delegate.selectionColor ?? const Color(0x00000000);
///     for (final TextBox box in delegate.getBoxesForSelection(selection)) {
///       canvas.drawRRect(RRect.fromRectAndRadius(box.toRect(), const Radius.circular(4)), paint);
///     }
///   }
/// }
/// ```
///
/// The [Selectable]s live from [didAddText] to [didRemoveText]. The text is
/// re-added to the plugin whenever its content or its registrar changes.
/// Unlike for other plugins, detaching the render object of the text does not
/// remove the text from the plugin, only disposing it does: a scrolling list
/// detaches and re-attaches the selected items that it keeps alive, and their
/// selection has to survive that.
class TextSelectionPlugin extends TextPlugin {
  /// Creates the plugin that makes static text selectable.
  const TextSelectionPlugin();

  // The state of each text lives outside of the plugin so that the plugin can
  // be const, and so that a fragment can find the fragments of an enclosing
  // paragraph whichever plugin instance created them.
  static final Expando<_TextSelectionState> _states = Expando<_TextSelectionState>(
    'TextSelectionPlugin',
  );

  /// Whether [selectable] is one of the [Selectable]s that a
  /// [TextSelectionPlugin] currently maintains for the text of
  /// [renderObject].
  ///
  /// This backs [RenderParagraph.selectableBelongsToParagraph], which is the
  /// public way to ask.
  @internal
  static bool ownsSelectable(RenderObject renderObject, Selectable selectable) {
    return selectable is _SelectableFragment &&
        !selectable.owner.isDisposed &&
        identical(selectable.delegate.renderObject, renderObject);
  }

  /// Above ordinary plugins (which default to `0`), so that the selection
  /// highlight stays visible on top of their opaque background decorations.
  @override
  int get paintOrder => 100;

  @override
  @mustCallSuper
  void didAddText(TextDelegate delegate) {
    final SelectionRegistrar? registrar = delegate.selectionRegistrar;
    if (registrar == null || delegate.renderObject is! RenderParagraph) {
      return;
    }
    _states[delegate] = _TextSelectionState(this, delegate, registrar);
  }

  @override
  @mustCallSuper
  void didLayoutText(TextDelegate delegate) {
    _states[delegate]?.didChangeLayout();
  }

  @override
  @mustCallSuper
  void didRemoveText(TextDelegate delegate) {
    _states[delegate]?.dispose();
    _states[delegate] = null;
  }

  /// Paints the highlight of [selection], a selected range of
  /// [TextDelegate.text] that contains no [PlaceholderSpan].
  ///
  /// The `canvas` is in the coordinate space of the text widget and the
  /// highlight is painted behind the glyphs. The default implementation fills
  /// the boxes of the selection with [TextDelegate.selectionColor].
  @protected
  void paintSelectionHighlight(Canvas canvas, TextDelegate delegate, TextSelection selection) {
    final Color? selectionColor = delegate.selectionColor;
    if (selectionColor == null) {
      return;
    }
    final selectionPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = selectionColor;
    for (final TextBox textBox in delegate.getBoxesForSelection(
      selection,
      includePlaceholders: true,
    )) {
      canvas.drawRect(textBox.toRect(), selectionPaint);
    }
  }
}

/// Resolves which [TextSelectionPlugin] handles the selection of a text
/// widget that was given `plugins` by its [TextPluginScope]s.
///
/// Selectable text keeps the innermost [TextSelectionPlugin] of `plugins`, or
/// gets the default one if there is none. Text that is not selectable gets
/// none. The other plugins are returned unchanged and in the same order.
@internal
List<TextPlugin> resolveTextSelectionPlugin(List<TextPlugin> plugins, {required bool selectable}) {
  TextPlugin? selectionPlugin;
  for (final plugin in plugins) {
    if (plugin is TextSelectionPlugin) {
      selectionPlugin = plugin;
    }
  }
  if (selectionPlugin == null) {
    return selectable ? <TextPlugin>[...plugins, const TextSelectionPlugin()] : plugins;
  }
  return <TextPlugin>[
    for (final plugin in plugins)
      if (plugin is! TextSelectionPlugin || (selectable && identical(plugin, selectionPlugin)))
        plugin,
  ];
}

/// The selection of one text widget: its [Selectable]s, their highlight, and
/// the anchors of the selection handles.
class _TextSelectionState {
  _TextSelectionState(this.plugin, this.delegate, this.registrar) {
    final String plainText = delegate.text;
    var start = 0;
    while (start < plainText.length) {
      int end = plainText.indexOf(_SelectableFragment._placeholderCharacter, start);
      if (start != end) {
        if (end == -1) {
          end = plainText.length;
        }
        fragments.add(
          _SelectableFragment(
            owner: this,
            range: TextRange(start: start, end: end),
            fullText: plainText,
          ),
        );
        start = end;
      }
      start += 1;
    }
    fragments.forEach(registrar.add);
  }

  /// The selection state of `renderObject`, if a [TextSelectionPlugin] is
  /// currently making its text selectable.
  static _TextSelectionState? maybeOf(RenderObject renderObject) {
    final Object host = renderObject;
    if (host is! TextPluginHost) {
      return null;
    }
    for (final TextDelegate delegate in host.textPluginDelegates) {
      final _TextSelectionState? state = TextSelectionPlugin._states[delegate];
      if (state != null) {
        return state;
      }
    }
    return null;
  }

  final TextSelectionPlugin plugin;
  final TextDelegate delegate;
  final SelectionRegistrar registrar;

  /// One fragment per run of text between two placeholders, in text order.
  final List<_SelectableFragment> fragments = <_SelectableFragment>[];

  late final _TextSelectionHighlightPainter _highlightPainter = _TextSelectionHighlightPainter(
    this,
  );

  bool isDisposed = false;

  void didChangeLayout() {
    for (final _SelectableFragment fragment in fragments) {
      fragment.didChangeParagraphLayout();
    }
  }

  /// Called by a fragment after its selection changed.
  void didChangeSelection() {
    if (isDisposed) {
      return;
    }
    final selections = <TextSelection>[
      for (final _SelectableFragment fragment in fragments)
        if (fragment.selection case final TextSelection selection) selection,
    ];
    delegate.backgroundPainter = selections.isEmpty ? null : _highlightPainter;
    delegate.reportSelections(selections);
    delegate.markNeedsPaint();
  }

  /// Called by a fragment after its handle links or its selection geometry
  /// changed.
  void updateHandleAnchors() {
    if (isDisposed) {
      return;
    }
    delegate.anchors = <TextAnchor>[
      for (final _SelectableFragment fragment in fragments) ...fragment.handleAnchors,
    ];
  }

  void dispose() {
    assert(!isDisposed);
    isDisposed = true;
    fragments.forEach(registrar.remove);
    for (final _SelectableFragment fragment in fragments) {
      fragment.dispose();
    }
    // The host disposes the delegate right after didRemoveText, which
    // uninstalls the anchors and the reported selections.
    delegate.backgroundPainter = null;
  }
}

class _TextSelectionHighlightPainter extends CustomPainter {
  _TextSelectionHighlightPainter(this.state);

  final _TextSelectionState state;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _SelectableFragment fragment in state.fragments) {
      final TextSelection? selection = fragment.selection;
      if (selection != null) {
        state.plugin.paintSelectionHighlight(canvas, state.delegate, selection);
      }
    }
  }

  @override
  bool shouldRepaint(_TextSelectionHighlightPainter oldDelegate) => oldDelegate.state != state;
}

/// A continuous, selectable piece of paragraph.
///
/// Since the selections in [PlaceholderSpan] are handled independently in its
/// subtree, a selection in a paragraph can't continue across a
/// [PlaceholderSpan]. [TextSelectionPlugin] splits the text on
/// [PlaceholderSpan]s and creates one `_SelectableFragment` per run, so that
/// they can be selected separately.
///
/// Everything a fragment needs to know about its own text comes from the
/// [TextDelegate]. It only names [RenderParagraph] to find the paragraphs that
/// enclose this one through [WidgetSpan]s, which selecting by paragraph needs.
class _SelectableFragment
    with Selectable, Diagnosticable, ChangeNotifier
    implements TextLayoutMetrics {
  _SelectableFragment({required this.owner, required this.fullText, required this.range})
    : assert(range.isValid && !range.isCollapsed && range.isNormalized) {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
    _selectionGeometry = _getSelectionGeometry();
  }

  final TextRange range;
  final _TextSelectionState owner;
  final String fullText;

  TextDelegate get delegate => owner.delegate;

  RenderParagraph get paragraph => delegate.renderObject as RenderParagraph;

  TextPosition? _textSelectionStart;
  TextPosition? _textSelectionEnd;

  bool _selectableContainsOriginTextBoundary = false;

  LayerLink? _startHandleLayerLink;
  LayerLink? _endHandleLayerLink;

  @override
  SelectionGeometry get value => _selectionGeometry;
  late SelectionGeometry _selectionGeometry;

  void _updateSelectionGeometry() {
    final SelectionGeometry newValue = _getSelectionGeometry();

    if (_selectionGeometry == newValue) {
      return;
    }
    _selectionGeometry = newValue;
    owner.updateHandleAnchors();
    notifyListeners();
  }

  SelectionGeometry _getSelectionGeometry() {
    if (_textSelectionStart == null || _textSelectionEnd == null) {
      return const SelectionGeometry(status: SelectionStatus.none, hasContent: true);
    }

    final int selectionStart = _textSelectionStart!.offset;
    final int selectionEnd = _textSelectionEnd!.offset;
    final bool isReversed = selectionStart > selectionEnd;
    final Offset startOffsetInParagraphCoordinates = _getOffsetForPosition(_textSelectionStart!);
    final Offset endOffsetInParagraphCoordinates = selectionStart == selectionEnd
        ? startOffsetInParagraphCoordinates
        : _getOffsetForPosition(_textSelectionEnd!);
    final flipHandles = isReversed != (TextDirection.rtl == delegate.textDirection);
    final selection = TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd);
    final selectionRects = <Rect>[];
    for (final TextBox textBox in delegate.getBoxesForSelection(
      selection,
      includePlaceholders: true,
    )) {
      selectionRects.add(textBox.toRect());
    }
    final selectionCollapsed = selectionStart == selectionEnd;
    final (
      TextSelectionHandleType startSelectionHandleType,
      TextSelectionHandleType endSelectionHandleType,
    ) = switch ((selectionCollapsed, flipHandles)) {
      // Always prefer collapsed handle when selection is collapsed.
      (true, _) => (TextSelectionHandleType.collapsed, TextSelectionHandleType.collapsed),
      (false, true) => (TextSelectionHandleType.right, TextSelectionHandleType.left),
      (false, false) => (TextSelectionHandleType.left, TextSelectionHandleType.right),
    };
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: startOffsetInParagraphCoordinates,
        lineHeight: delegate.preferredLineHeight,
        handleType: startSelectionHandleType,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: endOffsetInParagraphCoordinates,
        lineHeight: delegate.preferredLineHeight,
        handleType: endSelectionHandleType,
      ),
      selectionRects: selectionRects,
      status: selectionCollapsed ? SelectionStatus.collapsed : SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    late final SelectionResult result;
    final TextPosition? existingSelectionStart = _textSelectionStart;
    final TextPosition? existingSelectionEnd = _textSelectionEnd;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final edgeUpdate = event as SelectionEdgeUpdateEvent;
        final TextGranularity granularity = event.granularity;

        switch (granularity) {
          case TextGranularity.character:
            result = _updateSelectionEdge(
              edgeUpdate.globalPosition,
              isEnd: edgeUpdate.type == SelectionEventType.endEdgeUpdate,
            );
          case TextGranularity.word:
            result = _updateSelectionEdgeByTextBoundary(
              edgeUpdate.globalPosition,
              isEnd: edgeUpdate.type == SelectionEventType.endEdgeUpdate,
              getTextBoundary: _getWordBoundaryAtPosition,
            );
          case TextGranularity.paragraph:
            result = _updateSelectionEdgeByMultiSelectableTextBoundary(
              edgeUpdate.globalPosition,
              isEnd: edgeUpdate.type == SelectionEventType.endEdgeUpdate,
              getTextBoundary: _getParagraphBoundaryAtPosition,
              getClampedTextBoundary: _getClampedParagraphBoundaryAtPosition,
            );
          case TextGranularity.document:
          case TextGranularity.line:
            assert(false, 'Moving the selection edge by line or document is not supported.');
        }
      case SelectionEventType.clear:
        result = _handleClearSelection();
      case SelectionEventType.selectAll:
        result = _handleSelectAll();
      case SelectionEventType.selectWord:
        final selectWord = event as SelectWordSelectionEvent;
        result = _handleSelectWord(selectWord.globalPosition);
      case SelectionEventType.selectParagraph:
        final selectParagraph = event as SelectParagraphSelectionEvent;
        if (selectParagraph.absorb) {
          _handleSelectAll();
          result = SelectionResult.next;
          _selectableContainsOriginTextBoundary = true;
        } else {
          result = _handleSelectParagraph(selectParagraph.globalPosition);
        }
      case SelectionEventType.granularlyExtendSelection:
        final granularlyExtendSelection = event as GranularlyExtendSelectionEvent;
        result = _handleGranularlyExtendSelection(
          granularlyExtendSelection.forward,
          granularlyExtendSelection.isEnd,
          granularlyExtendSelection.granularity,
        );
      case SelectionEventType.directionallyExtendSelection:
        final directionallyExtendSelection = event as DirectionallyExtendSelectionEvent;
        result = _handleDirectionallyExtendSelection(
          directionallyExtendSelection.dx,
          directionallyExtendSelection.isEnd,
          directionallyExtendSelection.direction,
        );
    }

    if (existingSelectionStart != _textSelectionStart ||
        existingSelectionEnd != _textSelectionEnd) {
      _didChangeSelection();
    }
    return result;
  }

  @override
  SelectedContent? getSelectedContent() {
    if (_textSelectionStart == null || _textSelectionEnd == null) {
      return null;
    }
    final int start = math.min(_textSelectionStart!.offset, _textSelectionEnd!.offset);
    final int end = math.max(_textSelectionStart!.offset, _textSelectionEnd!.offset);
    return SelectedContent(plainText: fullText.substring(start, end));
  }

  @override
  SelectedContentRange? getSelection() {
    if (_textSelectionStart == null || _textSelectionEnd == null) {
      return null;
    }
    return SelectedContentRange(
      startOffset: _textSelectionStart!.offset,
      endOffset: _textSelectionEnd!.offset,
    );
  }

  void _didChangeSelection() {
    owner.didChangeSelection();
    _updateSelectionGeometry();
  }

  TextPosition _updateSelectionStartEdgeByTextBoundary(
    _TextBoundaryRecord? textBoundary,
    _TextBoundaryAtPosition getTextBoundary,
    TextPosition position,
    TextPosition? existingSelectionStart,
    TextPosition? existingSelectionEnd,
  ) {
    TextPosition? targetPosition;
    if (textBoundary != null) {
      assert(
        textBoundary.boundaryStart.offset >= range.start &&
            textBoundary.boundaryEnd.offset <= range.end,
      );
      if (_selectableContainsOriginTextBoundary &&
          existingSelectionStart != null &&
          existingSelectionEnd != null) {
        final isSamePosition = position.offset == existingSelectionEnd.offset;
        final bool isSelectionInverted =
            existingSelectionStart.offset > existingSelectionEnd.offset;
        final bool shouldSwapEdges =
            !isSamePosition &&
            (isSelectionInverted != (position.offset > existingSelectionEnd.offset));
        if (shouldSwapEdges) {
          if (position.offset < existingSelectionEnd.offset) {
            targetPosition = textBoundary.boundaryStart;
          } else {
            targetPosition = textBoundary.boundaryEnd;
          }
          // When the selection is inverted by the new position it is necessary to
          // swap the start edge (moving edge) with the end edge (static edge) to
          // maintain the origin text boundary within the selection.
          final _TextBoundaryRecord localTextBoundary = getTextBoundary(existingSelectionEnd);
          assert(
            localTextBoundary.boundaryStart.offset >= range.start &&
                localTextBoundary.boundaryEnd.offset <= range.end,
          );
          _setSelectionPosition(
            existingSelectionEnd.offset == localTextBoundary.boundaryStart.offset
                ? localTextBoundary.boundaryEnd
                : localTextBoundary.boundaryStart,
            isEnd: true,
          );
        } else {
          if (position.offset < existingSelectionEnd.offset) {
            targetPosition = textBoundary.boundaryStart;
          } else if (position.offset > existingSelectionEnd.offset) {
            targetPosition = textBoundary.boundaryEnd;
          } else {
            // Keep the origin text boundary in bounds when position is at the static edge.
            targetPosition = existingSelectionStart;
          }
        }
      } else {
        if (existingSelectionEnd != null) {
          // If the end edge exists and the start edge is being moved, then the
          // start edge is moved to encompass the entire text boundary at the new position.
          if (position.offset < existingSelectionEnd.offset) {
            targetPosition = textBoundary.boundaryStart;
          } else {
            targetPosition = textBoundary.boundaryEnd;
          }
        } else {
          // Move the start edge to the closest text boundary.
          targetPosition = _closestTextBoundary(textBoundary, position);
        }
      }
    } else {
      // The position is not contained within the current rect. The targetPosition
      // will either be at the end or beginning of the current rect. See [SelectionUtils.adjustDragOffset]
      // for a more in depth explanation on this adjustment.
      if (_selectableContainsOriginTextBoundary &&
          existingSelectionStart != null &&
          existingSelectionEnd != null) {
        // When the selection is inverted by the new position it is necessary to
        // swap the start edge (moving edge) with the end edge (static edge) to
        // maintain the origin text boundary within the selection.
        final isSamePosition = position.offset == existingSelectionEnd.offset;
        final bool isSelectionInverted =
            existingSelectionStart.offset > existingSelectionEnd.offset;
        final bool shouldSwapEdges =
            !isSamePosition &&
            (isSelectionInverted != (position.offset > existingSelectionEnd.offset));

        if (shouldSwapEdges) {
          final _TextBoundaryRecord localTextBoundary = getTextBoundary(existingSelectionEnd);
          assert(
            localTextBoundary.boundaryStart.offset >= range.start &&
                localTextBoundary.boundaryEnd.offset <= range.end,
          );
          _setSelectionPosition(
            isSelectionInverted ? localTextBoundary.boundaryEnd : localTextBoundary.boundaryStart,
            isEnd: true,
          );
        }
      }
    }
    return targetPosition ?? position;
  }

  TextPosition _updateSelectionEndEdgeByTextBoundary(
    _TextBoundaryRecord? textBoundary,
    _TextBoundaryAtPosition getTextBoundary,
    TextPosition position,
    TextPosition? existingSelectionStart,
    TextPosition? existingSelectionEnd,
  ) {
    TextPosition? targetPosition;
    if (textBoundary != null) {
      assert(
        textBoundary.boundaryStart.offset >= range.start &&
            textBoundary.boundaryEnd.offset <= range.end,
      );
      if (_selectableContainsOriginTextBoundary &&
          existingSelectionStart != null &&
          existingSelectionEnd != null) {
        final isSamePosition = position.offset == existingSelectionStart.offset;
        final bool isSelectionInverted =
            existingSelectionStart.offset > existingSelectionEnd.offset;
        final bool shouldSwapEdges =
            !isSamePosition &&
            (isSelectionInverted != (position.offset < existingSelectionStart.offset));
        if (shouldSwapEdges) {
          if (position.offset < existingSelectionStart.offset) {
            targetPosition = textBoundary.boundaryStart;
          } else {
            targetPosition = textBoundary.boundaryEnd;
          }
          // When the selection is inverted by the new position it is necessary to
          // swap the end edge (moving edge) with the start edge (static edge) to
          // maintain the origin text boundary within the selection.
          final _TextBoundaryRecord localTextBoundary = getTextBoundary(existingSelectionStart);
          assert(
            localTextBoundary.boundaryStart.offset >= range.start &&
                localTextBoundary.boundaryEnd.offset <= range.end,
          );
          _setSelectionPosition(
            existingSelectionStart.offset == localTextBoundary.boundaryStart.offset
                ? localTextBoundary.boundaryEnd
                : localTextBoundary.boundaryStart,
            isEnd: false,
          );
        } else {
          if (position.offset < existingSelectionStart.offset) {
            targetPosition = textBoundary.boundaryStart;
          } else if (position.offset > existingSelectionStart.offset) {
            targetPosition = textBoundary.boundaryEnd;
          } else {
            // Keep the origin text boundary in bounds when position is at the static edge.
            targetPosition = existingSelectionEnd;
          }
        }
      } else {
        if (existingSelectionStart != null) {
          // If the start edge exists and the end edge is being moved, then the
          // end edge is moved to encompass the entire text boundary at the new position.
          if (position.offset < existingSelectionStart.offset) {
            targetPosition = textBoundary.boundaryStart;
          } else {
            targetPosition = textBoundary.boundaryEnd;
          }
        } else {
          // Move the end edge to the closest text boundary.
          targetPosition = _closestTextBoundary(textBoundary, position);
        }
      }
    } else {
      // The position is not contained within the current rect. The targetPosition
      // will either be at the end or beginning of the current rect. See [SelectionUtils.adjustDragOffset]
      // for a more in depth explanation on this adjustment.
      if (_selectableContainsOriginTextBoundary &&
          existingSelectionStart != null &&
          existingSelectionEnd != null) {
        // When the selection is inverted by the new position it is necessary to
        // swap the end edge (moving edge) with the start edge (static edge) to
        // maintain the origin text boundary within the selection.
        final isSamePosition = position.offset == existingSelectionStart.offset;
        final bool isSelectionInverted =
            existingSelectionStart.offset > existingSelectionEnd.offset;
        final bool shouldSwapEdges =
            isSelectionInverted != (position.offset < existingSelectionStart.offset) ||
            isSamePosition;
        if (shouldSwapEdges) {
          final _TextBoundaryRecord localTextBoundary = getTextBoundary(existingSelectionStart);
          assert(
            localTextBoundary.boundaryStart.offset >= range.start &&
                localTextBoundary.boundaryEnd.offset <= range.end,
          );
          _setSelectionPosition(
            isSelectionInverted ? localTextBoundary.boundaryStart : localTextBoundary.boundaryEnd,
            isEnd: false,
          );
        }
      }
    }
    return targetPosition ?? position;
  }

  SelectionResult _updateSelectionEdgeByTextBoundary(
    Offset globalPosition, {
    required bool isEnd,
    required _TextBoundaryAtPosition getTextBoundary,
  }) {
    // When the start/end edges are swapped, i.e. the start is after the end, and
    // the scrollable synthesizes an event for the opposite edge, this will potentially
    // move the opposite edge outside of the origin text boundary and we are unable to recover.
    final TextPosition? existingSelectionStart = _textSelectionStart;
    final TextPosition? existingSelectionEnd = _textSelectionEnd;

    _setSelectionPosition(null, isEnd: isEnd);
    final Matrix4 transform = delegate.getTransformTo(null);
    transform.invert();
    final Offset localPosition = MatrixUtils.transformPoint(transform, globalPosition);
    if (_rect.isEmpty) {
      final SelectionResult result = SelectionUtils.getResultBasedOnRect(_rect, localPosition);
      _setSelectionPosition(
        result == SelectionResult.next
            ? TextPosition(offset: range.end)
            : TextPosition(offset: range.start, affinity: TextAffinity.upstream),
        isEnd: isEnd,
      );
      return result;
    }
    final Offset adjustedOffset = SelectionUtils.adjustDragOffset(
      _rect,
      localPosition,
      direction: delegate.textDirection,
    );

    final TextPosition position = delegate.getPositionForOffset(adjustedOffset);
    // Check if the original local position is within the rect, if it is not then
    // we do not need to look up the text boundary for that position. This is to
    // maintain a selectables selection collapsed at 0 when the local position is
    // not located inside its rect.
    _TextBoundaryRecord? textBoundary = _rect.contains(localPosition)
        ? getTextBoundary(position)
        : null;
    if (textBoundary != null &&
        (textBoundary.boundaryStart.offset < range.start &&
                textBoundary.boundaryEnd.offset <= range.start ||
            textBoundary.boundaryStart.offset >= range.end &&
                textBoundary.boundaryEnd.offset > range.end)) {
      // When the position is located at a placeholder inside of the text, then we may compute
      // a text boundary that does not belong to the current selectable fragment. In this case
      // we should invalidate the text boundary so that it is not taken into account when
      // computing the target position.
      textBoundary = null;
    }
    final TextPosition targetPosition = _clampTextPosition(
      isEnd
          ? _updateSelectionEndEdgeByTextBoundary(
              textBoundary,
              getTextBoundary,
              position,
              existingSelectionStart,
              existingSelectionEnd,
            )
          : _updateSelectionStartEdgeByTextBoundary(
              textBoundary,
              getTextBoundary,
              position,
              existingSelectionStart,
              existingSelectionEnd,
            ),
    );

    _setSelectionPosition(targetPosition, isEnd: isEnd);
    if (targetPosition.offset == range.end) {
      return SelectionResult.next;
    }

    if (targetPosition.offset == range.start) {
      return SelectionResult.previous;
    }
    // TODO(chunhtai): The geometry information should not be used to determine
    // selection result. This is a workaround to RenderParagraph, where it does
    // not have a way to get accurate text length if its text is truncated due to
    // layout constraint.
    return SelectionUtils.getResultBasedOnRect(_rect, localPosition);
  }

  SelectionResult _updateSelectionEdge(Offset globalPosition, {required bool isEnd}) {
    _setSelectionPosition(null, isEnd: isEnd);
    final Matrix4 transform = delegate.getTransformTo(null);
    transform.invert();
    final Offset localPosition = MatrixUtils.transformPoint(transform, globalPosition);
    if (_rect.isEmpty) {
      final SelectionResult result = SelectionUtils.getResultBasedOnRect(_rect, localPosition);
      _setSelectionPosition(
        result == SelectionResult.next
            ? TextPosition(offset: range.end)
            : TextPosition(offset: range.start, affinity: TextAffinity.upstream),
        isEnd: isEnd,
      );
      return result;
    }
    final Offset adjustedOffset = SelectionUtils.adjustDragOffset(
      _rect,
      localPosition,
      direction: delegate.textDirection,
    );

    final TextPosition position = _clampTextPosition(delegate.getPositionForOffset(adjustedOffset));
    _setSelectionPosition(position, isEnd: isEnd);
    if (position.offset == range.end) {
      return SelectionResult.next;
    }
    if (position.offset == range.start) {
      return SelectionResult.previous;
    }
    // TODO(chunhtai): The geometry information should not be used to determine
    // selection result. This is a workaround to RenderParagraph, where it does
    // not have a way to get accurate text length if its text is truncated due to
    // layout constraint.
    return SelectionUtils.getResultBasedOnRect(_rect, localPosition);
  }

  // This method handles updating the start edge by a text boundary that may
  // not be contained within this selectable fragment. It is possible
  // that a boundary spans multiple selectable fragments when the text contains
  // [WidgetSpan]s.
  //
  // This method differs from [_updateSelectionStartEdgeByTextBoundary] in that
  // to pivot offset used to swap selection edges and maintain the origin
  // text boundary selected may be located outside of this selectable fragment.
  //
  // See [_updateSelectionEndEdgeByMultiSelectableTextBoundary] for the method
  // that handles updating the end edge.
  SelectionResult? _updateSelectionStartEdgeByMultiSelectableTextBoundary(
    _TextBoundaryAtPositionInText getTextBoundary,
    bool paragraphContainsPosition,
    TextPosition position,
    TextPosition? existingSelectionStart,
    TextPosition? existingSelectionEnd,
  ) {
    const isEnd = false;
    if (_selectableContainsOriginTextBoundary &&
        existingSelectionStart != null &&
        existingSelectionEnd != null) {
      // If this selectable contains the origin boundary, maintain the existing
      // selection.
      final bool forwardSelection = existingSelectionEnd.offset >= existingSelectionStart.offset;
      if (paragraphContainsPosition) {
        // When the position is within the root paragraph, swap the start and end
        // edges when the selection is inverted.
        final _TextBoundaryRecord boundaryAtPosition = getTextBoundary(position, fullText);
        // To accurately retrieve the origin text boundary when the selection
        // is forward, use existingSelectionEnd.offset - 1. This is necessary
        // because in a forwards selection, existingSelectionEnd marks the end
        // of the origin text boundary. Using the unmodified offset incorrectly
        // targets the subsequent text boundary.
        final _TextBoundaryRecord originTextBoundary = getTextBoundary(
          forwardSelection
              ? TextPosition(
                  offset: existingSelectionEnd.offset - 1,
                  affinity: existingSelectionEnd.affinity,
                )
              : existingSelectionEnd,
          fullText,
        );
        final TextPosition targetPosition;
        final int pivotOffset = forwardSelection
            ? originTextBoundary.boundaryEnd.offset
            : originTextBoundary.boundaryStart.offset;
        final shouldSwapEdges = !forwardSelection != (position.offset > pivotOffset);
        if (position.offset < pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryStart;
        } else if (position.offset > pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryEnd;
        } else {
          // Keep the origin text boundary in bounds when position is at the static edge.
          targetPosition = forwardSelection ? existingSelectionStart : existingSelectionEnd;
        }
        if (shouldSwapEdges) {
          _setSelectionPosition(
            _clampTextPosition(
              forwardSelection ? originTextBoundary.boundaryStart : originTextBoundary.boundaryEnd,
            ),
            isEnd: true,
          );
        }
        _setSelectionPosition(_clampTextPosition(targetPosition), isEnd: isEnd);
        final bool finalSelectionIsForward =
            _textSelectionEnd!.offset >= _textSelectionStart!.offset;
        if (boundaryAtPosition.boundaryStart.offset > range.end &&
            boundaryAtPosition.boundaryEnd.offset > range.end) {
          return SelectionResult.next;
        }
        if (boundaryAtPosition.boundaryStart.offset < range.start &&
            boundaryAtPosition.boundaryEnd.offset < range.start) {
          return SelectionResult.previous;
        }
        if (finalSelectionIsForward) {
          if (boundaryAtPosition.boundaryStart.offset >= originTextBoundary.boundaryStart.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryStart.offset < originTextBoundary.boundaryStart.offset) {
            return SelectionResult.previous;
          }
        } else {
          if (boundaryAtPosition.boundaryEnd.offset <= originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryEnd.offset > originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.next;
          }
        }
      } else {
        // When the drag position is not contained within the root paragraph,
        // swap the edges when the selection changes direction.
        final TextPosition clampedPosition = _clampTextPosition(position);
        // To accurately retrieve the origin text boundary when the selection
        // is forward, use existingSelectionEnd.offset - 1. This is necessary
        // because in a forwards selection, existingSelectionEnd marks the end
        // of the origin text boundary. Using the unmodified offset incorrectly
        // targets the subsequent text boundary.
        final _TextBoundaryRecord originTextBoundary = getTextBoundary(
          forwardSelection
              ? TextPosition(
                  offset: existingSelectionEnd.offset - 1,
                  affinity: existingSelectionEnd.affinity,
                )
              : existingSelectionEnd,
          fullText,
        );
        if (forwardSelection && clampedPosition.offset == range.start) {
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (!forwardSelection && clampedPosition.offset == range.end) {
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.next;
        }
        if (forwardSelection && clampedPosition.offset == range.end) {
          _setSelectionPosition(_clampTextPosition(originTextBoundary.boundaryStart), isEnd: true);
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.next;
        }
        if (!forwardSelection && clampedPosition.offset == range.start) {
          _setSelectionPosition(_clampTextPosition(originTextBoundary.boundaryEnd), isEnd: true);
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.previous;
        }
      }
    } else {
      // A paragraph boundary may not be completely contained within this root
      // selectable fragment. Keep searching until we find the end of the
      // boundary. Do not search when the current drag position is on a placeholder
      // to allow traversal to reach that placeholder.
      final positionOnPlaceholder =
          delegate.getWordBoundary(position).textInside(fullText) == _placeholderCharacter;
      if (!paragraphContainsPosition || positionOnPlaceholder) {
        return null;
      }
      if (existingSelectionEnd != null) {
        final _TextBoundaryRecord boundaryAtPosition = getTextBoundary(position, fullText);
        final bool backwardSelection =
            existingSelectionStart == null && existingSelectionEnd.offset == range.start ||
            existingSelectionStart == existingSelectionEnd &&
                existingSelectionEnd.offset == range.start ||
            existingSelectionStart != null &&
                existingSelectionStart.offset > existingSelectionEnd.offset;
        if (boundaryAtPosition.boundaryStart.offset < range.start &&
            boundaryAtPosition.boundaryEnd.offset < range.start) {
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (boundaryAtPosition.boundaryStart.offset > range.end &&
            boundaryAtPosition.boundaryEnd.offset > range.end) {
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (backwardSelection) {
          if (boundaryAtPosition.boundaryEnd.offset <= range.end) {
            _setSelectionPosition(_clampTextPosition(boundaryAtPosition.boundaryEnd), isEnd: isEnd);
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryEnd.offset > range.end) {
            _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
            return SelectionResult.next;
          }
        } else {
          _setSelectionPosition(_clampTextPosition(boundaryAtPosition.boundaryStart), isEnd: isEnd);
          if (boundaryAtPosition.boundaryStart.offset < range.start) {
            return SelectionResult.previous;
          }
          if (boundaryAtPosition.boundaryStart.offset >= range.start) {
            return SelectionResult.end;
          }
        }
      }
    }
    return null;
  }

  // This method handles updating the end edge by a text boundary that may
  // not be contained within this selectable fragment. It is possible
  // that a boundary spans multiple selectable fragments when the text contains
  // [WidgetSpan]s.
  //
  // This method differs from [_updateSelectionEndEdgeByTextBoundary] in that
  // to pivot offset used to swap selection edges and maintain the origin
  // text boundary selected may be located outside of this selectable fragment.
  //
  // See [_updateSelectionStartEdgeByMultiSelectableTextBoundary] for the method
  // that handles updating the end edge.
  SelectionResult? _updateSelectionEndEdgeByMultiSelectableTextBoundary(
    _TextBoundaryAtPositionInText getTextBoundary,
    bool paragraphContainsPosition,
    TextPosition position,
    TextPosition? existingSelectionStart,
    TextPosition? existingSelectionEnd,
  ) {
    const isEnd = true;
    if (_selectableContainsOriginTextBoundary &&
        existingSelectionStart != null &&
        existingSelectionEnd != null) {
      // If this selectable contains the origin boundary, maintain the existing
      // selection.
      final bool forwardSelection = existingSelectionEnd.offset >= existingSelectionStart.offset;
      if (paragraphContainsPosition) {
        // When the position is within the root paragraph, swap the start and end
        // edges when the selection is inverted.
        final _TextBoundaryRecord boundaryAtPosition = getTextBoundary(position, fullText);
        // To accurately retrieve the origin text boundary when the selection
        // is backwards, use existingSelectionStart.offset - 1. This is necessary
        // because in a backwards selection, existingSelectionStart marks the end
        // of the origin text boundary. Using the unmodified offset incorrectly
        // targets the subsequent text boundary.
        final _TextBoundaryRecord originTextBoundary = getTextBoundary(
          forwardSelection
              ? existingSelectionStart
              : TextPosition(
                  offset: existingSelectionStart.offset - 1,
                  affinity: existingSelectionStart.affinity,
                ),
          fullText,
        );
        final TextPosition targetPosition;
        final int pivotOffset = forwardSelection
            ? originTextBoundary.boundaryStart.offset
            : originTextBoundary.boundaryEnd.offset;
        final shouldSwapEdges = !forwardSelection != (position.offset < pivotOffset);
        if (position.offset < pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryStart;
        } else if (position.offset > pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryEnd;
        } else {
          // Keep the origin text boundary in bounds when position is at the static edge.
          targetPosition = forwardSelection ? existingSelectionEnd : existingSelectionStart;
        }
        if (shouldSwapEdges) {
          _setSelectionPosition(
            _clampTextPosition(
              forwardSelection ? originTextBoundary.boundaryEnd : originTextBoundary.boundaryStart,
            ),
            isEnd: false,
          );
        }
        _setSelectionPosition(_clampTextPosition(targetPosition), isEnd: isEnd);
        final bool finalSelectionIsForward =
            _textSelectionEnd!.offset >= _textSelectionStart!.offset;
        if (boundaryAtPosition.boundaryStart.offset > range.end &&
            boundaryAtPosition.boundaryEnd.offset > range.end) {
          return SelectionResult.next;
        }
        if (boundaryAtPosition.boundaryStart.offset < range.start &&
            boundaryAtPosition.boundaryEnd.offset < range.start) {
          return SelectionResult.previous;
        }
        if (finalSelectionIsForward) {
          if (boundaryAtPosition.boundaryEnd.offset <= originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryEnd.offset > originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.next;
          }
        } else {
          if (boundaryAtPosition.boundaryStart.offset >= originTextBoundary.boundaryStart.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryStart.offset < originTextBoundary.boundaryStart.offset) {
            return SelectionResult.previous;
          }
        }
      } else {
        // When the drag position is not contained within the root paragraph,
        // swap the edges when the selection changes direction.
        final TextPosition clampedPosition = _clampTextPosition(position);
        // To accurately retrieve the origin text boundary when the selection
        // is backwards, use existingSelectionStart.offset - 1. This is necessary
        // because in a backwards selection, existingSelectionStart marks the end
        // of the origin text boundary. Using the unmodified offset incorrectly
        // targets the subsequent text boundary.
        final _TextBoundaryRecord originTextBoundary = getTextBoundary(
          forwardSelection
              ? existingSelectionStart
              : TextPosition(
                  offset: existingSelectionStart.offset - 1,
                  affinity: existingSelectionStart.affinity,
                ),
          fullText,
        );
        if (forwardSelection && clampedPosition.offset == range.start) {
          _setSelectionPosition(_clampTextPosition(originTextBoundary.boundaryEnd), isEnd: false);
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (!forwardSelection && clampedPosition.offset == range.end) {
          _setSelectionPosition(_clampTextPosition(originTextBoundary.boundaryStart), isEnd: false);
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.next;
        }
        if (forwardSelection && clampedPosition.offset == range.end) {
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.next;
        }
        if (!forwardSelection && clampedPosition.offset == range.start) {
          _setSelectionPosition(clampedPosition, isEnd: isEnd);
          return SelectionResult.previous;
        }
      }
    } else {
      // A paragraph boundary may not be completely contained within this root
      // selectable fragment. Keep searching until we find the end of the
      // boundary. Do not search when the current drag position is on a placeholder
      // to allow traversal to reach that placeholder.
      final positionOnPlaceholder =
          delegate.getWordBoundary(position).textInside(fullText) == _placeholderCharacter;
      if (!paragraphContainsPosition || positionOnPlaceholder) {
        return null;
      }
      if (existingSelectionStart != null) {
        final _TextBoundaryRecord boundaryAtPosition = getTextBoundary(position, fullText);
        final bool backwardSelection =
            existingSelectionEnd == null && existingSelectionStart.offset == range.end ||
            existingSelectionStart == existingSelectionEnd &&
                existingSelectionStart.offset == range.end ||
            existingSelectionEnd != null &&
                existingSelectionStart.offset > existingSelectionEnd.offset;
        if (boundaryAtPosition.boundaryStart.offset < range.start &&
            boundaryAtPosition.boundaryEnd.offset < range.start) {
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (boundaryAtPosition.boundaryStart.offset > range.end &&
            boundaryAtPosition.boundaryEnd.offset > range.end) {
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (backwardSelection) {
          _setSelectionPosition(_clampTextPosition(boundaryAtPosition.boundaryStart), isEnd: isEnd);
          if (boundaryAtPosition.boundaryStart.offset < range.start) {
            return SelectionResult.previous;
          }
          if (boundaryAtPosition.boundaryStart.offset >= range.start) {
            return SelectionResult.end;
          }
        } else {
          if (boundaryAtPosition.boundaryEnd.offset <= range.end) {
            _setSelectionPosition(_clampTextPosition(boundaryAtPosition.boundaryEnd), isEnd: isEnd);
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryEnd.offset > range.end) {
            _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
            return SelectionResult.next;
          }
        }
      }
    }
    return null;
  }

  // The placeholder character used by [RenderParagraph].
  static final String _placeholderCharacter = String.fromCharCode(
    PlaceholderSpan.placeholderCodeUnit,
  );
  static final int _placeholderLength = _placeholderCharacter.length;

  // This method handles updating the start edge by a text boundary that may
  // not be contained within this selectable fragment. It is possible
  // that a boundary spans multiple selectable fragments when the text contains
  // [WidgetSpan]s.
  //
  // This method differs from [_updateSelectionStartEdgeByMultiSelectableBoundary]
  // in that to maintain the origin text boundary selected at a placeholder,
  // this selectable fragment must be aware of the [RenderParagraph] that closely
  // encompasses the complete origin text boundary.
  //
  // See [_updateSelectionEndEdgeAtPlaceholderByMultiSelectableTextBoundary] for the method
  // that handles updating the end edge.
  SelectionResult? _updateSelectionStartEdgeAtPlaceholderByMultiSelectableTextBoundary(
    _TextBoundaryAtPositionInText getTextBoundary,
    Offset globalPosition,
    bool paragraphContainsPosition,
    TextPosition position,
    TextPosition? existingSelectionStart,
    TextPosition? existingSelectionEnd,
  ) {
    const isEnd = false;
    if (_selectableContainsOriginTextBoundary &&
        existingSelectionStart != null &&
        existingSelectionEnd != null) {
      // If this selectable contains the origin boundary, maintain the existing
      // selection.
      final bool forwardSelection = existingSelectionEnd.offset >= existingSelectionStart.offset;
      final RenderParagraph originParagraph = _getOriginParagraph();
      final fragmentBelongsToOriginParagraph = originParagraph == paragraph;
      if (fragmentBelongsToOriginParagraph) {
        return _updateSelectionStartEdgeByMultiSelectableTextBoundary(
          getTextBoundary,
          paragraphContainsPosition,
          position,
          existingSelectionStart,
          existingSelectionEnd,
        );
      }
      final Matrix4 originTransform = originParagraph.getTransformTo(null);
      originTransform.invert();
      final Offset originParagraphLocalPosition = MatrixUtils.transformPoint(
        originTransform,
        globalPosition,
      );
      final bool positionWithinOriginParagraph = originParagraph.paintBounds.contains(
        originParagraphLocalPosition,
      );
      final TextPosition positionRelativeToOriginParagraph = originParagraph.getPositionForOffset(
        originParagraphLocalPosition,
      );
      if (positionWithinOriginParagraph) {
        // When the selection is inverted by the new position it is necessary to
        // swap the start edge (moving edge) with the end edge (static edge) to
        // maintain the origin text boundary within the selection.
        final String originText = originParagraph.text.toPlainText(includeSemanticsLabels: false);
        final _TextBoundaryRecord boundaryAtPosition = getTextBoundary(
          positionRelativeToOriginParagraph,
          originText,
        );
        final _TextBoundaryRecord originTextBoundary = getTextBoundary(
          _getPositionInParagraph(originParagraph),
          originText,
        );
        final TextPosition targetPosition;
        final int pivotOffset = forwardSelection
            ? originTextBoundary.boundaryEnd.offset
            : originTextBoundary.boundaryStart.offset;
        final shouldSwapEdges =
            !forwardSelection != (positionRelativeToOriginParagraph.offset > pivotOffset);
        if (positionRelativeToOriginParagraph.offset < pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryStart;
        } else if (positionRelativeToOriginParagraph.offset > pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryEnd;
        } else {
          // Keep the origin text boundary in bounds when position is at the static edge.
          targetPosition = existingSelectionStart;
        }
        if (shouldSwapEdges) {
          _setSelectionPosition(existingSelectionStart, isEnd: true);
        }
        _setSelectionPosition(_clampTextPosition(targetPosition), isEnd: isEnd);
        final bool finalSelectionIsForward =
            _textSelectionEnd!.offset >= _textSelectionStart!.offset;
        final TextPosition originParagraphPlaceholderTextPosition = _getPositionInParagraph(
          originParagraph,
        );
        final originParagraphPlaceholderRange = TextRange(
          start: originParagraphPlaceholderTextPosition.offset,
          end: originParagraphPlaceholderTextPosition.offset + _placeholderLength,
        );
        if (boundaryAtPosition.boundaryStart.offset > originParagraphPlaceholderRange.end &&
            boundaryAtPosition.boundaryEnd.offset > originParagraphPlaceholderRange.end) {
          return SelectionResult.next;
        }
        if (boundaryAtPosition.boundaryStart.offset < originParagraphPlaceholderRange.start &&
            boundaryAtPosition.boundaryEnd.offset < originParagraphPlaceholderRange.start) {
          return SelectionResult.previous;
        }
        if (finalSelectionIsForward) {
          if (boundaryAtPosition.boundaryEnd.offset <= originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryEnd.offset > originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.next;
          }
        } else {
          if (boundaryAtPosition.boundaryStart.offset >= originTextBoundary.boundaryStart.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryStart.offset < originTextBoundary.boundaryStart.offset) {
            return SelectionResult.previous;
          }
        }
      } else {
        // When the drag position is not contained within the origin paragraph,
        // swap the edges when the selection changes direction.
        //
        // [SelectionUtils.adjustDragOffset] will adjust the given [Offset] to the
        // beginning or end of the provided [Rect] based on whether the [Offset]
        // is located within the given [Rect].
        final Offset adjustedOffset = SelectionUtils.adjustDragOffset(
          originParagraph.paintBounds,
          originParagraphLocalPosition,
          direction: delegate.textDirection,
        );
        final TextPosition adjustedPositionRelativeToOriginParagraph = originParagraph
            .getPositionForOffset(adjustedOffset);
        final TextPosition originParagraphPlaceholderTextPosition = _getPositionInParagraph(
          originParagraph,
        );
        final originParagraphPlaceholderRange = TextRange(
          start: originParagraphPlaceholderTextPosition.offset,
          end: originParagraphPlaceholderTextPosition.offset + _placeholderLength,
        );
        if (forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset <=
                originParagraphPlaceholderRange.start) {
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (!forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset >=
                originParagraphPlaceholderRange.end) {
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset >=
                originParagraphPlaceholderRange.end) {
          _setSelectionPosition(existingSelectionStart, isEnd: true);
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (!forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset <=
                originParagraphPlaceholderRange.start) {
          _setSelectionPosition(existingSelectionStart, isEnd: true);
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
      }
    } else {
      // When the drag position is somewhere on the root text and not a placeholder,
      // traverse the selectable fragments relative to the [RenderParagraph] that
      // contains the drag position.
      if (paragraphContainsPosition) {
        return _updateSelectionStartEdgeByMultiSelectableTextBoundary(
          getTextBoundary,
          paragraphContainsPosition,
          position,
          existingSelectionStart,
          existingSelectionEnd,
        );
      }
      if (existingSelectionEnd != null) {
        final ({RenderParagraph paragraph, Offset localPosition})? targetDetails =
            _getParagraphContainingPosition(globalPosition);
        if (targetDetails == null) {
          return null;
        }
        final RenderParagraph targetParagraph = targetDetails.paragraph;
        final TextPosition positionRelativeToTargetParagraph = targetParagraph.getPositionForOffset(
          targetDetails.localPosition,
        );
        final String targetText = targetParagraph.text.toPlainText(includeSemanticsLabels: false);
        final positionOnPlaceholder =
            targetParagraph
                .getWordBoundary(positionRelativeToTargetParagraph)
                .textInside(targetText) ==
            _placeholderCharacter;
        if (positionOnPlaceholder) {
          return null;
        }
        final bool backwardSelection =
            existingSelectionStart == null && existingSelectionEnd.offset == range.start ||
            existingSelectionStart == existingSelectionEnd &&
                existingSelectionEnd.offset == range.start ||
            existingSelectionStart != null &&
                existingSelectionStart.offset > existingSelectionEnd.offset;
        final _TextBoundaryRecord boundaryAtPositionRelativeToTargetParagraph = getTextBoundary(
          positionRelativeToTargetParagraph,
          targetText,
        );
        final TextPosition targetParagraphPlaceholderTextPosition = _getPositionInParagraph(
          targetParagraph,
        );
        final targetParagraphPlaceholderRange = TextRange(
          start: targetParagraphPlaceholderTextPosition.offset,
          end: targetParagraphPlaceholderTextPosition.offset + _placeholderLength,
        );
        if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset <
                targetParagraphPlaceholderRange.start &&
            boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset <
                targetParagraphPlaceholderRange.start) {
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset >
                targetParagraphPlaceholderRange.end &&
            boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset >
                targetParagraphPlaceholderRange.end) {
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (backwardSelection) {
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset <=
              targetParagraphPlaceholderRange.end) {
            _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
            return SelectionResult.end;
          }
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset >
              targetParagraphPlaceholderRange.end) {
            _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
            return SelectionResult.next;
          }
        } else {
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset >=
              targetParagraphPlaceholderRange.start) {
            _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
            return SelectionResult.end;
          }
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset <
              targetParagraphPlaceholderRange.start) {
            _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
            return SelectionResult.previous;
          }
        }
      }
    }
    return null;
  }

  // This method handles updating the end edge by a text boundary that may
  // not be contained within this selectable fragment. It is possible
  // that a boundary spans multiple selectable fragments when the text contains
  // [WidgetSpan]s.
  //
  // This method differs from [_updateSelectionEndEdgeByMultiSelectableBoundary]
  // in that to maintain the origin text boundary selected at a placeholder, this
  // selectable fragment must be aware of the [RenderParagraph] that closely
  // encompasses the complete origin text boundary.
  //
  // See [_updateSelectionStartEdgeAtPlaceholderByMultiSelectableTextBoundary]
  // for the method that handles updating the start edge.
  SelectionResult? _updateSelectionEndEdgeAtPlaceholderByMultiSelectableTextBoundary(
    _TextBoundaryAtPositionInText getTextBoundary,
    Offset globalPosition,
    bool paragraphContainsPosition,
    TextPosition position,
    TextPosition? existingSelectionStart,
    TextPosition? existingSelectionEnd,
  ) {
    const isEnd = true;
    if (_selectableContainsOriginTextBoundary &&
        existingSelectionStart != null &&
        existingSelectionEnd != null) {
      // If this selectable contains the origin boundary, maintain the existing
      // selection.
      final bool forwardSelection = existingSelectionEnd.offset >= existingSelectionStart.offset;
      final RenderParagraph originParagraph = _getOriginParagraph();
      final fragmentBelongsToOriginParagraph = originParagraph == paragraph;
      if (fragmentBelongsToOriginParagraph) {
        return _updateSelectionEndEdgeByMultiSelectableTextBoundary(
          getTextBoundary,
          paragraphContainsPosition,
          position,
          existingSelectionStart,
          existingSelectionEnd,
        );
      }
      final Matrix4 originTransform = originParagraph.getTransformTo(null);
      originTransform.invert();
      final Offset originParagraphLocalPosition = MatrixUtils.transformPoint(
        originTransform,
        globalPosition,
      );
      final bool positionWithinOriginParagraph = originParagraph.paintBounds.contains(
        originParagraphLocalPosition,
      );
      final TextPosition positionRelativeToOriginParagraph = originParagraph.getPositionForOffset(
        originParagraphLocalPosition,
      );
      if (positionWithinOriginParagraph) {
        // When the selection is inverted by the new position it is necessary to
        // swap the end edge (moving edge) with the start edge (static edge) to
        // maintain the origin text boundary within the selection.
        final String originText = originParagraph.text.toPlainText(includeSemanticsLabels: false);
        final _TextBoundaryRecord boundaryAtPosition = getTextBoundary(
          positionRelativeToOriginParagraph,
          originText,
        );
        final _TextBoundaryRecord originTextBoundary = getTextBoundary(
          _getPositionInParagraph(originParagraph),
          originText,
        );
        final TextPosition targetPosition;
        final int pivotOffset = forwardSelection
            ? originTextBoundary.boundaryStart.offset
            : originTextBoundary.boundaryEnd.offset;
        final shouldSwapEdges =
            !forwardSelection != (positionRelativeToOriginParagraph.offset < pivotOffset);
        if (positionRelativeToOriginParagraph.offset < pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryStart;
        } else if (positionRelativeToOriginParagraph.offset > pivotOffset) {
          targetPosition = boundaryAtPosition.boundaryEnd;
        } else {
          // Keep the origin text boundary in bounds when position is at the static edge.
          targetPosition = existingSelectionEnd;
        }
        if (shouldSwapEdges) {
          _setSelectionPosition(existingSelectionEnd, isEnd: false);
        }
        _setSelectionPosition(_clampTextPosition(targetPosition), isEnd: isEnd);
        final bool finalSelectionIsForward =
            _textSelectionEnd!.offset >= _textSelectionStart!.offset;
        final TextPosition originParagraphPlaceholderTextPosition = _getPositionInParagraph(
          originParagraph,
        );
        final originParagraphPlaceholderRange = TextRange(
          start: originParagraphPlaceholderTextPosition.offset,
          end: originParagraphPlaceholderTextPosition.offset + _placeholderLength,
        );
        if (boundaryAtPosition.boundaryStart.offset > originParagraphPlaceholderRange.end &&
            boundaryAtPosition.boundaryEnd.offset > originParagraphPlaceholderRange.end) {
          return SelectionResult.next;
        }
        if (boundaryAtPosition.boundaryStart.offset < originParagraphPlaceholderRange.start &&
            boundaryAtPosition.boundaryEnd.offset < originParagraphPlaceholderRange.start) {
          return SelectionResult.previous;
        }
        if (finalSelectionIsForward) {
          if (boundaryAtPosition.boundaryEnd.offset <= originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryEnd.offset > originTextBoundary.boundaryEnd.offset) {
            return SelectionResult.next;
          }
        } else {
          if (boundaryAtPosition.boundaryStart.offset >= originTextBoundary.boundaryStart.offset) {
            return SelectionResult.end;
          }
          if (boundaryAtPosition.boundaryStart.offset < originTextBoundary.boundaryStart.offset) {
            return SelectionResult.previous;
          }
        }
      } else {
        // When the drag position is not contained within the origin paragraph,
        // swap the edges when the selection changes direction.
        //
        // [SelectionUtils.adjustDragOffset] will adjust the given [Offset] to the
        // beginning or end of the provided [Rect] based on whether the [Offset]
        // is located within the given [Rect].
        final Offset adjustedOffset = SelectionUtils.adjustDragOffset(
          originParagraph.paintBounds,
          originParagraphLocalPosition,
          direction: delegate.textDirection,
        );
        final TextPosition adjustedPositionRelativeToOriginParagraph = originParagraph
            .getPositionForOffset(adjustedOffset);
        final TextPosition originParagraphPlaceholderTextPosition = _getPositionInParagraph(
          originParagraph,
        );
        final originParagraphPlaceholderRange = TextRange(
          start: originParagraphPlaceholderTextPosition.offset,
          end: originParagraphPlaceholderTextPosition.offset + _placeholderLength,
        );
        if (forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset <=
                originParagraphPlaceholderRange.start) {
          _setSelectionPosition(existingSelectionEnd, isEnd: false);
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (!forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset >=
                originParagraphPlaceholderRange.end) {
          _setSelectionPosition(existingSelectionEnd, isEnd: false);
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset >=
                originParagraphPlaceholderRange.end) {
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (!forwardSelection &&
            adjustedPositionRelativeToOriginParagraph.offset <=
                originParagraphPlaceholderRange.start) {
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
      }
    } else {
      // When the drag position is somewhere on the root text and not a placeholder,
      // traverse the selectable fragments relative to the [RenderParagraph] that
      // contains the drag position.
      if (paragraphContainsPosition) {
        return _updateSelectionEndEdgeByMultiSelectableTextBoundary(
          getTextBoundary,
          paragraphContainsPosition,
          position,
          existingSelectionStart,
          existingSelectionEnd,
        );
      }
      if (existingSelectionStart != null) {
        final ({RenderParagraph paragraph, Offset localPosition})? targetDetails =
            _getParagraphContainingPosition(globalPosition);
        if (targetDetails == null) {
          return null;
        }
        final RenderParagraph targetParagraph = targetDetails.paragraph;
        final TextPosition positionRelativeToTargetParagraph = targetParagraph.getPositionForOffset(
          targetDetails.localPosition,
        );
        final String targetText = targetParagraph.text.toPlainText(includeSemanticsLabels: false);
        final positionOnPlaceholder =
            targetParagraph
                .getWordBoundary(positionRelativeToTargetParagraph)
                .textInside(targetText) ==
            _placeholderCharacter;
        if (positionOnPlaceholder) {
          return null;
        }
        final bool backwardSelection =
            existingSelectionEnd == null && existingSelectionStart.offset == range.end ||
            existingSelectionStart == existingSelectionEnd &&
                existingSelectionStart.offset == range.end ||
            existingSelectionEnd != null &&
                existingSelectionStart.offset > existingSelectionEnd.offset;
        final _TextBoundaryRecord boundaryAtPositionRelativeToTargetParagraph = getTextBoundary(
          positionRelativeToTargetParagraph,
          targetText,
        );
        final TextPosition targetParagraphPlaceholderTextPosition = _getPositionInParagraph(
          targetParagraph,
        );
        final targetParagraphPlaceholderRange = TextRange(
          start: targetParagraphPlaceholderTextPosition.offset,
          end: targetParagraphPlaceholderTextPosition.offset + _placeholderLength,
        );
        if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset <
                targetParagraphPlaceholderRange.start &&
            boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset <
                targetParagraphPlaceholderRange.start) {
          _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
          return SelectionResult.previous;
        }
        if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset >
                targetParagraphPlaceholderRange.end &&
            boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset >
                targetParagraphPlaceholderRange.end) {
          _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
          return SelectionResult.next;
        }
        if (backwardSelection) {
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset >=
              targetParagraphPlaceholderRange.start) {
            _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
            return SelectionResult.end;
          }
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryStart.offset <
              targetParagraphPlaceholderRange.start) {
            _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd);
            return SelectionResult.previous;
          }
        } else {
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset <=
              targetParagraphPlaceholderRange.end) {
            _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
            return SelectionResult.end;
          }
          if (boundaryAtPositionRelativeToTargetParagraph.boundaryEnd.offset >
              targetParagraphPlaceholderRange.end) {
            _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd);
            return SelectionResult.next;
          }
        }
      }
    }
    return null;
  }

  SelectionResult _updateSelectionEdgeByMultiSelectableTextBoundary(
    Offset globalPosition, {
    required bool isEnd,
    required _TextBoundaryAtPositionInText getTextBoundary,
    required _TextBoundaryAtPosition getClampedTextBoundary,
  }) {
    // When the start/end edges are swapped, i.e. the start is after the end, and
    // the scrollable synthesizes an event for the opposite edge, this will potentially
    // move the opposite edge outside of the origin text boundary and we are unable to recover.
    final TextPosition? existingSelectionStart = _textSelectionStart;
    final TextPosition? existingSelectionEnd = _textSelectionEnd;

    _setSelectionPosition(null, isEnd: isEnd);
    final Matrix4 transform = delegate.getTransformTo(null);
    transform.invert();
    final Offset localPosition = MatrixUtils.transformPoint(transform, globalPosition);
    if (_rect.isEmpty) {
      final SelectionResult result = SelectionUtils.getResultBasedOnRect(_rect, localPosition);
      _setSelectionPosition(
        result == SelectionResult.next
            ? TextPosition(offset: range.end)
            : TextPosition(offset: range.start, affinity: TextAffinity.upstream),
        isEnd: isEnd,
      );
      return result;
    }
    final Offset adjustedOffset = SelectionUtils.adjustDragOffset(
      _rect,
      localPosition,
      direction: delegate.textDirection,
    );
    final Offset adjustedOffsetRelativeToParagraph = SelectionUtils.adjustDragOffset(
      delegate.paintBounds,
      localPosition,
      direction: delegate.textDirection,
    );

    final TextPosition position = delegate.getPositionForOffset(adjustedOffset);
    final TextPosition positionInFullText = delegate.getPositionForOffset(
      adjustedOffsetRelativeToParagraph,
    );

    final SelectionResult? result;
    if (_isPlaceholder()) {
      result = isEnd
          ? _updateSelectionEndEdgeAtPlaceholderByMultiSelectableTextBoundary(
              getTextBoundary,
              globalPosition,
              delegate.paintBounds.contains(localPosition),
              positionInFullText,
              existingSelectionStart,
              existingSelectionEnd,
            )
          : _updateSelectionStartEdgeAtPlaceholderByMultiSelectableTextBoundary(
              getTextBoundary,
              globalPosition,
              delegate.paintBounds.contains(localPosition),
              positionInFullText,
              existingSelectionStart,
              existingSelectionEnd,
            );
    } else {
      result = isEnd
          ? _updateSelectionEndEdgeByMultiSelectableTextBoundary(
              getTextBoundary,
              delegate.paintBounds.contains(localPosition),
              positionInFullText,
              existingSelectionStart,
              existingSelectionEnd,
            )
          : _updateSelectionStartEdgeByMultiSelectableTextBoundary(
              getTextBoundary,
              delegate.paintBounds.contains(localPosition),
              positionInFullText,
              existingSelectionStart,
              existingSelectionEnd,
            );
    }
    if (result != null) {
      return result;
    }

    // Check if the original local position is within the rect, if it is not then
    // we do not need to look up the text boundary for that position. This is to
    // maintain a selectables selection collapsed at 0 when the local position is
    // not located inside its rect.
    _TextBoundaryRecord? textBoundary = _boundingBoxesContains(localPosition)
        ? getClampedTextBoundary(position)
        : null;
    if (textBoundary != null &&
        (textBoundary.boundaryStart.offset < range.start &&
                textBoundary.boundaryEnd.offset <= range.start ||
            textBoundary.boundaryStart.offset >= range.end &&
                textBoundary.boundaryEnd.offset > range.end)) {
      // When the position is located at a placeholder inside of the text, then we may compute
      // a text boundary that does not belong to the current selectable fragment. In this case
      // we should invalidate the text boundary so that it is not taken into account when
      // computing the target position.
      textBoundary = null;
    }
    final TextPosition targetPosition = _clampTextPosition(
      isEnd
          ? _updateSelectionEndEdgeByTextBoundary(
              textBoundary,
              getClampedTextBoundary,
              position,
              existingSelectionStart,
              existingSelectionEnd,
            )
          : _updateSelectionStartEdgeByTextBoundary(
              textBoundary,
              getClampedTextBoundary,
              position,
              existingSelectionStart,
              existingSelectionEnd,
            ),
    );

    _setSelectionPosition(targetPosition, isEnd: isEnd);
    if (targetPosition.offset == range.end) {
      return SelectionResult.next;
    }

    if (targetPosition.offset == range.start) {
      return SelectionResult.previous;
    }
    // TODO(chunhtai): The geometry information should not be used to determine
    // selection result. This is a workaround to RenderParagraph, where it does
    // not have a way to get accurate text length if its text is truncated due to
    // layout constraint.
    return SelectionUtils.getResultBasedOnRect(_rect, localPosition);
  }

  TextPosition _closestTextBoundary(_TextBoundaryRecord textBoundary, TextPosition position) {
    final int differenceA = (position.offset - textBoundary.boundaryStart.offset).abs();
    final int differenceB = (position.offset - textBoundary.boundaryEnd.offset).abs();
    return differenceA < differenceB ? textBoundary.boundaryStart : textBoundary.boundaryEnd;
  }

  bool _isPlaceholder() {
    // Determine whether this selectable fragment is a placeholder.
    RenderObject? current = delegate.renderObject.parent;
    while (current != null) {
      if (current is RenderParagraph) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  RenderParagraph _getOriginParagraph() {
    // This method should only be called from a fragment that contains
    // the origin boundary. By traversing up the RenderTree, determine the
    // highest RenderParagraph that contains the origin text boundary.
    assert(_selectableContainsOriginTextBoundary);
    // Begin at the parent because it is guaranteed the paragraph containing
    // this selectable fragment contains the origin boundary.
    RenderObject? current = delegate.renderObject.parent;
    RenderParagraph? originParagraph;
    while (current != null) {
      if (current is RenderParagraph) {
        final List<_SelectableFragment>? fragments = _TextSelectionState.maybeOf(current)
            ?.fragments;
        if (fragments != null) {
          var paragraphContainsOriginTextBoundary = false;
          for (final _SelectableFragment fragment in fragments) {
            if (fragment._selectableContainsOriginTextBoundary) {
              paragraphContainsOriginTextBoundary = true;
              originParagraph = current;
              break;
            }
          }
          if (!paragraphContainsOriginTextBoundary) {
            return originParagraph ?? paragraph;
          }
        }
      }
      current = current.parent;
    }
    return originParagraph ?? paragraph;
  }

  ({RenderParagraph paragraph, Offset localPosition})? _getParagraphContainingPosition(
    Offset globalPosition,
  ) {
    // This method will return the closest [RenderParagraph] whose rect
    // contains the given `globalPosition` and the given `globalPosition`
    // relative to that [RenderParagraph]. If no ancestor [RenderParagraph]
    // contains the given `globalPosition` then this method will return null.
    RenderObject? current = paragraph;
    while (current != null) {
      if (current is RenderParagraph) {
        final Matrix4 currentTransform = current.getTransformTo(null);
        currentTransform.invert();
        final Offset currentParagraphLocalPosition = MatrixUtils.transformPoint(
          currentTransform,
          globalPosition,
        );
        final bool positionWithinCurrentParagraph = current.paintBounds.contains(
          currentParagraphLocalPosition,
        );
        if (positionWithinCurrentParagraph) {
          return (paragraph: current, localPosition: currentParagraphLocalPosition);
        }
      }
      current = current.parent;
    }
    return null;
  }

  bool _boundingBoxesContains(Offset position) {
    for (final Rect rect in boundingBoxes) {
      if (rect.contains(position)) {
        return true;
      }
    }
    return false;
  }

  TextPosition _clampTextPosition(TextPosition position) {
    // Affinity of range.end is upstream.
    if (position.offset > range.end ||
        (position.offset == range.end && position.affinity == TextAffinity.downstream)) {
      return TextPosition(offset: range.end, affinity: TextAffinity.upstream);
    }
    if (position.offset < range.start) {
      return TextPosition(offset: range.start);
    }
    return position;
  }

  void _setSelectionPosition(TextPosition? position, {required bool isEnd}) {
    if (isEnd) {
      _textSelectionEnd = position;
    } else {
      _textSelectionStart = position;
    }
  }

  SelectionResult _handleClearSelection() {
    _textSelectionStart = null;
    _textSelectionEnd = null;
    _selectableContainsOriginTextBoundary = false;
    return SelectionResult.none;
  }

  SelectionResult _handleSelectAll() {
    _textSelectionStart = TextPosition(offset: range.start);
    _textSelectionEnd = TextPosition(offset: range.end, affinity: TextAffinity.upstream);
    return SelectionResult.none;
  }

  SelectionResult _handleSelectTextBoundary(_TextBoundaryRecord textBoundary) {
    // This fragment may not contain the boundary, decide what direction the target
    // fragment is located in. Because fragments are separated by placeholder
    // spans, we also check if the beginning or end of the boundary is touching
    // either edge of this fragment.
    if (textBoundary.boundaryStart.offset < range.start &&
        textBoundary.boundaryEnd.offset <= range.start) {
      return SelectionResult.previous;
    } else if (textBoundary.boundaryStart.offset >= range.end &&
        textBoundary.boundaryEnd.offset > range.end) {
      return SelectionResult.next;
    }
    // Fragments are separated by placeholder span, the text boundary shouldn't
    // expand across fragments.
    assert(
      textBoundary.boundaryStart.offset >= range.start &&
          textBoundary.boundaryEnd.offset <= range.end,
    );
    _textSelectionStart = textBoundary.boundaryStart;
    _textSelectionEnd = textBoundary.boundaryEnd;
    _selectableContainsOriginTextBoundary = true;
    return SelectionResult.end;
  }

  TextRange? _intersect(TextRange a, TextRange b) {
    assert(a.isNormalized);
    assert(b.isNormalized);
    final int startMax = math.max(a.start, b.start);
    final int endMin = math.min(a.end, b.end);
    if (startMax <= endMin) {
      // Intersection.
      return TextRange(start: startMax, end: endMin);
    }
    return null;
  }

  SelectionResult _handleSelectMultiFragmentTextBoundary(_TextBoundaryRecord textBoundary) {
    // This fragment may not contain the boundary, decide what direction the target
    // fragment is located in. Because fragments are separated by placeholder
    // spans, we also check if the beginning or end of the boundary is touching
    // either edge of this fragment.
    if (textBoundary.boundaryStart.offset < range.start &&
        textBoundary.boundaryEnd.offset <= range.start) {
      return SelectionResult.previous;
    } else if (textBoundary.boundaryStart.offset >= range.end &&
        textBoundary.boundaryEnd.offset > range.end) {
      return SelectionResult.next;
    }
    final boundaryAsRange = TextRange(
      start: textBoundary.boundaryStart.offset,
      end: textBoundary.boundaryEnd.offset,
    );
    final TextRange? intersectRange = _intersect(range, boundaryAsRange);
    if (intersectRange != null) {
      _textSelectionStart = TextPosition(offset: intersectRange.start);
      _textSelectionEnd = TextPosition(offset: intersectRange.end);
      _selectableContainsOriginTextBoundary = true;
      if (range.end < textBoundary.boundaryEnd.offset) {
        return SelectionResult.next;
      }
      return SelectionResult.end;
    }
    return SelectionResult.none;
  }

  _TextBoundaryRecord _adjustTextBoundaryAtPosition(TextRange textBoundary, TextPosition position) {
    late final TextPosition start;
    late final TextPosition end;
    if (position.offset > textBoundary.end) {
      start = end = TextPosition(offset: position.offset);
    } else {
      start = TextPosition(offset: textBoundary.start);
      end = TextPosition(offset: textBoundary.end, affinity: TextAffinity.upstream);
    }
    return (boundaryStart: start, boundaryEnd: end);
  }

  SelectionResult _handleSelectWord(Offset globalPosition) {
    final TextPosition position = delegate.getPositionForOffset(
      delegate.globalToLocal(globalPosition),
    );
    if (_positionIsWithinCurrentSelection(position) && _textSelectionStart != _textSelectionEnd) {
      return SelectionResult.end;
    }
    final _TextBoundaryRecord wordBoundary = _getWordBoundaryAtPosition(position);
    return _handleSelectTextBoundary(wordBoundary);
  }

  _TextBoundaryRecord _getWordBoundaryAtPosition(TextPosition position) {
    final TextRange word = delegate.getWordBoundary(position);
    assert(word.isNormalized);
    return _adjustTextBoundaryAtPosition(word, position);
  }

  SelectionResult _handleSelectParagraph(Offset globalPosition) {
    final Offset localPosition = delegate.globalToLocal(globalPosition);
    final TextPosition position = delegate.getPositionForOffset(localPosition);
    final _TextBoundaryRecord paragraphBoundary = _getParagraphBoundaryAtPosition(
      position,
      fullText,
    );
    return _handleSelectMultiFragmentTextBoundary(paragraphBoundary);
  }

  TextPosition _getPositionInParagraph(RenderParagraph targetParagraph) {
    final Matrix4 transform = delegate.getTransformTo(targetParagraph);
    final Offset localCenter = delegate.paintBounds.centerLeft;
    final Offset localPos = MatrixUtils.transformPoint(transform, localCenter);
    final TextPosition position = targetParagraph.getPositionForOffset(localPos);
    return position;
  }

  _TextBoundaryRecord _getParagraphBoundaryAtPosition(TextPosition position, String text) {
    final paragraphBoundary = ParagraphBoundary(text);
    // Use position.offset - 1 when `position` is at the end of the selectable to retrieve
    // the previous text boundary's location.
    final int paragraphStart =
        paragraphBoundary.getLeadingTextBoundaryAt(
          position.offset == text.length || position.affinity == TextAffinity.upstream
              ? position.offset - 1
              : position.offset,
        ) ??
        0;
    final int paragraphEnd =
        paragraphBoundary.getTrailingTextBoundaryAt(position.offset) ?? text.length;
    final paragraphRange = TextRange(start: paragraphStart, end: paragraphEnd);
    assert(paragraphRange.isNormalized);
    return _adjustTextBoundaryAtPosition(paragraphRange, position);
  }

  _TextBoundaryRecord _getClampedParagraphBoundaryAtPosition(TextPosition position) {
    final paragraphBoundary = ParagraphBoundary(fullText);
    // Use position.offset - 1 when `position` is at the end of the selectable to retrieve
    // the previous text boundary's location.
    int paragraphStart =
        paragraphBoundary.getLeadingTextBoundaryAt(
          position.offset == fullText.length || position.affinity == TextAffinity.upstream
              ? position.offset - 1
              : position.offset,
        ) ??
        0;
    int paragraphEnd =
        paragraphBoundary.getTrailingTextBoundaryAt(position.offset) ?? fullText.length;
    paragraphStart = paragraphStart < range.start
        ? range.start
        : paragraphStart > range.end
        ? range.end
        : paragraphStart;
    paragraphEnd = paragraphEnd > range.end
        ? range.end
        : paragraphEnd < range.start
        ? range.start
        : paragraphEnd;
    final paragraphRange = TextRange(start: paragraphStart, end: paragraphEnd);
    assert(paragraphRange.isNormalized);
    return _adjustTextBoundaryAtPosition(paragraphRange, position);
  }

  SelectionResult _handleDirectionallyExtendSelection(
    double horizontalBaseline,
    bool isExtent,
    SelectionExtendDirection movement,
  ) {
    final Matrix4 transform = delegate.getTransformTo(null);
    if (transform.invert() == 0.0) {
      switch (movement) {
        case SelectionExtendDirection.previousLine:
        case SelectionExtendDirection.backward:
          return SelectionResult.previous;
        case SelectionExtendDirection.nextLine:
        case SelectionExtendDirection.forward:
          return SelectionResult.next;
      }
    }
    final double baselineInParagraphCoordinates = MatrixUtils.transformPoint(
      transform,
      Offset(horizontalBaseline, 0),
    ).dx;
    assert(!baselineInParagraphCoordinates.isNaN);
    final TextPosition newPosition;
    final SelectionResult result;
    switch (movement) {
      case SelectionExtendDirection.previousLine:
      case SelectionExtendDirection.nextLine:
        assert(_textSelectionEnd != null && _textSelectionStart != null);
        final TextPosition targetedEdge = isExtent ? _textSelectionEnd! : _textSelectionStart!;
        final MapEntry<TextPosition, SelectionResult> moveResult = _handleVerticalMovement(
          targetedEdge,
          horizontalBaselineInParagraphCoordinates: baselineInParagraphCoordinates,
          below: movement == SelectionExtendDirection.nextLine,
        );
        newPosition = moveResult.key;
        result = moveResult.value;
      case SelectionExtendDirection.forward:
      case SelectionExtendDirection.backward:
        _textSelectionEnd ??= movement == SelectionExtendDirection.forward
            ? TextPosition(offset: range.start)
            : TextPosition(offset: range.end, affinity: TextAffinity.upstream);
        _textSelectionStart ??= _textSelectionEnd;
        final TextPosition targetedEdge = isExtent ? _textSelectionEnd! : _textSelectionStart!;
        final Offset edgeOffsetInParagraphCoordinates = _getOffsetForPosition(targetedEdge);
        final baselineOffsetInParagraphCoordinates = Offset(
          baselineInParagraphCoordinates,
          // Use half of line height to point to the middle of the line.
          edgeOffsetInParagraphCoordinates.dy - delegate.preferredLineHeight / 2,
        );
        newPosition = delegate.getPositionForOffset(baselineOffsetInParagraphCoordinates);
        result = SelectionResult.end;
    }
    if (isExtent) {
      _textSelectionEnd = newPosition;
    } else {
      _textSelectionStart = newPosition;
    }
    return result;
  }

  SelectionResult _handleGranularlyExtendSelection(
    bool forward,
    bool isExtent,
    TextGranularity granularity,
  ) {
    _textSelectionEnd ??= forward
        ? TextPosition(offset: range.start)
        : TextPosition(offset: range.end, affinity: TextAffinity.upstream);
    _textSelectionStart ??= _textSelectionEnd;
    final TextPosition targetedEdge = isExtent ? _textSelectionEnd! : _textSelectionStart!;
    if (forward && (targetedEdge.offset == range.end)) {
      return SelectionResult.next;
    }
    if (!forward && (targetedEdge.offset == range.start)) {
      return SelectionResult.previous;
    }
    final SelectionResult result;
    final TextPosition newPosition;
    switch (granularity) {
      case TextGranularity.character:
        final String text = range.textInside(fullText);
        newPosition = _moveBeyondTextBoundaryAtDirection(
          targetedEdge,
          forward,
          CharacterBoundary(text),
        );
        result = SelectionResult.end;
      case TextGranularity.word:
        final TextBoundary textBoundary = delegate.moveByWordBoundary;
        newPosition = _moveBeyondTextBoundaryAtDirection(targetedEdge, forward, textBoundary);
        result = SelectionResult.end;
      case TextGranularity.paragraph:
        final String text = range.textInside(fullText);
        newPosition = _moveBeyondTextBoundaryAtDirection(
          targetedEdge,
          forward,
          ParagraphBoundary(text),
        );
        result = SelectionResult.end;
      case TextGranularity.line:
        newPosition = _moveToTextBoundaryAtDirection(targetedEdge, forward, LineBoundary(this));
        result = SelectionResult.end;
      case TextGranularity.document:
        final String text = range.textInside(fullText);
        newPosition = _moveBeyondTextBoundaryAtDirection(
          targetedEdge,
          forward,
          DocumentBoundary(text),
        );
        if (forward && newPosition.offset == range.end) {
          result = SelectionResult.next;
        } else if (!forward && newPosition.offset == range.start) {
          result = SelectionResult.previous;
        } else {
          result = SelectionResult.end;
        }
    }

    if (isExtent) {
      _textSelectionEnd = newPosition;
    } else {
      _textSelectionStart = newPosition;
    }
    return result;
  }

  // Move **beyond** the local boundary of the given type (unless range.start or
  // range.end is reached). Used for most TextGranularity types except for
  // TextGranularity.line, to ensure the selection movement doesn't get stuck at
  // a local fixed point.
  TextPosition _moveBeyondTextBoundaryAtDirection(
    TextPosition end,
    bool forward,
    TextBoundary textBoundary,
  ) {
    final int newOffset = forward
        ? textBoundary.getTrailingTextBoundaryAt(end.offset) ?? range.end
        : textBoundary.getLeadingTextBoundaryAt(end.offset - 1) ?? range.start;
    return TextPosition(offset: newOffset);
  }

  // Move **to** the local boundary of the given type. Typically used for line
  // boundaries, such that performing "move to line start" more than once never
  // moves the selection to the previous line.
  TextPosition _moveToTextBoundaryAtDirection(
    TextPosition end,
    bool forward,
    TextBoundary textBoundary,
  ) {
    assert(end.offset >= 0);
    final int caretOffset;
    switch (end.affinity) {
      case TextAffinity.upstream:
        if (end.offset < 1 && !forward) {
          assert(end.offset == 0);
          return const TextPosition(offset: 0);
        }
        final characterBoundary = CharacterBoundary(fullText);
        caretOffset =
            math.max(
              0,
              characterBoundary.getLeadingTextBoundaryAt(range.start + end.offset) ?? range.start,
            ) -
            1;
      case TextAffinity.downstream:
        caretOffset = end.offset;
    }
    final int offset = forward
        ? textBoundary.getTrailingTextBoundaryAt(caretOffset) ?? range.end
        : textBoundary.getLeadingTextBoundaryAt(caretOffset) ?? range.start;
    return TextPosition(offset: offset);
  }

  MapEntry<TextPosition, SelectionResult> _handleVerticalMovement(
    TextPosition position, {
    required double horizontalBaselineInParagraphCoordinates,
    required bool below,
  }) {
    final List<ui.LineMetrics> lines = delegate.computeLineMetrics();
    final Offset offset = delegate.getOffsetForCaret(position, Rect.zero);
    int currentLine = lines.length - 1;
    for (final lineMetrics in lines) {
      if (lineMetrics.baseline > offset.dy) {
        currentLine = lineMetrics.lineNumber;
        break;
      }
    }
    final TextPosition newPosition;
    if (below && currentLine == lines.length - 1) {
      newPosition = TextPosition(offset: range.end, affinity: TextAffinity.upstream);
    } else if (!below && currentLine == 0) {
      newPosition = TextPosition(offset: range.start);
    } else {
      final int newLine = below ? currentLine + 1 : currentLine - 1;
      newPosition = _clampTextPosition(
        delegate.getPositionForOffset(
          Offset(horizontalBaselineInParagraphCoordinates, lines[newLine].baseline),
        ),
      );
    }
    final SelectionResult result;
    if (newPosition.offset == range.start) {
      result = SelectionResult.previous;
    } else if (newPosition.offset == range.end) {
      result = SelectionResult.next;
    } else {
      result = SelectionResult.end;
    }
    assert(result != SelectionResult.next || below);
    assert(result != SelectionResult.previous || !below);
    return MapEntry<TextPosition, SelectionResult>(newPosition, result);
  }

  /// Whether the given text position is contained in current selection
  /// range.
  ///
  /// The parameter `start` must be smaller than `end`.
  bool _positionIsWithinCurrentSelection(TextPosition position) {
    if (_textSelectionStart == null || _textSelectionEnd == null) {
      return false;
    }
    // Normalize current selection.
    late TextPosition currentStart;
    late TextPosition currentEnd;
    if (_compareTextPositions(_textSelectionStart!, _textSelectionEnd!) > 0) {
      currentStart = _textSelectionStart!;
      currentEnd = _textSelectionEnd!;
    } else {
      currentStart = _textSelectionEnd!;
      currentEnd = _textSelectionStart!;
    }
    return _compareTextPositions(currentStart, position) >= 0 &&
        _compareTextPositions(currentEnd, position) <= 0;
  }

  /// Compares two text positions.
  ///
  /// Returns 1 if `position` < `otherPosition`, -1 if `position` > `otherPosition`,
  /// or 0 if they are equal.
  static int _compareTextPositions(TextPosition position, TextPosition otherPosition) {
    if (position.offset < otherPosition.offset) {
      return 1;
    } else if (position.offset > otherPosition.offset) {
      return -1;
    } else if (position.affinity == otherPosition.affinity) {
      return 0;
    } else {
      return position.affinity == TextAffinity.upstream ? 1 : -1;
    }
  }

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) {
    return delegate.getTransformTo(ancestor);
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (owner.isDisposed || !delegate.attached) {
      assert(startHandle == null && endHandle == null, 'Only clean up can be called.');
      return;
    }
    if (_startHandleLayerLink == startHandle && _endHandleLayerLink == endHandle) {
      return;
    }
    _startHandleLayerLink = startHandle;
    _endHandleLayerLink = endHandle;
    owner.updateHandleAnchors();
  }

  /// The selection of this fragment, in offsets of the whole text.
  TextSelection? get selection {
    final TextPosition? start = _textSelectionStart;
    final TextPosition? end = _textSelectionEnd;
    if (start == null || end == null) {
      return null;
    }
    return TextSelection(baseOffset: start.offset, extentOffset: end.offset);
  }

  /// The anchors of the selection handles that this fragment owns.
  ///
  /// The region hands its handle links to the selectables that contain the
  /// edges of the selection, see [pushHandleLayers]. The handles themselves
  /// are widgets in the overlay that follow these anchors.
  List<TextAnchor> get handleAnchors {
    if (_textSelectionStart == null || _textSelectionEnd == null) {
      return const <TextAnchor>[];
    }
    final LayerLink? startLink = _startHandleLayerLink;
    final SelectionPoint? startPoint = value.startSelectionPoint;
    final LayerLink? endLink = _endHandleLayerLink;
    final SelectionPoint? endPoint = value.endSelectionPoint;
    return <TextAnchor>[
      if (startLink != null && startPoint != null)
        TextAnchor.point(link: startLink, offset: startPoint.localPosition),
      if (endLink != null && endPoint != null)
        TextAnchor.point(link: endLink, offset: endPoint.localPosition),
    ];
  }

  List<Rect>? _cachedBoundingBoxes;

  // The plugin learns about a new layout at the end of the layout phase (see
  // [didChangeParagraphLayout]). Until then the cached geometry cannot be
  // trusted: the paragraph is either waiting for a layout, or it has been
  // laid out again already and whoever asks (its parent, for example) has to
  // get the new geometry.
  void _dropCachedGeometryIfLayoutIsStale() {
    if (!delegate.hasLayout || delegate.pendingLayout) {
      _cachedRect = null;
      _cachedBoundingBoxes = null;
    }
  }

  @override
  List<Rect> get boundingBoxes {
    _dropCachedGeometryIfLayoutIsStale();
    if (_cachedBoundingBoxes == null) {
      final List<TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: .max,
        includePlaceholders: true,
      );
      if (boxes.isNotEmpty) {
        _cachedBoundingBoxes = <Rect>[];
        for (final textBox in boxes) {
          _cachedBoundingBoxes!.add(textBox.toRect());
        }
      } else {
        final Offset offset = _getOffsetForPosition(TextPosition(offset: range.start));
        final rect = Rect.fromPoints(offset, offset.translate(0, -delegate.preferredLineHeight));
        _cachedBoundingBoxes = <Rect>[rect];
      }
    }
    return _cachedBoundingBoxes!;
  }

  Rect? _cachedRect;

  Rect get _rect {
    _dropCachedGeometryIfLayoutIsStale();
    if (_cachedRect == null) {
      final List<TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: .max,
        includePlaceholders: true,
      );
      if (boxes.isNotEmpty) {
        Rect result = boxes.first.toRect();
        for (var index = 1; index < boxes.length; index += 1) {
          result = result.expandToInclude(boxes[index].toRect());
        }
        _cachedRect = result;
      } else {
        final Offset offset = _getOffsetForPosition(TextPosition(offset: range.start));
        _cachedRect = Rect.fromPoints(offset, offset.translate(0, -delegate.preferredLineHeight));
      }
    }
    return _cachedRect!;
  }

  void didChangeParagraphLayout() {
    _cachedRect = null;
    _cachedBoundingBoxes = null;
  }

  @override
  int get contentLength => range.end - range.start;

  @override
  Size get size {
    return _rect.size;
  }

  // The bottom of the caret at `position`, where a selection handle attaches.
  Offset _getOffsetForPosition(TextPosition position) {
    return delegate.getOffsetForCaret(position, Rect.zero) +
        Offset(0, delegate.getFullHeightForCaret(position));
  }

  TextPosition _getTextPositionVertical(TextPosition position, double verticalOffset) {
    final Offset caretOffset = delegate.getOffsetForCaret(position, Rect.zero);
    return delegate.getPositionForOffset(caretOffset.translate(0.0, verticalOffset));
  }

  @override
  TextSelection getLineAtOffset(TextPosition position) {
    final TextRange line = delegate.getLineBoundary(position);
    final int start = line.start.clamp(range.start, range.end);
    final int end = line.end.clamp(range.start, range.end);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  @override
  TextPosition getTextPositionAbove(TextPosition position) {
    // -0.5 of preferredLineHeight points to the middle of the line above.
    return _clampTextPosition(
      _getTextPositionVertical(position, -0.5 * delegate.preferredLineHeight),
    );
  }

  @override
  TextPosition getTextPositionBelow(TextPosition position) {
    // 1.5 of preferredLineHeight points to the middle of the line below.
    return _clampTextPosition(
      _getTextPositionVertical(position, 1.5 * delegate.preferredLineHeight),
    );
  }

  @override
  TextRange getWordBoundary(TextPosition position) => delegate.getWordBoundary(position);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<String>('textInsideRange', range.textInside(fullText)));
    properties.add(DiagnosticsProperty<TextRange>('range', range));
    properties.add(DiagnosticsProperty<String>('fullText', fullText));
  }
}
