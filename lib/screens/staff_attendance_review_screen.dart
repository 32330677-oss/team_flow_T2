import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/help_tip.dart';

class StaffAttendanceReviewScreen extends StatefulWidget {
  const StaffAttendanceReviewScreen({super.key});

  @override
  State<StaffAttendanceReviewScreen> createState() => _StaffAttendanceReviewScreenState();
}

typedef _DateGroups = Map<String, List<Map<String, dynamic>>>;

class _StaffAttendanceReviewScreenState extends State<StaffAttendanceReviewScreen> {
  final Set<int> _selectedIds = <int>{};
  _DateGroups _grouped = {};
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await ApiConfig.dio.get('/staff-attendance/pending');
      final raw = response.data is Map ? response.data['data'] : null;

      final byDate = <String, List<Map<String, dynamic>>>{};
      if (raw is List) {
        for (final value in raw) {
          if (value is! Map) continue;
          final item = Map<String, dynamic>.from(value);
          final rawDate = '${item['record_date'] ?? '1970-01-01'}';
          final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
          byDate.putIfAbsent(date, () => <Map<String, dynamic>>[]);
          byDate[date]!.add(item);
        }
      }

      final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
      final ordered = <String, List<Map<String, dynamic>>>{};
      for (final date in sortedDates) {
        ordered[date] = byDate[date]!;
      }

      if (!mounted) return;
      setState(() {
        _grouped = ordered;
        _selectedIds.clear();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(_errorMessage(e, 'Failed to load staff attendance records.'), false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Failed to load staff attendance records.', false);
    }
  }

  String _errorMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return '${data['message']}';
    return fallback;
  }

  List<int> _idsOf(List<Map<String, dynamic>> items) {
    return items
        .map((item) => int.tryParse('${item['staff_attendance_id']}'))
        .whereType<int>()
        .toList();
  }

  Map<String, dynamic>? _itemById(int id) {
    for (final list in _grouped.values) {
      for (final item in list) {
        if ('${item['staff_attendance_id']}' == '$id') return item;
      }
    }
    return null;
  }

  bool _hasOpenAnomaly(Map<String, dynamic>? i) =>
      i != null && i['anomaly_code'] != null && i['anomaly_ack_at'] == null;

  Future<String?> _askText(String title, String message, String label, {int minLen = 5}) async {
    final ctrl = TextEditingController();
    String? err;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 2,
                decoration: InputDecoration(labelText: label, errorText: err, border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().length < minLen) {
                  setD(() => err = 'Min. $minLen characters');
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return r;
  }

  /// D-11: Sick / Vacation / Holiday is NOT paid automatically. The Admin
  /// decides explicitly; the decision is audited.
  Future<void> _setPaid(int id, bool paid) async {
    final reason = await _askText(
      paid ? 'Mark as paid' : 'Mark as unpaid',
      paid
          ? 'This day will be paid in staff payroll. Your name, the time and the reason are recorded.'
          : 'This day will not be paid in staff payroll.',
      'Reason (required)',
      minLen: 3,
    );
    if (reason == null) return;
    try {
      final r = await ApiConfig.dio.post('/staff-attendance/admin/$id/paid', data: {'is_paid': paid, 'reason': reason});
      _showMessage((r.data is Map ? r.data['message'] : null)?.toString() ?? 'Saved', true);
      await _fetchData();
    } on DioException catch (e) {
      _showMessage(_errorMessage(e, 'Failed to save the paid decision.'), false);
    }
  }

  Future<void> _reviewSelected(List<int> ids, String status, {String? note}) async {
    if (ids.isEmpty || _working) return;

    String? ackNote;
    if (status == 'Approved') {
      final flagged = ids.map(_itemById).where(_hasOpenAnomaly).toList();
      if (flagged.isNotEmpty) {
        ackNote = await _askText(
          'Records need review',
          '${flagged.length} record(s) are flagged (${flagged.first?['anomaly_detail'] ?? 'long session'}). '
              'Approve only after checking the times.',
          'Review note (required)',
        );
        if (ackNote == null) return;
      }
    }

    setState(() => _working = true);

    final succeeded = <int>[];
    final failed = <int>[];
    String? firstError;
    for (final id in ids) {
      try {
        final flagged = _hasOpenAnomaly(_itemById(id));
        await ApiConfig.dio.post('/staff-attendance/review', data: {
          'staff_attendance_id': id,
          'status': status,
          'admin_note': note,
          if (flagged && ackNote != null) 'acknowledge_anomaly': true,
          if (flagged && ackNote != null) 'anomaly_note': ackNote,
        });
        succeeded.add(id);
      } on DioException catch (e) {
        failed.add(id);
        firstError ??= _errorMessage(e, 'Request failed');
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() => _working = false);
    if (failed.isEmpty) {
      _showMessage('${succeeded.length} record(s) processed successfully.', true);
    } else {
      _showMessage('${succeeded.length} succeeded, ${failed.length} failed.${firstError != null ? ' $firstError' : ''}', false);
    }
    await _fetchData();
  }

  Future<String?> _promptForReason(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejection reason'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Why is this record being rejected?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      color: color.withOpacity(.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(.15), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: Colors.grey.shade700)),
            ])),
          ],
        ),
      ),
    );
  }

  String _timeOnly(dynamic value) {
    if (value == null) return '--:--';
    final text = '$value'.replaceFirst('T', ' ');
    return text.length > 16 ? text.substring(11, 16) : text;
  }

  Widget _statusChip(String status) {
    final rejected = status == 'Rejected';
    final color = rejected ? Colors.red : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  Widget _attendanceStatusChip(String status) {
    Color color;
    switch (status) {
      case 'Absent':
        color = Colors.red;
        break;
      case 'Sick':
        color = Colors.orange;
        break;
      case 'Vacation':
        color = Colors.blue;
        break;
      case 'Holiday':
        color = Colors.purple;
        break;
      default:
        color = Colors.green;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  Widget _staffCard(Map<String, dynamic> item) {
    final id = int.tryParse('${item['staff_attendance_id']}');
    if (id == null) return const SizedBox.shrink();

    final status = '${item['status'] ?? 'Submitted'}';
    final rejected = status == 'Rejected';
    final selected = _selectedIds.contains(id);
    final attendanceStatus = '${item['attendance_status'] ?? 'Present'}';
    final isPresent = attendanceStatus == 'Present';
    final overtimeHours = double.tryParse('${item['overtime_hours'] ?? 0}') ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? Colors.indigo : Colors.grey.shade200, width: selected ? 1.4 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: selected,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                 onChanged: rejected ? null : (v) => setState(() => v == true ? _selectedIds.add(id) : _selectedIds.remove(id)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['full_name'] ?? 'Staff'}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${item['staff_unique_id'] ?? ''}${item['site_name'] != null ? ' • ${item['site_name']}' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _attendanceStatusChip(attendanceStatus),
                if (isPresent) ...[
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.login_rounded, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 3),
                    Text(_timeOnly(item['check_in_time']), style: const TextStyle(fontSize: 12.5)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.logout_rounded, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 3),
                    Text(_timeOnly(item['check_out_time']), style: const TextStyle(fontSize: 12.5)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timelapse_rounded, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 3),
                    Text('${item['regular_hours'] ?? '--'}h', style: const TextStyle(fontSize: 12.5)),
                  ]),
                  if (overtimeHours > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(.10), borderRadius: BorderRadius.circular(20)),
                      child: Text('OT: ${overtimeHours.toStringAsFixed(2)}h',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.deepPurple.shade400)),
                    ),
                ],
              ],
            ),
            if (item['anomaly_code'] != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item['anomaly_ack_at'] == null ? Colors.orange.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.report_problem_rounded, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item['anomaly_ack_at'] == null
                          ? 'Needs review: ${item['anomaly_detail'] ?? item['anomaly_code']}'
                          : 'Reviewed: ${item['anomaly_ack_note'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                  const HelpTip(title: 'Long session', message: HelpTexts.longShift, size: 16),
                ]),
              ),
            ],
            if (['Sick', 'Vacation', 'Holiday'].contains(attendanceStatus)) ...[
              const SizedBox(height: 6),
              Row(children: [
                StatusPill(
                  label: ('${item['is_paid']}' == '1' || item['is_paid'] == true) ? 'Paid' : 'Not paid',
                  color: ('${item['is_paid']}' == '1' || item['is_paid'] == true) ? Colors.green.shade700 : Colors.grey.shade700,
                  icon: Icons.payments_outlined,
                ),
                const SizedBox(width: 4),
                const HelpTip(
                  title: 'Paid leave decision',
                  message: 'Sick, vacation and holiday days are not paid automatically. '
                      'The Admin marks them as paid (or unpaid) explicitly; every decision is recorded.',
                  size: 16,
                ),
                const Spacer(),
                if (status == 'Submitted' || status == 'Approved')
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => _setPaid(id, !('${item['is_paid']}' == '1' || item['is_paid'] == true)),
                    child: Text(('${item['is_paid']}' == '1' || item['is_paid'] == true) ? 'Mark unpaid' : 'Mark as paid'),
                  ),
              ]),
            ],
            if (rejected && item['admin_rejection_notes'] != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('${item['admin_rejection_notes']}', style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
           children: [

  if (!rejected)
    TextButton.icon(
      onPressed: _working ? null : () => _reviewSelected([id], 'Approved'),
      icon: const Icon(Icons.check, size: 16),
      label: const Text('Approve', style: TextStyle(fontSize: 12.5)),
      style: TextButton.styleFrom(
        foregroundColor: Colors.green.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    ),

    if (!rejected && item['source'] != 'Biometric')
    TextButton.icon(
      onPressed: _working
          ? null
          : () async {
              final note = await _promptForReason(context);
              if (note != null && note.trim().isNotEmpty) {
                await _reviewSelected([id], 'Rejected', note: note.trim());
              }
            },
      icon: const Icon(Icons.close, size: 16),
      label: const Text('Reject', style: TextStyle(fontSize: 12.5)),
      style: TextButton.styleFrom(
        foregroundColor: Colors.red.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    ),

],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateSection(String date, List<Map<String, dynamic>> items) {
  final ids = _idsOf(items.where((i) => '${i['status']}' == 'Submitted').toList());
    final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);
    final selected = ids.where(_selectedIds.contains).toList();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.grey.shade200)),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        title: Row(children: [
          Checkbox(
            value: allSelected,
            tristate: true,
            onChanged: (value) => setState(() {
              if (value == true) {
                _selectedIds.addAll(ids);
              } else {
                _selectedIds.removeAll(ids);
              }
            }),
          ),
          Expanded(child: Text(date, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          Text('${items.length} record(s)', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                if (selected.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: _working ? null : () => _reviewSelected(selected, 'Approved'),
                        icon: const Icon(Icons.check, size: 16),
                        label: Text('Approve ${selected.length}', style: const TextStyle(fontSize: 12.5)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                      ),
                      FilledButton.icon(
                        onPressed: _working
                            ? null
                            : () async {
                                final note = await _promptForReason(context);
                                if (note != null && note.trim().isNotEmpty) {
                                  await _reviewSelected(selected, 'Rejected', note: note.trim());
                                }
                              },
                        icon: const Icon(Icons.close, size: 16),
                        label: Text('Reject ${selected.length}', style: const TextStyle(fontSize: 12.5)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      ),
                    ]),
                  ),
                ],
                ...items.map(_staffCard),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _grouped.values.expand((v) => v).toList();
    final pending = allItems.where((i) => '${i['status']}' == 'Submitted').length;
    final rejected = allItems.where((i) => '${i['status']}' == 'Rejected').length;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Staff Attendance Review',
        actions: [
          IconButton(onPressed: _fetchData, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: _grouped.isEmpty
                  ? ListView(children: const [SizedBox(height: 220), Center(child: Text('No staff attendance records to review.'))])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                      children: [
                        LayoutBuilder(builder: (context, constraints) {
                          final cards = [
                            _summaryCard('Submitted', '$pending', Icons.pending_actions, Colors.orange),
                            _summaryCard('Rejected', '$rejected', Icons.warning_amber, Colors.red),
                          ];
                          return constraints.maxWidth < 500
                              ? Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList())
                              : Row(children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])]);
                        }),
                        const SizedBox(height: 10),
                        ..._grouped.entries.map((entry) => _dateSection(entry.key, entry.value)),
                      ],
                    ),
            ),
      bottomNavigationBar: _working ? const LinearProgressIndicator(minHeight: 3) : null,
    );
  }
}