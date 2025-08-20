import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'driver_assignment_screen.dart';

// Import หน้าจออื่นๆ ที่เกี่ยวข้อง
// ตรวจสอบให้แน่ใจว่า path ของไฟล์ถูกต้อง
import 'login_screen.dart';
import 'user_management_screen.dart';
import 'vehicle_management_screen.dart';
import 'pickup_point_management_screen.dart';
import 'trip_history_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  // ฟังก์ชันสำหรับ Logout
  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      print("Error during logout: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16.0),
        crossAxisCount: 2,
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        children: [
          _buildDashboardCard(
            context,
            icon: Icons.people_alt_outlined,
            label: 'จัดการผู้ใช้',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserManagementScreen(),
                ),
              );
            },
          ),
          _buildDashboardCard(
            context,
            icon: Icons.directions_bus_filled_outlined,
            label: 'จัดการยานพาหนะ',
            onTap: () {
              // แก้ไขตรงนี้เพื่อนำทางไปยังหน้าจอใหม่
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const VehicleManagementScreen(),
                ),
              );
            },
          ),
          _buildDashboardCard(
            context,
            icon: Icons.pin_drop_outlined,
            label: 'จัดการจุดรับ-ส่ง',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PickupPointManagementScreen(),
                ),
              );
            },
          ),
          _buildDashboardCard(
            context,
            icon: Icons.history_edu_outlined,
            label: 'ประวัติการเดินทาง',
            onTap: () {
              // <<< แก้ไขตรงนี้ >>>
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TripHistoryScreen(),
                ),
              );
            },
          ),
          _buildDashboardCard(
            context,
            icon: Icons.assignment_ind_outlined,
            label: 'มอบหมายงานคนขับ',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DriverAssignmentScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48.0, color: Theme.of(context).primaryColor),
            const SizedBox(height: 12.0),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
