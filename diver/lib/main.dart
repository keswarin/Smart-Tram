// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'firebase_options.dart';

// URL ของ API ที่คุณได้มาจากการ Deploy
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
      theme: ThemeData(primarySwatch: Colors.green),
      home: const RequestScreen(),
    );
  }
}

// --- หน้าจอเรียกรถ (Request Screen - เพิ่มโลโก้) ---
class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});
  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  List<Building> _buildings = [];
  Building? _selectedPickup;
  Building? _selectedDropoff;
  int _passengerCount = 1;
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
          'passengerCount': _passengerCount,
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
      _passengerCount = 1;
      _statusMessage = '';
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request a Ride'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoading
              ? const CircularProgressIndicator()
              : SingleChildScrollView( // <<< เพิ่มเพื่อให้เลื่อนได้ถ้าจอล้น
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- 🎯 Widget ใหม่: แสดงโลโก้ ---
                      Image.asset(
                        'assets/images/logo.png',
                        height: 600, // <<< กำหนดความสูงของโลโก้
                      ),
                      const SizedBox(height: 20),
                      // ------------------------------------

                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.green),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'เวลาให้บริการ',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                            ),
                            SizedBox(height: 4),
                            Text('เช้า: 07.00–09.00 น.'),
                            Text('เที่ยง: 11.00–13.00 น.'),
                            Text('เย็น: 15.00–17.45 น.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<Building>(
                        value: _selectedPickup,
                        hint: const Text('Select Pickup Location'),
                        items: _buildings.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
                        onChanged: (val) => setState(() => _selectedPickup = val),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<Building>(
                        value: _selectedDropoff,
                        hint: const Text('Select Drop-off Location'),
                        items: _buildings.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
                        onChanged: (val) => setState(() => _selectedDropoff = val),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<int>(
                        value: _passengerCount,
                        decoration: const InputDecoration(labelText: 'Passengers'),
                        items: List.generate(10, (index) => index + 1)
                            .map((count) => DropdownMenuItem(
                                  value: count,
                                  child: Text('$count person(s)'),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _passengerCount = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: _submitRequest,
                        child: const Text('Confirm Request', style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.map),
                        label: const Text('View Live Map'),
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const LiveMapScreen(),
                          ));
                        },
                      ),
                      if (_statusMessage.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(_statusMessage, textAlign: TextAlign.center),
                      ),
                    ],
                  ),
              ),
        ),
      ),
    );
  }
}

// --- ส่วนที่เหลือของไฟล์ (TrackingScreen, LiveMapScreen, etc.) เหมือนเดิมทุกประการ ---
class TrackingScreen extends StatefulWidget {
  final String requestId;
  const TrackingScreen({super.key, required this.requestId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Stream<DocumentSnapshot>? _requestStream;

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
          final rideRequest = RideRequest(
            id: snapshot.data!.id,
            status: data['status'],
            driverId: data['driverId'],
            pickupPointId: data['pickupPointId'],
          );

          switch (rideRequest.status) {
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
              return DriverTrackingMap(
                driverId: rideRequest.driverId!,
                requestId: rideRequest.id,
              );
            case 'completed':
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 80),
                    const SizedBox(height: 20),
                    const Text('Trip Completed!', style: TextStyle(fontSize: 24)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    )
                  ],
                ),
              );
            default:
              return Center(child: Text('Unknown status: ${rideRequest.status}'));
          }
        },
      ),
    );
  }
}

class DriverTrackingMap extends StatefulWidget {
  final String driverId;
  final String requestId;
  const DriverTrackingMap({super.key, required this.driverId, required this.requestId});

  @override
  State<DriverTrackingMap> createState() => _DriverTrackingMapState();
}

class _DriverTrackingMapState extends State<DriverTrackingMap> {
  late StreamSubscription<DocumentSnapshot> _driverSubscription;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  BitmapDescriptor? _tramIcon;
  String _distanceMessage = 'Calculating distance...';
  LatLng? _driverPosition;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(18.9039, 98.9216),
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    _loadTramIcon();
    _subscribeToDriverLocation();
  }

  @override
  void dispose() {
    _driverSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadTramIcon() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/tram_icon.png',
    );
    if (mounted) setState(() => _tramIcon = icon);
  }

  void _subscribeToDriverLocation() {
    final driverRef = FirebaseFirestore.instance.collection('drivers').doc(widget.driverId);
    _driverSubscription = driverRef.snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        final location = data['currentLocation'] as GeoPoint?;
        if (location != null) {
          _driverPosition = LatLng(location.latitude, location.longitude);
          _updateMarkerAndDistance(location);
        }
      }
    });
  }

  Future<void> _updateMarkerAndDistance(GeoPoint driverLocationGeo) async {
    final driverLatLng = LatLng(driverLocationGeo.latitude, driverLocationGeo.longitude);

    final requestDoc = await FirebaseFirestore.instance.collection('ride_requests').doc(widget.requestId).get();
    if (!requestDoc.exists) return;

    final requestData = requestDoc.data()!;
    final pickupPointId = requestData['pickupPointId'];
    final pickupDoc = await FirebaseFirestore.instance.collection('pickup_points').doc(pickupPointId).get();
    if (!pickupDoc.exists) return;

    final pickupLocationGeo = pickupDoc.data()!['coordinates'] as GeoPoint;
    final pickupLatLng = LatLng(pickupLocationGeo.latitude, pickupLocationGeo.longitude);

    final distanceInMeters = Geolocator.distanceBetween(
      driverLatLng.latitude, driverLatLng.longitude,
      pickupLatLng.latitude, pickupLatLng.longitude,
    );
    final distanceInKm = distanceInMeters / 1000;

    final driverMarker = Marker(
      markerId: const MarkerId('driver'),
      position: driverLatLng,
      icon: _tramIcon ?? BitmapDescriptor.defaultMarker,
      anchor: const Offset(0.5, 0.5),
      flat: true,
    );

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.add(driverMarker);
        _distanceMessage = 'Driver will arrive in ${distanceInKm.toStringAsFixed(2)} km';
      });
    }
  }
  
  void _centerOnDriver() {
    if (_driverPosition != null && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_driverPosition!));
    }
  }

  @override
  Widget build(BuildContext context) {
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
                BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
              ],
            ),
            child: Text(
              _distanceMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
    target: LatLng(18.9039, 98.9216),
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
    super.dispose();
  }

  Future<void> _loadTramIcon() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/tram_icon.png',
    );
    if (mounted) {
      setState(() {
        _tramIcon = icon;
      });
    }
  }

  void _subscribeToAllDrivers() {
    final driversQuery = FirebaseFirestore.instance
        .collection('drivers')
        .where('isOnline', isEqualTo: true);

    _driversSubscription = driversQuery.snapshots().listen((snapshot) {
      if (mounted) {
        _updateMarkersAndDriverList(snapshot.docs);
      }
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

        updatedDrivers.add(
          Driver(id: doc.id, name: data['displayName'] ?? 'Driver', position: position)
        );
      }
    }
    setState(() {
      _markers.clear();
      _markers.addAll(updatedMarkers);
      _onlineDrivers = updatedDrivers;
    });
  }

  void _goToDriver(LatLng position) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 17),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tram Map'),
      ),
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
