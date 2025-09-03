// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'firebase_options.dart';
import 'gradient_background_animation.dart'; // 🎯 เพิ่ม import ไฟล์ที่คุณสร้างแยก

// URL ของ API
const String apiUrl = "https://api-nlcuxevdba-as.a.run.app";

// --- Models ---
class Building {
  final String id;
  final String name;
  Building({required this.id, required this.name});
  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(id: json['id'], name: json['name']);
  }
}

class _DriverInfo {
  final String id;
  final String name;
  final LatLng position;
  final String status;

  _DriverInfo({
    required this.id,
    required this.name,
    required this.position,
    required this.status,
  });
}

// --- Main ---
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
      debugShowCheckedModeBanner: false,
      title: 'Smart Tram Request',
      theme: ThemeData(
        primarySwatch: Colors.green,
        fontFamily: 'Roboto',
      ),
      home: const RequestScreen(),
    );
  }
}

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});
  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  // --- State ---
  List<Building> _buildings = [];
  Building? _selectedPickup;
  Building? _selectedDropoff;
  final int _passengerCount = 1;
  bool _isLoading = true;
  String? _currentRequestId;
  StreamSubscription<DocumentSnapshot>? _driverSubscription;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  BitmapDescriptor? _tramIcon;
  String _distanceMessage = 'กำลังคำนวณระยะทาง...';
  LatLng? _driverPosition;
  String? _currentlyTrackedDriverId;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(18.7941, 98.9526),
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    _fetchBuildings();
    _loadTramIcon();
  }

  @override
  void dispose() {
    _driverSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadTramIcon() async {
    try {
      final icon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/images/tram_icon.png',
      );
      if (mounted) setState(() => _tramIcon = icon);
    } catch (e) {
      print("Error loading tram icon: $e");
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกทั้งจุดรับและจุดส่ง')),
      );
      return;
    }
    if (_selectedPickup!.id == _selectedDropoff!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('จุดรับและจุดส่งต้องไม่ซ้ำกัน')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final availableDrivers = await FirebaseFirestore.instance
          .collection('drivers')
          .where('status', isEqualTo: 'online')
          .where('isAvailable', isEqualTo: true)
          .limit(1)
          .get();

      if (availableDrivers.docs.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('ขออภัย ไม่มีคนขับที่พร้อมให้บริการในขณะนี้')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final response = await http.post(
        Uri.parse('$apiUrl/requests'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': 'test_user_id',
          'pickupBuildingId': _selectedPickup!.id,
          'dropoffBuildingId': _selectedDropoff!.id,
          'pickupPointName': _selectedPickup!.name,
          'dropoffPointName': _selectedDropoff!.name,
          'passengerCount': _passengerCount,
        }),
      );

      if (response.statusCode == 201 && mounted) {
        final newRequestId = json.decode(response.body)['id'];
        setState(() {
          _currentRequestId = newRequestId;
          _isLoading = false;
        });
        _clearForm();
      } else {
        if (mounted) setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถส่งคำขอได้')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  void _clearForm() {
    setState(() {
      _selectedPickup = null;
      _selectedDropoff = null;
    });
  }

  Future<void> _cancelRequest() async {
    if (_currentRequestId == null) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/requests/$_currentRequestId/cancel'),
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _currentRequestId = null;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยกเลิกคำขอแล้ว')),
        );
      } else {
        if (mounted) setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถยกเลิกคำขอได้')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  void _subscribeToDriverLocation(String driverId, String requestId) {
    if (_currentlyTrackedDriverId == driverId) return;
    _driverSubscription?.cancel();
    _currentlyTrackedDriverId = driverId;
    final driverRef =
        FirebaseFirestore.instance.collection('drivers').doc(driverId);
    _driverSubscription = driverRef.snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data();
        final location = data?['currentLocation'] as GeoPoint?;
        if (location != null) {
          _updateMarkerAndDistance(location, requestId);
        }
      }
    });
  }

  Future<void> _updateMarkerAndDistance(
      GeoPoint driverLocationGeo, String requestId) async {
    final driverLatLng =
        LatLng(driverLocationGeo.latitude, driverLocationGeo.longitude);
    final requestDoc = await FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(requestId)
        .get();
    if (!requestDoc.exists || !mounted) return;
    final requestData = requestDoc.data()!;
    final pickupPointId = requestData['pickupPointId'];
    final pickupDoc = await FirebaseFirestore.instance
        .collection('pickup_points')
        .doc(pickupPointId)
        .get();
    if (!pickupDoc.exists || !mounted) return;

    final pickupLocationGeo = pickupDoc.data()!['coordinates'] as GeoPoint;
    final pickupLatLng =
        LatLng(pickupLocationGeo.latitude, pickupLocationGeo.longitude);
    final distanceInMeters = Geolocator.distanceBetween(driverLatLng.latitude,
        driverLatLng.longitude, pickupLatLng.latitude, pickupLatLng.longitude);
    final distanceInKm = distanceInMeters / 1000;

    final driverMarker = Marker(
      markerId: const MarkerId('driver'),
      position: driverLatLng,
      icon: _tramIcon ?? BitmapDescriptor.defaultMarker,
      anchor: const Offset(0.5, 0.5),
      flat: true,
    );
    final pickupMarker = Marker(
      markerId: const MarkerId('pickup'),
      position: pickupLatLng,
      infoWindow: const InfoWindow(title: 'จุดรับ'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    );

    setState(() {
      _driverPosition = driverLatLng;
      _markers.clear();
      _markers.add(driverMarker);
      _markers.add(pickupMarker);
      _distanceMessage =
          'คนขับจะมาถึงใน ${distanceInKm.toStringAsFixed(2)} กม.';
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(driverLatLng));
  }

  void _centerOnDriver() {
    if (_driverPosition != null && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_driverPosition!));
    }
  }

  void _showCancellationDialog(String reason) {
    if (!mounted || _currentRequestId == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("การเดินทางถูกยกเลิก"),
          content: Text("การเดินทางของคุณถูกยกเลิกโดยคนขับ\nเหตุผล: $reason"),
          actions: <Widget>[
            TextButton(
              child: const Text("ตกลง"),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _currentRequestId = null;
                  _markers.clear();
                  _currentlyTrackedDriverId = null;
                  _driverSubscription?.cancel();
                });
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackgroundAnimation(
      // 🎯 ครอบ Scaffold ด้วย Widget ใหม่
      child: Scaffold(
        backgroundColor: Colors.transparent, // 🎯 ทำให้พื้นหลังโปร่งใส
        appBar: AppBar(
          title:
              Text(_currentRequestId == null ? 'Smart Tram' : 'กำลังติดตามรถ'),
          backgroundColor:
              Colors.white.withOpacity(0.8), // ทำให้ AppBar กึ่งโปร่งใส
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _currentRequestId == null
          ? _buildRequestForm()
          : _buildTrackingView(),
    );
  }

  Widget _buildRequestForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            elevation: 8.0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/images/logo.png', height: 100),
                  const SizedBox(height: 16),
                  const Text('เรียกรถราง',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  _buildDropdown(
                    hint: 'จุดรับ',
                    value: _selectedPickup,
                    onChanged: (val) => setState(() => _selectedPickup = val),
                    icon: Icons.trip_origin,
                  ),
                  const SizedBox(height: 16),
                  _buildDropdown(
                    hint: 'จุดส่ง',
                    value: _selectedDropoff,
                    onChanged: (val) => setState(() => _selectedDropoff = val),
                    icon: Icons.flag,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0)),
                    ),
                    onPressed: _submitRequest,
                    child: const Text('ค้นหาคนขับ',
                        style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => const LiveMapScreen()));
                    },
                    child: const Text('ดูแผนที่',
                        style: TextStyle(color: Colors.black54)),
                  ),
                  const SizedBox(height: 16),
                  _buildServiceTimeIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(
      {required String hint,
      required Building? value,
      required ValueChanged<Building?> onChanged,
      required IconData icon}) {
    return DropdownButtonFormField<Building>(
      value: value,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      ),
      items: _buildings
          .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildServiceTimeIndicator() {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;
    final isMorning = currentHour >= 7 && currentHour <= 9;
    final isNoon = currentHour >= 11 && currentHour <= 13;
    final isEvening = (currentHour >= 15 && currentHour < 17) ||
        (currentHour == 17 && currentMinute <= 45);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildTimeChip("เช้า", "07:00-09:00", isMorning),
        _buildTimeChip("เที่ยง", "11:00-13:00", isNoon),
        _buildTimeChip("เย็น", "15:00-17:45", isEvening),
      ],
    );
  }

  Widget _buildTimeChip(String title, String timeRange, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? Colors.green : Colors.grey[300],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  color: isActive ? Colors.white : Colors.black54,
                  fontSize: 12)),
          const SizedBox(height: 2),
          Text(timeRange,
              style: TextStyle(
                  color: isActive ? Colors.white : Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildTrackingView() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_requests')
          .doc(_currentRequestId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentRequestId != null) {
              setState(() => _currentRequestId = null);
            }
          });
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final status = data['status'] ?? 'unknown';
        final driverId = data['driverId'] as String?;

        switch (status) {
          case 'pending':
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text('กำลังค้นหาคนขับ...',
                      style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _cancelRequest,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                    child: const Text('ยกเลิกคำขอ'),
                  ),
                ],
              ),
            );
          case 'accepted':
            if (driverId != null) {
              _subscribeToDriverLocation(driverId, _currentRequestId!);
              return _buildDriverTrackingMap();
            }
            return const Center(child: Text('คนขับรับงานแล้ว แต่หา ID ไม่เจอ'));

          case 'cancelled_by_driver':
            final reason = data['cancellationReason'] ?? 'ไม่มีเหตุผล';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _currentRequestId != null) {
                _showCancellationDialog(reason);
              }
            });
            return const Center(child: CircularProgressIndicator());

          case 'completed':
            _driverSubscription?.cancel();
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 80),
                  const SizedBox(height: 20),
                  const Text('การเดินทางเสร็จสิ้น!',
                      style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _currentRequestId = null;
                      _markers.clear();
                      _currentlyTrackedDriverId = null;
                    }),
                    child: const Text('เสร็จสิ้น'),
                  )
                ],
              ),
            );
          default:
            return Center(child: Text('สถานะไม่รู้จัก: $status'));
        }
      },
    );
  }

  Widget _buildDriverTrackingMap() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialPosition,
          onMapCreated: (controller) => _mapController = controller,
          markers: _markers,
        ),
        Positioned(
          top: 10,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))
              ],
            ),
            child: Text(_distanceMessage,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton(
              onPressed: _centerOnDriver,
              tooltip: 'Center on Driver',
              child: const Icon(Icons.my_location),
            ),
          ),
        ),
      ],
    );
  }
}

// --- LiveMapScreen ---
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});
  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  late StreamSubscription<QuerySnapshot> _driversSubscription;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  List<_DriverInfo> _allDrivers = [];
  BitmapDescriptor? _tramIcon;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(18.7941, 98.9526),
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    _loadTramIcon();
    _subscribeToAllDrivers();
  }

  @override
  void dispose() {
    _driversSubscription.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadTramIcon() async {
    try {
      final icon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/images/tram_icon.png',
      );
      if (mounted) setState(() => _tramIcon = icon);
    } catch (e) {
      print("Error loading tram icon for LiveMapScreen: $e");
    }
  }

  void _subscribeToAllDrivers() {
    final driversQuery = FirebaseFirestore.instance.collection('drivers');
    _driversSubscription = driversQuery.snapshots().listen((snapshot) {
      if (mounted) _updateMarkersAndDriverList(snapshot.docs);
    });
  }

  void _updateMarkersAndDriverList(List<QueryDocumentSnapshot> driverDocs) {
    final Set<Marker> updatedMarkers = {};
    final List<_DriverInfo> updatedDrivers = [];

    for (var doc in driverDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final location = data['currentLocation'] as GeoPoint?;
      final status = data['status'] as String? ?? 'offline';

      LatLng position = const LatLng(0, 0);
      if (location != null) {
        position = LatLng(location.latitude, location.longitude);
      }

      if (status == 'online' && location != null) {
        updatedMarkers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: position,
            icon: _tramIcon ?? BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(title: data['displayName'] ?? 'คนขับ'),
            anchor: const Offset(0.5, 0.5),
            flat: true,
          ),
        );
      }

      updatedDrivers.add(_DriverInfo(
        id: doc.id,
        name: data['displayName'] ?? 'คนขับ',
        position: position,
        status: status,
      ));
    }

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(updatedMarkers);
        _allDrivers = updatedDrivers;
      });
    }
  }

  void _goToDriver(LatLng position) {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 17));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แผนที่รถราง (Real-time)')),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              markers: _markers,
              onMapCreated: (controller) => _mapController = controller,
            ),
          ),
          Container(
            height: 80,
            color: Colors.white,
            child: _allDrivers.isEmpty
                ? const Center(child: Text('ไม่พบข้อมูลคนขับในระบบ'))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _allDrivers.length,
                    itemBuilder: (context, index) {
                      final driver = _allDrivers[index];
                      final bool isOnline = driver.status == 'online';

                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton.icon(
                          icon: Icon(
                            Icons.directions_bus,
                            color: isOnline ? Colors.white : Colors.grey,
                          ),
                          label: Text(
                            driver.name,
                            style: TextStyle(
                              color: isOnline ? Colors.white : Colors.grey,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isOnline
                                ? Theme.of(context).primaryColor
                                : Colors.grey[300],
                            disabledBackgroundColor: Colors.grey[300],
                          ),
                          onPressed: isOnline
                              ? () => _goToDriver(driver.position)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
