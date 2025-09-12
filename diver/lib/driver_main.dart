// lib/driver_main.dart (แก้ไขข้อผิดพลาดแล้ว)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geofence_service/geofence_service.dart';
import 'services/auth_service.dart';

const String apiUrl =
    "https://asia-southeast1-shuttle-tracking-7f71a.cloudfunctions.net";

// --- Models ---
class RideRequest {
  final String id;
  final String status;
  final String pickupPointName;
  final String dropoffPointName;
  final int passengerCount;
  final GeoPoint pickupCoordinates;
  final GeoPoint dropoffCoordinates;

  RideRequest({
    required this.id,
    required this.status,
    required this.pickupPointName,
    required this.dropoffPointName,
    required this.passengerCount,
    required this.pickupCoordinates,
    required this.dropoffCoordinates,
  });

  factory RideRequest.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final pickupCoords = data['pickupPoint']?['coordinates'] as GeoPoint? ??
        const GeoPoint(0, 0);
    final dropoffCoords = data['dropoffPoint']?['coordinates'] as GeoPoint? ??
        const GeoPoint(0, 0);

    return RideRequest(
      id: doc.id,
      status: data['status'] ?? 'unknown',
      pickupPointName: data['pickupPointName'] ?? 'N/A',
      dropoffPointName: data['dropoffPointName'] ?? 'N/A',
      passengerCount: data['passengerCount'] ?? 1,
      pickupCoordinates: pickupCoords,
      dropoffCoordinates: dropoffCoords,
    );
  }
}

class DriverMain extends StatefulWidget {
  const DriverMain({super.key});

  @override
  State<DriverMain> createState() => _DriverMainState();
}

class _DriverMainState extends State<DriverMain> {
  Timer? _locationUpdateTimer;
  String _locationStatus = 'Initializing...';
  String? _driverId;

  List<RideRequest> _currentTrips = [];
  final Set<String> _triggeredActions = {};

  GeofenceService? _geofenceService;
  final Set<String> _trackedRequestIds = {};

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _driverId = user.uid;

      if (kIsWeb) {
        print(
            "🚀 Running on Web platform. Initializing Timer-based location check.");
        _startLocationUpdatesWithTimerCheck();
      } else {
        print("📱 Running on Mobile platform. Initializing Geofence service.");
        _initializeMobileGeofencing();
        _startLocationUpdates();
      }

      _updatePresence(true);
      _updateDriverStatusInFirestore('online');
    } else {
      _locationStatus = "Error: Not logged in!";
    }
  }

  // =================================================================
  // WEB-SPECIFIC LOGIC 💻 (ทำงานเมื่อ kIsWeb == true)
  // =================================================================
  Future<void> _checkProximityAndUpdate(gl.Position currentPosition) async {
    if (_currentTrips.isEmpty) return;
    const double arrivalThresholdMeters = 150.0;
    for (final request in _currentTrips) {
      if (request.status == 'accepted' &&
          !_triggeredActions.contains('${request.id}_pickup')) {
        double distance = gl.Geolocator.distanceBetween(
            currentPosition.latitude,
            currentPosition.longitude,
            request.pickupCoordinates.latitude,
            request.pickupCoordinates.longitude);
        print(
            "WEB_CHECK: Distance to pickup for ${request.id}: ${distance.toStringAsFixed(2)}m");
        if (distance <= arrivalThresholdMeters) {
          print(
              "WEB_ACTION: ➡️ Arrived at PICKUP for ${request.id}. Confirming...");
          _triggeredActions.add('${request.id}_pickup');
          await _updateTripStatus(request.id, 'on_trip');
        }
      } else if (request.status == 'on_trip' &&
          !_triggeredActions.contains('${request.id}_dropoff')) {
        double distance = gl.Geolocator.distanceBetween(
            currentPosition.latitude,
            currentPosition.longitude,
            request.dropoffCoordinates.latitude,
            request.dropoffCoordinates.longitude);
        print(
            "WEB_CHECK: Distance to dropoff for ${request.id}: ${distance.toStringAsFixed(2)}m");
        if (distance <= arrivalThresholdMeters) {
          print(
              "WEB_ACTION: 🏁 Arrived at DROPOFF for ${request.id}. Completing trip...");
          _triggeredActions.add('${request.id}_dropoff');
          await _updateTripStatus(request.id, 'completed');
        }
      }
    }
  }

  Future<void> _startLocationUpdatesWithTimerCheck() async {
    bool serviceEnabled;
    gl.LocationPermission permission;
    serviceEnabled = await gl.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        setState(() => _locationStatus = 'Location services disabled.');
      return;
    }
    permission = await gl.Geolocator.checkPermission();
    if (permission == gl.LocationPermission.denied) {
      permission = await gl.Geolocator.requestPermission();
      if (permission == gl.LocationPermission.denied) {
        if (mounted)
          setState(() => _locationStatus = 'Location permissions denied.');
        return;
      }
    }
    if (permission == gl.LocationPermission.deniedForever) {
      if (mounted)
        setState(
            () => _locationStatus = 'Location permissions permanently denied.');
      return;
    }

    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        gl.Position position = await gl.Geolocator.getCurrentPosition();
        if (mounted)
          setState(() => _locationStatus =
              'Web Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}');
        await http.put(
          Uri.parse('$apiUrl/updateDriverLocation/$_driverId'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(
              {'latitude': position.latitude, 'longitude': position.longitude}),
        );
        await _checkProximityAndUpdate(position);
      } catch (e) {
        if (mounted)
          setState(() => _locationStatus = 'Could not get location. Error: $e');
      }
    });
  }

  // =================================================================
  // MOBILE-SPECIFIC LOGIC 📱 (ทำงานเมื่อ kIsWeb == false)
  // =================================================================
  void _initializeMobileGeofencing() {
    _geofenceService = GeofenceService.instance.setup(
        interval: 5000,
        accuracy: 100,
        loiteringDelayMs: 15000,
        statusChangeDelayMs: 10000,
        useActivityRecognition: true,
        allowMockLocations: true,
        printDevLog: true,
        geofenceRadiusSortType: GeofenceRadiusSortType.DESC);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geofenceService!
          .addGeofenceStatusChangeListener(_onGeofenceStatusChanged);
      _geofenceService!.addLocationServicesStatusChangeListener(
          _onLocationServicesStatusChanged);
      _geofenceService!.addStreamErrorListener(_onError);
      _geofenceService!.start().catchError(_onError);
    });
  }

  Future<void> _onGeofenceStatusChanged(
      Geofence geofence,
      GeofenceRadius geofenceRadius,
      GeofenceStatus geofenceStatus,
      Location location) async {
    print(
        'MOBILE_EVENT: ✅ Geofence Event: ID=${geofence.id}, Status=${geofenceStatus.toString()}');
    if (geofenceStatus == GeofenceStatus.DWELL) {
      final parts = geofence.id.split('_');
      if (parts.length < 2) return;
      final requestId = parts.first;
      final pointType = parts.last;
      if (pointType == 'pickup') {
        print(
            "MOBILE_ACTION: ➡️ Arrived at PICKUP for $requestId. Confirming...");
        await _updateTripStatus(requestId, 'on_trip');
        _geofenceService?.removeGeofenceById(geofence.id);
      } else if (pointType == 'dropoff') {
        print(
            "MOBILE_ACTION: 🏁 Arrived at DROPOFF for $requestId. Completing trip...");
        await _updateTripStatus(requestId, 'completed');
        _geofenceService?.removeGeofenceById(geofence.id);
        if (mounted) setState(() => _trackedRequestIds.remove(requestId));
      }
    }
  }

  void _onLocationServicesStatusChanged(bool status) {
    print('MOBILE_EVENT: Location Services status: $status');
  }

  void _onError(error) {
    final errorCode = getErrorCodesFromError(error);
    if (errorCode == null) {
      print('MOBILE_EVENT: Undefined error: $error');
      return;
    }
    print('MOBILE_EVENT: Geofence ErrorCode: $errorCode');
  }

  void _startGeofencingForTrip(RideRequest request) {
    if (_trackedRequestIds.contains(request.id)) return;
    _trackedRequestIds.add(request.id);
    print("MOBILE_ACTION: 🚀 Starting geofencing for trip: ${request.id}");

    final pickupGeofence = Geofence(
        id: '${request.id}_pickup',
        latitude: request.pickupCoordinates.latitude,
        longitude: request.pickupCoordinates.longitude,
        radius: [GeofenceRadius(id: 'pickup_radius', length: 150)]);
    final dropoffGeofence = Geofence(
        id: '${request.id}_dropoff',
        latitude: request.dropoffCoordinates.latitude,
        longitude: request.dropoffCoordinates.longitude,
        radius: [GeofenceRadius(id: 'dropoff_radius', length: 150)]);

    _geofenceService?.addGeofenceList([pickupGeofence, dropoffGeofence]);
  }

  // =================================================================
  // SHARED LOGIC (ใช้ร่วมกันทั้ง Web และ Mobile)
  // =================================================================
  @override
  void dispose() {
    _updatePresence(false);
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled;
    gl.LocationPermission permission;
    serviceEnabled = await gl.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        setState(() => _locationStatus = 'Location services disabled.');
      return;
    }
    permission = await gl.Geolocator.checkPermission();
    if (permission == gl.LocationPermission.denied) {
      permission = await gl.Geolocator.requestPermission();
      if (permission == gl.LocationPermission.denied) {
        if (mounted)
          setState(() => _locationStatus = 'Location permissions denied.');
        return;
      }
    }
    if (permission == gl.LocationPermission.deniedForever) {
      if (mounted)
        setState(
            () => _locationStatus = 'Location permissions permanently denied.');
      return;
    }

    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        gl.Position position = await gl.Geolocator.getCurrentPosition(
            desiredAccuracy: gl.LocationAccuracy.high);
        if (mounted)
          setState(() => _locationStatus =
              'Mobile Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}');
        await http.put(
          Uri.parse('$apiUrl/updateDriverLocation/$_driverId'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(
              {'latitude': position.latitude, 'longitude': position.longitude}),
        );
      } catch (e) {
        if (mounted)
          setState(() => _locationStatus = 'Could not get location. Error: $e');
      }
    });
  }

  Future<void> _updateTripStatus(String requestId, String newStatus) async {
    String functionName = '';
    if (newStatus == 'on_trip') {
      functionName = 'confirmPickup';
    } else if (newStatus == 'completed') {
      functionName = 'completeTrip';
    } else {
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/$functionName/$requestId'),
      );
      if (response.statusCode != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถอัปเดตสถานะได้: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  /// ✅ **[FIXED]** แก้ไขฟังก์ชันนี้ให้เป็น async และคืนค่า Future<void>
  Future<void> _updatePresence(bool isOnline) async {
    if (_driverId == null) return;
    final dbRef = FirebaseDatabase.instance.ref("driverStatus/$_driverId");
    if (isOnline) {
      // เพิ่ม await เพื่อรอให้การทำงานกับฐานข้อมูลเสร็จสิ้น
      await dbRef.set({
        'isOnline': true,
        'last_seen': ServerValue.timestamp,
      });
      // onDisconnect ไม่ใช่ async จึงไม่ต้อง await
      dbRef.onDisconnect().set({
        'isOnline': false,
        'last_seen': ServerValue.timestamp,
      });
    } else {
      // เพิ่ม await เพื่อรอให้การทำงานกับฐานข้อมูลเสร็จสิ้น
      await dbRef.set({
        'isOnline': false,
        'last_seen': ServerValue.timestamp,
      });
    }
  }

  Future<void> _updateDriverStatusInFirestore(String status,
      {String? reason}) async {
    if (_driverId == null) return;
    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverId)
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
              hintText: 'เช่น พักส่วนตัว',
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

  Future<void> _logout() async {
    /// ✅ **[FIXED]** ตอนนี้บรรทัดนี้จะทำงานได้ถูกต้อง
    await _updatePresence(false);
    await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_driverId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("เกิดข้อผิดพลาด: ไม่สามารถระบุคนขับได้"),
              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: _logout, child: const Text("กลับไปหน้า Login")),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .snapshots(),
      builder: (context, driverSnapshot) {
        if (!driverSnapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (!driverSnapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('ไม่พบข้อมูลคนขับในระบบ'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _logout,
                      child: const Text('กลับไปหน้า Login'),
                    )
                  ],
                ),
              ),
            ),
          );
        }
        final driverData = driverSnapshot.data!.data() as Map<String, dynamic>;
        final bool isTrulyOnline = (driverData['status'] == 'online');
        return Scaffold(
          appBar: AppBar(
            title: Text(isTrulyOnline ? 'แอปคนขับ' : 'ปิดให้บริการ'),
            backgroundColor: isTrulyOnline ? Colors.green : Colors.grey,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _logout,
                tooltip: 'Logout',
              )
            ],
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

  Map<String, int> _summarizeLocations(
      List<RideRequest> trips, String pointType) {
    final Map<String, int> summary = {};
    for (var trip in trips) {
      final locationName = pointType == 'pickupPointName'
          ? trip.pickupPointName
          : trip.dropoffPointName;
      final passengers = trip.passengerCount;
      summary.update(locationName, (value) => value + passengers,
          ifAbsent: () => passengers);
    }
    return summary;
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
          .where('driverId', isEqualTo: _driverId)
          .where('status', whereIn: ['accepted', 'on_trip']).snapshots(),
      builder: (context, tripSnapshot) {
        if (tripSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tripSnapshot.hasError) {
          return Center(child: Text('Error: ${tripSnapshot.error}'));
        }

        if (tripSnapshot.hasData) {
          _currentTrips = tripSnapshot.data!.docs
              .map((doc) => RideRequest.fromSnapshot(doc))
              .toList();

          final currentTripIds = _currentTrips.map((t) => t.id).toSet();
          _triggeredActions.removeWhere((action) {
            final tripId = action.split('_').first;
            return !currentTripIds.contains(tripId);
          });
        } else {
          _currentTrips = [];
          _triggeredActions.clear();
        }

        if (_currentTrips.isEmpty) {
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

        if (!kIsWeb) {
          for (var trip in _currentTrips) {
            _startGeofencingForTrip(trip);
          }
        }

        final pickupSummary = _summarizeLocations(
            _currentTrips.where((t) => t.status == 'accepted').toList(),
            'pickupPointName');
        final dropoffSummary =
            _summarizeLocations(_currentTrips, 'dropoffPointName');

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'งานปัจจุบัน (${driverData['currentPassengers'] ?? 0}/${driverData['capacity'] ?? 10} คน)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700)),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTripInfoColumn('จุดรับ', pickupSummary),
                        const VerticalDivider(width: 32, thickness: 1),
                        _buildTripInfoColumn('จุดส่ง', dropoffSummary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTripInfoColumn(String title, Map<String, int> locations) {
    return Expanded(
      child: Column(
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          if (locations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child:
                  Text('-', style: TextStyle(fontSize: 18, color: Colors.grey)),
            ),
          Expanded(
            child: ListView(
              children: locations.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      Text(entry.key,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person,
                              color: Colors.grey, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${entry.value} passengers',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
