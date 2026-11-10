// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/widgets.dart';
///
/// @docImport 'editable.dart';
library;

import 'dart:math' as math;
import 'dart:ui'
    as ui
    show
        BoxHeightStyle,
        BoxWidthStyle,
        Gradient,
        LineMetrics,
        PlaceholderAlignment,
        Shader,
        TextBox,
        TextHeightBehavior;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'box.dart';
import 'custom_paint.dart';
import 'debug.dart';
import 'layout_helper.dart';
import 'object.dart';
import 'selection.dart';
import 'text_plugin.dart';
import 'text_selection_plugin.dart';

const String _kEllipsis = '\u2026';

/// Used by the [RenderParagraph] to map its rendering children to their
/// corresponding semantics nodes.
///
/// The [RichText] uses this to tag the relation between its placeholder spans
/// and their semantics nodes.
@immutable
class PlaceholderSpanIndexSemanticsTag extends SemanticsTag {
  /// Creates a semantics tag with the input `index`.
  ///
  /// Different [PlaceholderSpanIndexSemanticsTag]s with the same `index` are
  /// consider the same.
  const PlaceholderSpanIndexSemanticsTag(this.index)
    : super('PlaceholderSpanIndexSemanticsTag($index)');

  /// The index of this tag.
  final int index;

  @override
  bool operator ==(Object other) {
    return other is PlaceholderSpanIndexSemanticsTag && other.index == index;
  }

  @override
  int get hashCode => Object.hash(PlaceholderSpanIndexSemanticsTag, index);
}

/// Parent data used by [RenderParagraph] and [RenderEditable] to annotate
/// inline contents (such as [WidgetSpan]s) with.
class TextParentData extends ParentData with ContainerParentDataMixin<RenderBox> {
  /// The offset at which to paint the child in the parent's coordinate system.
  ///
  /// A `null` value indicates this inline widget is not laid out. For instance,
  /// when the inline widget has never been laid out, or the inline widget is
  /// ellipsized away.
  Offset? get offset => _offset;
  Offset? _offset;

  /// The [PlaceholderSpan] associated with this render child.
  ///
  /// This field is usually set by a [ParentDataWidget], and is typically not
  /// null when `performLayout` is called.
  PlaceholderSpan? span;

  @override
  void detach() {
    span = null;
    _offset = null;
    super.detach();
  }

  @override
  String toString() => 'widget: $span, ${offset == null ? "not laid out" : "offset: $offset"}';
}

/// A mixin that provides useful default behaviors for text [RenderBox]es
/// ([RenderParagraph] and [RenderEditable] for example) with inline content
/// children managed by the [ContainerRenderObjectMixin] mixin.
///
/// This mixin assumes every child managed by the [ContainerRenderObjectMixin]
/// mixin corresponds to a [PlaceholderSpan], and they are organized in logical
/// order of the text (the order each [PlaceholderSpan] is encountered when the
/// user reads the text).
///
/// To use this mixin in a [RenderBox] class:
///
///  * Call [layoutInlineChildren] in the `performLayout` and `computeDryLayout`
///    implementation, and during intrinsic size calculations, to get the size
///    information of the inline widgets as a `List` of `PlaceholderDimensions`.
///    Determine the positioning of the inline widgets (which is usually done by
///    a [TextPainter] using its line break algorithm).
///
///  * Call [positionInlineChildren] with the positioning information of the
///    inline widgets.
///
///  * Implement [RenderBox.applyPaintTransform], optionally with
///    [defaultApplyPaintTransform].
///
///  * Call [paintInlineChildren] in [RenderBox.paint] to paint the inline widgets.
///
///  * Call [hitTestInlineChildren] in [RenderBox.hitTestChildren] to hit test the
///    inline widgets.
///
/// See also:
///
///  * [WidgetSpan.extractFromInlineSpan], a helper function for extracting
///    [WidgetSpan]s from an [InlineSpan] tree.
mixin RenderInlineChildrenContainerDefaults
    on RenderBox, ContainerRenderObjectMixin<RenderBox, TextParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! TextParentData) {
      child.parentData = TextParentData();
    }
  }

  static PlaceholderDimensions _layoutChild(
    RenderBox child,
    BoxConstraints childConstraints,
    ChildLayouter layoutChild,
    ChildBaselineGetter getBaseline,
  ) {
    final parentData = child.parentData! as TextParentData;
    final PlaceholderSpan? span = parentData.span;
    assert(span != null);
    return span == null
        ? PlaceholderDimensions.empty
        : PlaceholderDimensions(
            size: layoutChild(child, childConstraints),
            alignment: span.alignment,
            baseline: span.baseline,
            baselineOffset: switch (span.alignment) {
              ui.PlaceholderAlignment.aboveBaseline ||
              ui.PlaceholderAlignment.belowBaseline ||
              ui.PlaceholderAlignment.bottom ||
              ui.PlaceholderAlignment.middle ||
              ui.PlaceholderAlignment.top => null,
              ui.PlaceholderAlignment.baseline => getBaseline(
                child,
                childConstraints,
                span.baseline!,
              ),
            },
          );
  }

  /// Computes the layout for every inline child using the `maxWidth` constraint.
  ///
  /// Returns a list of [PlaceholderDimensions], representing the layout results
  /// for each child managed by the [ContainerRenderObjectMixin] mixin.
  ///
  /// The `getChildBaseline` parameter and the `layoutChild` parameter must be
  /// consistent: if `layoutChild` computes the size of the child without
  /// modifying the actual layout of that child, then `getChildBaseline` must
  /// also be "dry", and vice versa.
  ///
  /// Since this method does not impose a maximum height constraint on the
  /// inline children, some children may become taller than this [RenderBox].
  ///
  /// See also:
  ///
  ///  * [TextPainter.setPlaceholderDimensions], the method that usually takes
  ///    the layout results from this method as the input.
  @protected
  List<PlaceholderDimensions> layoutInlineChildren(
    double maxWidth,
    ChildLayouter layoutChild,
    ChildBaselineGetter getChildBaseline,
  ) {
    final constraints = BoxConstraints(maxWidth: maxWidth);
    return <PlaceholderDimensions>[
      for (RenderBox? child = firstChild; child != null; child = childAfter(child))
        _layoutChild(child, constraints, layoutChild, getChildBaseline),
    ];
  }

  /// Positions each inline child according to the coordinates provided in the
  /// `boxes` list.
  ///
  /// The `boxes` list must be in logical order, which is the order each child
  /// is encountered when the user reads the text. Usually the length of the
  /// list equals [childCount], but it can be less than that, when some children
  /// are omitted due to ellipsing. It never exceeds [childCount].
  ///
  /// See also:
  ///
  ///  * [TextPainter.inlinePlaceholderBoxes], the method that can be used to
  ///    get the input `boxes`.
  @protected
  void positionInlineChildren(List<ui.TextBox> boxes) {
    RenderBox? child = firstChild;
    for (final box in boxes) {
      if (child == null) {
        assert(() {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('Invalid number of boxes provided to positionInlineChildren.'),
            ErrorDescription(
              'The number of boxes (${boxes.length}) exceeds the number of child render objects ($childCount). '
              'Each box corresponds to a child, but there are not enough children to position all boxes.',
            ),
            ErrorHint(
              'This error typically occurs when a custom InlineSpan implementation returns a list of boxes '
              'that is longer than the number of inline children. Ensure that the number of boxes returned '
              'by `computeLineMetrics` or similar methods does not exceed the number of children.',
            ),
            DiagnosticsProperty<RenderObject>(
              'The RenderParagraph receiving the boxes',
              this,
              style: DiagnosticsTreeStyle.errorProperty,
            ),
          ]);
        }());
        return;
      }
      final textParentData = child.parentData! as TextParentData;
      textParentData._offset = Offset(box.left, box.top);
      child = childAfter(child);
    }
    while (child != null) {
      final textParentData = child.parentData! as TextParentData;
      textParentData._offset = null;
      child = childAfter(child);
    }
  }

  /// Applies the transform that would be applied when painting the given child
  /// to the given matrix.
  ///
  /// Render children whose [TextParentData.offset] is null zeros out the
  /// `transform` to indicate they're invisible thus should not be painted.
  @protected
  void defaultApplyPaintTransform(RenderBox child, Matrix4 transform) {
    final childParentData = child.parentData! as TextParentData;
    final Offset? offset = childParentData.offset;
    if (offset == null) {
      transform.setZero();
    } else {
      transform.translateByDouble(offset.dx, offset.dy, 0, 1);
    }
  }

  /// Paints each inline child.
  ///
  /// Render children whose [TextParentData.offset] is null will be skipped by
  /// this method.
  @protected
  void paintInlineChildren(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData! as TextParentData;
      final Offset? childOffset = childParentData.offset;
      if (childOffset == null) {
        return;
      }
      context.paintChild(child, childOffset + offset);
      child = childAfter(child);
    }
  }

  /// Performs a hit test on each inline child.
  ///
  /// Render children whose [TextParentData.offset] is null will be skipped by
  /// this method.
  @protected
  bool hitTestInlineChildren(BoxHitTestResult result, Offset position) {
    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData! as TextParentData;
      final Offset? childOffset = childParentData.offset;
      if (childOffset == null) {
        return false;
      }
      final bool isHit = result.addWithPaintOffset(
        offset: childOffset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) =>
            child!.hitTest(result, position: transformed),
      );
      if (isHit) {
        return true;
      }
      child = childAfter(child);
    }
    return false;
  }
}

class _UnspecifiedTextScaler extends TextScaler {
  const _UnspecifiedTextScaler();

  @override
  Never get textScaleFactor => throw UnimplementedError();

  @override
  Never scale(double fontSize) => throw UnimplementedError();
}

/// A render object that displays a paragraph of text.
class RenderParagraph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, TextParentData>,
        RenderInlineChildrenContainerDefaults,
        RelayoutWhenSystemFontsChangeMixin
    implements TextPluginHost {
  /// Creates a paragraph render object.
  ///
  /// The [maxLines] property may be null (and indeed defaults to null), but if
  /// it is not null, it must be greater than zero.
  RenderParagraph(
    InlineSpan text, {
    TextAlign textAlign = TextAlign.start,
    required TextDirection textDirection,
    this._softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    double textScaleFactor = 1.0,
    TextScaler textScaler = const _UnspecifiedTextScaler(),
    int? maxLines,
    Locale? locale,
    StrutStyle? strutStyle,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    ui.TextHeightBehavior? textHeightBehavior,
    List<RenderBox>? children,
    this._selectionColor,
    SelectionRegistrar? registrar,
    List<TextPlugin>? textPlugins,
    this._devicePixelRatio = 1.0,
  }) : assert(text.debugAssertIsValid()),
       assert(maxLines == null || maxLines > 0),
       assert(
         identical(textScaler, const _UnspecifiedTextScaler()) || textScaleFactor == 1.0,
         'textScaleFactor is deprecated and cannot be specified when textScaler is specified.',
       ),
       _overflow = overflow,
       _textPainter = TextPainter(
         text: text,
         textAlign: textAlign,
         textDirection: textDirection,
         textScaler: textScaler == const _UnspecifiedTextScaler()
             ? TextScaler.linear(textScaleFactor)
             : textScaler,
         maxLines: maxLines,
         ellipsis: overflow == TextOverflow.ellipsis ? _kEllipsis : null,
         locale: locale,
         strutStyle: strutStyle,
         textWidthBasis: textWidthBasis,
         textHeightBehavior: textHeightBehavior,
       ) {
    addAll(children);
    this.registrar = registrar;
    this.textPlugins = textPlugins;
  }

  final TextPainter _textPainter;

  // Currently, computing min/max intrinsic width/height will destroy state
  // inside the painter. Instead of calling _layout again to get back the correct
  // state, use a separate TextPainter for intrinsics calculation.
  //
  // TODO(abarth): Make computing the min/max intrinsic width/height a
  //  non-destructive operation.
  TextPainter? _textIntrinsicsCache;

  TextPainter get _textIntrinsics {
    return (_textIntrinsicsCache ??= TextPainter())
      ..text = _textPainter.text
      ..textAlign = _textPainter.textAlign
      ..textDirection = _textPainter.textDirection
      ..textScaler = _textPainter.textScaler
      ..maxLines = _textPainter.maxLines
      ..ellipsis = _textPainter.ellipsis
      ..locale = _textPainter.locale
      ..strutStyle = _textPainter.strutStyle
      ..textWidthBasis = _textPainter.textWidthBasis
      ..textHeightBehavior = _textPainter.textHeightBehavior;
  }

  List<AttributedString>? _cachedAttributedLabels;

  List<InlineSpanSemanticsInformation>? _cachedCombinedSemanticsInfos;

  /// The text to display.
  InlineSpan get text => _textPainter.text!;

  set text(InlineSpan value) {
    final String? oldPlainText = (_textPluginDelegates?.isNotEmpty ?? false)
        ? _textPainter.text!.toPlainText(includeSemanticsLabels: false)
        : null;
    switch (_textPainter.text!.compareTo(value)) {
      case RenderComparison.identical:
        return;
      case RenderComparison.metadata:
        _textPainter.text = value;
        _cachedCombinedSemanticsInfos = null;
        markNeedsSemanticsUpdate();
      case RenderComparison.paint:
        _textPainter.text = value;
        _cachedAttributedLabels = null;
        _cachedCombinedSemanticsInfos = null;
        markNeedsPaint();
        markNeedsSemanticsUpdate();
      case RenderComparison.layout:
        _textPainter.text = value;
        _overflowShader = null;
        _cachedAttributedLabels = null;
        _cachedCombinedSemanticsInfos = null;
        markNeedsLayout();
        _resetTextSelectionDelegates();
    }
    if (oldPlainText != null &&
        oldPlainText != _textPainter.text!.toPlainText(includeSemanticsLabels: false)) {
      _notifyTextPluginsDidUpdateText();
    }
  }

  /// The ongoing selections in this paragraph, as reported by the
  /// [TextSelectionPlugin] that makes it selectable.
  ///
  /// The selection does not include selections in [PlaceholderSpan] if there
  /// are any.
  List<TextSelection> get selections {
    final Map<TextPlugin, TextDelegate>? delegates = _textPluginDelegates;
    if (delegates == null) {
      return const <TextSelection>[];
    }
    return <TextSelection>[
      for (final TextDelegate delegate in delegates.values) ...delegate.reportedSelections,
    ];
  }

  /// The [SelectionRegistrar] this paragraph will be, or is, registered to.
  ///
  /// The paragraph does not implement selection itself. While it is attached
  /// and has a registrar, a [TextSelectionPlugin] splits its text into
  /// [Selectable]s and registers them: the innermost one provided through
  /// [textPlugins], or else a default one that the paragraph installs.
  SelectionRegistrar? get registrar => _registrar;
  SelectionRegistrar? _registrar;

  set registrar(SelectionRegistrar? value) {
    if (value == _registrar) {
      return;
    }
    _registrar = value;
    _resetTextSelectionDelegates();
  }

  /// Determines whether the given [Selectable] was created for this
  /// [RenderParagraph].
  ///
  /// The text of a paragraph is split into multiple [Selectable]s,
  /// delimited by [PlaceholderSpan]s or [WidgetSpan]s.
  bool selectableBelongsToParagraph(Selectable selectable) {
    return TextSelectionPlugin.ownsSelectable(this, selectable);
  }

  /// The [TextPlugin]s that this paragraph is registered with, in installation
  /// order (outermost to innermost).
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
    // Selectable text always has exactly one selection plugin.
    final List<TextPlugin> rawPlugins = resolveTextSelectionPlugin(
      _textPlugins ?? const <TextPlugin>[],
      selectable: _registrar != null,
    );
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

  void _notifyTextPluginsDidUpdateText() {
    if (_textPluginDelegates == null || _textPluginDelegates!.isEmpty) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values) {
      delegate.pendingUpdate = true;
    }
    _scheduleTextPluginFlush();
  }

  void _notifyTextPluginsSelectionChanged() {
    if (_textPluginDelegates == null || _textPluginDelegates!.isEmpty) {
      return;
    }
    for (final TextDelegate delegate in _textPluginDelegates!.values.toList(growable: false)) {
      delegate.notifyChanged();
    }
  }

  @override
  @internal
  Iterable<TextDelegate> get textPluginDelegates =>
      _textPluginDelegates?.values ?? const Iterable<TextDelegate>.empty();

  @override
  @internal
  void didChangeTextAnnotations(TextDelegate delegate) {
    _cachedCombinedSemanticsInfos = null;
    _cachedAttributedLabels = null;
    markNeedsSemanticsUpdate();
    if (_textPluginDelegates == null) {
      return;
    }
    for (final TextDelegate other in _textPluginDelegates!.values.toList(growable: false)) {
      if (!identical(other, delegate) && !other.isDisposed) {
        other.notifyChanged();
      }
    }
  }

  @override
  @internal
  void didChangeTextAnchors(TextDelegate delegate) {
    // This paragraph pushes layers exactly while anchors are installed.
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  @internal
  void didChangeTextSelections(TextDelegate delegate) {
    _notifyTextPluginsSelectionChanged();
  }

  // The Selectables of a selection plugin live from didAddText to
  // didRemoveText, and depend on the text and on the registrar. A change of
  // either one therefore re-adds this paragraph to its selection plugin.
  void _resetTextSelectionDelegates() {
    final Map<TextPlugin, TextDelegate>? delegates = _textPluginDelegates;
    if (delegates != null) {
      final List<TextPlugin> selectionPlugins = delegates.keys
          .whereType<TextSelectionPlugin>()
          .toList(growable: false);
      for (final plugin in selectionPlugins) {
        final TextDelegate delegate = delegates.remove(plugin)!;
        delegate.detachPainters();
        if (delegate.hasDispatchedAdd) {
          plugin.didRemoveText(delegate);
        }
        delegate.dispose();
      }
      if (delegates.isEmpty) {
        _textPluginDelegates = null;
      }
    }
    if (attached) {
      _syncTextPluginDelegates();
    }
  }

  // Removes this paragraph from its plugins.
  //
  // With `keepSelection`, the delegate of the selection plugin stays: a
  // selection has to survive its paragraph being detached and attached again,
  // which is what a list does to keep a selected item alive after it has been
  // scrolled out of view. Its Selectables then stay registered, as they are
  // for a paragraph that is merely not painted.
  void _removeAllTextPluginDelegates({bool keepSelection = false}) {
    final Map<TextPlugin, TextDelegate>? delegates = _textPluginDelegates;
    if (delegates == null) {
      return;
    }
    _textPluginDelegates = null;
    Map<TextPlugin, TextDelegate>? keptDelegates;
    for (final MapEntry<TextPlugin, TextDelegate> entry in delegates.entries) {
      final TextDelegate delegate = entry.value;
      delegate.detachPainters();
      if (keepSelection && entry.key is TextSelectionPlugin) {
        (keptDelegates ??= <TextPlugin, TextDelegate>{})[entry.key] = delegate;
        continue;
      }
      if (delegate.hasDispatchedAdd) {
        delegate.plugin.didRemoveText(delegate);
      }
      delegate.dispose();
    }
    _textPluginDelegates = keptDelegates;
  }

  void _disposeTextPluginDelegates() {
    _textPlugins = null;
    _removeAllTextPluginDelegates();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _syncTextPluginDelegates();
    if (_textPluginDelegates != null) {
      var hasUndeliveredNotifications = false;
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        delegate.attachPainters();
        if (!delegate.hasDispatchedAdd || delegate.pendingUpdate || delegate.pendingLayout) {
          hasUndeliveredNotifications = true;
        }
      }
      // A delegate that was kept through the detach (see [detach]) missed its
      // notifications if they were due while this paragraph was detached, and
      // a paragraph that comes back unchanged is not laid out again.
      if (hasUndeliveredNotifications) {
        _scheduleTextPluginFlush();
      }
    }
  }

  @override
  void detach() {
    _removeAllTextPluginDelegates(keepSelection: true);
    super.detach();
  }

  // Each [TextAnchor] of a plugin (such as the anchor of a selection handle)
  // is a layer.
  @override
  bool get alwaysNeedsCompositing => hasTextAnchors(textPluginDelegates);

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
  void dispose() {
    _disposeTextPluginDelegates();
    _textPainter.dispose();
    _textIntrinsicsCache?.dispose();
    super.dispose();
  }

  /// How the text should be aligned horizontally.
  TextAlign get textAlign => _textPainter.textAlign;

  set textAlign(TextAlign value) {
    if (_textPainter.textAlign == value) {
      return;
    }
    _textPainter.textAlign = value;
    markNeedsPaint();
  }

  /// The directionality of the text.
  ///
  /// This decides how the [TextAlign.start], [TextAlign.end], and
  /// [TextAlign.justify] values of [textAlign] are interpreted.
  ///
  /// This is also used to disambiguate how to render bidirectional text. For
  /// example, if the [text] is an English phrase followed by a Hebrew phrase,
  /// in a [TextDirection.ltr] context the English phrase will be on the left
  /// and the Hebrew phrase to its right, while in a [TextDirection.rtl]
  /// context, the English phrase will be on the right and the Hebrew phrase on
  /// its left.
  TextDirection get textDirection => _textPainter.textDirection!;

  set textDirection(TextDirection value) {
    if (_textPainter.textDirection == value) {
      return;
    }
    _textPainter.textDirection = value;
    markNeedsLayout();
  }

  /// Whether the text should break at soft line breaks.
  ///
  /// If false, the glyphs in the text will be positioned as if there was
  /// unlimited horizontal space.
  ///
  /// If [softWrap] is false, [overflow] and [textAlign] may have unexpected
  /// effects.
  bool get softWrap => _softWrap;
  bool _softWrap;

  set softWrap(bool value) {
    if (_softWrap == value) {
      return;
    }
    _softWrap = value;
    markNeedsLayout();
  }

  /// How visual overflow should be handled.
  TextOverflow get overflow => _overflow;
  TextOverflow _overflow;

  set overflow(TextOverflow value) {
    if (_overflow == value) {
      return;
    }
    _overflow = value;
    _textPainter.ellipsis = value == TextOverflow.ellipsis ? _kEllipsis : null;
    markNeedsLayout();
  }

  /// Deprecated. Will be removed in a future version of Flutter. Use
  /// [textScaler] instead.
  ///
  /// The number of font pixels for each logical pixel.
  ///
  /// For example, if the text scale factor is 1.5, text will be 50% larger than
  /// the specified font size.
  @Deprecated(
    'Use textScaler instead. '
    'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
    'This feature was deprecated after v3.12.0-2.0.pre.',
  )
  double get textScaleFactor => _textPainter.textScaleFactor;

  @Deprecated(
    'Use textScaler instead. '
    'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
    'This feature was deprecated after v3.12.0-2.0.pre.',
  )
  set textScaleFactor(double value) {
    textScaler = TextScaler.linear(value);
  }

  /// {@macro flutter.painting.textPainter.textScaler}
  TextScaler get textScaler => _textPainter.textScaler;

  set textScaler(TextScaler value) {
    if (_textPainter.textScaler == value) {
      return;
    }
    _textPainter.textScaler = value;
    _overflowShader = null;
    markNeedsLayout();
  }

  /// The number of device pixels for each logical pixel.
  ///
  /// This is used by some renderers (like WebParagraph on the web) to
  /// regenerate the text bitmap when the scale changes.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;

  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) {
      return;
    }
    _devicePixelRatio = value;
    if (kIsWeb) {
      // The `WebParagraph` implementation renders the paragraph as an image. After a
      // `devicePixelRatio` change, the image needs to be regenerated or it would look blurry.
      markNeedsPaint();
    }
  }

  /// An optional maximum number of lines for the text to span, wrapping if
  /// necessary. If the text exceeds the given number of lines, it will be
  /// truncated according to [overflow] and [softWrap].
  int? get maxLines => _textPainter.maxLines;

  /// The value may be null. If it is not null, then it must be greater than
  /// zero.
  set maxLines(int? value) {
    assert(value == null || value > 0);
    if (_textPainter.maxLines == value) {
      return;
    }
    _textPainter.maxLines = value;
    _overflowShader = null;
    markNeedsLayout();
  }

  /// Used by this paragraph's internal [TextPainter] to select a
  /// locale-specific font.
  ///
  /// In some cases, the same Unicode character may be rendered differently
  /// depending on the locale. For example, the '骨' character is rendered
  /// differently in the Chinese and Japanese locales. In these cases, the
  /// [locale] may be used to select a locale-specific font.
  Locale? get locale => _textPainter.locale;

  /// The value may be null.
  set locale(Locale? value) {
    if (_textPainter.locale == value) {
      return;
    }
    _textPainter.locale = value;
    _overflowShader = null;
    markNeedsLayout();
  }

  /// {@macro flutter.painting.textPainter.strutStyle}
  StrutStyle? get strutStyle => _textPainter.strutStyle;

  /// The value may be null.
  set strutStyle(StrutStyle? value) {
    if (_textPainter.strutStyle == value) {
      return;
    }
    _textPainter.strutStyle = value;
    _overflowShader = null;
    markNeedsLayout();
  }

  /// {@macro flutter.painting.textPainter.textWidthBasis}
  TextWidthBasis get textWidthBasis => _textPainter.textWidthBasis;

  set textWidthBasis(TextWidthBasis value) {
    if (_textPainter.textWidthBasis == value) {
      return;
    }
    _textPainter.textWidthBasis = value;
    _overflowShader = null;
    markNeedsLayout();
  }

  /// {@macro dart.ui.textHeightBehavior}
  ui.TextHeightBehavior? get textHeightBehavior => _textPainter.textHeightBehavior;

  set textHeightBehavior(ui.TextHeightBehavior? value) {
    if (_textPainter.textHeightBehavior == value) {
      return;
    }
    _textPainter.textHeightBehavior = value;
    _overflowShader = null;
    markNeedsLayout();
  }

  /// The color to use when painting the selection.
  ///
  /// Ignored if the text is not selectable (e.g. if [registrar] is null).
  Color? get selectionColor => _selectionColor;
  Color? _selectionColor;

  set selectionColor(Color? value) {
    if (_selectionColor == value) {
      return;
    }
    _selectionColor = value;
    _notifyTextPluginsSelectionChanged();
    if (selections.isNotEmpty) {
      markNeedsPaint();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final List<PlaceholderDimensions> placeholderDimensions = layoutInlineChildren(
      double.infinity,
      (RenderBox child, BoxConstraints constraints) =>
          Size(child.getMinIntrinsicWidth(double.infinity), 0.0),
      ChildLayoutHelper.getDryBaseline,
    );
    return (_textIntrinsics
          ..setPlaceholderDimensions(placeholderDimensions)
          ..layout())
        .minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final List<PlaceholderDimensions> placeholderDimensions = layoutInlineChildren(
      double.infinity,
      // Height and baseline is irrelevant as all text will be laid
      // out in a single line. Therefore, using 0.0 as a dummy for the height.
      (RenderBox child, BoxConstraints constraints) =>
          Size(child.getMaxIntrinsicWidth(double.infinity), 0.0),
      ChildLayoutHelper.getDryBaseline,
    );
    return (_textIntrinsics
          ..setPlaceholderDimensions(placeholderDimensions)
          ..layout())
        .maxIntrinsicWidth;
  }

  /// An estimate of the height of a line in the text. See [TextPainter.preferredLineHeight].
  ///
  /// This does not require the layout to be updated.
  double get preferredLineHeight => _textPainter.preferredLineHeight;

  double _computeIntrinsicHeight(double width) {
    return (_textIntrinsics
          ..setPlaceholderDimensions(
            layoutInlineChildren(
              width,
              ChildLayoutHelper.dryLayoutChild,
              ChildLayoutHelper.getDryBaseline,
            ),
          )
          ..layout(minWidth: width, maxWidth: _adjustMaxWidth(width)))
        .height;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _computeIntrinsicHeight(width);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _computeIntrinsicHeight(width);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  @protected
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final GlyphInfo? glyph = _textPainter.getClosestGlyphForOffset(position);
    // The hit-test can't fall through the horizontal gaps between visually
    // adjacent characters on the same line, even with a large letter-spacing or
    // text justification, as graphemeClusterLayoutBounds.width is the advance
    // width to the next character, so there's no gap between their
    // graphemeClusterLayoutBounds rects.
    final GlyphInfo? hitGlyph =
        glyph != null && glyph.graphemeClusterLayoutBounds.contains(position) ? glyph : null;
    var hitAnnotation = false;
    if (hitGlyph != null && _textPluginDelegates != null) {
      // Plugin annotations stack above authored spans, topmost first, so the
      // gesture arena and the mouse tracker see them in visual order.
      for (final TextAnnotation annotation in textAnnotationsAt(
        _textPluginDelegates!.values,
        hitGlyph.graphemeClusterCodeUnitRange.start,
      )) {
        result.add(HitTestEntry<HitTestTarget>(annotation));
        hitAnnotation = true;
      }
    }
    final InlineSpan? spanHit = hitGlyph != null
        ? _textPainter.text!.getSpanForPosition(
            TextPosition(offset: hitGlyph.graphemeClusterCodeUnitRange.start),
          )
        : null;
    switch (spanHit) {
      case final HitTestTarget span:
        result.add(HitTestEntry(span));
        return true;
      case _:
        return hitTestInlineChildren(result, position) || hitAnnotation;
    }
  }

  bool _needsClipping = false;
  ui.Shader? _overflowShader;

  /// Whether this paragraph currently has a [dart:ui.Shader] for its overflow
  /// effect.
  ///
  /// Used to test this object. Not for use in production.
  @visibleForTesting
  bool get debugHasOverflowShader => _overflowShader != null;

  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    _textPainter.markNeedsLayout();
  }

  // Placeholder dimensions representing the sizes of child inline widgets.
  //
  // These need to be cached because the text painter's placeholder dimensions
  // will be overwritten during intrinsic width/height calculations and must be
  // restored to the original values before final layout and painting.
  List<PlaceholderDimensions>? _placeholderDimensions;

  double _adjustMaxWidth(double maxWidth) {
    return softWrap || overflow == TextOverflow.ellipsis ? maxWidth : double.infinity;
  }

  void _layoutTextWithConstraints(BoxConstraints constraints) {
    _textPainter
      ..setPlaceholderDimensions(_placeholderDimensions)
      ..layout(minWidth: constraints.minWidth, maxWidth: _adjustMaxWidth(constraints.maxWidth));
  }

  @override
  @protected
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final Size size =
        (_textIntrinsics
              ..setPlaceholderDimensions(
                layoutInlineChildren(
                  constraints.maxWidth,
                  ChildLayoutHelper.dryLayoutChild,
                  ChildLayoutHelper.getDryBaseline,
                ),
              )
              ..layout(
                minWidth: constraints.minWidth,
                maxWidth: _adjustMaxWidth(constraints.maxWidth),
              ))
            .size;
    return constraints.constrain(size);
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    assert(!debugNeedsLayout);
    assert(constraints.debugAssertIsValid());
    _layoutTextWithConstraints(constraints);
    // TODO(garyq): Since our metric for ideographic baseline is currently
    // inaccurate and the non-alphabetic baselines are based off of the
    // alphabetic baseline, we use the alphabetic for now to produce correct
    // layouts. We should eventually change this back to pass the `baseline`
    // property when the ideographic baseline is properly implemented
    // (https://github.com/flutter/flutter/issues/22625).
    return _textPainter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  @override
  double computeDryBaseline(covariant BoxConstraints constraints, TextBaseline baseline) {
    assert(constraints.debugAssertIsValid());
    _textIntrinsics
      ..setPlaceholderDimensions(
        layoutInlineChildren(
          constraints.maxWidth,
          ChildLayoutHelper.dryLayoutChild,
          ChildLayoutHelper.getDryBaseline,
        ),
      )
      ..layout(minWidth: constraints.minWidth, maxWidth: _adjustMaxWidth(constraints.maxWidth));
    return _textIntrinsics.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;
    _placeholderDimensions = layoutInlineChildren(
      constraints.maxWidth,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    _layoutTextWithConstraints(constraints);
    positionInlineChildren(_textPainter.inlinePlaceholderBoxes!);

    final Size textSize = _textPainter.size;
    size = constraints.constrain(textSize);

    final bool didOverflowHeight = size.height < textSize.height || _textPainter.didExceedMaxLines;
    final bool didOverflowWidth = size.width < textSize.width;
    // TODO(abarth): We're only measuring the sizes of the line boxes here. If
    // the glyphs draw outside the line boxes, we might think that there isn't
    // visual overflow when there actually is visual overflow. This can become
    // a problem if we start having horizontal overflow and introduce a clip
    // that affects the actual (but undetected) vertical overflow.
    final bool hasVisualOverflow = didOverflowWidth || didOverflowHeight;
    if (hasVisualOverflow) {
      switch (_overflow) {
        case TextOverflow.visible:
          _needsClipping = false;
          _overflowShader = null;
        case TextOverflow.clip:
        case TextOverflow.ellipsis:
          _needsClipping = true;
          _overflowShader = null;
        case TextOverflow.fade:
          _needsClipping = true;
          final fadeSizePainter = TextPainter(
            text: TextSpan(style: _textPainter.text!.style, text: '\u2026'),
            textDirection: textDirection,
            textScaler: textScaler,
            locale: locale,
          )..layout();
          if (didOverflowWidth) {
            final (double fadeStart, double fadeEnd) = switch (textDirection) {
              TextDirection.rtl => (fadeSizePainter.width, 0.0),
              TextDirection.ltr => (size.width - fadeSizePainter.width, size.width),
            };
            _overflowShader = ui.Gradient.linear(
              Offset(fadeStart, 0.0),
              Offset(fadeEnd, 0.0),
              <Color>[const Color(0xFFFFFFFF), const Color(0x00FFFFFF)],
            );
          } else {
            final double fadeEnd = size.height;
            final double fadeStart = fadeEnd - fadeSizePainter.height / 2.0;
            _overflowShader = ui.Gradient.linear(
              Offset(0.0, fadeStart),
              Offset(0.0, fadeEnd),
              <Color>[const Color(0xFFFFFFFF), const Color(0x00FFFFFF)],
            );
          }
          fadeSizePainter.dispose();
      }
    } else {
      _needsClipping = false;
      _overflowShader = null;
    }

    if (_textPluginDelegates != null && _textPluginDelegates!.isNotEmpty) {
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        delegate.hasValidLayout = true;
        delegate.pendingLayout = true;
      }
      _scheduleTextPluginFlush();
    }
  }

  void _paintWithCustomPainter(Canvas canvas, Offset offset, CustomPainter painter) {
    late int debugPreviousCanvasSaveCount;
    canvas.save();
    assert(() {
      debugPreviousCanvasSaveCount = canvas.getSaveCount();
      return true;
    }());
    if (offset != Offset.zero) {
      canvas.translate(offset.dx, offset.dy);
    }
    painter.paint(canvas, size);
    assert(() {
      final int debugNewCanvasSaveCount = canvas.getSaveCount();
      if (debugNewCanvasSaveCount > debugPreviousCanvasSaveCount) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'The $painter custom painter called canvas.save() or canvas.saveLayer() at least '
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
            'The $painter custom painter called canvas.restore() '
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

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    defaultApplyPaintTransform(child, transform);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Text alignment only triggers repaint so it's possible the text layout has
    // been invalidated but performLayout wasn't called at this point. Make sure
    // the TextPainter has a valid layout.
    _layoutTextWithConstraints(constraints);
    assert(() {
      if (debugRepaintTextRainbowEnabled) {
        final paint = Paint()..color = debugCurrentRepaintColor.toColor();
        context.canvas.drawRect(offset & size, paint);
      }
      return true;
    }());

    if (_textPluginDelegates != null &&
        _textPluginDelegates!.values.any(
          (TextDelegate delegate) => delegate.backgroundPainter != null,
        )) {
      if (_needsClipping) {
        context.canvas.save();
        context.canvas.clipRect(offset & size);
      }
      // In paint order. The selection highlight is the background of a
      // [TextSelectionPlugin], whose paint order puts it above the
      // decorations of ordinary plugins.
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        final CustomPainter? backgroundPainter = delegate.backgroundPainter;
        if (backgroundPainter != null) {
          _paintWithCustomPainter(context.canvas, offset, backgroundPainter);
        }
      }
      if (_needsClipping) {
        context.canvas.restore();
      }
    }

    if (_needsClipping) {
      final Rect bounds = offset & size;
      if (_overflowShader != null) {
        // This layer limits what the shader below blends with to be just the
        // text (as opposed to the text and its background).
        context.canvas.saveLayer(bounds, Paint());
      } else {
        context.canvas.save();
      }
      context.canvas.clipRect(bounds);
    }

    assert(() {
      _textPainter.debugPaintTextLayoutBoxes = debugPaintTextLayoutBoxes;
      return true;
    }());

    _textPainter.paint(context.canvas, offset);

    paintInlineChildren(context, offset);

    if (_needsClipping) {
      if (_overflowShader != null) {
        context.canvas.translate(offset.dx, offset.dy);
        final paint = Paint()
          ..blendMode = BlendMode.modulate
          ..shader = _overflowShader;
        context.canvas.drawRect(Offset.zero & size, paint);
      }
      context.canvas.restore();
    }

    if (_textPluginDelegates != null &&
        _textPluginDelegates!.values.any(
          (TextDelegate delegate) => delegate.foregroundPainter != null,
        )) {
      if (_needsClipping) {
        context.canvas.save();
        context.canvas.clipRect(offset & size);
      }
      for (final TextDelegate delegate in _textPluginDelegates!.values) {
        final CustomPainter? foregroundPainter = delegate.foregroundPainter;
        if (foregroundPainter != null) {
          _paintWithCustomPainter(context.canvas, offset, foregroundPainter);
        }
      }
      if (_needsClipping) {
        context.canvas.restore();
      }
    }

    // Layers that widgets in the overlay follow, such as selection handles.
    pushTextAnchorLayers(context, offset, textPluginDelegates);
  }

  /// Returns the offset at which to paint the caret.
  ///
  /// Valid only after [layout].
  Offset getOffsetForCaret(TextPosition position, Rect caretPrototype) {
    assert(!debugNeedsLayout);
    _layoutTextWithConstraints(constraints);
    return _textPainter.getOffsetForCaret(position, caretPrototype);
  }

  /// {@macro flutter.painting.textPainter.getFullHeightForCaret}
  ///
  /// Valid only after [layout].
  double getFullHeightForCaret(TextPosition position) {
    assert(!debugNeedsLayout);
    _layoutTextWithConstraints(constraints);
    return _textPainter.getFullHeightForCaret(position, Rect.zero);
  }

  /// Returns a list of rects that bound the given selection.
  ///
  /// The [boxHeightStyle] and [boxWidthStyle] arguments may be used to select
  /// the shape of the [TextBox]es. These properties default to
  /// [ui.BoxHeightStyle.tight] and [ui.BoxWidthStyle.tight] respectively.
  ///
  /// A given selection might have more than one rect if the [RenderParagraph]
  /// contains multiple [InlineSpan]s or bidirectional text, because logically
  /// contiguous text might not be visually contiguous.
  ///
  /// Valid only after [layout].
  ///
  /// See also:
  ///
  ///  * [TextPainter.getBoxesForSelection], the method in TextPainter to get
  ///    the equivalent boxes.
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  }) {
    assert(!debugNeedsLayout);
    _layoutTextWithConstraints(constraints);
    return _textPainter.getBoxesForSelection(
      selection,
      boxHeightStyle: boxHeightStyle,
      boxWidthStyle: boxWidthStyle,
    );
  }

  /// Returns the position within the text for the given pixel offset.
  ///
  /// Valid only after [layout].
  TextPosition getPositionForOffset(Offset offset) {
    assert(!debugNeedsLayout);
    _layoutTextWithConstraints(constraints);
    return _textPainter.getPositionForOffset(offset);
  }

  /// Returns the text range of the word at the given offset. Characters not
  /// part of a word, such as spaces, symbols, and punctuation, have word breaks
  /// on both sides. In such cases, this method will return a text range that
  /// contains the given text position.
  ///
  /// Word boundaries are defined more precisely in Unicode Standard Annex #29
  /// <http://www.unicode.org/reports/tr29/#Word_Boundaries>.
  ///
  /// Valid only after [layout].
  TextRange getWordBoundary(TextPosition position) {
    assert(!debugNeedsLayout);
    _layoutTextWithConstraints(constraints);
    return _textPainter.getWordBoundary(position);
  }

  /// Returns the text range of the line that contains the given position.
  ///
  /// Valid only after [layout].
  ///
  /// See also:
  ///
  ///  * [TextPainter.getLineBoundary], the method in TextPainter to get the
  ///    equivalent range.
  TextRange getLineBoundary(TextPosition position) {
    assert(!debugNeedsLayout);
    _layoutTextWithConstraints(constraints);
    return _textPainter.getLineBoundary(position);
  }

  /// Returns the metrics of every line of the text as laid out.
  ///
  /// Valid only after [layout].
  ///
  /// See also:
  ///
  ///  * [TextPainter.computeLineMetrics], the method in TextPainter to get
  ///    the equivalent metrics.
  List<ui.LineMetrics> computeLineMetrics() {
    assert(!debugNeedsLayout);
    _layoutTextWithConstraints(constraints);
    return _textPainter.computeLineMetrics();
  }

  /// {@macro flutter.painting.TextPainter.wordBoundaries}
  WordBoundary get wordBoundaries => _textPainter.wordBoundaries;

  /// Returns the size of the text as laid out.
  ///
  /// This can differ from [size] if the text overflowed or if the [constraints]
  /// provided by the parent [RenderObject] forced the layout to be bigger than
  /// necessary for the given [text].
  ///
  /// This returns the [TextPainter.size] of the underlying [TextPainter].
  ///
  /// Valid only after [layout].
  Size get textSize {
    assert(!debugNeedsLayout);
    return _textPainter.size;
  }

  /// Whether the text was truncated or ellipsized as laid out.
  ///
  /// This returns the [TextPainter.didExceedMaxLines] of the underlying [TextPainter].
  ///
  /// Valid only after [layout].
  bool get didExceedMaxLines {
    assert(!debugNeedsLayout);
    return _textPainter.didExceedMaxLines;
  }

  /// Collected during [describeSemanticsConfiguration], used by
  /// [assembleSemanticsNode].
  List<InlineSpanSemanticsInformation>? _semanticsInfo;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final List<InlineSpanSemanticsInformation> spanInfo = text.getSemanticsInformation();
    _semanticsInfo = _textPluginDelegates == null
        ? spanInfo
        : applyTextAnnotationsToSemantics(spanInfo, _textPluginDelegates!.values);
    var needsAssembleSemanticsNode = false;
    var needsChildConfigurationsDelegate = false;
    for (final InlineSpanSemanticsInformation info in _semanticsInfo!) {
      if (info.requiresOwnNode && !info.isPlaceholder) {
        needsAssembleSemanticsNode = true;
        break;
      }
      needsChildConfigurationsDelegate = needsChildConfigurationsDelegate || info.isPlaceholder;
    }

    if (needsAssembleSemanticsNode) {
      config.explicitChildNodes = true;
      config.isSemanticBoundary = true;
    } else if (needsChildConfigurationsDelegate) {
      config.childConfigurationsDelegate = _childSemanticsConfigurationsDelegate;
    } else {
      if (_cachedAttributedLabels == null) {
        final buffer = StringBuffer();
        var offset = 0;
        final attributes = <StringAttribute>[];
        for (final InlineSpanSemanticsInformation info in _semanticsInfo!) {
          final String label = info.semanticsLabel ?? info.text;
          for (final StringAttribute infoAttribute in info.stringAttributes) {
            final TextRange originalRange = infoAttribute.range;
            attributes.add(
              infoAttribute.copy(
                range: TextRange(
                  start: offset + originalRange.start,
                  end: offset + originalRange.end,
                ),
              ),
            );
          }
          buffer.write(label);
          offset += label.length;
        }
        _cachedAttributedLabels = <AttributedString>[
          AttributedString(buffer.toString(), attributes: attributes),
        ];
      }
      config.attributedLabel = _cachedAttributedLabels![0];
      config.textDirection = textDirection;
    }
  }

  ChildSemanticsConfigurationsResult _childSemanticsConfigurationsDelegate(
    List<SemanticsConfiguration> childConfigs,
  ) {
    final builder = ChildSemanticsConfigurationsResultBuilder();
    var placeholderIndex = 0;
    var childConfigsIndex = 0;
    var attributedLabelCacheIndex = 0;
    _cachedCombinedSemanticsInfos ??= combineSemanticsInfo(_semanticsInfo!);
    for (final InlineSpanSemanticsInformation info in _cachedCombinedSemanticsInfos!) {
      if (info.isPlaceholder) {
        // Mark every childConfig belongs to this placeholder to merge up group.
        while (childConfigsIndex < childConfigs.length &&
            _childConfigBelongsToPlaceholder(childConfigs[childConfigsIndex], placeholderIndex)) {
          builder.markAsMergeUp(childConfigs[childConfigsIndex]);
          childConfigsIndex += 1;
        }
        placeholderIndex += 1;
      } else {
        builder.markAsMergeUp(_createSemanticsConfigForTextInfo(info, attributedLabelCacheIndex));
        attributedLabelCacheIndex += 1;
      }
    }
    return builder.build();
  }

  /// Returns whether [childConfig] belongs to the placeholder at
  /// [placeholderIndex] in this paragraph.
  ///
  /// Nested paragraphs may inherit [PlaceholderSpanIndexSemanticsTag]s from
  /// ancestors with colliding indexes. The first placeholder tag is the one
  /// added by this paragraph, so later inherited tags must not decide ownership
  /// here.
  static bool _childConfigBelongsToPlaceholder(
    SemanticsConfiguration childConfig,
    int placeholderIndex,
  ) {
    final Iterable<SemanticsTag>? tags = childConfig.tagsForChildren;
    if (tags == null) {
      return false;
    }
    for (final SemanticsTag tag in tags) {
      if (tag is PlaceholderSpanIndexSemanticsTag) {
        return tag.index == placeholderIndex;
      }
    }
    return false;
  }

  SemanticsConfiguration _createSemanticsConfigForTextInfo(
    InlineSpanSemanticsInformation textInfo,
    int cacheIndex,
  ) {
    assert(!textInfo.requiresOwnNode);
    final List<AttributedString> cachedStrings = _cachedAttributedLabels ??= <AttributedString>[];
    assert(cacheIndex <= cachedStrings.length);
    final bool hasCache = cacheIndex < cachedStrings.length;

    late AttributedString attributedLabel;
    if (hasCache) {
      attributedLabel = cachedStrings[cacheIndex];
    } else {
      assert(cachedStrings.length == cacheIndex);
      attributedLabel = AttributedString(
        textInfo.semanticsLabel ?? textInfo.text,
        attributes: textInfo.stringAttributes,
      );
      cachedStrings.add(attributedLabel);
    }
    return SemanticsConfiguration()
      ..textDirection = textDirection
      ..attributedLabel = attributedLabel;
  }

  // Caches [SemanticsNode]s created during [assembleSemanticsNode] so they
  // can be re-used when [assembleSemanticsNode] is called again. This ensures
  // stable ids for the [SemanticsNode]s of [TextSpan]s across
  // [assembleSemanticsNode] invocations.
  Map<Key, SemanticsNode>? _cachedChildNodes;

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    assert(_semanticsInfo != null && _semanticsInfo!.isNotEmpty);
    final newChildren = <SemanticsNode>[];
    TextDirection currentDirection = textDirection;
    Rect currentRect;
    var ordinal = 0.0;
    var start = 0;
    var placeholderIndex = 0;
    var childIndex = 0;
    RenderBox? child = firstChild;
    final newChildCache = <Key, SemanticsNode>{};
    _cachedCombinedSemanticsInfos ??= combineSemanticsInfo(_semanticsInfo!);
    for (final InlineSpanSemanticsInformation info in _cachedCombinedSemanticsInfos!) {
      final selection = TextSelection(baseOffset: start, extentOffset: start + info.text.length);
      start += info.text.length;

      if (info.isPlaceholder) {
        // A placeholder span may have 0 to multiple semantics nodes, we need
        // to annotate all of the semantics nodes belong to this span.
        while (children.length > childIndex &&
            children
                .elementAt(childIndex)
                .isTagged(PlaceholderSpanIndexSemanticsTag(placeholderIndex))) {
          final SemanticsNode childNode = children.elementAt(childIndex);
          final parentData = child!.parentData! as TextParentData;
          // parentData.scale may be null if the render object is truncated.
          if (parentData.offset != null) {
            newChildren.add(childNode);
          }
          childIndex += 1;
        }
        child = childAfter(child!);
        placeholderIndex += 1;
      } else {
        final initialDirection = currentDirection;
        final List<ui.TextBox> rects = getBoxesForSelection(selection);
        if (rects.isEmpty) {
          continue;
        }
        Rect rect = rects.first.toRect();
        currentDirection = rects.first.direction;
        for (final ui.TextBox textBox in rects.skip(1)) {
          rect = rect.expandToInclude(textBox.toRect());
          currentDirection = textBox.direction;
        }
        // Any of the text boxes may have had infinite dimensions.
        // We shouldn't pass infinite dimensions up to the bridges.
        rect = Rect.fromLTWH(
          math.max(0.0, rect.left),
          math.max(0.0, rect.top),
          math.min(rect.width, constraints.maxWidth),
          math.min(rect.height, constraints.maxHeight),
        );
        // round the current rectangle to make this API testable and add some
        // padding so that the accessibility rects do not overlap with the text.
        currentRect = Rect.fromLTRB(
          rect.left.floorToDouble() - 4.0,
          rect.top.floorToDouble() - 4.0,
          rect.right.ceilToDouble() + 4.0,
          rect.bottom.ceilToDouble() + 4.0,
        );
        final configuration = SemanticsConfiguration()
          ..sortKey = OrdinalSortKey(ordinal++)
          ..textDirection = initialDirection
          ..identifier = info.semanticsIdentifier ?? ''
          ..attributedLabel = AttributedString(
            info.semanticsLabel ?? info.text,
            attributes: info.stringAttributes,
          );
        if (info case final TextAnnotationSemanticsInformation annotated) {
          annotated.annotation.describeSemanticsConfiguration(
            configuration,
            fallbackRecognizer: info.recognizer,
          );
        } else {
          applyRecognizerSemantics(configuration, info.recognizer);
        }
        if (node.parentPaintClipRect != null) {
          final Rect paintRect = node.parentPaintClipRect!.intersect(currentRect);
          configuration.isHidden = paintRect.isEmpty && !currentRect.isEmpty;
        }
        final SemanticsNode newChild;
        if (_cachedChildNodes?.isNotEmpty ?? false) {
          newChild = _cachedChildNodes!.remove(_cachedChildNodes!.keys.first)!;
        } else {
          final key = UniqueKey();
          newChild = SemanticsNode(key: key, showOnScreen: _createShowOnScreenFor(key));
        }
        newChild
          ..updateWith(config: configuration)
          ..rect = currentRect;
        newChildCache[newChild.key!] = newChild;
        newChildren.add(newChild);
      }
    }
    // Makes sure we annotated all of the semantics children.
    assert(childIndex == children.length);
    assert(child == null);

    _cachedChildNodes = newChildCache;
    node.updateWith(config: config, childrenInInversePaintOrder: newChildren);
  }

  VoidCallback? _createShowOnScreenFor(Key key) {
    return () {
      final SemanticsNode node = _cachedChildNodes![key]!;
      showOnScreen(descendant: this, rect: node.rect);
    };
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _cachedChildNodes = null;
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    return <DiagnosticsNode>[
      text.toDiagnosticsNode(name: 'text', style: DiagnosticsTreeStyle.transition),
    ];
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<TextAlign>('textAlign', textAlign));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection));
    properties.add(
      FlagProperty(
        'softWrap',
        value: softWrap,
        ifTrue: 'wrapping at box width',
        ifFalse: 'no wrapping except at line break characters',
        showName: true,
      ),
    );
    properties.add(EnumProperty<TextOverflow>('overflow', overflow));
    properties.add(
      DiagnosticsProperty<TextScaler>('textScaler', textScaler, defaultValue: TextScaler.noScaling),
    );
    properties.add(DiagnosticsProperty<Locale>('locale', locale, defaultValue: null));
    properties.add(IntProperty('maxLines', maxLines, ifNull: 'unlimited'));
    properties.add(DoubleProperty('devicePixelRatio', devicePixelRatio, defaultValue: 1.0));
  }
}
