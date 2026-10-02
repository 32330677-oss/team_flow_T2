import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/biometric_processing_service.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/help_tip.dart';

/// C-14: manage existing device ID mappings (list, End, Void, Impact, Re-queue).
/// Nothing is deleted: End sets the last valid date, Void deactivates the
/// mapping; both are audited by the backend and require a reason.
class DeviceMappingsManageScreen extends StatefulWidget {
  const DeviceMappingsManageScreen({super.key});

  @override
  State<DeviceMappingsManageScreen> createState() => _DeviceMappingsManageScreenState();
}

class _DeviceMappingsManageScreenState extends State<DeviceMappingsManageScreen> {
  final _search = TextEditingController();
  final _processing = BiometricProcessingService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _activeOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _date(dynamic v) {
    if (v == null) return '';
    final s = '$v';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _err(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      return (e.response?.data['message'] ?? fallback).toString();
    }
    if (e is BiometricApiException) return e.message;
    return fallback;
  }

  void _snack(String m, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiConfig.dio.get('/biometric/device-users', queryParameters: {
        if (_activeOnly) 'active': '1',
      });
      final list = (r.data is Map ? r.data['data'] : null) as List? ?? [];
      setState(() => _rows = list.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      _snack(_err(e, 'Failed to load mappings.'), ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((m) {
      final name = '${m['worker_name'] ?? m['staff_name'] ?? ''}'.toLowerCase();
      return '${m['device_employee_id']}'.contains(q) || name.contains(q);
    }).toList();
  }

  Future<String?> _reason(String title, String message) async {
    final c = TextEditingController();
    String? err;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                maxLines: 2,
                decoration: InputDecoration(labelText: 'Reason (required)', errorText: err, border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (c.text.trim().length < 3) {
                  setD(() => err = 'Please enter a reason');
                  return;
                }
                Navigator.pop(ctx, c.text.trim());
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _end(Map<String, dynamic> m) async {
    final from = DateTime.tryParse(_date(m['effective_from'])) ?? DateTime(2020);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: 'Last day this mapping is valid',
      initialDate: now.isBefore(from) ? from : DateTime(now.year, now.month, now.day),
      firstDate: from,
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    final day = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    final reason = await _reason('End mapping', 'Device ID ${m['device_employee_id']} stays mapped up to and including $day. '
        'Punches after that date will need a new mapping.');
    if (reason == null) return;
    try {
      await ApiConfig.dio.patch('/biometric/device-users/${m['id']}/end', data: {'effective_to': day, 'reason': reason});
      _snack('Mapping ended (last day $day).');
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed to end the mapping.'), ok: false);
    }
  }

  Future<void> _void(Map<String, dynamic> m) async {
    final reason = await _reason('Void mapping',
        'Use only for a mapping created by mistake. It is kept in the history as inactive. '
        'Check "Impact" first: punches already applied through it are not changed automatically.');
    if (reason == null) return;
    try {
      await ApiConfig.dio.patch('/biometric/device-users/${m['id']}/void', data: {'reason': reason});
      _snack('Mapping voided.');
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed to void the mapping.'), ok: false);
    }
  }

  Future<void> _impact(Map<String, dynamic> m) async {
    Map<String, dynamic> data;
    try {
      data = await _processing.getMappingImpact(int.parse('${m['id']}'));
    } catch (e) {
      _snack(_err(e, 'Failed to load impact.'), ok: false);
      return;
    }
    if (!mounted) return;
    final punches = (data['punches'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final records = (data['affected_records'] as List? ?? []);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Impact — device ID ${m['device_employee_id']}'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${punches.length} punch(es) processed with this mapping • ${records.length} attendance record(s) touched'),
            const SizedBox(height: 8),
            Flexible(
              child: punches.isEmpty
                  ? const Text('No punches used this mapping.')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: punches.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = punches[i];
                        return ListTile(
                          dense: true,
                          title: Text('${p['punched_at']} · ${p['punch_type'] ?? ''}'),
                          subtitle: Text('${p['processing_status']} · ${p['processing_result'] ?? ''}'),
                          trailing: p['can_requeue'] == true
                              ? TextButton(
                                  onPressed: () async {
                                    final reason = await _reason('Re-queue punch',
                                        'The punch is processed again with the mapping valid on its own date.');
                                    if (reason == null) return;
                                    try {
                                      final msg = await _processing.requeueItem(int.parse('${p['punch_id']}'), reason);
                                      _snack(msg);
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    } catch (e) {
                                      _snack(_err(e, 'Failed to re-queue.'), ok: false);
                                    }
                                  },
                                  child: const Text('Re-queue'),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Existing Device Mappings',
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search device ID or name',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Active only'),
              selected: _activeOnly,
              onSelected: (v) {
                setState(() => _activeOnly = v);
                _load();
              },
            ),
            const HelpTip(
              title: 'Device mappings',
              message: 'A mapping links a device employee ID to one worker or staff member for a date range. '
                  'End = the mapping stops after a given last day (e.g. the person left). '
                  'Void = the mapping was wrong from the start. Impact shows punches already processed with it; '
                  'punches that now resolve to a different person can be re-queued.',
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const Center(child: Text('No mappings found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final m = rows[i];
                        final active = '${m['active']}' == '1' || m['active'] == true;
                        final name = m['worker_name'] ?? m['staff_name'] ?? '-';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColorsLocal.primary.withOpacity(.1),
                                  child: Text('${m['device_employee_id']}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('$name', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${m['entity_type']} · ${_date(m['effective_from'])} → ${m['effective_to'] == null ? 'open' : _date(m['effective_to'])}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                  ]),
                                ),
                                StatusPill(label: active ? 'Active' : 'Void', color: active ? Colors.green.shade700 : Colors.grey),
                              ]),
                              const SizedBox(height: 6),
                              Wrap(spacing: 4, alignment: WrapAlignment.end, children: [
                                TextButton.icon(
                                  onPressed: () => _impact(m),
                                  icon: const Icon(Icons.query_stats, size: 16),
                                  label: const Text('Impact'),
                                ),
                                if (active)
                                  TextButton.icon(
                                    onPressed: () => _end(m),
                                    icon: const Icon(Icons.event_busy, size: 16),
                                    label: const Text('End'),
                                  ),
                                if (active)
                                  TextButton.icon(
                                    onPressed: () => _void(m),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                                    icon: const Icon(Icons.block, size: 16),
                                    label: const Text('Void'),
                                  ),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class AppColorsLocal {
  static const Color primary = Color(0xFF1A2A6C);
}
