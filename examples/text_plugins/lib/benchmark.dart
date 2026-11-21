// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// A benchmark for the cost of text plugins on a page with a lot of text.
//
// Run it in profile mode, never in debug mode:
//
//     flutter run --profile -d macos -t lib/benchmark.dart
//
// The same file runs on the painter prototype (`text-plugin-mvp`) and on the
// inline-span prototype. What differs between the two is in
// `benchmark_compat.dart`.
//
// Each page is a column of N paragraphs that are all mounted and laid out.
// Every paragraph is its own repaint boundary, as an item of a list would be.
//
// A time is reported in two parts where there are two: the time of the call
// that changes something (for example setting the search query, which scans
// the text), and the time spent in drawFrame for the frames that follow:
// build, layout, paint and compositing. Raster time is not included.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'benchmark_compat.dart';
import 'plugins/search_in_page_plugin.dart';

/// How many frames are averaged for one number.
const int _runs = 20;

/// The page sizes, in paragraphs.
const List<int> _pageSizes = <int>[1000, 10000];

/// How many paragraphs change in one frame.
const List<int> _changedCounts = <int>[0, 1, 10, 100];

/// One paragraph in ten contains this word.
const String _query = 'Flutter';

late final _BenchmarkBinding _binding;

/// Times every call to [drawFrame].
class _BenchmarkBinding extends WidgetsFlutterBinding {
  final Stopwatch frameWatch = Stopwatch();

  @override
  void drawFrame() {
    frameWatch.start();
    try {
      super.drawFrame();
    } finally {
      frameWatch.stop();
    }
  }
}

class _NoopPlugin extends TextPlugin {}

String _paragraph(int index, int version) {
  final word = index % 10 == 0 ? _query : 'Nothing';
  return 'Paragraph $index, version $version: the quick brown fox jumps over '
      'the lazy dog. $word appears in this sentence.';
}

Widget _shell(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
      child: ColoredBox(color: const Color(0xFFFFFFFF), child: child),
    ),
  );
}

class _Page extends StatefulWidget {
  const _Page({
    super.key,
    required this.count,
    required this.plugins,
    this.variant,
    this.emptyScope = false,
  });

  final int count;

  /// The plugins of the scope. Null for no scope.
  final List<TextPlugin>? plugins;
  final Variant? variant;

  /// Whether to wrap the page in a scope that installs no plugin.
  final bool emptyScope;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  late final List<ValueNotifier<String>> texts = <ValueNotifier<String>>[
    for (var i = 0; i < widget.count; i++)
      ValueNotifier<String>(_paragraph(i, 0)),
  ];

  late List<TextPlugin>? plugins = widget.plugins;

  /// Changes [count] paragraphs, spread evenly over the page.
  void change(int count, int version) {
    if (count == 0) {
      return;
    }
    final int step = texts.length ~/ count;
    for (var i = 0; i < count; i++) {
      final int index = i * step;
      texts[index].value = _paragraph(index, version);
    }
  }

  /// Rebuilds the page, and with it every paragraph, without a change.
  void rebuild() {
    setState(() {});
  }

  /// Appends one paragraph that contains the query.
  void append() {
    setState(() {
      texts.add(ValueNotifier<String>(_paragraph(texts.length * 10, 0)));
    });
  }

  /// Replaces the plugins of the scope.
  void setPlugins(List<TextPlugin> value) {
    setState(() {
      plugins = value;
    });
  }

  @override
  void dispose() {
    for (final ValueNotifier<String> text in texts) {
      text.dispose();
    }
    super.dispose();
  }

  late final Widget _column = SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final ValueNotifier<String> text in texts)
          RepaintBoundary(
            child: ValueListenableBuilder<String>(
              valueListenable: text,
              builder: (BuildContext context, String value, Widget? child) {
                return Text(value);
              },
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The column is built again when the list of texts grows, and when
    // [rebuild] asks for it.
    Widget body = texts.length == widget.count && !_rebuildAll
        ? _column
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final ValueNotifier<String> text in texts)
                  RepaintBoundary(
                    child: ValueListenableBuilder<String>(
                      valueListenable: text,
                      builder:
                          (BuildContext context, String value, Widget? child) {
                            return Text(value);
                          },
                    ),
                  ),
              ],
            ),
          );
    final List<TextPlugin>? plugins = this.plugins;
    if (plugins != null) {
      body = wrapScope(plugins: plugins, variant: widget.variant!, child: body);
    } else if (widget.emptyScope) {
      body = TextPluginScope.none(child: body);
    }
    return _shell(body);
  }

  bool _rebuildAll = false;

  /// Whether [rebuild] builds every paragraph widget again (true), or only
  /// the page and its scope (false).
  set rebuildAll(bool value) => _rebuildAll = value;
}

/// Runs one frame now, without waiting for the engine to ask for it.
void _pumpFrame() {
  _binding.handleBeginFrame(null);
  _binding.handleDrawFrame();
}

/// Runs the frames that the last frame asked for.
void _settle() {
  for (var i = 0; i < 10 && _binding.hasScheduledFrame; i++) {
    _pumpFrame();
  }
}

class _Timing {
  const _Timing(this.change, this.frame);

  /// Milliseconds in the call that made the change.
  final double change;

  /// Milliseconds in drawFrame for the frames that followed.
  final double frame;

  @override
  String toString() =>
      '${(change + frame).toStringAsFixed(3)} ms '
      '(${change.toStringAsFixed(3)} change + ${frame.toStringAsFixed(3)} frame)';
}

/// Returns the average time of [change] and of the frames that follow it.
Future<_Timing> _measure(int runs, void Function(int run) change) async {
  _settle();
  final int before = _binding.frameWatch.elapsedMicroseconds;
  final changeWatch = Stopwatch();
  for (var run = 0; run < runs; run++) {
    changeWatch.start();
    change(run);
    changeWatch.stop();
    _pumpFrame();
    _settle();
  }
  final double frame =
      (_binding.frameWatch.elapsedMicroseconds - before) / runs / 1000.0;
  // Let the event loop run, so that the window stays responsive.
  await Future<void>.delayed(Duration.zero);
  return _Timing(changeWatch.elapsedMicroseconds / runs / 1000.0, frame);
}

final List<String> _lines = <String>[];

void _report(String line) {
  _lines.add(line);
  debugPrint('BENCHMARK $line');
}

Future<void> _mount(Widget widget) async {
  runApp(widget);
  // The first frame of a new root widget is a warm-up frame that runs from
  // timers. Wait for it, then run whatever it asked for.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  _settle();
}

Future<void> _unmount() => _mount(const SizedBox.shrink());

enum _Kind { noScope, emptyScope, noop, search }

Future<void> _runPage(int count, _Kind kind, Variant? variant) async {
  final SearchInPagePlugin? search = kind == _Kind.search
      ? makeSearch(variant!)
      : null;
  final List<TextPlugin>? plugins = switch (kind) {
    _Kind.noScope || _Kind.emptyScope => null,
    _Kind.noop => <TextPlugin>[_NoopPlugin()],
    _Kind.search => <TextPlugin>[search!],
  };
  final pageKey = GlobalKey<_PageState>();
  final String name = switch (kind) {
    _Kind.noScope => 'no scope',
    _Kind.emptyScope => 'scope without plugins',
    _Kind.noop => 'no-op plugin [${variant!.label}]',
    _Kind.search => 'search plugin [${variant!.label}]',
  };
  final label = 'N=$count, $name';

  final int beforeMount = _binding.frameWatch.elapsedMicroseconds;
  await _mount(
    _Page(
      key: pageKey,
      count: count,
      plugins: plugins,
      variant: variant,
      emptyScope: kind == _Kind.emptyScope,
    ),
  );
  final double mount =
      (_binding.frameWatch.elapsedMicroseconds - beforeMount) / 1000.0;
  _report('$label: P1 mount the page: ${mount.toStringAsFixed(3)} ms');
  final _PageState page = pageKey.currentState!;
  counters();

  if (search != null) {
    // P6. The first search over the whole page.
    final _Timing first = await _measure(1, (int run) {
      search.query = _query;
    });
    _report(
      '$label: P6 first search, ${search.matches.length} matches: $first'
      ' [${counters()}]',
    );
  }

  // P1. A frame in which k paragraphs change.
  for (final int changed in _changedCounts) {
    final _Timing timing = await _measure(_runs, (int run) {
      page.change(changed, 1 + run % 2);
    });
    _report(
      '$label: P1 frame with $changed changed paragraphs: '
      '${timing.frame.toStringAsFixed(3)} ms',
    );
  }

  // P1. A frame that rebuilds every paragraph widget, with no change.
  page.rebuildAll = true;
  final _Timing rebuild = await _measure(_runs, (int run) {
    page.rebuild();
  });
  page.rebuildAll = false;
  _report(
    '$label: P1 frame that rebuilds all paragraphs: '
    '${rebuild.frame.toStringAsFixed(3)} ms',
  );

  if (search != null) {
    counters();
    // P2. A keystroke in the search field: the query changes, and every text
    // that matched gets a different highlight.
    final _Timing keystroke = await _measure(_runs, (int run) {
      search.query = run.isEven ? 'Flutte' : _query;
    });
    _report(
      '$label: P2 query change, 10% of the texts match: $keystroke'
      ' [per run: ${counters()} / $_runs]',
    );

    // P2b. The active match moves to the next text.
    search.query = _query;
    _settle();
    counters();
    final _Timing next = await _measure(_runs, (int run) {
      search.nextMatch();
    });
    _report('$label: P2b next match: $next [per run: ${counters()} / $_runs]');

    // P3. A keystroke that matches nothing, before and after.
    search.query = 'qqqq';
    _settle();
    counters();
    final _Timing nothing = await _measure(_runs, (int run) {
      search.query = run.isEven ? 'qqqqq' : 'qqqq';
    });
    _report(
      '$label: P3 query change, no text matches: $nothing'
      ' [per run: ${counters()} / $_runs]',
    );

    // P1. A frame in which one paragraph that matches is appended.
    search.query = _query;
    _settle();
    final _Timing append = await _measure(_runs, (int run) {
      page.append();
    });
    _report(
      '$label: P1 frame that appends one paragraph: '
      '${append.frame.toStringAsFixed(3)} ms',
    );
  }

  await _unmount();
  search?.dispose();
}

/// P8. A scope that has no plugin gets its first one, and loses it again.
Future<void> _runFirstPlugin(int count, Variant variant) async {
  final pageKey = GlobalKey<_PageState>();
  await _mount(
    _Page(
      key: pageKey,
      count: count,
      plugins: const <TextPlugin>[],
      variant: variant,
    ),
  );
  final _PageState page = pageKey.currentState!;
  final plugin = _NoopPlugin();
  final _Timing add = await _measure(1, (int run) {
    page.setPlugins(<TextPlugin>[plugin]);
  });
  final _Timing remove = await _measure(1, (int run) {
    page.setPlugins(const <TextPlugin>[]);
  });
  _report(
    'N=$count, [${variant.label}]: P8 first plugin added to the scope: '
    '${add.frame.toStringAsFixed(3)} ms, removed: ${remove.frame.toStringAsFixed(3)} ms',
  );
  await _unmount();
}

/// P4. One long paragraph in which the highlighted word moves.
Future<void> _runKaraoke(Variant? variant) async {
  final String text = List<String>.generate(
    2000,
    (int i) => 'word$i',
  ).join(' ');
  final KaraokePlugin? plugin = variant == null ? null : KaraokePlugin();
  Widget body = SingleChildScrollView(
    child: RepaintBoundary(child: Text(text)),
  );
  if (plugin != null) {
    body = wrapScope(
      plugins: <TextPlugin>[plugin],
      variant: variant!,
      child: body,
    );
  }
  await _mount(_shell(body));
  final _Timing step = await _measure(100, (int run) {
    plugin?.step();
  });
  _report(
    'P4 moving word in a paragraph of 2000 words, '
    '${variant == null ? 'no plugin (idle frame)' : '[${variant.label}]'}: $step',
  );
  await _unmount();
}

/// P5. Typing in a text field whose text has matches.
Future<void> _runTyping(Variant? variant) async {
  final controller = TextEditingController(
    text: List<String>.filled(
      40,
      'The quick brown fox jumps over the lazy dog.',
    ).join(' '),
  );
  final focusNode = FocusNode();
  final SearchInPagePlugin? search = variant == null
      ? null
      : makeSearch(variant);
  Widget body = EditableText(
    controller: controller,
    focusNode: focusNode,
    maxLines: null,
    style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
    cursorColor: const Color(0xFF000000),
    backgroundCursorColor: const Color(0xFF888888),
  );
  if (search != null) {
    body = wrapScope(
      plugins: <TextPlugin>[search],
      variant: variant!,
      child: body,
    );
  }
  await _mount(_shell(body));
  search?.query = 'fox';
  _settle();
  final _Timing typing = await _measure(100, (int run) {
    controller.text = '${controller.text}x';
  });
  _report(
    'P5 typing one character in a field of 1800 characters with 40 matches, '
    '${variant == null ? 'no plugin' : '[${variant.label}]'}: '
    '${typing.frame.toStringAsFixed(3)} ms',
  );
  await _unmount();
  search?.dispose();
  controller.dispose();
  focusNode.dispose();
}

Future<void> _runAll() async {
  _report(
    kDebugMode
        ? 'WARNING: debug mode. These numbers are not valid. Use --profile.'
        : 'prototype: $branchLabel, mode: ${kProfileMode ? 'profile' : 'release'}, '
              '${kIsWeb ? 'web' : defaultTargetPlatform.name}',
  );
  _report(
    'each frame time is the average of $_runs frames unless it says otherwise',
  );
  for (final int count in _pageSizes) {
    await _runPage(count, _Kind.noScope, null);
    await _runPage(count, _Kind.emptyScope, null);
    for (final Variant variant in variants) {
      await _runPage(count, _Kind.noop, variant);
      await _runPage(count, _Kind.search, variant);
    }
  }
  for (final int count in _pageSizes) {
    for (final Variant variant in variants.take(2)) {
      await _runFirstPlugin(count, variant);
    }
  }
  await _runKaraoke(null);
  for (final Variant variant in variants.take(2)) {
    await _runKaraoke(variant);
  }
  await _runTyping(null);
  for (final Variant variant in variants.take(2)) {
    await _runTyping(variant);
  }
  _report('done');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            _lines.join('\n'),
            style: const TextStyle(fontSize: 13, color: Color(0xFF000000)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  _binding = _BenchmarkBinding();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFFFFFFFF),
        child: Center(
          child: Text(
            'Running the text plugin benchmark...',
            style: TextStyle(fontSize: 16, color: Color(0xFF000000)),
          ),
        ),
      ),
    ),
  );
  // Let the first frame show before the work starts.
  Timer(const Duration(milliseconds: 500), _runAll);
}
