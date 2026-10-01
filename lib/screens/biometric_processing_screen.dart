import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/biometric_processing_service.dart';
import '../widgets/app_data_table.dart';
import '../widgets/custom_app_bar.dart';
import 'biometric_daily_review_tab.dart';
import 'payroll_export_service.dart';

class BiometricProcessingScreen extends StatefulWidget {
  /// 0 = Processing, 1 = Daily Review
  final int initialTab;
  const BiometricProcessingScreen({super.key, this.initialTab = 0});

  @override
  State<BiometricProcessingScreen> createState() => _BiometricProcessingScreenState();
}

class _BiometricProcessingScreenState extends State<BiometricProcessingScreen> {
  static const int _limit = 200;

  final _service = BiometricProcessingService();

  BiometricStatus? _status;
  List<BiometricIssue> _issues = [];
  String? _filter; // null = NeedsReview + Failed
  BiometricRunSummary? _lastRun;

  bool _loading = true;
  bool _processing = false;
  String? _loadError;

  DateTime _attDate = DateTime.now();
  List<Map<String, dynamic>> _attWorkers = [];
  List<Map<String, dynamic>> _attStaff = [];
  bool _attLoading = false;
  bool _downloading = false;

  String get _attDateStr => DateFormat('yyyy-MM-dd').format(_attDate);

  @override
  void initState() {
    super.initState();
    _load(); // read-only: never triggers processing
    _loadAttendance();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getBiometricProcessingStatus(),
        _service.getBiometricProcessingIssues(status: _filter),
      ]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as BiometricStatus;
        _issues = results[1] as List<BiometricIssue>;
        _loadError = null;
        _loading = false;
      });
    } on BiometricApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _run({bool? retryFailed}) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final r = await _service.processBiometricPunches(
        limit: _limit,
        retryFailed: retryFailed,
      );
      if (!mounted) return;
      setState(() => _lastRun = r);
      _snack(
        '${r.selected} punches selected — ${r.processed} processed, '
        '${r.needsReview} need review, ${r.skipped} informational, '
        '${r.invalid} invalid, ${r.failed} failed.',
        (r.failed > 0 || r.needsReview > 0) ? Colors.orange.shade800 : Colors.green.shade700,
      );
      await _load(showSpinner: false);
      await _loadAttendance();
    } on BiometricApiException catch (e) {
      if (!mounted) return;
      _snack(e.message, e.statusCode == 409 ? Colors.orange.shade800 : Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _loadAttendance() async {
    if (mounted) setState(() => _attLoading = true);
    try {
      final r = await _service.getBiometricAttendance(_attDateStr);
      if (!mounted) return;
      setState(() {
        _attWorkers = r['workers']!;
        _attStaff = r['staff']!;
        _attLoading = false;
      });
    } on BiometricApiException catch (e) {
      if (!mounted) return;
      setState(() => _attLoading = false);
      _snack(e.message, Colors.red);
    }
  }

  Future<void> _pickAttDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _attDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() => _attDate = d);
      _loadAttendance();
    }
  }

  Future<void> _downloadExcel() async {
    setState(() => _downloading = true);
    try {
      final bytes = await _service.downloadDailyAttendance(_attDateStr);
      await PayrollExportService.exportBytes(bytes, 'daily_attendance_$_attDateStr.xlsx');
      _snack('Daily attendance report is ready.', Colors.green.shade700);
    } on BiometricApiException catch (e) {
      _snack(e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _editTimes(Map<String, dynamic> row, bool isWorker) async {
    final changed = await showBiometricEditTimesDialog(
      context,
      service: _service,
      isWorker: isWorker,
      recordId: int.parse('${row[isWorker ? 'attendance_id' : 'staff_attendance_id']}'),
      fullName: '${row['full_name'] ?? ''}',
      checkIn: row['check_in_time']?.toString(),
      checkOut: row['check_out_time']?.toString(),
      status: row['status']?.toString(),
      fallbackDate: _attDate,
    );
    if (changed) await _loadAttendance();
  }

  Widget _attRow(Map<String, dynamic> r, bool isWorker) {
    String t(dynamic v) => v == null ? '--:--' : '$v'.replaceFirst('T', ' ').substring(11, 16);
    final status = '${r['status']}';
    final editable = status == 'Draft' || status == 'Submitted';
    final hours = isWorker ? r['total_working_hours'] : r['regular_hours'];
    final sub = isWorker
        ? '${r['site_name'] ?? ''} • ${r['shift_type'] ?? ''}'
        : '${r['position'] ?? 'Staff'}';
    final missingOut = r['check_in_time'] != null && r['check_out_time'] == null;
    return ListTile(
      dense: true,
      leading: Icon(isWorker ? Icons.engineering_outlined : Icons.badge_outlined, color: AppColors.primary),
      title: Text('${r['full_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$sub\nIn ${t(r['check_in_time'])} → Out ${missingOut ? 'missing' : t(r['check_out_time'])} • ${hours ?? '--'}h '
          '${(double.tryParse('${r['overtime_hours'] ?? 0}') ?? 0) > 0 ? '• OT ${r['overtime_hours']}h' : ''}'),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusBadge.fromStatus(status),
        IconButton(
          tooltip: editable ? 'Edit times' : 'Locked',
          icon: const Icon(Icons.edit_rounded, size: 18),
          onPressed: editable ? () => _editTimes(r, isWorker) : null,
        ),
      ]),
    );
  }

  Widget _attendanceSection() {
    final empty = _attWorkers.isEmpty && _attStaff.isEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Biometric Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          OutlinedButton.icon(
            onPressed: _pickAttDate,
            icon: const Icon(Icons.calendar_today, size: 15),
            label: Text(_attDateStr),
          ),
          FilledButton.icon(
            onPressed: _downloading ? null : _downloadExcel,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: _downloading
                ? const SizedBox(width: 15, height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.table_view, size: 16),
            label: const Text('Download Excel'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Attendance created by biometric punches. Fix times here (a wrong check-out can be cleared). '
          'Biometric records follow the normal submit / approve / reject flow. '
          'The Excel file is the daily attendance report (workers).',
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (_attLoading)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (empty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('No biometric attendance for this date.',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else ...[
          if (_attWorkers.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Workers', style: TextStyle(fontWeight: FontWeight.w700))),
            ..._attWorkers.map((r) => _attRow(r, true)),
          ],
          if (_attStaff.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Staff', style: TextStyle(fontWeight: FontWeight.w700))),
            ..._attStaff.map((r) => _attRow(r, false)),
          ],
        ],
      ]),
    );
  }

  Future<void> _confirmRetryFailed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retry all Failed punches?'),
        content: const Text(
          'Failed punches are retried automatically up to 3 times. This also re-processes '
          'Failed punches that already reached that limit (up to $_limit, together with Pending ones). '
          'Failed punches usually need investigation first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retry Failed')),
        ],
      ),
    );
    if (ok == true) await _run(retryFailed: true);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: CustomAppBar(
          title: 'Biometric Processing',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: (_loading || _processing) ? null : () => _load(),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.play_circle_outline), text: 'Processing'),
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'Daily Review'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _processingTab(),
            const BiometricDailyReviewTab(),
          ],
        ),
      ),
    );
  }

  Widget _processingTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Process imported biometric punches into attendance records. '
            'Anything ambiguous is never guessed: it goes to the Daily Review tab.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (_loadError != null) _errorBox(_loadError!),
          if (_status != null) ...[
            _statusCards(_status!),
            const SizedBox(height: 14),
            _actionCard(_status!),
            const SizedBox(height: 14),
            _lastRunCard(),
            const SizedBox(height: 14),
            _issuesSection(),
            const SizedBox(height: 14),
            _attendanceSection(),
          ],
        ],
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: TextStyle(color: Colors.red.shade900))),
          TextButton(onPressed: () => _load(), child: const Text('Retry')),
        ]),
      );

  Widget _statCard(String label, int value, Color color, String hint) {
    return Tooltip(
      message: hint,
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text('$value',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(hint,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
              maxLines: 3),
        ]),
      ),
    );
  }

  Widget _statusCards(BiometricStatus s) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      _statCard('Pending', s.pending, Colors.orange.shade800, 'Waiting to be processed.'),
      _statCard('Processed', s.processed, Colors.green.shade700, 'Changed attendance.'),
      _statCard('Needs Review', s.needsReview, Colors.deepPurple, 'A person must decide (Daily Review).'),
      _statCard('Failed', s.failed, AppColors.danger, 'Unexpected error. Auto-retried up to 3 times.'),
      _statCard('Informational', s.skipped, Colors.blueGrey, 'Nothing to do (already applied / manual record exists).'),
      _statCard('Invalid', s.invalid, Colors.brown, 'Future or too-old punch. Never processed.'),
      _statCard('Dismissed', s.dismissed, Colors.grey.shade700, 'Closed by an admin with a note.'),
      _statCard('Total', s.total, AppColors.primary, 'All punches tracked.'),
    ]);
  }

  Widget _actionCard(BiometricStatus s) {
    String? diagnosis;
    if (s.needsReview > 0) {
      diagnosis = '${s.needsReview} punch(es) need a decision. Open the Daily Review tab.';
    } else if (s.pending == 0) {
      diagnosis = 'There are no pending biometric punches to process.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Processing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 10),
          _pill(_processing ? 'Processing…' : 'Idle',
              _processing ? Colors.orange.shade800 : Colors.green.shade700),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: _processing ? null : () => _run(),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: _processing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_processing ? 'Processing…' : 'Process Pending Punches'),
          ),
          OutlinedButton.icon(
            onPressed: _processing || s.failed == 0 ? null : _confirmRetryFailed,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            icon: const Icon(Icons.replay_circle_filled_outlined),
            label: const Text('Retry All Failed'),
          ),
        ]),
        const SizedBox(height: 10),
        const Text(
          'Each run handles up to $_limit punches, oldest first, applied chronologically. '
          'Failed punches are retried automatically up to 3 times; items that need review '
          'are only handled from the Daily Review.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        if (diagnosis != null) ...[
          const SizedBox(height: 8),
          Text(diagnosis, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
        ],
      ]),
    );
  }

  Widget _lastRunCard() {
    final r = _lastRun;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Last Processing Run (this session)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (r == null)
          const Text(
            'No run started from this screen yet. Per-punch outcomes appear below and in the Daily Review.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else ...[
          Wrap(spacing: 8, runSpacing: 6, children: [
            _pill('Selected ${r.selected}', AppColors.primary),
            _pill('Processed ${r.processed}', Colors.green.shade700),
            _pill('Needs review ${r.needsReview}', Colors.deepPurple),
            _pill('Informational ${r.skipped}', Colors.blueGrey),
            _pill('Invalid ${r.invalid}', Colors.brown),
            _pill('Failed ${r.failed}', AppColors.danger),
          ]),
          const SizedBox(height: 8),
          Text(
            'Requested ${DateFormat('yyyy-MM-dd HH:mm:ss').format(r.requestedAt)} • '
            'round-trip ${(r.roundTrip.inMilliseconds / 1000).toStringAsFixed(1)}s (measured on this device) • '
            'retry all failed: ${r.retryFailed ? 'yes' : 'no'}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ]),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _issuesSection() {
    final filters = <String?, String>{
      null: 'Open (Review + Failed)',
      'NeedsReview': 'Needs Review',
      'Failed': 'Failed',
      'Invalid': 'Invalid',
      'Skipped': 'Informational',
      'Dismissed': 'Dismissed',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final e in filters.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: _filter == e.key,
            onSelected: _processing
                ? null
                : (_) {
                    setState(() => _filter = e.key);
                    _load();
                  },
          ),
      ]),
      const SizedBox(height: 10),
      AppDataTableCard(
        title: 'Punch Outcomes',
        subtitle: 'Latest ${_issues.length} (max 100) • act on them in the Daily Review tab',
        icon: Icons.report_problem_outlined,
        accentColor: AppColors.primary,
        emptyMessage: 'Nothing here.',
        columns: const [
          DataColumn(label: Text('  Punch ID')),
          DataColumn(label: Text('  Employee')),
          DataColumn(label: Text('  Punched At')),
          DataColumn(label: Text('  Type')),
          DataColumn(label: Text('  Status')),
          DataColumn(label: Text('  Reason')),
          DataColumn(label: Text('  Attempts')),
          DataColumn(label: Text('  Last Attempt')),
        ],
        rows: _issues.map(_row).toList(),
      ),
    ]);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Failed':
        return AppColors.danger;
      case 'NeedsReview':
        return Colors.deepPurple;
      case 'Invalid':
        return Colors.brown;
      case 'Processed':
        return Colors.green.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  DataRow _row(BiometricIssue i) {
    final color = _statusColor(i.status);
    String cut(String s) => s.length > 19 ? s.substring(0, 19) : s;
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: w);

    return DataRow(cells: [
      DataCell(pad(Text('${i.punchId}'))),
      DataCell(pad(Text(i.deviceEmployeeId))),
      DataCell(pad(Text(cut(i.punchedAt).replaceFirst('T', ' ')))),
      DataCell(pad(Text(i.punchType))),
      DataCell(pad(StatusBadge(label: i.status == 'Skipped' ? 'Informational' : i.status, color: color))),
      DataCell(pad(Tooltip(
        message: i.error ?? i.explanation,
        child: SizedBox(
          width: 280,
          child: Text('${i.result ?? '-'}\n${i.error ?? i.explanation}',
              style: const TextStyle(fontSize: 11.5), maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ))),
      DataCell(pad(Text('${i.attempts}'))),
      DataCell(pad(Text(
        i.processedAt == null
            ? '-'
            : '${cut(i.processedAt!)}${i.processedByUserId != null ? '\nby user #${i.processedByUserId}' : ''}',
        style: const TextStyle(fontSize: 11.5),
      ))),
    ]);
  }
}

/// Shared edit dialog for a biometric record (used by the Processing tab and
/// the Daily Review "Enter Checkout" action). Returns true when saved.
Future<bool> showBiometricEditTimesDialog(
  BuildContext context, {
  required BiometricProcessingService service,
  required bool isWorker,
  required int recordId,
  required String fullName,
  String? checkIn,
  String? checkOut,
  String? status,
  required DateTime fallbackDate,
}) async {
  DateTime? inDt = DateTime.tryParse('${checkIn ?? ''}'.replaceFirst(' ', 'T'));
  DateTime? outDt = DateTime.tryParse('${checkOut ?? ''}'.replaceFirst(' ', 'T'));
  final originalOut = outDt;
  bool clearOut = false;
  final reason = TextEditingController();
  final f = DateFormat('yyyy-MM-dd HH:mm');

  Future<DateTime?> pickDT(BuildContext ctx, DateTime? initial) async {
    final base = initial ?? fallbackDate;
    final d = await showDatePicker(
      context: ctx,
      initialDate: base,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 2)),
    );
    if (d == null || !ctx.mounted) return null;
    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Edit — $fullName'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check-in'),
            subtitle: Text(inDt == null ? 'Not set' : f.format(inDt!)),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () async {
              final v = await pickDT(ctx, inDt);
              if (v != null) setD(() => inDt = v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check-out'),
            subtitle: Text(clearOut
                ? 'Will be cleared'
                : (outDt == null ? 'Missing — enter the real check-out' : f.format(outDt!))),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () async {
              final v = await pickDT(ctx, outDt ?? inDt);
              if (v != null) setD(() { outDt = v; clearOut = false; });
            },
          ),
          if (originalOut != null && status == 'Draft')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: clearOut,
              onChanged: (v) => setD(() => clearOut = v ?? false),
              title: const Text('Clear this check-out (it is wrong)'),
              subtitle: const Text('The record goes back to "missing check-out". The raw punch is kept.',
                  style: TextStyle(fontSize: 11)),
            ),
          TextField(
            controller: reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  final reasonText = reason.text.trim();
  reason.dispose();
  if (ok != true) return false;

  final sf = DateFormat('yyyy-MM-dd HH:mm:ss');
  // Unchanged values are sent back exactly as stored (seconds included).
  String? fmt(DateTime? v, String? original) {
    if (v == null) return null;
    final orig = DateTime.tryParse('${original ?? ''}'.replaceFirst(' ', 'T'));
    if (orig != null && orig.year == v.year && orig.month == v.month && orig.day == v.day &&
        orig.hour == v.hour && orig.minute == v.minute) {
      return original!.replaceFirst('T', ' ').substring(0, 19);
    }
    return sf.format(v);
  }

  try {
    await service.editBiometricTimes(
      isWorker: isWorker,
      id: recordId,
      checkIn: fmt(inDt, checkIn),
      checkOut: clearOut ? null : fmt(outDt, checkOut),
      clearCheckOut: clearOut,
      reason: reasonText,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Times updated.'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
    return true;
  } on BiometricApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
    return false;
  }
}
