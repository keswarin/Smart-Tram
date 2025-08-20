import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Model ง่ายๆ สำหรับเก็บข้อมูลยานพาหนะ
class Vehicle {
  final String docId; // Document ID จริงๆ ของรถ
  final String vehicleId; // รหัสรถ เช่น TRAM-01
  final String displayName;

  Vehicle(
      {required this.docId,
      required this.vehicleId,
      required this.displayName});
}

class DriverAssignmentScreen extends StatefulWidget {
  const DriverAssignmentScreen({super.key});

  @override
  State<DriverAssignmentScreen> createState() => _DriverAssignmentScreenState();
}

class _DriverAssignmentScreenState extends State<DriverAssignmentScreen> {
  // Stream สำหรับดึงรายชื่อคนขับ
  final Stream<QuerySnapshot> _driversStream = FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'driver')
      .snapshots();

  // Future สำหรับดึงข้อมูลรถที่ว่าง
  Future<List<Vehicle>> _fetchAvailableVehicles() {
    return FirebaseFirestore.instance
        .collection('vehicles')
        .where('status', isEqualTo: 'active')
        .get()
        .then((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return Vehicle(
                docId: doc.id,
                vehicleId: data['vehicleId'] ?? 'N/A',
                displayName: data['displayName'] ?? 'N/A',
              );
            }).toList());
  }

  // ฟังก์ชันสำหรับแสดง Dialog เพื่อมอบหมายรถ
  Future<void> _showAssignVehicleDialog(DocumentSnapshot driverUserDoc) async {
    final String driverUid = driverUserDoc.id;
    final String driverName =
        (driverUserDoc.data() as Map<String, dynamic>)['displayName'] ?? 'N/A';

    // ดึงข้อมูลรถที่ว่างทั้งหมด
    final availableVehicles = await _fetchAvailableVehicles();
    String? selectedVehicleDocId;

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('มอบหมายรถให้ $driverName'),
          content: DropdownButtonFormField<String>(
            hint: const Text('--- เลือกรถที่ว่าง ---'),
            isExpanded: true,
            items: availableVehicles.map((Vehicle vehicle) {
              return DropdownMenuItem<String>(
                value: vehicle.docId,
                child: Text('${vehicle.displayName} (${vehicle.vehicleId})'),
              );
            }).toList(),
            onChanged: (String? newValue) {
              selectedVehicleDocId = newValue;
            },
            validator: (value) => value == null ? 'กรุณาเลือกรถ' : null,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              child: const Text('บันทึก'),
              onPressed: () {
                if (selectedVehicleDocId != null) {
                  _assignVehicleToDriver(driverUid, selectedVehicleDocId!);
                  Navigator.of(dialogContext).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  // ฟังก์ชันสำหรับอัปเดตข้อมูลใน collection 'drivers'
  Future<void> _assignVehicleToDriver(
      String driverUid, String vehicleDocId) async {
    try {
      // เราจะใช้ .set และ merge:true เพื่อสร้าง document ใหม่ถ้ายังไม่มี
      // หรืออัปเดตถ้ามีอยู่แล้ว
      await FirebaseFirestore.instance.collection('drivers').doc(driverUid).set(
        {'assignedVehicleId': vehicleDocId},
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('มอบหมายยานพาหนะสำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Widget ย่อยสำหรับแสดงรถที่คนขับได้รับมอบหมาย
  Widget _buildAssignedVehicleInfo(String driverUid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverUid)
          .snapshots(),
      builder: (context, driverDocSnapshot) {
        if (!driverDocSnapshot.hasData || !driverDocSnapshot.data!.exists) {
          return const Text('ยังไม่ได้รับมอบหมาย',
              style: TextStyle(color: Colors.orange, fontSize: 12));
        }

        final driverData =
            driverDocSnapshot.data!.data() as Map<String, dynamic>;
        final String? vehicleDocId = driverData['assignedVehicleId'];

        if (vehicleDocId == null) {
          return const Text('ยังไม่ได้รับมอบหมาย',
              style: TextStyle(color: Colors.orange, fontSize: 12));
        }

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('vehicles')
              .doc(vehicleDocId)
              .get(),
          builder: (context, vehicleSnapshot) {
            if (vehicleSnapshot.connectionState == ConnectionState.waiting) {
              return const Text('กำลังโหลด...', style: TextStyle(fontSize: 12));
            }
            if (!vehicleSnapshot.hasData || !vehicleSnapshot.data!.exists) {
              return const Text('รถไม่ถูกต้อง',
                  style: TextStyle(color: Colors.red, fontSize: 12));
            }
            final vehicleData =
                vehicleSnapshot.data!.data() as Map<String, dynamic>;
            return Text(
              'รถ: ${vehicleData['displayName'] ?? 'N/A'}',
              style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('มอบหมายงานคนขับ'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _driversStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('เกิดข้อผิดพลาด'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(data['displayName'] ?? 'N/A'),
                  subtitle: _buildAssignedVehicleInfo(doc.id),
                  trailing: const Icon(Icons.assignment_ind_outlined),
                  onTap: () => _showAssignVehicleDialog(doc),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
