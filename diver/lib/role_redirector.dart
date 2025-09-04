// lib/role_redirector.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'driver_main.dart';
import 'main.dart'; // สำหรับฝั่งผู้ใช้ (ถ้าไฟล์ main.dart คือหน้า user)

class RoleRedirector extends StatelessWidget {
  const RoleRedirector({super.key});

  Future<String?> _getUserRole(String uid) async {
    final firestore = FirebaseFirestore.instance;

    // 🔹 ตรวจสอบใน collection 'drivers'
    final driverDoc = await firestore.collection('drivers').doc(uid).get();
    if (driverDoc.exists) {
      return "driver";
    }

    // 🔹 ตรวจสอบใน collection 'users'
    final userDoc = await firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      return "user";
    }

    return null; // ถ้าไม่พบ
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("ยังไม่ได้เข้าสู่ระบบ")),
      );
    }

    return FutureBuilder<String?>(
      future: _getUserRole(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const Scaffold(
            body: Center(
              child: Text("ไม่พบข้อมูลผู้ใช้ กรุณาติดต่อผู้ดูแลระบบ"),
            ),
          );
        }

        final role = snapshot.data;

        if (role == "driver") {
          // 🔹 ไปหน้า Driver
          return DriverScreen(driverId: user.uid);
        } else {
          // 🔹 ไปหน้า User (เรียก main.dart ที่เป็นหน้าเลือกขึ้นรถ)
          return const RequestScreen();
        }
      },
    );
  }
}
