// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'firebase_options.dart';

// URL ของ API ที่คุณได้มาจากการ Deploy
const String apiUrl =
    "https://asia-southeast1-shuttle-tracking-7f71a.cloudfunctions.net/api";

// --- Models (เหมือนเดิม) ---
class Building {
  final String id;
  final String name;
  Building({required this.id, required this.name});
  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(id: json['id'], name: json['name']);
  }
}

class RideRequest {
  final String id;
  final String status;
  final String? driverId;
  RideRequest({required this.id, required this.status, this.driverId});
}

// --- Main (เหมือนเดิม) ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Tram Request',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const RequestScreen(),
    );
  }
}

// --- หน้าจอเรียกรถ (Request Screen - เหมือนเดิม) ---
class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});
  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  List<Building> _buildings = [];
  Building? _selectedPickup;
  Building? _selectedDropoff;
  bool _isLoading = true;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchBuildings();
  }

  Future<void> _fetchBuildings() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/buildings'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _buildings = data.map((json) => Building.fromJson(json)).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitRequest() async {
    if (_selectedPickup == null || _selectedDropoff == null) {
      setState(() => _statusMessage = 'Please select both locations.');
      return;
    }
    if (_selectedPickup!.id == _selectedDropoff!.id) {
      setState(() => _statusMessage = 'Locations cannot be the same.');
      return;
    }
    setState(() => _statusMessage = 'Submitting request...');
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/requests'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': 'test_user_id',
          'pickupBuildingId': _selectedPickup!.id,
          'dropoffBuildingId': _selectedDropoff!.id,
          'pickupPointName': _selectedPickup!.name,
          'dropoffPointName': _selectedDropoff!.name,
        }),
      );
      if (response.statusCode == 201 && mounted) {
        final newRequestId = json.decode(response.body)['id'];
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => TrackingScreen(requestId: newRequestId),
        ));
        _clearForm();
      } else {
        setState(() => _statusMessage = 'Failed to submit request.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error: ${e.toString()}');
    }
  }

  void _clearForm() {
    setState(() {
      _selectedPickup = null;
      _selectedDropoff = null;
      _statusMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request a Ride')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<Building>(
                      value: _selectedPickup,
                      hint: const Text('Select Pickup Location'),
                      items: _buildings
                          .map((b) =>
                              DropdownMenuItem(value: b, child: Text(b.name)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedPickup = val),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<Building>(
                      value: _selectedDropoff,
                      hint: const Text('Select Drop-off Location'),
                      items: _buildings
                          .map((b) =>
                              DropdownMenuItem(value: b, child: Text(b.name)))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedDropoff = val),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _submitRequest,
                      child: const Text('Confirm Request'),
                    ),
                    if (_statusMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child:
                            Text(_statusMessage, textAlign: TextAlign.center),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

// --- หน้าจอติดตามรถ (Tracking Screen - เหมือนเดิม) ---
class TrackingScreen extends StatefulWidget {
  final String requestId;
  const TrackingScreen({super.key, required this.requestId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Stream<DocumentSnapshot>? _requestStream;
  RideRequest? _rideRequest;

  @override
  void initState() {
    super.initState();
    _requestStream = FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(widget.requestId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking Ride')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _requestStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Request not found.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          _rideRequest = RideRequest(
            id: snapshot.data!.id,
            status: data['status'],
            driverId: data['driverId'],
          );

          switch (_rideRequest!.status) {
            case 'pending':
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('Finding a driver...', style: TextStyle(fontSize: 18)),
                  ],
                ),
              );
            case 'accepted':
              return DriverTrackingMap(driverId: _rideRequest!.driverId!);
            case 'completed':
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 80),
                    const SizedBox(height: 20),
                    const Text('Trip Completed!',
                        style: TextStyle(fontSize: 24)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    )
                  ],
                ),
              );
            default:
              return Center(
                  child: Text('Unknown status: ${_rideRequest!.status}'));
          }
        },
      ),
    );
  }
}

// --- Widget แผนที่สำหรับติดตามคนขับ (อัปเกรดใหม่) ---
class DriverTrackingMap extends StatefulWidget {
  final String driverId;
  const DriverTrackingMap({super.key, required this.driverId});

  @override
  State<DriverTrackingMap> createState() => _DriverTrackingMapState();
}

class _DriverTrackingMapState extends State<DriverTrackingMap> {
  Stream<DocumentSnapshot>? _driverStream;
  GoogleMapController? _mapController;
  Marker? _driverMarker;
  BitmapDescriptor? _tramIcon; // <<< ตัวแปรสำหรับเก็บไอคอนรถราง

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(18.9039, 98.9216),
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    _loadTramIcon(); // <<< เรียกใช้ฟังก์ชันโหลดไอคอน
    _driverStream = FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.driverId)
        .snapshots();
  }

  // --- ฟังก์ชันใหม่: โหลดไอคอนรถรางจาก assets ---
  Future<void> _loadTramIcon() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/tram_icon.png', // <<< Path ไปยังไฟล์รูปของคุณ
    );
    if (mounted) {
      setState(() {
        _tramIcon = icon;
      });
    }
  }

  // --- อัปเกรด: ใช้ไอคอนใหม่ในการสร้าง Marker ---
  void _updateMarker(GeoPoint location) {
    final newPosition = LatLng(location.latitude, location.longitude);
    if (mounted) {
      setState(() {
        _driverMarker = Marker(
          markerId: const MarkerId('driver'),
          position: newPosition,
          icon:
              _tramIcon ?? BitmapDescriptor.defaultMarker, // <<< ใช้ไอคอนรถราง
          infoWindow: const InfoWindow(title: 'Driver'),
          anchor: const Offset(0.5, 0.5), // ทำให้ไอคอนอยู่ตรงกลางพิกัด
          flat: true, // ทำให้ไอคอนไม่หมุนตามแผนที่
        );
      });
    }
    _mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _driverStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final location = data['currentLocation'] as GeoPoint?;
          if (location != null) {
            // เรียกใช้ _updateMarker เมื่อมีข้อมูลใหม่
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateMarker(location);
            });
          }
        }
        return GoogleMap(
          initialCameraPosition: _initialPosition,
          onMapCreated: (controller) => _mapController = controller,
          markers: _driverMarker != null ? {_driverMarker!} : {},
        );
      },
    );
  }
}
