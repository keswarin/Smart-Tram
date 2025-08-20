import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // <<< แก้ไขบรรทัดนี้ให้ถูกต้อง

class PickupPointManagementScreen extends StatefulWidget {
  const PickupPointManagementScreen({super.key});

  @override
  State<PickupPointManagementScreen> createState() =>
      _PickupPointManagementScreenState();
}

class _PickupPointManagementScreenState
    extends State<PickupPointManagementScreen> {
  // อ้างอิงไปยัง Collection 'pickup_points'
  final CollectionReference _pickupPointsCollection =
      FirebaseFirestore.instance.collection('pickup_points');

  // Controllers สำหรับฟอร์มใน Dialog
  final TextEditingController _nameController = TextEditingController();
  LatLng? _selectedCoordinates;

  // --- ฟังก์ชันสำหรับแสดง Dialog ---
  Future<void> _showPointDialog({DocumentSnapshot? pointSnapshot}) async {
    _selectedCoordinates = null; // รีเซ็ตค่าพิกัดทุกครั้งที่เปิด Dialog

    // ถ้าเป็นการแก้ไข (Edit), ให้ดึงข้อมูลเก่ามาแสดงในฟอร์ม
    if (pointSnapshot != null) {
      final data = pointSnapshot.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? '';
      final GeoPoint? coordinates = data['coordinates'] as GeoPoint?;
      if (coordinates != null) {
        _selectedCoordinates =
            LatLng(coordinates.latitude, coordinates.longitude);
      }
    } else {
      // ถ้าเป็นการเพิ่มใหม่ (Add), ให้ล้างข้อมูลในฟอร์ม
      _nameController.clear();
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        // ใช้ StatefulBuilder เพื่อให้แผนที่ใน Dialog อัปเดต Marker ได้
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(pointSnapshot == null
                  ? 'เพิ่มจุดรับ-ส่งใหม่'
                  : 'แก้ไขจุดรับ-ส่ง'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: _nameController,
                      decoration:
                          const InputDecoration(labelText: 'ชื่อจุดรับ-ส่ง'),
                    ),
                    const SizedBox(height: 16),
                    Text("เลือกพิกัดบนแผนที่:",
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      width: double.maxFinite,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _selectedCoordinates ??
                              const LatLng(
                                  18.7950, 98.9860), // ตำแหน่งเริ่มต้น (มช.)
                          zoom: 15,
                        ),
                        markers: {
                          if (_selectedCoordinates != null)
                            Marker(
                              markerId: const MarkerId('selected-point'),
                              position: _selectedCoordinates!,
                              draggable: true,
                              onDragEnd: (newPosition) {
                                setDialogState(() {
                                  _selectedCoordinates = newPosition;
                                });
                              },
                            ),
                        },
                        onTap: (LatLng coordinates) {
                          setDialogState(() {
                            _selectedCoordinates = coordinates;
                          });
                        },
                      ),
                    ),
                    if (_selectedCoordinates == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'กรุณาแตะบนแผนที่เพื่อเลือกพิกัด',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
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
                    // ตรวจสอบว่ากรอกข้อมูลครบถ้วนก่อนบันทึก
                    if (_nameController.text.isNotEmpty &&
                        _selectedCoordinates != null) {
                      _addOrUpdatePoint(pointSnapshot: pointSnapshot);
                      Navigator.of(context).pop();
                    } else {
                      // (Optional) แสดงข้อความเตือนถ้าข้อมูลไม่ครบ
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('กรุณากรอกชื่อและเลือกพิกัดบนแผนที่'),
                        backgroundColor: Colors.orange,
                      ));
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
  Future<void> _addOrUpdatePoint({DocumentSnapshot? pointSnapshot}) async {
    final pointData = {
      'name': _nameController.text,
      'coordinates': GeoPoint(
          _selectedCoordinates!.latitude, _selectedCoordinates!.longitude),
      'isActive': true, // ตั้งค่าเริ่มต้นให้ใช้งานได้เลย
    };

    try {
      if (pointSnapshot == null) {
        // เพิ่มข้อมูลใหม่
        await _pickupPointsCollection.add(pointData);
      } else {
        // อัปเดตข้อมูลเดิม
        await _pickupPointsCollection.doc(pointSnapshot.id).update(pointData);
      }
    } catch (e) {
      print("Error saving pickup point: $e");
    }
  }

  // --- ฟังก์ชันสำหรับลบจุดรับ-ส่ง ---
  Future<void> _deletePoint(String docId) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบจุดรับ-ส่งนี้?'),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                try {
                  await _pickupPointsCollection.doc(docId).delete();
                } catch (e) {
                  print("Error deleting pickup point: $e");
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
        title: const Text('จัดการจุดรับ-ส่ง'),
      ),
      // ใช้ StreamBuilder เพื่อให้หน้าจออัปเดตข้อมูลอัตโนมัติแบบ Real-time
      body: StreamBuilder<QuerySnapshot>(
        stream: _pickupPointsCollection.orderBy('name').snapshots(),
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
              final GeoPoint? coordinates = data['coordinates'] as GeoPoint?;
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.location_on)),
                  title: Text(data['name'] ?? 'N/A'),
                  subtitle: Text(coordinates != null
                      ? 'Lat: ${coordinates.latitude.toStringAsFixed(4)}, Lng: ${coordinates.longitude.toStringAsFixed(4)}'
                      : 'ไม่มีข้อมูลพิกัด'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showPointDialog(pointSnapshot: doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deletePoint(doc.id),
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
        onPressed: () => _showPointDialog(),
        tooltip: 'เพิ่มจุดรับ-ส่ง',
        child: const Icon(Icons.add_location_alt_outlined),
      ),
    );
  }
}
