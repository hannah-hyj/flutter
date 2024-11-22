import 'package:flutter/widgets.dart';

/// A widget that applies animated effects to its child.
class Animated extends StatefulWidget {
  /// Creates a widget that applies animated effects to its child.
  const Animated({
    super.key,
    this.curve = Curves.linear,
    required this.child,
  });

  /// The widget to apply animated effects to.
  final Widget child;

  /// The curve to apply when animating the parameters of this container.
  final Curve curve;

  @override
  State<Animated> createState() => AnimatedState();
}

/// The state for the [Animated] widget.
class AnimatedState extends State<Animated>
    with SingleTickerProviderStateMixin {
  late AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  @override
  void initState() {
    super.initState();
  }

  CurvedAnimation _createCurve() {
    return CurvedAnimation(parent: controller, curve: widget.curve);
  }

  Animation<double> get animation => _animation;
  late CurvedAnimation _animation = _createCurve();

  @override
  void didUpdateWidget(Animated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.curve != oldWidget.curve) {
      _animation.dispose();
      _animation = _createCurve();
    }
  }

  void forward() {
    controller
      ..value = 0.0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Todo: what can I add in the mixin?
mixin AnimatedStateMixin<T extends StatefulWidget> on State<T> {}

/// get the [AnimatedState] from the nearest [Animated] ancestor.
AnimatedState? getAnimateState(BuildContext context) {
  return context.findAncestorStateOfType<AnimatedState>();
}

/// get the [AnimationController] from the nearest [Animated] ancestor.
AnimationController? getcontroller(BuildContext context) {
  final AnimatedState? parent =
      context.findAncestorStateOfType<AnimatedState>();

  return parent?.controller;
}


/// Adds [animated] extension to [Widget].
///
extension AnimateWidgetExtensions on Widget {
  /// Wraps the target [Widget] in an [Animate] instance, and returns
  /// the instance for chaining calls.
  /// Ex. `myWidget.animate()` is equivalent to `Animate(child: myWidget)`.
  Animated animated({
    Key? key,
    bool? autoPlay,
    Duration? delay,
    AnimationController? controller,
    double? target,
    double? value,
  }) =>
      Animated(
        key: key,
        child: this,
      );
}
