// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// A benchmark for the cost of text plugins on a page with a lot of text.
//
// Run it in profile mode, never in debug mode:
//
//     flutter run --profile -d macos -t lib/benchmark.dart
//
// It answers two review questions on the RFC:
//
//  * Does the cost of the plugin lifecycle follow the amount of text that
//    changed in a frame, and not the amount of text on the page?
//  * On a very large page, is appending a little text fast, even if the first
//    search is slow?
//
// Each page is a column of N paragraphs that are all mounted and laid out.
// Every paragraph is its own repaint boundary, as an item of a list would be.
// The same page is measured three ways: with no TextPluginScope, with a
// plugin that does nothing, and with SearchInPagePlugin and an active query.
//
// The time reported for a frame is the time spent in drawFrame: build,
// layout, the post-layout plugin callbacks, paint and compositing. Raster
// time is not included.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

enum _Mode {
  noScope('no scope'),
  noopPlugin('no-op plugin'),
  searchPlugin('search plugin');

  const _Mode(this.label);

  final String label;
}

String _paragraph(int index, int version) {
  final word = index % 10 == 0 ? _query : 'Nothing';
  return 'Paragraph $index, version $version: the quick brown fox jumps over '
      'the lazy dog. $word appears in this sentence.';
}

class _Page extends StatefulWidget {
  const _Page({super.key, required this.count, required this.plugin});

  final int count;
  final TextPlugin? plugin;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  late final List<ValueNotifier<String>> texts = <ValueNotifier<String>>[
    for (var i = 0; i < widget.count; i++)
      ValueNotifier<String>(_paragraph(i, 0)),
  ];

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

  /// Appends one paragraph that contains the query.
  void append() {
    setState(() {
      texts.add(ValueNotifier<String>(_paragraph(texts.length * 10, 0)));
    });
  }

  @override
  void dispose() {
    for (final ValueNotifier<String> text in texts) {
      text.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body = SingleChildScrollView(
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
    final TextPlugin? plugin = widget.plugin;
    if (plugin != null) {
      body = TextPluginScope(plugin: plugin, child: body);
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
        child: ColoredBox(color: const Color(0xFFFFFFFF), child: body),
      ),
    );
  }
}

Future<void> _settle() async {
  while (_binding.hasScheduledFrame) {
    await _binding.endOfFrame;
  }
}

/// Returns the average time in milliseconds of a frame that follows [change].
Future<double> _measureFrames(int runs, void Function(int run) change) async {
  await _settle();
  final int before = _binding.frameWatch.elapsedMicroseconds;
  for (var run = 0; run < runs; run++) {
    change(run);
    _binding.scheduleFrame();
    await _binding.endOfFrame;
    await _settle();
  }
  return (_binding.frameWatch.elapsedMicroseconds - before) / runs / 1000.0;
}

String _ms(double value) => '${value.toStringAsFixed(3)} ms';

final List<String> _lines = <String>[];

void _report(String line) {
  _lines.add(line);
  debugPrint('BENCHMARK $line');
}

Future<void> _runScenario(int count, _Mode mode) async {
  final SearchInPagePlugin? search = mode == _Mode.searchPlugin
      ? SearchInPagePlugin()
      : null;
  final TextPlugin? plugin = switch (mode) {
    _Mode.noScope => null,
    _Mode.noopPlugin => _NoopPlugin(),
    _Mode.searchPlugin => search,
  };
  final pageKey = GlobalKey<_PageState>();
  final label = 'N=$count, ${mode.label}';

  // Mount the page.
  final int beforeMount = _binding.frameWatch.elapsedMicroseconds;
  runApp(_Page(key: pageKey, count: count, plugin: plugin));
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await _binding.endOfFrame;
  await _settle();
  final double mount =
      (_binding.frameWatch.elapsedMicroseconds - beforeMount) / 1000.0;
  _report('$label: mount the page: ${_ms(mount)}');
  final _PageState page = pageKey.currentState!;

  // The first search over the whole page.
  if (search != null) {
    final watch = Stopwatch()..start();
    search.query = _query;
    watch.stop();
    final double frame = await _measureFrames(1, (int run) {});
    _report(
      '$label: first search, ${search.matches.length} matches: '
      '${_ms(watch.elapsedMicroseconds / 1000.0)} to scan and sort, '
      'then ${_ms(frame)} for the frame',
    );
  }

  // A frame in which k paragraphs change.
  for (final int changed in _changedCounts) {
    final double frame = await _measureFrames(_runs, (int run) {
      page.change(changed, 1 + run % 2);
    });
    _report('$label: frame with $changed changed paragraphs: ${_ms(frame)}');
  }

  // A frame in which one paragraph is appended.
  final double append = await _measureFrames(_runs, (int run) {
    page.append();
  });
  _report('$label: frame that appends one paragraph: ${_ms(append)}');
  if (search != null) {
    _report('$label: matches after the appends: ${search.matches.length}');
  }

  // Unmount the page before the plugin is disposed.
  runApp(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await _binding.endOfFrame;
  await _settle();
  search?.dispose();
}

Future<void> _runAll() async {
  _report(
    kDebugMode
        ? 'WARNING: debug mode. These numbers are not valid. Use --profile.'
        : 'mode: ${kProfileMode ? 'profile' : 'release'}, '
              '${kIsWeb ? 'web' : defaultTargetPlatform.name}',
  );
  _report('each frame time is the average of $_runs frames');
  for (final int count in _pageSizes) {
    for (final _Mode mode in _Mode.values) {
      await _runScenario(count, mode);
    }
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
