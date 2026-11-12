// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'plugins/frosted_spoiler_plugin.dart';
import 'plugins/spellcheck_linter_plugin.dart';
import 'plugins/spellcheck_suggestions_plugin.dart';

void main() {
  runApp(const TextPluginsDemoApp());
}

/// A small app for trying out the two text plugins that build widgets:
/// [SpellcheckSuggestionsPlugin] and [FrostedSpoilerPlugin].
class TextPluginsDemoApp extends StatelessWidget {
  /// Creates the [TextPluginsDemoApp].
  const TextPluginsDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Text plugins with widgets',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      home: const TextPluginsHomePage(),
    );
  }
}

/// The page of the demo: a list of things to try, and text to try them on.
class TextPluginsHomePage extends StatefulWidget {
  /// Creates the [TextPluginsHomePage].
  const TextPluginsHomePage({super.key});

  @override
  State<TextPluginsHomePage> createState() => _TextPluginsHomePageState();
}

class _TextPluginsHomePageState extends State<TextPluginsHomePage>
    with SingleTickerProviderStateMixin {
  // Shown at the top of the page, outside the scope of the plugins.
  static const List<String> _whatToTry = <String>[
    'Paragraphs: click a word with a wavy underline. A menu opens next to '
        'it and shows the suggestion. It only offers to replace the word '
        'in a text field: a plugin cannot change the text of a Text widget.',
    'Paragraphs: click a blurred span to show it, and again to hide it.',
    'Text field: click "recieve". The caret moves and the menu opens. '
        '"Replace with" fixes the word. The plugin edits through the field.',
    'Text field: move the caret into the blurred span and out again. The '
        'span is clear while the caret is inside.',
    'Selection: drag to select the text, also starting on a blurred span.',
    'Moving text: open a menu and watch it follow the card. The blur moves '
        'with the text.',
    'Scrolling: scroll with a menu open. The menu closes, and the blur '
        'scrolls with the text.',
    'Keyboard: Tab to a flagged word, Enter opens its menu, Escape closes '
        'it. Tab to a blurred span, Enter toggles it.',
    'Chips: the first one off leaves the painter-only spell check, '
        'underlines only. The second one off leaves the spoiler markers '
        'as plain text: a painter-only plugin cannot be tapped.',
  ];

  static const TextStyle _bodyStyle = TextStyle(fontSize: 16, height: 1.5);

  late final SpellcheckSuggestionsPlugin _suggestionsPlugin;
  late final SpellcheckLinterPlugin _linterPlugin;
  late final FrostedSpoilerPlugin _frostedPlugin;
  late final AnimationController _moveController;

  final TextEditingController _fieldController = TextEditingController(
    text: 'We recieve ||a secret|| by mail',
  );
  final ValueNotifier<String> _lastEvent = ValueNotifier<String>('none yet');

  // The paragraphs of the first section. The "Add as paragraph" button adds
  // the text of the field to them.
  final List<String> _paragraphs = <String>[
    'Teams recieve seperate alerts when a build fails. The ending of the '
        'story: ||the gardener was the heir all along||.',
    'We utilize one channel for deploys. Study card: {{RenderParagraph}} '
        'lays out text.',
  ];

  bool _useSuggestionMenu = true;
  bool _useFrostedGlass = true;
  bool _isMoving = true;

  @override
  void initState() {
    super.initState();
    _suggestionsPlugin = SpellcheckSuggestionsPlugin(
      onReplace: _handleReplaced,
    );
    _linterPlugin = SpellcheckLinterPlugin();
    _frostedPlugin = FrostedSpoilerPlugin(onMatchTapped: _handleSpoilerTapped);
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _moveController.dispose();
    _suggestionsPlugin.dispose();
    _frostedPlugin.dispose();
    _fieldController.dispose();
    _lastEvent.dispose();
    super.dispose();
  }

  // With its chip off, the spell check falls back to the painter-only
  // plugin, which still underlines. The spoilers have no painter-only
  // version: a plugin that only paints cannot be tapped, so it could not
  // show a span again.
  List<TextPlugin> get _plugins => <TextPlugin>[
    if (_useSuggestionMenu) _suggestionsPlugin else _linterPlugin,
    if (_useFrostedGlass) _frostedPlugin,
  ];

  void _handleSpoilerTapped(
    SpoilerMaskMatch match, {
    required bool isRevealed,
  }) {
    _lastEvent.value =
        '${match.kind.label.toLowerCase()} ${isRevealed ? 'shown' : 'hidden'}';
  }

  // Called after the plugin has replaced a word in the text field. In other
  // text the menu only shows the suggestion: a plugin cannot change the text
  // of a Text widget.
  void _handleReplaced(SpellcheckIssue issue, String replacement) {
    _lastEvent.value = 'replaced "${issue.matchedText}" with "$replacement"';
  }

  void _addParagraph() {
    final String text = _fieldController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _paragraphs.add(text);
    });
  }

  void _toggleMoving() {
    setState(() {
      _isMoving = !_isMoving;
      if (_isMoving) {
        _moveController.repeat();
      } else {
        _moveController.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primaryContainer,
        title: const Text('Text plugins with widgets'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildWhatToTry(colorScheme),
          _buildControls(colorScheme),
          Expanded(
            child: TextPluginScope.multiple(
              plugins: _plugins,
              child: SingleChildScrollView(
                key: const Key('article_scroll_view'),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildParagraphs(),
                        _buildTextField(),
                        _buildSelection(),
                        _buildMovingText(colorScheme),
                        _buildScrolling(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatToTry(ColorScheme colorScheme) {
    return Material(
      color: colorScheme.secondaryContainer,
      child: ExpansionTile(
        key: const Key('what_to_try'),
        initiallyExpanded: true,
        shape: const Border(),
        leading: const Icon(Icons.checklist),
        title: const Text(
          'What to try',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: <Widget>[
          // Scrolls by itself when the window is small.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (int index, String item) in _whatToTry.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${index + 1}. $item',
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            const Text(
              'Built with widgets:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            FilterChip(
              key: const Key('chip_suggestion_menu'),
              visualDensity: VisualDensity.compact,
              label: const Text('Suggestion menu'),
              tooltip: 'Off: the painter-only spell check, underlines only',
              selected: _useSuggestionMenu,
              onSelected: (bool value) {
                setState(() {
                  _useSuggestionMenu = value;
                });
              },
            ),
            FilterChip(
              key: const Key('chip_frosted_spoiler'),
              visualDensity: VisualDensity.compact,
              label: const Text('Frosted glass'),
              tooltip: 'Off: no spoiler plugin, the markers are plain text',
              selected: _useFrostedGlass,
              onSelected: (bool value) {
                setState(() {
                  _useFrostedGlass = value;
                });
              },
            ),
            ValueListenableBuilder<String>(
              valueListenable: _lastEvent,
              builder: (BuildContext context, String value, Widget? child) {
                return Text(
                  'Last event: $value',
                  key: const Key('last_event'),
                  style: const TextStyle(fontSize: 13),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParagraphs() {
    return _Section(
      title: '1. Paragraphs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < _paragraphs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _paragraphs[i],
                key: Key('custom_note_text_$i'),
                style: _bodyStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return _Section(
      title: '2. Text field',
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: const Key('custom_note_input'),
              controller: _fieldController,
              style: _bodyStyle,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (String value) => _addParagraph(),
            ),
          ),
          const SizedBox(width: 8),
          TextPluginScope.none(
            child: FilledButton.icon(
              key: const Key('add_note_button'),
              onPressed: _addParagraph,
              icon: const Icon(Icons.add),
              label: const Text('Add as paragraph'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelection() {
    return const _Section(
      title: '3. Selection',
      child: SelectionArea(
        key: Key('selection_area_zone'),
        child: Text(
          'Drag across this text to select it. It has a seperate typo and '
          'a ||hidden plot twist|| in it, and it is long enough to wrap '
          'onto a second line in a narrow window.',
          key: Key('selection_area_paragraph_1'),
          style: _bodyStyle,
        ),
      ),
    );
  }

  Widget _buildMovingText(ColorScheme colorScheme) {
    return _Section(
      title: '4. Moving text',
      trailing: IconButton(
        key: const Key('moving_card_toggle_button'),
        visualDensity: VisualDensity.compact,
        tooltip: _isMoving ? 'Pause' : 'Resume',
        icon: Icon(_isMoving ? Icons.pause : Icons.play_arrow),
        onPressed: _toggleMoving,
      ),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: AnimatedBuilder(
          animation: _moveController,
          builder: (BuildContext context, Widget? child) {
            final double angle = _moveController.value * 2 * math.pi;
            return Align(
              alignment: Alignment(math.sin(angle), math.sin(angle * 2)),
              child: child,
            );
          },
          child: FractionallySizedBox(
            widthFactor: 0.6,
            child: Card(
              margin: EdgeInsets.zero,
              color: colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'This card moves. We recieve ||a secret|| on the way.',
                  key: Key('moving_card_text'),
                  style: TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrolling() {
    return const _Section(
      title: '5. Scrolling',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'This section is here to make the page long enough to scroll. '
            'Open the menu on teh typo in this sentence, then scroll.',
            style: _bodyStyle,
          ),
          SizedBox(height: 160),
          Text(
            'Halfway down: an error occured, and ||nobody noticed||.',
            style: _bodyStyle,
          ),
          SizedBox(height: 160),
          Text(
            'Near the end: we utilize a second {{cloze answer}} here, and '
            'recieve one more typo.',
            style: _bodyStyle,
          ),
          SizedBox(height: 240),
          Text('The end of the page.', style: _bodyStyle),
        ],
      ),
    );
  }
}

/// A titled card. The title is not text for the plugins to decorate.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextPluginScope.none(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
