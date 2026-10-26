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
/// A [TextPlugin] is notified after layout as text widgets are added, updated,
/// laid out, and removed within its scope, and can also receive pointer events
/// originating from those text widgets.
///
/// Each text widget in the scope is represented by a [TextDelegate], which
/// allows the plugin to query the displayed string, query layout metrics (such
/// as [TextDelegate.getBoxesForSelection]), and attach a
/// [TextDelegate.backgroundPainter] or [TextDelegate.foregroundPainter].
///
/// Multiple [TextPlugin]s can be composed for the same subtree by nesting
/// [TextPluginScope] widgets or using [TextPluginScope.multiple]. By default,
/// their painters are painted in the order in which the plugins were installed
/// in the widget tree (outermost first), or ordered by [paintOrder] when
/// specified.
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

  /// Whether this plugin requires offscreen content in scrollable viewports to
  /// be rendered so it can be discovered and navigated to (for example,
  /// "Find in Page" / `Ctrl+F` search).
  ///
  /// When any active [TextPlugin] within a [TextPluginScope] has
  /// [needsOffscreenContent] set to `true`, [TextPluginScope] installs an
  /// [OffscreenContentRenderingStrategy] with
  /// [OffscreenRenderingPolicy.eager] so that scrollable viewports (such as
  /// [ListView], [CustomScrollView], and [Viewport]) within the scope expand
  /// their cache extent and eagerly render offscreen sliver children.
  ///
  /// If a [TextPlugin] also implements [Listenable] (for example, by extending
  /// or mixing in [ChangeNotifier]), [TextPluginScope] automatically listens
  /// to the plugin and updates the [OffscreenContentRenderingStrategy] whenever
  /// [needsOffscreenContent] changes.
  ///
  /// Defaults to `false`.
  bool get needsOffscreenContent => false;

  /// The relative order in which this plugin paints and receives pointer
  /// events compared to other active [TextPlugin]s on the same text widget.
  ///
  /// Plugins with a lower [paintOrder] paint first (further in the background)
  /// and receive pointer events first. When two plugins have the same
  /// [paintOrder], their relative order is determined by their
  /// [TextPluginScope] installation order (outermost scope first).
  ///
  /// Defaults to `0`.
  int get paintOrder => 0;

  /// Whether this plugin paints text selection highlights.
  ///
  /// When a plugin with [handlesSelectionHighlight] set to `true` is active
  /// on a [RenderParagraph], its [TextDelegate.backgroundPainter] is painted
  /// after other plugin background painters (immediately behind the text
  /// glyphs) and replaces the built-in selection highlight painting on
  /// [RenderParagraph].
  @internal
  bool get handlesSelectionHighlight => false;

  /// Called after layout whenever a new text widget ([Text], [RichText], or
  /// [EditableText]) appears in the subtree covered by this plugin.
  ///
  /// Layout queries on [delegate] (such as [TextDelegate.getBoxesForSelection]
  /// and [TextDelegate.size]) are guaranteed to be valid during this callback.
  void didAddText(TextDelegate delegate) {}

  /// Called after layout whenever the text displayed in a text widget covered
  /// by this plugin changes.
  ///
  /// Layout queries on [delegate] (such as [TextDelegate.getBoxesForSelection]
  /// and [TextDelegate.size]) are guaranteed to be valid during this callback.
  void didUpdateText(TextDelegate delegate) {}

  /// Called whenever a text widget covered by this plugin completes layout.
  ///
  /// Layout queries on [delegate] (such as [TextDelegate.getBoxesForSelection]
  /// and [TextDelegate.size]) are guaranteed to be valid during this callback.
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
/// Each `(RenderObject, TextPlugin)` pair receives its own dedicated
/// [TextDelegate] instance. Through this delegate, the plugin can:
///
///  * Query the plain text ([text]) or rich [InlineSpan] ([textSpan]).
///  * Query layout metrics (e.g., [getBoxesForSelection],
///    [getPositionForOffset], [getWordBoundary]).
///  * Scroll enclosing viewports to reveal a specific [ui.TextRange] via
///    [ensureVisible] or a local [Rect] via [showOnScreen].
///  * Sort delegates in logical document order using [compareTo]
///    ([Comparable]).
///  * Provide a [backgroundPainter] or [foregroundPainter] to paint behind or
///    in front of the text.
///  * Listen for text or layout updates via [addListener], or register an
///    [onPointerEvent] callback.
class TextDelegate extends ChangeNotifier implements Comparable<TextDelegate> {
  /// Creates a [TextDelegate] for the given [RenderObject] ([RenderParagraph],
  /// [RenderEditable], or [TextDelegateHostMixin]) and [TextPlugin].
  @internal
  TextDelegate(this.renderObject, this.plugin)
    : assert(
        renderObject is RenderParagraph ||
            renderObject is RenderEditable ||
            renderObject is TextDelegateHostMixin,
      ) {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
  }

  /// The render box ([RenderParagraph], [RenderEditable], or custom
  /// [TextDelegateHostMixin]) represented by this delegate.
  final RenderBox renderObject;

  RenderParagraph? get _paragraph =>
      renderObject is RenderParagraph ? renderObject as RenderParagraph : null;
  RenderEditable? get _editable =>
      renderObject is RenderEditable ? renderObject as RenderEditable : null;
  TextDelegateHostMixin? get _host =>
      renderObject is TextDelegateHostMixin ? renderObject as TextDelegateHostMixin : null;

  /// The [TextPlugin] that owns this delegate.
  final TextPlugin plugin;

  /// Tracks whether the underlying render object currently has an up-to-date
  /// layout in both debug and release builds.
  @internal
  bool hasValidLayout = false;

  /// Whether [TextPlugin.didAddText] has been dispatched for this delegate.
  @internal
  bool hasDispatchedAdd = false;

  /// Whether [TextPlugin.didUpdateText] is pending for the next post-layout flush.
  @internal
  bool pendingUpdate = false;

  /// Whether [TextPlugin.didLayoutText] is pending for the next post-layout flush.
  @internal
  bool pendingLayout = false;

  /// Whether this delegate has been disposed.
  @internal
  bool isDisposed = false;

  /// Returns the plain text in the text widget represented by this delegate.
  String get text {
    if (_paragraph != null) {
      return _paragraph!.text.toPlainText(includeSemanticsLabels: false);
    }
    if (_editable != null) {
      return _editable!.text?.toPlainText(includeSemanticsLabels: false) ?? _editable!.plainText;
    }
    return _host!.plainText;
  }

  /// Returns the [InlineSpan] tree displayed by the text widget represented by
  /// this delegate.
  InlineSpan get textSpan {
    if (_paragraph != null) {
      return _paragraph!.text;
    }
    if (_editable != null) {
      return _editable!.text ?? TextSpan(text: _editable!.plainText);
    }
    return _host!.textSpan;
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

  /// The active text selections in the text widget represented by this
  /// delegate.
  ///
  /// For a [RenderParagraph] with embedded [PlaceholderSpan]s (such as
  /// [WidgetSpan]s), each selectable text fragment may have its own
  /// [TextSelection].
  List<TextSelection> get selections {
    if (_paragraph != null) {
      return _paragraph!.selections;
    }
    if (_editable != null) {
      final TextSelection? editableSelection = _editable!.selection;
      if (editableSelection == null || !editableSelection.isValid) {
        return const <TextSelection>[];
      }
      return <TextSelection>[editableSelection];
    }
    return _host!.selections;
  }

  /// The color used to paint selection highlights on the text widget
  /// represented by this delegate.
  Color? get selectionColor {
    if (_paragraph != null) {
      return _paragraph!.selectionColor;
    }
    if (_editable != null) {
      return _editable!.selectionColor;
    }
    return _host!.selectionColor;
  }

  /// The directionality of the text.
  ui.TextDirection get textDirection =>
      _paragraph?.textDirection ?? _editable?.textDirection ?? _host!.textDirection;

  /// Whether the underlying render object is currently attached to the
  /// render tree.
  bool get attached => renderObject.attached;

  /// Whether the underlying render object has undergone layout and has a
  /// size.
  bool get hasSize => renderObject.hasSize;

  /// Whether the underlying render object has a valid, up-to-date layout.
  ///
  /// Guaranteed to be `true` during [TextPlugin.didAddText],
  /// [TextPlugin.didUpdateText], [TextPlugin.didLayoutText],
  /// [CustomPainter.paint], and [TextPlugin.handlePointerEvent].
  bool get hasLayout => hasValidLayout && renderObject.hasSize && !renderObject.debugNeedsLayout;

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
  /// By default ([includePlaceholders] is `false`), boxes corresponding to
  /// embedded [PlaceholderSpan]s (such as [WidgetSpan]s) are excluded from the
  /// returned list so text highlights do not paint across inline widgets.
  ///
  /// Valid only after layout (see [hasLayout]).
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
    bool includePlaceholders = false,
  }) {
    if (_editable != null) {
      return _editable!.getBoxesForSelection(selection);
    }
    if (_host != null) {
      return _host!.getBoxesForSelection(
        selection,
        boxHeightStyle: boxHeightStyle,
        boxWidthStyle: boxWidthStyle,
      );
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
    if (_editable != null) {
      return _editable!.getPositionForOffset(offset);
    }
    return _host!.getPositionForOffset(offset);
  }

  /// Returns the [ui.TextRange] of the word at the given [position].
  ///
  /// Valid only after layout (see [hasLayout]).
  ui.TextRange getWordBoundary(ui.TextPosition position) {
    if (_paragraph != null) {
      return _paragraph!.getWordBoundary(position);
    }
    if (_editable != null) {
      return _editable!.getWordBoundary(position);
    }
    return _host!.getWordBoundary(position);
  }

  /// Returns the local offset at which to paint the caret for the given
  /// [position].
  ///
  /// Valid only after layout (see [hasLayout]).
  Offset getOffsetForCaret(ui.TextPosition position, Rect caretPrototype) {
    if (_paragraph != null) {
      return _paragraph!.getOffsetForCaret(position, caretPrototype);
    }
    if (_editable != null) {
      return _editable!.getOffsetForCaret(position, caretPrototype);
    }
    return _host!.getOffsetForCaret(position, caretPrototype);
  }

  /// Returns the full height of the caret at the given [position].
  ///
  /// Valid only after layout (see [hasLayout]).
  double getFullHeightForCaret(ui.TextPosition position) {
    if (_paragraph != null) {
      return _paragraph!.getFullHeightForCaret(position);
    }
    if (_editable != null) {
      return _editable!.getFullHeightForCaret(position);
    }
    return _host!.getFullHeightForCaret(position);
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
    isDisposed = true;
    detachPainters();
    _backgroundPainter = null;
    _foregroundPainter = null;
    onPointerEvent = null;
    super.dispose();
  }
}

/// A mixin for custom [RenderBox] subclasses (such as those that paint text
/// directly with [TextPainter] or non-text render objects exposing a searchable
/// label) that participate in a [TextPluginScope].
///
/// Subclasses using this mixin should:
///  1. Implement [plainText], [textDirection], and [getBoxesForSelection].
///  2. Call [markNeedsTextDelegateUpdate] when [plainText] changes.
///  3. Call [didLayoutTextDelegates] at the end of [performLayout].
///  4. Call [paintTextPluginBackgrounds] and [paintTextPluginForegrounds]
///     inside [paint].
mixin TextDelegateHostMixin on RenderBox {
  /// The plain text (or searchable label) exposed to [TextPlugin]s.
  String get plainText;

  /// The [InlineSpan] tree exposed to [TextPlugin]s.
  ///
  /// Defaults to a [TextSpan] wrapping [plainText].
  InlineSpan get textSpan => TextSpan(text: plainText);

  /// The directionality of [plainText].
  ui.TextDirection get textDirection;

  /// Active selections on this render object, if any.
  List<TextSelection> get selections => const <TextSelection>[];

  /// The selection highlight color on this render object, if any.
  Color? get selectionColor => null;

  /// Returns the [ui.TextBox]es bounding [selection] in local coordinates.
  ///
  /// A custom [RenderBox] using [TextPainter] can delegate this directly to
  /// [TextPainter.getBoxesForSelection]. A non-text [RenderBox] (such as an
  /// image or colored badge) can return its full bounding box when [selection]
  /// is non-empty:
  /// `[ui.TextBox.fromLTRBD(0, 0, size.width, size.height, textDirection)]`.
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  });

  /// Returns the [ui.TextPosition] for a local pixel [offset].
  ui.TextPosition getPositionForOffset(Offset offset) => const ui.TextPosition(offset: 0);

  /// Returns the word boundary [ui.TextRange] at [position].
  ui.TextRange getWordBoundary(ui.TextPosition position) =>
      ui.TextRange(start: 0, end: plainText.length);

  /// Returns the local caret offset for [position].
  Offset getOffsetForCaret(ui.TextPosition position, Rect caretPrototype) => Offset.zero;

  /// Returns the full caret height for [position].
  double getFullHeightForCaret(ui.TextPosition position) => hasSize ? size.height : 0.0;

  /// The [TextPlugin]s that this render object is registered with.
  List<TextPlugin>? get textPlugins => _textPlugins;
  List<TextPlugin>? _textPlugins;
  Map<TextPlugin, TextDelegate>? _textPluginDelegates;

  set textPlugins(List<TextPlugin>? value) {
    if (listEquals(_textPlugins, value)) {
      return;
    }
    final List<TextPlugin> oldPlugins = _textPlugins ?? const <TextPlugin>[];
    final newPlugins = value != null ? List<TextPlugin>.unmodifiable(value) : const <TextPlugin>[];
    _textPlugins = value != null ? newPlugins : null;

    if (!attached) {
      return;
    }
    _syncTextPluginDelegates(oldPlugins: oldPlugins);
  }

  bool _textPluginFlushScheduled = false;

  void _scheduleTextPluginFlush() {
    if (_textPluginFlushScheduled || !attached || owner == null) {
      return;
    }
    _textPluginFlushScheduled = true;
    owner!.schedulePostLayoutCallback(_flushTextPluginNotifications);
  }

  void _flushTextPluginNotifications() {
    _textPluginFlushScheduled = false;
    if (!attached || _textPluginDelegates == null || _textPluginDelegates!.isEmpty) {
      return;
    }
    if (!hasSize || debugNeedsLayout) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values.toList(growable: false)) {
      if (delegate.isDisposed) {
        continue;
      }
      delegate.hasValidLayout = true;
      if (!delegate.hasDispatchedAdd) {
        delegate.hasDispatchedAdd = true;
        delegate.pendingUpdate = false;
        delegate.pendingLayout = false;
        delegate.notifyChanged();
        delegate.plugin.didAddText(delegate);
        if (!delegate.isDisposed) {
          delegate.plugin.didLayoutText(delegate);
        }
      } else if (delegate.pendingUpdate) {
        delegate.pendingUpdate = false;
        delegate.pendingLayout = false;
        delegate.notifyChanged();
        delegate.plugin.didUpdateText(delegate);
        if (!delegate.isDisposed) {
          delegate.plugin.didLayoutText(delegate);
        }
      } else if (delegate.pendingLayout) {
        delegate.pendingLayout = false;
        delegate.notifyChanged();
        delegate.plugin.didLayoutText(delegate);
      }
    }
  }

  void _syncTextPluginDelegates({List<TextPlugin>? oldPlugins}) {
    final List<TextPlugin> rawPlugins = _textPlugins ?? const <TextPlugin>[];
    final newPlugins = <TextPlugin>[...rawPlugins];
    mergeSort<TextPlugin>(
      newPlugins,
      compare: (TextPlugin a, TextPlugin b) => a.paintOrder.compareTo(b.paintOrder),
    );
    if (_textPluginDelegates != null) {
      final Set<TextPlugin> newPluginSet = newPlugins.toSet();
      final List<TextPlugin> removedPlugins = _textPluginDelegates!.keys
          .where((TextPlugin plugin) => !newPluginSet.contains(plugin))
          .toList(growable: false);
      var needsRepaint = false;
      for (final plugin in removedPlugins) {
        final TextDelegate delegate = _textPluginDelegates!.remove(plugin)!;
        if (delegate.backgroundPainter != null || delegate.foregroundPainter != null) {
          needsRepaint = true;
        }
        delegate.detachPainters();
        if (delegate.hasDispatchedAdd) {
          plugin.didRemoveText(delegate);
        }
        delegate.dispose();
      }
      if (needsRepaint) {
        markNeedsPaint();
      }
    }

    if (newPlugins.isEmpty) {
      _textPluginDelegates = null;
      return;
    }

    final Map<TextPlugin, TextDelegate> existingDelegates =
        _textPluginDelegates ?? <TextPlugin, TextDelegate>{};
    final orderedDelegates = <TextPlugin, TextDelegate>{};
    final newlyAddedDelegates = <TextDelegate>[];
    final bool currentlyHasValidLayout = hasSize && !debugNeedsLayout;
    for (final plugin in newPlugins) {
      if (orderedDelegates.containsKey(plugin)) {
        continue;
      }
      final TextDelegate? existing = existingDelegates[plugin];
      if (existing != null) {
        orderedDelegates[plugin] = existing;
      } else {
        final delegate = TextDelegate(this, plugin)..hasValidLayout = currentlyHasValidLayout;
        orderedDelegates[plugin] = delegate;
        newlyAddedDelegates.add(delegate);
      }
    }
    _textPluginDelegates = orderedDelegates;

    if (newlyAddedDelegates.isNotEmpty) {
      _scheduleTextPluginFlush();
    }
    if (oldPlugins != null && !listEquals(oldPlugins, newPlugins)) {
      markNeedsPaint();
    }
  }

  /// Marks attached [TextDelegate]s as having updated [plainText] so that
  /// [TextPlugin.didUpdateText] is dispatched after the next layout flush.
  @protected
  void markNeedsTextDelegateUpdate() {
    if (_textPluginDelegates == null || _textPluginDelegates!.isEmpty) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values) {
      delegate.pendingUpdate = true;
    }
    _scheduleTextPluginFlush();
  }

  /// Marks attached [TextDelegate]s as having completed layout so that
  /// [TextPlugin.didAddText], [TextPlugin.didUpdateText], and
  /// [TextPlugin.didLayoutText] are flushed at the end of the layout pass.
  ///
  /// Call this at the end of [performLayout] after setting [size].
  @protected
  void didLayoutTextDelegates() {
    if (_textPluginDelegates != null && _textPluginDelegates!.isNotEmpty) {
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        delegate.hasValidLayout = true;
        delegate.pendingLayout = true;
      }
      _scheduleTextPluginFlush();
    }
  }

  void _paintWithCustomPainter(Canvas canvas, Offset offset, CustomPainter painter) {
    canvas.save();
    if (offset != Offset.zero) {
      canvas.translate(offset.dx, offset.dy);
    }
    painter.paint(canvas, size);
    canvas.restore();
  }

  /// Paints the [TextDelegate.backgroundPainter]s of all active [TextPlugin]s.
  @protected
  void paintTextPluginBackgrounds(PaintingContext context, Offset offset) {
    if (_textPluginDelegates == null) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values) {
      final CustomPainter? painter = delegate.backgroundPainter;
      if (painter != null) {
        _paintWithCustomPainter(context.canvas, offset, painter);
      }
    }
  }

  /// Paints the [TextDelegate.foregroundPainter]s of all active [TextPlugin]s.
  @protected
  void paintTextPluginForegrounds(PaintingContext context, Offset offset) {
    if (_textPluginDelegates == null) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values) {
      final CustomPainter? painter = delegate.foregroundPainter;
      if (painter != null) {
        _paintWithCustomPainter(context.canvas, offset, painter);
      }
    }
  }

  void _removeAllTextPluginDelegates() {
    if (_textPluginDelegates == null) {
      return;
    }
    final List<TextDelegate> delegates = _textPluginDelegates!.values.toList(growable: false);
    _textPluginDelegates = null;
    for (final delegate in delegates) {
      delegate.detachPainters();
      if (delegate.hasDispatchedAdd) {
        delegate.plugin.didRemoveText(delegate);
      }
      delegate.dispose();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _syncTextPluginDelegates();
    if (_textPluginDelegates != null) {
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        delegate.attachPainters();
      }
    }
  }

  @override
  void detach() {
    _removeAllTextPluginDelegates();
    super.detach();
  }

  @override
  void markNeedsLayout() {
    if (_textPluginDelegates != null) {
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        delegate.hasValidLayout = false;
      }
    }
    super.markNeedsLayout();
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    super.handleEvent(event, entry);
    if (_textPluginDelegates != null && _textPluginDelegates!.isNotEmpty) {
      for (final TextDelegate delegate in _textPluginDelegates!.values.toList(growable: false)) {
        delegate.onPointerEvent?.call(event);
        delegate.plugin.handlePointerEvent(delegate, event);
      }
    }
  }

  @override
  void dispose() {
    _textPlugins = null;
    _removeAllTextPluginDelegates();
    super.dispose();
  }
}
