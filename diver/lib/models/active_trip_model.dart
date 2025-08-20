// lib/models/active_trip_model.dart
// (ตรวจสอบ path การ import ให้ถูกต้องตามโครงสร้างโปรเจกต์ของคุณ)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'stop_in_trip_model.dart'; // ตรวจสอบว่า path นี้ถูกต้อง และไฟล์ stop_in_trip_model.dart มีอยู่จริง

class ActiveTrip {
  final String tripId;
  final String driverId;
  String
      status; // เช่น "pending", "in_progress", "completed", "cancelled_by_driver", "driver_issue"
  final Timestamp createdAt;
  Timestamp updatedAt;
  final List<String>
      requestIds; // IDs ของ ride_requests ทั้งหมดที่รวมอยู่ใน trip นี้
  final String?
      overviewPolylineEncoded; // Optional: สำหรับวาดเส้นทางภาพรวมบนแผนที่
  List<StopInTrip> stops; // รายการจุดจอดใน Trip นี้ (ใช้ StopInTrip model)
  final double?
      estimatedTotalDuration; // Optional: เวลารวมโดยประมาณของ Trip (หน่วยเป็นนาที หรือวินาทีตามที่คุณกำหนด)
  double? actualTotalDuration;
  final String?
      assignedVehicleId; // Optional: เวลารวมที่ใช้จริง (จะถูกคำนวณเมื่อ Trip สิ้นสุด)

  ActiveTrip({
    required this.tripId,
    required this.driverId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.requestIds,
    this.overviewPolylineEncoded,
    required this.stops,
    this.estimatedTotalDuration,
    this.actualTotalDuration,
    this.assignedVehicleId,
  });

  // Factory constructor สำหรับสร้าง ActiveTrip object จาก DocumentSnapshot ที่ได้จาก Firestore
  factory ActiveTrip.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;

    // ตรวจสอบและแปลง List ของ stops จาก Map เป็น List<StopInTrip>
    List<StopInTrip> parsedStops = [];
    if (data['stops'] != null && data['stops'] is List) {
      parsedStops = (data['stops'] as List<dynamic>)
          .map((stopData) =>
              StopInTrip.fromMap(stopData as Map<String, dynamic>))
          .toList();
    }

    return ActiveTrip(
      tripId: data['tripId'] as String,
      driverId: data['driverId'] as String,
      status: data['status'] as String,
      createdAt: data['createdAt'] as Timestamp,
      updatedAt: data['updatedAt'] as Timestamp,
      requestIds: List<String>.from(
          data['requestIds'] as List? ?? []), // จัดการกรณี requestIds เป็น null
      overviewPolylineEncoded: data['overviewPolylineEncoded'] as String?,
      stops: parsedStops, // ใช้ stops ที่แปลงแล้ว
      estimatedTotalDuration: (data['estimatedTotalDuration'] as num?)
          ?.toDouble(), // จัดการกรณีเป็น null และแปลงเป็น double
      actualTotalDuration: (data['actualTotalDuration'] as num?)
          ?.toDouble(), // จัดการกรณีเป็น null และแปลงเป็น double
      assignedVehicleId: data['assignedVehicleId'] as String?,
    );
  }

  get vehicleDisplayName => null;

  // Method สำหรับแปลง ActiveTrip object กลับเป็น Map เพื่อเขียนลง Firestore
  Map<String, dynamic> toMap() {
    return {
      'tripId': tripId,
      'driverId': driverId,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'requestIds': requestIds,
      'overviewPolylineEncoded': overviewPolylineEncoded,
      'stops': stops
          .map((stop) => stop.toMap())
          .toList(), // แปลงแต่ละ StopInTrip กลับเป็น Map
      'estimatedTotalDuration': estimatedTotalDuration,
      'actualTotalDuration': actualTotalDuration,
      'assignedVehicleId': assignedVehicleId,
    };
  }
}
