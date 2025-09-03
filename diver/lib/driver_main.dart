// lib/driver_main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';

// URL ของ API
const String apiUrl = "https://api-nlcuxevdba-as.a.run.app";

// ID ของคนขับ (สำหรับทดสอบ)
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
      debugShowCheckedModeBanner: false,
      title: 'Driver App',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
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

  void _updatePresence(bool isOnline) {
    final dbRef =
        FirebaseDatabase.instance.ref("driverStatus/$currentDriverId");

    if (isOnline) {
      dbRef.set({
        'isOnline': true,
        'last_seen': ServerValue.timestamp,
      });
      dbRef.onDisconnect().set({
        'isOnline': false,
        'last_seen': ServerValue.timestamp,
      });
    } else {
      dbRef.set({
        'isOnline': false,
        'last_seen': ServerValue.timestamp,
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    _updatePresence(true);
  }

  @override
  void dispose() {
    _updatePresence(false);
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        setState(() => _locationStatus = 'Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted)
          setState(() => _locationStatus = 'Location permissions are denied.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted)
        setState(() =>
            _locationStatus = 'Location permissions are permanently denied.');
      return;
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
        if (mounted) {
          setState(() => _locationStatus = 'Could not get location.');
        }
      }
    });
  }

  Future<void> _updateDriverStatusInFirestore(String status,
      {String? reason}) async {
    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(currentDriverId)
        .update({
      'status': status,
      'pauseReason': reason ?? FieldValue.delete(),
      'isAvailable': status == 'online',
    });
  }

  void _showPauseDialog() {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('หยุดพักบริการ'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'เหตุผล',
              hintText: 'เช่น รถเสีย, พักส่วนตัว',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                final reason = reasonController.text.isNotEmpty
                    ? reasonController.text
                    : "หยุดบริการชั่วคราว";

                _updateDriverStatusInFirestore('paused', reason: reason);
                Navigator.pop(context);
              },
              child: const Text('ยืนยัน'),
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

        final bool isTrulyOnline = (driverData['status'] == 'online') &&
            (driverData['isAvailable'] == true);

        return Scaffold(
          appBar: AppBar(
            title: Text(isTrulyOnline ? 'แอปคนขับ' : 'ปิดให้บริการ'),
            backgroundColor: isTrulyOnline ? Colors.green : Colors.grey,
            foregroundColor: Colors.white,
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: isTrulyOnline
              ? FloatingActionButton.extended(
                  onPressed: _showPauseDialog,
                  label: const Text('หยุดพักบริการ'),
                  icon: const Icon(Icons.pause),
                  backgroundColor: Colors.orange,
                )
              : FloatingActionButton.extended(
                  onPressed: () {
                    _updateDriverStatusInFirestore('online');
                  },
                  label: const Text('ออนไลน์'),
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
          body: _buildDriverBody(isTrulyOnline, driverData),
        );
      },
    );
  }

  Widget _buildDriverBody(bool isTrulyOnline, Map<String, dynamic> driverData) {
    if (!isTrulyOnline) {
      final reason = driverData['pauseReason'] ?? '';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.power_settings_new, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('ปิดให้บริการ',
                style: TextStyle(fontSize: 22, color: Colors.grey)),
            if (reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('เหตุผล: $reason',
                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
              ),
          ],
        ),
      );
    }

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
        if (!tripSnapshot.hasData || tripSnapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.trip_origin, size: 60, color: Colors.green),
                SizedBox(height: 16),
                Text('กำลังรอรับงาน...',
                    style: TextStyle(fontSize: 18, color: Colors.grey)),
              ],
            ),
          );
        }

        final requests = tripSnapshot.data!.docs
            .map((doc) => RideRequest.fromSnapshot(doc))
            .toList();
        final summary = _summarizeTrips(requests);

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('รายการงานของฉัน',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      _buildTripInfoColumn('จุดรับ', summary.pickups),
                      const VerticalDivider(width: 32, thickness: 1),
                      _buildTripInfoColumn('จุดส่ง', summary.dropoffs),
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
                      textAlign: TextAlign.center,
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
