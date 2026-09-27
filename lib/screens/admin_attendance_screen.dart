import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_drawer.dart';
class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

// Date -> Site -> records
typedef _SiteGroups = Map<String, List<Map<String, dynamic>>>;

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  final Set<int> _selectedIds = <int>{};
  Map<String, _SiteGroups> _grouped = {};
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
      final response = await ApiConfig.dio.get('/admin/attendance/pending');
      final raw = response.data is Map ? response.data['data'] : null;

      // date -> site -> [records]
      final byDate = <String, _SiteGroups>{};

      if (raw is List) {
        for (final value in raw) {
          if (value is! Map) continue;
          final item = Map<String, dynamic>.from(value);
          final rawDate = '${item['record_date'] ?? '1970-01-01'}';
          final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
          final siteName = (item['site_name'] ?? 'Unknown Site').toString();

          byDate.putIfAbsent(date, () => <String, List<Map<String, dynamic>>>{});
          byDate[date]!.putIfAbsent(siteName, () => <Map<String, dynamic>>[]);
          byDate[date]![siteName]!.add(item);
        }
      }

      final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
      final ordered = <String, _SiteGroups>{};
      for (final date in sortedDates) {
        final sites = byDate[date]!;
        final sortedSites = sites.keys.toList()..sort();
        final orderedSites = <String, List<Map<String, dynamic>>>{};
        for (final site in sortedSites) {
          orderedSites[site] = sites[site]!;
        }
        ordered[date] = orderedSites;
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
      _showMessage(_errorMessage(e, 'Failed to load attendance records.'), false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Failed to load attendance records.', false);
    }
  }

  String _errorMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return '${data['message']}';
    return fallback;
  }

  List<int> _idsOf(List<Map<String, dynamic>> items) {
    return items
        .map((item) => int.tryParse('${item['attendance_id']}'))
        .whereType<int>()
        .toList();
  }

  Future<void> _reviewSelected(List<int> ids, String status, {String? note}) async {
    if (ids.isEmpty || _working) return;
    setState(() => _working = true);

    final succeeded = <int>[];
    final failed = <int>[];
    for (final id in ids) {
      try {
        await ApiConfig.dio.post('/admin/attendance/review', data: {
          'attendance_id': id,
          'status': status,
          'admin_note': note,
        });
        succeeded.add(id);
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() => _working = false);
    if (failed.isEmpty) {
      _showMessage('${succeeded.length} record(s) processed successfully.', true);
    } else {
      _showMessage('${succeeded.length} succeeded, ${failed.length} failed.', false);
    }
    await _fetchData();
  }

  Future<String?> _promptForReason(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for correction'),
        content: TextField(
            controller: controller,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder())),
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

  // ---------------------------------------------------------------------
  // Management leave: counter-based input (minutes, step 15) instead of a
  // free-text field. Sends decimal hours to the server (minutes / 60),
  // matching the `decimal(4,2)` column and avoiding ambiguous manual entry.
  // ---------------------------------------------------------------------

Future<void> _showManagementLeaveDialog(
  int attendanceId, {
  num currentHours = 0,
  required bool hasCheckIn,
}) async {
  int minutes = ((currentHours * 60) / 15).round() * 15; // snap to nearest 15
  if (minutes < 0) minutes = 0;
  if (minutes > 24 * 60) minutes = 24 * 60;
  final reason = TextEditingController();
  String? reasonError;
 
  String fmt(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
 
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Management leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasCheckIn
                  ? 'Use the counter to set the compensated time (steps of 15 minutes).'
                  : 'This worker has no check-in (Absent/Sick/Vacation/Holiday). '
                      'These hours will be counted directly as working hours, '
                      'so a reason is required.',
              style: TextStyle(
                fontSize: 12,
                color: hasCheckIn ? Colors.grey : Colors.orange.shade800,
                fontWeight: hasCheckIn ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove),
                  onPressed: minutes <= 0
                      ? null
                      : () => setDialogState(() => minutes -= 15),
                ),
                Container(
                  width: 110,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    fmt(minutes),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: minutes >= 24 * 60
                      ? null
                      : () => setDialogState(() => minutes += 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              maxLines: 2,
              onChanged: (_) {
                if (reasonError != null) setDialogState(() => reasonError = null);
              },
              decoration: InputDecoration(
                // Mark as required only when there's no check-in.
                labelText: hasCheckIn ? 'Reason (optional)' : 'Reason *',
                border: const OutlineInputBorder(),
                errorText: reasonError,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!hasCheckIn && reason.text.trim().isEmpty) {
                setDialogState(() => reasonError = 'A reason is required for workers with no check-in.');
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
 
  final reasonValue = reason.text.trim();
  reason.dispose();
  if (result != true) return;
 
  final hoursValue = minutes / 60.0;
 
  try {
    final response = await ApiConfig.dio.patch('/attendance/$attendanceId/management-leave', data: {
      'hours': hoursValue,
      'reason': reasonValue,
    });
 
    if (!mounted) return;
    _showMessage('Management leave saved (${fmt(minutes)}).', true);
 
    // Server returns a `warning` when the shift is still open (check-in
    // without check-out): the hours were saved but not yet reflected in
    // total_working_hours until checkout happens.
    final warning = response.data is Map ? response.data['warning'] : null;
    if (warning != null && '$warning'.trim().isNotEmpty) {
      // Slight delay so it doesn't collide with the success snackbar above.
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _showMessage('$warning', false);
      });
    }
 
    await _fetchData();
  } on DioException catch (e) {
    if (mounted) _showMessage(_errorMessage(e, 'Failed to save management leave.'), false);
  }
}

  Future<void> _showSettingsDialog() async {
    bool lunchPaid = false;
    int minutes = 480;
    try {
      final response = await ApiConfig.dio.get('/admin/attendance/settings/breaks');
      final data = response.data is Map ? response.data['data'] : null;
      if (data is Map) {
        lunchPaid = '${data['is_lunch_paid']}'.toLowerCase() == 'true';
        minutes = int.tryParse('${data['standard_work_minutes']}') ?? 600;
      }
    } catch (_) {
      if (mounted) _showMessage('Failed to load settings.', false);
      return;
    }
    if (!mounted) return;

    final minutesController = TextEditingController(text: '$minutes');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Attendance settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lunch is paid'),
                value: lunchPaid,
                onChanged: (value) => setDialogState(() => lunchPaid = value),
              ),
              TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Standard work minutes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final value = int.tryParse(minutesController.text.trim());
                if (value == null || value <= 0 || value > 1440) {
                  _showMessage('Minutes must be between 1 and 1440.', false);
                  return;
                }
                try {
                  await ApiConfig.dio.put('/admin/attendance/settings/breaks', data: {
                    'is_lunch_paid': lunchPaid,
                    'standard_work_minutes': value,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) _showMessage('Settings updated.', true);
                } on DioException catch (e) {
                  if (mounted) _showMessage(_errorMessage(e, 'Failed to update settings.'), false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    minutesController.dispose();
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

  // Compact per-worker card. Shows an Overtime badge only when overtime_hours > 0.
  Widget _workerCard(Map<String, dynamic> item) {
    final id = int.tryParse('${item['attendance_id']}');
    if (id == null) return const SizedBox.shrink();

    final status = '${item['status'] ?? item['attendance_status'] ?? 'Submitted'}';
    final rejected = status == 'Rejected';
    final selected = _selectedIds.contains(id);

    final overtimeHours = double.tryParse('${item['overtime_hours'] ?? 0}') ?? 0;
    final hasOvertime = overtimeHours > 0;
    final managementHours = double.tryParse('${item['management_leave_hours'] ?? 0}') ?? 0;

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
                  onChanged: (v) => setState(() => v == true ? _selectedIds.add(id) : _selectedIds.remove(id)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${item['full_name'] ?? 'Worker'}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.login_rounded, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 3),
                Text(_timeOnly(item['check_in_time']), style: const TextStyle(fontSize: 12.5)),
                const SizedBox(width: 12),
                Icon(Icons.logout_rounded, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 3),
                Text(_timeOnly(item['check_out_time']), style: const TextStyle(fontSize: 12.5)),
                const SizedBox(width: 12),
                Icon(Icons.timelapse_rounded, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 3),
                Text('${item['total_working_hours'] ?? '--'}h', style: const TextStyle(fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // Overtime indicator — only rendered when > 0.
                if (hasOvertime)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 12, color: Colors.deepPurple.shade400),
                        const SizedBox(width: 3),
                        Text(
                          'Overtime: ${overtimeHours.toStringAsFixed(2)}h',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.deepPurple.shade400),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('No overtime', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ),
                if (managementHours > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Mgmt leave: ${managementHours.toStringAsFixed(2)}h',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.teal.shade700),
                    ),
                  ),
              ],
            ),
            if (rejected && item['admin_rejection_notes'] != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${item['admin_rejection_notes']}',
                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                ),
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
                    style: TextButton.styleFrom(foregroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ),
                TextButton.icon(
                  onPressed: _working
                      ? null
                      : () async {
                          final note = await _promptForReason(context);
                          if (note != null) await _reviewSelected([id], 'Rejected', note: note);
                        },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject', style: TextStyle(fontSize: 12.5)),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700, padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
     IconButton(
  tooltip: 'Management leave',
  visualDensity: VisualDensity.compact,
  icon: const Icon(Icons.more_time_rounded, size: 19, color: Colors.teal),
  onPressed: () => _showManagementLeaveDialog(
    id,
    currentHours: managementHours,
    hasCheckIn: item['check_in_time'] != null,
  ),
),
              ],
            ),
          ],
        ),
      ),
    );
  }

Widget _siteSection(String date, String siteName, List<Map<String, dynamic>> items) {
  final ids = _idsOf(items);
  final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);

  final shiftGroups = <String, List<Map<String, dynamic>>>{};

  for (final item in items) {
    final shift = item['shift_type'] == 'Night' ? 'Night' : 'Day';
    shiftGroups.putIfAbsent(shift, () => []).add(item);
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: allSelected,
              tristate: true,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => setState(() {
                if (value == true) {
                  _selectedIds.addAll(ids);
                } else {
                  _selectedIds.removeAll(ids);
                }
              }),
            ),
            Icon(
              Icons.location_on,
              size: 15,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                siteName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${items.length}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11.5,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        ...shiftGroups.entries.map((entry) {
          final shiftType = entry.key;
          final shiftItems = entry.value;

          final shiftIds = _idsOf(shiftItems);
          final shiftSelected =
              shiftIds.isNotEmpty && shiftIds.every(_selectedIds.contains);

          final selected = shiftIds
              .where(_selectedIds.contains)
              .toList();

          final overtimeCount = shiftItems.where(
            (i) =>
                (double.tryParse(
                      '${i['overtime_hours'] ?? 0}',
                    ) ??
                    0) >
                0,
          ).length;

          final isNight = shiftType == 'Night';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: shiftSelected,
                      tristate: true,
                      visualDensity: VisualDensity.compact,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selectedIds.addAll(shiftIds);
                        } else {
                          _selectedIds.removeAll(shiftIds);
                        }
                      }),
                    ),
                    Icon(
                      isNight
                          ? Icons.nightlight_outlined
                          : Icons.wb_sunny_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      shiftType,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${shiftItems.length}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    if (overtimeCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$overtimeCount OT',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.deepPurple.shade400,
                          ),
                        ),
                      ),
                  ],
                ),

                if (selected.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          onPressed: _working
                              ? null
                              : () => _reviewSelected(
                                    selected,
                                    'Approved',
                                  ),
                          icon: const Icon(Icons.check, size: 15),
                          label: Text(
                            'Approve ${selected.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _working
                              ? null
                              : () async {
                                  final note =
                                      await _promptForReason(context);
                                  if (note != null) {
                                    await _reviewSelected(
                                      selected,
                                      'Rejected',
                                      note: note,
                                    );
                                  }
                                },
                          icon: const Icon(Icons.close, size: 15),
                          label: Text(
                            'Reject ${selected.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 8),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth > 700 ? 2 : 1;

                    if (columns == 1) {
                      return Column(
                        children: shiftItems.map(_workerCard).toList(),
                      );
                    }

                    final cardWidth = (constraints.maxWidth - 8) / 2;

                    return Wrap(
                      spacing: 8,
                      runSpacing: 0,
                      children: shiftItems
                          .map(
                            (item) => SizedBox(
                              width: cardWidth,
                              child: _workerCard(item),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        }),
      ],
    ),
  );
}

  Widget _dateSection(String date, _SiteGroups sites) {
    final allItemsForDate = sites.values.expand((v) => v).toList();
    final ids = _idsOf(allItemsForDate);
    final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);

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
          Text('${allItemsForDate.length} records • ${sites.length} sites', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: sites.entries.map((e) => _siteSection(date, e.key, e.value)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _grouped.values.expand((sites) => sites.values.expand((v) => v)).toList();
    final pending = allItems.where((i) => '${i['status']}' == 'Submitted').length;
    final rejected = allItems.where((i) => '${i['status']}' == 'Rejected').length;
    final overtimeTotal = allItems.where((i) => (double.tryParse('${i['overtime_hours'] ?? 0}') ?? 0) > 0).length;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Admin Attendance Review',
        actions: [
          IconButton(onPressed: _showSettingsDialog, icon: const Icon(Icons.tune), tooltip: 'Settings'),
          IconButton(onPressed: _fetchData, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: _grouped.isEmpty
                  ? ListView(children: const [SizedBox(height: 220), Center(child: Text('No attendance records to review.'))])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                      children: [
                        LayoutBuilder(builder: (context, constraints) {
                          final cards = [
                            _summaryCard('Submitted', '$pending', Icons.pending_actions, Colors.orange),
                            _summaryCard('Rejected', '$rejected', Icons.warning_amber, Colors.red),
                            _summaryCard('With Overtime', '$overtimeTotal', Icons.bolt_rounded, Colors.deepPurple),
                          ];
                          return constraints.maxWidth < 650
                              ? Column(children: cards.map((card) => Padding(padding: const EdgeInsets.only(bottom: 8), child: card)).toList())
                              : Row(children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1]), const SizedBox(width: 10), Expanded(child: cards[2])]);
                        }),
                        const SizedBox(height: 10),
                        ..._grouped.entries.map((entry) => _dateSection(entry.key, entry.value)),
                      ],
                    ),
            ),
      bottomNavigationBar: _working
          ? const LinearProgressIndicator(minHeight: 3)
          : null,
    );
  }
}