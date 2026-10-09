// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plugins/linkify_plugin.dart';
import 'plugins/pii_redaction_plugin.dart';
import 'plugins/read_aloud_plugin.dart';
import 'plugins/search_in_page_plugin.dart';
import 'plugins/seo_extractor_plugin.dart';
import 'plugins/spellcheck_linter_plugin.dart';
import 'plugins/stock_ticker_plugin.dart';

void main() {
  runApp(const TextPluginsDemoApp());
}

/// Demo application showcasing the [TextPlugin], [TextDelegate], and
/// [TextPluginScope] architecture from `Text-Plugins-One-Pager.md`.
class TextPluginsDemoApp extends StatelessWidget {
  /// Creates the [TextPluginsDemoApp].
  const TextPluginsDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Text Plugins Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4), // Modern Material 3 Purple
          brightness: Brightness.light,
          surface: const Color(0xFFFBFDF8),
          surfaceContainerHighest: const Color(0xFFEADDFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFBFDF8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFBFDF8),
          elevation: 0,
          scrolledUnderElevation: 2,
          centerTitle: false,
          iconTheme: IconThemeData(color: Color(0xFF1D1B20)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1D1B20),
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
          ),
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 8),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4EFF4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF6750A4), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
      ),
      home: const TextPluginsHomePage(),
    );
  }
}

/// Main interactive workbench for testing and composing [TextPlugin]s.
class TextPluginsHomePage extends StatefulWidget {
  /// Creates the [TextPluginsHomePage].
  const TextPluginsHomePage({super.key});

  @override
  State<TextPluginsHomePage> createState() => _TextPluginsHomePageState();
}

class _TextPluginsHomePageState extends State<TextPluginsHomePage> {
  late final SearchInPagePlugin _searchPlugin;
  late final StockTickerPlugin _stockTickerPlugin;
  late final LinkifyPlugin _linkifyPlugin;
  late final SeoExtractorPlugin _seoPlugin;
  late final PiiRedactionPlugin _piiPlugin;
  late final ReadAloudPlugin _readAloudPlugin;
  late final SpellcheckLinterPlugin _spellcheckPlugin;

  final TextEditingController _searchController = TextEditingController(text: 'Flutter');
  final TextEditingController _customNoteController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _enableSearchPlugin = true;
  bool _enableStockPlugin = true;
  bool _enableLinkifyPlugin = true;
  bool _enableSeoPlugin = true;
  bool _enablePiiPlugin = true;
  bool _enableReadAloudPlugin = true;
  bool _enableSpellcheckPlugin = true;
  bool _showSeoInspector = true;

  StockTickerInfo? _lastTappedTicker;
  String? _lastTappedUrl;
  PiiMatch? _lastTappedPii;
  bool _lastTappedPiiRevealed = false;
  SpellcheckIssue? _lastTappedSpellcheckIssue;

  static const String _initialCustomNote =
      r'Try $NVDA or $AAPL at https://pub.dev — teams recieve seperate alerts '
      r'and utilize token sk-live-9876543210abcdef (contact ops@example.com or SSN 123-45-6789).';

  final List<String> _customNotes = <String>[_initialCustomNote];

  @override
  void initState() {
    super.initState();
    _searchPlugin = SearchInPagePlugin()..query = _searchController.text;
    _stockTickerPlugin = StockTickerPlugin(onTickerTapped: _handleTickerTapped);
    _linkifyPlugin = LinkifyPlugin(onLinkTapped: _handleLinkTapped);
    _seoPlugin = SeoExtractorPlugin();
    _piiPlugin = PiiRedactionPlugin(onMatchTapped: _handlePiiTapped);
    _readAloudPlugin = ReadAloudPlugin();
    _spellcheckPlugin = SpellcheckLinterPlugin(onIssueTapped: _handleSpellcheckTapped);
  }

  @override
  void dispose() {
    _searchPlugin.dispose();
    _seoPlugin.dispose();
    _piiPlugin.dispose();
    _readAloudPlugin.dispose();
    _searchController.dispose();
    _customNoteController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handlePiiTapped(PiiMatch match, {required bool isRevealed}) {
    setState(() {
      _lastTappedPii = match;
      _lastTappedPiiRevealed = isRevealed;
    });
  }

  void _handleSpellcheckTapped(SpellcheckIssue issue) {
    setState(() {
      _lastTappedSpellcheckIssue = issue;
    });
  }

  void _handleTickerTapped(StockTickerInfo info) {
    setState(() {
      _lastTappedTicker = info;
    });
    if (!mounted) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        final bool isUp = info.isPositive;
        final badgeColor = isUp ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
        final sign = isUp ? '+' : '';
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: badgeColor),
                    ),
                    child: Text(
                      info.symbol,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(info.companyName, style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        '\$${info.price.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$sign${info.changePercent.toStringAsFixed(2)}%',
                        style: TextStyle(color: badgeColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Market Cap: ${info.marketCap}', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(info.summary, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
      },
    );
  }

  void _handleLinkTapped(String url) {
    setState(() {
      _lastTappedUrl = url;
    });
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Opened link via LinkifyPlugin: $url'),
          action: SnackBarAction(
            label: 'Copy URL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
            },
          ),
        ),
      );
  }

  void _addCustomNote() {
    final String text = _customNoteController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _customNotes.add(text);
      _customNoteController.clear();
    });
  }

  List<TextPlugin> get _activePlugins => <TextPlugin>[
    if (_enableStockPlugin) _stockTickerPlugin,
    if (_enableLinkifyPlugin) _linkifyPlugin,
    if (_enableSpellcheckPlugin) _spellcheckPlugin,
    if (_enableReadAloudPlugin) _readAloudPlugin,
    if (_enableSearchPlugin) _searchPlugin,
    if (_enablePiiPlugin) _piiPlugin,
    if (_enableSeoPlugin) _seoPlugin,
  ];

  void _activateFindInPage() {
    if (!_enableSearchPlugin) {
      setState(() {
        _enableSearchPlugin = true;
      });
    }
    _searchPlugin.eagerLoadOffscreenText = true;
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _activateFindInPage,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _activateFindInPage,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: colorScheme.primaryContainer,
            title: const Text('Flutter Text Plugins Workbench'),
            actions: <Widget>[
              IconButton(
                tooltip: _showSeoInspector ? 'Hide SEO Inspector' : 'Show SEO Inspector',
                icon: Icon(_showSeoInspector ? Icons.schema : Icons.schema_outlined),
                onPressed: () {
                  setState(() {
                    _showSeoInspector = !_showSeoInspector;
                  });
                },
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              _buildPluginControlHeader(colorScheme),
              if (_enableSearchPlugin) _buildSearchBar(colorScheme),
              if (_enableReadAloudPlugin) _buildReadAloudBar(colorScheme),
              if (_lastTappedTicker != null ||
                  _lastTappedUrl != null ||
                  _lastTappedPii != null ||
                  _lastTappedSpellcheckIssue != null)
                _buildInteractionBanner(colorScheme),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool wideScreen = constraints.maxWidth >= 720 && _showSeoInspector;
                    final Widget articleContent = _buildScopedArticleContent();
                    if (wideScreen) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(flex: 3, child: articleContent),
                          const VerticalDivider(width: 1),
                          Expanded(flex: 2, child: _buildSeoInspectorPanel()),
                        ],
                      );
                    }
                    return Column(
                      children: <Widget>[
                        Expanded(child: articleContent),
                        if (_showSeoInspector) ...<Widget>[
                          const Divider(height: 1),
                          SizedBox(height: 160, child: _buildSeoInspectorPanel()),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPluginControlHeader(ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Text(
              'Active TextPlugins:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.search, size: 16),
              label: const Text('Search in Page'),
              selected: _enableSearchPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableSearchPlugin = value;
                });
              },
            ),
            const SizedBox(width: 6),
            FilterChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.trending_up, size: 16),
              label: const Text('Stock Tickers'),
              selected: _enableStockPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableStockPlugin = value;
                });
              },
            ),
            const SizedBox(width: 6),
            FilterChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.link, size: 16),
              label: const Text('Linkify URLs'),
              selected: _enableLinkifyPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableLinkifyPlugin = value;
                });
              },
            ),
            const SizedBox(width: 6),
            FilterChip(
              key: const Key('chip_pii_plugin'),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.visibility_off_outlined, size: 16),
              label: const Text('PII Redaction'),
              selected: _enablePiiPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enablePiiPlugin = value;
                });
              },
            ),
            const SizedBox(width: 6),
            FilterChip(
              key: const Key('chip_spellcheck_plugin'),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.spellcheck, size: 16),
              label: const Text('Spellcheck Linter'),
              selected: _enableSpellcheckPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableSpellcheckPlugin = value;
                });
              },
            ),
            const SizedBox(width: 6),
            FilterChip(
              key: const Key('chip_read_aloud_plugin'),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.record_voice_over_outlined, size: 16),
              label: const Text('Read-Aloud (TTS)'),
              selected: _enableReadAloudPlugin,
              onSelected: (bool value) {
                if (!value) {
                  _readAloudPlugin.stop();
                }
                setState(() {
                  _enableReadAloudPlugin = value;
                });
              },
            ),
            const SizedBox(width: 6),
            FilterChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.analytics_outlined, size: 16),
              label: const Text('SEO Extractor'),
              selected: _enableSeoPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableSeoPlugin = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadAloudBar(ColorScheme colorScheme) {
    return ListenableBuilder(
      listenable: _readAloudPlugin,
      builder: (BuildContext context, Widget? child) {
        final ReadAloudWord? active = _readAloudPlugin.currentWord;
        final int total = _readAloudPlugin.words.length;
        final int current = active == null ? 0 : _readAloudPlugin.currentWordIndex + 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.record_voice_over, size: 18),
              const SizedBox(width: 8),
              Text(
                active != null
                    ? 'Speaking: "${active.word}" ($current/$total)'
                    : 'Read-Aloud Idle ($total words)',
                key: const Key('read_aloud_status'),
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                key: const Key('read_aloud_prev_word_button'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous word',
                icon: const Icon(Icons.skip_previous, size: 20),
                onPressed: total > 0 ? _readAloudPlugin.stepPreviousWord : null,
              ),
              IconButton(
                key: const Key('read_aloud_play_button'),
                visualDensity: VisualDensity.compact,
                tooltip: _readAloudPlugin.isPlaying ? 'Pause Read-Aloud' : 'Play Read-Aloud',
                icon: Icon(
                  _readAloudPlugin.isPlaying ? Icons.pause_circle : Icons.play_circle,
                  size: 22,
                ),
                onPressed: total > 0 ? _readAloudPlugin.togglePlay : null,
              ),
              IconButton(
                key: const Key('read_aloud_next_word_button'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Next word',
                icon: const Icon(Icons.skip_next, size: 20),
                onPressed: total > 0 ? _readAloudPlugin.stepNextWord : null,
              ),
              IconButton(
                key: const Key('read_aloud_stop_button'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Stop Read-Aloud',
                icon: const Icon(Icons.stop_circle_outlined, size: 20),
                onPressed: active != null ? _readAloudPlugin.stop : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return ListenableBuilder(
      listenable: _searchPlugin,
      builder: (BuildContext context, Widget? child) {
        final int total = _searchPlugin.matches.length;
        final int current = total == 0 ? 0 : _searchPlugin.activeMatchIndex + 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.find_in_page_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('search_input'),
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: const InputDecoration(
                    hintText: 'Find in page (e.g. Flutter, GOOG, Archive #20)...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (String value) {
                    _searchPlugin.query = value;
                  },
                  onSubmitted: (_) {
                    _searchPlugin.scrollToActiveMatch();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Aa'),
                tooltip: 'Case sensitive',
                selected: _searchPlugin.caseSensitive,
                onSelected: (bool value) {
                  _searchPlugin.caseSensitive = value;
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                key: const Key('eager_load_chip'),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.bolt, size: 16),
                label: const Text('Cancel Lazy Load'),
                tooltip: 'Eagerly lay out offscreen SliverList items (auto-enabled on Ctrl+F)',
                selected: _searchPlugin.eagerLoadOffscreenText,
                onSelected: (bool value) {
                  _searchPlugin.eagerLoadOffscreenText = value;
                },
              ),
              const SizedBox(width: 12),
              Text(
                '$current / $total',
                key: const Key('search_match_count'),
                style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
              ),
              IconButton(
                key: const Key('search_prev_button'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous match',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: total > 0 ? _searchPlugin.previousMatch : null,
              ),
              IconButton(
                key: const Key('search_next_button'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Next match',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: total > 0 ? _searchPlugin.nextMatch : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInteractionBanner(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: colorScheme.secondaryContainer,
      child: Wrap(
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (_lastTappedTicker != null)
            Text(
              'Last tapped ticker: ${_lastTappedTicker!.symbol} '
              '(\$${_lastTappedTicker!.price.toStringAsFixed(2)})',
              key: const Key('last_tapped_ticker'),
              style: TextStyle(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (_lastTappedUrl != null)
            Text(
              'Last tapped link: $_lastTappedUrl',
              key: const Key('last_tapped_url'),
              style: TextStyle(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (_lastTappedPii != null)
            Text(
              'PII (${_lastTappedPii!.kind.label}): '
              '${_lastTappedPiiRevealed ? "Revealed (${_lastTappedPii!.rawValue})" : "Masked (••••••••)"}',
              key: const Key('last_tapped_pii'),
              style: TextStyle(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (_lastTappedSpellcheckIssue != null)
            Text(
              'Lint "${_lastTappedSpellcheckIssue!.matchedText}" → '
              '"${_lastTappedSpellcheckIssue!.rule.suggestion}"',
              key: const Key('last_tapped_spellcheck'),
              style: TextStyle(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScopedArticleContent() {
    return TextPluginScope.multiple(
      plugins: _activePlugins,
      child: CustomScrollView(
        key: const Key('article_scroll_view'),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Composable Text Plugins in Flutter',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Every paragraph below is rendered using standard Flutter Text and Text.rich '
                    'widgets—no custom SearchableText or LinkText widgets required. Multiple '
                    'TextPlugins inspect, highlight, and handle pointer events on the same Text '
                    'widgets simultaneously.',
                    style: TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Market & Ecosystem Report (Tap any Ticker or URL)',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Flutter continues to power multi-platform applications built at '
                            'GOOG and across the industry. Developers building for AAPL iOS/macOS, '
                            'MSFT Windows, and web browsers can learn more at https://flutter.dev '
                            'and https://dart.dev.',
                            key: Key('market_report_text'),
                            style: TextStyle(fontSize: 15, height: 1.55),
                          ),
                          SizedBox(height: 10),
                          Text.rich(
                            TextSpan(
                              text: 'In hardware and cloud news, ',
                              style: TextStyle(fontSize: 15, height: 1.55),
                              children: <InlineSpan>[
                                TextSpan(
                                  text: 'NVDA and AMZN',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text:
                                      ' expanded AI infrastructure while TSLA updated its '
                                      'in-vehicle software. Agricultural tech updates are also '
                                      'available at http://www.goderfarmers.com for reference.',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Live Interactive TextField (EditableText)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Try typing GOOG, AAPL, https://flutter.dev, or search queries directly in '
                    'the TextField below. Active TextPlugins highlight, linkify, and lint '
                    'editable text live as you type!',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          key: const Key('custom_note_input'),
                          controller: _customNoteController,
                          decoration: const InputDecoration(
                            hintText: 'Type text with GOOG, AAPL, or https://example.com live...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addCustomNote(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextPluginScope.none(
                        child: FilledButton.icon(
                          key: const Key('add_note_button'),
                          onPressed: _addCustomNote,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Text'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _customNotes.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(_customNotes[i], key: Key('custom_note_text_$i')),
                        trailing: TextPluginScope.none(
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove paragraph',
                            onPressed: () {
                              setState(() {
                                _customNotes.removeAt(i);
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  TextPluginScope.none(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Opt-Out Zone (TextPluginScope.none)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'This Text widget is wrapped in TextPluginScope.none, so mentions of '
                            'GOOG, AAPL, Flutter, and https://flutter.dev inside this box are '
                            'intentionally ignored by ancestor plugins.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverList.builder(
              itemCount: 20,
              itemBuilder: (BuildContext context, int index) {
                final int itemNumber = index + 1;
                final isDeepTarget = itemNumber == 20;
                return Card(
                  key: Key('lazy_archive_card_$itemNumber'),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      isDeepTarget
                          ? 'Lazy Archive #$itemNumber — Deep Offscreen Target: Quantum Impeller '
                                'Pipeline for GOOG and AAPL at https://dart.dev/overview'
                          : 'Lazy Archive #$itemNumber — Historical research dispatch covering '
                                'cloud infrastructure for MSFT and NVDA.',
                      key: Key('lazy_archive_text_$itemNumber'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeoInspectorPanel() {
    return ListenableBuilder(
      listenable: _seoPlugin,
      builder: (BuildContext context, Widget? child) {
        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        return Container(
          color: colorScheme.surfaceContainerLowest,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.travel_explore, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Live SEO & Text Extractor',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Chip(
                    label: Text(
                      'Text Widgets: ${_seoPlugin.widgetCount}',
                      key: const Key('seo_widget_count'),
                    ),
                  ),
                  Chip(
                    label: Text('Words: ${_seoPlugin.wordCount}', key: const Key('seo_word_count')),
                  ),
                  Chip(label: Text('Chars: ${_seoPlugin.characterCount}')),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _enableSeoPlugin
                          ? _seoPlugin.toJsonLd()
                          : '// SEO Extractor plugin is currently disabled.',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
