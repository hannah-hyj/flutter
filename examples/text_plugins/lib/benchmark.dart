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
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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

/// With `--dart-define=TEXT=uniform` every paragraph is the same sentence
/// with a number in front, as in the first runs of this benchmark. That text
/// is unlike real text in a way that matters: the engine does not keep the
/// shaping of a paragraph in its cache if the paragraph starts or ends with
/// the same 40 characters as the one it cached before. The default is text in
/// which every paragraph is different.
const bool _uniformText = String.fromEnvironment('TEXT') == 'uniform';

const List<String> _vocabulary = <String>[
  'time',
  'people',
  'water',
  'music',
  'garden',
  'window',
  'river',
  'bright',
  'small',
  'quiet',
  'market',
  'letter',
  'summer',
  'winter',
  'forest',
  'silver',
  'yellow',
  'simple',
  'travel',
  'listen',
  'moment',
  'number',
  'family',
  'friend',
  'school',
  'street',
  'animal',
  'plant',
  'light',
  'sound',
  'paper',
  'stone',
  'cloud',
  'ocean',
  'bridge',
  'castle',
  'orange',
  'purple',
  'mirror',
  'candle',
  'pocket',
  'basket',
  'button',
  'carpet',
  'dinner',
  'engine',
  'guitar',
  'hammer',
  'island',
  'jacket',
  'kitten',
  'ladder',
  'magnet',
  'needle',
  'pencil',
  'rabbit',
  'saddle',
  'ticket',
  'violin',
]; // dart format off

/// [count] words that are different for every [seed]. [fixed] puts given words
/// at given positions.
String _words(int seed, int count, {Map<int, String> fixed = const <int, String>{}}) {
  int state = (seed * 2654435761 + 97) & 0x7fffffff;
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    if (i > 0) {
      buffer.write(' ');
    }
    buffer.write(fixed[i] ?? _vocabulary[(state >> 8) % _vocabulary.length]);
  }
  return buffer.toString();
}

/// A short paragraph of the stress page. One in ten contains the query.
String _paragraph(int index, int version) {
  if (_uniformText) {
    final word = index % 10 == 0 ? _query : 'Nothing';
    return 'Paragraph $index, version $version: the quick brown fox jumps over '
        'the lazy dog. $word appears in this sentence.';
  }
  return _words(index, 14, fixed: <int, String>{
    3: 'v$version',
    if (index % 10 == 0) 9: _rare,
  });
}

/// The word that one text in ten contains (one in twenty of the long ones).
const String _rare = _uniformText ? _query : 'counterclockwise';

/// Every part of [_rare] of four letters or more that is in no other word.
/// These are the queries of a user who types, corrects and types again: each
/// gives the same texts a different highlight.
final List<String> _rareQueries = <String>[
  for (var start = 0; start < _rare.length; start++)
    for (var end = start + 4; end <= _rare.length; end++)
      if (!_vocabulary.any((String word) => word.contains(_rare.substring(start, end))))
        _rare.substring(start, end),
];

/// A query that the texts with [_rare] match, different for every [run].
///
/// The engine keeps the shaping of the last 128 paragraphs that it laid out,
/// and a paragraph with a highlight that it has seen before is found there.
/// A user who types a new query produces highlights that it has not seen. So
/// the queries here do not come back before the cache has forgotten them.
String _rareQuery(int run) {
  if (_uniformText) {
    return run.isEven ? 'Flutte' : _query;
  }
  return _rareQueries[run % _rareQueries.length];
}

/// Two queries that alternate, as when a user types a letter and deletes it.
/// The engine has seen both highlights of every text.
String _rareQuerySeenBefore(int run) {
  if (_uniformText) {
    return run.isEven ? 'Flutte' : _query;
  }
  return run.isEven ? _rare.substring(0, _rare.length - 1) : _rare;
}

/// A query that every long paragraph matches about eight times.
String _commonQuery(int run) {
  if (_uniformText) {
    return run.isEven ? 'fo' : 'fox';
  }
  const queries = <String>['fo', 'fox', 'ox'];
  return queries[run % queries.length];
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

// ---------------------------------------------------------------------------
// Realistic cases. The cases above are stress cases: thousands of texts are
// mounted, and a thousand of them change in one frame. The cases below are
// sized like an app.
// ---------------------------------------------------------------------------

String _sentence(int index) {
  if (_uniformText) {
    final word = index % 10 == 0 ? _query : 'Nothing';
    return 'Item $index: the quick brown fox jumps over the lazy dog. '
        '$word appears in this sentence.';
  }
  return _words(index + 100000, 14, fixed: <int, String>{if (index % 10 == 0) 7: _rare});
}

/// R1. A lazy list of 10,000 items. Only the items on screen are built, which
/// is how a long page is written in an app.
Future<void> _runLazyList(Variant? variant) async {
  final SearchInPagePlugin? search = variant == null
      ? null
      : makeSearch(variant);
  final controller = ScrollController();
  Widget body = ListView.builder(
    controller: controller,
    itemCount: 10000,
    itemBuilder: (BuildContext context, int index) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Text(_sentence(index)),
      );
    },
  );
  if (search != null) {
    body = wrapScope(
      plugins: <TextPlugin>[search],
      variant: variant!,
      child: body,
    );
  }
  await _mount(_shell(body));
  final label =
      'R1 lazy list of 10000 items, ${variant == null ? 'no plugin' : '[${variant.label}]'}';
  if (search != null) {
    search.query = _query;
    _settle();
    final _Timing keystroke = await _measure(_runs * 5, (int run) {
      search.query = run.isEven ? 'Flutte' : _query;
    });
    _report(
      '$label: keystroke, ${search.matches.length} matches on screen: $keystroke',
    );
    final _Timing next = await _measure(_runs * 5, (int run) {
      search.nextMatch();
    });
    _report('$label: next match: $next');
    search.query = _query;
    _settle();
  }
  // Scroll by 120 pixels a frame, which brings new items in on every frame.
  var offset = 0.0;
  final _Timing scroll = await _measure(200, (int run) {
    offset += 120;
    controller.jumpTo(offset);
  });
  _report(
    '$label: scroll 120 px in a frame: ${scroll.frame.toStringAsFixed(3)} ms',
  );
  await _unmount();
  search?.dispose();
  controller.dispose();
}

String _longParagraph(int index) {
  if (_uniformText) {
    final word = index % 20 == 0 ? _query : 'Nothing';
    final buffer = StringBuffer('Section $index. ');
    for (var i = 0; i < 8; i++) {
      buffer.write('The quick brown fox jumps over the lazy dog and then rests. ');
    }
    buffer.write('$word appears here.');
    return buffer.toString();
  }
  // About 500 characters, with "fox" eight times.
  return _words(index + 200000, 80, fixed: <int, String>{
    for (var i = 5; i < 80; i += 10) i: 'fox',
    if (index % 20 == 0) 40: _rare,
  });
}

/// R2. An article: 300 paragraphs of about 500 characters, all mounted.
Future<void> _runArticle(Variant? variant) async {
  final SearchInPagePlugin? search = variant == null
      ? null
      : makeSearch(variant);
  Widget body = SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < 300; i++)
          RepaintBoundary(child: Text(_longParagraph(i))),
      ],
    ),
  );
  if (search != null) {
    body = wrapScope(
      plugins: <TextPlugin>[search],
      variant: variant!,
      child: body,
    );
  }
  await _mount(_shell(body));
  final label =
      'R2 article of 300 paragraphs, ${variant == null ? 'no plugin' : '[${variant.label}]'}';
  if (search == null) {
    final _Timing idle = await _measure(_runs, (int run) {});
    _report('$label: idle frame: ${idle.frame.toStringAsFixed(3)} ms');
  } else {
    search.query = _query;
    _settle();
    final _Timing rare = await _measure(_runs * 2, (int run) {
      search.query = run.isEven ? 'Flutte' : _query;
    });
    _report(
      '$label: keystroke, rare word, ${search.matches.length} matches in 15 texts: $rare',
    );
    search.query = 'fox';
    _settle();
    final _Timing common = await _measure(_runs * 2, (int run) {
      search.query = run.isEven ? 'fo' : 'fox';
    });
    _report(
      '$label: keystroke, common word, ${search.matches.length} matches in 300 texts: $common',
    );
    final _Timing next = await _measure(_runs * 2, (int run) {
      search.nextMatch();
    });
    _report('$label: next match: $next');
  }
  await _unmount();
  search?.dispose();
}

/// R3. One text whose highlighted word moves, for texts of different length.
Future<void> _runLength(int words, Variant variant) async {
  final String text = List<String>.generate(
    words,
    (int i) => 'word$i',
  ).join(' ');
  final plugin = KaraokePlugin();
  await _mount(
    _shell(
      wrapScope(
        plugins: <TextPlugin>[plugin],
        variant: variant,
        child: SingleChildScrollView(child: RepaintBoundary(child: Text(text))),
      ),
    ),
  );
  final _Timing step = await _measure(200, (int run) {
    plugin.step();
  });
  _report(
    'R3 moving word in one text of $words words (${text.length} characters), '
    '[${variant.label}]: ${step.frame.toStringAsFixed(3)} ms',
  );
  await _unmount();
}

/// R5. A highlight that is animated: its color changes on every frame, on
/// [count] texts at once.
Future<void> _runPulse(int count, Variant variant) async {
  final plugin = PulsePlugin();
  await _mount(
    _shell(
      wrapScope(
        plugins: <TextPlugin>[plugin],
        variant: variant,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < count; i++)
                RepaintBoundary(child: Text(_sentence(i))),
            ],
          ),
        ),
      ),
    ),
  );
  final _Timing tick = await _measure(200, (int run) {
    plugin.tick();
  });
  _report(
    'R5 animated highlight on $count texts, [${variant.label}]: '
    '${tick.frame.toStringAsFixed(3)} ms a frame',
  );
  await _unmount();
}

/// R6. A mouse drag that selects across 40 paragraphs, one pointer move a
/// frame.
Future<void> _runSelectionDrag(String label, VoidCallback setup) async {
  setup();
  final focusNode = FocusNode();
  await _mount(
    _shell(
      Overlay(
        initialEntries: <OverlayEntry>[
          OverlayEntry(
            builder: (BuildContext context) {
              return SelectableRegion(
                focusNode: focusNode,
                selectionControls: emptyTextSelectionControls,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (var i = 0; i < 40; i++)
                      RepaintBoundary(child: Text(_sentence(i))),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
  const start = Offset(20, 8);
  var time = Duration.zero;
  GestureBinding.instance.handlePointerEvent(
    const PointerAddedEvent(
      pointer: 7,
      kind: PointerDeviceKind.mouse,
      position: start,
    ),
  );
  GestureBinding.instance.handlePointerEvent(
    const PointerDownEvent(
      pointer: 7,
      kind: PointerDeviceKind.mouse,
      position: start,
      buttons: kPrimaryButton,
    ),
  );
  _pumpFrame();
  _settle();
  const steps = 100;
  final _Timing drag = await _measure(steps, (int run) {
    time += const Duration(milliseconds: 16);
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        timeStamp: time,
        position: start + Offset(3.0 * (run + 1), 5.0 * (run + 1)),
        delta: const Offset(3, 5),
        buttons: kPrimaryButton,
      ),
    );
  });
  // Count the paragraphs that have a selection, to know that the drag did
  // select.
  var selected = 0;
  void visit(RenderObject object) {
    if (object is RenderParagraph &&
        object.selections.any((TextSelection s) => !s.isCollapsed)) {
      selected += 1;
    }
    object.visitChildren(visit);
  }

  RendererBinding.instance.renderViews.first.visitChildren(visit);
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      pointer: 7,
      kind: PointerDeviceKind.mouse,
      timeStamp: time,
      position: start + const Offset(3.0 * steps, 5.0 * steps),
    ),
  );
  GestureBinding.instance.handlePointerEvent(
    const PointerRemovedEvent(pointer: 7, kind: PointerDeviceKind.mouse),
  );
  _report(
    'R6 selection drag across 40 paragraphs, $label: $drag a pointer move, '
    '$selected paragraphs selected at the end',
  );
  await _unmount();
  focusNode.dispose();
}

/// R2b. The common-word keystroke of the article, with a search plugin that
/// spreads the new decorations over frames. Reports the longest frame and how
/// many frames it takes until every highlight is there.
Future<void> _runArticleBatched(int perFrame, Variant variant) async {
  // Nullable on the painter branch, where there is no such plugin.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  final SearchInPagePlugin? search = makeBatchedSearch(perFrame);
  if (search == null) {
    return;
  }
  await _mount(
    _shell(
      wrapScope(
        plugins: <TextPlugin>[search],
        variant: variant,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < 300; i++)
                RepaintBoundary(child: Text(_longParagraph(i))),
            ],
          ),
        ),
      ),
    ),
  );
  search.query = 'fox';
  _settle();
  var longest = 0.0;
  var frames = 0;
  var total = 0.0;
  const runs = 10;
  for (var run = 0; run < runs; run++) {
    search.query = run.isEven ? 'fo' : 'fox';
    for (var i = 0; i < 100; i++) {
      final int before = _binding.frameWatch.elapsedMicroseconds;
      _pumpFrame();
      final double frame =
          (_binding.frameWatch.elapsedMicroseconds - before) / 1000.0;
      frames += 1;
      total += frame;
      if (frame > longest) {
        longest = frame;
      }
      if (!_binding.hasScheduledFrame) {
        break;
      }
    }
    await Future<void>.delayed(Duration.zero);
  }
  _report(
    'R2b article, common word, at most $perFrame texts a frame, [${variant.label}]: '
    'longest frame ${longest.toStringAsFixed(3)} ms, '
    '${(frames / runs).toStringAsFixed(1)} frames and '
    '${(total / runs).toStringAsFixed(3)} ms in total for a keystroke',
  );
  await _unmount();
  search.dispose();
}

// ---------------------------------------------------------------------------
// Loops for a CPU profiler. Each runs one case over and over for a fixed time
// and prints a marker when it starts and ends, so that a profiler can be
// attached for exactly that time. See tool/cpu_profile.dart.
// ---------------------------------------------------------------------------

const Duration _loopTime = Duration(milliseconds: 7500);

Future<void> _loop(String name, void Function(int run) change) async {
  _settle();
  _report('LOOP START $name');
  final total = Stopwatch()..start();
  final work = Stopwatch();
  var run = 0;
  while (total.elapsed < _loopTime) {
    work.start();
    for (var i = 0; i < 5; i++) {
      change(run);
      run += 1;
      _pumpFrame();
      _settle();
    }
    work.stop();
    // Let the event loop run, so that the profiler can be talked to.
    await Future<void>.delayed(Duration.zero);
  }
  _report(
    'LOOP END $name, $run iterations, '
    '${(work.elapsedMicroseconds / run / 1000.0).toStringAsFixed(4)} ms each',
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Widget _column(int count, String Function(int index) text) {
  return SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < count; i++) RepaintBoundary(child: Text(text(i))),
      ],
    ),
  );
}

Future<void> _runProfilerLoops() async {
  // Which way of running a plugin: on the span branch 0 is the widget layer
  // and 1 is the render layer. The painter branch has one.
  const index = int.fromEnvironment('LOOP_VARIANT', defaultValue: 1);
  final Variant variant =
      variants[index < variants.length ? index : variants.length - 1];
  const only = String.fromEnvironment('LOOP_ONLY');
  bool wanted(String name) => only.isEmpty || name.startsWith(only);

  // R1. The lazy list.
  if (wanted('R1')) {
    final SearchInPagePlugin search = makeSearch(variant);
    final controller = ScrollController();
    await _mount(
      _shell(
        wrapScope(
          plugins: <TextPlugin>[search],
          variant: variant,
          child: ListView.builder(
            controller: controller,
            itemCount: 10000,
            itemBuilder: (BuildContext context, int index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(_sentence(index)),
              );
            },
          ),
        ),
      ),
    );
    search.query = _rare;
    await _loop('R1 lazy list keystroke', (int run) {
      search.query = _rareQuery(run);
    });
    search.query = _rare;
    await _loop('R1 lazy list keystroke, highlights seen before', (int run) {
      search.query = _rareQuerySeenBefore(run);
    });
    search.query = _rare;
    await _loop('R1 lazy list next match', (int run) {
      search.nextMatch();
    });
    search.query = _rare;
    _settle();
    var offset = 0.0;
    var direction = 120.0;
    await _loop('R1 lazy list scroll', (int run) {
      if (offset > 500000 || offset + direction < 0) {
        direction = -direction;
      }
      offset += direction;
      controller.jumpTo(offset);
    });
    await _unmount();
    search.dispose();
    controller.dispose();
  }

  // R2. The article.
  if (wanted('R2')) {
    final SearchInPagePlugin search = makeSearch(variant);
    await _mount(
      _shell(
        wrapScope(
          plugins: <TextPlugin>[search],
          variant: variant,
          child: _column(300, _longParagraph),
        ),
      ),
    );
    search.query = _rare;
    await _loop('R2 article keystroke rare word', (int run) {
      search.query = _rareQuery(run);
    });
    search.query = _rare;
    await _loop('R2 article keystroke rare word, highlights seen before', (int run) {
      search.query = _rareQuerySeenBefore(run);
    });
    search.query = 'fox';
    await _loop('R2 article keystroke common word', (int run) {
      search.query = _commonQuery(run);
    });
    search.query = 'fox';
    await _loop('R2 article next match', (int run) {
      search.nextMatch();
    });
    await _unmount();
    search.dispose();
  }

  // R3 and P4. One text whose highlighted word moves.
  for (final words in <int>[10, 50, 200, 1000, 2000]) {
    final name = 'R3 moving word $words words';
    if (!wanted(name)) {
      continue;
    }
    final String text = List<String>.generate(
      words,
      (int i) => 'word$i',
    ).join(' ');
    final plugin = KaraokePlugin();
    await _mount(
      _shell(
        wrapScope(
          plugins: <TextPlugin>[plugin],
          variant: variant,
          child: SingleChildScrollView(
            child: RepaintBoundary(child: Text(text)),
          ),
        ),
      ),
    );
    await _loop(name, (int run) {
      plugin.step();
    });
    await _unmount();
  }

  // R5. The animated highlight.
  for (final count in <int>[10, 40]) {
    final name = 'R5 animated highlight $count texts';
    if (!wanted(name)) {
      continue;
    }
    final pulse = PulsePlugin();
    await _mount(
      _shell(
        wrapScope(
          plugins: <TextPlugin>[pulse],
          variant: variant,
          child: _column(count, _sentence),
        ),
      ),
    );
    await _loop(name, (int run) {
      pulse.tick();
    });
    await _unmount();
  }

  // R6. The selection drag.
  if (wanted('R6')) {
    final int mode = index + 1 < selectionModes.length
        ? index + 1
        : selectionModes.length - 1;
    selectionModes[mode].$2();
    final focusNode = FocusNode();
    await _mount(
      _shell(
        Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(
              builder: (BuildContext context) {
                return SelectableRegion(
                  focusNode: focusNode,
                  selectionControls: emptyTextSelectionControls,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (var i = 0; i < 40; i++)
                        RepaintBoundary(child: Text(_sentence(i))),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
    const start = Offset(20, 8);
    var time = Duration.zero;
    Offset last = start;
    GestureBinding.instance.handlePointerEvent(
      const PointerAddedEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        position: start,
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      const PointerDownEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        position: start,
        buttons: kPrimaryButton,
      ),
    );
    _pumpFrame();
    await _loop('R6 selection drag (${selectionModes[mode].$1})', (int run) {
      // Back and forth over 100 steps.
      final int step = run % 200 < 100 ? run % 200 : 200 - run % 200;
      final Offset position = start + Offset(3.0 * (step + 1), 5.0 * (step + 1));
      final Offset delta = position - last;
      last = position;
      time += const Duration(milliseconds: 16);
      GestureBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          pointer: 7,
          kind: PointerDeviceKind.mouse,
          timeStamp: time,
          position: position,
          delta: delta,
          buttons: kPrimaryButton,
        ),
      );
    });
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        timeStamp: time,
        position: last,
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      const PointerRemovedEvent(pointer: 7, kind: PointerDeviceKind.mouse),
    );
    await _unmount();
    focusNode.dispose();
    selectionModes.first.$2();
  }

  // P5. Typing in a text field with matches.
  if (wanted('P5')) {
    // About 1800 characters with "fox" 40 times.
    final String initial = _uniformText
        ? List<String>.filled(40, 'The quick brown fox jumps over the lazy dog.').join(' ')
        : _words(7, 280, fixed: <int, String>{for (var i = 3; i < 280; i += 7) i: 'fox'});
    final controller = TextEditingController(text: initial);
    final focusNode = FocusNode();
    final SearchInPagePlugin search = makeSearch(variant);
    await _mount(
      _shell(
        wrapScope(
          plugins: <TextPlugin>[search],
          variant: variant,
          child: EditableText(
            controller: controller,
            focusNode: focusNode,
            maxLines: null,
            style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
            cursorColor: const Color(0xFF000000),
            backgroundCursorColor: const Color(0xFF888888),
          ),
        ),
      ),
    );
    search.query = 'fox';
    await _loop('P5 typing in a field', (int run) {
      // A text that the engine has not seen, and that does not grow.
      controller.text = '$initial ${run % 100000}';
    });
    await _unmount();
    search.dispose();
    controller.dispose();
    focusNode.dispose();
  }

  // P2, P2b, P3. The stress page: N short paragraphs, all mounted.
  for (final count in <int>[1000, 10000]) {
    if (!wanted('P2 N=$count') && !wanted('P3 N=$count')) {
      continue;
    }
    final SearchInPagePlugin search = makeSearch(variant);
    await _mount(
      _shell(
        wrapScope(
          plugins: <TextPlugin>[search],
          variant: variant,
          child: _column(count, (int i) => _paragraph(i, 0)),
        ),
      ),
    );
    search.query = _rare;
    await _loop('P2 N=$count keystroke', (int run) {
      search.query = _rareQuery(run);
    });
    search.query = _rare;
    await _loop('P2 N=$count next match', (int run) {
      search.nextMatch();
    });
    search.query = 'qqqq';
    await _loop('P3 N=$count keystroke no match', (int run) {
      search.query = run.isEven ? 'qqqqq' : 'qqqq';
    });
    await _unmount();
    search.dispose();
  }

  // P1. A rebuild of every paragraph widget, with a plugin that does nothing.
  if (wanted('P1')) {
    final pageKey = GlobalKey<_PageState>();
    await _mount(
      _Page(
        key: pageKey,
        count: 1000,
        plugins: <TextPlugin>[_NoopPlugin()],
        variant: variant,
      ),
    );
    final _PageState page = pageKey.currentState!;
    page.rebuildAll = true;
    await _loop('P1 N=1000 rebuild all, no-op plugin', (int run) {
      page.rebuild();
    });
    await _unmount();
  }

  // P8. The first plugin is added to a scope, and removed again.
  if (wanted('P8')) {
    final pageKey = GlobalKey<_PageState>();
    await _mount(
      _Page(
        key: pageKey,
        count: 1000,
        plugins: const <TextPlugin>[],
        variant: variant,
      ),
    );
    final _PageState page = pageKey.currentState!;
    final plugin = _NoopPlugin();
    await _loop('P8 N=1000 first plugin added and removed', (int run) {
      page.setPlugins(run.isEven ? <TextPlugin>[plugin] : const <TextPlugin>[]);
    });
    await _unmount();
  }
}

Future<void> _runRealistic() async {
  final List<Variant> precise = variants.take(2).toList();
  await _runLazyList(null);
  for (final variant in precise) {
    await _runLazyList(variant);
  }
  await _runArticle(null);
  for (final variant in precise) {
    await _runArticle(variant);
  }
  for (final perFrame in <int>[25, 50]) {
    await _runArticleBatched(perFrame, precise.last);
  }
  for (final words in <int>[10, 50, 200, 1000]) {
    for (final variant in precise) {
      await _runLength(words, variant);
    }
  }
  for (final count in <int>[10, 40]) {
    for (final variant in precise) {
      await _runPulse(count, variant);
    }
  }
  for (final (String label, VoidCallback setup) in selectionModes) {
    await _runSelectionDrag(label, setup);
  }
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
  const which = String.fromEnvironment('BENCH');
  if (which == 'loops') {
    await _runProfilerLoops();
    _report('done');
    return;
  }
  if (which == 'breakdown') {
    for (final String line in runBreakdown(_longParagraph(0))) {
      _report(line);
    }
    _report('done');
    return;
  }
  if (which != 'stress') {
    await _runRealistic();
  }
  if (which == 'realistic') {
    _report('done');
    return;
  }
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
