// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Takes CPU samples of the text plugin benchmark while it runs its profiler
// loops, and says for each loop how the time is split between Dart code and
// the engine.
//
// 1. Start the benchmark and write its output to a file:
//
//        flutter run --profile -d macos -t lib/benchmark.dart \
//            --dart-define=BENCH=loops > /tmp/run.txt 2>&1
//
// 2. Start this script with that file and a directory for its output:
//
//        dart tool/cpu_profile.dart /tmp/run.txt benchmark_results/cpu/span_b
//
// For every loop of the benchmark it writes `<directory>/<loop>.txt`, and at
// the end `<directory>/summary.tsv` with one line for each loop.
//
// The samples come from the CPU profiler of the Dart VM, which is on in
// profile mode. It samples the UI thread and sees native frames of the engine
// by name. With `--native` as a third argument the script also runs the macOS
// `sample` tool, which writes a full native call tree of every thread (large).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Duration _sampleTime = Duration(seconds: 5);

/// Where a sample is, by the kind of work. Every sample is in exactly one.
enum _Category {
  dartPlugin('Dart: the plugin', false),
  dartPrototype('Dart: text plugin machinery of the framework', false),
  dartFramework('Dart: the rest of the framework', false),
  dartRuntime('Dart VM: allocation, GC, stubs', false),
  engineBuild('Engine: building a paragraph (ParagraphBuilder)', true),
  engineLayout('Engine: ui.Paragraph.layout (shaping, line breaking)', true),
  enginePaint('Engine: drawing the text (ui.Paragraph.paint)', true),
  engineQuery('Engine: paragraph queries (boxes of a range and others)', true),
  engineOther('Engine: everything else (display list, layers, memory)', true);

  const _Category(this.label, this.isEngine);

  final String label;
  final bool isEngine;
}

final RegExp _plugin = RegExp(
  r'^(SearchInPagePlugin|PulsePlugin|KaraokePlugin|_NoopPlugin|_SelectionHighlightTextPlugin|'
  r'_SearchBackgroundPainter|_SearchForegroundPainter|_PulsePainter|_KaraokePainter|'
  r'_SelectionHighlightPainter)\.',
);
final RegExp _prototype = RegExp(
  r'^(decorateTextSpan|_Decorator\.|TextDelegateSet\.|TextDelegate\.|TextLayout\.|'
  r'_TextLayout\.|TextPluginScope|_TextPluginScopeState|_TextPluginSpanBuilderState|'
  r'TextPluginSpanBuilder|TextSpanDecoration)|TextDelegateHostMixin',
);
final RegExp _paragraphLayout = RegExp(
  r'^(skia::textlayout::ParagraphImpl::layout\(|flutter::Paragraph::layout\(|'
  r'txt::ParagraphSkia::Layout\()',
);
final RegExp _paragraphBuild = RegExp(
  r'^(flutter::ParagraphBuilder::|skia::textlayout::ParagraphBuilderImpl::|'
  r'txt::ParagraphBuilderSkia::|txt::ParagraphBuilder::)',
);
final RegExp _paragraphPaint = RegExp(
  r'^(skia::textlayout::ParagraphImpl::paint\(|flutter::Paragraph::paint\(|'
  r'txt::ParagraphSkia::Paint\()',
);
final RegExp _paragraphQuery = RegExp(
  r'^(flutter::Paragraph::|txt::ParagraphSkia::)',
);
final RegExp _vmRuntime = RegExp(r'^(dart::|\[Stub\]|DRT_|DLRT_)');

/// The phases of a frame, by a function that is on the stack during it.
const List<(String, String)> _phases = <(String, String)>[
  ('build', 'BuildOwner.buildScope'),
  ('layout', 'PipelineOwner.flushLayout'),
  ('paint', 'PipelineOwner.flushPaint'),
  ('composite', 'RenderView.compositeFrame'),
  ('semantics', 'PipelineOwner.flushSemantics'),
  ('frame start', 'SchedulerBinding.handleBeginFrame'),
];

/// Functions whose inclusive share is listed, in groups.
final List<(String, List<Pattern>)> _selected = <(String, List<Pattern>)>[
  (
    'The plugin and the text plugin machinery (Dart)',
    <Pattern>[_plugin, _prototype],
  ),
  (
    'Text in the framework (Dart)',
    <Pattern>[
      'RenderParagraph.performLayout',
      'RenderParagraph.paint',
      'RenderParagraph._setPainterText',
      'RenderEditable.performLayout',
      'RenderEditable.paint',
      'TextPainter.layout',
      'TextPainter.paint',
      'TextPainter._createParagraph',
      'TextPainter.getBoxesForSelection',
      'TextSpan.build',
      'TextSpan.compareTo',
      'toPlainText',
      'RenderFlex.performLayout',
      'RenderSliverList.performLayout',
    ],
  ),
  (
    'Text in the engine (native)',
    <Pattern>[
      RegExp(r'^flutter::ParagraphBuilder::(Create|build|addText|pushStyle)'),
      RegExp(
        r'^skia::textlayout::ParagraphImpl::(layout|paint|shapeTextIntoEndlessLine|'
        r'breakShapedTextIntoLines|computeCodeUnitProperties|buildClusterTable|formatLines|'
        r'getRectsForRange|applySpacingAndBuildClusterTable)\(',
      ),
      RegExp(r'^skia::textlayout::OneLineShaper::shape\('),
      RegExp(r'^hb_shape_full'),
      RegExp(r'^skia::textlayout::TextLine::paint'),
      RegExp(r'^flutter::Paragraph::getRectsForRange'),
    ],
  ),
];

class _VmService {
  _VmService(this._socket) {
    _socket.listen((dynamic data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final Completer<Map<String, dynamic>>? completer = _pending.remove(
        message['id'],
      );
      if (completer == null) {
        return;
      }
      if (message['error'] != null) {
        completer.completeError(StateError('${message['error']}'));
      } else {
        completer.complete(message['result'] as Map<String, dynamic>);
      }
    });
  }

  final WebSocket _socket;
  final Map<Object?, Completer<Map<String, dynamic>>> _pending =
      <Object?, Completer<Map<String, dynamic>>>{};
  int _nextId = 0;

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?>? params,
  ]) {
    final id = '${_nextId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params ?? <String, Object?>{},
      }),
    );
    return completer.future;
  }
}

String _nameOf(Map<String, dynamic> entry) {
  final function = entry['function'] as Map<String, dynamic>;
  final name = function['name'] as String? ?? '?';
  final Object? owner = function['owner'];
  if (owner is Map<String, dynamic> && owner['name'] is String) {
    final ownerName = owner['name'] as String;
    if (ownerName.isNotEmpty && function['type'] != 'NativeFunction') {
      return '$ownerName.$name';
    }
  }
  return name;
}

_Category _categorize(List<int> stack, List<String> names, List<String> kinds) {
  final int leaf = stack.first;
  if (kinds[leaf] == 'Dart') {
    // Dart code. Whose? The plugin's if a function of the plugin is on the
    // stack, also when the plugin called into the framework.
    for (final index in stack) {
      if (_plugin.hasMatch(names[index])) {
        return _Category.dartPlugin;
      }
    }
    for (final index in stack) {
      if (_prototype.hasMatch(names[index])) {
        return _Category.dartPrototype;
      }
    }
    return _Category.dartFramework;
  }
  // Native code. The paragraph work of the engine is told apart by the
  // function of the engine that is on the stack.
  var build = false;
  var layout = false;
  var paint = false;
  var query = false;
  for (final index in stack) {
    final String name = names[index];
    if (kinds[index] == 'Dart') {
      break;
    }
    if (_paragraphLayout.hasMatch(name)) {
      layout = true;
    } else if (_paragraphBuild.hasMatch(name)) {
      build = true;
    } else if (_paragraphPaint.hasMatch(name)) {
      paint = true;
    } else if (_paragraphQuery.hasMatch(name)) {
      query = true;
    }
  }
  if (layout) {
    return _Category.engineLayout;
  }
  if (build) {
    return _Category.engineBuild;
  }
  if (paint) {
    return _Category.enginePaint;
  }
  if (query) {
    return _Category.engineQuery;
  }
  // Allocation and garbage collection are native code that Dart code causes.
  if (_vmRuntime.hasMatch(names[leaf]) || kinds[leaf] != 'Native') {
    return _Category.dartRuntime;
  }
  return _Category.engineOther;
}

String _percent(int part, int whole) =>
    whole == 0 ? '  0.0' : (100 * part / whole).toStringAsFixed(1).padLeft(5);

Future<String?> _profileLoop(
  _VmService service,
  String isolateId,
  int pid,
  String loop,
  Directory directory,
  File log, {
  required bool native,
}) async {
  final String slug = loop.replaceAll(RegExp('[^A-Za-z0-9=]+'), '_');
  // Let the loop get going, then sample.
  await Future<void>.delayed(const Duration(milliseconds: 800));
  await service.call('clearCpuSamples', <String, Object?>{
    'isolateId': isolateId,
  });
  Future<ProcessResult>? nativeSample;
  if (native) {
    nativeSample = Process.run('sample', <String>[
      '$pid',
      '${_sampleTime.inSeconds}',
      '-file',
      '${directory.path}/${slug}_native.txt',
    ]);
  }
  await Future<void>.delayed(_sampleTime);
  final Map<String, dynamic> samples = await service.call(
    'getCpuSamples',
    <String, Object?>{
      'isolateId': isolateId,
      'timeOriginMicros': 0,
      'timeExtentMicros': 1 << 52,
    },
  );
  await nativeSample;

  // The time of one round, which the benchmark prints when the loop ends.
  String? iterations;
  String? milliseconds;
  final end = RegExp(
    'LOOP END ${RegExp.escape(loop)}, (\\d+) iterations, ([0-9.]+) ms each',
  );
  for (var i = 0; i < 100 && milliseconds == null; i++) {
    final RegExpMatch? match = end.firstMatch(log.readAsStringSync());
    if (match != null) {
      iterations = match.group(1);
      milliseconds = match.group(2);
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  final double perRound = double.tryParse(milliseconds ?? '') ?? double.nan;

  final functions = (samples['functions'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final List<String> names = functions.map(_nameOf).toList();
  final List<String> kinds = functions
      .map((Map<String, dynamic> e) => e['kind'] as String)
      .toList();
  final sampleList = (samples['samples'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final int count = sampleList.length;

  final categories = <_Category, int>{
    for (final _Category c in _Category.values) c: 0,
  };
  final phases = <String, int>{
    for (final (String, String) p in _phases) p.$1: 0,
  };
  var outsideFrame = 0;
  final phaseIndex = <int, String>{};
  for (var i = 0; i < names.length; i++) {
    for (final (String phase, String function) in _phases) {
      if (names[i].endsWith(function)) {
        phaseIndex[i] = phase;
      }
    }
  }
  for (final sample in sampleList) {
    final List<int> stack = (sample['stack'] as List<dynamic>).cast<int>();
    if (stack.isEmpty) {
      continue;
    }
    final _Category category = _categorize(stack, names, kinds);
    categories[category] = categories[category]! + 1;
    String? phase;
    for (final index in stack) {
      phase = phaseIndex[index];
      if (phase != null) {
        break;
      }
    }
    if (phase == null) {
      outsideFrame += 1;
    } else {
      phases[phase] = phases[phase]! + 1;
    }
  }
  final int engine = _Category.values
      .where((_Category c) => c.isEngine)
      .fold(0, (int sum, _Category c) => sum + categories[c]!);
  final int dart = count - engine;

  String ms(int part) =>
      count == 0 ? '?' : (perRound * part / count).toStringAsFixed(3);
  final out = StringBuffer()
    ..writeln('CPU profile of the loop "$loop"')
    ..writeln(
      '$count samples of the UI thread, one every ${samples['samplePeriod']} microseconds, '
      'from the CPU profiler of the Dart VM',
    )
    ..writeln('$iterations rounds in the loop, $milliseconds ms a round')
    ..writeln()
    ..writeln('Dart side and engine side. Every sample is in one line.')
    ..writeln(
      '  ${_percent(dart, count)} %  ${ms(dart).padLeft(8)} ms  DART SIDE',
    )
    ..writeln(
      '  ${_percent(engine, count)} %  ${ms(engine).padLeft(8)} ms  ENGINE SIDE',
    );
  for (final category in _Category.values) {
    out.writeln(
      '    ${_percent(categories[category]!, count)} %  '
      '${ms(categories[category]!).padLeft(8)} ms  ${category.label}',
    );
  }
  out
    ..writeln()
    ..writeln('The phases of a frame');
  for (final (String phase, _) in _phases) {
    if (phases[phase]! > 0) {
      out.writeln(
        '  ${_percent(phases[phase]!, count)} %  ${ms(phases[phase]!).padLeft(8)} ms  $phase',
      );
    }
  }
  out.writeln(
    '  ${_percent(outsideFrame, count)} %  ${ms(outsideFrame).padLeft(8)} ms  '
    'outside of a frame (the call that makes the change, and the loop itself)',
  );

  out
    ..writeln()
    ..writeln('Exclusive: the sample was in this function itself');
  final List<Map<String, dynamic>> byExclusive = functions.toList()
    ..sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (b['exclusiveTicks'] as int).compareTo(a['exclusiveTicks'] as int),
    );
  for (final Map<String, dynamic> entry in byExclusive.take(30)) {
    final ticks = entry['exclusiveTicks'] as int;
    if (ticks * 200 < count) {
      break;
    }
    String name = _nameOf(entry);
    if (name.length > 120) {
      name = '${name.substring(0, 120)}...';
    }
    out.writeln('  ${_percent(ticks, count)} %  ${entry['kind']}  $name');
  }

  out
    ..writeln()
    ..writeln('Inclusive: this function was on the stack. Selected functions.');
  for (final (String title, List<Pattern> patterns) in _selected) {
    out.writeln('  $title');
    final List<Map<String, dynamic>> matching =
        functions.where((Map<String, dynamic> entry) {
          final String name = _nameOf(entry);
          return patterns.any((Pattern pattern) => name.contains(pattern));
        }).toList()..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              (b['inclusiveTicks'] as int).compareTo(
                a['inclusiveTicks'] as int,
              ),
        );
    for (final Map<String, dynamic> entry in matching.take(10)) {
      final ticks = entry['inclusiveTicks'] as int;
      if (ticks * 200 < count) {
        break;
      }
      String name = _nameOf(entry);
      if (name.length > 110) {
        name = '${name.substring(0, 110)}...';
      }
      out.writeln('    ${_percent(ticks, count)} %  $name');
    }
  }
  File('${directory.path}/$slug.txt').writeAsStringSync(out.toString());
  stdout.writeln(
    '$loop: $milliseconds ms a round, ${_percent(engine, count).trim()} % engine',
  );

  return <String>[
    loop,
    milliseconds ?? '',
    '$count',
    ms(dart),
    ms(engine),
    for (final _Category category in _Category.values)
      ms(categories[category]!),
    for (final (String phase, _) in _phases) ms(phases[phase]!),
    ms(outsideFrame),
  ].join('\t');
}

Future<void> main(List<String> args) async {
  final log = File(args[0]);
  final directory = Directory(args[1])..createSync(recursive: true);
  final bool native = args.length > 2 && args[2] == '--native';
  final serviceUrl = RegExp(
    r'Dart VM Service on \S+ is available at: (http://\S+)',
  );
  final loopStart = RegExp(r'BENCHMARK LOOP START (.+)');

  final summary = <String>[
    <String>[
      'loop',
      'ms a round',
      'samples',
      'Dart side ms',
      'engine side ms',
      for (final _Category category in _Category.values) category.label,
      for (final (String phase, _) in _phases) 'phase: $phase',
      'outside of a frame',
    ].join('\t'),
  ];
  _VmService? service;
  String? isolateId;
  int? pid;
  final done = <String>{};
  final DateTime deadline = DateTime.now().add(const Duration(minutes: 20));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!log.existsSync()) {
      continue;
    }
    final String text = log.readAsStringSync();
    if (service == null) {
      final RegExpMatch? match = serviceUrl.firstMatch(text);
      if (match == null) {
        continue;
      }
      final Uri http = Uri.parse(match.group(1)!);
      final Uri ws = http.replace(scheme: 'ws', path: '${http.path}ws');
      service = _VmService(await WebSocket.connect(ws.toString()));
      final Map<String, dynamic> vm = await service.call('getVM');
      pid = vm['pid'] as int;
      isolateId =
          ((vm['isolates'] as List<dynamic>).first
                  as Map<String, dynamic>)['id']
              as String;
      stdout.writeln('connected, pid $pid');
    }
    for (final RegExpMatch match in loopStart.allMatches(text)) {
      final String loop = match.group(1)!.trim();
      if (done.add(loop)) {
        final String? line = await _profileLoop(
          service,
          isolateId!,
          pid!,
          loop,
          directory,
          log,
          native: native,
        );
        if (line != null) {
          summary.add(line);
          File('${directory.path}/summary.tsv')
              .writeAsStringSync('${summary.join('\n')}\n');
        }
      }
    }
    if (text.contains('BENCHMARK done')) {
      break;
    }
  }
  exit(0);
}
