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

// --- 🎯 แก้ไข: ID ของคนขับคนที่ 2 ---
const String currentDriverId = "oL5Ub0sKjwQdQ6xizvx9GZxFRau1";
// ------------------------------------

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

class GroupedTrip {
  final String pickupPointName;
  final String dropoffPointName;
  int totalPassengers;

  GroupedTrip({
    required this.pickupPointName,
    required this.dropoffPointName,
    this.totalPassengers = 0,
  });
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
  Stream<QuerySnapshot>? _myTripsStream;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    _myTripsStream = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('driverId', isEqualTo: currentDriverId)
        .where('status', isEqualTo: 'accepted')
        .snapshots();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

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

  List<GroupedTrip> _groupTrips(List<RideRequest> requests) {
    final Map<String, GroupedTrip> groupedMap = {};

    for (var request in requests) {
      final key = '${request.pickupPointName}-${request.dropoffPointName}';

      if (groupedMap.containsKey(key)) {
        groupedMap[key]!.totalPassengers += request.passengerCount;
      } else {
        groupedMap[key] = GroupedTrip(
          pickupPointName: request.pickupPointName,
          dropoffPointName: request.dropoffPointName,
          totalPassengers: request.passengerCount,
        );
      }
    }
    return groupedMap.values.toList();
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
            title: const Text('My Assigned Trips'),
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
              child: Text(_locationStatus, textAlign: TextAlign.center),
            ),
          ),
          body: _buildDriverBody(driverStatus, driverData),
        );
      },
    );
  }

  Widget _buildDriverBody(
      String driverStatus, Map<String, dynamic> driverData) {
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

    return StreamBuilder<QuerySnapshot>(
      stream: _myTripsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('Waiting for a trip...',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
          );
        }

        final requests = snapshot.data!.docs
            .map((doc) => RideRequest.fromSnapshot(doc))
            .toList();
        final groupedTrips = _groupTrips(requests);

        return ListView.builder(
          itemCount: groupedTrips.length,
          itemBuilder: (context, index) {
            final trip = groupedTrips[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trip #${index + 1}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('From: ${trip.pickupPointName}'),
                    Text('To: ${trip.dropoffPointName}'),
                    Text('Total Passengers: ${trip.totalPassengers}'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
