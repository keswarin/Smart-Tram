import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'login_screen.dart';

// --- PickupPoint Model ---
class PickupPoint {
  final String id;
  final String name;
  final LatLng coordinates;

  PickupPoint(
      {required this.id, required this.name, required this.coordinates});

  factory PickupPoint.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    GeoPoint geoPoint = data['coordinates'] is GeoPoint
        ? data['coordinates'] as GeoPoint
        : const GeoPoint(0, 0);
    return PickupPoint(
      id: doc.id,
      name: data['name'] as String? ?? 'Unknown Point',
      coordinates: LatLng(geoPoint.latitude, geoPoint.longitude),
    );
  }
}

class UserMapScreen extends StatefulWidget {
  const UserMapScreen({Key? key}) : super(key: key);

  @override
  State<UserMapScreen> createState() => _UserMapScreenState();
}

class _UserMapScreenState extends State<UserMapScreen> {
  final Completer<GoogleMapController> _controllerCompleter =
      Completer<GoogleMapController>();
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};

  StreamSubscription? _onlineDriversSubscription;
  final Set<Marker> _onlineDriverMarkers = {};

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(19.025, 98.935), // พิกัด มร.ชม. ศูนย์แม่ริม
    zoom: 15.5,
  );

  List<PickupPoint> _pickupPointsList = [];
  bool _isLoadingPickupPoints = true;
  String? _userId;
  final TextEditingController _userNotesController = TextEditingController();
  String? _activeRequestId;
  StreamSubscription? _activeJobSubscription;
  StreamSubscription? _assignedDriverLocationSubscription;
  Map<String, dynamic>? _activeJobData;
  String? _currentJobStatus;
  bool _isJobActive = false;
  String? _jobStatusMessage;
  String? _activeJobPickupName;
  String? _activeJobDropoffName;
  LatLng? _activeJobPickupLatLng;
  LatLng? _activeJobDropoffLatLng;
  String? _assignedDriverId;
  String? _assignedDriverIdPreviousCheck;
  LatLng? _assignedDriverLocation; // <-- ตัวแปรสำหรับเก็บตำแหน่งคนขับ
  double _assignedDriverHeading = 0.0; // <-- ตัวแปรสำหรับเก็บทิศทางคนขับ
  bool _isCancellingRequest = false;
  Timer? _cancellationTimer;
  DateTime? _requestSubmissionClientTime;
  bool _canCancelForFree = false;
  String? _etaToPickupDisplay;
  String? _driverIssueMessageReceived;
  Timestamp? _driverIssueTimestampReceived;
  Set<Polyline> _previewPolylinesInDialog = {};
  Set<Polyline> _driverToPickupPolylines = {};
  Set<Polyline> _tripPolylines = {};
  final String _proxyBaseUrl = 'http://localhost:5550';

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _fetchPickupPoints();
    if (_userId != null) {
      _checkForExistingActiveJobUser();
      _listenToOnlineDrivers();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _logoutUser(showSnackbar: true, message: "กรุณาเข้าสู่ระบบเพื่อใช้งาน");
      });
    }
  }

  @override
  void dispose() {
    _activeJobSubscription?.cancel();
    _assignedDriverLocationSubscription?.cancel();
    _onlineDriversSubscription?.cancel();
    _cancellationTimer?.cancel();
    _mapController?.dispose();
    _userNotesController.dispose();
    super.dispose();
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  void _listenToOnlineDrivers() {
    if (!mounted) return;
    _onlineDriversSubscription?.cancel();

    final driversQuery = FirebaseFirestore.instance
        .collection('drivers')
        .where('isOnline', isEqualTo: true);

    _onlineDriversSubscription = driversQuery.snapshots().listen((snapshot) {
      if (!mounted) return;

      final Set<Marker> newMarkers = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final driverId = doc.id;

        if (driverId == _assignedDriverId) {
          continue;
        }

        final GeoPoint? location = data['currentLocation'] as GeoPoint?;
        if (location != null) {
          final latLng = LatLng(location.latitude, location.longitude);
          final heading = (data['heading'] as num?)?.toDouble() ?? 0.0;

          final marker = Marker(
            markerId: MarkerId('driver_$driverId'),
            position: latLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            rotation: heading,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            zIndex: 1,
          );
          newMarkers.add(marker);
        }
      }

      setStateIfMounted(() {
        _onlineDriverMarkers.clear();
        _onlineDriverMarkers.addAll(newMarkers);
      });
    }, onError: (error) {
      print("Error listening to online drivers: $error");
    });
  }

  Future<void> _fetchPickupPoints() async {
    if (!mounted) return;
    setStateIfMounted(() => _isLoadingPickupPoints = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pickup_points')
          .where('isActive', isEqualTo: true)
          .orderBy('name')
          .get();
      if (!mounted) return;
      final points =
          snapshot.docs.map((doc) => PickupPoint.fromFirestore(doc)).toList();
      setStateIfMounted(() {
        _pickupPointsList = points;
        _isLoadingPickupPoints = false;
      });
    } catch (e) {
      if (!mounted) return;
      print("Error fetching pickup points: $e");
      setStateIfMounted(() => _isLoadingPickupPoints = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถโหลดจุดรับ-ส่งได้: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _checkForExistingActiveJobUser() async {
    if (_userId == null || !mounted) return;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('userId', isEqualTo: _userId)
          .where('status', whereNotIn: [
            'completed',
            'cancelled_by_user',
            'cancelled_by_driver',
            'cancelled_by_system',
            'driver_issue_resolved'
          ])
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty && mounted) {
        final activeJobDoc = querySnapshot.docs.first;
        final data = activeJobDoc.data();

        setStateIfMounted(() {
          _activeRequestId = activeJobDoc.id;
          _activeJobData = data;
          _isJobActive = true;
          _currentJobStatus = data['status'] as String?;
          _activeJobPickupName = data['pickupPointName'] as String?;
          _activeJobDropoffName = data['dropoffPointName'] as String?;
          _assignedDriverId = data['driverId'] as String?;
          _assignedDriverIdPreviousCheck = _assignedDriverId;

          final GeoPoint? pickupGP = data['pickupLatLng'] as GeoPoint?;
          if (pickupGP != null)
            _activeJobPickupLatLng =
                LatLng(pickupGP.latitude, pickupGP.longitude);

          final GeoPoint? dropoffGP = data['dropoffLatLng'] as GeoPoint?;
          if (dropoffGP != null)
            _activeJobDropoffLatLng =
                LatLng(dropoffGP.latitude, dropoffGP.longitude);

          _driverIssueMessageReceived = null;
          _driverIssueTimestampReceived = null;

          final Timestamp? createdAtTimestamp = data['createdAt'] as Timestamp?;
          if (createdAtTimestamp != null) {
            _requestSubmissionClientTime = createdAtTimestamp.toDate();
            DateTime gracePeriodEnd =
                _requestSubmissionClientTime!.add(const Duration(seconds: 3));
            if (DateTime.now().isBefore(gracePeriodEnd) &&
                (_currentJobStatus == 'requested' ||
                    _currentJobStatus == 'driver_assigned')) {
              _canCancelForFree = true;
              _startCancellationTimer(
                  remainingDuration: gracePeriodEnd.difference(DateTime.now()));
            } else {
              _canCancelForFree = false;
            }
          } else {
            _canCancelForFree = false;
          }
          _updateJobDisplayInfo();
        });
        _startListeningToActiveJob(_activeRequestId!);
        if (_assignedDriverId != null) {
          _listenToAssignedDriverLocation(_assignedDriverId!);
        }
      } else {
        if (mounted) setStateIfMounted(() => _isJobActive = false);
      }
    } catch (e) {
      print("Error checking for user's active job: $e");
      if (mounted) setStateIfMounted(() => _isJobActive = false);
    }
  }

  void _startListeningToActiveJob(String requestId) {
    if (!mounted) return;
    _activeJobSubscription?.cancel();
    _activeJobSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(requestId)
        .snapshots()
        .listen((DocumentSnapshot snapshot) {
      if (!mounted) {
        _activeJobSubscription?.cancel();
        return;
      }
      if (!snapshot.exists) {
        if (_isJobActive) {
          _resetActiveJobState(
              message: "ไม่พบข้อมูลงานปัจจุบัน", showSnackbar: true);
        }
        return;
      }
      final data = snapshot.data() as Map<String, dynamic>;
      final newStatusFromServer = data['status'] as String?;

      setStateIfMounted(() {
        _activeJobData = data;
        _currentJobStatus = newStatusFromServer;
        _assignedDriverId = data['driverId'] as String?;

        final GeoPoint? pickupGP = data['pickupLatLng'] as GeoPoint?;
        if (pickupGP != null)
          _activeJobPickupLatLng =
              LatLng(pickupGP.latitude, pickupGP.longitude);

        final GeoPoint? dropoffGP = data['dropoffLatLng'] as GeoPoint?;
        if (dropoffGP != null)
          _activeJobDropoffLatLng =
              LatLng(dropoffGP.latitude, dropoffGP.longitude);

        final newIssueMsg = data['driverIssueMessage'] as String?;
        final newIssueTs = data['driverIssueTimestamp'] as Timestamp?;

        if (newStatusFromServer == 'completed' ||
            (newStatusFromServer ?? '').startsWith('cancelled') ||
            newStatusFromServer == 'driver_issue_resolved') {
          _driverIssueMessageReceived = null;
          _driverIssueTimestampReceived = null;
        } else if (newIssueMsg != null && newIssueMsg.isNotEmpty) {
          if (_driverIssueTimestampReceived == null ||
              (newIssueTs != null &&
                  newIssueTs.compareTo(_driverIssueTimestampReceived!) > 0)) {
            _driverIssueMessageReceived = newIssueMsg;
            _driverIssueTimestampReceived = newIssueTs;
            if (newStatusFromServer == 'driver_issue' &&
                mounted &&
                ModalRoute.of(context)!.isCurrent) {
              _showDriverIssueAlert(newIssueMsg);
            }
          }
        } else {
          _driverIssueMessageReceived = null;
          _driverIssueTimestampReceived = null;
        }
        _updateJobDisplayInfo();
      });

      if (_assignedDriverId != null &&
          _assignedDriverId != _assignedDriverIdPreviousCheck) {
        _listenToAssignedDriverLocation(_assignedDriverId!);
        _updateEtaToPickupDisplay();
      } else if (_assignedDriverId == null &&
          _assignedDriverIdPreviousCheck != null) {
        _assignedDriverLocationSubscription?.cancel();
        _assignedDriverLocationSubscription = null;
        if (mounted) {
          setStateIfMounted(() => _markers.removeWhere(
              (m) => m.markerId.value == 'assigned_driver_marker'));
        }
        setStateIfMounted(() => _etaToPickupDisplay = null);
      }
      _assignedDriverIdPreviousCheck = _assignedDriverId;

      if (newStatusFromServer == 'completed' ||
          newStatusFromServer == 'cancelled_by_driver' ||
          newStatusFromServer == 'cancelled_by_system' ||
          newStatusFromServer == 'cancelled_by_user' ||
          newStatusFromServer == 'driver_issue_resolved') {
        _showCompletionOrCancellationDialogAndReset(newStatusFromServer!);
      }
    }, onError: (error) {
      if (_isJobActive && mounted) {
        _resetActiveJobState(
            message: "เกิดข้อผิดพลาดในการติดตามงาน", showSnackbar: true);
      }
    });
  }

  void _listenToAssignedDriverLocation(String driverId) {
    if (!mounted) return;
    _assignedDriverLocationSubscription?.cancel();
    _assignedDriverLocationSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .listen((DocumentSnapshot snapshot) {
      if (!mounted ||
          !snapshot.exists ||
          !_isJobActive ||
          _assignedDriverId != driverId) {
        _assignedDriverLocationSubscription?.cancel();
        _assignedDriverLocationSubscription = null;
        if (mounted) {
          setStateIfMounted(() => _markers.removeWhere(
              (m) => m.markerId.value == 'assigned_driver_marker'));
        }
        return;
      }
      final data = snapshot.data() as Map<String, dynamic>;
      final GeoPoint? driverGeoPoint = data['currentLocation'] as GeoPoint?;
      final num? headingNum = data['heading'] as num?;

      if (driverGeoPoint != null) {
        final newLocation =
            LatLng(driverGeoPoint.latitude, driverGeoPoint.longitude);
        if (mounted) {
          // --- VVVVVV แก้ไขจุดที่พิมพ์ผิด VVVVVV ---
          bool locationOrHeadingChanged = _assignedDriverLocation == null ||
              _assignedDriverLocation!.latitude != newLocation.latitude ||
              _assignedDriverLocation!.longitude != newLocation.longitude ||
              _assignedDriverHeading !=
                  (headingNum?.toDouble() ?? _assignedDriverHeading);
          // --- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ---
          if (locationOrHeadingChanged) {
            setStateIfMounted(() {
              _assignedDriverLocation = newLocation;
              _assignedDriverHeading =
                  headingNum?.toDouble() ?? _assignedDriverHeading;
              _updateDriverMarker();
              if ((_currentJobStatus == 'en_route_to_pickup' ||
                  _currentJobStatus == 'driver_assigned')) {
                _drawDriverToPickupRoute();
                _updateEtaToPickupDisplay();
              }
            });
          }
        }
      }
    }, onError: (error) {
      print("Error listening to driver $driverId location: $error");
    });
  }

  void _updateDriverMarker() {
    if (!mounted) return;
    if (_assignedDriverLocation != null && _isJobActive) {
      final Marker driverMarker = Marker(
        markerId: const MarkerId('assigned_driver_marker'),
        position: _assignedDriverLocation!,
        rotation: _assignedDriverHeading,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        infoWindow: const InfoWindow(title: 'คนขับของคุณ'),
        zIndex: 2,
      );
      setStateIfMounted(() => _markers.add(driverMarker));
    } else {
      setStateIfMounted(() => _markers
          .removeWhere((m) => m.markerId.value == 'assigned_driver_marker'));
    }
  }

  void _updateJobDisplayInfo() {
    if (!mounted || !_isJobActive || _activeJobData == null) {
      setStateIfMounted(() {
        _jobStatusMessage = " ";
        _etaToPickupDisplay = null;
      });
      return;
    }
    final status = _activeJobData!['status'] as String?;
    String tempJobStatusMessage = "สถานะ: ${status ?? 'ไม่ทราบ'}";

    switch (status) {
      case 'requested':
        tempJobStatusMessage = "กำลังค้นหาคนขับ...";
        _etaToPickupDisplay = null;
        if (mounted) setStateIfMounted(() => _driverToPickupPolylines.clear());
        break;
      case 'driver_assigned':
        tempJobStatusMessage = "คนขับรับงานแล้ว";
        _updateEtaToPickupDisplay();
        _drawDriverToPickupRoute();
        break;
      case 'en_route_to_pickup':
        tempJobStatusMessage = "คนขับกำลังเดินทางมารับ";
        _updateEtaToPickupDisplay();
        _drawDriverToPickupRoute();
        break;
      case 'arrived_pickup':
        tempJobStatusMessage = "คนขับถึงจุดรับแล้ว";
        _etaToPickupDisplay = "คนขับถึงแล้ว!";
        if (mounted) setStateIfMounted(() => _driverToPickupPolylines.clear());
        break;
      case 'on_trip':
        tempJobStatusMessage = "กำลังเดินทางไปยังจุดหมาย";
        _etaToPickupDisplay = null;
        if (mounted) setStateIfMounted(() => _driverToPickupPolylines.clear());
        _drawPickupToDropoffRoute();
        break;
      case 'completed':
      case 'driver_issue_resolved':
        tempJobStatusMessage = status == 'completed'
            ? "การเดินทางเสร็จสิ้น"
            : "ปัญหาได้รับการแก้ไข";
        _etaToPickupDisplay = null;
        if (mounted)
          setStateIfMounted(() {
            _driverToPickupPolylines.clear();
            _tripPolylines.clear();
          });
        break;
      case 'cancelled_by_user':
      case 'cancelled_by_driver':
      case 'cancelled_by_system':
        tempJobStatusMessage = "การเดินทางถูกยกเลิก";
        _etaToPickupDisplay = null;
        if (mounted)
          setStateIfMounted(() {
            _driverToPickupPolylines.clear();
            _tripPolylines.clear();
          });
        break;
      case 'driver_issue':
        tempJobStatusMessage = "คนขับแจ้งปัญหา!";
        break;
      default:
        tempJobStatusMessage = "สถานะ: ${status ?? 'ไม่ทราบ'}";
    }
    setStateIfMounted(() => _jobStatusMessage = tempJobStatusMessage);
  }

  Future<void> _updateEtaToPickupDisplay() async {
    if (!mounted ||
        !_isJobActive ||
        _assignedDriverLocation == null ||
        _activeJobPickupLatLng == null ||
        _currentJobStatus == 'on_trip' ||
        _currentJobStatus == 'completed' ||
        (_currentJobStatus ?? '').startsWith('cancelled')) {
      setStateIfMounted(() => _etaToPickupDisplay = null);
      return;
    }

    final Timestamp? etaFromFirestore =
        _activeJobData?['estimatedDriverArrivalTimeToPickup'] as Timestamp?;
    if (etaFromFirestore != null) {
      final etaDateTime = etaFromFirestore.toDate().toLocal();
      final now = DateTime.now();
      if (etaDateTime.isAfter(now)) {
        final diff = etaDateTime.difference(now);
        String etaText = "รถจะถึงประมาณ ";
        if (diff.inHours > 0) etaText += "${diff.inHours} ชม. ";
        etaText += "${diff.inMinutes.remainder(60)} นาที";
        setStateIfMounted(() => _etaToPickupDisplay = etaText);
      } else {
        setStateIfMounted(() => _etaToPickupDisplay = "คนขับควรจะถึงแล้ว");
      }
      return;
    }

    final String originParam =
        '${_assignedDriverLocation!.latitude},${_assignedDriverLocation!.longitude}';
    final String destinationParam =
        '${_activeJobPickupLatLng!.latitude},${_activeJobPickupLatLng!.longitude}';
    final String backendUrl =
        '$_proxyBaseUrl/api/directions?origin=$originParam&destination=$destinationParam';

    try {
      setStateIfMounted(() => _etaToPickupDisplay = "กำลังคำนวณ ETA...");
      final response = await http
          .get(Uri.parse(backendUrl))
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData['status'] == 'OK' &&
            (responseData['routes'] as List).isNotEmpty) {
          final durationText = responseData['routes'][0]['legs'][0]['duration']
              ['text'] as String;
          setStateIfMounted(
              () => _etaToPickupDisplay = 'รถจะถึงภายใน $durationText');
        } else {
          setStateIfMounted(() => _etaToPickupDisplay = 'คำนวณ ETA ไม่ได้');
        }
      } else {
        setStateIfMounted(
            () => _etaToPickupDisplay = 'คำนวณ ETA ไม่ได้ (Srv Err)');
      }
    } catch (e) {
      if (mounted) {
        setStateIfMounted(
            () => _etaToPickupDisplay = 'คำนวณ ETA ไม่ได้ (Net Err)');
      }
    }
  }

  Future<void> _drawPolyline(
    LatLng origin,
    LatLng destination,
    PolylineId polylineId,
    Color color,
    Set<Polyline> targetSet, {
    bool animate = true,
  }) async {
    if (!mounted) return;
    if (_proxyBaseUrl.isEmpty) return;

    final String originParam = '${origin.latitude},${origin.longitude}';
    final String destinationParam =
        '${destination.latitude},${destination.longitude}';
    final String backendUrl =
        '$_proxyBaseUrl/api/directions?origin=$originParam&destination=$destinationParam';

    List<LatLng> polylineCoordinates = [];

    try {
      final response = await http
          .get(Uri.parse(backendUrl))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData['status'] == 'OK' &&
            (responseData['routes'] as List).isNotEmpty) {
          String encodedPolyline = responseData['routes'][0]
              ['overview_polyline']['points'] as String;
          if (encodedPolyline.isNotEmpty) {
            List<PointLatLng> decodedPoints =
                PolylinePoints().decodePolyline(encodedPolyline);
            if (decodedPoints.isNotEmpty) {
              polylineCoordinates = decodedPoints
                  .map((point) => LatLng(point.latitude, point.longitude))
                  .toList();
            }
          }
        }
      }
    } catch (e) {
      print('Error getting encoded polyline for $polylineId: $e');
    }

    if (!mounted) return;
    setStateIfMounted(() {
      targetSet.removeWhere((p) => p.polylineId == polylineId);
      if (polylineCoordinates.isNotEmpty) {
        final Polyline routePolyline = Polyline(
            polylineId: polylineId,
            color: color,
            width: 5,
            points: polylineCoordinates);
        targetSet.add(routePolyline);

        if (animate &&
            _mapController != null &&
            polylineCoordinates.length >= 2) {
          try {
            LatLngBounds bounds =
                _calculateBounds([origin, destination, ...polylineCoordinates]);
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && _mapController != null) {
                _mapController!
                    .animateCamera(CameraUpdate.newLatLngBounds(bounds, 80.0));
              }
            });
          } catch (e) {
            print("Error animating camera to bounds for $polylineId: $e");
          }
        }
      }
    });
  }

  Future<void> _drawDriverToPickupRoute() async {
    if (_assignedDriverLocation != null &&
        _activeJobPickupLatLng != null &&
        _currentJobStatus != 'on_trip') {
      await _drawPolyline(
          _assignedDriverLocation!,
          _activeJobPickupLatLng!,
          const PolylineId('driver_to_pickup_route'),
          Colors.blueAccent.withOpacity(0.7),
          _driverToPickupPolylines);
    } else {
      if (mounted) setStateIfMounted(() => _driverToPickupPolylines.clear());
    }
  }

  Future<void> _drawPickupToDropoffRoute() async {
    if (_activeJobPickupLatLng != null &&
        _activeJobDropoffLatLng != null &&
        _currentJobStatus == 'on_trip') {
      await _drawPolyline(
          _activeJobPickupLatLng!,
          _activeJobDropoffLatLng!,
          const PolylineId('pickup_to_dropoff_route'),
          Colors.purpleAccent.withOpacity(0.7),
          _tripPolylines);
    } else {
      if (mounted) setStateIfMounted(() => _tripPolylines.clear());
    }
  }

  Future<void> _drawPreviewRouteInDialog(
    LatLng pickup,
    LatLng dropoff,
    StateSetter dialogSetState, {
    required Function(bool) isDrawingSetter,
  }) async {
    if (!mounted) return;
    dialogSetState(() => isDrawingSetter(true));

    if ((pickup.latitude == 0 && pickup.longitude == 0) ||
        (dropoff.latitude == 0 && dropoff.longitude == 0)) {
      dialogSetState(() {
        _previewPolylinesInDialog.clear();
        isDrawingSetter(false);
      });
      return;
    }

    Set<Polyline> localDialogPolylines = {};
    await _drawPolyline(
        pickup,
        dropoff,
        const PolylineId('dialog_preview_route_id'),
        Colors.deepOrangeAccent.withOpacity(0.8),
        localDialogPolylines,
        animate: false);

    if (mounted) {
      dialogSetState(() {
        _previewPolylinesInDialog = localDialogPolylines;
        isDrawingSetter(false);
      });
    } else {
      isDrawingSetter(false);
    }
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
          southwest: _kInitialPosition.target,
          northeast: _kInitialPosition.target);
    }
    double minLat = points.first.latitude, minLng = points.first.longitude;
    double maxLat = points.first.latitude, maxLng = points.first.longitude;
    for (var point in points) {
      minLat = min(point.latitude, minLat);
      maxLat = max(point.latitude, maxLat);
      minLng = min(point.longitude, minLng);
      maxLng = max(point.longitude, maxLng);
    }
    return LatLngBounds(
        southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  void _startCancellationTimer({Duration? remainingDuration}) {
    _cancellationTimer?.cancel();
    final duration = remainingDuration ?? const Duration(minutes: 1);

    if (!mounted) return;

    if (duration.isNegative || duration.inSeconds < 1) {
      if (mounted) setStateIfMounted(() => _canCancelForFree = false);
      return;
    }

    _cancellationTimer = Timer(duration, () {
      if (mounted && _isJobActive) {
        setStateIfMounted(() => _canCancelForFree = false);
      }
    });
  }

  Future<void> _handleCancelRideRequest() async {
    if (!_isJobActive || _activeRequestId == null || _isCancellingRequest)
      return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการยกเลิก'),
        content: Text(_canCancelForFree
            ? 'คุณต้องการยกเลิกคำขอนี้ใช่หรือไม่? (ยังอยู่ในช่วงยกเลิกฟรี)'
            : 'คุณต้องการยกเลิกคำขอนี้ใช่หรือไม่?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('ไม่')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('ใช่, ยกเลิก',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setStateIfMounted(() => _isCancellingRequest = true);
      try {
        await FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(_activeRequestId!)
            .update({
          'status': 'cancelled_by_user',
          'cancelledBy': 'user',
          'cancellationReason': _canCancelForFree
              ? 'within_grace_period_by_user'
              : 'user_cancelled_after_grace_period_or_assigned',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('เกิดข้อผิดพลาดในการยกเลิก: ${e.toString()}'),
              backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setStateIfMounted(() => _isCancellingRequest = false);
      }
    }
  }

  void _resetActiveJobState({
    String? message,
    bool showSnackbar = false,
    Color? snackbarColor,
  }) {
    if (!mounted) return;

    _activeJobSubscription?.cancel();
    _assignedDriverLocationSubscription?.cancel();
    _cancellationTimer?.cancel();

    _activeJobSubscription = null;
    _assignedDriverLocationSubscription = null;
    _cancellationTimer = null;

    setStateIfMounted(() {
      _isJobActive = false;
      _activeRequestId = null;
      _activeJobData = null;
      _currentJobStatus = null;
      _jobStatusMessage = null;
      _assignedDriverId = null;
      _assignedDriverIdPreviousCheck = null;
      _assignedDriverLocation = null;
      _markers.removeWhere((m) => m.markerId.value == 'assigned_driver_marker');
      _previewPolylinesInDialog.clear();
      _driverToPickupPolylines.clear();
      _tripPolylines.clear();
      _requestSubmissionClientTime = null;
      _canCancelForFree = false;
      _etaToPickupDisplay = null;
      _driverIssueMessageReceived = null;
      _driverIssueTimestampReceived = null;
      _activeJobPickupName = null;
      _activeJobDropoffName = null;
      _activeJobPickupLatLng = null;
      _activeJobDropoffLatLng = null;
    });

    if (showSnackbar &&
        message != null &&
        mounted &&
        ModalRoute.of(context)!.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: snackbarColor ?? Colors.grey.shade700,
          duration: const Duration(seconds: 3)));
    }
  }

  void _showCompletionOrCancellationDialogAndReset(String finalStatus) {
    if (!mounted) return;

    String title = "การแจ้งเตือน";
    String content = "สถานะงาน: $finalStatus";
    Color? dialogColor = Colors.blueGrey;

    if (finalStatus == 'completed') {
      title = "การเดินทางเสร็จสิ้น";
      content = "ขอบคุณที่ใช้บริการ!";
      dialogColor = Colors.green;
    } else if (finalStatus.startsWith('cancelled')) {
      title = "การเดินทางถูกยกเลิก";
      final reason = _activeJobData?['cancellationReason'] as String?;
      content = reason != null && reason.isNotEmpty
          ? "การเดินทางของคุณถูกยกเลิก (เหตุผล: $reason)"
          : "การเดินทางของคุณถูกยกเลิก";
      dialogColor = Colors.orange;
    } else if (finalStatus == 'driver_issue_resolved') {
      title = "ปัญหาได้รับการแก้ไข";
      content =
          "ปัญหาที่คนขับแจ้งได้รับการแก้ไขแล้ว หากการเดินทางถูกยกเลิกไปก่อนหน้านี้ คุณอาจจะต้องทำการเรียกรถใหม่อีกครั้ง";
      dialogColor = Colors.blue;
    } else {
      _resetActiveJobState(
          message: "สถานะงานมีการเปลี่ยนแปลง: $finalStatus",
          showSnackbar: true);
      return;
    }

    _resetActiveJobState();

    if (mounted && ModalRoute.of(context)!.isCurrent) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              child: Text('ตกลง', style: TextStyle(color: dialogColor)),
              onPressed: () {
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      );
    }
  }

  void _showDriverIssueAlert(String message) {
    if (!mounted || !ModalRoute.of(context)!.isCurrent) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            const Text('แจ้งเตือนจากคนขับ'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('รับทราบ'),
          ),
        ],
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!mounted) return;
    if (!_controllerCompleter.isCompleted) {
      _controllerCompleter.complete(controller);
    }
    _mapController = controller;
    _mapController
        ?.animateCamera(CameraUpdate.newCameraPosition(_kInitialPosition));
  }

  void _showRequestRideDialog() {
    if (!mounted || _isLoadingPickupPoints) return;

    String? localSelectedPickupId;
    String? localSelectedDropoffId;
    LatLng? localPreviewPickupLatLng;
    LatLng? localPreviewDropoffLatLng;
    bool localIsDrawingPreviewRoute = false;

    _userNotesController.clear();
    if (mounted) {
      setStateIfMounted(() => _previewPolylinesInDialog.clear());
    }

    final GlobalKey<FormState> dialogFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: !localIsDrawingPreviewRoute,
      builder: (BuildContext dialogContext) {
        bool isDialogRequestingRideLocal = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('เรียกรถราง'),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              content: SingleChildScrollView(
                child: Form(
                  key: dialogFormKey,
                  child: ListBody(
                    children: <Widget>[
                      if (_pickupPointsList.isEmpty)
                        const Text('ไม่พบข้อมูลจุดรับ-ส่ง',
                            style: TextStyle(color: Colors.red)),
                      if (_pickupPointsList.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: localSelectedPickupId,
                          hint: const Text('--- เลือกจุดรับ ---'),
                          isExpanded: true,
                          items: _pickupPointsList
                              .map((PickupPoint point) =>
                                  DropdownMenuItem<String>(
                                      value: point.id,
                                      child: Text(point.name,
                                          overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: isDialogRequestingRideLocal ||
                                  localIsDrawingPreviewRoute
                              ? null
                              : (String? newValue) {
                                  if (newValue == null) return;
                                  final selectedPoint = _pickupPointsList
                                      .firstWhere((p) => p.id == newValue);
                                  setDialogState(() {
                                    localSelectedPickupId = newValue;
                                    localPreviewPickupLatLng =
                                        selectedPoint.coordinates;
                                    _previewPolylinesInDialog.clear();
                                  });
                                  if (localPreviewPickupLatLng != null &&
                                      localPreviewDropoffLatLng != null) {
                                    _drawPreviewRouteInDialog(
                                        localPreviewPickupLatLng!,
                                        localPreviewDropoffLatLng!,
                                        setDialogState,
                                        isDrawingSetter: (val) =>
                                            setDialogState(() =>
                                                localIsDrawingPreviewRoute =
                                                    val));
                                  }
                                },
                          validator: (value) =>
                              value == null ? 'กรุณาเลือกจุดรับ' : null,
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: localSelectedDropoffId,
                          hint: const Text('--- เลือกจุดส่ง ---'),
                          isExpanded: true,
                          items: _pickupPointsList
                              .map((PickupPoint point) =>
                                  DropdownMenuItem<String>(
                                      value: point.id,
                                      child: Text(point.name,
                                          overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: isDialogRequestingRideLocal ||
                                  localIsDrawingPreviewRoute
                              ? null
                              : (String? newValue) {
                                  if (newValue == null) return;
                                  if (newValue == localSelectedPickupId) {
                                    ScaffoldMessenger.of(dialogContext)
                                        .showSnackBar(const SnackBar(
                                            content: Text(
                                                'จุดส่งต้องไม่ซ้ำกับจุดรับ'),
                                            backgroundColor: Colors.orange,
                                            duration: Duration(seconds: 2)));
                                    return;
                                  }
                                  final selectedPoint = _pickupPointsList
                                      .firstWhere((p) => p.id == newValue);
                                  setDialogState(() {
                                    localSelectedDropoffId = newValue;
                                    localPreviewDropoffLatLng =
                                        selectedPoint.coordinates;
                                    _previewPolylinesInDialog.clear();
                                  });
                                  if (localPreviewPickupLatLng != null &&
                                      localPreviewDropoffLatLng != null) {
                                    _drawPreviewRouteInDialog(
                                        localPreviewPickupLatLng!,
                                        localPreviewDropoffLatLng!,
                                        setDialogState,
                                        isDrawingSetter: (val) =>
                                            setDialogState(() =>
                                                localIsDrawingPreviewRoute =
                                                    val));
                                  }
                                },
                          validator: (value) {
                            if (value == null) return 'กรุณาเลือกจุดส่ง';
                            if (value == localSelectedPickupId)
                              return 'จุดส่งต้องไม่ซ้ำกับจุดรับ';
                            return null;
                          },
                        ),
                        const SizedBox(height: 15),
                        if (localPreviewPickupLatLng != null &&
                            localPreviewDropoffLatLng != null &&
                            _previewPolylinesInDialog.isNotEmpty)
                          SizedBox(
                            height: 150,
                            child: AbsorbPointer(
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                    target: localPreviewPickupLatLng ??
                                        _kInitialPosition.target,
                                    zoom: 14),
                                markers: {
                                  if (localPreviewPickupLatLng != null)
                                    Marker(
                                        markerId:
                                            const MarkerId('d_pickup_preview'),
                                        position: localPreviewPickupLatLng!),
                                  if (localPreviewDropoffLatLng != null)
                                    Marker(
                                        markerId:
                                            const MarkerId('d_dropoff_preview'),
                                        position: localPreviewDropoffLatLng!),
                                },
                                polylines: _previewPolylinesInDialog,
                                mapToolbarEnabled: false,
                                zoomControlsEnabled: false,
                                myLocationButtonEnabled: false,
                                myLocationEnabled: false,
                                onMapCreated: (GoogleMapController c) {
                                  if (_previewPolylinesInDialog.isNotEmpty &&
                                      localPreviewPickupLatLng != null &&
                                      localPreviewDropoffLatLng != null) {
                                    Future.delayed(
                                        const Duration(milliseconds: 50), () {
                                      if (mounted && c != null) {
                                        c.animateCamera(
                                            CameraUpdate.newLatLngBounds(
                                                _calculateBounds([
                                                  localPreviewPickupLatLng!,
                                                  localPreviewDropoffLatLng!
                                                ]),
                                                60.0));
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 15),
                        TextFormField(
                          controller: _userNotesController,
                          decoration: const InputDecoration(
                              labelText: 'หมายเหตุถึงคนขับ (ถ้ามี)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.notes_rounded)),
                          maxLines: 2,
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (localIsDrawingPreviewRoute)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))),
                    ],
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: <Widget>[
                TextButton(
                  child: const Text('ยกเลิก'),
                  onPressed:
                      isDialogRequestingRideLocal || localIsDrawingPreviewRoute
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton.icon(
                  icon: isDialogRequestingRideLocal
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(isDialogRequestingRideLocal
                      ? 'กำลังส่ง...'
                      : 'ยืนยันเรียกรถ'),
                  onPressed: (_pickupPointsList.isEmpty ||
                          isDialogRequestingRideLocal ||
                          localIsDrawingPreviewRoute)
                      ? null
                      : () {
                          if (dialogFormKey.currentState!.validate()) {
                            _submitRideRequest(
                                dialogContext,
                                localSelectedPickupId,
                                localSelectedDropoffId,
                                localPreviewPickupLatLng,
                                localPreviewDropoffLatLng,
                                setDialogState,
                                isDialogRequestingSetter: (val) =>
                                    setDialogState(() =>
                                        isDialogRequestingRideLocal = val));
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (mounted) {
        setStateIfMounted(() => _previewPolylinesInDialog.clear());
      }
    });
  }

  Future<void> _submitRideRequest(
    BuildContext dialogContext,
    String? selectedPickupId,
    String? selectedDropoffId,
    LatLng? previewPickupLatLng,
    LatLng? previewDropoffLatLng,
    StateSetter originalDialogSetState, {
    required Function(bool) isDialogRequestingSetter,
  }) async {
    if (selectedPickupId == null ||
        selectedDropoffId == null ||
        previewPickupLatLng == null ||
        previewDropoffLatLng == null ||
        _userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ข้อมูลไม่ครบถ้วน โปรดเลือกจุดรับส่ง'),
          backgroundColor: Colors.red));
      try {
        isDialogRequestingSetter(false);
      } catch (e) {/*ignore*/}
      return;
    }

    if (selectedPickupId == selectedDropoffId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('จุดรับและจุดส่งต้องไม่ซ้ำกัน'),
          backgroundColor: Colors.orange));
      try {
        isDialogRequestingSetter(false);
      } catch (e) {/*ignore*/}
      return;
    }

    isDialogRequestingSetter(true);
    if (mounted) setStateIfMounted(() => _isJobActive = true);

    final pickupName = _pickupPointsList
        .firstWhere((p) => p.id == selectedPickupId,
            orElse: () => PickupPoint(
                id: '', name: 'N/A', coordinates: const LatLng(0, 0)))
        .name;
    final dropoffName = _pickupPointsList
        .firstWhere((p) => p.id == selectedDropoffId,
            orElse: () => PickupPoint(
                id: '', name: 'N/A', coordinates: const LatLng(0, 0)))
        .name;
    final DateTime clientSubmitTime = DateTime.now();

    Map<String, dynamic> requestData = {
      'userId': _userId,
      'userName': FirebaseAuth.instance.currentUser?.displayName ??
          'ผู้ใช้ (ID: ${_userId!.substring(0, min(5, _userId!.length))})',
      'pickupPointId': selectedPickupId,
      'pickupPointName': pickupName,
      'pickupLatLng':
          GeoPoint(previewPickupLatLng.latitude, previewPickupLatLng.longitude),
      'dropoffPointId': selectedDropoffId,
      'dropoffPointName': dropoffName,
      'dropoffLatLng': GeoPoint(
          previewDropoffLatLng.latitude, previewDropoffLatLng.longitude),
      'status': 'requested',
      'createdAt': FieldValue.serverTimestamp(),
      'requestTimeoutAt':
          Timestamp.fromDate(clientSubmitTime.add(const Duration(seconds: 3))),
      'updatedAt': FieldValue.serverTimestamp(),
      'numberOfPassengers': 1,
      'userNotes': _userNotesController.text.trim().isNotEmpty
          ? _userNotesController.text.trim()
          : null,
      'driverId': null,
      'tripId': null,
      'driverIssueMessage': null,
      'driverIssueTimestamp': null,
      'cancelledBy': null,
      'cancellationReason': null,
    };

    try {
      DocumentReference newRequestRef = await FirebaseFirestore.instance
          .collection('ride_requests')
          .add(requestData)
          .timeout(const Duration(seconds: 30));

      if (mounted) {
        setStateIfMounted(() {
          _activeRequestId = newRequestRef.id;
          _activeJobPickupName = pickupName;
          _activeJobDropoffName = dropoffName;
          _activeJobPickupLatLng = previewPickupLatLng;
          _activeJobDropoffLatLng = previewDropoffLatLng;
          _requestSubmissionClientTime = clientSubmitTime;
          _canCancelForFree = true;
        });
        _startCancellationTimer();
        _updateJobDisplayInfo();
        _startListeningToActiveJob(_activeRequestId!);

        try {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        } catch (e) {
          print("Dialog pop error: $e");
        }

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ส่งคำขอเรียกรถสำเร็จ!'),
            backgroundColor: Colors.green));
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('การส่งคำขอล่าช้าเกินไป โปรดลองอีกครั้ง'),
            backgroundColor: Colors.orange));
        _resetActiveJobState(message: "การส่งคำขอล้มเหลว (หมดเวลา)");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('เกิดข้อผิดพลาดในการส่งคำขอ: ${e.toString()}'),
            backgroundColor: Colors.red));
        _resetActiveJobState(message: "การส่งคำขอล้มเหลว");
      }
    } finally {
      try {
        isDialogRequestingSetter(false);
      } catch (e) {
        print("Error setting dialog state: $e");
      }
    }
  }

  Widget _buildFloatingActionButton() {
    if (_isJobActive) {
      return const SizedBox.shrink();
    } else {
      return FloatingActionButton.extended(
        onPressed: _isLoadingPickupPoints ? null : _showRequestRideDialog,
        label:
            Text(_isLoadingPickupPoints ? 'กำลังโหลดจุดรับส่ง...' : 'เรียกรถ'),
        icon: const Icon(Icons.directions_bus_filled_outlined),
        backgroundColor: Theme.of(context).primaryColor,
      );
    }
  }

  Widget _buildJobStatusPanel() {
    if (!_isJobActive || _activeJobData == null) {
      return const SizedBox.shrink();
    }

    bool shouldShowCancelButton = false;
    String cancelButtonText = 'ยกเลิกฟรี (3 วินาที)';
    Color cancelButtonColor = Colors.amber.shade700;
    VoidCallback? onCancelPressed = _handleCancelRideRequest;

    if (_canCancelForFree &&
        (_currentJobStatus == 'requested' ||
            _currentJobStatus == 'driver_assigned')) {
      shouldShowCancelButton = true;
    }

    if (_isCancellingRequest && shouldShowCancelButton) {
      onCancelPressed = null;
      cancelButtonText = 'กำลังยกเลิก...';
    }

    if (_currentJobStatus == 'on_trip' ||
        _currentJobStatus == 'arrived_pickup' ||
        _currentJobStatus == 'completed' ||
        (_currentJobStatus ?? '').startsWith('cancelled') ||
        _currentJobStatus == 'driver_issue_resolved') {
      shouldShowCancelButton = false;
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Material(
          elevation: 12,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _jobStatusMessage ?? "กำลังอัปเดตสถานะ...",
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                if (_activeJobPickupName != null &&
                    _activeJobDropoffName != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'จาก: $_activeJobPickupName\nถึง: $_activeJobDropoffName',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey.shade700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_etaToPickupDisplay != null &&
                    _etaToPickupDisplay!.isNotEmpty &&
                    (_currentJobStatus == 'driver_assigned' ||
                        _currentJobStatus == 'en_route_to_pickup')) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined,
                          color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _etaToPickupDisplay!,
                        style: const TextStyle(
                            fontSize: 15,
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
                if (_driverIssueMessageReceived != null &&
                    _driverIssueMessageReceived!.isNotEmpty &&
                    _currentJobStatus == 'driver_issue') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.orange.shade300, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              "คนขับแจ้ง:",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _driverIssueMessageReceived!,
                          style: TextStyle(
                              color: Colors.orange.shade700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (shouldShowCancelButton)
                  ElevatedButton.icon(
                    icon: _isCancellingRequest
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.free_cancellation_outlined,
                            size: 20),
                    label: Text(cancelButtonText,
                        style: const TextStyle(fontSize: 14.5)),
                    onPressed: onCancelPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cancelButtonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logoutUser({bool showSnackbar = false, String? message}) async {
    await FirebaseAuth.instance.signOut();
    _resetActiveJobState();
    if (mounted) {
      if (showSnackbar &&
          message != null &&
          ModalRoute.of(context)!.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showPanel = _isJobActive && _activeJobData != null;
    double bottomPaddingForMap = 20.0;
    if (showPanel) {
      bottomPaddingForMap = MediaQuery.of(context).size.height * 0.28;
      if (_driverIssueMessageReceived != null &&
          _driverIssueMessageReceived!.isNotEmpty &&
          _currentJobStatus == 'driver_issue') bottomPaddingForMap += 40;
      if (_etaToPickupDisplay != null && _etaToPickupDisplay!.isNotEmpty)
        bottomPaddingForMap += 20;
      if (bottomPaddingForMap < 180) bottomPaddingForMap = 180;
      if (bottomPaddingForMap > MediaQuery.of(context).size.height * 0.45) {
        bottomPaddingForMap = MediaQuery.of(context).size.height * 0.45;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('เรียกรถ (ผู้ใช้)'),
        actions: [
          if (_isJobActive)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'โหลดสถานะใหม่',
              onPressed: () {
                if (_activeRequestId != null) {
                  _activeJobSubscription?.cancel();
                  _startListeningToActiveJob(_activeRequestId!);
                  if (_assignedDriverId != null) {
                    _assignedDriverLocationSubscription?.cancel();
                    _listenToAssignedDriverLocation(_assignedDriverId!);
                  }
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
            onPressed: _logoutUser,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _kInitialPosition,
            mapType: MapType.normal,
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers.union(_onlineDriverMarkers),
            polylines: _driverToPickupPolylines.union(_tripPolylines),
            padding: EdgeInsets.only(
              bottom: bottomPaddingForMap,
              top: 10,
              right: 5,
              left: 5,
            ),
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),
          if (showPanel) _buildJobStatusPanel(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildFloatingActionButton(),
    );
  }
}
