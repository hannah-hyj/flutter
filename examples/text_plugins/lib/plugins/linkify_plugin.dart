// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A tap recognizer that does not take part in a gesture at all unless
/// [isEnabled] says so when the pointer goes down.
///
/// In selectable or editable text a plain click belongs to the selection. A
/// span has one recognizer, and it is the first one in the gesture arena, so
/// an ordinary [TapGestureRecognizer] would win every tap on the link and a
/// double click would no longer select the word. Staying out of the arena is
/// the only way for a span to give a click back.
class _ConditionalTapGestureRecognizer extends TapGestureRecognizer {
  _ConditionalTapGestureRecognizer(this.isEnabled);

  final bool Function() isEnabled;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    return isEnabled() && super.isPointerAllowed(event);
  }
}

class _Link {
  _Link(this.range, this.url, this.recognizer);

  TextRange range;
  final String url;
  final TapGestureRecognizer recognizer;
}

/// Stage 2 of the inline-span prototype: turns URLs in plain text into links.
///
/// A link is a [TextSpanDecoration] with a style, a recognizer and a mouse
/// cursor. Hit testing, the cursor and the semantics node of the link are what
/// [TextSpan] already does for a span with a recognizer. The plugin adds no
/// hit testing of its own.
class LinkifyPlugin extends TextPlugin {
  /// Creates a plugin that calls [onOpen] when a link is activated.
  LinkifyPlugin({
    required this.onOpen,
    this.linkColor = const Color(0xFF1565C0),
  });

  /// Called with the URL of the link that was tapped.
  final void Function(String url) onOpen;

  /// The color of a link.
  final Color linkColor;

  /// The URL under the mouse pointer, if any.
  final ValueNotifier<String?> hoveredUrl = ValueNotifier<String?>(null);

  static final RegExp _urlPattern = RegExp(r'(?:https?://|www\.)[^\s\uFFFC|]+');

  final Map<TextDelegate, List<_Link>> _links = <TextDelegate, List<_Link>>{};

  @override
  void didAddText(TextDelegate delegate) => _scan(delegate);

  @override
  void didUpdateText(TextDelegate delegate) => _scan(delegate);

  @override
  void didRemoveText(TextDelegate delegate) {
    for (final _Link link in _links.remove(delegate) ?? const <_Link>[]) {
      link.recognizer.dispose();
    }
  }

  void _scan(TextDelegate delegate) {
    // A recognizer has to stay the same object for as long as the link is the
    // same link, or a tap that started on the old one never completes. So the
    // recognizers of the previous scan are reused by URL.
    final List<_Link> old = _links[delegate] ?? <_Link>[];
    final links = <_Link>[];
    for (final RegExpMatch match in _urlPattern.allMatches(delegate.text)) {
      final String url = match.group(0)!;
      final range = TextRange(start: match.start, end: match.end);
      final int reuse = old.indexWhere((_Link link) => link.url == url);
      if (reuse != -1) {
        links.add(old.removeAt(reuse)..range = range);
      } else {
        final recognizer = _ConditionalTapGestureRecognizer(
          () => _canOpen(delegate),
        );
        recognizer.onTap = () => onOpen(url);
        links.add(_Link(range, url, recognizer));
      }
    }
    for (final link in old) {
      link.recognizer.dispose();
    }
    if (links.isEmpty) {
      _links.remove(delegate);
    } else {
      _links[delegate] = links;
    }
  }

  // In text that can be selected or edited, a plain click places the caret
  // or starts a selection. There the link needs a modifier key. Nothing in a
  // span can express this rule, so it is here, in the plugin.
  bool _canOpen(TextDelegate delegate) {
    return !delegate.isSelectable ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final List<_Link>? links = _links[delegate];
    if (links == null) {
      return const <TextSpanDecoration>[];
    }
    // A text field that can be edited does not accept a span with a
    // recognizer: RenderEditable asserts that it is read-only, on every
    // platform but macOS. There the link is only styled.
    final bool interactive =
        !delegate.isEditable || defaultTargetPlatform == TargetPlatform.macOS;
    return <TextSpanDecoration>[
      for (final _Link link in links)
        TextSpanDecoration(
          range: link.range,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
          recognizer: interactive ? link.recognizer : null,
          mouseCursor: interactive ? SystemMouseCursors.click : null,
          onEnter: (PointerEnterEvent event) => hoveredUrl.value = link.url,
          onExit: (PointerExitEvent event) {
            if (hoveredUrl.value == link.url) {
              hoveredUrl.value = null;
            }
          },
        ),
    ];
  }

  /// Disposes the recognizers and the notifier.
  void dispose() {
    for (final List<_Link> links in _links.values) {
      for (final link in links) {
        link.recognizer.dispose();
      }
    }
    _links.clear();
    hoveredUrl.dispose();
  }
}
