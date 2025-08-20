import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Import หน้าจอทั้งหมดของคุณ ---
// ตรวจสอบให้แน่ใจว่า path ของไฟล์ถูกต้องตามโครงสร้างโปรเจคของคุณ
import 'screens/login_screen.dart';
import 'screens/driver_home_screen.dart';
import 'screens/user_map_screen.dart';
import 'screens/admin_dashboard_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder จะคอยฟังสถานะการล็อกอินจาก Firebase อยู่ตลอดเวลา
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ขณะที่กำลังรอการเชื่อมต่อ ให้แสดงหน้าจอ loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ถ้า Stream มีข้อมูล (หมายถึงมี User ล็อกอินอยู่)
        if (snapshot.hasData) {
          // เราจะไปดึงข้อมูล role จาก Firestore ต่อ
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(snapshot.data!.uid) // ใช้ uid ของคนที่ล็อกอินอยู่
                .get(),
            builder: (context, userSnapshot) {
              // ขณะที่กำลังรอข้อมูลจาก Firestore
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // ถ้าหาข้อมูล user ไม่เจอ หรือไม่มี field 'role'
              if (!userSnapshot.hasData ||
                  !userSnapshot.data!.exists ||
                  (userSnapshot.data!.data() as Map<String, dynamic>)['role'] ==
                      null) {
                // ให้กลับไปหน้า Login (อาจจะ logout ก่อนเพื่อความปลอดภัย)
                print(
                    "AuthWrapper Error: User document not found or role is missing.");
                // FirebaseAuth.instance.signOut();
                return const LoginScreen();
              }

              // ดึงค่า role ออกมา
              final String role = userSnapshot.data!.get('role');

              // ตรวจสอบ role แล้วส่งไปหน้าจอที่ถูกต้อง
              switch (role) {
                case 'driver':
                  return const DriverHomeScreen();
                case 'passenger':
                  return const UserMapScreen();
                case 'admin':
                  return const AdminDashboardScreen(); // <<< แก้ไขเป็นหน้านี้
                default:
                  return const LoginScreen();
              }
            },
          );
        }

        // ถ้า Stream ไม่มีข้อมูล (ไม่มีใครล็อกอินอยู่) ให้ไปหน้า Login
        return const LoginScreen();
      },
    );
  }
}
