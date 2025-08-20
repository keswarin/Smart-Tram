import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const int kCapacityPerRound = 6; // สูงสุดต่อรอบ

class GroupedRequest {
  final String pickupPointId;
  final String dropoffPointId;
  final String pickupPointName;
  final String dropoffPointName;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  GroupedRequest({
    required this.pickupPointId,
    required this.dropoffPointId,
    required this.pickupPointName,
    required this.dropoffPointName,
    required this.docs,
  });

  int get passengerCount => docs.fold<int>(
        0,
        (sum, d) => sum + (d.data()['numberOfPassengers'] as int? ?? 1),
      );
}

class RequestListScreen extends StatefulWidget {
  const RequestListScreen({Key? key}) : super(key: key);

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  String? _driverId;
  String? _assignedVehicleId;
  String? _assignedVehicleDisplayName;

  @override
  void initState() {
    super.initState();
    _driverId = FirebaseAuth.instance.currentUser?.uid;
    _loadDriverMeta();
  }

  Future<void> _loadDriverMeta() async {
    final uid = _driverId;
    if (uid == null) return;
    final snap =
        await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
    if (!mounted || !snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    setState(() {
      _assignedVehicleId = data['assignedVehicleId'] as String?;
      _assignedVehicleDisplayName =
          data['assignedVehicleDisplayName'] as String?;
    });
  }

  /// รวมคำขอที่เส้นทางเดียวกัน แล้ว "ตัด" เป็นบัคเก็ตละ ≤ 6 คน
  List<GroupedRequest> _groupIntoBuckets(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final byRoute =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in docs) {
      final m = d.data();
      final pid = m['pickupPointId'] as String? ?? '';
      final did = m['dropoffPointId'] as String? ?? '';
      (byRoute['${pid}_$did'] ??= []).add(d);
    }

    final result = <GroupedRequest>[];

    for (final entry in byRoute.entries) {
      final list = [...entry.value];
      list.sort((a, b) {
        final ta =
            (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb =
            (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return ta.compareTo(tb);
      });

      List<QueryDocumentSnapshot<Map<String, dynamic>>> bucket = [];
      int used = 0;

      void flush() {
        if (bucket.isEmpty) return;
        final first = bucket.first.data();
        result.add(GroupedRequest(
          pickupPointId: first['pickupPointId'] as String? ?? '',
          dropoffPointId: first['dropoffPointId'] as String? ?? '',
          pickupPointName: first['pickupPointName'] as String? ??
              (first['pickupPointId'] as String? ?? ''),
          dropoffPointName: first['dropoffPointName'] as String? ??
              (first['dropoffPointId'] as String? ?? ''),
          docs: List.unmodifiable(bucket),
        ));
        bucket = [];
        used = 0;
      }

      for (final d in list) {
        final m = d.data();
        final seats = m['numberOfPassengers'] as int? ?? 1;

        if (used + seats > kCapacityPerRound) flush();
        bucket.add(d);
        used += seats;
        if (used == kCapacityPerRound) flush();
      }
      flush();
    }

    // เรียงบัคเก็ตตามเวลาคำขอแรกในบัคเก็ต
    result.sort((a, b) {
      final ta = (a.docs.first.data()['createdAt'] as Timestamp?)
              ?.millisecondsSinceEpoch ??
          0;
      final tb = (b.docs.first.data()['createdAt'] as Timestamp?)
              ?.millisecondsSinceEpoch ??
          0;
      return ta.compareTo(tb);
    });

    return result;
  }

  Future<GeoPoint?> _getPointGeo(String id) async {
    if (id.isEmpty) return null;
    final s = await FirebaseFirestore.instance
        .collection('pickup_points')
        .doc(id)
        .get();
    if (!s.exists) return null;
    return (s.data() as Map<String, dynamic>)['coordinates'] as GeoPoint?;
  }

  /// แยกรายชื่อผู้โดยสารเป็นรายคน เพื่อให้ฝั่งคนขับนับจำนวนได้แม่น
  List<Map<String, dynamic>> _buildPassengerEntries(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String action) {
    final out = <Map<String, dynamic>>[];
    for (final d in docs) {
      final m = d.data();
      final seats = (m['numberOfPassengers'] as int? ?? 1);
      for (int i = 0; i < seats; i++) {
        out.add({
          'rideRequestId': d.id,
          'userId': m['userId'],
          'userName': m['userName'],
          'action': action, // 'pickup' or 'dropoff'
        });
      }
    }
    return out;
  }

  Future<void> _acceptBucket(GroupedRequest g) async {
    if (_driverId == null) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      final requestIds = <String>[];
      int total = 0;
      GeoPoint? pickupGP;
      GeoPoint? dropoffGP;

      // 1) อัปเดตคำขอทั้งหมดในบัคเก็ต -> assigned
      for (final doc in g.docs) {
        final m = doc.data();
        total += (m['numberOfPassengers'] as int? ?? 1);
        requestIds.add(doc.id);

        pickupGP = (m['pickupLatLng'] as GeoPoint?) ?? pickupGP;
        dropoffGP = (m['dropoffLatLng'] as GeoPoint?) ?? dropoffGP;

        batch.update(doc.reference, {
          'status': 'assigned',
          'driverId': _driverId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 2) ถ้าไม่มี GeoPoint ในคำขอ ให้ดึงจาก master pickup_points
      pickupGP ??= await _getPointGeo(g.pickupPointId);
      dropoffGP ??= await _getPointGeo(g.dropoffPointId);

      // 3) เตรียมผู้โดยสารแยกตามจุด
      final pickupPassengers = _buildPassengerEntries(g.docs, 'pickup');
      final dropoffPassengers = _buildPassengerEntries(g.docs, 'dropoff');

      // 4) เขียนงานของคนขับ (current)
      final assignedRouteRef = FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .collection('assigned_routes')
          .doc('current');

      // สร้าง map ของ stop โดยใส่ coordinates เฉพาะตอนที่มีค่า
      Map<String, dynamic> _stopMap({
        required String stopId,
        required String stopName,
        required List<Map<String, dynamic>> passengers,
        GeoPoint? coord,
      }) {
        final m = <String, dynamic>{
          'stopId': stopId,
          'stopName': stopName,
          'status': 'pending',
          'passengers': passengers,
        };
        if (coord != null) m['coordinates'] = coord;
        return m;
      }

      batch.set(assignedRouteRef, {
        'driverId': _driverId,
        'vehicleId': _assignedVehicleId,
        'assignedVehicleDisplayName': _assignedVehicleDisplayName,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'requestIds': requestIds,
        'passengerTotal': total, // ≤ 6
        'pickupPointId': g.pickupPointId,
        'pickupPointName': g.pickupPointName,
        'dropoffPointId': g.dropoffPointId,
        'dropoffPointName': g.dropoffPointName,
        'stops': [
          _stopMap(
            stopId: 'pickup_${g.pickupPointId}',
            stopName: g.pickupPointName,
            passengers: pickupPassengers,
            coord: pickupGP,
          ),
          _stopMap(
            stopId: 'dropoff_${g.dropoffPointId}',
            stopName: g.dropoffPointName,
            passengers: dropoffPassengers,
            coord: dropoffGP,
          ),
        ],
      });

      // 5) ทำสถานะคนขับเป็นไม่ว่าง
      batch.update(
        FirebaseFirestore.instance.collection('drivers').doc(_driverId),
        {'isAvailable': false},
      );

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'รับงานแล้ว: ${g.pickupPointName} → ${g.dropoffPointName} (${total}/$kCapacityPerRound)',
        ),
      ));
      Navigator.of(context).pop(); // กลับหน้า Driver
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('คำขอรอรับ (สูงสุด 6 คน/รอบ, รวมเส้นทางเดียวกัน)'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('ride_requests')
            .where('status', isEqualTo: 'requested')
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('เกิดข้อผิดพลาด'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีคำขอใหม่'));
          }

          final buckets = _groupIntoBuckets(docs);

          return ListView.builder(
            itemCount: buckets.length,
            itemBuilder: (_, i) {
              final g = buckets[i];
              return Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${g.pickupPointName} → ${g.dropoffPointName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'จำนวนผู้โดยสาร: ${g.passengerCount} / $kCapacityPerRound คน',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: g.docs.map((d) {
                          final m = d.data();
                          final name =
                              (m['userName'] as String?) ?? m['userId'];
                          final seats =
                              (m['numberOfPassengers'] as int? ?? 1);
                          return Chip(label: Text('$name ($seats)'));
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _acceptBucket(g),
                        child: const Text('รับงานรอบนี้'),
                      ),
                    ],
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
