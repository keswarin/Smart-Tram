// lib/screens/auth_gate.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Import หน้าจอทั้งหมด รวมถึงไฟล์หลักของคุณ ---
// --- Import หน้าจอทั้งหมด รวมถึงไฟล์หลักของคุณ ---
import 'login_screen.dart'; // ไฟล์อยู่ในโฟลเดอร์เดียวกัน
import 'otp_screen.dart'; // ไฟล์อยู่ในโฟลเดอร์เดียวกัน
import '../user_main.dart'; // ถอยกลับ 1 ระดับเพื่อหาไฟล์
import '../driver_main.dart'; // ถอยกลับ 1 ระดับเพื่อหาไฟล์

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ถ้ายังไม่ล็อกอิน -> ไปหน้า Login
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        final user = snapshot.data!;

        // ถ้าล็อกอินแล้ว -> ตรวจสอบ Role
        return FutureBuilder<DocumentSnapshot?>(
          future: _getUserRoleDoc(user.uid, user.email!),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            if (!roleSnapshot.hasData || roleSnapshot.data == null) {
              // กรณีหาข้อมูลไม่เจอ ให้กลับไปหน้า Login เพื่อความปลอดภัย
              return const LoginScreen();
            }

            final doc = roleSnapshot.data!;

            // 1. ถ้าเป็น "คนขับ"
            if (doc.reference.parent.id == 'drivers') {
              // ไปที่หน้าหลักของคนขับ
              return const DriverMain(); // <<< เรียกใช้คลาสจาก driver_main.dart
            }

            // 2. ถ้าเป็น "ผู้ใช้ทั่วไป"
            if (doc.reference.parent.id == 'users') {
              final data = doc.data() as Map<String, dynamic>;
              if (data['isVerified'] == true) {
                // ยืนยันแล้ว -> ไปที่หน้าหลักของผู้ใช้
                return const UserMain(); // <<< เรียกใช้คลาสจาก user_main.dart
              } else {
                // ยังไม่ยืนยัน -> ไปหน้า OTP
                return const OtpScreen();
              }
            }

            // ถ้าไม่เข้าเงื่อนไขไหนเลย ให้กลับไปหน้า Login
            return const LoginScreen();
          },
        );
      },
    );
  }

  /// ฟังก์ชันสำหรับค้นหา Role ของผู้ใช้จาก Firestore
  Future<DocumentSnapshot?> _getUserRoleDoc(String uid, String email) async {
    final firestore = FirebaseFirestore.instance;
    // ค้นหาใน 'drivers' collection ก่อน
    final driverQuery = await firestore
        .collection('drivers')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (driverQuery.docs.isNotEmpty) {
      return driverQuery.docs.first;
    }
    // ถ้าไม่เจอ ให้ค้นหาใน 'users' collection
    final userDoc = await firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      return userDoc;
    }
    return null;
  }
}
