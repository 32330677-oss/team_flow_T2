import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/biometric_processing_service.dart';
import '../widgets/app_data_table.dart';
import '../widgets/custom_app_bar.dart';

/// B4 — Lunch for BIOMETRIC staff records (Admin).
/// The device has no lunch punches, so the Admin applies the lunch window
/// explicitly. Nothing is applied automatically. Only Draft records change.
class StaffLunchDeductionScreen extends StatefulWidget {
  final DateTime? initialDate;
  const StaffLunchDeductionScreen({super.key, this.initialDate});

  @override
  State<StaffLunchDeductionScreen> createState() => _StaffLunchDeductionScreenState();
}

class _StaffLunchDeductionScreenState extends State<StaffLunchDeductionScreen> {
  final _service = BiometricProcessingService();
  late DateTime _date = widget.initialDate ?? DateTime.now();
  List<Map<String, dynamic>> _rows = [];
  final Set<int> _selected = <int>{};
  bool _loading = true;
  bool _saving = false;
  TimeOfDay _start = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 13, minute: 0);

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);
  String _t(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _service.getStaffLunchDay(_dateStr);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _selected.removeWhere((id) => !rows.any((r) => _id(r) == id && r['editable'] == true));
        _loading = false;
      });
    } on BiometricApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e.message, Colors.red);
    }
  }

  int _id(Map<String, dynamic> r) => int.tryParse('${r['staff_attendance_id']}') ?? 0;

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Future<void> _apply({required bool remove, bool useDefault = false}) async {
    if (_selected.isEmpty || _saving) return;
    final start = useDefault ? '12:00' : _t(_start);
    final end = useDefault ? '13:00' : _t(_end);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(remove ? 'Remove lunch' : 'Apply lunch'),
        content: Text(remove
            ? 'Remove the lunch window from ${_selected.length} record(s) on $_dateStr?'
            : 'Apply lunch $start – $end to ${_selected.length} record(s) on $_dateStr? '
                'Hours are recalculated for records that already have a check-out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final msg = await _service.applyStaffLunch(
        date: _dateStr,
        staffAttendanceIds: _selected.toList(),
        lunchStart: remove ? null : start,
        lunchEnd: remove ? null : end,
        remove: remove,
      );
      _snack(msg, Colors.green.shade700);
      _selected.clear();
      await _load();
    } on BiometricApiException catch (e) {
      _snack(e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _hm(dynamic v) {
    final s = v?.toString();
    if (s == null || s.length < 16) return '--:--';
    return s.replaceFirst('T', ' ').substring(11, 16);
  }

  @override
  Widget build(BuildContext context) {
    final editableIds = _rows.where((r) => r['editable'] == true).map(_id).toSet();
    final allSelected = editableIds.isNotEmpty && _selected.length == editableIds.length;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(title: 'Staff Lunch (Biometric)', actions: [
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(DateFormat('EEE, dd MMM yyyy').format(_date)),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context, initialDate: _date, firstDate: DateTime(2023), lastDate: DateTime.now());
                    if (d != null) {
                      setState(() {
                        _date = d;
                        _selected.clear();
                      });
                      _load();
                    }
                  },
                ),
                OutlinedButton(
                  onPressed: () async {
                    final v = await showTimePicker(context: context, initialTime: _start);
                    if (v != null) setState(() => _start = v);
                  },
                  child: Text('From ${_t(_start)}'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final v = await showTimePicker(context: context, initialTime: _end);
                    if (v != null) setState(() => _end = v);
                  },
                  child: Text('To ${_t(_end)}'),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _selected.isEmpty || _saving ? null : () => _apply(remove: false, useDefault: true),
                  icon: const Icon(Icons.restaurant, size: 16),
                  label: Text('Apply default 12:00–13:00 (${_selected.length})'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _selected.isEmpty || _saving ? null : () => _apply(remove: false),
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text('Apply ${_t(_start)}–${_t(_end)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _selected.isEmpty || _saving ? null : () => _apply(remove: true),
                  icon: const Icon(Icons.no_meals, size: 16),
                  label: const Text('Remove lunch'),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Only biometric staff records in Draft can change. Lunch must be inside the shift.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  CheckboxListTile(
                    value: allSelected,
                    onChanged: editableIds.isEmpty
                        ? null
                        : (v) => setState(() {
                              _selected.clear();
                              if (v == true) _selected.addAll(editableIds);
                            }),
                    title: Text('Select all (${editableIds.length} editable of ${_rows.length})'),
                  ),
                  const Divider(height: 1),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No biometric staff attendance for this date.'),
                    ),
                  for (final r in _rows)
                    CheckboxListTile(
                      value: _selected.contains(_id(r)),
                      onChanged: r['editable'] == true
                          ? (v) => setState(() {
                                if (v == true) {
                                  _selected.add(_id(r));
                                } else {
                                  _selected.remove(_id(r));
                                }
                              })
                          : null,
                      title: Text('${r['full_name']}'),
                      subtitle: Text(
                        'In ${_hm(r['check_in_time'])} → Out ${r['check_out_time'] == null ? 'missing' : _hm(r['check_out_time'])} • '
                        '${r['lunch_applied'] == true ? 'Lunch ${_hm(r['lunch_start_time'])}–${_hm(r['lunch_end_time'])}' : 'Lunch pending'} • '
                        '${r['status']}',
                      ),
                      secondary: StatusBadge(
                        label: r['lunch_applied'] == true ? 'Applied' : 'Pending',
                        color: r['lunch_applied'] == true ? Colors.green.shade700 : Colors.orange.shade800,
                      ),
                    ),
                ]),
              ),
            ]),
    );
  }
}
