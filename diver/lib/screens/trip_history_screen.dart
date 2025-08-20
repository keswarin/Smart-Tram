import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // สำหรับการจัดรูปแบบวันที่และเวลา

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  // สร้าง Future เพื่อดึงข้อมูลการเดินทางที่สิ้นสุดแล้ว
  late Future<QuerySnapshot> _tripsFuture;

  @override
  void initState() {
    super.initState();
    _tripsFuture = _fetchTripHistory();
  }

  // ฟังก์ชันสำหรับดึงข้อมูลจาก Firestore
  Future<QuerySnapshot> _fetchTripHistory() {
    // เราจะดึงข้อมูลจาก collection 'ride_requests'
    // โดยกรองเอาเฉพาะ status ที่สิ้นสุดแล้ว และเรียงตามวันที่สร้างล่าสุด
    return FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status',
            whereIn: ['completed', 'cancelled_by_user', 'cancelled_by_driver'])
        .orderBy('createdAt', descending: true)
        .limit(50) // จำกัดการโหลด 50 รายการล่าสุดเพื่อประสิทธิภาพ
        .get();
  }

  // ฟังก์ชันสำหรับรีเฟรชข้อมูล
  void _refreshHistory() {
    setState(() {
      _tripsFuture = _fetchTripHistory();
    });
  }

  // Helper function สำหรับจัดรูปแบบ Timestamp ให้อ่านง่าย
  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    // ใช้ intl package เพื่อแปลงเป็นรูปแบบ วัน/เดือน/ปี ชั่วโมง:นาที
    final DateTime dateTime = timestamp.toDate();
    final DateFormat formatter = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');
    return formatter.format(dateTime);
  }

  // Helper function สำหรับสร้างสีและไอคอนตามสถานะ
  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'completed':
        return {'color': Colors.green, 'icon': Icons.check_circle};
      case 'cancelled_by_user':
        return {'color': Colors.orange, 'icon': Icons.cancel};
      case 'cancelled_by_driver':
        return {'color': Colors.red, 'icon': Icons.cancel_schedule_send};
      default:
        return {'color': Colors.grey, 'icon': Icons.help_outline};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการเดินทาง'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshHistory,
            tooltip: 'โหลดข้อมูลใหม่',
          ),
        ],
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: _tripsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('ไม่พบประวัติการเดินทาง'));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final statusInfo = _getStatusInfo(data['status'] ?? '');

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusInfo['color'],
                    child: Icon(statusInfo['icon'], color: Colors.white),
                  ),
                  title: Text('จาก: ${data['pickupPointName'] ?? 'N/A'}'),
                  subtitle: Text(
                      'ถึง: ${data['dropoffPointName'] ?? 'N/A'}\nผู้ใช้: ${data['userName'] ?? 'N/A'}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        (data['status'] ?? 'N/A')
                            .replaceAll('_', ' ')
                            .toUpperCase(),
                        style: TextStyle(
                            color: statusInfo['color'],
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                      Text(
                        _formatTimestamp(data['createdAt'] as Timestamp?),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
