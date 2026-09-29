import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/biometric_processing_service.dart';
import '../widgets/app_data_table.dart';
import '../widgets/custom_app_bar.dart';

class BiometricProcessingScreen extends StatefulWidget {
  const BiometricProcessingScreen({super.key});

  @override
  State<BiometricProcessingScreen> createState() => _BiometricProcessingScreenState();
}

class _BiometricProcessingScreenState extends State<BiometricProcessingScreen> {
  static const int _limit = 200;

  final _service = BiometricProcessingService();

  BiometricStatus? _status;
  List<BiometricIssue> _issues = [];
  String? _filter; // null = all, 'Skipped', 'Failed'
  BiometricRunSummary? _lastRun;

  bool _loading = true;
  bool _processing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load(); // read-only: never triggers processing
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

  Future<void> _run({bool? retrySkipped, bool? retryFailed}) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final r = await _service.processBiometricPunches(
        limit: _limit,
        retrySkipped: retrySkipped,
        retryFailed: retryFailed,
      );
      if (!mounted) return;
      setState(() => _lastRun = r);
      _snack(
        '${r.selected} punches selected — ${r.processed} processed, '
        '${r.skipped} skipped, ${r.failed} failed.',
        r.failed > 0 ? Colors.orange.shade800 : Colors.green.shade700,
      );
      await _load(showSpinner: false);
    } on BiometricApiException catch (e) {
      if (!mounted) return;
      _snack(e.message, e.statusCode == 409 ? Colors.orange.shade800 : Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _confirmRetryFailed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retry Failed punches?'),
        content: const Text(
          'This will re-process punches that previously failed, together with Pending and Skipped punches '
          '(up to $_limit). Failed punches usually need investigation first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retry Failed')),
        ],
      ),
    );
    if (ok == true) await _run(retrySkipped: true, retryFailed: true);
  }

  void _snack(String msg, Color color) {
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
    return Scaffold(
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(showSpinner: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Process imported biometric punches into attendance records.',
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
                  ],
                ],
              ),
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
        width: 190,
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
      _statCard('Processed', s.processed, Colors.green.shade700, 'Successfully handled.'),
      _statCard('Skipped', s.skipped, Colors.blueGrey,
          'Not processed because of a known condition. Can be retried.'),
      _statCard('Failed', s.failed, AppColors.danger,
          'Unexpected/explicit failure. Needs attention.'),
      _statCard('Total', s.total, AppColors.primary, 'All punches tracked.'),
    ]);
  }

  Widget _actionCard(BiometricStatus s) {
    String? diagnosis;
    if (s.pending == 0 && s.skipped > 0) {
      diagnosis = '${s.skipped} punches are currently skipped. Review the reasons below, '
          'fix the underlying issue, then retry them.';
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
            onPressed: _processing || s.skipped == 0
                ? null
                : () => _run(retrySkipped: true, retryFailed: false),
            icon: const Icon(Icons.replay),
            label: const Text('Retry Skipped'),
          ),
          OutlinedButton.icon(
            onPressed: _processing || s.failed == 0 ? null : _confirmRetryFailed,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            icon: const Icon(Icons.replay_circle_filled_outlined),
            label: const Text('Retry Failed'),
          ),
        ]),
        const SizedBox(height: 10),
        const Text(
          'Each run handles up to $_limit punches, oldest first. Process Pending Punches also '
          'retries Skipped punches; it never retries Failed punches. Retrying Failed is always explicit.',
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
            'No run started from this screen yet. The server does not store run history; '
            'per-punch outcomes appear in the table below.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else ...[
          Wrap(spacing: 8, runSpacing: 6, children: [
            _pill('Selected ${r.selected}', AppColors.primary),
            _pill('Processed ${r.processed}', Colors.green.shade700),
            _pill('Skipped ${r.skipped}', Colors.blueGrey),
            _pill('Failed ${r.failed}', AppColors.danger),
          ]),
          const SizedBox(height: 8),
          Text(
            'Requested ${DateFormat('yyyy-MM-dd HH:mm:ss').format(r.requestedAt)} • '
            'round-trip ${(r.roundTrip.inMilliseconds / 1000).toStringAsFixed(1)}s (measured on this device) • '
            'retry skipped: ${r.retrySkipped ? 'yes' : 'no'} • retry failed: ${r.retryFailed ? 'yes' : 'no'}',
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
    final filters = <String?, String>{null: 'All', 'Skipped': 'Skipped', 'Failed': 'Failed'};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, children: [
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
        title: 'Skipped & Failed Punches',
        subtitle: 'Latest ${_issues.length} (max 100) • hover a result for its meaning',
        icon: Icons.report_problem_outlined,
        accentColor: AppColors.primary,
        emptyMessage: 'No processing issues.',
        columns: const [
          DataColumn(label: Text('  Punch ID')),
          DataColumn(label: Text('  Employee')),
          DataColumn(label: Text('  Punched At')),
          DataColumn(label: Text('  Type')),
          DataColumn(label: Text('  Status')),
          DataColumn(label: Text('  Result')),
          DataColumn(label: Text('  Error')),
          DataColumn(label: Text('  Attempts')),
          DataColumn(label: Text('  Last Attempt')),
        ],
        rows: _issues.map(_row).toList(),
      ),
    ]);
  }

  DataRow _row(BiometricIssue i) {
    final failed = i.status == 'Failed';
    final color = failed ? AppColors.danger : Colors.blueGrey;
    String cut(String s) => s.length > 19 ? s.substring(0, 19) : s;
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: w);

    return DataRow(cells: [
      DataCell(pad(Text('${i.punchId}'))),
      DataCell(pad(Text(i.deviceEmployeeId))),
      DataCell(pad(Text(cut(i.punchedAt)))),
      DataCell(pad(Text(i.punchType))),
      DataCell(pad(StatusBadge(label: i.status, color: color))),
      DataCell(pad(Tooltip(
        message: i.explanation,
        child: SizedBox(
          width: 230,
          child: Text('${i.result ?? '-'}\n${i.explanation}',
              style: const TextStyle(fontSize: 11.5), maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ))),
      DataCell(pad(SizedBox(
        width: 180,
        child: Text(i.error ?? '-',
            style: const TextStyle(fontSize: 11.5), maxLines: 3, overflow: TextOverflow.ellipsis),
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