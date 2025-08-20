import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // สร้างตัวแปร Future เพื่อเก็บผลลัพธ์การดึงข้อมูล
  late Future<QuerySnapshot> _usersFuture;

  @override
  void initState() {
    super.initState();
    // สั่งให้ดึงข้อมูลครั้งแรกเมื่อหน้าจอถูกสร้าง
    _usersFuture = _fetchUsers();
  }

  // ฟังก์ชันสำหรับดึงข้อมูลจาก Firestore
  Future<QuerySnapshot> _fetchUsers() {
    return FirebaseFirestore.instance.collection('users').get();
  }

  // ฟังก์ชันสำหรับปุ่มรีเฟรช
  void _refreshUsers() {
    setState(() {
      // สั่งให้ดึงข้อมูลใหม่และ rebuild UI
      _usersFuture = _fetchUsers();
    });
  }

  // ฟังก์ชันสำหรับแสดง Dialog แก้ไข Role
  Future<void> _showEditRoleDialog(
      BuildContext context, String docId, String currentRole) async {
    String? selectedRole = currentRole;

    // ใช้ StatefulBuilder เพื่อให้ Dropdown ใน Dialog สามารถ update ค่าที่เลือกได้
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('เปลี่ยน Role'),
              content: DropdownButton<String>(
                value: selectedRole,
                isExpanded: true,
                items: <String>['passenger', 'driver', 'admin']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setDialogState(() {
                    selectedRole = newValue;
                  });
                },
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton(
                  child: const Text('บันทึก'),
                  onPressed: () {
                    if (selectedRole != null && selectedRole != currentRole) {
                      _updateUserRole(docId, selectedRole!);
                    }
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ฟังก์ชันสำหรับอัปเดตข้อมูล Role ใน Firestore
  Future<void> _updateUserRole(String docId, String newRole) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .update({'role': newRole});

      // หลังจากอัปเดตสำเร็จ ให้รีเฟรชข้อมูลในหน้าจอเพื่อแสดงผลล่าสุด
      _refreshUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดต Role สำเร็จ'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการผู้ใช้'),
        actions: [
          // ปุ่มสำหรับรีเฟรชข้อมูล
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'โหลดข้อมูลใหม่',
            onPressed: _refreshUsers,
          ),
        ],
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: _usersFuture, // ใช้ Future ที่เราสร้างไว้
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('ไม่พบข้อมูลผู้ใช้'));
          }

          return ListView(
            children: snapshot.data!.docs.map((DocumentSnapshot document) {
              Map<String, dynamic> data =
                  document.data()! as Map<String, dynamic>;
              String currentRole = data['role'] ?? 'N/A';

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(_getIconForRole(currentRole)),
                  ),
                  title: Text(data['displayName'] ?? 'No Name'),
                  subtitle: Text(data['email'] ?? 'No Email'),
                  trailing: Text(
                    currentRole.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getColorForRole(currentRole),
                    ),
                  ),
                  onTap: () {
                    _showEditRoleDialog(context, document.id, currentRole);
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  // Helper functions สำหรับแสดงผลให้สวยงาม
  IconData _getIconForRole(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'driver':
        return Icons.directions_bus;
      case 'passenger':
        return Icons.person;
      default:
        return Icons.help_outline;
    }
  }

  Color _getColorForRole(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'driver':
        return Colors.blue;
      case 'passenger':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
