// lib/gradient_background_animation.dart
import 'package:flutter/material.dart';

class GradientBackgroundAnimation extends StatefulWidget {
  final Widget child; // เพื่อให้เนื้อหาของหน้าจออยู่ข้างบน Background

  const GradientBackgroundAnimation({super.key, required this.child});

  @override
  State<GradientBackgroundAnimation> createState() =>
      _GradientBackgroundAnimationState();
}

class _GradientBackgroundAnimationState
    extends State<GradientBackgroundAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<AlignmentGeometry>
      _animation; // สำหรับเปลี่ยนตำแหน่งของ Gradient

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8), // ความเร็วในการเปลี่ยน (8 วินาที)
    )..repeat(reverse: true); // เล่นซ้ำไป-กลับ

    // กำหนดการเคลื่อนที่ของ Gradient จากมุมหนึ่งไปอีกมุมหนึ่ง
    _animation = Tween<AlignmentGeometry>(
      begin: Alignment.topLeft, // เริ่มต้นจากมุมซ้ายบน
      end: Alignment.bottomRight, // ไปจบที่มุมขวาล่าง
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut, // ทำให้การเคลื่อนไหวดูนุ่มนวล
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: _animation
                  .value, // ตำแหน่งเริ่มต้นของ Gradient จะเปลี่ยนไปเรื่อยๆ
              end: Alignment.bottomLeft, // ตำแหน่งสิ้นสุดของ Gradient
              colors: [
                Colors.orange.shade200, // สีที่ 1 (ส้มอ่อน)
                const Color.fromARGB(255, 213, 140, 31), // สีที่ 2 (ชมพูอ่อน)
                const Color.fromARGB(255, 5, 5, 5), // สีที่ 3 (ม่วงอ่อน)
              ],
              stops: const [0.0, 0.5, 1.0], // กำหนดจุดหยุดของแต่ละสี
            ),
          ),
          child: widget.child, // แสดงเนื้อหาของหน้าจอ
        );
      },
    );
  }
}
