import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // สำหรับ Firebase
import 'package:intl/date_symbol_data_local.dart'; // สำหรับ Format วันที่ locale ไทย
import 'firebase_options.dart'; // ไฟล์ config Firebase ของคุณ

// --- Import หน้าจอเริ่มต้น ---
import 'auth_wrapper.dart'; // <<< แก้ไข: Import AuthWrapper เข้ามา

Future<void> main() async {
  // ต้องมีเพื่อให้ Flutter Plugin ทำงานก่อน runApp
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize การตั้งค่า Locale สำหรับ intl
  await initializeDateFormatting('th_TH', null);

  // สั่งให้แอปเริ่มทำงาน
  runApp(const MyApp());
}

// Widget หลักของแอปพลิเคชัน
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'University Tram Service', // อาจจะเปลี่ยนชื่อแอปให้เป็นกลาง
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ),

      // --- กำหนดหน้าจอเริ่มต้นของแอป ---
      home: const AuthWrapper(), // <<< แก้ไข: ตั้งค่าให้เริ่มที่ AuthWrapper
    );
  }
}
