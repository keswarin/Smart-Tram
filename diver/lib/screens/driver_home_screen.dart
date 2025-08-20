import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/active_trip_model.dart';
import '../models/stop_in_trip_model.dart';
import 'login_screen.dart';
import 'request_list_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  String? _driverId;
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _locationSubscription;
  LatLng? _currentLocation;
  String? _assignedVehicleId;
  String? _assignedVehicleDisplayName;

  StreamSubscription? _activeTripSubscription;
  ActiveTrip? _activeTrip;
  int _currentStopIndex = -1;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _driverId = FirebaseAuth.instance.currentUser?.uid;
    _initializeDriver();
  }

  @override
  void dispose() {
    _activeTripSubscription?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeDriver() async {
    setState(() => _isLoading = true);
    await _fetchDriverInfo();
    await _initializeLocation();
    _listenForActiveTrip();
    setState(() => _isLoading = false);
  }

  Future<void> _fetchDriverInfo() async {
    if (_driverId == null) {
      setState(() => _errorMessage = "ไม่พบ ID คนขับ");
      return;
    }
    final driverDoc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverId)
        .get();
    if (mounted && driverDoc.exists) {
      final data = driverDoc.data() as Map<String, dynamic>;
      final vehicleId = data['assignedVehicleId'];
      if (vehicleId != null) {
        final vehicleDoc = await FirebaseFirestore.instance
            .collection('vehicles')
            .doc(vehicleId)
            .get();
        if (mounted && vehicleDoc.exists) {
          setState(() {
            _assignedVehicleId = vehicleId;
            _assignedVehicleDisplayName =
                (vehicleDoc.data() as Map<String, dynamic>)['displayName'];
          });
        }
      }
    }
  }

  Future<void> _initializeLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('กรุณาอนุญาตการเข้าถึงตำแหน่งสำหรับโหมดคนขับ')),
          );
        }
        return;
      }
    }

    final first = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    _currentLocation = LatLng(first.latitude, first.longitude);
    await _publishDriverLocation(first);

    _locationSubscription?.cancel();
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      await _publishDriverLocation(pos);
      if (mounted) setState(() {});
    });
  }

  /// ยิงตำแหน่งคนขับขึ้น Firestore
  Future<void> _publishDriverLocation(Position pos) async {
    if (_driverId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .set({
        'coordinates': GeoPoint(pos.latitude, pos.longitude),
        'heading': pos.heading,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _listenForActiveTrip() {
    if (_driverId == null) return;
    _activeTripSubscription?.cancel();
    _activeTripSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverId)
        .collection('assigned_routes')
        .doc('current')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _activeTrip = ActiveTrip.fromSnapshot(snapshot);

          // หา stop ตัวแรกที่ยังไม่ completed; ถ้าไม่เจอให้ใช้ตัวแรก
          _currentStopIndex = _activeTrip!.stops
              .indexWhere((s) => s.status != 'action_completed');
          if (_currentStopIndex < 0 && _activeTrip!.stops.isNotEmpty) {
            _currentStopIndex = 0;
          }
        });
      } else {
        setState(() {
          _activeTrip = null;
          _currentStopIndex = -1;
        });
        FirebaseFirestore.instance
            .collection('drivers')
            .doc(_driverId)
            .update({'isAvailable': true});
      }
    });
  }

  /// คนขับกดเสร็จสิ้นที่จุดนี้ / เสร็จสิ้น Trip
  Future<void> _completeCurrentStop() async {
    if (_activeTrip == null || _activeTrip!.stops.isEmpty) return;

    final idx = _currentStopIndex >= 0 ? _currentStopIndex : 0;
    final StopInTrip currentStop = _activeTrip!.stops[idx];
    currentStop.status = 'action_completed';

    final batch = FirebaseFirestore.instance.batch();
    final isLastStop = idx == _activeTrip!.stops.length - 1;

    final activeTripRef = FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverId)
        .collection('assigned_routes')
        .doc('current');

    if (isLastStop) {
      // ปิดเที่ยว: ลบ current + ปิดคำขอทั้งหมด
      batch.delete(activeTripRef);
      for (final reqId in _activeTrip!.requestIds) {
        batch.update(
          FirebaseFirestore.instance.collection('ride_requests').doc(reqId),
          {
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          },
        );
      }
    } else {
      // อัปเดตสถานะ stops
      batch.update(activeTripRef,
          {'stops': _activeTrip!.stops.map((e) => e.toMap()).toList()});
    }

    try {
      await batch.commit();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('คนขับ (${_assignedVehicleDisplayName ?? ""})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RequestListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentLocation ?? const LatLng(19.025, 98.935),
                    zoom: 15.5,
                  ),
                  myLocationEnabled: true,
                  markers: _buildMarkers(),
                ),
                if (_activeTrip != null) _buildTripInfoPanel(),
                if (_activeTrip == null && _errorMessage == null)
                  _buildIdlePanel(),
              ],
            ),
    );
  }

  /// แผงรายละเอียดงาน “ติดหน้าจอ” (ถาวรจนกว่าจะกดเสร็จสิ้น)
  Widget _buildTripInfoPanel() {
    final idx = _currentStopIndex >= 0 ? _currentStopIndex : 0;
    final currentStop = _activeTrip!.stops[idx];

    final pickups =
        currentStop.passengers.where((p) => p.action == 'pickup').toList();
    final dropoffs =
        currentStop.passengers.where((p) => p.action == 'dropoff').toList();

    StopInTrip? nextStop;
    if (idx + 1 < _activeTrip!.stops.length) {
      nextStop = _activeTrip!.stops[idx + 1];
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
                blurRadius: 12, offset: Offset(0, -2), color: Colors.black12)
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'รอบงานปัจจุบัน • จุดที่ ${idx + 1}/${_activeTrip!.stops.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currentStop.stopName,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        if (pickups.isNotEmpty)
                          Text('รับขึ้น: ${pickups.length} คน',
                              style: Theme.of(context).textTheme.bodyMedium),
                        if (dropoffs.isNotEmpty)
                          Text('ส่งลง: ${dropoffs.length} คน',
                              style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
              if (nextStop != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.flag_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('จุดถัดไป: ${nextStop!.stopName}',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (pickups.isNotEmpty || dropoffs.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (pickups.isNotEmpty)
                      Chip(
                        avatar: const Icon(Icons.call_made, size: 18),
                        label: Text('รับ ${pickups.length}'),
                      ),
                    if (dropoffs.isNotEmpty)
                      Chip(
                        avatar: const Icon(Icons.call_received, size: 18),
                        label: Text('ส่ง ${dropoffs.length}'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              ElevatedButton(
                onPressed: _completeCurrentStop,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(idx == _activeTrip!.stops.length - 1
                    ? 'เสร็จสิ้น Trip'
                    : 'เสร็จสิ้นที่จุดนี้'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdlePanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Card(
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'คุณว่าง รอรับงานใหม่...',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: _currentLocation!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    if (_activeTrip != null && _currentStopIndex >= 0) {
      final currentStop = _activeTrip!.stops[_currentStopIndex];
      markers.add(Marker(
        markerId: MarkerId(currentStop.stopId),
        position: currentStop.coordinates,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: currentStop.stopName),
      ));
    }
    return markers;
  }
}
