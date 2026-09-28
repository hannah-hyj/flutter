// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

@immutable
class _LinkMatch {
  const _LinkMatch({required this.range, required this.url});

  final TextRange range;
  final String url;
}

/// A [TextPlugin] that automatically detects URLs in any [Text] or [RichText]
/// widget, highlights them as links, and makes them clickable.
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
  final Map<TextDelegate, Offset> _pointerDownPositions = <TextDelegate, Offset>{};

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
    _pointerDownPositions.remove(delegate);
  }

  @override
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {
    final List<_LinkMatch>? links = _linksByDelegate[delegate];
    if (links == null || links.isEmpty || !delegate.hasLayout) {
      return;
    }

    if (event is PointerDownEvent) {
      _pointerDownPositions[delegate] = event.localPosition;
    } else if (event is PointerUpEvent) {
      final Offset? downPos = _pointerDownPositions.remove(delegate);
      if (downPos == null || (event.localPosition - downPos).distance > kTouchSlop) {
        return;
      }
      for (final _LinkMatch link in links) {
        final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
          TextSelection(baseOffset: link.range.start, extentOffset: link.range.end),
        );
        final bool hit = boxes.any(
          (ui.TextBox box) => box.toRect().inflate(2.0).contains(event.localPosition),
        );
        if (hit) {
          onLinkTapped?.call(link.url);
          break;
        }
      }
    } else if (event is PointerCancelEvent) {
      _pointerDownPositions.remove(delegate);
    }
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

    if (matches.isEmpty) {
      _linksByDelegate.remove(delegate);
      delegate.backgroundPainter = null;
      delegate.foregroundPainter = null;
    } else {
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
    }
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
