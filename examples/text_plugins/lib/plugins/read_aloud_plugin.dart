// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Represents a single spoken word token within a [TextDelegate].
@immutable
class ReadAloudWord {
  /// Creates a [ReadAloudWord].
  const ReadAloudWord({required this.delegate, required this.range, required this.word});

  /// The [TextDelegate] containing this word.
  final TextDelegate delegate;

  /// The character range of this word within [TextDelegate.text].
  final TextRange range;

  /// The plain text of the word.
  final String word;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ReadAloudWord && other.delegate == delegate && other.range == range;
  }

  @override
  int get hashCode => Object.hash(delegate, range);
}

/// A [TextPlugin] that provides a Text-to-Speech (TTS) "Read-Aloud Karaoke"
/// synchronizer across all [Text] and [RichText] widgets in a
/// [TextPluginScope].
///
/// Orders paragraphs in true document order via [TextDelegate.compareTo],
/// highlights both the active paragraph and the currently spoken word, and
/// scrolls the viewport via [TextDelegate.ensureVisible] as reading progresses.
class ReadAloudPlugin extends TextPlugin with ChangeNotifier {
  /// Creates a [ReadAloudPlugin].
  ReadAloudPlugin({
    this.wordInterval = const Duration(milliseconds: 240),
    this.paragraphTintColor = const Color(0x140288D1),
    this.activeWordBackgroundColor = const Color(0x5500ACC1),
    this.activeWordUnderlineColor = const Color(0xFF006064),
  });

  /// Interval between words during automatic playback.
  final Duration wordInterval;

  /// Soft background tint painted behind the active paragraph.
  final Color paragraphTintColor;

  /// Highlight color painted behind the currently spoken word.
  final Color activeWordBackgroundColor;

  /// Accent underline color painted beneath the currently spoken word.
  final Color activeWordUnderlineColor;

  static final RegExp _wordPattern = RegExp(r'[A-Za-z0-9$#@./:_-]+');

  final Set<TextDelegate> _delegates = <TextDelegate>{};
  final List<ReadAloudWord> _words = <ReadAloudWord>[];

  int _currentWordIndex = -1;
  bool _isPlaying = false;
  Timer? _timer;
  bool _notificationScheduled = false;
  bool _disposed = false;

  /// All word tokens in document order across the scoped subtree.
  List<ReadAloudWord> get words => List<ReadAloudWord>.unmodifiable(_words);

  /// Index of the currently spoken word in [words], or `-1` if inactive.
  int get currentWordIndex => _currentWordIndex;

  /// The currently spoken [ReadAloudWord], or `null` if inactive.
  ReadAloudWord? get currentWord => (_currentWordIndex >= 0 && _currentWordIndex < _words.length)
      ? _words[_currentWordIndex]
      : null;

  /// Whether automatic word-by-word read-aloud playback is currently running.
  bool get isPlaying => _isPlaying;

  void _notifyListenersSafely() {
    if (_disposed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (!_notificationScheduled) {
        _notificationScheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _notificationScheduled = false;
          if (!_disposed) {
            notifyListeners();
          }
        });
      }
    } else {
      notifyListeners();
    }
  }

  /// Starts or pauses automatic read-aloud playback.
  void togglePlay() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Starts automatic word-by-word read-aloud playback.
  void play() {
    if (_words.isEmpty) {
      return;
    }
    if (_currentWordIndex < 0 || _currentWordIndex >= _words.length) {
      _currentWordIndex = 0;
    }
    _isPlaying = true;
    _updatePainters();
    _ensureCurrentWordVisible();
    _timer?.cancel();
    _timer = Timer.periodic(wordInterval, (_) {
      if (_currentWordIndex + 1 < _words.length) {
        _currentWordIndex += 1;
        _updatePainters();
        _ensureCurrentWordVisible();
        _notifyListenersSafely();
      } else {
        pause();
      }
    });
    _notifyListenersSafely();
  }

  /// Pauses automatic read-aloud playback.
  void pause() {
    _timer?.cancel();
    _timer = null;
    if (_isPlaying) {
      _isPlaying = false;
      _notifyListenersSafely();
    }
  }

  /// Stops playback and clears the active word highlight.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
    _currentWordIndex = -1;
    _updatePainters();
    _notifyListenersSafely();
  }

  /// Steps forward by one word in document order and scrolls it into view.
  void stepNextWord() {
    if (_words.isEmpty) {
      return;
    }
    _currentWordIndex = (_currentWordIndex + 1) % _words.length;
    _updatePainters();
    _ensureCurrentWordVisible();
    _notifyListenersSafely();
  }

  /// Steps backward by one word in document order and scrolls it into view.
  void stepPreviousWord() {
    if (_words.isEmpty) {
      return;
    }
    _currentWordIndex = (_currentWordIndex <= 0) ? _words.length - 1 : _currentWordIndex - 1;
    _updatePainters();
    _ensureCurrentWordVisible();
    _notifyListenersSafely();
  }

  void _ensureCurrentWordVisible() {
    final ReadAloudWord? active = currentWord;
    if (active == null || !active.delegate.hasLayout) {
      return;
    }
    active.delegate.ensureVisible(
      active.range,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void didAddText(TextDelegate delegate) {
    _delegates.add(delegate);
    _rebuildWords();
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _rebuildWords();
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    if (currentWord?.delegate == delegate) {
      delegate.markNeedsPaint();
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.backgroundPainter = null;
    delegate.foregroundPainter = null;
    _delegates.remove(delegate);
    _rebuildWords();
  }

  void _rebuildWords() {
    final ReadAloudWord? previousWord = currentWord;
    _words.clear();
    final List<TextDelegate> sortedDelegates = _delegates.toList()..sort();
    for (final delegate in sortedDelegates) {
      final String plainText = delegate.text;
      for (final RegExpMatch match in _wordPattern.allMatches(plainText)) {
        _words.add(
          ReadAloudWord(
            delegate: delegate,
            range: TextRange(start: match.start, end: match.end),
            word: match.group(0)!,
          ),
        );
      }
    }

    if (_words.isEmpty) {
      _currentWordIndex = -1;
      pause();
    } else if (previousWord != null) {
      final int preserved = _words.indexOf(previousWord);
      if (preserved != -1) {
        _currentWordIndex = preserved;
      } else if (_currentWordIndex >= _words.length) {
        _currentWordIndex = 0;
      }
    }

    _updatePainters();
    _notifyListenersSafely();
  }

  void _updatePainters() {
    final ReadAloudWord? active = currentWord;
    for (final TextDelegate delegate in _delegates) {
      if (active != null && active.delegate == delegate) {
        delegate.backgroundPainter = _ReadAloudBackgroundPainter(
          delegate: delegate,
          wordRange: active.range,
          paragraphTintColor: paragraphTintColor,
          activeWordBackgroundColor: activeWordBackgroundColor,
        );
        delegate.foregroundPainter = _ReadAloudForegroundPainter(
          delegate: delegate,
          wordRange: active.range,
          underlineColor: activeWordUnderlineColor,
        );
      } else {
        delegate.backgroundPainter = null;
        delegate.foregroundPainter = null;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class _ReadAloudBackgroundPainter extends CustomPainter {
  _ReadAloudBackgroundPainter({
    required this.delegate,
    required this.wordRange,
    required this.paragraphTintColor,
    required this.activeWordBackgroundColor,
  });

  final TextDelegate delegate;
  final TextRange wordRange;
  final Color paragraphTintColor;
  final Color activeWordBackgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final paragraphPaint = Paint()
      ..color = paragraphTintColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).inflate(4.0), const Radius.circular(6.0)),
      paragraphPaint,
    );

    final wordPaint = Paint()
      ..color = activeWordBackgroundColor
      ..style = PaintingStyle.fill;
    final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
      TextSelection(baseOffset: wordRange.start, extentOffset: wordRange.end),
      includePlaceholders: false,
    );
    for (final box in boxes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.toRect().inflate(2.0), const Radius.circular(4.0)),
        wordPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReadAloudBackgroundPainter oldDelegate) {
    return oldDelegate.wordRange != wordRange ||
        oldDelegate.paragraphTintColor != paragraphTintColor ||
        oldDelegate.activeWordBackgroundColor != activeWordBackgroundColor;
  }
}

class _ReadAloudForegroundPainter extends CustomPainter {
  _ReadAloudForegroundPainter({
    required this.delegate,
    required this.wordRange,
    required this.underlineColor,
  });

  final TextDelegate delegate;
  final TextRange wordRange;
  final Color underlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final underlinePaint = Paint()
      ..color = underlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
      TextSelection(baseOffset: wordRange.start, extentOffset: wordRange.end),
      includePlaceholders: false,
    );
    for (final box in boxes) {
      final Rect rect = box.toRect();
      canvas.drawLine(
        Offset(rect.left, rect.bottom + 1.0),
        Offset(rect.right, rect.bottom + 1.0),
        underlinePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReadAloudForegroundPainter oldDelegate) {
    return oldDelegate.wordRange != wordRange || oldDelegate.underlineColor != underlineColor;
  }
}
