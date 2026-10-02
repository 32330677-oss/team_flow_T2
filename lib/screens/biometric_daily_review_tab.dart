import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/biometric_processing_service.dart';
import '../widgets/app_data_table.dart';
import 'biometric_processing_screen.dart' show showBiometricEditTimesDialog;
import 'device_id_mapping_screen.dart';
import 'staff_lunch_deduction_screen.dart';

/// Phase 2 — Biometric Daily Review.
///
/// Everything the processor could not decide safely is shown here with its
/// reason, the mapping used, the related attendance record, and ONLY the
/// actions that are valid for that item (computed by the backend).
class BiometricDailyReviewTab extends StatefulWidget {
  const BiometricDailyReviewTab({super.key});

  @override
  State<BiometricDailyReviewTab> createState() => _BiometricDailyReviewTabState();
}

class _BiometricDailyReviewTabState extends State<BiometricDailyReviewTab>
    with AutomaticKeepAliveClientMixin {
  final _service = BiometricProcessingService();

  DateTime _date = DateTime.now();
  bool _unresolvedOnly = false;
  bool _loading = true;
  bool _working = false;
  String? _error;
  DailyReview? _review;
  final Set<int> _selected = <int>{};

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.getDailyReview(_dateStr, unresolvedOnly: _unresolvedOnly);
      if (!mounted) return;
      setState(() {
        _review = r;
        _selected.removeWhere((id) => !r.items.any((i) => i.punchId == id));
        _loading = false;
      });
    } on BiometricApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      helpText: 'Review punches of this date',
    );
    if (d != null) {
      setState(() => _date = d);
      _load();
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Future<String?> _askText(String title, String label, {bool required = true, String? hint}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hint != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(hint, style: const TextStyle(fontSize: 12.5))),
          TextField(
            controller: c,
            maxLines: 2,
            autofocus: true,
            decoration: InputDecoration(labelText: required ? '$label *' : label, border: const OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (required && c.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _runAction(Future<String> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final msg = await action();
      _snack(msg, Colors.green.shade700);
      await _load();
    } on BiometricApiException catch (e) {
      _snack(e.message, e.statusCode == 409 ? Colors.orange.shade800 : Colors.red);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _onAction(ReviewItem item, String action) async {
    if (action == 'retry') {
      await _runAction(() => _service.retryItem(item.punchId));
    } else if (action == 'use_as_checkout') {
      final t = item.target;
      if (t == null) return;
      final reason = await _askText('Use as Checkout', 'Reason', required: false,
          hint: 'Apply the ${item.punchType} at ${_hm(item.punchedAt)} as the check-out of '
              '${t.fullName}\'s session that started ${_fmt(t.checkIn)}.');
      if (reason == null) return;
      await _runAction(() => _service.useAsCheckout(item.punchId, t.recordId, reason: reason));
    } else if (action == 'keep_as_new_in') {
      final reason = await _askText('Keep as New IN', 'Reason', required: false,
          hint: 'Create a new session from this IN. The previous session stays open (missing checkout).');
      if (reason == null) return;
      await _runAction(() => _service.keepAsNewIn(item.punchId, reason: reason));
    } else if (action == 'mark_duplicate') {
      final note = await _askText('Mark as Duplicate', 'Note', required: false,
          hint: 'The punch is closed as a duplicate. Attendance is not changed.');
      if (note == null) return;
      await _runAction(() => _service.markDuplicate(item.punchId, note: note));
    } else if (action == 'dismiss') {
      final note = await _askText('Dismiss', 'Why is this punch dismissed?',
          hint: 'Attendance is not changed. The punch stays in the history.');
      if (note == null) return;
      await _runAction(() => _service.dismissItems([item.punchId], note));
    } else if (action == 'review_later') {
      final note = await _askText('Review Later', 'Note');
      if (note == null) return;
      await _runAction(() => _service.reviewLater(item.punchId, note));
    } else if (action == 'enter_checkout') {
      final t = item.target;
      if (t == null) return;
      final saved = await showBiometricEditTimesDialog(
        context,
        service: _service,
        isWorker: t.isWorker,
        recordId: t.recordId,
        fullName: t.fullName,
        checkIn: t.checkIn,
        checkOut: t.checkOut,
        status: t.status,
        fallbackDate: _date,
      );
      if (saved) await _load();
    } else if (action == 'restore_for_processing') {
      final reason = await _askText('Restore for processing', 'Reason',
          hint: 'This punch is older than the processing window. Restoring lets the next run process it '
              'normally. The decision is recorded.');
      if (reason == null) return;
      await _runAction(() => _service.restoreItem(item.punchId, reason));
    } else if (action == 'requeue') {
      final reason = await _askText('Re-queue punch', 'Reason',
          hint: 'The punch was dismissed while unmapped. It is processed again with the employee mapping valid on its own date.');
      if (reason == null) return;
      await _runAction(() => _service.requeueItem(item.punchId, reason));
    } else if (action == 'map_employee') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceIdMappingScreen()));
      if (mounted) _load();
    }
  }

  Future<void> _bulkDismiss() async {
    if (_selected.isEmpty) return;
    final note = await _askText('Dismiss ${_selected.length} item(s)', 'Reason',
        hint: 'Attendance is not changed. The punches stay in the history.');
    if (note == null) return;
    await _runAction(() => _service.dismissItems(_selected.toList(), note));
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _submitOrphan(Map<String, dynamic> d) async {
    final isWorker = d['target_table'] == 'attendance';
    final recordId = int.tryParse('${d['record_id']}') ?? 0;
    final reason = await _askText('Submit for review', 'Reason',
        hint: '${d['full_name']} — ${d['record_date']}\n'
            'Reason this draft has no reviewer: ${d['orphan_reason'] == 'site_not_active' ? 'site is not Active' : 'no current supervisor'}.\n'
            'The record goes through the normal submission checks and still needs Admin approval.');
    if (reason == null) return;
    if (_working) return;
    setState(() => _working = true);
    try {
      final msg = await _service.adminSubmitForReview(isWorker: isWorker, recordId: recordId, reason: reason);
      _snack(msg, Colors.green.shade700);
      await _load();
    } on BiometricApiException catch (e) {
      if (e.code == 'LUNCH_DECISION_REQUIRED') {
        final decision = await _askLunchDecision(d, e);
        if (decision != null) {
          try {
            final msg = await _service.adminSubmitForReview(
                isWorker: isWorker, recordId: recordId, reason: reason, lunchDecision: decision);
            _snack(msg, Colors.green.shade700);
            await _load();
          } on BiometricApiException catch (e2) {
            _snack(e2.message, Colors.red);
          }
        }
      } else {
        _snack(e.message, e.statusCode == 409 ? Colors.orange.shade800 : Colors.red);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<Map<String, dynamic>?> _askLunchDecision(Map<String, dynamic> d, BiometricApiException e) async {
    final period = e.details['lunch_period'];
    final start = period is Map ? period['start']?.toString() : null;
    final end = period is Map ? period['end']?.toString() : null;
    bool worked = false;
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Lunch confirmation'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['full_name']} has no recorded lunch.'
                '${start != null ? '\nSite lunch: ${_hm(start)} – ${_hm(end)}' : '\nNo site lunch period is recorded for this day.'}'),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: false,
              groupValue: worked,
              onChanged: (v) => setD(() => worked = v ?? false),
              title: const Text('Did not work during lunch (deduct the site lunch)'),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: true,
              groupValue: worked,
              onChanged: (v) => setD(() => worked = v ?? true),
              title: const Text('Worked through lunch'),
            ),
            if (worked)
              TextField(
                controller: reasonCtl,
                decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (worked && reasonCtl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (ok != true) return null;
    return {'worked_through_lunch': worked, if (worked) 'reason': reason};
  }

  Future<void> _enterCheckout(Map<String, dynamic> m) async {
    final saved = await showBiometricEditTimesDialog(
      context,
      service: _service,
      isWorker: m['target_table'] == 'attendance',
      recordId: int.tryParse('${m['record_id']}') ?? 0,
      fullName: '${m['full_name'] ?? ''}',
      checkIn: m['check_in_time']?.toString(),
      checkOut: null,
      status: 'Draft',
      fallbackDate: _date,
    );
    if (saved) await _load();
  }

  // ---------------------------------------------------------------- helpers

  static String _fmt(String? v) {
    if (v == null || v.isEmpty) return '—';
    final s = v.replaceFirst('T', ' ');
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  static String _hm(String? v) {
    if (v == null || v.isEmpty) return '--:--';
    final s = v.replaceFirst('T', ' ');
    return s.length >= 16 ? s.substring(11, 16) : s;
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _section(String title, IconData icon, List<Widget> children, {Widget? trailing, String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          if (trailing != null) trailing,
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger))
          else if (_review != null) ...[
            _counts(_review!),
            const SizedBox(height: 14),
            _itemsSection(_review!),
            _missingCheckoutsSection(_review!),
            _orphanSection(_review!),
            _unmappedSection(_review!),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      OutlinedButton.icon(
        onPressed: _working ? null : _pickDate,
        icon: const Icon(Icons.calendar_today, size: 16),
        label: Text(DateFormat('EEE, dd MMM yyyy').format(_date)),
      ),
      FilterChip(
        label: const Text('All unresolved (any date)'),
        selected: _unresolvedOnly,
        onSelected: _working
            ? null
            : (v) {
                setState(() => _unresolvedOnly = v);
                _load();
              },
      ),
      IconButton(tooltip: 'Refresh', onPressed: _working ? null : _load, icon: const Icon(Icons.refresh)),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => StaffLunchDeductionScreen(initialDate: _date))),
        icon: const Icon(Icons.restaurant, size: 16),
        label: const Text('Staff lunch'),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceIdMappingScreen()));
          if (mounted) _load();
        },
        icon: const Icon(Icons.link, size: 16),
        label: const Text('Device mapping'),
      ),
    ]);
  }

  Widget _counts(DailyReview r) {
    final s = r.byStatus;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Punches of ${r.date}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _pill('Needs review ${s['NeedsReview'] ?? 0}', Colors.deepPurple),
          _pill('Failed ${s['Failed'] ?? 0}', AppColors.danger),
          _pill('Pending ${s['Pending'] ?? 0}', Colors.orange.shade800),
          _pill('Processed ${s['Processed'] ?? 0}', Colors.green.shade700),
          _pill('Informational ${s['Skipped'] ?? 0}', Colors.blueGrey),
          _pill('Invalid ${s['Invalid'] ?? 0}', Colors.brown),
          _pill('Dismissed ${s['Dismissed'] ?? 0}', Colors.grey.shade700),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _pill('Still unresolved (all dates) ${r.stillUnresolvedTotal}', Colors.deepPurple.shade700),
          _pill('Resolved today ${r.resolvedToday}', Colors.teal),
          _pill('Missing checkouts ${r.missingCheckouts.length}', Colors.orange.shade900),
          _pill('Drafts without reviewer ${r.orphanDrafts.length}', Colors.indigo),
          _pill('Unmapped device IDs ${r.unmappedDeviceIds.length}', Colors.red.shade700),
        ]),
        if (r.needsReviewByReason.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Needs review by reason', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in r.needsReviewByReason.entries)
              Tooltip(
                message: explainBiometricResult(e.key),
                child: _pill('${e.key}: ${e.value}', Colors.deepPurple),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _itemsSection(DailyReview r) {
    final dismissable = r.items.where((i) => i.actions.contains('dismiss')).map((i) => i.punchId).toSet();
    return _section(
      'Items to review (${r.items.length})',
      Icons.fact_check_outlined,
      r.items.isEmpty
          ? [const Text('Nothing to review. 🎉', style: TextStyle(color: AppColors.textSecondary))]
          : r.items.map((i) => _itemCard(i, dismissable.contains(i.punchId))).toList(),
      subtitle: 'Only the actions that are valid for each item are shown. Nothing here is decided automatically.',
      trailing: _selected.isEmpty
          ? null
          : FilledButton.icon(
              onPressed: _working ? null : _bulkDismiss,
              style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade800),
              icon: const Icon(Icons.block, size: 16),
              label: Text('Dismiss ${_selected.length}'),
            ),
    );
  }

  Widget _itemCard(ReviewItem i, bool selectable) {
    final failed = i.status == 'Failed';
    final color = failed ? AppColors.danger : Colors.deepPurple;
    final m = i.mapping;
    final t = i.target;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (selectable)
            Checkbox(
              value: _selected.contains(i.punchId),
              onChanged: _working
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _selected.add(i.punchId);
                        } else {
                          _selected.remove(i.punchId);
                        }
                      }),
            ),
          Icon(i.punchType == 'IN' ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${i.punchType} • ${_fmt(i.punchedAt)} • device ${i.deviceEmployeeId}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          StatusBadge(label: failed ? 'Failed' : 'Needs review', color: color),
        ]),
        const SizedBox(height: 6),
        Text(i.explanation, style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 4),
        Text('Reason code: ${i.result ?? '-'} • attempts ${i.attempts} • punch #${i.punchId}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (m != null)
            _pill(
              '${m.entityType}: ${m.personName ?? '?'} • mapping #${m.id} '
              '(${m.effectiveFrom ?? '?'} → ${m.effectiveTo ?? 'open'})'
              '${i.mappingSource == 'current' ? ' • current mapping' : ''}'
              '${m.active ? '' : ' • VOIDED'}',
              Colors.indigo,
            )
          else
            _pill('No mapping for this date', Colors.red.shade700),
          if (i.batchStatus.isNotEmpty && i.batchStatus != 'Completed' && i.batchStatus != 'CompletedWithErrors')
            _pill('Batch ${i.batchStatus}', Colors.orange.shade800),
        ]),
        if (t != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Related record: ${t.fullName} • ${t.recordDate ?? ''}'
              '${t.siteName != null ? ' • ${t.siteName} ${t.shiftType ?? ''}' : ''}\n'
              'In ${_fmt(t.checkIn)} → Out ${t.checkOut == null ? 'missing' : _fmt(t.checkOut)} • '
              '${t.attendanceStatus ?? ''} • ${t.status ?? ''} • ${t.source ?? ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
        if (i.resolutionNote != null) ...[
          const SizedBox(height: 6),
          Text('Note: ${i.resolutionNote}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in i.actions)
            _actionButton(i, a),
        ]),
      ]),
    );
  }

  Widget _actionButton(ReviewItem i, String action) {
    final primary = {'use_as_checkout', 'keep_as_new_in', 'retry', 'map_employee', 'enter_checkout'}.contains(action);
    final onPressed = _working ? null : () => _onAction(i, action);
    if (primary) {
      return FilledButton.tonal(onPressed: onPressed, child: Text(biometricActionLabel(action)));
    }
    return OutlinedButton(onPressed: onPressed, child: Text(biometricActionLabel(action)));
  }

  Widget _missingCheckoutsSection(DailyReview r) {
    return _section(
      'Missing checkouts (${r.missingCheckouts.length})',
      Icons.timer_off_outlined,
      r.missingCheckouts.isEmpty
          ? [const Text('No open biometric sessions for this date.', style: TextStyle(color: AppColors.textSecondary))]
          : r.missingCheckouts.map((m) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(m['target_table'] == 'attendance' ? Icons.engineering_outlined : Icons.badge_outlined),
                title: Text('${m['full_name']}'),
                subtitle: Text('In ${_fmt(m['check_in_time']?.toString())}'
                    '${m['site_name'] != null ? ' • ${m['site_name']} ${m['shift_type'] ?? ''}' : ''} • Out missing'),
                trailing: FilledButton.tonal(
                  onPressed: _working ? null : () => _enterCheckout(m),
                  child: const Text('Enter Checkout'),
                ),
              )).toList(),
      subtitle: 'A check-out is never invented. Wait for the biometric OUT, or enter the real time.',
    );
  }

  Widget _orphanSection(DailyReview r) {
    return _section(
      'Drafts without a reviewer (${r.orphanDrafts.length})',
      Icons.assignment_late_outlined,
      r.orphanDrafts.isEmpty
          ? [const Text('None for this date.', style: TextStyle(color: AppColors.textSecondary))]
          : r.orphanDrafts.map((d) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(d['target_table'] == 'attendance' ? Icons.engineering_outlined : Icons.badge_outlined),
                title: Text('${d['full_name']} • ${d['record_date']}'),
                subtitle: Text(
                  '${d['orphan_reason'] == 'site_not_active' ? 'Site not Active' : 'No current supervisor'}'
                  '${d['site_name'] != null ? ' • ${d['site_name']}' : ''} • '
                  'In ${_fmt(d['check_in_time']?.toString())} → Out ${d['check_out_time'] == null ? 'missing' : _fmt(d['check_out_time']?.toString())}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: _working ? null : () => _submitOrphan(d),
                  child: const Text('Submit for review'),
                ),
              )).toList(),
      subtitle: 'Admin can submit these with a reason. Normal checks still apply and the record still needs approval.',
    );
  }

  Widget _unmappedSection(DailyReview r) {
    return _section(
      'Unmapped device IDs (${r.unmappedDeviceIds.length})',
      Icons.fingerprint,
      r.unmappedDeviceIds.isEmpty
          ? [const Text('All punches of this date are mapped.', style: TextStyle(color: AppColors.textSecondary))]
          : r.unmappedDeviceIds.map((u) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fingerprint),
                title: Text('Device ${u['device_employee_id']}'),
                subtitle: Text('${u['punches']} punch(es) • ${_fmt(u['first_punch']?.toString())} → ${_fmt(u['last_punch']?.toString())}'),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceIdMappingScreen()));
                    if (mounted) _load();
                  },
                  child: const Text('Map Employee'),
                ),
              )).toList(),
      subtitle: 'After mapping, press Retry on the related items above.',
    );
  }
}
