import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // <<< ยังคงใช้งานอยู่สำหรับ Format เวลา

class CurrentJobScreen extends StatefulWidget {
  final String requestId; // <<< รับ Request ID มา

  const CurrentJobScreen({super.key, required this.requestId});

  @override
  State<CurrentJobScreen> createState() => _CurrentJobScreenState();
}

class _CurrentJobScreenState extends State<CurrentJobScreen> {
  StreamSubscription? _jobSubscription;
  Map<String, dynamic>? _jobData; // เก็บข้อมูลงานปัจจุบัน
  String? _currentStatus; // เก็บสถานะปัจจุบัน
  bool _isLoading = true;
  String? _errorMessage;
  String? _driverId;

  @override
  void initState() {
    super.initState();
    _driverId = FirebaseAuth.instance.currentUser?.uid;
    if (_driverId == null) {
      print("CRITICAL ERROR: Driver ID is null in CurrentJobScreen initState!");
      setState(() {
        _isLoading = false;
        _errorMessage = "ไม่สามารถยืนยันตัวตนคนขับได้";
      });
    } else {
      _listenToCurrentJob(); // เริ่มฟังข้อมูลของงานนี้
    }
  }

  @override
  void dispose() {
    _jobSubscription?.cancel();
    print(
        "CurrentJobScreen disposed: Cancelled listener for ${widget.requestId}");
    super.dispose();
  }

  // --- ฟังข้อมูลของ Job ปัจจุบันจาก Firestore ---
  void _listenToCurrentJob() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final jobDocRef = FirebaseFirestore.instance
        .collection('ride_requests') // <<< ตรวจสอบชื่อ Collection
        .doc(widget.requestId);

    print("Attaching listener to job ${widget.requestId}");
    _jobSubscription =
        jobDocRef.snapshots().listen((DocumentSnapshot snapshot) {
      if (!mounted) return;
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        print("Current job data received: Status is $status");
        setState(() {
          _jobData = data;
          _currentStatus = status;
          _isLoading = false;
          _errorMessage = null;
        });
        if (_currentStatus == 'completed' || _currentStatus == 'cancelled') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showCompletionDialogAndPop();
            }
          });
        }
      } else {
        print("Error: Job document ${widget.requestId} not found.");
        setState(() {
          _isLoading = false;
          _errorMessage = "ไม่พบข้อมูลงานปัจจุบัน อาจถูกยกเลิกหรือลบไปแล้ว";
          _jobData = null;
          _currentStatus = null;
        });
      }
    }, onError: (error) {
      print("Error listening to current job ${widget.requestId}: $error");
      if (mounted) {
        setState(() {
          _errorMessage = "เกิดข้อผิดพลาดในการโหลดข้อมูลงาน: $error";
          _isLoading = false;
        });
      }
    });
  }

  // --- ฟังก์ชันอัปเดตสถานะงาน ---
  Future<void> _updateJobStatus(String newStatus) async {
    if (_driverId == null) {
      /* ... handle error ... */ return;
    }
    // ... (โค้ดเหมือนเดิม) ...
    print(
        "Updating job ${widget.requestId} from $_currentStatus to status: $newStatus");
    final jobDocRef = FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(widget.requestId);
    final currentContext = context;
    try {
      Map<String, dynamic> updateData = {'status': newStatus};
      // *** ตรวจสอบชื่อ Field ของ Timestamp ให้ตรงกับ Firestore ***
      if (newStatus == 'arrived_pickup') {
        updateData['arrived_at'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'on_trip') {
        updateData['started_trip_at'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'completed') {
        updateData['completed_at'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'cancelled') {
        updateData['cancelled_at'] = FieldValue.serverTimestamp();
        updateData['cancelled_by'] = 'driver';
      }
      await jobDocRef.update(updateData);
      print(
          "Job ${widget.requestId} status updated successfully to $newStatus");
    } catch (e) {
      /* ... handle error ... */
      print(
          "Error updating job status to $newStatus for ${widget.requestId}: $e");
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(SnackBar(
            content: Text('เกิดข้อผิดพลาดในการอัปเดตสถานะ: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }

  // --- แสดง Dialog ตอนงานเสร็จ/ยกเลิก แล้ว Pop กลับ ---
  void _showCompletionDialogAndPop() {
    if (!mounted) return;
    // ... (โค้ดเหมือนเดิม) ...
    final String title = (_currentStatus == 'completed')
        ? 'การเดินทางเสร็จสิ้น'
        : 'การเดินทางถูกยกเลิก';
    final String content = (_currentStatus == 'completed')
        ? 'ขอบคุณสำหรับการให้บริการ'
        : 'ระบบบันทึกการยกเลิกแล้ว';
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    if (mounted && Navigator.canPop(context)) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('ตกลง'),
                )
              ],
            )).then((_) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    });
  }

  // --- ดึงชื่อสถานที่ ---
  String _getPointName(String fieldPrefix) {
    if (_jobData == null) return 'N/A';
    // *** ตรวจสอบชื่อ Field ให้ตรงกับ Firestore ***
    return _jobData!['${fieldPrefix}PointName'] as String? ??
        _jobData!['${fieldPrefix}_address'] as String? ??
        'N/A';
  }

  // --- ฟังก์ชัน Format Timestamp ---
  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final dateTime = timestamp.toDate().toLocal();
      final formatter = DateFormat('HH:mm น. (dd/MM/yy)', 'th_TH');
      return formatter.format(dateTime);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  // --- สร้าง Widget แสดงปุ่มตามสถานะปัจจุบัน ---
  Widget _buildActionButton() {
    if (_jobData == null || _currentStatus == null) {
      return const SizedBox.shrink();
    }
    // ... (โค้ด switch case เหมือนเดิม) ...
    switch (_currentStatus) {
      case 'en_route':
        return ElevatedButton.icon(
          icon: const Icon(Icons.pin_drop_outlined),
          label: const Text("ถึงจุดรับแล้ว"),
          onPressed: () => _updateJobStatus('arrived_pickup'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
        );
      case 'arrived_pickup':
        return ElevatedButton.icon(
          icon: const Icon(Icons.navigation_outlined),
          label: const Text("เริ่มเดินทาง"),
          onPressed: () => _updateJobStatus('on_trip'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
        );
      case 'on_trip':
        return ElevatedButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text("เสร็จสิ้นการเดินทาง"),
          onPressed: () => _updateJobStatus('completed'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        );
      case 'completed':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text('การเดินทางเสร็จสิ้นแล้ว',
                  style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
        );
      case 'cancelled':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cancel, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('การเดินทางถูกยกเลิก',
                  style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
        );
      default:
        return Text('สถานะงาน: $_currentStatus (ไม่ถูกต้อง)',
            style: const TextStyle(color: Colors.grey));
    }
  }

  // (Optional) Helper function สำหรับกำหนดสีสถานะ
  Color _getStatusColor(String? status) {
    // ... (โค้ดเหมือนเดิม) ...
    if (status == null) return Colors.grey;
    switch (status) {
      case 'en_route':
        return Colors.blueAccent;
      case 'arrived_pickup':
        return Colors.orangeAccent;
      case 'on_trip':
        return Colors.deepPurpleAccent;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayId = widget.requestId.length > 6
        ? '...${widget.requestId.substring(widget.requestId.length - 6)}'
        : widget.requestId;
    return Scaffold(
      appBar: AppBar(title: Text('รายละเอียดงาน (ID: $displayId)')),
      body: _buildJobDetails(),
    );
  }

  // --- ฟังก์ชันสร้างส่วน Body ของหน้าจอ ---
  Widget _buildJobDetails() {
    // --- จัดการสถานะ Loading, Error, No Data ---
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      /* ... แสดง Error พร้อมปุ่ม Retry ... */
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('ลองโหลดใหม่'),
                onPressed: _listenToCurrentJob,
              )
            ],
          ),
        ),
      );
    }
    if (_jobData == null) {
      /* ... แสดง ไม่พบข้อมูล พร้อมปุ่มกลับ ... */
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, color: Colors.grey, size: 48),
              const SizedBox(height: 16),
              const Text('ไม่พบข้อมูลงาน',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
                child: const Text('กลับ'),
              )
            ],
          ),
        ),
      );
    }

    // --- แสดงรายละเอียดงาน ---
    final pickupName = _getPointName('pickup');
    final dropoffName = _getPointName('dropoff');
    final statusDisplay = _currentStatus ?? 'N/A';

    // --- ลบการดึง userId ออก ---
    // final userId = _jobData!['userId'] as String?;

    // --- ดึงข้อมูล Timestamp ต่างๆ ---
    // *** ตรวจสอบชื่อ Field ให้ตรงกับ Firestore ***
    final Timestamp? acceptedAt = _jobData!['accepted_at'] as Timestamp?;
    final Timestamp? arrivedAt = _jobData!['arrived_at'] as Timestamp?;
    final Timestamp? startedTripAt = _jobData!['started_trip_at'] as Timestamp?;
    final Timestamp? completedAt = _jobData!['completed_at'] as Timestamp?;
    final Timestamp? cancelledAt = _jobData!['cancelled_at'] as Timestamp?;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          // --- การ์ดแสดงสถานะ ---
          Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('สถานะปัจจุบัน: ',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(statusDisplay,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(statusDisplay),
                          )),
                ],
              ),
            ),
          ),

          // --- การ์ดแสดงจุดรับ-ส่ง ---
          Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.my_location,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('จุดรับ'),
                  subtitle: Text(pickupName,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading:
                      const Icon(Icons.flag_circle, color: Colors.redAccent),
                  title: const Text('จุดส่ง'),
                  subtitle: Text(dropoffName,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              ],
            ),
          ),

          // --- ลบการ์ดแสดงข้อมูลผู้ใช้ ---
          // if (userId != null)
          //    Card( /* ... */ ),

          // --- การ์ดแสดงข้อมูลเวลา (ใช้ _formatTimestamp) ---
          Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(children: [
                if (acceptedAt != null)
                  _buildTimeListTile(
                      Icons.thumb_up_alt_outlined, 'เวลารับงาน', acceptedAt),
                if (arrivedAt != null)
                  _buildTimeListTile(
                      Icons.pin_drop_outlined, 'เวลาถึงจุดรับ', arrivedAt),
                if (startedTripAt != null)
                  _buildTimeListTile(Icons.navigation_outlined,
                      'เวลาเริ่มเดินทาง', startedTripAt),
                if (completedAt != null)
                  _buildTimeListTile(
                      Icons.check_circle_outline, 'เวลาเสร็จสิ้น', completedAt),
                if (cancelledAt != null)
                  _buildTimeListTile(
                      Icons.cancel_outlined, 'เวลายกเลิก', cancelledAt,
                      color: Colors.red),
              ]),
            ),
          ),

          // --- แสดงปุ่ม Action ---
          Center(child: _buildActionButton()),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // -- Helper Widget สำหรับสร้าง ListTile แสดงเวลา --
  Widget _buildTimeListTile(IconData icon, String title, Timestamp timestamp,
      {Color? color}) {
    // ... (โค้ดเหมือนเดิม) ...
    return ListTile(
      leading: Icon(icon, size: 20, color: color ?? Colors.grey[700]),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Text(_formatTimestamp(timestamp),
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color ?? Colors.black87)),
      dense: true,
    );
  }
} // End of _CurrentJobScreenState
