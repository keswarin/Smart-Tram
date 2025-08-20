import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'signup_screen.dart';
import '../widgets/animated_gradient_background.dart'; // Import พื้นหลัง

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- VVVVVV แก้ไขฟังก์ชันนี้ VVVVVV ---
  Future<void> _handleLogin() async {
    // 1. ตรวจสอบข้อมูลในฟอร์ม
    if (!_formKey.currentState!.validate()) return;

    // 2. แสดง Loading Spinner และล้าง Error เก่า
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 3. พยายามล็อกอิน
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 4. เมื่อล็อกอินสำเร็จ เราจะไม่ทำอะไรเลยในหน้านี้
      // ปล่อยให้ AuthWrapper ที่คอยฟังอยู่ จัดการเปลี่ยนหน้าจอไปเอง
      // ไม่ต้องเรียก setState(() => _isLoading = false) ตรงนี้
    } on FirebaseAuthException catch (e) {
      // 5. ถ้าเกิด Error ให้หยุด Loading และแสดงข้อความ Error
      String message = 'เกิดข้อผิดพลาด';
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        message = 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      }
      if (mounted) {
        setState(() {
          _errorMessage = message;
          _isLoading = false; // หยุด Loading Spinner เฉพาะตอนที่เกิด Error
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'เกิดข้อผิดพลาดที่ไม่คาดคิด';
          _isLoading = false; // หยุด Loading Spinner เฉพาะตอนที่เกิด Error
        });
      }
    }
    // เราได้เอา finally block ออกไป แล้วจัดการ _isLoading ใน catch แทน
  }
  // --- ^^^^^^ สิ้นสุดการแก้ไข ^^^^^^ ---

  @override
  Widget build(BuildContext context) {
    const double cardMaxWidth = 400.0;

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: cardMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildGlassmorphismCard(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassmorphismCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: _buildLoginForm(),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.asset(
            'assets/images/image.png',
            height: 100,
          ),
          const SizedBox(height: 20),
          Text(
            'University Tram Service',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(blurRadius: 10.0, color: Colors.black.withOpacity(0.5))
              ],
            ),
          ),
          const SizedBox(height: 30),
          _buildTextField(
            controller: _emailController,
            hintText: 'อีเมล',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) => (value == null || !value.contains('@'))
                ? 'กรุณาใส่อีเมลที่ถูกต้อง'
                : null,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _passwordController,
            hintText: 'รหัสผ่าน',
            icon: Icons.lock_outline,
            isPassword: true,
            validator: (value) =>
                (value == null || value.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.yellow.shade200, fontWeight: FontWeight.bold),
              ),
            ),
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : ElevatedButton(
                  onPressed: _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.white.withOpacity(0.9),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('เข้าสู่ระบบ',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
          TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const SignupScreen())),
            child: Text(
              'ยังไม่มีบัญชี? สมัครสมาชิก',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? !_isPasswordVisible : false,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.9)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withOpacity(0.9),
                ),
                onPressed: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.5), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}
