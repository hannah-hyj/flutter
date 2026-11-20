// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

/// Severity of a [SpellcheckIssue].
enum LintSeverity {
  /// A spelling mistake (painted with a red wavy underline).
  spellingError,

  /// A style-guide suggestion (painted with an amber/blue wavy underline).
  styleSuggestion,
}

/// Rule definition for [SpellcheckLinterPlugin].
@immutable
class SpellcheckRule {
  /// Creates a [SpellcheckRule].
  const SpellcheckRule({
    required this.incorrectWord,
    required this.suggestion,
    required this.message,
    required this.severity,
  });

  /// The lowercase word token to flag.
  final String incorrectWord;

  /// Recommended replacement text.
  final String suggestion;

  /// Diagnostic explanation for the author.
  final String message;

  /// Severity of the diagnostic.
  final LintSeverity severity;
}

/// Represents a single spelling or style issue detected in a [TextDelegate].
@immutable
class SpellcheckIssue {
  /// Creates a [SpellcheckIssue].
  const SpellcheckIssue({
    required this.delegate,
    required this.range,
    required this.matchedText,
    required this.rule,
  });

  /// The [TextDelegate] containing this issue.
  final TextDelegate delegate;

  /// The character range of the flagged word within [TextDelegate.text].
  final TextRange range;

  /// The exact substring matched in the text.
  final String matchedText;

  /// The [SpellcheckRule] that triggered this diagnostic.
  final SpellcheckRule rule;
}

/// A [TextPlugin] that performs live spellchecking and editorial style-guide
/// linting across all [Text] and [RichText] widgets in its scope, painting
/// wavy underlines as [TextSpanDecoration]s.
class SpellcheckLinterPlugin extends TextPlugin {
  /// Creates a [SpellcheckLinterPlugin].
  SpellcheckLinterPlugin();

  /// Built-in spelling and style-guide rules.
  static const Map<String, SpellcheckRule> defaultRules =
      <String, SpellcheckRule>{
        'recieve': SpellcheckRule(
          incorrectWord: 'recieve',
          suggestion: 'receive',
          message: 'Spelling: "i" before "e" except after "c".',
          severity: LintSeverity.spellingError,
        ),
        'seperate': SpellcheckRule(
          incorrectWord: 'seperate',
          suggestion: 'separate',
          message: 'Spelling: "separate" is spelled with "-par-", not "-per-".',
          severity: LintSeverity.spellingError,
        ),
        'occured': SpellcheckRule(
          incorrectWord: 'occured',
          suggestion: 'occurred',
          message: 'Spelling: double "r" in past tense "occurred".',
          severity: LintSeverity.spellingError,
        ),
        'teh': SpellcheckRule(
          incorrectWord: 'teh',
          suggestion: 'the',
          message: 'Spelling: common keyboard transposition typo.',
          severity: LintSeverity.spellingError,
        ),
        'utilize': SpellcheckRule(
          incorrectWord: 'utilize',
          suggestion: 'use',
          message: 'Style Guide: prefer concise "use" over "utilize".',
          severity: LintSeverity.styleSuggestion,
        ),
      };

  static final RegExp _wordTokenizer = RegExp(r'\b[A-Za-z]+\b');

  final Map<TextDelegate, List<SpellcheckIssue>> _issuesByDelegate =
      <TextDelegate, List<SpellcheckIssue>>{};

  @override
  void didAddText(TextDelegate delegate) {
    _lintDelegate(delegate);
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _lintDelegate(delegate);
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    _issuesByDelegate.remove(delegate);
  }

  static const TextStyle _errorStyle = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: Color(0xFFD32F2F),
  );

  static const TextStyle _suggestionStyle = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: Color(0xFFEF6C00),
  );

  /// The issues found in the text of [delegate].
  List<SpellcheckIssue> issuesFor(TextDelegate delegate) =>
      _issuesByDelegate[delegate] ?? const <SpellcheckIssue>[];

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final List<SpellcheckIssue>? issues = _issuesByDelegate[delegate];
    if (issues == null) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      for (final SpellcheckIssue issue in issues)
        TextSpanDecoration(
          range: issue.range,
          style: issue.rule.severity == LintSeverity.spellingError
              ? _errorStyle
              : _suggestionStyle,
        ),
    ];
  }

  void _lintDelegate(TextDelegate delegate) {
    final String plainText = delegate.text;
    final issues = <SpellcheckIssue>[];
    for (final RegExpMatch match in _wordTokenizer.allMatches(plainText)) {
      final String word = match.group(0)!;
      final SpellcheckRule? rule = defaultRules[word.toLowerCase()];
      if (rule != null) {
        issues.add(
          SpellcheckIssue(
            delegate: delegate,
            range: TextRange(start: match.start, end: match.end),
            matchedText: word,
            rule: rule,
          ),
        );
      }
    }
    // The lifecycle callbacks run before the decorations of this text are
    // asked for, so recording the issues is all there is to do.
    if (issues.isEmpty) {
      _issuesByDelegate.remove(delegate);
    } else {
      _issuesByDelegate[delegate] = issues;
    }
  }
}
