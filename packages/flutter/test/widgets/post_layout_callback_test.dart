// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoggingPainter extends CustomPainter {
  _LoggingPainter(this.log, {required this.generation});

  final List<String> log;
  final int generation;

  @override
  void paint(Canvas canvas, Size size) {
    log.add('paint');
  }

  @override
  bool shouldRepaint(_LoggingPainter oldDelegate) => generation != oldDelegate.generation;
}

void main() {
  // The test binding runs the steps of a frame itself instead of calling
  // RendererBinding.drawFrame, so this checks that it runs the callbacks too.
  testWidgets('A post-layout callback runs between layout and paint in a widget test', (
    WidgetTester tester,
  ) async {
    final log = <String>[];

    Widget build({required int generation, required double height}) {
      return Center(
        child: SizedBox(
          width: 100.0,
          height: height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              log.add('layout');
              return CustomPaint(painter: _LoggingPainter(log, generation: generation));
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(build(generation: 0, height: 100.0));
    log.clear();

    RendererBinding.instance.addPostLayoutCallback(() => log.add('callback'));
    await tester.pumpWidget(build(generation: 1, height: 200.0));
    expect(log, <String>['layout', 'callback', 'paint']);

    // The callback is not kept for the next frame.
    log.clear();
    await tester.pumpWidget(build(generation: 2, height: 300.0));
    expect(log, <String>['layout', 'paint']);
  });

  testWidgets('A post-layout callback added outside a frame asks for a frame', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.hasScheduledFrame, isFalse);

    var calls = 0;
    RendererBinding.instance.addPostLayoutCallback(() => calls += 1);
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(calls, 0);

    await tester.pump();
    expect(calls, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Marking a render object as needing layout in a post-layout callback throws', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const Center(child: SizedBox(width: 100.0, height: 100.0)));
    final RenderObject renderObject = tester.renderObject(find.byType(SizedBox));

    FlutterError? error;
    RendererBinding.instance.addPostLayoutCallback(() {
      try {
        renderObject.markNeedsLayout();
      } on FlutterError catch (e) {
        error = e;
      }
    });
    await tester.pump();

    expect(error, isNotNull);
    expect(error!.toStringDeep(), contains('was mutated during a post-layout callback.'));

    // After the frame the same call is allowed.
    renderObject.markNeedsLayout();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
