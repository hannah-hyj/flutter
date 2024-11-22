import 'package:flutter/material.dart';

import 'package:flutter/animation.dart';


////   This is to test a widget like Animate(Row(Container(), Container()))

void main() {
  runApp(ScaleEffectApp());
}

class ScaleEffectApp extends StatelessWidget {
  ScaleEffectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ScaleEffectScreen(),
    );
  }
}

class ScaleEffectScreen extends StatelessWidget {
  const ScaleEffectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: MyAnimatedButton(),
      ),
    );
  }
}

class MyAnimatedButton extends StatefulWidget {
  const MyAnimatedButton({super.key});

  @override
  State<MyAnimatedButton> createState() => _MyAnimatedButtonState();
}

class _MyAnimatedButtonState extends State<MyAnimatedButton> {
  double scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Animated(
          child: Row(
            children: [
              Container(
                height: 50 * scale,
                width: 100 * scale, // Scale factor
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      if (scale < 5) {
                        scale += 1;
                      } else {
                        scale = 1;
                      }
                    });
                  },
                  child: const Text("Press here"),
                ),
              ),
              Container(
                height: 50 * scale,
                width: 100 * scale, // Scale factor
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      if (scale < 5) {
                        scale += 1;
                      } else {
                        scale = 1;
                      }
                    });
                  },
                  child: const Text("Press here"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
