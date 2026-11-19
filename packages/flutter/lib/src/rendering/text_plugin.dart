// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/widgets.dart';
/// @docImport 'custom_paint.dart';
library;

import 'dart:ui'
    as ui
    show BoxHeightStyle, BoxWidthStyle, TextBox, TextDirection, TextPosition, TextRange;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'binding.dart';
import 'box.dart';
import 'editable.dart';
import 'object.dart';
import 'paragraph.dart';

/// An interface for plugins that interact with and change the visual appearance
/// of text rendered by [RenderParagraph] and [RenderEditable] (such as via [Text],
/// [RichText], and [EditableText] widgets) within a [TextPluginScope].
///
/// A [TextPlugin] is notified as text widgets are added, updated, and removed
/// within its scope. It is not notified when a text is laid out.
///
/// Each text widget in the scope is represented by a [TextDelegate], which
/// allows the plugin to query the displayed string and attach a
/// [TextDelegate.backgroundPainter] or [TextDelegate.foregroundPainter]. The
/// layout of the text is not available on the delegate. A painter receives
/// it, as a [TextLayout], while it paints.
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

  /// The relative order in which this plugin paints compared to other active
  /// [TextPlugin]s on the same text widget.
  ///
  /// Plugins with a lower [paintOrder] paint first (further in the
  /// background). When two plugins have the same
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

  /// Called whenever a new text widget ([Text], [RichText], or
  /// [EditableText]) appears in the subtree covered by this plugin.
  ///
  /// This runs after the layout phase of the frame. The render tree is
  /// complete by then, also for text that is created during layout, such as
  /// the items of a lazy list. So the document order of [delegate]
  /// ([TextDelegate.compareTo]) is valid during this callback.
  ///
  /// The layout of the text is not available here. Set a painter, which
  /// receives a [TextLayout] when it paints. A painter that is set in this
  /// callback paints in the same frame.
  void didAddText(TextDelegate delegate) {}

  /// Called whenever the text displayed in a text widget covered by this
  /// plugin changes.
  ///
  /// Like [didAddText], this runs after the layout phase of the frame, and the
  /// layout of the text is not available here.
  ///
  /// There is no callback for a text that is only laid out again. Such a text
  /// is painted again, and its painters receive the new [TextLayout].
  void didUpdateText(TextDelegate delegate) {}

  /// Called whenever a text widget is removed from the subtree covered by this
  /// plugin.
  void didRemoveText(TextDelegate delegate) {}
}

/// The layout of a text widget, given to a [TextPluginPainter] while it
/// paints.
///
/// All geometry is in the local coordinate space of the text widget, which is
/// also the coordinate space of the canvas the painter receives.
///
/// A [TextLayout] is only valid during the call to [TextPluginPainter.paint]
/// that received it. Using it later throws in debug mode.
final class TextLayout {
  TextLayout._(this._delegate);

  final TextDelegate _delegate;
  bool _debugValid = true;

  bool _debugCheckValid() {
    assert(
      _debugValid,
      'A TextLayout was used outside of the TextPluginPainter.paint call that '
      'received it. The layout of a text is only available while painting.',
    );
    return true;
  }

  /// The size of the text widget.
  Size get size {
    assert(_debugCheckValid());
    return _delegate._host.size;
  }

  /// Returns a list of [ui.TextBox]es that bound the given [selection].
  ///
  /// By default ([includePlaceholders] is `false`), boxes corresponding to
  /// embedded [PlaceholderSpan]s (such as [WidgetSpan]s) are excluded from the
  /// returned list so text highlights do not paint across inline widgets.
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
    bool includePlaceholders = false,
  }) {
    assert(_debugCheckValid());
    return _delegate._getBoxesForSelection(
      selection,
      boxHeightStyle: boxHeightStyle,
      boxWidthStyle: boxWidthStyle,
      includePlaceholders: includePlaceholders,
    );
  }

  /// Returns the [ui.TextPosition] within the text for the given [offset].
  ui.TextPosition getPositionForOffset(Offset offset) {
    assert(_debugCheckValid());
    return _delegate._getPositionForOffset(offset);
  }

  /// Returns the [ui.TextRange] of the word at the given [position].
  ui.TextRange getWordBoundary(ui.TextPosition position) {
    assert(_debugCheckValid());
    return _delegate._getWordBoundary(position);
  }

  /// Returns the offset at which to paint the caret for the given [position].
  Offset getOffsetForCaret(ui.TextPosition position, Rect caretPrototype) {
    assert(_debugCheckValid());
    return _delegate._getOffsetForCaret(position, caretPrototype);
  }

  /// Returns the full height of the caret at the given [position].
  double getFullHeightForCaret(ui.TextPosition position) {
    assert(_debugCheckValid());
    return _delegate._getFullHeightForCaret(position);
  }
}

/// Paints behind or in front of a text widget on behalf of a [TextPlugin].
///
/// This is the text plugin counterpart of [CustomPainter]. The difference is
/// that [paint] receives the [TextLayout] of the text, so that a plugin only
/// sees the layout of a text while it paints.
///
/// The painter repaints when the optional `repaint` [Listenable] notifies, or
/// when a new painter is set for which [shouldRepaint] returns true.
abstract class TextPluginPainter extends Listenable {
  /// Creates a text plugin painter.
  ///
  /// The painter will repaint whenever `repaint` notifies its listeners.
  const TextPluginPainter({this._repaint});

  final Listenable? _repaint;

  @override
  void addListener(VoidCallback listener) => _repaint?.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _repaint?.removeListener(listener);

  /// Paints on [canvas], in the local coordinate space of the text widget.
  ///
  /// [layout] is only valid during this call.
  void paint(Canvas canvas, TextLayout layout);

  /// Whether a new instance of this painter has to repaint, given the
  /// instance it replaces.
  bool shouldRepaint(covariant TextPluginPainter oldPainter);
}

/// A delegate representing a text render object ([RenderParagraph] or
/// [RenderEditable]) registered with a [TextPlugin].
///
/// Each `(RenderObject, TextPlugin)` pair receives its own dedicated
/// [TextDelegate] instance. Through this delegate, the plugin can:
///
///  * Query the plain text ([text]) or rich [InlineSpan] ([textSpan]).
///  * Scroll enclosing viewports to reveal a specific [ui.TextRange] via
///    [ensureVisible].
///  * Sort delegates in logical document order using [compareTo]
///    ([Comparable]).
///  * Provide a [backgroundPainter] or [foregroundPainter] to paint behind or
///    in front of the text.
///  * Listen for text updates via [addListener].
///
/// The delegate does not expose the layout of the text. A
/// [TextPluginPainter] receives it, as a [TextLayout], while it paints.
class TextDelegate extends ChangeNotifier implements Comparable<TextDelegate> {
  // Only a [TextDelegateHostMixin] creates delegates: one for each pair of a
  // text render object and a [TextPlugin].
  TextDelegate._(this._host, this.plugin) {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
  }

  // The render object ([RenderParagraph], [RenderEditable], or a custom
  // [TextDelegateHostMixin]) that this delegate represents.
  //
  // It is private on purpose. A plugin reads the text through the members of
  // this class, and the geometry through the [TextLayout] that its painter
  // receives. With the render object it could change the text, read the
  // layout at any time, or reach the painters of another plugin.
  final TextDelegateHostMixin _host;

  /// The [TextPlugin] that owns this delegate.
  final TextPlugin plugin;

  // The state below is written by [TextDelegateHostMixin] only.

  // Whether the underlying render object currently has an up-to-date layout,
  // in both debug and release builds.
  bool _hasValidLayout = false;

  // Whether [TextPlugin.didAddText] has been dispatched for this delegate.
  bool _hasDispatchedAdd = false;

  // Whether [TextPlugin.didUpdateText] is pending for the next post-layout flush.
  bool _pendingUpdate = false;

  // Whether this delegate has been disposed.
  bool _isDisposed = false;

  /// Returns the plain text in the text widget represented by this delegate.
  String get text => _host.plainText;

  /// Returns the [InlineSpan] tree displayed by the text widget represented by
  /// this delegate.
  InlineSpan get textSpan => _host.textSpan;

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
  ///
  /// This is empty for a text field ([RenderEditable]). A text field paints
  /// its own selection, and a plugin has nothing to add to it.
  List<TextSelection> get selections => _host.selections;

  /// The color used to paint selection highlights on the text widget
  /// represented by this delegate.
  Color? get selectionColor => _host.selectionColor;

  /// The directionality of the text.
  ui.TextDirection get textDirection => _host.textDirection;

  /// Whether the underlying render object is currently attached to the
  /// render tree.
  bool get attached => _host.attached;

  bool get _hasLayout => _hasValidLayout && _host.hasSize && !_host.debugNeedsLayout;

  /// A [TextPluginPainter] to be painted in front of the text widget.
  TextPluginPainter? get foregroundPainter => _foregroundPainter;
  TextPluginPainter? _foregroundPainter;
  set foregroundPainter(TextPluginPainter? value) {
    if (_foregroundPainter == value) {
      return;
    }
    final TextPluginPainter? oldPainter = _foregroundPainter;
    _foregroundPainter = value;
    _didUpdatePainter(_foregroundPainter, oldPainter);
  }

  /// A [TextPluginPainter] to be painted behind the text widget.
  TextPluginPainter? get backgroundPainter => _backgroundPainter;
  TextPluginPainter? _backgroundPainter;
  set backgroundPainter(TextPluginPainter? value) {
    if (_backgroundPainter == value) {
      return;
    }
    final TextPluginPainter? oldPainter = _backgroundPainter;
    _backgroundPainter = value;
    _didUpdatePainter(_backgroundPainter, oldPainter);
  }

  void _didUpdatePainter(TextPluginPainter? newPainter, TextPluginPainter? oldPainter) {
    if (newPainter == null) {
      assert(oldPainter != null);
      _host.markNeedsPaint();
    } else if (oldPainter == null ||
        newPainter.runtimeType != oldPainter.runtimeType ||
        newPainter.shouldRepaint(oldPainter)) {
      _host.markNeedsPaint();
    }
    if (_host.attached) {
      oldPainter?.removeListener(_host.markNeedsPaint);
      newPainter?.addListener(_host.markNeedsPaint);
    }
  }

  List<ui.TextBox> _getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
    bool includePlaceholders = false,
  }) {
    if (includePlaceholders || !selection.isValid || selection.isCollapsed) {
      return _host.getBoxesForSelection(
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
            _host.getBoxesForSelection(
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
        _host.getBoxesForSelection(
          TextSelection(baseOffset: segmentStart, extentOffset: end),
          boxHeightStyle: boxHeightStyle,
          boxWidthStyle: boxWidthStyle,
        ),
      );
    }
    return boxes;
  }

  ui.TextPosition _getPositionForOffset(Offset offset) {
    return _host.getPositionForOffset(offset);
  }

  ui.TextRange _getWordBoundary(ui.TextPosition position) {
    return _host.getWordBoundary(position);
  }

  Offset _getOffsetForCaret(ui.TextPosition position, Rect caretPrototype) {
    return _host.getOffsetForCaret(position, caretPrototype);
  }

  double _getFullHeightForCaret(ui.TextPosition position) {
    return _host.getFullHeightForCaret(position);
  }

  /// Runs [scroll] after the current frame if a frame is being produced, and
  /// returns whether it did so.
  ///
  /// Scrolling can mark a viewport as needing layout. That is not allowed
  /// while a frame is being built, laid out and painted, which is when the
  /// lifecycle callbacks of a [TextPlugin] run. So a scroll that is requested
  /// during a frame waits for the end of that frame. The scroll is dropped if
  /// the text is gone by then.
  bool _deferScrollToEndOfFrame(VoidCallback scroll) {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      return false;
    }
    SchedulerBinding.instance.addPostFrameCallback((Duration timeStamp) {
      if (!_isDisposed && attached && _hasLayout) {
        scroll();
      }
    }, debugLabel: 'TextDelegate.ensureVisible');
    return true;
  }

  void _showOnScreen({Rect? rect, Duration duration = Duration.zero, Curve curve = Curves.ease}) {
    _host.showOnScreen(descendant: _host, rect: rect, duration: duration, curve: curve);
  }

  /// Scrolls any enclosing scrollable viewports so that the given character
  /// [range] within this text widget is visible on screen.
  ///
  /// The framework computes the rectangle of the glyphs in [range] (or of the
  /// caret if [range] is collapsed). A plugin does not need the layout of the
  /// text for this.
  ///
  /// This is safe to call from a lifecycle callback of a [TextPlugin]. When it
  /// is called while a frame is being produced, the scroll happens at the end
  /// of that frame and shows in the next one. Otherwise it happens right away.
  /// Nothing happens if the text has no layout at that point.
  void ensureVisible(
    ui.TextRange range, {
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    // The rectangle of the range is computed when the scroll runs.
    if (_deferScrollToEndOfFrame(() => ensureVisible(range, duration: duration, curve: curve))) {
      return;
    }
    if (!_hasLayout) {
      return;
    }
    final List<ui.TextBox> boxes = _getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    if (boxes.isNotEmpty) {
      Rect targetRect = boxes.first.toRect();
      for (var i = 1; i < boxes.length; i += 1) {
        targetRect = targetRect.expandToInclude(boxes[i].toRect());
      }
      _showOnScreen(rect: targetRect, duration: duration, curve: curve);
      return;
    }
    final position = ui.TextPosition(offset: range.start);
    final Offset caretOffset = _getOffsetForCaret(position, Rect.zero);
    final double caretHeight = _getFullHeightForCaret(position);
    _showOnScreen(
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
  ///
  /// One comparison walks both ancestor chains to the root. When the two
  /// branches are children of a parent that keeps a sibling list, such as a
  /// [RenderFlex] or a [RenderSliverList], it then walks that list from both
  /// children at once, so the cost grows with the distance between them. For
  /// other parents it visits all children of the common parent.
  ///
  /// To order many delegates, use [sortInDocumentOrder], which walks the tree
  /// once instead of comparing pairs.
  @override
  int compareTo(TextDelegate other) {
    if (identical(this, other) || identical(_host, other._host)) {
      return 0;
    }

    final thisAncestors = <RenderObject>[];
    for (RenderObject? node = _host; node != null; node = node.parent) {
      thisAncestors.add(node);
    }

    final otherAncestors = <RenderObject>[];
    for (RenderObject? node = other._host; node != null; node = node.parent) {
      otherAncestors.add(node);
    }

    int thisIndex = thisAncestors.length - 1;
    int otherIndex = otherAncestors.length - 1;

    if (!identical(thisAncestors[thisIndex], otherAncestors[otherIndex])) {
      // The two render objects do not share a common root (e.g., one is detached).
      return identityHashCode(_host).compareTo(identityHashCode(other._host));
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

    final int? siblingOrder = _compareSiblings(thisBranch, otherBranch);
    if (siblingOrder != null) {
      return siblingOrder;
    }

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

  static RenderObject? _nextSibling(RenderObject? node) {
    final ParentData? parentData = node?.parentData;
    return parentData is ContainerParentDataMixin<RenderObject> ? parentData.nextSibling : null;
  }

  /// Orders two children of one parent by walking the sibling list forward
  /// from both at once. The walk ends when one reaches the other, so its cost
  /// is the distance between the two.
  ///
  /// Returns null if the two are not in one sibling list, for example when
  /// the parent does not use [ContainerRenderObjectMixin].
  static int? _compareSiblings(RenderObject a, RenderObject b) {
    if (a.parentData is! ContainerParentDataMixin<RenderObject> ||
        b.parentData is! ContainerParentDataMixin<RenderObject>) {
      return null;
    }
    RenderObject? afterA = _nextSibling(a);
    RenderObject? afterB = _nextSibling(b);
    while (afterA != null || afterB != null) {
      if (identical(afterA, b)) {
        return -1;
      }
      if (identical(afterB, a)) {
        return 1;
      }
      afterA = _nextSibling(afterA);
      afterB = _nextSibling(afterB);
    }
    return null;
  }

  /// Sorts [delegates] in place into logical document order, the order that
  /// [compareTo] defines.
  ///
  /// Sorting with [compareTo] compares pairs, and each comparison walks part
  /// of the tree. This method walks the tree once instead: it marks the
  /// ancestors of every delegate, then visits only the marked nodes from the
  /// root, in the order of [RenderObject.visitChildren]. The cost is the
  /// number of children of the marked nodes, however many delegates there
  /// are. Use it to order many delegates at once, for example every text
  /// that matches a search.
  static void sortInDocumentOrder(List<TextDelegate> delegates) {
    if (delegates.length < 2) {
      return;
    }
    final delegatesByRenderObject = <RenderObject, List<TextDelegate>>{};
    final marked = <RenderObject>{};
    RenderObject? root;
    for (final delegate in delegates) {
      (delegatesByRenderObject[delegate._host] ??= <TextDelegate>[]).add(delegate);
      RenderObject? node = delegate._host;
      RenderObject? top;
      while (node != null && marked.add(node)) {
        top = node;
        node = node.parent;
      }
      if (node == null && top != null) {
        // The walk ended at a node without a parent, so `top` is a root.
        if (root != null && !identical(root, top)) {
          // The delegates are not in one tree, for example because one is
          // detached. Fall back to comparing pairs.
          delegates.sort();
          return;
        }
        root = top;
      }
    }
    if (root == null) {
      return;
    }

    final sorted = <TextDelegate>[];
    void visit(RenderObject node) {
      final List<TextDelegate>? atNode = delegatesByRenderObject[node];
      if (atNode != null) {
        sorted.addAll(atNode);
      }
      node.visitChildren((RenderObject child) {
        if (marked.contains(child)) {
          visit(child);
        }
      });
    }

    visit(root);
    assert(sorted.length == delegates.length);
    delegates.setAll(0, sorted);
  }

  /// Marks the underlying render object as needing to repaint.
  void markNeedsPaint() {
    _host.markNeedsPaint();
  }

  // Attaches painter listeners when the render object attaches to the
  // pipeline owner.
  void _attachPainters() {
    _backgroundPainter?.addListener(_host.markNeedsPaint);
    _foregroundPainter?.addListener(_host.markNeedsPaint);
  }

  // Detaches painter listeners when the render object detaches from the
  // pipeline owner.
  void _detachPainters() {
    _backgroundPainter?.removeListener(_host.markNeedsPaint);
    _foregroundPainter?.removeListener(_host.markNeedsPaint);
  }

  // Calls [painter] with the layout of the text. The [TextLayout] is only
  // valid during the call.
  void _paint(TextPluginPainter painter, Canvas canvas) {
    final layout = TextLayout._(this);
    try {
      painter.paint(canvas, layout);
    } finally {
      assert(() {
        layout._debugValid = false;
        return true;
      }());
    }
  }

  // Notifies listeners registered on this [TextDelegate] that the text or the
  // selection has been updated.
  void _notifyChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _detachPainters();
    _backgroundPainter = null;
    _foregroundPainter = null;
    super.dispose();
  }
}

/// A mixin for [RenderBox] subclasses that participate in a [TextPluginScope].
///
/// [RenderParagraph] and [RenderEditable] use it. A custom [RenderBox] can use
/// it too, for example one that paints text directly with [TextPainter], or a
/// non-text render object that exposes a searchable label.
///
/// The mixin creates one [TextDelegate] for each [TextPlugin] in
/// [textPlugins], tells the plugins about the text after layout, and disposes
/// the delegates when the render object is detached.
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

  /// The selections that a plugin with [TextPlugin.handlesSelectionHighlight]
  /// paints for this render object.
  ///
  /// Defaults to none. A render object that paints its own selection, such as
  /// [RenderEditable], keeps the default.
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
    RendererBinding.instance.addPostLayoutCallback(_flushTextPluginNotifications);
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
      if (delegate._isDisposed) {
        continue;
      }
      delegate._hasValidLayout = true;
      if (!delegate._hasDispatchedAdd) {
        delegate._hasDispatchedAdd = true;
        delegate._pendingUpdate = false;
        delegate._notifyChanged();
        delegate.plugin.didAddText(delegate);
      } else if (delegate._pendingUpdate) {
        delegate._pendingUpdate = false;
        delegate._notifyChanged();
        delegate.plugin.didUpdateText(delegate);
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
        delegate._detachPainters();
        if (delegate._hasDispatchedAdd) {
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
        final delegate = TextDelegate._(this, plugin).._hasValidLayout = currentlyHasValidLayout;
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

  /// Whether this render object currently has a [TextDelegate], which is the
  /// case while it is attached and [textPlugins] is not empty.
  ///
  /// A subclass can use this to skip work that only plugins need.
  @protected
  bool get hasTextDelegates => _textPluginDelegates != null && _textPluginDelegates!.isNotEmpty;

  /// Notifies the listeners of every [TextDelegate] of this render object,
  /// without a [TextPlugin] callback.
  ///
  /// Call this when something that a delegate exposes changed and the text
  /// did not, for example [selections] or [selectionColor].
  @protected
  void notifyTextDelegateListeners() {
    if (!hasTextDelegates) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values.toList(growable: false)) {
      delegate._notifyChanged();
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
      delegate._pendingUpdate = true;
    }
    _scheduleTextPluginFlush();
  }

  /// Records that this render object has a layout, so that a pending
  /// [TextPlugin.didAddText] or [TextPlugin.didUpdateText] is flushed at the
  /// end of the layout pass.
  ///
  /// The plugins are not told about the layout itself. A text that was laid
  /// out is painted again, and a painter receives the new [TextLayout] then.
  ///
  /// Call this at the end of [performLayout] after setting [size].
  @protected
  void didLayoutTextDelegates() {
    if (_textPluginDelegates != null && _textPluginDelegates!.isNotEmpty) {
      var hasPendingCallback = false;
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        delegate._hasValidLayout = true;
        if (!delegate._hasDispatchedAdd || delegate._pendingUpdate) {
          hasPendingCallback = true;
        }
      }
      // The flush is only needed for a text that was added or changed before
      // it had a layout.
      if (hasPendingCallback) {
        _scheduleTextPluginFlush();
      }
    }
  }

  void _paintWithTextPluginPainter(
    Canvas canvas,
    Offset offset,
    TextDelegate delegate,
    TextPluginPainter painter,
  ) {
    late int debugPreviousCanvasSaveCount;
    canvas.save();
    assert(() {
      debugPreviousCanvasSaveCount = canvas.getSaveCount();
      return true;
    }());
    if (offset != Offset.zero) {
      canvas.translate(offset.dx, offset.dy);
    }
    delegate._paint(painter, canvas);
    assert(() {
      final int debugNewCanvasSaveCount = canvas.getSaveCount();
      if (debugNewCanvasSaveCount > debugPreviousCanvasSaveCount) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'The $painter text plugin painter called canvas.save() or canvas.saveLayer() at least '
            '${debugNewCanvasSaveCount - debugPreviousCanvasSaveCount} more '
            'time${debugNewCanvasSaveCount - debugPreviousCanvasSaveCount == 1 ? '' : 's'} '
            'than it called canvas.restore().',
          ),
          ErrorDescription(
            'This leaves the canvas in an inconsistent state and will probably result in a broken display.',
          ),
          ErrorHint(
            'You must pair each call to save()/saveLayer() with a later matching call to restore().',
          ),
        ]);
      }
      if (debugNewCanvasSaveCount < debugPreviousCanvasSaveCount) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'The $painter text plugin painter called canvas.restore() '
            '${debugPreviousCanvasSaveCount - debugNewCanvasSaveCount} more '
            'time${debugPreviousCanvasSaveCount - debugNewCanvasSaveCount == 1 ? '' : 's'} '
            'than it called canvas.save() or canvas.saveLayer().',
          ),
          ErrorDescription(
            'This leaves the canvas in an inconsistent state and will result in a broken display.',
          ),
          ErrorHint('You should only call restore() if you first called save() or saveLayer().'),
        ]);
      }
      return debugNewCanvasSaveCount == debugPreviousCanvasSaveCount;
    }());
    canvas.restore();
  }

  /// Paints the [TextDelegate.backgroundPainter]s of all active [TextPlugin]s.
  ///
  /// The painter of a plugin with [TextPlugin.handlesSelectionHighlight] is
  /// painted after the others, so that it is right behind the text.
  ///
  /// This method does not clip. Clipping is the decision of the render object.
  @protected
  void paintTextPluginBackgrounds(PaintingContext context, Offset offset) {
    if (_textPluginDelegates == null) {
      return;
    }
    var hasSelectionHighlightPlugin = false;
    for (final TextDelegate delegate in _textPluginDelegates!.values) {
      if (delegate.plugin.handlesSelectionHighlight) {
        hasSelectionHighlightPlugin = true;
        continue;
      }
      final TextPluginPainter? painter = delegate.backgroundPainter;
      if (painter != null) {
        _paintWithTextPluginPainter(context.canvas, offset, delegate, painter);
      }
    }
    if (!hasSelectionHighlightPlugin) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values) {
      if (!delegate.plugin.handlesSelectionHighlight) {
        continue;
      }
      final TextPluginPainter? painter = delegate.backgroundPainter;
      if (painter != null) {
        _paintWithTextPluginPainter(context.canvas, offset, delegate, painter);
      }
    }
  }

  /// Paints the [TextDelegate.foregroundPainter]s of all active [TextPlugin]s.
  ///
  /// This method does not clip. Clipping is the decision of the render object.
  @protected
  void paintTextPluginForegrounds(PaintingContext context, Offset offset) {
    if (_textPluginDelegates == null) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values) {
      final TextPluginPainter? painter = delegate.foregroundPainter;
      if (painter != null) {
        _paintWithTextPluginPainter(context.canvas, offset, delegate, painter);
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
      delegate._detachPainters();
      if (delegate._hasDispatchedAdd) {
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
        delegate._attachPainters();
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
        delegate._hasValidLayout = false;
      }
    }
    super.markNeedsLayout();
  }

  @override
  void dispose() {
    _textPlugins = null;
    _removeAllTextPluginDelegates();
    super.dispose();
  }
}
