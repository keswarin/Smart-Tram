// lib/main.dart (ฉบับสมบูรณ์ล่าสุด)

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

class RideRequest {
  final String id;
  final String status;
  final String? driverId;
  final String pickupPointId;

  RideRequest(
      {required this.id,
      required this.status,
      this.driverId,
      required this.pickupPointId});
}

class Driver {
  final String id;
  final String name;
  final LatLng position;

  Driver({required this.id, required this.name, required this.position});
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
      title: 'Smart Tram Request',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.grey[200],
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
  // --- State สำหรับฟอร์มเรียกรถ ---
  List<Building> _buildings = [];
  Building? _selectedPickup;
  Building? _selectedDropoff;
  final int _passengerCount = 1;
  bool _isLoading = true;
  String _statusMessage = '';

  // --- State สำหรับการติดตาม (Tracking) ---
  String? _currentRequestId;
  StreamSubscription<DocumentSnapshot>? _driverSubscription;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  BitmapDescriptor? _tramIcon;
  String _distanceMessage = 'Calculating distance...';
  LatLng? _driverPosition;
  String? _currentlyTrackedDriverId;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(13.7658086, 100.564992),
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
        const SnackBar(content: Text('Please select both locations.')),
      );
      return;
    }
    if (_selectedPickup!.id == _selectedDropoff!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Locations cannot be the same.')),
      );
      return;
    }
    setState(() => _isLoading = true);
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
        setState(() {
          _statusMessage = 'Failed to submit request.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _clearForm() {
    setState(() {
      _selectedPickup = null;
      _selectedDropoff = null;
      _statusMessage = '';
    });
  }

  void _subscribeToDriverLocation(String driverId, String requestId) {
    if (_currentlyTrackedDriverId == driverId) return;

    _driverSubscription?.cancel();
    _currentlyTrackedDriverId = driverId;

    final driverRef =
        FirebaseFirestore.instance.collection('drivers').doc(driverId);
    _driverSubscription = driverRef.snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        final location = data['currentLocation'] as GeoPoint?;
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

    final distanceInMeters = Geolocator.distanceBetween(
      driverLatLng.latitude,
      driverLatLng.longitude,
      pickupLatLng.latitude,
      pickupLatLng.longitude,
    );
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
      infoWindow: const InfoWindow(title: 'Pick-up Point'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    );

    setState(() {
      _driverPosition = driverLatLng;
      _markers.clear();
      _markers.add(driverMarker);
      _markers.add(pickupMarker);
      _distanceMessage =
          'Driver will arrive in ${distanceInKm.toStringAsFixed(2)} km';
    });

    _mapController?.animateCamera(CameraUpdate.newLatLng(driverLatLng));
  }

  void _centerOnDriver() {
    if (_driverPosition != null && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_driverPosition!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentRequestId == null ? 'Smart Tram' : 'Tracking Ride'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_currentRequestId == null) {
      return _buildRequestForm();
    }
    return _buildTrackingView();
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
                  Image.asset(
                    'assets/images/logo.png',
                    height: 100,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Request a Ride',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  _buildDropdown(
                    hint: 'Pick-up',
                    value: _selectedPickup,
                    onChanged: (val) => setState(() => _selectedPickup = val),
                  ),
                  const SizedBox(height: 16),
                  _buildDropdown(
                    hint: 'Drop-off',
                    value: _selectedDropoff,
                    onChanged: (val) => setState(() => _selectedDropoff = val),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    onPressed: _submitRequest,
                    child: const Text('Find Driver',
                        style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => const LiveMapScreen()));
                    },
                    child: const Text('View Map',
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

  Widget _buildDropdown({
    required String hint,
    required Building? value,
    required ValueChanged<Building?> onChanged,
  }) {
    return DropdownButtonFormField<Building>(
      value: value,
      decoration: InputDecoration(
        labelText: hint,
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
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            timeRange,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.black54,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
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
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Waiting for request details...'));
        }
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final status = data['status'] ?? 'unknown';
        final driverId = data['driverId'] as String?;

        switch (status) {
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
            if (driverId != null) {
              _subscribeToDriverLocation(driverId, _currentRequestId!);
              return _buildDriverTrackingMap();
            }
            return const Center(
                child: Text('Driver assigned, but ID is missing.'));
          case 'completed':
            _driverSubscription?.cancel();
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 80),
                  const SizedBox(height: 20),
                  const Text('Trip Completed!', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _currentRequestId = null;
                      _markers.clear();
                      _currentlyTrackedDriverId = null;
                    }),
                    child: const Text('Done'),
                  )
                ],
              ),
            );
          default:
            return Center(child: Text('Unknown status: $status'));
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

// --- LiveMapScreen (เหมือนเดิมทุกประการ) ---
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  late StreamSubscription<QuerySnapshot> _driversSubscription;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  List<Driver> _onlineDrivers = [];
  BitmapDescriptor? _tramIcon;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(13.7658086, 100.564992),
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
    final driversQuery = FirebaseFirestore.instance
        .collection('drivers')
        .where('status', isEqualTo: 'online');
    _driversSubscription = driversQuery.snapshots().listen((snapshot) {
      if (mounted) _updateMarkersAndDriverList(snapshot.docs);
    });
  }

  void _updateMarkersAndDriverList(List<QueryDocumentSnapshot> driverDocs) {
    final Set<Marker> updatedMarkers = {};
    final List<Driver> updatedDrivers = [];
    for (var doc in driverDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final location = data['currentLocation'] as GeoPoint?;
      if (location != null) {
        final position = LatLng(location.latitude, location.longitude);
        updatedMarkers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: position,
            icon: _tramIcon ?? BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(title: data['displayName'] ?? 'Driver'),
            anchor: const Offset(0.5, 0.5),
            flat: true,
          ),
        );
        updatedDrivers.add(Driver(
            id: doc.id,
            name: data['displayName'] ?? 'Driver',
            position: position));
      }
    }
    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(updatedMarkers);
        _onlineDrivers = updatedDrivers;
      });
    }
  }

  void _goToDriver(LatLng position) {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 17));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Tram Map')),
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
            child: _onlineDrivers.isEmpty
                ? const Center(child: Text('No drivers online.'))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _onlineDrivers.length,
                    itemBuilder: (context, index) {
                      final driver = _onlineDrivers[index];
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.directions_bus),
                          label: Text(driver.name),
                          onPressed: () => _goToDriver(driver.position),
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
