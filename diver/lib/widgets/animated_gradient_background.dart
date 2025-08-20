import 'package:flutter/material.dart';
import 'package:simple_animations/simple_animations.dart';

enum _AnimationProps { color1, color2, color3, color4 }

class AnimatedGradientBackground extends StatelessWidget {
  const AnimatedGradientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.black87, // สีดำเข้ม
      Colors.grey.shade900, // สีดำเทา
      Colors.amber.shade800, // สีทองเข้ม
      Colors.amber.shade500, // สีทองสว่าง
    ];

    final tween = MovieTween()
      ..scene(duration: const Duration(seconds: 10))
          .tween(_AnimationProps.color1,
              ColorTween(begin: colors.elementAt(0), end: colors.elementAt(1)))
          .tween(_AnimationProps.color2,
              ColorTween(begin: colors.elementAt(1), end: colors.elementAt(2)))
          .tween(_AnimationProps.color3,
              ColorTween(begin: colors.elementAt(2), end: colors.elementAt(3)))
          .tween(_AnimationProps.color4,
              ColorTween(begin: colors.elementAt(3), end: colors.elementAt(0)));

    return LoopAnimationBuilder<Movie>(
      tween: tween,
      duration: tween.duration,
      builder: (context, value, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                value.get(_AnimationProps.color1),
                value.get(_AnimationProps.color2),
                value.get(_AnimationProps.color3),
                value.get(_AnimationProps.color4),
              ],
            ),
          ),
        );
      },
    );
  }
}
