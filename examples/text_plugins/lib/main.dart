// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plugins/linkify_plugin.dart';
import 'plugins/search_in_page_plugin.dart';
import 'plugins/seo_extractor_plugin.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
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

  final TextEditingController _searchController = TextEditingController(text: 'Flutter');
  final TextEditingController _customNoteController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _enableSearchPlugin = true;
  bool _enableStockPlugin = true;
  bool _enableLinkifyPlugin = true;
  bool _enableSeoPlugin = true;
  bool _showSeoInspector = true;

  StockTickerInfo? _lastTappedTicker;
  String? _lastTappedUrl;

  final List<String> _customNotes = <String>[
    r'Try adding a note mentioning $NVDA or $AAPL and https://pub.dev to see plugins react live!',
  ];

  @override
  void initState() {
    super.initState();
    _searchPlugin = SearchInPagePlugin()..query = _searchController.text;
    _stockTickerPlugin = StockTickerPlugin(onTickerTapped: _handleTickerTapped);
    _linkifyPlugin = LinkifyPlugin(onLinkTapped: _handleLinkTapped);
    _seoPlugin = SeoExtractorPlugin();
  }

  @override
  void dispose() {
    _searchPlugin.dispose();
    _seoPlugin.dispose();
    _searchController.dispose();
    _customNoteController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
    if (_enableSearchPlugin) _searchPlugin,
    if (_enableSeoPlugin) _seoPlugin,
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocusNode.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _searchFocusNode.requestFocus,
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
              if (_lastTappedTicker != null || _lastTappedUrl != null)
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              'Active TextPlugins:',
              style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
            FilterChip(
              avatar: const Icon(Icons.search, size: 18),
              label: const Text('Search in Page'),
              selected: _enableSearchPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableSearchPlugin = value;
                });
              },
            ),
            FilterChip(
              avatar: const Icon(Icons.trending_up, size: 18),
              label: const Text('Stock Tickers'),
              selected: _enableStockPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableStockPlugin = value;
                });
              },
            ),
            FilterChip(
              avatar: const Icon(Icons.link, size: 18),
              label: const Text('Linkify URLs'),
              selected: _enableLinkifyPlugin,
              onSelected: (bool value) {
                setState(() {
                  _enableLinkifyPlugin = value;
                });
              },
            ),
            FilterChip(
              avatar: const Icon(Icons.analytics_outlined, size: 18),
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

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return ListenableBuilder(
      listenable: _searchPlugin,
      builder: (BuildContext context, Widget? child) {
        final int total = _searchPlugin.matches.length;
        final int current = total == 0 ? 0 : _searchPlugin.activeMatchIndex + 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: const InputDecoration(
                    hintText: 'Find in page (e.g. Flutter, GOOG, http)...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (String value) {
                    _searchPlugin.query = value;
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Aa'),
                tooltip: 'Case sensitive',
                selected: _searchPlugin.caseSensitive,
                onSelected: (bool value) {
                  _searchPlugin.caseSensitive = value;
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
                tooltip: 'Previous match',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: total > 0 ? _searchPlugin.previousMatch : null,
              ),
              IconButton(
                key: const Key('search_next_button'),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
        ],
      ),
    );
  }

  Widget _buildScopedArticleContent() {
    return TextPluginScope.multiple(
      plugins: _activePlugins,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
              'Dynamic Content Playground',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextPluginScope.none(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('custom_note_input'),
                      controller: _customNoteController,
                      decoration: const InputDecoration(
                        hintText: 'Add a paragraph with GOOG, AAPL, or https://example.com...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addCustomNote(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('add_note_button'),
                    onPressed: _addCustomNote,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Text'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _customNotes.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(_customNotes[i]),
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
          ],
        ),
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
