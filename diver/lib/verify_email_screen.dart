// lib/verify_email_screen.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_signup_screen.dart';
import 'role_redirector.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _timer;
  bool _isVerified = false;

  @override
  void initState() {
    super.initState();
    // เริ่มเช็คทุก 5 วินาที
    _timer = Timer.periodic(
        const Duration(seconds: 5), (_) => _checkEmailVerified());
  }

  Future<void> _checkEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.reload(); // sync สถานะจาก server
      if (user.emailVerified) {
        setState(() => _isVerified = true);
        _timer?.cancel();
      }
    }
  }

  Future<void> _resendEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ส่งอีเมลยืนยันใหม่แล้ว")),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginSignupScreen()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isVerified) {
      // ถ้ายืนยันแล้ว -> ไป RoleRedirector ทันที
      return const RoleRedirector();
    }

    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ยืนยันอีเมล"),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.email, size: 80, color: Colors.blue),
              const SizedBox(height: 20),
              Text(
                "เราได้ส่งอีเมลยืนยันไปที่:\n${user?.email ?? ''}",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              const Text(
                "กรุณาเปิดกล่องอีเมลของคุณ แล้วกดลิงก์ยืนยันเพื่อใช้งานระบบ",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                onPressed: _resendEmail,
                label: const Text("ส่งอีเมลยืนยันใหม่"),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                onPressed: () => _logout(context),
                label: const Text("ออกจากระบบ"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
