import 'package:flutter/material.dart';
import '../services/auth_service.dart'; // <-- แก้ไข import ตรงนี้
import 'register_screen.dart'; // <-- import หน้า register

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  void _login() async {
    // ตรวจสอบว่าผู้ใช้กรอกข้อมูลครบหรือไม่
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("กรุณากรอกอีเมลและรหัสผ่าน")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await _authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      // หาก login ไม่สำเร็จ (userCredential เป็น null) ให้แสดงข้อความ
      if (userCredential == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("อีเมลหรือรหัสผ่านไม่ถูกต้อง")),
        );
      }
      // ไม่ต้องเขียนโค้ด redirect ที่นี่ เพราะ AuthGate จะจัดการให้เอง
    } finally {
      // ซ่อน loading indicator ไม่ว่าจะสำเร็จหรือไม่
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart Tram - Login"),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ช่องกรอกอีเมล
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              // ช่องกรอกรหัสผ่าน
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              // ปุ่ม Login
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _login,
                      child: const Text('เข้าสู่ระบบ'),
                    ),
              // ปุ่มสำหรับไปหน้าสมัครสมาชิก
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  );
                },
                child: const Text("ยังไม่มีบัญชี? สมัครสมาชิก"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
