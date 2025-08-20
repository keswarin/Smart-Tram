// ../models/grouped_request_model.dart
// (ตรวจสอบ path การ import ให้ถูกต้องตามโครงสร้างโปรเจกต์ของคุณ)

import 'package:cloud_firestore/cloud_firestore.dart'; // สำหรับ QueryDocumentSnapshot
import 'package:google_maps_flutter/google_maps_flutter.dart'; // สำหรับ LatLng

class GroupedRequestData {
  final String key; // Key ที่ใช้ในการจัดกลุ่ม เช่น "pickupId-dropoffId"
  final List<QueryDocumentSnapshot>
      requests; // รายการคำขอ (ride_requests documents) ทั้งหมดในกลุ่มนี้
  final String pickupPointId;
  final String pickupPointName;
  final LatLng
      pickupLatLng; // ใน Model นี้ เราจะเก็บเป็น LatLng เพื่อให้ง่ายต่อการใช้งานใน UI
  final String dropoffPointId;
  final String dropoffPointName;
  final LatLng dropoffLatLng; // ใน Model นี้ เราจะเก็บเป็น LatLng
  final List<String>
      userDisplayNames; // รายชื่อผู้ใช้สำหรับแสดงผล (เช่น "User A, User B, ...")

  GroupedRequestData({
    required this.key,
    required this.requests,
    required this.pickupPointId,
    required this.pickupPointName,
    required this.pickupLatLng,
    required this.dropoffPointId,
    required this.dropoffPointName,
    required this.dropoffLatLng,
    required this.userDisplayNames,
  });

  // ไม่จำเป็นต้องมี fromMap หรือ toMap สำหรับ class นี้
  // เพราะมันถูกสร้างขึ้นในฝั่ง client (RequestListScreen) โดยตรง
  // จากข้อมูลที่ดึงมาจาก Firestore (QueryDocumentSnapshot)
  // และไม่ได้ถูกเขียนกลับไป Firestore ในรูปแบบของ GroupedRequestData โดยตรง
}
