// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class _LinkMatch {
  const _LinkMatch({required this.range, required this.url});

  final TextRange range;
  final String url;
}

/// A [TextPlugin] that automatically detects URLs in any [Text] or [RichText]
/// widget, highlights them as links, and makes them clickable.
///
/// Each detected URL is declared as a [TextAnnotation], which gives it
/// gesture-arena participation (a drag that starts on a link scrolls, a tap
/// opens it exactly once), a hand cursor, a focusable link node for screen
/// readers, and Tab/Enter keyboard access, without any pointer bookkeeping in
/// the plugin.
///
/// In editable or selectable text (see [TextDelegate.isEditable] and
/// [TextDelegate.isSelectable]) a plain click must keep placing the caret or
/// selecting words, so there a link only opens on modifier-click (or on a
/// touch tap), following the convention of editors such as Google Docs.
class LinkifyPlugin extends TextPlugin {
  /// Creates a [LinkifyPlugin].
  LinkifyPlugin({
    this.onLinkTapped,
    this.linkTint = const Color(0x1F1565C0),
    this.underlineColor = const Color(0xFF1565C0),
  });

  /// Callback invoked when a detected URL is tapped by the user.
  final ValueChanged<String>? onLinkTapped;

  /// Subtle background tint painted behind detected links.
  final Color linkTint;

  /// Underline color painted under detected links.
  final Color underlineColor;

  static final RegExp _urlRegExp = RegExp(
    r'(?:https?:\/\/|www\.)[^\s<>()]+[^\s<>().,;:!?"\x27\]]',
    caseSensitive: false,
  );

  final Map<TextDelegate, List<_LinkMatch>> _linksByDelegate = <TextDelegate, List<_LinkMatch>>{};
  final Map<TextDelegate, List<_ModifierClickRecognizer>> _recognizersByDelegate =
      <TextDelegate, List<_ModifierClickRecognizer>>{};

  @override
  void didAddText(TextDelegate delegate) {
    _scanLinks(delegate);
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _scanLinks(delegate);
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    if (_linksByDelegate.containsKey(delegate)) {
      delegate.markNeedsPaint();
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.backgroundPainter = null;
    delegate.foregroundPainter = null;
    _linksByDelegate.remove(delegate);
    _disposeRecognizers(delegate);
  }

  void _disposeRecognizers(TextDelegate delegate) {
    _recognizersByDelegate.remove(delegate)?.forEach((_ModifierClickRecognizer r) => r.dispose());
  }

  void _scanLinks(TextDelegate delegate) {
    final String text = delegate.text;
    final matches = <_LinkMatch>[];
    for (final RegExpMatch match in _urlRegExp.allMatches(text)) {
      final String raw = match.group(0)!;
      final normalized = raw.startsWith('http') ? raw : 'https://$raw';
      matches.add(
        _LinkMatch(
          range: TextRange(start: match.start, end: match.end),
          url: normalized,
        ),
      );
    }

    _disposeRecognizers(delegate);
    if (matches.isEmpty) {
      _linksByDelegate.remove(delegate);
      delegate.backgroundPainter = null;
      delegate.foregroundPainter = null;
      delegate.annotations = const <TextAnnotation>[];
      return;
    }

    _linksByDelegate[delegate] = matches;
    delegate.backgroundPainter = _LinkBackgroundPainter(
      delegate: delegate,
      links: matches,
      tintColor: linkTint,
    );
    delegate.foregroundPainter = _LinkForegroundPainter(
      delegate: delegate,
      links: matches,
      underlineColor: underlineColor,
    );

    // Editor convention: in editable or selectable text a plain click places
    // the caret / selects, so only modifier-clicks (and touch taps) open links.
    final bool requiresModifier = delegate.isEditable || delegate.isSelectable;
    final recognizers = <_ModifierClickRecognizer>[];
    final annotations = <TextAnnotation>[];
    for (final _LinkMatch link in matches) {
      void open() => onLinkTapped?.call(link.url);
      _ModifierClickRecognizer? recognizer;
      if (requiresModifier) {
        recognizer = _ModifierClickRecognizer(onActivate: open);
        recognizers.add(recognizer);
      }
      annotations.add(
        TextAnnotation(
          range: link.range,
          key: link.url,
          cursor: SystemMouseCursors.click,
          linkUrl: Uri.tryParse(link.url),
          onTap: requiresModifier ? null : open,
          recognizer: recognizer,
        ),
      );
    }
    delegate.annotations = annotations;
    if (recognizers.isNotEmpty) {
      _recognizersByDelegate[delegate] = recognizers;
    }
  }
}

/// A tap recognizer that only competes for mouse clicks with a modifier key
/// held (Cmd/Ctrl+click), while accepting any touch tap.
class _ModifierClickRecognizer extends TapGestureRecognizer {
  _ModifierClickRecognizer({required VoidCallback onActivate}) {
    onTap = onActivate;
  }

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (!super.isPointerAllowed(event)) {
      return false;
    }
    if (event.kind != PointerDeviceKind.mouse) {
      return true;
    }
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    return keyboard.isMetaPressed || keyboard.isControlPressed;
  }
}

class _LinkBackgroundPainter extends CustomPainter {
  _LinkBackgroundPainter({required this.delegate, required this.links, required this.tintColor});

  final TextDelegate delegate;
  final List<_LinkMatch> links;
  final Color tintColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final paint = Paint()
      ..color = tintColor
      ..style = PaintingStyle.fill;
    for (final _LinkMatch link in links) {
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: link.range.start, extentOffset: link.range.end),
      );
      for (final box in boxes) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(box.toRect().inflate(1.0), const Radius.circular(3.0)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinkBackgroundPainter oldDelegate) {
    return oldDelegate.links != links || oldDelegate.tintColor != tintColor;
  }
}

class _LinkForegroundPainter extends CustomPainter {
  _LinkForegroundPainter({
    required this.delegate,
    required this.links,
    required this.underlineColor,
  });

  final TextDelegate delegate;
  final List<_LinkMatch> links;
  final Color underlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final paint = Paint()
      ..color = underlineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final _LinkMatch link in links) {
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: link.range.start, extentOffset: link.range.end),
      );
      for (final box in boxes) {
        final Rect rect = box.toRect();
        canvas.drawLine(
          Offset(rect.left, rect.bottom - 0.5),
          Offset(rect.right, rect.bottom - 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinkForegroundPainter oldDelegate) {
    return oldDelegate.links != links || oldDelegate.underlineColor != underlineColor;
  }
}
