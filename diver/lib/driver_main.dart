// lib/driver_main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <<< เพิ่ม Firestore
import 'package:geolocator/geolocator.dart';
import 'firebase_options.dart';

// URL ของ API ที่คุณได้มาจากการ Deploy
const String apiUrl =
    "https://asia-southeast1-shuttle-tracking-7f71a.cloudfunctions.net/api";

// TODO: เปลี่ยนเป็น ID ของคนขับที่ล็อกอินจริงในอนาคต
const String currentDriverId = "iuKw2zWz1we31CBuQcA00E6acr93";

// Model RideRequest (เหมือนเดิม)
class RideRequest {
  final String id;
  final String pickupPointName;
  final String dropoffPointName;
  final String userId;

  RideRequest({
    required this.id,
    required this.pickupPointName,
    required this.dropoffPointName,
    required this.userId,
  });

  factory RideRequest.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RideRequest(
      id: doc.id,
      pickupPointName: data['pickupPointName'] ?? 'N/A',
      dropoffPointName: data['dropoffPointName'] ?? 'N/A',
      userId: data['userId'] ?? 'N/A',
    );
  }
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
        primarySwatch: Colors.orange,
        visualDensity: VisualDensity.adaptivePlatformDensity,
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
  // --- เปลี่ยนมาใช้ Stream ---
  Stream<QuerySnapshot>? _requestsStream;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    // --- เริ่มดักฟังข้อมูลจาก Firestore ---
    _requestsStream = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  // ฟังก์ชันส่งตำแหน่ง (เหมือนเดิม)
  Future<void> _startLocationUpdates() async {
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

  // ฟังก์ชันรับงาน (เหมือนเดิม)
  Future<void> _acceptRequest(String requestId) async {
    try {
      final response = await http.put(
        Uri.parse('$apiUrl/requests/$requestId/accept'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'driverId': currentDriverId}),
      );
      if (response.statusCode != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to accept request. Status: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Requests'),
        // --- ไม่ต้องมีปุ่ม Refresh แล้ว ---
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(_locationStatus, textAlign: TextAlign.center),
        ),
      ),
      // --- เปลี่ยนมาใช้ StreamBuilder ---
      body: StreamBuilder<QuerySnapshot>(
        stream: _requestsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No pending requests.',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
            );
          }

          final requests = snapshot.data!.docs
              .map((doc) => RideRequest.fromSnapshot(doc))
              .toList();

          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text('From: ${request.pickupPointName}'),
                  subtitle: Text('To: ${request.dropoffPointName}'),
                  trailing: ElevatedButton(
                    onPressed: () => _acceptRequest(request.id),
                    child: const Text('Accept'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
