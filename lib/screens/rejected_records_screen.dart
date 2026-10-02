import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';

class RejectedRecordsScreen extends StatefulWidget {
  const RejectedRecordsScreen({super.key});

  @override
  _RejectedRecordsScreenState createState() => _RejectedRecordsScreenState();
}

class _RejectedRecordsScreenState extends State<RejectedRecordsScreen> {
  List<dynamic> _records = [];
  List<dynamic> _filteredRecords = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchRejected();
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchRejected() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/attendance/rejected');
      setState(() {
        _records = response.data['data'];
        _isLoading = false;
      });
      _applySearch();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applySearch() {
    final query = _searchController.text.trim();
    setState(() {
      if (query.isEmpty) {
        _filteredRecords = List.from(_records);
      } else {
        _filteredRecords = _records.where((r) {
          final name = (r['full_name'] ?? '').toString().toLowerCase();
          final site = (r['site_name'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              site.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Map<String, Map<String, List<dynamic>>> _groupRecords() {
    final Map<String, Map<String, List<dynamic>>> grouped = {};
    for (var r in _filteredRecords) {
      final site = r['site_name'] ?? 'No Site';
      final date = (r['record_date'] ?? '').toString().split('T').first;
      grouped.putIfAbsent(site, () => {});
      grouped[site]!.putIfAbsent(date, () => []);
      grouped[site]![date]!.add(r);
    }
    final Map<String, Map<String, List<dynamic>>> sortedGrouped = {};
    for (var site in grouped.keys) {
      final dates = grouped[site]!.keys.toList()..sort((a, b) => b.compareTo(a));
      final Map<String, List<dynamic>> orderedDates = {};
      for (var d in dates) {
        orderedDates[d] = grouped[site]![d]!;
      }
      sortedGrouped[site] = orderedDates;
    }
    return sortedGrouped;
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return '--:--';
    try {
      final time = DateTime.parse(isoTime).toLocal();
      return DateFormat('HH:mm').format(time);
    } catch (_) {
      return '--:--';
    }
  }

  Future<void> _resubmit(int id, String? newInIso, String? newOutIso, String remarks, {String? attendanceStatus}) async {
    try {
      await ApiConfig.dio.patch('/attendance/$id/resubmit', data: {
        if (attendanceStatus == null || attendanceStatus == 'Present') 'check_in_time': newInIso,
        if (attendanceStatus == null || attendanceStatus == 'Present') 'check_out_time': newOutIso,
        'remarks': remarks,
        if (attendanceStatus != null) 'attendance_status': attendanceStatus,
      });
      _fetchRejected();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resubmitted successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      String errorMsg = 'Failed to resubmit';
      if (e is DioException && e.response?.data['message'] != null) {
        errorMsg = e.response!.data['message'];
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openEditDialog(Map<String, dynamic> r) async {
    DateTime? checkIn = r['check_in_time'] != null ? DateTime.parse(r['check_in_time']).toLocal() : null;
    DateTime? checkOut = r['check_out_time'] != null ? DateTime.parse(r['check_out_time']).toLocal() : null;
    final remarksController = TextEditingController(text: r['remarks']?.toString() ?? '');
    final recordDate = DateTime.tryParse((r['record_date'] ?? '').toString().split('T').first) ?? DateTime.now();
    const statuses = ['Present', 'Absent', 'Sick', 'Vacation', 'Holiday'];
    String attendanceStatus = statuses.contains(r['attendance_status']) ? r['attendance_status'] : 'Present';

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickTime(bool isCheckIn) async {
              final initial = isCheckIn
                  ? (checkIn != null ? TimeOfDay.fromDateTime(checkIn!) : TimeOfDay.now())
                  : (checkOut != null ? TimeOfDay.fromDateTime(checkOut!) : TimeOfDay.now());

              final picked = await showTimePicker(context: context, initialTime: initial);

              if (picked != null) {
                // Check-in is always on the record date. Check-out is on the
                // record date, or the next day for a night shift (when the
                // picked time is not after check-in).
                var newDateTime = DateTime(
                  recordDate.year, recordDate.month, recordDate.day, picked.hour, picked.minute,
                );
                if (!isCheckIn && checkIn != null && !newDateTime.isAfter(checkIn!)) {
                  newDateTime = newDateTime.add(const Duration(days: 1));
                }
                setDialogState(() {
                  if (isCheckIn) {
                    checkIn = newDateTime;
                  } else {
                    checkOut = newDateTime;
                  }
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.person, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r['full_name'] ?? '', overflow: TextOverflow.ellipsis)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((r['admin_rejection_notes'] ?? r['remarks']) != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rejection Reason',
                              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (r['admin_rejection_notes'] ?? r['remarks'] ?? 'None').toString(),
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ],
                        ),
                      ),
                    const Divider(),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: attendanceStatus,
                      decoration: InputDecoration(
                        labelText: 'Attendance status',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setDialogState(() => attendanceStatus = v ?? attendanceStatus),
                    ),
                    const SizedBox(height: 12),
                    if (attendanceStatus == 'Present') ...[
                      _timeRow('Check-in Time', checkIn, () => pickTime(true)),
                      const SizedBox(height: 12),
                      _timeRow('Check-out Time', checkOut, () => pickTime(false)),
                      if (checkIn != null && checkOut != null && checkOut!.day != checkIn!.day)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Check-out is on the next day (night shift).',
                              style: TextStyle(fontSize: 12, color: Colors.indigo.shade400)),
                        ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: remarksController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Remarks',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _resubmit(
                      r['attendance_id'],
                      checkIn == null ? null : DateFormat('yyyy-MM-dd HH:mm:ss').format(checkIn!),
                      checkOut == null ? null : DateFormat('yyyy-MM-dd HH:mm:ss').format(checkOut!),
                      remarksController.text,
                      attendanceStatus: attendanceStatus,
                    );
                  },
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Resubmit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _timeRow(String label, DateTime? value, VoidCallback onTap) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.access_time, size: 16),
          label: Text(value != null ? DateFormat('HH:mm').format(value) : '--:--'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupRecords();

    return Scaffold(
      appBar: AppBar(title: const Text("Rejected Records")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by worker name or site...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : grouped.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 60, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('No rejected records found', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchRejected,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: grouped.entries.map((siteEntry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on, color: Colors.indigo, size: 20),
                                        const SizedBox(width: 6),
                                        Text(
                                          siteEntry.key,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...siteEntry.value.entries.map((dateEntry) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          child: Text(
                                            _formatDate(dateEntry.key),
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        ...dateEntry.value.map((r) {
                                          return Card(
                                            elevation: 1.5,
                                            margin: const EdgeInsets.only(bottom: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const CircleAvatar(
                                                        backgroundColor: Colors.blueGrey,
                                                        child: Icon(Icons.person, color: Colors.white),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              r['full_name'] ?? '',
                                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                                            ),
                                                            Row(
                                                              children: [
                                                                Icon(Icons.login, size: 14, color: Colors.grey.shade600),
                                                                const SizedBox(width: 4),
                                                                Text(_formatTime(r['check_in_time'])),
                                                                const SizedBox(width: 10),
                                                                Icon(Icons.logout, size: 14, color: Colors.grey.shade600),
                                                                const SizedBox(width: 4),
                                                                Text(_formatTime(r['check_out_time'])),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red.shade50,
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(
                                                          'Rejected',
                                                          style: TextStyle(
                                                            color: Colors.red.shade700,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if ((r['admin_rejection_notes'] ?? r['remarks']) != null)
                                                    Container(
                                                      width: double.infinity,
                                                      margin: const EdgeInsets.only(top: 10),
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.shade50,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        'Rejection Reason: ${r['admin_rejection_notes'] ?? r['remarks'] ?? 'None'}',
                                                        style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                                                      ),
                                                    ),
                                                  Align(
                                                    alignment: Alignment.centerLeft,
                                                    child: TextButton.icon(
                                                      onPressed: () => _openEditDialog(Map<String, dynamic>.from(r)),
                                                      icon: const Icon(Icons.edit, size: 16),
                                                      label: const Text('Edit & Resubmit'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    );
                                  }),
                                  const Divider(thickness: 1),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}