import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleManagementScreen extends StatefulWidget {
  const VehicleManagementScreen({super.key});

  @override
  State<VehicleManagementScreen> createState() =>
      _VehicleManagementScreenState();
}

class _VehicleManagementScreenState extends State<VehicleManagementScreen> {
  // อ้างอิงไปยัง Collection 'vehicles' ใน Firestore
  final CollectionReference _vehiclesCollection =
      FirebaseFirestore.instance.collection('vehicles');

  // --- ฟังก์ชันสำหรับแสดง Dialog เพื่อเพิ่มหรือแก้ไขข้อมูลยานพาหนะ ---
  Future<void> _showVehicleDialog({DocumentSnapshot? vehicleSnapshot}) async {
    // --- สร้างตัวแปรทั้งหมดที่จำเป็นสำหรับใช้ใน Dialog นี้โดยเฉพาะ ---
    final formKey = GlobalKey<FormState>();
    final displayNameController = TextEditingController();
    final vehicleIdController = TextEditingController();
    final capacityController = TextEditingController();

    // กำหนดค่าเริ่มต้น
    String selectedStatus = 'active';
    String selectedType = 'รถราง';

    // รายการตัวเลือกที่ถูกต้องสำหรับ Dropdown เพื่อป้องกันข้อมูลผิดพลาด
    const List<String> validStatuses = [
      'active',
      'maintenance',
      'out_of_service'
    ];
    const List<String> validTypes = ['รถราง', 'รถตู้'];

    // --- ถ้าเป็นการ "แก้ไข" ให้ดึงข้อมูลเก่ามาใส่ในฟอร์ม ---
    if (vehicleSnapshot != null) {
      final data = vehicleSnapshot.data() as Map<String, dynamic>;
      displayNameController.text = data['displayName'] ?? '';
      vehicleIdController.text = data['vehicleId'] ?? '';
      capacityController.text = (data['capacity'] ?? 0).toString();

      // ส่วนสำคัญ: ตรวจสอบว่าค่าที่ดึงมาจากฐานข้อมูล มีอยู่ในรายการตัวเลือกของเราหรือไม่
      // ถ้าไม่มี ให้ใช้ค่าเริ่มต้น ('active') เพื่อป้องกันแอป Crash
      String statusFromDb = data['status'] ?? 'active';
      selectedStatus =
          validStatuses.contains(statusFromDb) ? statusFromDb : 'active';

      String typeFromDb = data['type'] ?? 'รถราง';
      selectedType = validTypes.contains(typeFromDb) ? typeFromDb : 'รถราง';
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // ไม่ให้ปิด Dialog เมื่อกดนอกพื้นที่
      builder: (BuildContext context) {
        // ใช้ StatefulBuilder เพื่อให้ Dialog สามารถ re-render ตัวเองได้
        // เมื่อมีการเลือกค่าใน Dropdown ใหม่ โดยไม่กระทบกับหน้าจอหลัก
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(vehicleSnapshot == null
                  ? 'เพิ่มยานพาหนะใหม่'
                  : 'แก้ไขข้อมูลยานพาหนะ'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: displayNameController,
                        decoration: const InputDecoration(
                            labelText: 'ชื่อที่แสดงผล (Display Name)'),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'กรุณาใส่ชื่อ'
                            : null,
                      ),
                      TextFormField(
                        controller: vehicleIdController,
                        decoration: const InputDecoration(
                            labelText: 'รหัสยานพาหนะ (Vehicle ID)'),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'กรุณาใส่รหัส'
                            : null,
                      ),
                      TextFormField(
                        controller: capacityController,
                        decoration: const InputDecoration(
                            labelText: 'ความจุ (Capacity)'),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'กรุณาใส่ความจุ';
                          if (int.tryParse(value) == null)
                            return 'กรุณาใส่เป็นตัวเลข';
                          return null;
                        },
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(labelText: 'ประเภท'),
                        items: validTypes.map((String value) {
                          return DropdownMenuItem<String>(
                              value: value, child: Text(value));
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setDialogState(() => selectedType = newValue);
                          }
                        },
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedStatus,
                        decoration: const InputDecoration(labelText: 'สถานะ'),
                        items: validStatuses.map((String value) {
                          return DropdownMenuItem<String>(
                              value: value, child: Text(value));
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setDialogState(() => selectedStatus = newValue);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('บันทึก'),
                  onPressed: () {
                    // ตรวจสอบข้อมูลในฟอร์มก่อนบันทึก
                    if (formKey.currentState!.validate()) {
                      _addOrUpdateVehicle(
                        displayName: displayNameController.text,
                        vehicleId: vehicleIdController.text,
                        capacity: capacityController.text,
                        type: selectedType,
                        status: selectedStatus,
                        vehicleSnapshot: vehicleSnapshot,
                      );
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- ฟังก์ชันสำหรับเพิ่มหรืออัปเดตข้อมูลใน Firestore ---
  Future<void> _addOrUpdateVehicle({
    required String displayName,
    required String vehicleId,
    required String capacity,
    required String type,
    required String status,
    DocumentSnapshot? vehicleSnapshot,
  }) async {
    final int capacityInt = int.tryParse(capacity) ?? 0;

    final vehicleData = {
      'displayName': displayName,
      'vehicleId': vehicleId,
      'capacity': capacityInt,
      'type': type,
      'status': status,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (vehicleSnapshot == null) {
        // ถ้าไม่มี vehicleSnapshot แปลว่าเป็นการ "เพิ่ม" ข้อมูลใหม่
        await _vehiclesCollection.add(vehicleData);
      } else {
        // ถ้ามี vehicleSnapshot แปลว่าเป็นการ "อัปเดต" ข้อมูลเดิม
        await _vehiclesCollection.doc(vehicleSnapshot.id).update(vehicleData);
      }
    } catch (e) {
      print("Error saving vehicle: $e");
      // (Optional) อาจจะแสดง SnackBar แจ้งเตือนผู้ใช้ว่าบันทึกไม่สำเร็จ
    }
  }

  // --- ฟังก์ชันสำหรับลบยานพาหนะ ---
  Future<void> _deleteVehicle(String docId) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบยานพาหนะนี้?'),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                try {
                  await _vehiclesCollection.doc(docId).delete();
                } catch (e) {
                  print("Error deleting vehicle: $e");
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการยานพาหนะ'),
      ),
      // ใช้ StreamBuilder เพื่อให้หน้าจออัปเดตข้อมูลยานพาหนะอัตโนมัติแบบ Real-time
      body: StreamBuilder<QuerySnapshot>(
        stream: _vehiclesCollection.orderBy('displayName').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('ไม่พบข้อมูลยานพาหนะ'));
          }

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(data['type'] == 'รถราง'
                        ? Icons.tram
                        : Icons.directions_bus),
                  ),
                  title: Text(data['displayName'] ?? 'N/A'),
                  subtitle: Text(
                      'ID: ${data['vehicleId'] ?? 'N/A'} - สถานะ: ${data['status'] ?? 'N/A'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () =>
                            _showVehicleDialog(vehicleSnapshot: doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteVehicle(doc.id),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showVehicleDialog(),
        tooltip: 'เพิ่มยานพาหนะ',
        child: const Icon(Icons.add),
      ),
    );
  }
}
