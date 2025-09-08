import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream สำหรับเช็คสถานะการล็อกอินแบบ Real-time
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// ฟังก์ชันสำหรับเข้าสู่ระบบ
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      // สามารถจัดการ Error message ตาม e.code ได้ เช่น 'user-not-found', 'wrong-password'
      print("Sign in error: ${e.message}");
      return null;
    }
  }

  /// ฟังก์ชันสำหรับสมัครสมาชิก
  Future<UserCredential?> registerUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      // 1. ตรวจสอบก่อนว่าอีเมลนี้ถูกใช้โดยคนขับแล้วหรือยัง
      final driverCheck = await _db
          .collection('drivers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (driverCheck.docs.isNotEmpty) {
        // ถ้าเจออีเมลใน collection 'drivers' ให้โยน error ออกไป
        throw FirebaseAuthException(
          code: 'driver-account-exists',
          message: 'This email is already registered as a driver.',
        );
      }

      // 2. สร้างผู้ใช้ใน Firebase Authentication
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 3. บันทึกข้อมูลเพิ่มเติมของผู้ใช้ใน collection 'users'
      await _db.collection('users').doc(userCredential.user!.uid).set({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'createdAt': Timestamp.now(),
        'isVerified': false, // ตั้งค่าเริ่มต้นว่ายังไม่ยืนยัน OTP
      });

      return userCredential;
    } on FirebaseAuthException {
      // ส่งต่อ error ที่มาจาก Firebase Auth เช่น 'email-already-in-use'
      rethrow;
    } catch (e) {
      print("An unexpected error occurred during registration: $e");
      return null;
    }
  }

  /// ฟังก์ชันออกจากระบบ
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
