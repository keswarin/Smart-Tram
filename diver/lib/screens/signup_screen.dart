import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  // --- หัวใจหลักของการสมัครสมาชิก ---
  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ---- ขั้นตอนที่ 1: สร้าง User ใน Firebase Authentication ----
      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final User? newUser = userCredential.user;

      if (newUser != null) {
        // ---- ขั้นตอนที่ 2: สร้าง Document ของ User ใน Firestore ----
        await FirebaseFirestore.instance
            .collection('users')
            .doc(newUser.uid)
            .set({
          'displayName': _displayNameController.text.trim(),
          'email': newUser.email,
          'userId': newUser.uid,
          'role': 'passenger', // <-- กำหนด Role เป็น 'passenger' โดยอัตโนมัติ
          'createdAt': FieldValue.serverTimestamp(),
        });

        // อัปเดต displayName ใน Auth (เผื่อใช้ในอนาคต)
        await newUser.updateDisplayName(_displayNameController.text.trim());

        // เมื่อสมัครสำเร็จและข้อมูลถูกสร้างแล้ว ให้กลับไปหน้าก่อนหน้า
        // AuthWrapper จะตรวจจับการล็อกอินใหม่และส่งไปหน้า UserMapScreen เอง
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = 'เกิดข้อผิดพลาดบางอย่าง';
      if (e.code == 'weak-password') {
        message = 'รหัสผ่านคาดเดาง่ายเกินไป';
      } else if (e.code == 'email-already-in-use') {
        message = 'อีเมลนี้ถูกใช้งานแล้ว';
      }
      setState(() {
        _errorMessage = message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาด: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สมัครสมาชิก'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(labelText: 'ชื่อที่แสดง'),
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'กรุณาใส่ชื่อของคุณ'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'อีเมล'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => (value == null || !value.contains('@'))
                      ? 'กรุณาใส่อีเมลที่ถูกต้อง'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'รหัสผ่าน'),
                  obscureText: true,
                  validator: (value) => (value == null || value.length < 6)
                      ? 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร'
                      : null,
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  ElevatedButton(
                    onPressed: _handleSignup,
                    child: const Text('ลงทะเบียน'),
                  ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
