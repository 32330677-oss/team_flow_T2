// lib/screens/staff_lifecycle_screen.dart
//
// Shows a staff member's status history and site assignment history, and
// lets the Admin record a new status change (Active/Inactive/Terminated)
// or reassign the staff member to a different site. Opened from
// staff_screen.dart via a new "Lifecycle" action on each staff row.
//
// This is intentionally a separate screen/file from workers_screen.dart's
// worker-status logic — staff and worker lifecycle are not merged.

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_data_table.dart';
import '../widgets/help_tip.dart';

class StaffLifecycleScreen extends StatefulWidget {
  final Map<String, dynamic> staff;

  const StaffLifecycleScreen({super.key, required this.staff});

  @override
  State<StaffLifecycleScreen> createState() => _StaffLifecycleScreenState();
}

class _StaffLifecycleScreenState extends State<StaffLifecycleScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  bool _isLoading = true;
  List<dynamic> _statusHistory = [];
  List<dynamic> _assignmentHistory = [];
  List<dynamic> _sites = [];
  bool _isReturningEmployee = false;
  late String _currentStatus;

  int get _staffId => widget.staff['staff_id'] as int;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.staff['status']?.toString() ?? 'Active';
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiConfig.dio.get('/staff/$_staffId/lifecycle-history'),
        ApiConfig.dio.get('/staff/$_staffId/assignments'),
        ApiConfig.dio.get('/sites/all-sites'),
      ]);
    setState(() {
  _statusHistory = results[0].data['data'] ?? [];
  _isReturningEmployee = results[0].data['is_returning_employee'] == true; // جديد
  _assignmentHistory = results[1].data['data'] ?? [];
  _sites = results[2].data['data'] ?? [];
  _isLoading = false;
});
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Failed to load lifecycle data', Colors.red);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openStatusChangeDialog() async {
String selectedStatus = _currentStatus == 'Terminated'
    ? 'Active'
    : (_currentStatus == 'Active' ? 'Inactive' : 'Active');
        final dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Staff Status'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current status: $_currentStatus', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: const InputDecoration(labelText: 'New Status', border: OutlineInputBorder()),
                items: (_currentStatus == 'Terminated'
        ? const ['Active']
        : ['Active', 'Inactive', 'Terminated'].where((s) => s != _currentStatus).toList())
    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
    .toList(),
                  onChanged: (v) => setDialogState(() => selectedStatus = v ?? selectedStatus),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Effective Date', border: OutlineInputBorder()),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      dateController.text = picked.toIso8601String().split('T')[0];
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason (required)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (selectedStatus == 'Terminated') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Termination is a final state and will also close any open site assignment.',
                      style: TextStyle(color: Colors.red.shade800, fontSize: 12.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
           FilledButton(
  style: FilledButton.styleFrom(
    backgroundColor: selectedStatus == 'Terminated' ? Colors.red.shade700 : primaryColor,
  ),
  onPressed: () {
    if (reasonController.text.trim().isEmpty) {
      _showSnack('A reason is required.', Colors.orange);
      return;
    }
    Navigator.pop(dialogContext, true); // يسكر فوراً — منيح
  },
  child: const Text('Confirm'),
),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiConfig.dio.patch('/staff/$_staffId/lifecycle', data: {
        'new_status': selectedStatus,
        'effective_date': dateController.text,
        'reason': reasonController.text.trim(),
      });
      if (!mounted) return;
      setState(() => _currentStatus = selectedStatus);
      _showSnack('Status updated to $selectedStatus', Colors.green.shade700);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to update status') : 'Failed to update status';
      _showSnack(msg, Colors.red);
    }
  }

  Future<void> _openAssignSiteDialog() async {
    if (_currentStatus == 'Terminated') {
      _showSnack('Cannot assign a terminated staff member to a site.', Colors.orange);
      return;
    }
    int? selectedSiteId;
    final dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign to Site'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedSiteId,
                  decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                  items: _sites
                      .map<DropdownMenuItem<int>>((s) => DropdownMenuItem(
                            value: s['site_id'] as int,
                            child: Text(s['site_name'] ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedSiteId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Effective Date', border: OutlineInputBorder()),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      dateController.text = picked.toIso8601String().split('T')[0];
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (selectedSiteId == null) {
                  _showSnack('Please select a site.', Colors.orange);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedSiteId == null) return;

    try {
      await ApiConfig.dio.post('/staff/$_staffId/assignments', data: {
        'site_id': selectedSiteId,
        'assigned_date': dateController.text,
        'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      });
      if (!mounted) return;
      _showSnack('Staff member assigned successfully', Colors.green.shade700);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to assign staff member') : 'Failed to assign staff member';
      _showSnack(msg, Colors.red);
    }
  }

  Future<void> _unassignCurrentSite() async {
    final lastDay = await pickLastAssignedDay(
      context,
      title: 'Unassign from Site',
      message: 'This staff member will no longer be tied to a fixed site after the last day.',
    );
    if (lastDay == null) return;

    try {
      await ApiConfig.dio.delete('/staff/$_staffId/assignments/current', data: {'last_day': lastDay});
      if (!mounted) return;
      _showSnack('Staff member unassigned from site', Colors.blue);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to unassign') : 'Failed to unassign';
      _showSnack(msg, Colors.red);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green.shade700;
      case 'Inactive':
        return Colors.orange.shade800;
      case 'Terminated':
        return AppColors.danger;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOpenAssignment = _assignmentHistory.any((a) => a['unassigned_date'] == null);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(title: '${widget.staff['full_name'] ?? 'Staff'} — Lifecycle'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                     Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: _statusColor(_currentStatus).withOpacity(0.1),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    _currentStatus,
    style: TextStyle(
      color: _statusColor(_currentStatus),
      fontWeight: FontWeight.bold,
    ),
  ),
),

if (_isReturningEmployee) ...[
  const SizedBox(width: 8),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Returning employee',
      style: TextStyle(
        color: Colors.blue,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    ),
  ),
],

const Spacer(),
                          ElevatedButton.icon(
  onPressed: _openStatusChangeDialog,
  icon: const Icon(Icons.sync_alt, size: 18),
  label: Text(_currentStatus == 'Terminated' ? 'Reactivate' : 'Change Status'),
  style: ElevatedButton.styleFrom(
    backgroundColor: _currentStatus == 'Terminated' ? Colors.green.shade700 : primaryColor,
  ),
),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Site Assignment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
                      ),
                      if (hasOpenAssignment)
                        TextButton.icon(
                          onPressed: _unassignCurrentSite,
                          icon: const Icon(Icons.link_off, size: 16, color: Colors.orange),
                          label: const Text('Unassign', style: TextStyle(color: Colors.orange)),
                        ),
                      TextButton.icon(
                        onPressed: _openAssignSiteDialog,
                        icon: const Icon(Icons.add_location_alt, size: 16),
                        label: const Text('Assign'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppDataTableCard(
                    title: 'Assignment History',
                    icon: Icons.location_on_outlined,
                    accentColor: primaryColor,
                    emptyMessage: 'No site assignments recorded yet.',
                    columns: const [
                      DataColumn(label: Text('Site')),
                      DataColumn(label: Text('From')),
                      DataColumn(label: Text('To')),
                      DataColumn(label: Text('Notes')),
                    ],
                    rows: _assignmentHistory.map((a) {
                      return DataRow(cells: [
                        DataCell(Text(a['site_name'] ?? '')),
                        DataCell(Text('${a['assigned_date'] ?? ''}'.split('T')[0])),
                        DataCell(Text(a['unassigned_date'] == null ? 'Present' : '${a['unassigned_date']}'.split('T')[0])),
                        DataCell(Text(a['notes'] ?? '-')),
                      ]);
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text('Status History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  AppDataTableCard(
                    title: 'Status Changes',
                    icon: Icons.history,
                    accentColor: primaryColor,
                    emptyMessage: 'No status changes recorded yet.',
                    columns: const [
                      DataColumn(label: Text('From')),
                      DataColumn(label: Text('To')),
                      DataColumn(label: Text('Effective')),
                      DataColumn(label: Text('Reason')),
                      DataColumn(label: Text('By')),
                    ],
                    rows: _statusHistory.map((h) {
                      return DataRow(cells: [
                        DataCell(Text(h['old_status'] ?? '-')),
                        DataCell(StatusBadge.fromStatus(h['new_status'] ?? '')),
                        DataCell(Text('${h['effective_date'] ?? ''}'.split('T')[0])),
                        DataCell(SizedBox(width: 160, child: Text(h['reason'] ?? '-', overflow: TextOverflow.ellipsis))),
                        DataCell(Text(h['changed_by_name'] ?? '-')),
                      ]);
                    }).toList(),
                  ),
                ],
              ),
            ),
    );
  }
}