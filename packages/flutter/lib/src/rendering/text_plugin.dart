// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/widgets.dart';
library;

import 'dart:ui'
    as ui
    show BoxHeightStyle, BoxWidthStyle, TextBox, TextDirection, TextPosition, TextRange;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'box.dart';
import 'custom_paint.dart';
import 'editable.dart';
import 'object.dart';
import 'paragraph.dart';

/// An interface for plugins that interact with and change the visual appearance
/// of text rendered by [RenderParagraph] and [RenderEditable] (such as via [Text],
/// [RichText], and [EditableText] widgets) within a [TextPluginScope].
///
/// A [TextPlugin] is notified as text widgets are added, updated, laid out,
/// and removed within its scope, and can also receive pointer events
/// originating from those text widgets.
///
/// Each text widget in the scope is represented by a [TextDelegate], which
/// allows the plugin to query the displayed string, query layout metrics (such
/// as [TextDelegate.getBoxesForSelection]), and attach a
/// [TextDelegate.backgroundPainter] or [TextDelegate.foregroundPainter].
///
/// Multiple [TextPlugin]s can be composed for the same subtree by nesting
/// [TextPluginScope] widgets or using [TextPluginScope.multiple]. Their
/// painters are painted in the order in which the plugins were installed in the
/// widget tree: text plugins installed closer to the root paint first.
///
/// See also:
///
///  * [TextPluginScope], which installs one or more [TextPlugin]s for a
///    widget subtree.
///  * [TextDelegate], which represents an individual [RenderParagraph] or
///    [RenderEditable] managed by a [TextPlugin].
abstract class TextPlugin {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const TextPlugin();

  /// Whether scrollable viewports within the enclosing [TextPluginScope]
  /// should disable lazy loading and eagerly lay out all sliver children.
  ///
  /// When `true`, viewports (such as [ListView], [CustomScrollView], and
  /// [Viewport]) within the [TextPluginScope] expand their cache extent so
  /// that offscreen children in finite lazy lists are built and laid out
  /// immediately. This allows plugins such as "Find in Page" (`Ctrl+F`) to
  /// discover, highlight, and scroll to text matches in items that have not
  /// yet been scrolled into view.
  ///
  /// If a [TextPlugin] also implements [Listenable] (for example, by extending
  /// or mixing in [ChangeNotifier]), [TextPluginScope] automatically listens
  /// to the plugin and updates enclosing viewports whenever
  /// [disableLazyLoading] changes.
  ///
  /// Defaults to `false`.
  bool get disableLazyLoading => false;

  /// Called whenever a new text widget ([Text], [RichText], or [EditableText])
  /// appears in the subtree covered by this plugin.
  void didAddText(TextDelegate delegate) {}

  /// Called whenever the text displayed in a text widget covered by this
  /// plugin changes.
  void didUpdateText(TextDelegate delegate) {}

  /// Called whenever a text widget covered by this plugin completes layout.
  ///
  /// Layout queries on [delegate] (such as [TextDelegate.getBoxesForSelection])
  /// are guaranteed to be valid during this callback.
  void didLayoutText(TextDelegate delegate) {}

  /// Called whenever a text widget is removed from the subtree covered by this
  /// plugin.
  void didRemoveText(TextDelegate delegate) {}

  /// Called whenever a pointer event occurs on a text widget covered by this
  /// plugin.
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {}
}

/// A delegate representing a text render object ([RenderParagraph] or
/// [RenderEditable]) registered with a [TextPlugin].
///
/// A [TextPlugin] receives a dedicated [TextDelegate] instance for each text
/// widget in its scope. Through this delegate, the plugin can:
///
///  * Query the plain text ([text]) or rich [InlineSpan] ([textSpan]).
///  * Query layout metrics after layout has completed (e.g.,
///    [getBoxesForSelection], [getPositionForOffset], [getWordBoundary]).
///  * Scroll enclosing viewports to reveal a specific [ui.TextRange] via
///    [ensureVisible] or a local [Rect] via [showOnScreen].
///  * Sort delegates in logical document order using [compareTo]
///    ([Comparable]).
///  * Provide a [backgroundPainter] or [foregroundPainter] to paint behind or
///    in front of the text.
///  * Listen for text or layout updates via [addListener], or register an
///    [onPointerEvent] callback.
class TextDelegate extends ChangeNotifier implements Comparable<TextDelegate> {
  /// Creates a [TextDelegate] for the given [RenderObject] ([RenderParagraph] or
  /// [RenderEditable]) and [TextPlugin].
  @internal
  TextDelegate(this.renderObject, this.plugin)
    : assert(renderObject is RenderParagraph || renderObject is RenderEditable) {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
  }

  /// The render box ([RenderParagraph] or [RenderEditable]) represented by
  /// this delegate.
  final RenderBox renderObject;

  RenderParagraph? get _paragraph =>
      renderObject is RenderParagraph ? renderObject as RenderParagraph : null;
  RenderEditable? get _editable =>
      renderObject is RenderEditable ? renderObject as RenderEditable : null;

  /// The [TextPlugin] that owns this delegate.
  final TextPlugin plugin;

  /// Returns the plain text in the text widget represented by this delegate.
  String get text {
    if (_paragraph != null) {
      return _paragraph!.text.toPlainText(includeSemanticsLabels: false);
    }
    return _editable!.text?.toPlainText(includeSemanticsLabels: false) ?? _editable!.plainText;
  }

  /// Returns the [InlineSpan] tree displayed by the text widget represented by
  /// this delegate.
  InlineSpan get textSpan {
    if (_paragraph != null) {
      return _paragraph!.text;
    }
    return _editable!.text ?? TextSpan(text: _editable!.plainText);
  }

  /// Returns the character ranges occupied by [PlaceholderSpan]s (such as
  /// [WidgetSpan]s) within [text].
  ///
  /// Each [PlaceholderSpan] is represented in [text] by a single
  /// `0xFFFC` ([PlaceholderSpan.placeholderCodeUnit]) character.
  List<ui.TextRange> get placeholderRanges {
    final String plainText = text;
    final ranges = <ui.TextRange>[];
    var index = 0;
    while (index < plainText.length) {
      if (plainText.codeUnitAt(index) == PlaceholderSpan.placeholderCodeUnit) {
        final start = index;
        while (index < plainText.length &&
            plainText.codeUnitAt(index) == PlaceholderSpan.placeholderCodeUnit) {
          index += 1;
        }
        ranges.add(ui.TextRange(start: start, end: index));
      } else {
        index += 1;
      }
    }
    return ranges;
  }

  /// The directionality of the text.
  ui.TextDirection get textDirection => _paragraph?.textDirection ?? _editable!.textDirection;

  /// Whether the underlying render object is currently attached to the
  /// render tree.
  bool get attached => renderObject.attached;

  /// Whether the underlying render object has undergone layout and has a
  /// size.
  bool get hasSize => renderObject.hasSize;

  /// Whether the underlying render object has a valid, up-to-date layout.
  ///
  /// Layout query methods such as [getBoxesForSelection], [ensureVisible], and
  /// [getPositionForOffset] may only be called when [hasLayout] is true (such
  /// as inside [TextPlugin.didLayoutText], [CustomPainter.paint], or
  /// [TextPlugin.handlePointerEvent]).
  bool get hasLayout => renderObject.hasSize && !renderObject.debugNeedsLayout;

  /// The size of the underlying render object.
  ///
  /// Valid only after layout.
  Size get size => renderObject.size;

  /// An estimate of the bounds of the underlying render object in its
  /// local coordinate system.
  Rect get paintBounds => renderObject.paintBounds;

  /// Optional callback invoked when a [PointerEvent] occurs on the text widget
  /// represented by this delegate.
  ValueChanged<PointerEvent>? onPointerEvent;

  /// A [CustomPainter] to be painted in front of the text widget.
  CustomPainter? get foregroundPainter => _foregroundPainter;
  CustomPainter? _foregroundPainter;
  set foregroundPainter(CustomPainter? value) {
    if (_foregroundPainter == value) {
      return;
    }
    final CustomPainter? oldPainter = _foregroundPainter;
    _foregroundPainter = value;
    _didUpdatePainter(_foregroundPainter, oldPainter);
  }

  /// A [CustomPainter] to be painted behind the text widget.
  CustomPainter? get backgroundPainter => _backgroundPainter;
  CustomPainter? _backgroundPainter;
  set backgroundPainter(CustomPainter? value) {
    if (_backgroundPainter == value) {
      return;
    }
    final CustomPainter? oldPainter = _backgroundPainter;
    _backgroundPainter = value;
    _didUpdatePainter(_backgroundPainter, oldPainter);
  }

  void _didUpdatePainter(CustomPainter? newPainter, CustomPainter? oldPainter) {
    if (newPainter == null) {
      assert(oldPainter != null);
      renderObject.markNeedsPaint();
    } else if (oldPainter == null ||
        newPainter.runtimeType != oldPainter.runtimeType ||
        newPainter.shouldRepaint(oldPainter)) {
      renderObject.markNeedsPaint();
    }
    if (renderObject.attached) {
      oldPainter?.removeListener(renderObject.markNeedsPaint);
      newPainter?.addListener(renderObject.markNeedsPaint);
    }
  }

  /// Returns a list of [ui.TextBox]es that bound the given [selection] in the
  /// local coordinate space of the text widget.
  ///
  /// When [includePlaceholders] is `false`, boxes corresponding to embedded
  /// [PlaceholderSpan]s (such as [WidgetSpan]s) are excluded from the returned
  /// list.
  ///
  /// Valid only after layout (see [hasLayout]).
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
    bool includePlaceholders = true,
  }) {
    if (_editable != null) {
      return _editable!.getBoxesForSelection(selection);
    }
    if (includePlaceholders || !selection.isValid || selection.isCollapsed) {
      return _paragraph!.getBoxesForSelection(
        selection,
        boxHeightStyle: boxHeightStyle,
        boxWidthStyle: boxWidthStyle,
      );
    }
    final String plainText = text;
    final int start = selection.start.clamp(0, plainText.length);
    final int end = selection.end.clamp(0, plainText.length);
    final boxes = <ui.TextBox>[];
    var segmentStart = start;
    for (var i = start; i < end; i += 1) {
      if (plainText.codeUnitAt(i) == PlaceholderSpan.placeholderCodeUnit) {
        if (segmentStart < i) {
          boxes.addAll(
            _paragraph!.getBoxesForSelection(
              TextSelection(baseOffset: segmentStart, extentOffset: i),
              boxHeightStyle: boxHeightStyle,
              boxWidthStyle: boxWidthStyle,
            ),
          );
        }
        segmentStart = i + 1;
      }
    }
    if (segmentStart < end) {
      boxes.addAll(
        _paragraph!.getBoxesForSelection(
          TextSelection(baseOffset: segmentStart, extentOffset: end),
          boxHeightStyle: boxHeightStyle,
          boxWidthStyle: boxWidthStyle,
        ),
      );
    }
    return boxes;
  }

  /// Returns the [ui.TextPosition] within the text for the given local pixel
  /// [offset].
  ///
  /// Valid only after layout (see [hasLayout]).
  ui.TextPosition getPositionForOffset(Offset offset) {
    if (_paragraph != null) {
      return _paragraph!.getPositionForOffset(offset);
    }
    return _editable!.getPositionForOffset(offset);
  }

  /// Returns the [ui.TextRange] of the word at the given [position].
  ///
  /// Valid only after layout (see [hasLayout]).
  ui.TextRange getWordBoundary(ui.TextPosition position) {
    if (_paragraph != null) {
      return _paragraph!.getWordBoundary(position);
    }
    return _editable!.getWordBoundary(position);
  }

  /// Returns the local offset at which to paint the caret for the given
  /// [position].
  ///
  /// Valid only after layout (see [hasLayout]).
  Offset getOffsetForCaret(ui.TextPosition position, Rect caretPrototype) {
    if (_paragraph != null) {
      return _paragraph!.getOffsetForCaret(position, caretPrototype);
    }
    return _editable!.getOffsetForCaret(position, caretPrototype);
  }

  /// Returns the full height of the caret at the given [position].
  ///
  /// Valid only after layout (see [hasLayout]).
  double getFullHeightForCaret(ui.TextPosition position) {
    if (_paragraph != null) {
      return _paragraph!.getFullHeightForCaret(position);
    }
    return _editable!.getFullHeightForCaret(position);
  }

  /// Applies the paint transform from the underlying render object up to
  /// [ancestor] (or the root of the render tree if [ancestor] is null).
  Matrix4 getTransformTo(RenderObject? ancestor) {
    return renderObject.getTransformTo(ancestor);
  }

  /// Converts the given [point] from the local coordinate system of the text
  /// widget to the global coordinate system (or the coordinate system of
  /// [ancestor]).
  Offset localToGlobal(Offset point, {RenderObject? ancestor}) {
    return renderObject.localToGlobal(point, ancestor: ancestor);
  }

  /// Converts the given [point] from the global coordinate system (or the
  /// coordinate system of [ancestor]) to the local coordinate system of the
  /// text widget.
  Offset globalToLocal(Offset point, {RenderObject? ancestor}) {
    return renderObject.globalToLocal(point, ancestor: ancestor);
  }

  /// Scrolls any enclosing scrollable viewports so that this text widget (or
  /// the specified local [rect] within it) is visible on screen.
  void showOnScreen({Rect? rect, Duration duration = Duration.zero, Curve curve = Curves.ease}) {
    renderObject.showOnScreen(
      descendant: renderObject,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }

  /// Scrolls any enclosing scrollable viewports so that the given character
  /// [range] within this text widget is visible on screen.
  ///
  /// Computes the bounding rectangle of the glyphs in [range] (or the caret
  /// rect if [range] is collapsed) and delegates to [showOnScreen].
  ///
  /// Valid only after layout (see [hasLayout]).
  void ensureVisible(
    ui.TextRange range, {
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    assert(hasLayout);
    final List<ui.TextBox> boxes = getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      boxHeightStyle: ui.BoxHeightStyle.max,
      includePlaceholders: false,
    );
    if (boxes.isNotEmpty) {
      Rect targetRect = boxes.first.toRect();
      for (var i = 1; i < boxes.length; i += 1) {
        targetRect = targetRect.expandToInclude(boxes[i].toRect());
      }
      showOnScreen(rect: targetRect, duration: duration, curve: curve);
      return;
    }
    final position = ui.TextPosition(offset: range.start);
    final Offset caretOffset = getOffsetForCaret(position, Rect.zero);
    final double caretHeight = getFullHeightForCaret(position);
    showOnScreen(
      rect: Rect.fromLTWH(caretOffset.dx, caretOffset.dy, 1.0, caretHeight),
      duration: duration,
      curve: curve,
    );
  }

  /// Compares this [TextDelegate] with [other] according to their logical
  /// document order in the render tree.
  ///
  /// Returns a negative integer if this delegate's render object precedes
  /// [other]'s in a pre-order traversal of the render tree, zero if they
  /// represent the same render object, or a positive integer if this
  /// delegate follows [other].
  ///
  /// This is useful when scrollable lists mount items out of document order
  /// (for example, when scrolling upward in a lazy [ListView]).
  @override
  int compareTo(TextDelegate other) {
    if (identical(this, other) || identical(renderObject, other.renderObject)) {
      return 0;
    }

    final thisAncestors = <RenderObject>[];
    for (RenderObject? node = renderObject; node != null; node = node.parent) {
      thisAncestors.add(node);
    }

    final otherAncestors = <RenderObject>[];
    for (RenderObject? node = other.renderObject; node != null; node = node.parent) {
      otherAncestors.add(node);
    }

    int thisIndex = thisAncestors.length - 1;
    int otherIndex = otherAncestors.length - 1;

    if (!identical(thisAncestors[thisIndex], otherAncestors[otherIndex])) {
      // The two render objects do not share a common root (e.g., one is detached).
      return identityHashCode(renderObject).compareTo(identityHashCode(other.renderObject));
    }

    while (thisIndex >= 0 &&
        otherIndex >= 0 &&
        identical(thisAncestors[thisIndex], otherAncestors[otherIndex])) {
      thisIndex -= 1;
      otherIndex -= 1;
    }

    if (thisIndex < 0) {
      return -1;
    }
    if (otherIndex < 0) {
      return 1;
    }

    final RenderObject commonParent = thisAncestors[thisIndex + 1];
    final RenderObject thisBranch = thisAncestors[thisIndex];
    final RenderObject otherBranch = otherAncestors[otherIndex];

    var comparisonResult = 0;
    void findFirstChild(RenderObject child) {
      if (comparisonResult != 0) {
        return;
      }
      if (identical(child, thisBranch)) {
        comparisonResult = -1;
      } else if (identical(child, otherBranch)) {
        comparisonResult = 1;
      }
    }

    commonParent.visitChildren(findFirstChild);
    return comparisonResult;
  }

  /// Marks the underlying render object as needing to repaint.
  void markNeedsPaint() {
    renderObject.markNeedsPaint();
  }

  /// Attaches painter listeners when the render object attaches to the
  /// pipeline owner.
  @internal
  void attachPainters() {
    _backgroundPainter?.addListener(renderObject.markNeedsPaint);
    _foregroundPainter?.addListener(renderObject.markNeedsPaint);
  }

  /// Detaches painter listeners when the render object detaches from the
  /// pipeline owner.
  @internal
  void detachPainters() {
    _backgroundPainter?.removeListener(renderObject.markNeedsPaint);
    _foregroundPainter?.removeListener(renderObject.markNeedsPaint);
  }

  /// Notifies listeners registered on this [TextDelegate] that the text or
  /// layout has been updated.
  @internal
  void notifyChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    detachPainters();
    _backgroundPainter = null;
    _foregroundPainter = null;
    onPointerEvent = null;
    super.dispose();
  }
}
