// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rendering_tester.dart';

class _LoggingBox extends RenderBox {
  _LoggingBox(this.log);

  final List<String> log;

  @override
  void performLayout() {
    log.add('layout');
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    log.add('paint');
  }
}

void main() {
  TestRenderingFlutterBinding.ensureInitialized();

  test('A post-layout callback runs once, after layout and before paint', () {
    final log = <String>[];
    final box = _LoggingBox(log);
    layout(box);
    log.clear();

    box.markNeedsLayout();
    box.markNeedsPaint();
    RendererBinding.instance.addPostLayoutCallback(() {
      expect(RendererBinding.debugDoingPostLayoutCallbacks, isTrue);
      expect(box.debugNeedsLayout, isFalse);
      log.add('callback');
    });
    expect(log, isEmpty);
    expect(RendererBinding.debugDoingPostLayoutCallbacks, isFalse);

    pumpFrame(phase: EnginePhase.composite);
    expect(log, <String>['layout', 'callback', 'paint']);
    expect(RendererBinding.debugDoingPostLayoutCallbacks, isFalse);

    // The callback is not kept for the next frame.
    log.clear();
    box.markNeedsLayout();
    box.markNeedsPaint();
    pumpFrame(phase: EnginePhase.composite);
    expect(log, <String>['layout', 'paint']);
  });

  test('Post-layout callbacks run in the order in which they were added', () {
    final log = <String>[];
    layout(_LoggingBox(<String>[]));

    RendererBinding.instance.addPostLayoutCallback(() => log.add('first'));
    RendererBinding.instance.addPostLayoutCallback(() => log.add('second'));
    pumpFrame();
    expect(log, <String>['first', 'second']);
  });

  test('A post-layout callback added by a post-layout callback runs in the same frame', () {
    final log = <String>[];
    final box = _LoggingBox(log);
    layout(box);
    log.clear();

    box.markNeedsPaint();
    RendererBinding.instance.addPostLayoutCallback(() {
      log.add('outer');
      RendererBinding.instance.addPostLayoutCallback(() {
        expect(RendererBinding.debugDoingPostLayoutCallbacks, isTrue);
        log.add('inner');
      });
    });

    pumpFrame(phase: EnginePhase.composite);
    expect(log, <String>['outer', 'inner', 'paint']);
  });

  test('A post-layout callback can mark a render object as needing paint', () {
    final log = <String>[];
    final box = _LoggingBox(log);
    layout(box, phase: EnginePhase.composite);
    log.clear();

    RendererBinding.instance.addPostLayoutCallback(box.markNeedsPaint);
    pumpFrame(phase: EnginePhase.composite);
    expect(log, <String>['paint']);
  });

  test('Marking a render object as needing layout in a post-layout callback throws', () {
    final box = _LoggingBox(<String>[]);
    layout(box);

    FlutterError? error;
    RendererBinding.instance.addPostLayoutCallback(() {
      try {
        box.markNeedsLayout();
      } on FlutterError catch (e) {
        error = e;
      }
    });
    pumpFrame();

    expect(error, isNotNull);
    expect(
      error!.toStringDeep(),
      contains('A _LoggingBox was mutated during a post-layout callback.'),
    );
    expect(error!.toStringDeep(), contains('SchedulerBinding.addPostFrameCallback'));
    // The render object was not marked.
    expect(box.debugNeedsLayout, isFalse);

    // After the frame the same call is allowed.
    box.markNeedsLayout();
    expect(box.debugNeedsLayout, isTrue);
    pumpFrame();
    expect(box.debugNeedsLayout, isFalse);
  });

  test('The debug flag is reset when a post-layout callback throws', () {
    layout(_LoggingBox(<String>[]));

    RendererBinding.instance.addPostLayoutCallback(() {
      throw StateError('from the callback');
    });
    expect(pumpFrame, throwsStateError);
    expect(RendererBinding.debugDoingPostLayoutCallbacks, isFalse);
  });
}
