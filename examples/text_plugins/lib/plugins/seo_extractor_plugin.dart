// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A [TextPlugin] that extracts all visible text rendered by [Text] and
/// [RichText] widgets in its scope for Search Engine Optimization (SEO) and
/// live content indexing without requiring the semantics tree.
class SeoExtractorPlugin extends TextPlugin with ChangeNotifier {
  final List<TextDelegate> _delegates = <TextDelegate>[];
  bool _notificationScheduled = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

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

  /// The ordered list of non-empty text blocks currently rendered in the
  /// plugin's subtree.
  List<String> get extractedBlocks => _delegates
      .map((TextDelegate d) => d.text.trim())
      .where((String t) => t.isNotEmpty)
      .toList(growable: false);

  /// Total number of tracked [TextDelegate]s in the scope.
  int get widgetCount => _delegates.length;

  /// Total word count across all extracted text blocks.
  int get wordCount {
    var count = 0;
    final wordSplitter = RegExp(r'\S+');
    for (final String block in extractedBlocks) {
      count += wordSplitter.allMatches(block).length;
    }
    return count;
  }

  /// Total character count across all extracted text blocks.
  int get characterCount {
    var count = 0;
    for (final String block in extractedBlocks) {
      count += block.length;
    }
    return count;
  }

  /// Generates a structured JSON-LD representation of the page's text content
  /// suitable for search engine indexing.
  String toJsonLd() {
    final List<String> blocks = extractedBlocks;
    final String headline = blocks.isNotEmpty ? blocks.first : 'Untitled Flutter Page';
    final String articleBody = blocks.join('\n\n');
    final payload = <String, Object>{
      '@context': 'https://schema.org',
      '@type': 'Article',
      'headline': headline,
      'wordCount': wordCount,
      'textNodeCount': widgetCount,
      'articleBody': articleBody,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  @override
  void didAddText(TextDelegate delegate) {
    _delegates.add(delegate);
    _notifyListenersSafely();
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _notifyListenersSafely();
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    _delegates.remove(delegate);
    _notifyListenersSafely();
  }
}
