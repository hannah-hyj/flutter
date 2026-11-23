// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/widgets.dart';
library;

import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle, TextBox, TextDirection, TextPosition;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'box.dart';
import 'editable.dart';
import 'object.dart';
import 'paragraph.dart';

/// Where the decorations of a [TextPlugin] are turned into a span.
///
/// This exists for the inline-span experiment only, so that the two options
/// can be compared in one build. It is not a proposed API.
enum TextDecorationLayer {
  /// Option A. [Text] and [EditableText] build the decorated span in `build`
  /// and give it to the render object.
  widget,

  /// Option B. The render object keeps the span it was given and builds the
  /// decorated span itself.
  render,
}

/// The [TextDecorationLayer] of a [TextPluginScope] that does not choose one.
///
/// Experiment only. Tests set it to run the same test on both options. The
/// initial value can be chosen with `--dart-define=TEXT_DECORATION_LAYER=render`.
TextDecorationLayer debugDefaultTextDecorationLayer =
    const String.fromEnvironment('TEXT_DECORATION_LAYER') == 'render'
    ? TextDecorationLayer.render
    : TextDecorationLayer.widget;

/// Whether a decoration that only sets a background color is painted by the
/// render object of the text, instead of being put into the span.
///
/// Experiment only. With this, such a decoration does not change the span
/// that the text painter has. The paragraph of the engine is kept, and the
/// render object draws a rectangle for each box of the range, behind the
/// glyphs. Every other decoration still goes into the span.
///
/// The initial value can be chosen with
/// `--dart-define=TEXT_HIGHLIGHT_PAINT=framework`.
bool debugPaintHighlightsInFramework =
    const String.fromEnvironment('TEXT_HIGHLIGHT_PAINT') == 'framework';

/// An interface for plugins that read and decorate the text rendered by
/// [RenderParagraph] and [RenderEditable] (such as via [Text], [RichText],
/// and [EditableText] widgets) within a [TextPluginScope].
///
/// This is the inline-span prototype. A plugin does not paint. It returns
/// [TextSpanDecoration]s from [buildDecorations], and the framework applies
/// them to the [InlineSpan] tree of the text.
///
/// A [TextPlugin] is notified as text widgets are added, updated, and removed
/// within its scope. The callbacks run at build time: for each text,
/// [didAddText] or [didUpdateText] runs before [buildDecorations] for that
/// text, in the same frame.
///
/// See also:
///
///  * [TextPluginScope], which installs one or more [TextPlugin]s for a
///    widget subtree.
///  * [TextDelegate], which represents an individual text managed by a
///    [TextPlugin].
abstract class TextPlugin {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const TextPlugin();

  /// Whether this plugin requires offscreen content in scrollable viewports to
  /// be rendered so it can be discovered and navigated to (for example,
  /// "Find in Page" / `Ctrl+F` search).
  ///
  /// If a [TextPlugin] also implements [Listenable], [TextPluginScope] listens
  /// to it and updates the [OffscreenContentRenderingStrategy] whenever this
  /// changes.
  ///
  /// Defaults to `false`.
  bool get needsOffscreenContent => false;

  /// The relative order of this plugin compared to other [TextPlugin]s on the
  /// same text.
  ///
  /// Where the decorations of two plugins overlap, the plugin with the higher
  /// [paintOrder] wins. When two plugins have the same [paintOrder], the one
  /// from the inner [TextPluginScope] wins.
  ///
  /// Defaults to `0`.
  int get paintOrder => 0;

  /// Whether this plugin shows the selection of static text, so that
  /// [RenderParagraph] does not paint its own highlight.
  @internal
  bool get handlesSelectionHighlight => false;

  /// Whether every text in the scope asks this plugin for its decorations
  /// again when this plugin, as a [Listenable], notifies its listeners.
  ///
  /// This is the simple way to change decorations: change state and notify.
  /// Its cost follows the number of texts in the scope. The precise way is
  /// [TextDelegate.markNeedsDecoration], for the texts that changed.
  ///
  /// Defaults to `false`.
  bool get notifiesDecorationChanges => false;

  /// Called whenever a new text appears in the subtree covered by this plugin.
  ///
  /// This runs while the text is being built, before [buildDecorations] is
  /// called for it. The text has no layout yet, and the render tree around it
  /// may be incomplete, so the document order of [delegate]
  /// ([TextDelegate.compareTo]) is not reliable here.
  ///
  /// A plugin must not notify listeners synchronously from this callback. Use
  /// [deferToEndOfFrame].
  void didAddText(TextDelegate delegate) {}

  /// Called whenever the plain text of a text covered by this plugin changes.
  ///
  /// Like [didAddText], this runs at build time, before [buildDecorations].
  void didUpdateText(TextDelegate delegate) {}

  /// Called whenever a text is removed from the subtree covered by this
  /// plugin.
  void didRemoveText(TextDelegate delegate) {}

  /// Returns what this plugin wants done to the text of [delegate].
  ///
  /// Each [TextSpanDecoration.range] is in [TextDelegate.text], whatever other
  /// plugins do to the same text.
  ///
  /// The framework calls this when the text is built and whenever
  /// [TextDelegate.markNeedsDecoration] was called. It has to return equal
  /// decorations for equal state, and it must not change state.
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) => const <TextSpanDecoration>[];

  /// Runs [callback] now if no frame is being produced, and otherwise at the
  /// end of the current frame.
  ///
  /// The lifecycle callbacks run during build. A plugin that is a
  /// [ChangeNotifier] cannot notify its listeners from them, because a
  /// listener that calls `setState` would do so during build. It notifies
  /// through this method instead.
  static void deferToEndOfFrame(VoidCallback callback) {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(
        (Duration timeStamp) => callback(),
        debugLabel: 'TextPlugin.deferToEndOfFrame',
      );
    } else {
      callback();
    }
  }
}

/// A delegate representing one text registered with a [TextPlugin].
///
/// Each pair of a text and a [TextPlugin] has its own [TextDelegate]. Through
/// it the plugin can:
///
///  * Read the plain text ([text]) or the [InlineSpan] tree ([textSpan]).
///  * Ask for [TextPlugin.buildDecorations] to be called again
///    ([markNeedsDecoration]).
///  * Scroll enclosing viewports to reveal a range ([ensureVisible]).
///  * Sort delegates in document order ([compareTo], [sortInDocumentOrder]).
///  * Listen for changes of the text and of the selection ([addListener]).
///
/// The delegate does not expose the layout of the text.
class TextDelegate extends ChangeNotifier implements Comparable<TextDelegate> {
  TextDelegate._(this._set, this.plugin) {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
  }

  final TextDelegateSet _set;

  /// The [TextPlugin] that owns this delegate.
  final TextPlugin plugin;

  bool _isDisposed = false;

  // The render object of the text. Null in Option A until the text has been
  // built for the first time.
  TextDelegateHostMixin? get _host => _set._host;

  /// The plain text of the text widget, before any plugin decorated it.
  ///
  /// A [PlaceholderSpan] is one `0xFFFC` code unit, and semantics labels are
  /// not used.
  String get text => _set.plainText;

  /// The [InlineSpan] tree of the text widget, before any plugin decorated
  /// it.
  InlineSpan get textSpan => _set.span;

  /// Returns the character ranges occupied by [PlaceholderSpan]s (such as
  /// [WidgetSpan]s) within [text].
  List<TextRange> get placeholderRanges {
    final String plainText = text;
    final ranges = <TextRange>[];
    var index = 0;
    while (index < plainText.length) {
      if (plainText.codeUnitAt(index) == PlaceholderSpan.placeholderCodeUnit) {
        final start = index;
        while (index < plainText.length &&
            plainText.codeUnitAt(index) == PlaceholderSpan.placeholderCodeUnit) {
          index += 1;
        }
        ranges.add(TextRange(start: start, end: index));
      } else {
        index += 1;
      }
    }
    return ranges;
  }

  /// The active text selections in the text widget, in offsets of [text].
  ///
  /// This is empty for a text field ([RenderEditable]), which paints its own
  /// selection, and for a text that has not been built yet.
  List<TextSelection> get selections {
    final TextDelegateHostMixin? host = _host;
    if (host == null) {
      return const <TextSelection>[];
    }
    final DecoratedTextSpan? decorated = _set._decorated;
    if (decorated == null || !decorated.changesText) {
      return host.selections;
    }
    return <TextSelection>[
      for (final TextSelection selection in host.selections)
        TextSelection(
          baseOffset: decorated.toOriginalOffset(selection.baseOffset),
          extentOffset: decorated.toOriginalOffset(selection.extentOffset),
        ),
    ];
  }

  /// The color used to paint selection highlights on the text widget.
  Color? get selectionColor => _host?.selectionColor;

  /// The directionality of the text.
  ui.TextDirection get textDirection => _set.textDirection;

  /// Whether the text can be edited.
  bool get isEditable => _set.isEditable;

  /// Whether the text is in a [SelectableRegion] or is a text field, so that
  /// a pointer can select in it.
  bool get isSelectable => _set.isEditable || (_host?.isSelectable ?? false);

  /// Whether the render object of the text is attached to the render tree.
  bool get attached => _host?.attached ?? false;

  /// Asks the framework to call [TextPlugin.buildDecorations] for this text
  /// again.
  ///
  /// Only this text is updated. The text is laid out again if the new
  /// decorations differ from the old ones by more than a color or a text
  /// decoration.
  ///
  /// This must not be called while widgets are being built, laid out or
  /// painted. A plugin does not have to call it from [TextPlugin.didAddText]
  /// or [TextPlugin.didUpdateText]: the decorations are built right after
  /// those.
  void markNeedsDecoration() {
    if (!_isDisposed) {
      _set._markNeedsDecoration();
    }
  }

  bool get _hasLayout {
    final TextDelegateHostMixin? host = _host;
    return host != null && host.attached && host._hasValidLayout && host.hasSize;
  }

  /// Runs [scroll] after the current frame if a frame is being produced, and
  /// returns whether it did so.
  bool _deferScrollToEndOfFrame(VoidCallback scroll) {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      return false;
    }
    SchedulerBinding.instance.addPostFrameCallback((Duration timeStamp) {
      if (!_isDisposed && _hasLayout) {
        scroll();
      }
    }, debugLabel: 'TextDelegate.ensureVisible');
    return true;
  }

  /// Scrolls any enclosing scrollable viewports so that the given character
  /// [range] of [text] is visible on screen.
  ///
  /// This is safe to call from a lifecycle callback of a [TextPlugin]. When it
  /// is called while a frame is being produced, the scroll happens at the end
  /// of that frame and shows in the next one. Otherwise it happens right away.
  /// Nothing happens if the text has no layout at that point.
  void ensureVisible(
    TextRange range, {
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (_deferScrollToEndOfFrame(() => ensureVisible(range, duration: duration, curve: curve))) {
      return;
    }
    if (!_hasLayout) {
      return;
    }
    final TextDelegateHostMixin host = _host!;
    final Rect? rect = host._rectForRange(_set._toDecoratedRange(range));
    host.showOnScreen(descendant: host, rect: rect, duration: duration, curve: curve);
  }

  /// Compares this [TextDelegate] with [other] according to their logical
  /// document order in the render tree.
  ///
  /// The order is only reliable once the frame has been laid out. During
  /// build, which is when the lifecycle callbacks of a [TextPlugin] run, the
  /// render tree may be incomplete.
  ///
  /// To order many delegates, use [sortInDocumentOrder], which walks the tree
  /// once instead of comparing pairs.
  @override
  int compareTo(TextDelegate other) {
    final TextDelegateHostMixin? host = _host;
    final TextDelegateHostMixin? otherHost = other._host;
    if (identical(this, other) || (host != null && identical(host, otherHost))) {
      return 0;
    }
    if (host == null || otherHost == null) {
      return identityHashCode(_set).compareTo(identityHashCode(other._set));
    }

    final thisAncestors = <RenderObject>[];
    for (RenderObject? node = host; node != null; node = node.parent) {
      thisAncestors.add(node);
    }

    final otherAncestors = <RenderObject>[];
    for (RenderObject? node = otherHost; node != null; node = node.parent) {
      otherAncestors.add(node);
    }

    int thisIndex = thisAncestors.length - 1;
    int otherIndex = otherAncestors.length - 1;

    if (!identical(thisAncestors[thisIndex], otherAncestors[otherIndex])) {
      // The two render objects do not share a common root (e.g., one is detached).
      return identityHashCode(host).compareTo(identityHashCode(otherHost));
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
  /// [compareTo] defines, with one walk of the render tree.
  static void sortInDocumentOrder(List<TextDelegate> delegates) {
    if (delegates.length < 2) {
      return;
    }
    final delegatesByRenderObject = <RenderObject, List<TextDelegate>>{};
    final marked = <RenderObject>{};
    RenderObject? root;
    for (final delegate in delegates) {
      final TextDelegateHostMixin? host = delegate._host;
      if (host == null) {
        delegates.sort();
        return;
      }
      (delegatesByRenderObject[host] ??= <TextDelegate>[]).add(delegate);
      RenderObject? node = host;
      RenderObject? top;
      while (node != null && marked.add(node)) {
        top = node;
        node = node.parent;
      }
      if (node == null && top != null) {
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

  void _notifyChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

/// The delegates of one text, one for each [TextPlugin], and the decorated
/// span that the plugins produce for it.
///
/// This is the shared machinery of the two options of the inline-span
/// experiment. In Option A a widget owns it, in Option B the render object
/// does. It is not part of the plugin API.
class TextDelegateSet {
  /// Creates an empty set.
  ///
  /// [onNeedsDecoration] is called when a plugin asks for new decorations
  /// with [TextDelegate.markNeedsDecoration].
  TextDelegateSet({required this.onNeedsDecoration});

  /// Called when a plugin asks for new decorations.
  final VoidCallback onNeedsDecoration;

  Map<TextPlugin, TextDelegate> _delegates = <TextPlugin, TextDelegate>{};
  TextDelegateHostMixin? _host;

  /// The undecorated span of the text.
  InlineSpan get span => _span!;
  InlineSpan? _span;

  /// The plain text of [span].
  String get plainText => _plainText ??= span.toPlainText(includeSemanticsLabels: false);
  String? _plainText;

  /// The directionality of the text.
  ui.TextDirection get textDirection => _textDirection;
  ui.TextDirection _textDirection = ui.TextDirection.ltr;

  /// Whether the text is editable.
  bool get isEditable => _isEditable;
  bool _isEditable = false;

  /// Whether there is no delegate.
  bool get isEmpty => _delegates.isEmpty;

  /// The delegates, in the order of their plugins.
  Iterable<TextDelegate> get delegates => _delegates.values;

  /// The delegate of [plugin], if any.
  TextDelegate? delegateFor(TextPlugin plugin) => _delegates[plugin];

  /// The render object of the text, once there is one.
  TextDelegateHostMixin? get host => _host;

  bool _disposed = false;

  /// Brings the set up to date with the text and the plugins, and tells the
  /// plugins about it.
  ///
  /// A plugin that is new gets [TextPlugin.didAddText]. A plugin that is gone
  /// gets [TextPlugin.didRemoveText]. If the plain text changed, the others
  /// get [TextPlugin.didUpdateText].
  void update({
    required List<TextPlugin> plugins,
    required InlineSpan span,
    required ui.TextDirection textDirection,
    bool isEditable = false,
    bool allowReplacements = true,
  }) {
    assert(!_disposed);
    _allowReplacements = allowReplacements;
    _updating = true;
    try {
      _update(plugins, span, textDirection, isEditable);
    } finally {
      _updating = false;
    }
  }

  bool _updating = false;
  bool _allowReplacements = true;

  void _update(
    List<TextPlugin> plugins,
    InlineSpan span,
    ui.TextDirection textDirection,
    bool isEditable,
  ) {
    var textChanged = false;
    final InlineSpan? oldSpan = _span;
    if (!identical(oldSpan, span)) {
      // Only a layout change can change the plain text. A rebuild with an
      // equal span is the common case, and building the string for every
      // text on the page is not free.
      if (oldSpan != null && oldSpan.compareTo(span) == RenderComparison.layout) {
        final String oldPlainText = plainText;
        _span = span;
        _plainText = null;
        textChanged = oldPlainText != plainText;
      } else {
        _span = span;
      }
    }
    _textDirection = textDirection;
    _isEditable = isEditable;

    final Map<TextPlugin, TextDelegate> oldDelegates = _delegates;
    var same = oldDelegates.length == plugins.length;
    if (same) {
      var index = 0;
      for (final TextPlugin plugin in oldDelegates.keys) {
        if (!identical(plugin, plugins[index])) {
          same = false;
          break;
        }
        index += 1;
      }
    }
    if (same) {
      if (textChanged) {
        for (final TextDelegate delegate in oldDelegates.values.toList(growable: false)) {
          delegate._notifyChanged();
          delegate.plugin.didUpdateText(delegate);
        }
      }
      return;
    }

    final newDelegates = <TextPlugin, TextDelegate>{};
    final added = <TextDelegate>[];
    for (final plugin in plugins) {
      if (newDelegates.containsKey(plugin)) {
        continue;
      }
      final TextDelegate? existing = oldDelegates[plugin];
      if (existing != null) {
        newDelegates[plugin] = existing;
      } else {
        final delegate = TextDelegate._(this, plugin);
        newDelegates[plugin] = delegate;
        added.add(delegate);
      }
    }
    _delegates = newDelegates;
    for (final MapEntry<TextPlugin, TextDelegate> entry in oldDelegates.entries) {
      if (!newDelegates.containsKey(entry.key)) {
        entry.key.didRemoveText(entry.value);
        entry.value.dispose();
      }
    }
    for (final TextDelegate delegate in newDelegates.values.toList(growable: false)) {
      if (added.contains(delegate)) {
        delegate.plugin.didAddText(delegate);
      } else if (textChanged) {
        delegate._notifyChanged();
        delegate.plugin.didUpdateText(delegate);
      }
    }
  }

  DecoratedTextSpan? _decorated;
  InlineSpan? _decoratedFrom;
  List<TextSpanDecoration>? _decorations;

  /// How many times a decorated span was built by [decorate], for tests and
  /// benchmarks.
  static int debugDecorateCount = 0;

  /// How many times [TextPlugin.buildDecorations] was called, for tests and
  /// benchmarks.
  static int debugBuildDecorationsCount = 0;

  /// Asks every plugin for its decorations and returns the decorated span.
  ///
  /// Returns the same object as the last call if neither the span nor the
  /// decorations changed, so that the text is not laid out again.
  DecoratedTextSpan decorate() {
    assert(!_disposed);
    List<TextSpanDecoration>? decorations;
    for (final TextDelegate delegate in _delegates.values) {
      debugBuildDecorationsCount += 1;
      final List<TextSpanDecoration> own = delegate.plugin.buildDecorations(delegate);
      if (own.isEmpty) {
        continue;
      }
      decorations ??= <TextSpanDecoration>[];
      if (!_allowReplacements) {
        // The text of a text field has to stay the same string, or the caret
        // and the selection are wrong. So a replacement is dropped.
        decorations.addAll(
          own.where((TextSpanDecoration decoration) => decoration.replacement == null),
        );
      } else {
        decorations.addAll(own);
      }
    }
    decorations ??= const <TextSpanDecoration>[];
    var highlights = const <TextSpanDecoration>[];
    if (debugPaintHighlightsInFramework && decorations.isNotEmpty) {
      final rest = <TextSpanDecoration>[];
      final painted = <TextSpanDecoration>[];
      for (final TextSpanDecoration decoration in decorations) {
        (_isBackgroundOnly(decoration) ? painted : rest).add(decoration);
      }
      decorations = rest;
      highlights = painted;
    }
    if (!listEquals(_frameworkHighlights, highlights)) {
      _frameworkHighlights = highlights;
      debugFrameworkHighlightChangeCount += 1;
      // The span is the same, so the paragraph is. Only the rectangles are
      // drawn again.
      final TextDelegateHostMixin? host = _host;
      if (host != null && host.attached) {
        host.markNeedsPaint();
      }
    }
    final DecoratedTextSpan? last = _decorated;
    if (last != null && identical(_decoratedFrom, span) && listEquals(_decorations, decorations)) {
      return last;
    }
    debugDecorateCount += 1;
    _decoratedFrom = span;
    _decorations = decorations;
    return _decorated = decorateTextSpan(span, decorations);
  }

  /// The result of the last call to [decorate].
  DecoratedTextSpan? get decorated => _decorated;

  List<TextSpanDecoration> _frameworkHighlights = const <TextSpanDecoration>[];

  /// The decorations that the render object paints itself, see
  /// [debugPaintHighlightsInFramework].
  @visibleForTesting
  List<TextSpanDecoration> get debugFrameworkHighlights => _frameworkHighlights;

  /// How many times the decorations that the render object paints itself
  /// changed, for tests and benchmarks.
  static int debugFrameworkHighlightChangeCount = 0;

  TextStyle? _lastCheckedStyle;
  bool _lastCheckedStyleIsBackgroundOnly = false;

  bool _isBackgroundOnly(TextSpanDecoration decoration) {
    final TextStyle? style = decoration.style;
    if (style == null ||
        style.backgroundColor == null ||
        decoration.recognizer != null ||
        decoration.mouseCursor != null ||
        decoration.onEnter != null ||
        decoration.onExit != null ||
        decoration.semanticsLabel != null ||
        decoration.replacement != null) {
      return false;
    }
    // A plugin uses a few styles for many ranges.
    if (identical(style, _lastCheckedStyle)) {
      return _lastCheckedStyleIsBackgroundOnly;
    }
    _lastCheckedStyle = style;
    return _lastCheckedStyleIsBackgroundOnly =
        style == TextStyle(backgroundColor: style.backgroundColor);
  }

  TextRange _toDecoratedRange(TextRange range) {
    final DecoratedTextSpan? decorated = _decorated;
    if (decorated == null || !decorated.changesText) {
      return range;
    }
    return TextRange(
      start: decorated.toDecoratedOffset(range.start),
      end: decorated.toDecoratedOffset(range.end),
    );
  }

  void _markNeedsDecoration() {
    // While the plugins are being told about the text, the decorations are
    // about to be asked for anyway.
    if (!_disposed && !_updating) {
      onNeedsDecoration();
    }
  }

  /// Notifies the listeners of every delegate, without a plugin callback.
  void notifyListeners() {
    for (final TextDelegate delegate in _delegates.values.toList(growable: false)) {
      delegate._notifyChanged();
    }
  }

  /// Tells every plugin that the text is gone, and disposes the delegates.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final List<TextDelegate> delegates = _delegates.values.toList(growable: false);
    _delegates = <TextPlugin, TextDelegate>{};
    for (final delegate in delegates) {
      delegate.plugin.didRemoveText(delegate);
      delegate.dispose();
    }
    _host = null;
  }
}

/// A mixin for [RenderBox] subclasses that participate in a
/// [TextPluginScope].
///
/// [RenderParagraph] and [RenderEditable] use it.
///
/// In Option B of the inline-span experiment the render object owns the
/// delegates: it is given [textPlugins], and it calls [applyDecoratedTextSpan]
/// with the decorated span. In Option A a widget owns them and gives the
/// render object a [textDelegateSet], and the span that the render object is
/// given is already decorated.
mixin TextDelegateHostMixin on RenderBox {
  /// The span that this render object was given, before this render object
  /// decorated it.
  InlineSpan get textSpan;

  /// The directionality of the text.
  ui.TextDirection get textDirection;

  /// Whether the text can be edited.
  bool get isTextEditable => false;

  /// Whether a pointer can select in the text.
  bool get isSelectable => false;

  /// The selections that a plugin may want to decorate.
  ///
  /// Defaults to none. A render object that paints its own selection, such as
  /// [RenderEditable], keeps the default.
  List<TextSelection> get selections => const <TextSelection>[];

  /// The selection highlight color on this render object, if any.
  Color? get selectionColor => null;

  /// Returns the [ui.TextBox]es bounding [selection] in local coordinates.
  ///
  /// The offsets are in the text that is laid out, which is the decorated
  /// text.
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  });

  /// Returns the local caret offset for [position].
  Offset getOffsetForCaret(ui.TextPosition position, Rect caretPrototype) => Offset.zero;

  /// Returns the full caret height for [position].
  double getFullHeightForCaret(ui.TextPosition position) => hasSize ? size.height : 0.0;

  /// Gives the text painter of this render object the decorated span.
  ///
  /// Option B only. The implementation compares [span] with the span that is
  /// laid out and marks this render object as needing paint or layout.
  @protected
  void applyDecoratedTextSpan(InlineSpan span);

  // ---- Option B: the render object owns the delegates. ----

  /// The [TextPlugin]s whose decorations this render object applies itself.
  List<TextPlugin>? get textPlugins => _textPlugins;
  List<TextPlugin>? _textPlugins;
  set textPlugins(List<TextPlugin>? value) {
    if (listEquals(_textPlugins, value)) {
      return;
    }
    _textPlugins = value == null || value.isEmpty ? null : List<TextPlugin>.unmodifiable(value);
    if (attached) {
      _syncOwnSet();
    }
  }

  /// A number that the widget changes to make this render object ask its
  /// plugins for their decorations again.
  int get textPluginDecorationVersion => _textPluginDecorationVersion;
  int _textPluginDecorationVersion = 0;
  set textPluginDecorationVersion(int value) {
    if (_textPluginDecorationVersion == value) {
      return;
    }
    _textPluginDecorationVersion = value;
    if (_ownSet != null) {
      _applyOwnDecorations();
    }
  }

  TextDelegateSet? _ownSet;

  void _syncOwnSet() {
    final List<TextPlugin>? plugins = _textPlugins;
    if (plugins == null) {
      final TextDelegateSet? set = _ownSet;
      if (set != null) {
        _ownSet = null;
        set.dispose();
        applyDecoratedTextSpan(textSpan);
      }
      return;
    }
    final sorted = <TextPlugin>[...plugins];
    mergeSort<TextPlugin>(
      sorted,
      compare: (TextPlugin a, TextPlugin b) => a.paintOrder.compareTo(b.paintOrder),
    );
    final TextDelegateSet set = _ownSet ??= TextDelegateSet(
      onNeedsDecoration: _scheduleOwnDecorations,
    ).._host = this;
    set.update(
      plugins: sorted,
      span: textSpan,
      textDirection: textDirection,
      isEditable: isTextEditable,
    );
    _applyOwnDecorations();
  }

  bool _ownDecorationsScheduled = false;

  // A plugin asks for new decorations from an event handler, and the code
  // around it may still need the layout of the text: a selection that changes
  // during a drag reads the boxes of the text right after. So the span is not
  // replaced right away, which would mark the text as needing layout. It is
  // replaced at the start of the next frame, before build.
  void _scheduleOwnDecorations() {
    if (_ownDecorationsScheduled) {
      return;
    }
    _ownDecorationsScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((Duration timeStamp) {
      _ownDecorationsScheduled = false;
      if (attached) {
        _applyOwnDecorations();
      }
    });
  }

  void _applyOwnDecorations() {
    final TextDelegateSet? set = _ownSet;
    if (set == null) {
      return;
    }
    final DecoratedTextSpan decorated = set.decorate();
    assert(
      !decorated.changesText,
      'A TextSpanDecoration.replacement needs TextDecorationLayer.widget. '
      'A render object cannot create the widget of a WidgetSpan.',
    );
    applyDecoratedTextSpan(decorated.changesText ? textSpan : decorated.span);
  }

  /// Tells the plugins that [textSpan] changed, and applies their decorations
  /// to the new span.
  ///
  /// Returns false if this render object has no plugins of its own. The
  /// caller then gives the span to its text painter itself.
  @protected
  bool updateTextDelegates() {
    if (_ownSet == null) {
      return false;
    }
    _syncOwnSet();
    return true;
  }

  // ---- Option A: a widget owns the delegates. ----

  /// The delegates that a widget owns for this text.
  ///
  /// The render object only tells the set which render object the text has,
  /// so that a delegate can scroll to the text and compare its position.
  TextDelegateSet? get textDelegateSet => _externalSet;
  TextDelegateSet? _externalSet;
  set textDelegateSet(TextDelegateSet? value) {
    if (identical(_externalSet, value)) {
      return;
    }
    if (identical(_externalSet?._host, this)) {
      _externalSet!._host = null;
    }
    _externalSet = value;
    value?._host = this;
  }

  // ---- Both. ----

  TextDelegateSet? get _activeSet => _ownSet ?? _externalSet;

  /// Whether a [TextPlugin] sees this text.
  @protected
  bool get hasTextDelegates => !(_activeSet?.isEmpty ?? true);

  /// Whether a plugin with [TextPlugin.handlesSelectionHighlight] sees this
  /// text.
  @protected
  bool get hasSelectionHighlightPlugin {
    final TextDelegateSet? set = _activeSet;
    if (set == null) {
      return false;
    }
    for (final TextDelegate delegate in set.delegates) {
      if (delegate.plugin.handlesSelectionHighlight) {
        return true;
      }
    }
    return false;
  }

  /// Notifies the listeners of every [TextDelegate] of this render object,
  /// without a [TextPlugin] callback.
  ///
  /// Call this when something that a delegate exposes changed and the text
  /// did not, for example [selections] or [selectionColor].
  void notifyTextDelegateListeners() {
    _activeSet?.notifyListeners();
  }

  bool _hasValidLayout = false;

  /// Records that this render object has a layout.
  ///
  /// Call this at the end of [performLayout].
  @protected
  void didLayoutTextDelegates() {
    _hasValidLayout = true;
  }

  /// Paints the decorations that are not in the span, see
  /// [debugPaintHighlightsInFramework]. Call this right before the text is
  /// painted, with the offset that [getBoxesForSelection] is relative to.
  @protected
  void paintFrameworkHighlights(Canvas canvas, Offset offset) {
    final TextDelegateSet? set = _activeSet;
    if (set == null || set._frameworkHighlights.isEmpty) {
      return;
    }
    final paint = Paint();
    for (final TextSpanDecoration highlight in set._frameworkHighlights) {
      final TextRange range = set._toDecoratedRange(highlight.range);
      if (!range.isValid || range.isCollapsed) {
        continue;
      }
      paint.color = highlight.style!.backgroundColor!;
      final List<ui.TextBox> boxes = getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      for (final box in boxes) {
        canvas.drawRect(box.toRect().shift(offset), paint);
      }
    }
  }

  Rect? _rectForRange(TextRange range) {
    final List<ui.TextBox> boxes = getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    if (boxes.isNotEmpty) {
      Rect rect = boxes.first.toRect();
      for (var i = 1; i < boxes.length; i += 1) {
        rect = rect.expandToInclude(boxes[i].toRect());
      }
      return rect;
    }
    final position = ui.TextPosition(offset: range.start);
    final Offset caretOffset = getOffsetForCaret(position, Rect.zero);
    return Rect.fromLTWH(caretOffset.dx, caretOffset.dy, 1.0, getFullHeightForCaret(position));
  }

  /// The rectangle of [range] in local coordinates, for the framework.
  ///
  /// [range] is in the undecorated text. This is how the widgets layer reads
  /// the geometry of a range without giving it to a plugin.
  @internal
  Rect? debugRectForUndecoratedRange(TextRange range) {
    if (!_hasValidLayout || !hasSize) {
      return null;
    }
    return _rectForRange(_activeSet?._toDecoratedRange(range) ?? range);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _externalSet?._host = this;
    _syncOwnSet();
  }

  @override
  void detach() {
    final TextDelegateSet? set = _ownSet;
    if (set != null) {
      _ownSet = null;
      set.dispose();
    }
    super.detach();
  }

  @override
  void markNeedsLayout() {
    _hasValidLayout = false;
    super.markNeedsLayout();
  }

  @override
  void dispose() {
    _textPlugins = null;
    final TextDelegateSet? set = _ownSet;
    if (set != null) {
      _ownSet = null;
      set.dispose();
    }
    if (identical(_externalSet?._host, this)) {
      _externalSet!._host = null;
    }
    _externalSet = null;
    super.dispose();
  }
}
