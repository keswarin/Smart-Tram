import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ฟังก์ชันตรวจสอบว่าเป็นคนขับหรือไม่จากอีเมล
  /// โดยจะค้นหาใน collection 'drivers'
  Future<bool> isDriver(String email) async {
    try {
      final snapshot = await _db
          .collection('drivers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      // ถ้าเจอเอกสารใน collection drivers แสดงว่าเป็นคนขับ
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print("Error checking driver status: $e");
      return false;
    }
  }
}
