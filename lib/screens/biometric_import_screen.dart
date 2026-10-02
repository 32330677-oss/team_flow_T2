import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../services/biometric_import_service.dart';
import '../services/biometric_processing_service.dart' show BiometricApiException;
import '../widgets/app_data_table.dart';
import '../widgets/custom_app_bar.dart';
import 'biometric_processing_screen.dart';
import '../services/biometric_processing_service.dart' show BiometricProcessingService;

class BiometricImportScreen extends StatefulWidget {
  const BiometricImportScreen({super.key});

  @override
  State<BiometricImportScreen> createState() => _BiometricImportScreenState();
}

class _BiometricImportScreenState extends State<BiometricImportScreen> {
  final _service = BiometricImportService();

  List<ImportBatch> _batches = [];
  ConnectorStatus? _connector;
  ImportRunResult? _lastRun;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner) setState(() => _loading = true);
    try {
      final r = await _service.getBatches();
      if (!mounted) return;
      setState(() {
        _batches = r.batches;
        _connector = r.connector;
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

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Future<void> _pickAndImport() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Biometric export', extensions: ['txt', 'csv', 'dat']),
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import biometric file?'),
        content: Text('${file.name}\n${(bytes.length / 1024).toStringAsFixed(1)} KB\n\n'
            'The file will be imported into the punches table. Attendance is not created until you run Biometric Processing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final r = await _service.uploadAndImport(bytes, file.name);
      if (!mounted) return;
      setState(() => _lastRun = r);
      _snack(r.exitCode == 0 ? 'Import run finished. Check the history below.' : 'Connector reported a problem (exit ${r.exitCode}).',
          r.exitCode == 0 ? Colors.green.shade700 : Colors.orange.shade800);
      await _load(spinner: false);
    } on BiometricApiException catch (e) {
      _snack(e.message, e.statusCode == 409 ? Colors.orange.shade800 : Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runPending() async {
    setState(() => _busy = true);
    try {
      final r = await _service.runConnector();
      if (!mounted) return;
      setState(() => _lastRun = r);
      _snack(r.exitCode == 0 ? 'Connector run finished.' : 'Connector reported a problem (exit ${r.exitCode}).',
          r.exitCode == 0 ? Colors.green.shade700 : Colors.orange.shade800);
      await _load(spinner: false);
    } on BiometricApiException catch (e) {
      _snack(e.message, e.statusCode == 409 ? Colors.orange.shade800 : Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeStale(int batchId) async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close batch #$batchId'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Use this when an upload was interrupted. The punches already received become '
              'available for processing; the batch is recorded as closed with your reason.'),
          const SizedBox(height: 10),
          TextField(controller: c, decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (c.text.trim().length >= 3) Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('Close batch'),
          ),
        ],
      ),
    );
    c.dispose();
    if (reason == null) return;
    try {
      final msg = await BiometricProcessingService().closeStaleBatch(batchId, reason);
      _snack(msg, Colors.green.shade700);
      _load();
    } on BiometricApiException catch (e) {
      _snack(e.message, Colors.red);
    }
  }

  Future<void> _openDetail(ImportBatch b) async {
    try {
      final d = await _service.getBatch(b.id);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Batch #${d.batch.id}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(d.batch.sourceFile, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Status: ${d.batch.status}'),
                Text('Rows: ${d.batch.total}  •  Inserted: ${d.batch.inserted}  •  '
                    'Duplicates: ${d.batch.duplicates}  •  Errors: ${d.batch.errors}'),
                const Divider(height: 22),
                const Text('Processing of these punches', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(d.processing.entries.map((e) => '${e.key}: ${e.value}').join('  •  ')),
                if (d.errors.isNotEmpty) ...[
                  const Divider(height: 22),
                  const Text('Invalid lines', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...d.errors.take(20).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('Line ${e['lineNumber'] ?? '?'}: ${e['reason'] ?? ''}',
                            style: const TextStyle(fontSize: 12)),
                      )),
                ],
              ]),
            ),
          ),
          actions: [
            // C-14: an interrupted upload leaves the batch Pending and its
            // punches are never processed. Closing it is audited.
            if (d.batch.status == 'Pending')
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _closeStale(d.batch.id);
                },
                child: const Text('Close stale batch', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    } on BiometricApiException catch (e) {
      _snack(e.message, Colors.red);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Completed':
        return Colors.green.shade700;
      case 'CompletedWithErrors':
        return Colors.orange.shade800;
      case 'Failed':
        return AppColors.danger;
      default:
        return Colors.blueGrey;
    }
  }

  String _cut(String? s) => s == null ? '-' : (s.length > 19 ? s.substring(0, 19).replaceFirst('T', ' ') : s);

  @override
  Widget build(BuildContext context) {
    final c = _connector;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Biometric Import',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: (_loading || _busy) ? null : () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(spinner: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Import a device export file into the punches table. '
                      'Then run Biometric Processing to create attendance.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 14),
                  if (_loadError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_loadError!, style: TextStyle(color: Colors.red.shade900)),
                    ),
                  _actionCard(c),
                  const SizedBox(height: 14),
                  if (_lastRun != null) _runCard(_lastRun!),
                  if (_lastRun != null) const SizedBox(height: 14),
                  AppDataTableCard(
                    title: 'Import History',
                    subtitle: 'Latest ${_batches.length} batches • tap a row for details',
                    icon: Icons.history,
                    accentColor: AppColors.primary,
                    emptyMessage: 'No imports yet.',
                    columns: const [
                      DataColumn(label: Text('  #')),
                      DataColumn(label: Text('  File')),
                      DataColumn(label: Text('  Status')),
                      DataColumn(label: Text('  Rows')),
                      DataColumn(label: Text('  Inserted')),
                      DataColumn(label: Text('  Duplicates')),
                      DataColumn(label: Text('  Errors')),
                      DataColumn(label: Text('  Imported At')),
                    ],
                    rows: _batches.map((b) {
                      Widget pad(Widget w) =>
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: w);
                      return DataRow(
                        onSelectChanged: (_) => _openDetail(b),
                        cells: [
                          DataCell(pad(Text('${b.id}'))),
                          DataCell(pad(SizedBox(width: 200, child: Text(b.sourceFile, overflow: TextOverflow.ellipsis)))),
                          DataCell(pad(StatusBadge(label: b.status, color: _statusColor(b.status)))),
                          DataCell(pad(Text('${b.total}'))),
                          DataCell(pad(Text('${b.inserted}'))),
                          DataCell(pad(Text('${b.duplicates}'))),
                          DataCell(pad(Text('${b.errors}'))),
                          DataCell(pad(Text(_cut(b.importedAt ?? b.createdAt)))),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _actionCard(ConnectorStatus? c) {
    final enabled = c?.enabled == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Connector', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 10),
          StatusBadge(
            label: !enabled ? 'Not connected' : (c!.running ? 'Running' : 'Ready'),
            color: !enabled ? AppColors.danger : (c!.running ? Colors.orange.shade800 : Colors.green.shade700),
          ),
        ]),
        const SizedBox(height: 8),
        if (!enabled)
          const Text(
            'The backend cannot reach the Connector folder. Set BIOMETRIC_CONNECTOR_DIR in the backend .env '
            '(backend and Connector must be on the same machine).',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else
          Text('Files waiting in incoming: ${c!.incomingFiles}   •   Files in failed: ${c.failedFiles}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: (!enabled || _busy) ? null : _pickAndImport,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file_rounded),
            label: Text(_busy ? 'Working…' : 'Select file & Import'),
          ),
          OutlinedButton.icon(
            onPressed: (!enabled || _busy || (c?.incomingFiles ?? 0) == 0) ? null : _runPending,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Run pending files (${c?.incomingFiles ?? 0})'),
          ),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BiometricProcessingScreen()))
                    .then((_) => _load(spinner: false)),
            icon: const Icon(Icons.fingerprint_rounded),
            label: const Text('Go to Biometric Processing'),
          ),
        ]),
      ]),
    );
  }

  Widget _runCard(ImportRunResult r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Last Connector run', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 10),
          StatusBadge(
            label: r.timedOut ? 'Timed out' : (r.exitCode == 0 ? 'Exit 0' : 'Exit ${r.exitCode}'),
            color: (r.timedOut || r.exitCode != 0) ? Colors.orange.shade800 : Colors.green.shade700,
          ),
        ]),
        if (r.savedAs != null) ...[
          const SizedBox(height: 6),
          Text('Saved as ${r.savedAs}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xfff4f5f7), borderRadius: BorderRadius.circular(8)),
          child: SelectableText(
            r.output.isEmpty ? '(no output)' : r.output.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ]),
    );
  }
}