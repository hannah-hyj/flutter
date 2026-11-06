// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/widgets.dart';
library;

import 'dart:collection' show SplayTreeSet;
import 'dart:math' as math;
import 'dart:ui'
    as ui
    show
        BoxHeightStyle,
        BoxWidthStyle,
        StringAttribute,
        TextBox,
        TextDirection,
        TextPosition,
        TextRange;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

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
/// laid out, and removed within its scope.
///
/// Each text widget in the scope is represented by a [TextDelegate], which
/// allows the plugin to query the displayed string, query layout metrics (such
/// as [TextDelegate.getBoxesForSelection]), attach a
/// [TextDelegate.backgroundPainter] or [TextDelegate.foregroundPainter], and
/// make ranges interactive and accessible with [TextDelegate.annotations].
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
///  * [TextAnnotation], which describes how a range of text behaves (taps,
///    mouse cursor, hover) and what it means to assistive technology.
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

  /// The relative order of this plugin compared to other active [TextPlugin]s
  /// on the same text widget.
  ///
  /// Plugins with a lower [paintOrder] paint first (further in the
  /// background). When [TextAnnotation]s of different plugins overlap, the
  /// annotation of the plugin with the higher [paintOrder] is on top: it wins
  /// hit testing (and therefore taps), provides the mouse cursor, and is the
  /// one described to assistive technology. When two plugins have the same
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
}

/// A span-shaped overlay that a [TextPlugin] attaches to a character [range]
/// of a text widget.
///
/// A [TextAnnotation] describes how a range *behaves* and what it *means*
/// without mutating the [InlineSpan] tree or affecting layout. It is the
/// plugin counterpart of a [TextSpan] with a [TextSpan.recognizer]: from the
/// same declaration the host ([RenderParagraph], [RenderEditable], or a
/// [TextDelegateHostMixin]) derives
///
///  * **pointer input**: [onTap] and [onLongPress] are backed by gesture
///    recognizers owned by the annotation, so taps compete in the gesture
///    arena like any other gesture (a drag that starts on the range scrolls,
///    and at most one annotation wins a tap). For other gestures, such as
///    drags, provide a plugin-owned [recognizer] instead, exactly like
///    [TextSpan.recognizer];
///  * **mouse**: [cursor], [onEnter], [onHover], and [onExit], like
///    [TextSpan.mouseCursor], [MouseRegion.onHover], [TextSpan.onEnter], and
///    [TextSpan.onExit];
///  * **semantics**: an annotation with an action, a [semanticsLabel], or a
///    [linkUrl] is exposed to assistive technology. Interactive annotations get
///    their own [SemanticsNode] (a link when [linkUrl] is set, otherwise a
///    button), while a [semanticsLabel] alone only replaces the spoken text;
///  * **keyboard focus**: inside a [TextPluginScope], interactive annotations
///    on static text are reachable with Tab and activated with Enter or Space.
///
/// Ranges are UTF-16 offsets into [TextDelegate.text]. The annotations of a
/// single plugin on a single text widget must not overlap. Where annotations
/// of *different* plugins overlap, the annotation of the plugin with the
/// highest [TextPlugin.paintOrder] (the topmost one, matching the visual
/// stacking order) wins for hit testing, mouse cursor, and semantics.
///
/// Annotations are typically created in [TextPlugin.didAddText] and
/// [TextPlugin.didUpdateText]. A [key] lets the framework recognize the same
/// logical annotation across re-scans (for example, to preserve keyboard focus
/// while the text around a link changes); without one, annotations are
/// matched by [range], [linkUrl], and [semanticsLabel].
class TextAnnotation with Diagnosticable implements HitTestTarget, MouseTrackerAnnotation {
  /// Creates an annotation for [range].
  ///
  /// [range] must be valid, normalized, and non-empty.
  TextAnnotation({
    required this.range,
    this.key,
    this.onTap,
    this.onLongPress,
    this.recognizer,
    this.cursor = MouseCursor.defer,
    this.onEnter,
    this.onHover,
    this.onExit,
    this.semanticsLabel,
    this.linkUrl,
  }) : assert(range.isValid && range.isNormalized && !range.isCollapsed);

  /// The annotated character range, in UTF-16 offsets of [TextDelegate.text].
  final ui.TextRange range;

  /// Identifies this annotation across re-scans of the same text.
  ///
  /// Defaults to the combination of [range], [linkUrl], and [semanticsLabel].
  final Object? key;

  /// Called when the range is tapped, activated from the keyboard, or
  /// activated by assistive technology.
  ///
  /// Backed by a [TapGestureRecognizer] owned by this annotation.
  final VoidCallback? onTap;

  /// Called when the range is long-pressed.
  ///
  /// Backed by a [LongPressGestureRecognizer] owned by this annotation.
  final VoidCallback? onLongPress;

  /// A plugin-owned gesture recognizer that receives pointers landing on the
  /// range, in addition to (or instead of) [onTap] and [onLongPress].
  ///
  /// Use this for gestures the callbacks do not cover, or to decide per
  /// pointer whether to compete at all (for example, a
  /// [TapGestureRecognizer] whose [GestureRecognizer.isPointerAllowed] only
  /// accepts modifier-clicks inside editable text). As with
  /// [TextSpan.recognizer], the plugin is responsible for disposing it.
  final GestureRecognizer? recognizer;

  /// The mouse cursor shown while hovering over the range.
  ///
  /// Defaults to [MouseCursor.defer], which lets the cursor of a lower
  /// annotation or of the text widget itself apply.
  @override
  final MouseCursor cursor;

  /// Called when a mouse pointer enters the range.
  @override
  final PointerEnterEventListener? onEnter;

  /// Called when a mouse pointer moves within the range without any buttons
  /// pressed, for example to position a tooltip that follows the pointer.
  ///
  /// Unlike [onEnter] and [onExit], this is delivered through the hit-test
  /// path, so it only fires while the pointer is over the range's glyphs.
  final PointerHoverEventListener? onHover;

  /// Called when a mouse pointer exits the range.
  @override
  final PointerExitEventListener? onExit;

  /// Replaces the text of the range for assistive technology.
  final String? semanticsLabel;

  /// Marks the range as a link to this URL for assistive technology.
  final Uri? linkUrl;

  /// Whether this annotation responds to pointer input.
  bool get isInteractive => onTap != null || onLongPress != null || recognizer != null;

  /// The callback assistive technology and the keyboard use to activate this
  /// annotation.
  ///
  /// This is [onTap], or the tap callback of [recognizer] when it is a
  /// [TapGestureRecognizer] or [DoubleTapGestureRecognizer].
  VoidCallback? get activationCallback {
    return onTap ??
        switch (recognizer) {
          TapGestureRecognizer(:final VoidCallback? onTap) => onTap,
          DoubleTapGestureRecognizer(:final VoidCallback? onDoubleTap) => onDoubleTap,
          _ => null,
        };
  }

  VoidCallback? get _longPressCallback {
    return onLongPress ??
        switch (recognizer) {
          LongPressGestureRecognizer(:final GestureLongPressCallback? onLongPress) => onLongPress,
          _ => null,
        };
  }

  /// Whether this annotation is exposed as its own [SemanticsNode].
  bool get requiresOwnSemanticsNode =>
      activationCallback != null || _longPressCallback != null || linkUrl != null;

  /// Whether this annotation changes the semantics tree at all.
  bool get affectsSemantics => requiresOwnSemanticsNode || semanticsLabel != null;

  /// The identity used to match this annotation with its predecessor when a
  /// plugin re-scans the text: [key] if provided.
  Object get identity => key ?? (range, linkUrl, semanticsLabel);

  /// The [TextDelegate] this annotation is currently installed on, if any.
  TextDelegate? get delegate => _delegate;
  TextDelegate? _delegate;

  TapGestureRecognizer? _tapRecognizer;
  LongPressGestureRecognizer? _longPressRecognizer;

  /// Whether this annotation currently has keyboard focus.
  ///
  /// Maintained by [TextPluginScope]; reported to assistive technology as
  /// [SemanticsConfiguration.isFocused].
  bool get isFocused => _isFocused;
  bool _isFocused = false;
  @internal
  set isFocused(bool value) {
    if (_isFocused == value) {
      return;
    }
    _isFocused = value;
    _delegate?.renderObject.markNeedsSemanticsUpdate();
  }

  /// Requests keyboard focus for this annotation, if it is focusable.
  ///
  /// Set by [TextPluginScope] when a focus node exists for this annotation.
  @internal
  VoidCallback? get focusRequestHandler => _focusRequestHandler;
  VoidCallback? _focusRequestHandler;
  @internal
  set focusRequestHandler(VoidCallback? value) {
    if (_focusRequestHandler == value) {
      return;
    }
    _focusRequestHandler = value;
    _delegate?.renderObject.markNeedsSemanticsUpdate();
  }

  /// Whether this annotation can receive keyboard focus.
  bool get isFocusable => _focusRequestHandler != null;

  /// Activates this annotation as if it were tapped.
  ///
  /// Used for keyboard activation (Enter or Space) and by assistive
  /// technology.
  void activate() {
    activationCallback?.call();
  }

  @override
  bool get validForMouseTracker => _delegate != null;

  @override
  void handleEvent(PointerEvent event, HitTestEntry<HitTestTarget> entry) {
    if (_delegate == null) {
      return;
    }
    switch (event) {
      case PointerHoverEvent():
        onHover?.call(event);
      case PointerDownEvent():
        if (onTap != null) {
          (_tapRecognizer ??= TapGestureRecognizer(
            debugOwner: this,
          )..onTap = onTap).addPointer(event);
        }
        if (onLongPress != null) {
          (_longPressRecognizer ??= LongPressGestureRecognizer(
            debugOwner: this,
          )..onLongPress = onLongPress).addPointer(event);
        }
        recognizer?.addPointer(event);
      default:
        break;
    }
  }

  void _attach(TextDelegate delegate) {
    assert(
      _delegate == null || identical(_delegate, delegate),
      'A TextAnnotation can only be installed on one TextDelegate at a time.',
    );
    _delegate = delegate;
  }

  void _detach() {
    _delegate = null;
    _tapRecognizer?.dispose();
    _tapRecognizer = null;
    _longPressRecognizer?.dispose();
    _longPressRecognizer = null;
  }

  /// Describes this annotation on the [SemanticsConfiguration] of its node.
  ///
  /// [fallbackRecognizer] is the recognizer of an authored [TextSpan] covered
  /// by this annotation; it is used when the annotation itself has no action.
  @internal
  void describeSemanticsConfiguration(
    SemanticsConfiguration configuration, {
    GestureRecognizer? fallbackRecognizer,
  }) {
    final VoidCallback? tap = activationCallback;
    final VoidCallback? longPress = _longPressCallback;
    if (tap == null && longPress == null) {
      applyRecognizerSemantics(configuration, fallbackRecognizer);
    } else {
      if (tap != null) {
        configuration.onTap = tap;
      }
      if (longPress != null) {
        configuration.onLongPress = longPress;
      }
    }
    if (linkUrl != null) {
      configuration
        ..isLink = true
        ..linkUrl = linkUrl;
    } else if (tap != null) {
      configuration.isButton = true;
    }
    if (isFocusable) {
      configuration
        ..isFocusable = true
        ..isFocused = isFocused;
      // Mirrors Focus: iOS VoiceOver handles focus itself.
      if (defaultTargetPlatform != TargetPlatform.iOS) {
        configuration.onFocus = _focusRequestHandler;
      }
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ui.TextRange>('range', range));
    properties.add(DiagnosticsProperty<Object>('key', key, defaultValue: null));
    properties.add(FlagProperty('interactive', value: isInteractive, ifTrue: 'interactive'));
    properties.add(DiagnosticsProperty<Uri>('linkUrl', linkUrl, defaultValue: null));
    properties.add(StringProperty('semanticsLabel', semanticsLabel, defaultValue: null));
    properties.add(
      DiagnosticsProperty<MouseCursor>('cursor', cursor, defaultValue: MouseCursor.defer),
    );
    properties.add(FlagProperty('focused', value: isFocused, ifTrue: 'focused'));
  }
}

/// Applies the semantics of an authored [TextSpan.recognizer] to
/// [configuration], matching the behavior of [RenderParagraph].
@internal
void applyRecognizerSemantics(SemanticsConfiguration configuration, GestureRecognizer? recognizer) {
  switch (recognizer) {
    case TapGestureRecognizer(onTap: final VoidCallback? handler):
    case DoubleTapGestureRecognizer(onDoubleTap: final VoidCallback? handler):
      if (handler != null) {
        configuration.onTap = handler;
        configuration.isLink = true;
      }
    case LongPressGestureRecognizer(onLongPress: final GestureLongPressCallback? onLongPress):
      if (onLongPress != null) {
        configuration.onLongPress = onLongPress;
      }
    case null:
      break;
    default:
      assert(false, '${recognizer.runtimeType} is not supported.');
  }
}

/// The interface a render object implements to host [TextDelegate]s.
///
/// Implemented by [RenderParagraph], [RenderEditable], and
/// [TextDelegateHostMixin].
@internal
abstract interface class TextPluginHost {
  /// The active delegates of this host in paint order (bottom-most first).
  Iterable<TextDelegate> get textPluginDelegates;

  /// Called by [delegate] after its [TextDelegate.annotations] changed.
  void didChangeTextAnnotations(TextDelegate delegate);
}

/// Returns the [TextAnnotation]s covering the code unit at [offset], topmost
/// first.
///
/// [delegates] must be in paint order (bottom-most first), as returned by
/// [TextPluginHost.textPluginDelegates].
@internal
List<TextAnnotation> textAnnotationsAt(Iterable<TextDelegate> delegates, int offset) {
  List<TextAnnotation>? hits;
  for (final delegate in delegates) {
    for (final TextAnnotation annotation in delegate.annotations) {
      if (annotation.range.start > offset) {
        break;
      }
      if (offset < annotation.range.end) {
        (hits ??= <TextAnnotation>[]).add(annotation);
        break;
      }
    }
  }
  if (hits == null) {
    return const <TextAnnotation>[];
  }
  return hits.reversed.toList(growable: false);
}

/// Semantics information for a run of text covered by a [TextAnnotation].
///
/// Produced by [applyTextAnnotationsToSemantics] and consumed by the
/// `assembleSemanticsNode` implementations of the hosts.
@internal
class TextAnnotationSemanticsInformation extends InlineSpanSemanticsInformation {
  /// Wraps [info] (or a slice of it) with [annotation].
  TextAnnotationSemanticsInformation(
    super.text, {
    required this.annotation,
    String? semanticsLabel,
    super.semanticsIdentifier,
    List<ui.StringAttribute> stringAttributes = const <ui.StringAttribute>[],
    super.recognizer,
  }) : super(
         semanticsLabel: annotation.semanticsLabel ?? semanticsLabel,
         // Attributes are expressed in offsets of the original label, which
         // the annotation may have replaced.
         stringAttributes: annotation.semanticsLabel == null
             ? stringAttributes
             : const <ui.StringAttribute>[],
       );

  /// The annotation covering this run of text.
  final TextAnnotation annotation;

  @override
  bool get requiresOwnNode => super.requiresOwnNode || annotation.requiresOwnSemanticsNode;

  @override
  bool operator ==(Object other) {
    return other is TextAnnotationSemanticsInformation &&
        identical(other.annotation, annotation) &&
        super == other;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, annotation);
}

/// Splits [infos] at the boundaries of the semantics-affecting
/// [TextAnnotation]s installed on [delegates], so that every run covered by an
/// annotation becomes a [TextAnnotationSemanticsInformation].
///
/// The concatenated `text` of [infos] must equal [TextDelegate.text] (the
/// contract of [InlineSpan.getSemanticsInformation]), which puts annotation
/// ranges and semantics runs in the same coordinate space. Placeholders are
/// never annotated. A run that cannot be split (one with its own
/// `semanticsLabel`, `semanticsIdentifier`, or `recognizer`) is annotated as a
/// whole by the topmost annotation overlapping it.
///
/// [delegates] must be in paint order (bottom-most first).
@internal
List<InlineSpanSemanticsInformation> applyTextAnnotationsToSemantics(
  List<InlineSpanSemanticsInformation> infos,
  Iterable<TextDelegate> delegates,
) {
  // Topmost first.
  final stack = <TextAnnotation>[
    for (final TextDelegate delegate in delegates.toList(growable: false).reversed)
      for (final TextAnnotation annotation in delegate.annotations)
        if (annotation.affectsSemantics) annotation,
  ];
  if (stack.isEmpty) {
    return infos;
  }

  TextAnnotation? topmostOverlapping(int start, int end) {
    for (final annotation in stack) {
      if (annotation.range.start < end && start < annotation.range.end) {
        return annotation;
      }
    }
    return null;
  }

  final result = <InlineSpanSemanticsInformation>[];
  var start = 0;
  for (final info in infos) {
    final int end = start + info.text.length;
    if (info.isPlaceholder || info.text.isEmpty) {
      result.add(info);
    } else if (info.semanticsLabel != null ||
        info.semanticsIdentifier != null ||
        info.recognizer != null) {
      final TextAnnotation? annotation = topmostOverlapping(start, end);
      result.add(
        annotation == null
            ? info
            : TextAnnotationSemanticsInformation(
                info.text,
                annotation: annotation,
                semanticsLabel: info.semanticsLabel,
                semanticsIdentifier: info.semanticsIdentifier,
                stringAttributes: info.stringAttributes,
                recognizer: info.recognizer,
              ),
      );
    } else {
      final cuts = SplayTreeSet<int>()
        ..add(start)
        ..add(end);
      for (final annotation in stack) {
        if (annotation.range.start < end && start < annotation.range.end) {
          cuts.add(annotation.range.start.clamp(start, end));
          cuts.add(annotation.range.end.clamp(start, end));
        }
      }
      var segmentStart = start;
      for (final int segmentEnd in cuts.skip(1)) {
        final int localStart = segmentStart - start;
        final int localEnd = segmentEnd - start;
        final String segmentText = info.text.substring(localStart, localEnd);
        final attributes = <ui.StringAttribute>[
          for (final ui.StringAttribute attribute in info.stringAttributes)
            if (attribute.range.start < localEnd && localStart < attribute.range.end)
              attribute.copy(
                range: ui.TextRange(
                  start: math.max(attribute.range.start, localStart) - localStart,
                  end: math.min(attribute.range.end, localEnd) - localStart,
                ),
              ),
        ];
        final TextAnnotation? annotation = topmostOverlapping(segmentStart, segmentEnd);
        result.add(
          annotation == null
              ? InlineSpanSemanticsInformation(segmentText, stringAttributes: attributes)
              : TextAnnotationSemanticsInformation(
                  segmentText,
                  annotation: annotation,
                  stringAttributes: attributes,
                ),
        );
        segmentStart = segmentEnd;
      }
    }
    start = end;
  }
  return result;
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
///  * Install [TextAnnotation]s via [annotations] to make ranges tappable,
///    give them a mouse cursor, expose them to assistive technology, and make
///    them keyboard focusable.
///  * Listen for text, layout, selection, or annotation updates via
///    [addListener].
class TextDelegate extends ChangeNotifier implements Comparable<TextDelegate> {
  /// Creates a [TextDelegate] for the given [RenderObject] ([RenderParagraph],
  /// [RenderEditable], or [TextDelegateHostMixin]) and [TextPlugin].
  @internal
  TextDelegate(this.renderObject, this.plugin)
    : assert(
        renderObject is RenderParagraph ||
            renderObject is RenderEditable ||
            renderObject is TextDelegateHostMixin,
      ),
      assert(renderObject is TextPluginHost) {
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
  /// [CustomPainter.paint], and the callbacks of a [TextAnnotation].
  bool get hasLayout => hasValidLayout && renderObject.hasSize && !renderObject.debugNeedsLayout;

  /// The size of the underlying render object.
  ///
  /// Valid only after layout.
  Size get size => renderObject.size;

  /// An estimate of the bounds of the underlying render object in its
  /// local coordinate system.
  Rect get paintBounds => renderObject.paintBounds;

  /// Whether this delegate represents editable text ([RenderEditable], as
  /// used by [EditableText] and [TextField]), including read-only fields.
  ///
  /// Plugins use this to follow editor conventions: in editable text a plain
  /// click places the caret and a double-click selects a word, so a link
  /// should open on modifier-click or through a popup rather than on click.
  bool get isEditable => _editable != null;

  /// Whether this delegate represents a read-only [RenderEditable].
  ///
  /// Always `false` for static text.
  bool get isReadOnly => _editable?.readOnly ?? false;

  /// Whether the user can select the text represented by this delegate.
  ///
  /// `true` for a [RenderParagraph] registered with a [SelectionRegistrar]
  /// (inside a [SelectableRegion] or [SelectionArea]) and for a
  /// [RenderEditable] with interactive selection enabled.
  bool get isSelectable {
    if (_paragraph != null) {
      return _paragraph!.registrar != null;
    }
    if (_editable != null) {
      return _editable!.selectionEnabled;
    }
    return _host!.isSelectable;
  }

  /// The [TextAnnotation]s this plugin has installed on this text widget.
  ///
  /// Annotations make ranges tappable (through the gesture arena), give them
  /// a mouse cursor and hover callbacks, expose them to assistive technology,
  /// and make them keyboard focusable inside a [TextPluginScope]. See
  /// [TextAnnotation] for details.
  ///
  /// The list must be sorted by [TextAnnotation.range] and its ranges must not
  /// overlap or extend past the end of [text]. Setting a new list uninstalls
  /// the annotations that are not part of it (disposing the gesture
  /// recognizers they own), marks the semantics of the text widget dirty, and
  /// notifies the listeners of every delegate on the same text widget.
  ///
  /// Typically set in [TextPlugin.didAddText] and [TextPlugin.didUpdateText].
  List<TextAnnotation> get annotations => _annotations;
  List<TextAnnotation> _annotations = const <TextAnnotation>[];
  set annotations(List<TextAnnotation> value) {
    assert(!isDisposed);
    assert(_debugValidateAnnotations(value));
    if (listEquals(_annotations, value)) {
      return;
    }
    final List<TextAnnotation> oldAnnotations = _annotations;
    _annotations = List<TextAnnotation>.unmodifiable(value);
    for (final annotation in oldAnnotations) {
      if (!_annotations.contains(annotation)) {
        annotation._detach();
      }
    }
    for (final TextAnnotation annotation in _annotations) {
      annotation._attach(this);
    }
    (renderObject as TextPluginHost).didChangeTextAnnotations(this);
  }

  bool _debugValidateAnnotations(List<TextAnnotation> value) {
    final int length = text.length;
    for (var i = 0; i < value.length; i += 1) {
      final TextAnnotation annotation = value[i];
      assert(
        annotation.range.end <= length,
        'TextAnnotation ${annotation.range} extends past the end of the text ($length code units).',
      );
      assert(
        i == 0 || value[i - 1].range.end <= annotation.range.start,
        'TextAnnotations of a plugin must be sorted and must not overlap: '
        '${value[i - 1].range} is followed by ${annotation.range}.',
      );
      assert(
        annotation._delegate == null || identical(annotation._delegate, this),
        'TextAnnotation $annotation is already installed on another text widget.',
      );
    }
    return true;
  }

  /// All [TextAnnotation]s installed on this text widget by any plugin,
  /// topmost first (highest [TextPlugin.paintOrder] first).
  @internal
  List<TextAnnotation> get allAnnotations {
    final host = renderObject as TextPluginHost;
    return <TextAnnotation>[
      for (final TextDelegate delegate in host.textPluginDelegates.toList(growable: false).reversed)
        ...delegate.annotations,
    ];
  }

  /// Returns the [TextAnnotation]s installed on this text widget by any plugin
  /// that cover the code unit at [offset], topmost first.
  List<TextAnnotation> annotationsAt(int offset) {
    return textAnnotationsAt((renderObject as TextPluginHost).textPluginDelegates, offset);
  }

  /// The local bounding rectangle of the glyphs covered by [annotation], or
  /// null if the annotation is not laid out.
  ///
  /// Valid only after layout (see [hasLayout]).
  Rect? getBoundsForAnnotation(TextAnnotation annotation) {
    final List<ui.TextBox> boxes = getBoxesForSelection(
      TextSelection(baseOffset: annotation.range.start, extentOffset: annotation.range.end),
    );
    if (boxes.isEmpty) {
      return null;
    }
    Rect bounds = boxes.first.toRect();
    for (var i = 1; i < boxes.length; i += 1) {
      bounds = bounds.expandToInclude(boxes[i].toRect());
    }
    return bounds;
  }

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

  /// Notifies listeners registered on this [TextDelegate] that the text,
  /// layout, selection, or annotations have been updated.
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
    if (_annotations.isNotEmpty) {
      for (final TextAnnotation annotation in _annotations) {
        annotation._detach();
      }
      _annotations = const <TextAnnotation>[];
      (renderObject as TextPluginHost).didChangeTextAnnotations(this);
    }
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
///  5. Optionally call [hitTestTextAnnotations] in [hitTestChildren] and
///     [annotateSemanticsInformation] when building semantics, so that
///     [TextAnnotation]s installed by plugins become tappable and accessible.
mixin TextDelegateHostMixin on RenderBox implements TextPluginHost {
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

  /// Whether the user can select the text of this render object.
  bool get isSelectable => false;

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

  @override
  @internal
  Iterable<TextDelegate> get textPluginDelegates =>
      _textPluginDelegates?.values ?? const Iterable<TextDelegate>.empty();

  @override
  @internal
  void didChangeTextAnnotations(TextDelegate delegate) {
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

  /// Adds the [TextAnnotation]s covering the code unit at [offset] to
  /// [result], topmost first, so they participate in gesture recognition and
  /// mouse tracking.
  ///
  /// Call this from [hitTestChildren] with the code unit under `position`
  /// before adding this render object itself. Returns whether any annotation
  /// was hit.
  @protected
  bool hitTestTextAnnotations(BoxHitTestResult result, {required int offset}) {
    var hit = false;
    for (final TextAnnotation annotation in textAnnotationsAt(textPluginDelegates, offset)) {
      result.add(HitTestEntry<HitTestTarget>(annotation));
      hit = true;
    }
    return hit;
  }

  /// Splits [infos] at the boundaries of the [TextAnnotation]s installed on
  /// this render object, so that annotated runs can be reported as their own
  /// semantics nodes.
  ///
  /// The concatenated text of [infos] must equal [plainText].
  @protected
  List<InlineSpanSemanticsInformation> annotateSemanticsInformation(
    List<InlineSpanSemanticsInformation> infos,
  ) {
    return applyTextAnnotationsToSemantics(infos, textPluginDelegates);
  }

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
  void dispose() {
    _textPlugins = null;
    _removeAllTextPluginDelegates();
    super.dispose();
  }
}
