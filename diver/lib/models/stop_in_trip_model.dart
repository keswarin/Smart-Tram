// stop_in_trip_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // สำหรับ LatLng
// import 'passenger_action_model.dart'; // ถ้าจะแยก PassengerAction ออกไปอีกไฟล์

// --- Passenger Action Model (สามารถอยู่ในไฟล์เดียวกันหรือแยกไฟล์) ---
class PassengerActionInStop {
  final String userId;
  final String? userName; // Denormalized
  final String action; // "pickup" หรือ "dropoff"
  String
      status; // "pending_pickup", "picked_up", "no_show_pickup", "pending_dropoff", "dropped_off"
  final String? pickupPointId; // สำหรับอ้างอิง (ถ้า action == "pickup")
  final String? dropoffPointId; // สำหรับอ้างอิง (ถ้า action == "dropoff")
  final String? notesToDriver; // Optional
  final String rideRequestId;

  PassengerActionInStop({
    required this.userId,
    this.userName,
    required this.action,
    required this.status,
    this.pickupPointId,
    this.dropoffPointId,
    this.notesToDriver,
    required this.rideRequestId,
  });

  factory PassengerActionInStop.fromMap(Map<String, dynamic> map) {
    return PassengerActionInStop(
      userId: map['userId'] as String,
      userName: map['userName'] as String?,
      action: map['action'] as String,
      status: map['status'] as String,
      pickupPointId: map['pickupPointId'] as String?,
      dropoffPointId: map['dropoffPointId'] as String?,
      notesToDriver: map['notesToDriver'] as String?,
      rideRequestId: map['rideRequestId'] as String? ??
          '', // <--- เพิ่มบรรทัดนี้ (ถ้าอาจจะเป็น null ให้มี default)
      // หรือถ้ามั่นใจว่ามีเสมอ ก็เป็น as String
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'action': action,
      'status': status,
      'pickupPointId': pickupPointId,
      'dropoffPointId': dropoffPointId,
      'notesToDriver': notesToDriver,
      'rideRequestId': rideRequestId,
    };
  }
}
// --- End of Passenger Action Model ---

class StopInTrip {
  final String stopId;
  final int sequenceOrder;
  final String type; // "pickup", "dropoff", "pickup_dropoff"
  final String stopName;
  final LatLng
      coordinates; // ใช้ LatLng ใน Model เพื่อง่ายต่อการใช้งานกับ GoogleMap
  String
      status; // "pending", "shuttle_en_route", "arrived_at_stop", "pickup_completed_en_route_dropoff", "action_completed"
  Timestamp? estimatedArrivalTime;
  Timestamp? actualArrivalTime;
  Timestamp? actualDepartureTime;
  final List<String>
      associatedRequestIds; // ride_request IDs ที่เกี่ยวข้องกับ stop นี้
  final List<PassengerActionInStop>
      passengers; // <-- ใช้ PassengerActionInStop model

  StopInTrip({
    required this.stopId,
    required this.sequenceOrder,
    required this.type,
    required this.stopName,
    required this.coordinates,
    required this.status,
    this.estimatedArrivalTime,
    this.actualArrivalTime,
    this.actualDepartureTime,
    required this.associatedRequestIds,
    required this.passengers,
  });

  // Factory constructor to create a StopInTrip from a map (e.g., from Firestore)
  factory StopInTrip.fromMap(Map<String, dynamic> map) {
    GeoPoint geoPoint = map['coordinates'] as GeoPoint;
    return StopInTrip(
      stopId: map['stopId'] as String,
      sequenceOrder: map['sequenceOrder'] as int,
      type: map['type'] as String,
      stopName: map['stopName'] as String,
      coordinates: LatLng(geoPoint.latitude, geoPoint.longitude),
      status: map['status'] as String,
      estimatedArrivalTime: map['estimatedArrivalTime'] as Timestamp?,
      actualArrivalTime: map['actualArrivalTime'] as Timestamp?,
      actualDepartureTime: map['actualDepartureTime'] as Timestamp?,
      associatedRequestIds:
          List<String>.from(map['associatedRequestIds'] as List? ?? []),
      passengers: (map['passengers'] as List<dynamic>? ?? [])
          .map((passengerData) => PassengerActionInStop.fromMap(
              passengerData as Map<String, dynamic>))
          .toList(),
    );
  }

  // Method to convert a StopInTrip instance to a map (e.g., for Firestore)
  Map<String, dynamic> toMap() {
    return {
      'stopId': stopId,
      'sequenceOrder': sequenceOrder,
      'type': type,
      'stopName': stopName,
      'coordinates': GeoPoint(
          coordinates.latitude, coordinates.longitude), // แปลงกลับเป็น GeoPoint
      'status': status,
      'estimatedArrivalTime': estimatedArrivalTime,
      'actualArrivalTime': actualArrivalTime,
      'actualDepartureTime': actualDepartureTime,
      'associatedRequestIds': associatedRequestIds,
      'passengers': passengers.map((p) => p.toMap()).toList(),
    };
  }

  // Helper getter for LatLng, already defined as coordinates
  LatLng get latLng => coordinates;
}
