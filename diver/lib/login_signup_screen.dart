// lib/login_signup_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({super.key});

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends State<LoginSignupScreen> {
  bool _isLogin = true;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  String? _errorMessage;
  bool _isLoading = false;

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        if (_isLogin) {
          // 🔹 เข้าสู่ระบบ
          final userCredential = await _auth.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

          if (userCredential.user != null &&
              userCredential.user!.emailVerified) {
            // ✅ ยืนยันแล้ว -> ระบบจะไปต่อเองผ่าน AuthWrapper
          } else {
            // ❌ ยังไม่ยืนยัน
            await _auth.signOut();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ")),
            );
          }
        } else {
          // 🔹 สมัครสมาชิก
          final newUserCredential = await _auth.createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

          // ส่งอีเมลยืนยัน
          await newUserCredential.user?.sendEmailVerification();

          // สร้างข้อมูลผู้ใช้ใหม่ใน Firestore
          await FirebaseFirestore.instance
              .collection('users')
              .doc(newUserCredential.user!.uid)
              .set({
            'email': newUserCredential.user!.email,
            'createdAt': FieldValue.serverTimestamp(),
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "ส่งอีเมลยืนยันไปที่ ${_emailController.text} แล้ว กรุณายืนยันก่อนเข้าสู่ระบบ"),
            ),
          );
        }
      } on FirebaseAuthException catch (e) {
        setState(() {
          _errorMessage = e.message;
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ส่งอีเมลยืนยันใหม่แล้ว")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("เกิดข้อผิดพลาด: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isLogin ? 'เข้าสู่ระบบ' : 'สมัครสมาชิก',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                          labelText: 'อีเมล', border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value!.isEmpty ? 'กรุณากรอกอีเมล' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                          labelText: 'รหัสผ่าน', border: OutlineInputBorder()),
                      obscureText: true,
                      validator: (value) => value!.length < 6
                          ? 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร'
                          : null,
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(_errorMessage!,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 24),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            onPressed: _submitForm,
                            child:
                                Text(_isLogin ? 'เข้าสู่ระบบ' : 'สมัครสมาชิก'),
                          ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLogin = !_isLogin;
                          _errorMessage = null;
                        });
                      },
                      child: Text(_isLogin
                          ? 'สร้างบัญชีใหม่'
                          : 'ฉันมีบัญชีแล้ว เข้าสู่ระบบ'),
                    ),
                    if (_isLogin)
                      TextButton(
                        onPressed: _resendVerificationEmail,
                        child: const Text("ส่งอีเมลยืนยันใหม่"),
                      )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
