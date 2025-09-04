// lib/role_redirector.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'main.dart'; // แอปผู้ใช้
import 'driver_main.dart'; // แอปคนขับ

class RoleRedirector extends StatelessWidget {
  final String uid;
  const RoleRedirector({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('drivers').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return const Scaffold(
              body: Center(child: Text("Something went wrong")));
        }

        if (snapshot.data != null && snapshot.data!.exists) {
          // ถ้า UID นี้มีข้อมูลใน collection 'drivers' ให้ไปหน้าคนขับ
          return DriverScreen(driverId: uid);
        } else {
          // ถ้าไม่เจอ ให้ไปหน้าผู้ใช้ทั่วไป
          return RequestScreen();
        }
      },
    );
  }
}
