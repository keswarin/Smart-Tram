// lib/driver_main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'firebase_options.dart';

// URL ของ API
const String apiUrl = "https://api-nlcuxevdba-as.a.run.app";

// ID ของคนขับ
const String currentDriverId = "oL5Ub0sKjwQdQ6xizvx9GZxFRau1";

// --- Models ---
class RideRequest {
  final String pickupPointName;
  final String dropoffPointName;
  final int passengerCount;

  RideRequest({
    required this.pickupPointName,
    required this.dropoffPointName,
    required this.passengerCount,
  });

  factory RideRequest.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RideRequest(
      pickupPointName: data['pickupPointName'] ?? 'N/A',
      dropoffPointName: data['dropoffPointName'] ?? 'N/A',
      passengerCount: data['passengerCount'] ?? 1,
    );
  }
}

class TripSummary {
  final Map<String, int> pickups;
  final Map<String, int> dropoffs;

  TripSummary({required this.pickups, required this.dropoffs});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver App',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        // ✅ ใช้ CardThemeData ที่ถูกต้อง
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const DriverScreen(),
    );
  }
}

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  Timer? _locationUpdateTimer;
  String _locationStatus = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _startLocationUpdates() async {
    // ... (โค้ดส่วนนี้เหมือนเดิม) ...
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        if (mounted)
          setState(() => _locationStatus = 'Location permissions are denied.');
        return;
      }
    }
    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        if (mounted) {
          setState(() {
            _locationStatus =
                'Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          });
        }
        await http.put(
          Uri.parse('$apiUrl/drivers/$currentDriverId/location'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(
              {'latitude': position.latitude, 'longitude': position.longitude}),
        );
      } catch (e) {
        if (mounted)
          setState(() => _locationStatus = 'Could not get location.');
      }
    });
  }

  Future<void> _updateDriverStatus(String status, {String? reason}) async {
    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(currentDriverId)
        .update({
      'status': status,
      'pauseReason': reason ?? FieldValue.delete(),
    });
  }

  void _showPauseDialog() {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pause Service'),
          content: TextField(
            controller: reasonController,
            decoration:
                const InputDecoration(hintText: 'Enter reason (optional)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _updateDriverStatus('paused', reason: reasonController.text);
                Navigator.pop(context);
              },
              child: const Text('Confirm Pause'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentDriverId)
          .snapshots(),
      builder: (context, driverSnapshot) {
        if (!driverSnapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final driverData = driverSnapshot.data!.data() as Map<String, dynamic>;
        final driverStatus = driverData['status'] ?? 'offline';

        return Scaffold(
          appBar: AppBar(
            title: Text(
                driverStatus == 'online' ? 'Driver App' : 'Service Paused'),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: driverStatus == 'online'
              ? FloatingActionButton.extended(
                  onPressed: _showPauseDialog,
                  label: const Text('Pause Service'),
                  icon: const Icon(Icons.pause),
                  backgroundColor: Colors.red,
                )
              : FloatingActionButton.extended(
                  onPressed: () => _updateDriverStatus('online'),
                  label: const Text('Resume Service'),
                  icon: const Icon(Icons.play_arrow),
                  backgroundColor: Colors.green,
                ),
          bottomNavigationBar: BottomAppBar(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_locationStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
            ),
          ),
          body: _buildDriverBody(driverStatus, driverData),
        );
      },
    );
  }

  // --- 🎯 แก้ไข: เปลี่ยน Logic การแสดงผลทั้งหมด ---
  Widget _buildDriverBody(
      String driverStatus, Map<String, dynamic> driverData) {
    // ถ้าคนขับหยุดพัก ให้แสดงหน้าจอหยุดพัก
    if (driverStatus == 'paused') {
      final reason = driverData['pauseReason'] ?? '';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pause, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Service Paused',
                style: TextStyle(fontSize: 22, color: Colors.grey)),
            if (reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Reason: $reason',
                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
              ),
          ],
        ),
      );
    }

    // ถ้าคนขับออนไลน์ ให้ไปดึงงานที่ได้รับมอบหมายมาแสดง
    // ใช้ StreamBuilder อีกชั้นเพื่อดึงข้อมูลงานแบบ Real-time
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_requests')
          .where('driverId', isEqualTo: currentDriverId)
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, tripSnapshot) {
        if (tripSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tripSnapshot.hasError) {
          return Center(child: Text('Error: ${tripSnapshot.error}'));
        }
        // ถ้าไม่มีงานที่ได้รับมอบหมาย ให้แสดงว่า "กำลังรองาน"
        if (!tripSnapshot.hasData || tripSnapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('Waiting for a trip...',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
          );
        }

        // ถ้ามีงาน ให้จัดกลุ่มและแสดงผล
        final requests = tripSnapshot.data!.docs
            .map((doc) => RideRequest.fromSnapshot(doc))
            .toList();
        final summary = _summarizeTrips(requests);

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('My Assigned Trips',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      _buildTripInfoColumn('PICKUP', summary.pickups),
                      const VerticalDivider(width: 32, thickness: 1),
                      _buildTripInfoColumn('DROP-OFF', summary.dropoffs),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ฟังก์ชันจัดกลุ่ม
  TripSummary _summarizeTrips(List<RideRequest> requests) {
    final Map<String, int> pickups = {};
    final Map<String, int> dropoffs = {};

    for (var request in requests) {
      pickups.update(
          request.pickupPointName, (value) => value + request.passengerCount,
          ifAbsent: () => request.passengerCount);
      dropoffs.update(
          request.dropoffPointName, (value) => value + request.passengerCount,
          ifAbsent: () => request.passengerCount);
    }
    return TripSummary(pickups: pickups, dropoffs: dropoffs);
  }

  // ฟังก์ชันสร้าง UI แต่ละฝั่ง
  Widget _buildTripInfoColumn(String title, Map<String, int> locations) {
    return Expanded(
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...locations.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  Text(entry.key,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Icon(Icons.person, color: Colors.grey),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.value} passengers',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
