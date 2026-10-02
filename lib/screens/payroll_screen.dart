// payroll_screen.dart
import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'payroll_export_service.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/monthly_report_card.dart';
import '../widgets/help_tip.dart';
String formatSyp(dynamic value) {
  final amount = double.tryParse(value?.toString() ?? '0') ?? 0;
  return '${NumberFormat('#,##0', 'en_US').format(amount)} ل.س';
}

/// D-10: each batch carries its own currency. Worker batches are SYP.
String formatMoney(dynamic value, dynamic currency) {
  final cur = (currency ?? 'SYP').toString().toUpperCase();
  if (cur == 'SYP') return formatSyp(value);
  final amount = double.tryParse(value?.toString() ?? '0') ?? 0;
  return '${NumberFormat('#,##0.00', 'en_US').format(amount)} $cur';
}

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({Key? key}) : super(key: key);

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);
  static const Color accentColor = Color(0xfffdbb2d);
  static const Color dangerColor = Color(0xffb21f1f);

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _isGenerating = false;
  bool _isLoadingBatches = true;
  bool _isLoadingSites = true;

  List<dynamic> _payrollBatches = [];
  bool _includeHistory = false;
  List<dynamic> _filteredBatches = [];
  List<dynamic> _sites = [];

  int? _selectedSiteId;
  DateTime? _dailyAttendanceDate;
  bool _isExportingDailyAttendance = false;

  @override
  void initState() {
    super.initState();
    _fetchSites();
    _fetchPayrollReports();
    _fetchLastBatchDate();
    _searchController.addListener(_filterBatches);
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSites() async {
    try {
      final response = await ApiConfig.dio.get('/sites/all-sites');
      final responseData = response.data;
      List sitesList = [];
      if (responseData is List) {
        sitesList = responseData;
      } else if (responseData is Map && responseData['data'] is List) {
        sitesList = responseData['data'];
      }

      final formattedSites = sitesList.map((site) {
        return {
          ...site,
          'site_id': site['site_id'] != null ? int.parse(site['site_id'].toString()) : null,
        };
      }).toList();

      setState(() {
        _sites = formattedSites;
        _isLoadingSites = false;
      });
    } catch (e) {
      setState(() => _isLoadingSites = false);
      _showSnack('Failed to load sites', dangerColor);
    }
  }

  String formatDisplayDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final parsedDate = DateTime.parse(dateStr);
      return DateFormat('yyyy-MM-dd').format(DateTime(parsedDate.year, parsedDate.month, parsedDate.day));
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _fetchPayrollReports() async {
    setState(() => _isLoadingBatches = true);
    try {
      final queryParams = <String, dynamic>{};
      if (_selectedSiteId != null) {
        queryParams['site_id'] = _selectedSiteId;
      }
      if (_includeHistory) queryParams['include_history'] = '1';

      final response = await ApiConfig.dio.get(
        '/admin/payroll/report',
        queryParameters: queryParams,
      );

      final responseData = response.data;
      List batchesList = [];
      if (responseData is List) {
        batchesList = responseData;
      } else if (responseData is Map && responseData['data'] is List) {
        batchesList = responseData['data'];
      }

      setState(() {
        _payrollBatches = batchesList;
        _filteredBatches = _payrollBatches;
        _isLoadingBatches = false;
      });
    } catch (e) {
      setState(() => _isLoadingBatches = false);
      _showSnack('Failed to load payroll reports', dangerColor);
    }
  }

  void _filterBatches() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredBatches = _payrollBatches.where((b) {
        final id = b['payroll_batch_id'].toString();
        final by = (b['generated_by'] ?? '').toString().toLowerCase();
        return id.contains(q) || by.contains(q);
      }).toList();
    });
  }

  /// C-03: the server refuses to generate while attendance in the period is
  /// not approved, and returns the list. The Admin either fixes it first or
  /// explicitly confirms that those records are NOT paid in this batch.
  Future<bool> _confirmPendingAttendance(Map data) async {
    final List rows = (data['pending_attendance'] as List?) ?? [];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unapproved attendance in this period'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['message']?.toString() ?? ''),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length > 50 ? 50 : rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r['full_name']} · ${r['site_name']} (${r['shift_type'] ?? 'Day'})'),
                      subtitle: Text('${r['record_date']}'),
                      trailing: StatusPill(label: '${r['status']}', color: WorkflowColors.of(r['status']?.toString())),
                    );
                  },
                ),
              ),
              if (rows.length > 50)
                Text('…and ${rows.length - 50} more', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel — review first')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate without them', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _reasonDialog(String title, String message, String confirmLabel, Color color) async {
    final ctrl = TextEditingController();
    String? err;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Reason (required, min. 5 characters)',
                    errorText: err,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: () {
                if (ctrl.text.trim().length < 5) {
                  setD(() => err = 'Please enter a clear reason');
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(confirmLabel, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  /// D-03: void a Generated (not finalized) batch. Nothing is deleted.
  Future<void> _voidBatch(int batchId) async {
    final reason = await _reasonDialog(
      'Void batch #$batchId',
      'Use this only for a batch generated by mistake. The batch stays in the history as "Voided" '
          'and its period can be generated again. Finalized or paid batches cannot be voided.',
      'Void batch',
      dangerColor,
    );
    if (reason == null) return;
    try {
      final r = await ApiConfig.dio.patch('/admin/payroll/batch/$batchId/void', data: {'reason': reason});
      _showSnack(r.data['message']?.toString() ?? 'Batch voided', Colors.blueGrey);
      _fetchPayrollReports();
      _fetchLastBatchDate();
    } on DioException catch (e) {
      _showSnack(e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to void batch').toString() : 'Failed to void batch', dangerColor);
    }
  }

  /// D-03: correct a finalized, unpaid batch. Generation, verification and
  /// superseding happen in one server transaction; the old batch is only
  /// marked Superseded if the replacement was created successfully.
  Future<void> _supersedeBatch(int batchId, {bool acknowledgePending = false, String? reason}) async {
    reason ??= await _reasonDialog(
      'Correct (supersede) batch #$batchId',
      'A new version is generated for the same period and site from the current approved attendance. '
          'This batch is kept as "Superseded" for audit. Paid batches can never be superseded.',
      'Generate new version',
      Colors.indigo,
    );
    if (reason == null) return;
    try {
      final r = await ApiConfig.dio.post('/admin/payroll/batch/$batchId/supersede', data: {
        'reason': reason,
        if (acknowledgePending) 'acknowledge_pending': true,
      });
      _showSnack(r.data['message']?.toString() ?? 'New version generated', Colors.green.shade700);
      _fetchPayrollReports();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'PENDING_ATTENDANCE' && !acknowledgePending) {
        if (await _confirmPendingAttendance(data)) {
          await _supersedeBatch(batchId, acknowledgePending: true, reason: reason);
        }
        return;
      }
      _showSnack(data is Map ? (data['message'] ?? 'Failed to supersede batch').toString() : 'Failed to supersede batch', dangerColor);
    }
  }

  Future<void> _generatePayroll({bool acknowledgePending = false}) async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      _showSnack('Please select start and end dates', Colors.orange);
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final response = await ApiConfig.dio.post('/admin/payroll/generate', data: {
        'start_date': _startDateController.text,
        'end_date': _endDateController.text,
        if (_selectedSiteId != null) 'site_id': _selectedSiteId,
        if (acknowledgePending) 'acknowledge_pending': true,
      });
      if (response.data['success'] == true || response.statusCode == 200 || response.statusCode == 201) {
        _showSnack('Payroll batch generated successfully', Colors.green);
        _startDateController.clear();
        _endDateController.clear();
        _fetchPayrollReports();
        _fetchLastBatchDate();
      }
    } catch (e) {
      String errorMessage = 'Error generating payroll';

      if (e is DioException && e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data['code'] == 'PENDING_ATTENDANCE' && !acknowledgePending) {
          if (mounted) setState(() => _isGenerating = false);
          if (await _confirmPendingAttendance(data)) {
            await _generatePayroll(acknowledgePending: true);
          }
          return;
        }
        errorMessage = (data['message'] ?? errorMessage).toString();
      }

      _showSnack(errorMessage, Colors.orange[800]!);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _selectDailyAttendanceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dailyAttendanceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Select attendance date',
    );
    if (picked != null && mounted) {
      setState(() => _dailyAttendanceDate = picked);
    }
  }

  Future<void> _exportDailyAttendance() async {
    final selected = _dailyAttendanceDate;
    if (selected == null) {
      _showSnack('Select an attendance date first.', Colors.orange);
      return;
    }

    final date = DateFormat('yyyy-MM-dd').format(selected);
    setState(() => _isExportingDailyAttendance = true);
    try {
      final response = await ApiConfig.dio.get(
        '/admin/payroll/daily-attendance/export.xlsx',
        queryParameters: {
          'date': date,
          if (_selectedSiteId != null) 'site_id': _selectedSiteId,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data is List<int>
          ? List<int>.from(response.data as List<int>)
          : <int>[];
      if (bytes.isEmpty) throw Exception('Empty attendance report');
      await PayrollExportService.exportBytes(bytes, 'daily_attendance_$date.xlsx');
      if (mounted) _showSnack('Daily attendance report exported.', Colors.green);
    } on DioException catch (e) {
      if (mounted) {
        final data = e.response?.data;
        final message = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Failed to export daily attendance report.';
        _showSnack(message, dangerColor);
      }
    } catch (_) {
      if (mounted) _showSnack('Failed to export daily attendance report.', dangerColor);
    } finally {
      if (mounted) setState(() => _isExportingDailyAttendance = false);
    }
  }

Future<void> _finalizeBatch(int batchId) async {
  try {
    await ApiConfig.dio.patch('/admin/payroll/batch/$batchId/finalize');
    _showSnack('Payroll batch finalized successfully', Colors.green.shade700);
    _fetchPayrollReports();
  } on DioException catch (e) {
    final msg = e.response?.data is Map
        ? (e.response?.data['message'] ?? 'Failed to finalize batch')
        : 'Failed to finalize batch';
    _showSnack(msg, dangerColor);
  } catch (e) {
    _showSnack('Failed to finalize batch', dangerColor);
  }
}

Future<void> _markBatchAsPaid(int batchId) async {
  try {
    await ApiConfig.dio.patch('/admin/payroll/batch/$batchId/mark-paid');
    _showSnack('Batch marked as paid', Colors.green);
    _fetchPayrollReports();
  } on DioException catch (e) {
    final msg = e.response?.data is Map
        ? (e.response?.data['message'] ?? 'Failed to update payment status')
        : 'Failed to update payment status';
    _showSnack(msg, dangerColor);
  } catch (e) {
    _showSnack('Failed to update payment status', dangerColor);
  }
}

  // Stores the end date of the most recent batch (optionally scoped to the
  // selected site) so the "Start Date" picker can't create overlaps.
  DateTime? _lastBatchEndDate;

  Future<void> _fetchLastBatchDate() async {
    try {
      final queryParams = <String, dynamic>{};
      if (_selectedSiteId != null) {
        queryParams['site_id'] = _selectedSiteId;
      }
      final response = await ApiConfig.dio.get(
        '/admin/payroll/last-date',
        queryParameters: queryParams,
      );
      if (response.data['success'] == true && response.data['last_end_date'] != null) {
        String lastEndStr = response.data['last_end_date'].toString();
        if (lastEndStr.contains('T')) lastEndStr = lastEndStr.split('T')[0];

        DateTime parsedEnd = DateTime.parse(lastEndStr);
        DateTime nextStart = parsedEnd.add(const Duration(days: 1));

        setState(() {
          _lastBatchEndDate = parsedEnd;
          _startDateController.text = "${nextStart.year.toString().padLeft(4, '0')}-"
              "${nextStart.month.toString().padLeft(2, '0')}-"
              "${nextStart.day.toString().padLeft(2, '0')}";
        });
      } else {
        setState(() => _lastBatchEndDate = null);
      }
    } catch (_) {}
  }

Future<void> _selectDate(TextEditingController controller, {bool isStartDate = false}) async {
  final initial = isStartDate && _lastBatchEndDate != null
      ? _lastBatchEndDate!.add(const Duration(days: 1))
      : DateTime.now();

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2025),
    lastDate: DateTime(2035),
    // لم يعد فيه selectableDayPredicate يمنع التواريخ —
    // بس بنحذر الأدمن إذا اختار فترة قديمة (تصحيح/Supersede)
  );

  if (picked != null) {
    if (isStartDate &&
        _lastBatchEndDate != null &&
        !picked.isAfter(_lastBatchEndDate!)) {
      final confirmOverlap = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overlapping Period'),
          content: const Text(
            'This start date overlaps an existing payroll period.\n\n'
            '• Not finalized batch for the SAME period and site: it is replaced by a new version.\n'
            '• Finalized batch: generation is refused — use "Correct (supersede)" on that batch with a reason.\n'
            '• Paid batch: can never be regenerated; differences go through attendance corrections.\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmOverlap != true) return;
    }

    final String formattedDate = "${picked.year.toString().padLeft(4, '0')}-"
        "${picked.month.toString().padLeft(2, '0')}-"
        "${picked.day.toString().padLeft(2, '0')}";

    setState(() {
      controller.text = formattedDate;
    });
  }
}

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDate(dynamic dateInput) {
    if (dateInput == null || dateInput.toString().isEmpty) return '';
    try {
      String str = dateInput.toString();
      if (str.contains('T')) {
        str = str.split('T')[0];
      }
      DateTime parsed = DateTime.parse(str);
      return DateFormat('yyyy-MM-dd').format(DateTime(parsed.year, parsed.month, parsed.day));
    } catch (e) {
      return dateInput.toString();
    }
  }

  Future<void> _openBatchDetails(int batchId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final response = await ApiConfig.dio.get('/admin/payroll/batch/$batchId');
      if (!mounted) return;
      Navigator.pop(context);

      final data = response.data;
      final batch = data['batch'] ?? {};
      // NEW SHAPE: one entry per worker, each carrying a `sites` list with
      // the per-site hours/rates/pay breakdown. No more duplicated
      // net_salary rows fanned out across sites.
      final List workers = data['workers'] ?? [];
      _showBatchDetailsSheet(batch, workers);
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showSnack('Error loading batch details: $e', dangerColor);
    }
  }

  void _showBatchDetailsSheet(Map batch, List workers) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Batch #${batch['payroll_batch_id'] ?? ''} (v${batch['version_number'] ?? 1})',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryColor)),
              const SizedBox(width: 8),
              if ((batch['is_finalized'] == 1 || batch['is_finalized'] == true))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Finalized', style: TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Not Finalized', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          Text(
            'Period: ${_formatDate(batch['start_date'])} → ${_formatDate(batch['end_date'])}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    ),
    IconButton(
  icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
  tooltip: 'Export PDF Report',
  onPressed: () => _exportBatchPdf(batch),
),
    IconButton(
      icon: const Icon(Icons.table_view, color: dangerColor),
      tooltip: 'Export Excel Report',
      onPressed: () => _exportBatchExcel(batch),
    ),
    const SizedBox(width: 8),
    _statusChip(batch['status']?.toString() ?? 'Pending'),
  ],
),
            ),
            const Divider(height: 1),
            Expanded(
              child: workers.isEmpty
                  ? const Center(child: Text('No workers found in this batch.'))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: workers.length,
                      itemBuilder: (context, index) {
                        final w = Map<String, dynamic>.from(workers[index]);
                        return _WorkerPayrollCard(
                          worker: w,
                          onPreview: () => _openPayslipPreview(batch, w),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Workers: ${batch['total_workers'] ?? workers.length}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Total Amount: ${formatMoney(batch['total_amount'], batch['currency'])}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 16)),
                      ],
                    ),
                  ),
                if ((batch['status'] ?? 'Pending') == 'Generated' &&
                    !(batch['is_finalized'] == 1 || batch['is_finalized'] == true)) ...[
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _voidBatch(batch['payroll_batch_id']);
                    },
                    icon: const Icon(Icons.block, color: dangerColor, size: 18),
                    label: const Text('Void', style: TextStyle(color: dangerColor)),
                  ),
                  const SizedBox(width: 8),
                ],
                if ((batch['status'] ?? 'Pending') == 'Generated' &&
                    (batch['is_finalized'] == 1 || batch['is_finalized'] == true)) ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _supersedeBatch(batch['payroll_batch_id']);
                    },
                    icon: const Icon(Icons.published_with_changes, size: 18),
                    label: const Text('Correct (supersede)'),
                  ),
                  const SizedBox(width: 8),
                ],
                if ((batch['status'] ?? 'Pending') == 'Generated') ...[
  if (!(batch['is_finalized'] == 1 || batch['is_finalized'] == true))
    ElevatedButton.icon(
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Finalize Payroll Batch'),
            content: const Text(
              'Finalizing locks this period and confirms management approval. '
              'After finalizing, it can no longer be regenerated — only superseded with a new correction. Continue?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Finalize', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          Navigator.pop(context);
          await _finalizeBatch(batch['payroll_batch_id']);
        }
      },
      icon: const Icon(Icons.lock_outline, color: Colors.white, size: 18),
      label: const Text('Finalize', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
    )
  else
    ElevatedButton.icon(
      onPressed: () {
        Navigator.pop(context);
        _confirmMarkPaid(batch['payroll_batch_id']);
      },
      icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
      label: const Text('Mark Paid', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
    ),
],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The server generates and streams the final .xlsx — the client only
  // downloads/shares the bytes. No calculation happens here.
  Future<void> _exportBatchExcel(Map batch) async {
    final batchId = int.tryParse('${batch['payroll_batch_id']}');
    if (batchId == null) {
      _showSnack('Invalid payroll batch.', dangerColor);
      return;
    }
    try {
    final response = await ApiConfig.dio.get<List<int>>(
  '/admin/payroll/batch/$batchId/export.xlsx',
  options: Options(
    responseType: ResponseType.bytes,
    receiveTimeout: const Duration(seconds: 90),
  ),
);
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('Empty Excel response');
      await PayrollExportService.exportBytes(
        bytes,
        'payroll_batch_$batchId.xlsx',
      );
      if (mounted) _showSnack('Excel payroll file is ready.', Colors.green);
   } on DioException catch (e, stack) {
  print('Excel Dio error: ${e.message}');
  print('Status: ${e.response?.statusCode}');
  print('Response: ${e.response?.data}');
  print(stack);

  final data = e.response?.data;
  final message = data is Map && data['message'] != null
      ? data['message'].toString()
      : 'Failed to export Excel payroll file.';

  _showSnack(message, dangerColor);
} catch (e, stack) {
  print('Excel export error: $e');
  print(stack);
  _showSnack(
    'Excel export failed: $e',
    dangerColor,
  );
}
  }
Future<void> _exportBatchPdf(Map batch) async {
  final batchId = int.tryParse('${batch['payroll_batch_id']}');
  if (batchId == null) {
    _showSnack('Invalid payroll batch.', dangerColor);
    return;
  }
  try {
    final response = await ApiConfig.dio.get<List<int>>(
      '/admin/payroll/batch/$batchId/export.pdf',
      options: Options(
  responseType: ResponseType.bytes,
  receiveTimeout: const Duration(seconds: 90),
),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty PDF response');
    await PayrollExportService.exportBytes(bytes, 'payroll_batch_$batchId.pdf');
    if (mounted) _showSnack('PDF payroll report is ready.', Colors.green);
  } on DioException catch (e) {
    final data = e.response?.data;
    final message = data is Map && data['message'] != null
        ? data['message'].toString()
        : 'Failed to export PDF payroll report.';
    _showSnack(message, dangerColor);
  } catch (_) {
    _showSnack('Failed to export PDF payroll report.', dangerColor);
  }
}
  Future<void> _confirmMarkPaid(int batchId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: const Text('Mark this entire batch as paid? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) _markBatchAsPaid(batchId);
  }

  Widget _statusChip(String status) {
    final Color color;
    switch (status) {
      case 'Paid':
        color = Colors.green;
        break;
      case 'Superseded':
        color = Colors.blueGrey;
        break;
      case 'Voided':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  void _openPayslipPreview(Map batch, Map worker) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: _PayslipDialog(batch: batch, worker: worker),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: CustomAppBar(
        title: ('Payroll Management'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchSites();
          await _fetchPayrollReports();
          await _fetchLastBatchDate();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSiteFilterDropdown(),
              const SizedBox(height: 16),
                            _buildGenerateCard(),
              const SizedBox(height: 16),
              const MonthlyReportCard(
                title: 'Monthly Labor Hours & Payroll Report',
                subtitle: 'Workers / laborers only. Daily hours, totals and stored payroll values for the selected month or day range.',
                endpoint: '/admin/payroll/monthly-report.xlsx',
                pdfEndpoint: '/admin/payroll/monthly-report.pdf',
                filePrefix: 'labor_hours_payroll',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Flexible(child: Text('Payroll History', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryColor))),
                  const HelpTip(
                    title: 'Payroll batch states',
                    message: 'Generated: created, can be regenerated or voided while not finalized.\n'
                        'Finalized: approved; attendance in the period is locked. Can only be corrected with "Correct (supersede)".\n'
                        'Paid: final. Never regenerated or reopened.\n'
                        'Superseded / Voided: kept for audit only (shown with "Show history").',
                  ),
                  const SizedBox(width: 4),
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Show history'),
                    selected: _includeHistory,
                    onSelected: (v) {
                      setState(() => _includeHistory = v);
                      _fetchPayrollReports();
                    },
                  ),
                  const SizedBox(width: 8),
                  Text('${_filteredBatches.length} batches', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by batch ID or generated-by...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              _isLoadingBatches
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _filteredBatches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text('No payroll batches found', style: TextStyle(color: Colors.grey.shade600)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredBatches.length,
                          itemBuilder: (context, index) {
                            final batch = _filteredBatches[index];
                            final isPaid = (batch['status'] ?? 'Pending') == 'Paid';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: (isPaid ? Colors.green : accentColor).withOpacity(0.15),
                                  child: Icon(Icons.receipt_long, color: isPaid ? Colors.green : primaryColor),
                                ),
                                title: Row(
                                  children: [
                                    Text('Batch #${batch['payroll_batch_id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    IconButton(
  icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
  tooltip: 'Export PDF',
  onPressed: () => _exportBatchPdf(batch),
),
                                    IconButton(
                                      icon: const Icon(Icons.table_view, color: dangerColor, size: 20),
                                      tooltip: 'Export Excel',
                                      onPressed: () => _exportBatchExcel(batch),
                                    ),
                                  ],
                                ),
                               subtitle: Text(
  'v${batch['version_number'] ?? 1} • Period: ${_formatDate(batch['start_date'])} → ${_formatDate(batch['end_date'])}\n'
  'Workers: ${batch['total_workers']} • Total: ${formatMoney(batch['total_amount'], batch['currency'])} • By: ${batch['generated_by'] ?? 'Admin'}'
  '${(batch['is_finalized'] == 1 || batch['is_finalized'] == true) ? '' : ' • Not Finalized'}',
),
                                isThreeLine: true,
                                trailing: _statusChip(batch['status']?.toString() ?? 'Pending'),
                                onTap: () => _openBatchDetails(batch['payroll_batch_id']),
                              ),
                            );
                          },
                        ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSiteFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: DropdownButtonFormField<int?>(
        value: _selectedSiteId,
        decoration: const InputDecoration(
          labelText: 'Filter by Site',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        ),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('All Sites (الكل)'),
          ),
          ..._sites.map((site) {
            return DropdownMenuItem<int?>(
              value: site['site_id'],
              child: Text(site['site_name'] ?? 'Site #${site['site_id']}'),
            );
          }).toList(),
        ],
        onChanged: (val) {
          setState(() {
            _selectedSiteId = val;
          });
          _fetchPayrollReports();
          _fetchLastBatchDate();
        },
      ),
    );
  }

  Widget _buildGenerateCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Generate New Payroll', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
              const Spacer(),
              if (_selectedSiteId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: accentColor.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Text('For Selected Site', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startDateController,
                  readOnly: true,
                  onTap: () => _selectDate(_startDateController, isStartDate: true),
                  decoration: const InputDecoration(
                    labelText: 'Start Date',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _endDateController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'End Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  onTap: () => _selectDate(_endDateController),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generatePayroll,
              icon: _isGenerating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt, color: Colors.white),
              label: Text(_isGenerating ? 'Generating...' : 'Generate Payroll Batch', style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExportingDailyAttendance ? null : _selectDailyAttendanceDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_dailyAttendanceDate == null
                      ? 'Daily Attendance Date'
                      : DateFormat('yyyy-MM-dd').format(_dailyAttendanceDate!)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExportingDailyAttendance ? null : _exportDailyAttendance,
                  icon: _isExportingDailyAttendance
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print_outlined),
                  label: const Text('Print Daily Attendance'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkerPayrollCard extends StatelessWidget {
  final Map worker;
  final VoidCallback onPreview;

  const _WorkerPayrollCard({required this.worker, required this.onPreview});

  @override
  Widget build(BuildContext context) {
    final sites = (worker['sites'] is List) ? (worker['sites'] as List) : [];
    
    // استخراج كل أنواع الدفع الفريدة للمرونة
    final uniquePayTypes = sites.map((s) => s['pay_type']?.toString()).where((t) => t != null).toSet();
    final isMixed = uniquePayTypes.length > 1;
    final payTypeLabel = isMixed ? 'Mixed' : (worker['pay_type'] ?? 'Hourly');
    final isDaily = payTypeLabel == 'Daily';

    // جمع المجاميع من الـ sites للتأكد من مطابقة الأرقام
    final totalDays = sites.fold<num>(0, (sum, s) => sum + (num.tryParse(s['days_worked']?.toString() ?? '0') ?? 0));
    final totalRegular = sites.fold<num>(0, (sum, s) => sum + (num.tryParse(s['regular_hours_worked']?.toString() ?? '0') ?? 0));
    final totalOvertime = sites.fold<num>(0, (sum, s) => sum + (num.tryParse(s['overtime_hours_worked']?.toString() ?? '0') ?? 0));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    worker['worker_name'] ?? 'Worker #${worker['worker_id']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1a2a6c)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isMixed ? Colors.orange.shade50 : (isDaily ? Colors.purple.shade50 : Colors.blue.shade50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    payTypeLabel,
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.bold, 
                      color: isMixed ? Colors.orange.shade800 : (isDaily ? Colors.purple : Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Payslip'),
                ),
              ],
            ),
            const Divider(),
            if (isMixed)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('Sites / Types', '${sites.length} Records', Colors.blueGrey),
                  _miniStat('Total Days/Hrs', '${totalDays > 0 ? "$totalDays days" : ""} ${totalRegular > 0 ? "$totalRegular h" : ""}', Colors.blueGrey),
                  _miniStat('Net Pay', formatSyp(worker['net_salary']), Colors.green.shade700, bold: true),
                ],
              )
            else if (isDaily)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat(
  'Days Worked',
  (double.tryParse(worker['days_worked'].toString()) ?? 0).toStringAsFixed(2),
  Colors.blueGrey,
),
                  _miniStat('Daily Rate', formatSyp(worker['daily_rate'] ?? sites.firstOrNull?['daily_rate_snapshot']), Colors.blueGrey),
                  _miniStat('Net Pay', formatSyp(worker['net_salary']), Colors.green.shade700, bold: true),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('Regular', '$totalRegular h', Colors.blueGrey),
                  _miniStat('Overtime', '$totalOvertime h', Colors.orange.shade800),
                  _miniStat('Net Pay', formatSyp(worker['net_salary']), Colors.green.shade700, bold: true),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color, {bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Read-only payslip for a single worker within a batch. Iterates the
/// worker's `sites` breakdown and shows the single net-salary total once.
class _PayslipDialog extends StatefulWidget {
  final Map batch;
  final Map worker;

  const _PayslipDialog({required this.batch, required this.worker});

  @override
  State<_PayslipDialog> createState() => _PayslipDialogState();
}

class _PayslipDialogState extends State<_PayslipDialog> {
  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.contains('T') ? s.split('T')[0] : s;
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  List<Map<String, dynamic>> get _sites {
    final raw = widget.worker['sites'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final b = widget.batch;
    final sites = _sites;

    final uniquePayTypes = sites.map((s) => s['pay_type']?.toString()).where((t) => t != null).toSet();
    final isMixed = uniquePayTypes.length > 1;
    final payTypeLabel = isMixed ? 'Mixed' : (w['pay_type'] ?? 'Hourly');

    final totalRegularHours = sites.fold<double>(0, (sum, s) => sum + _num(s['regular_hours_worked']));
    final totalOvertimeHours = sites.fold<double>(0, (sum, s) => sum + _num(s['overtime_hours_worked']));
    final totalDaysWorked = sites.fold<double>(0, (sum, s) => sum + _num(s['days_worked']));
    final totalBaseSalary = sites.fold<double>(0, (sum, s) => sum + _num(s['base_salary']));
    final totalOvertimePay = sites.fold<double>(0, (sum, s) => sum + _num(s['overtime_pay']));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w['worker_name'] ?? 'Worker #${w['worker_id']}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c))),
                        const SizedBox(height: 2),
                        Text('Batch #${b['payroll_batch_id']} • Payslip', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),
              _infoRow('Period', '${_fmtDate(b['start_date'])} to ${_fmtDate(b['end_date'])}'),
              _infoRow('Payment Type', payTypeLabel),
              
              if (isMixed) ...[
                _infoRow(
  'Days Worked',
  (double.tryParse(w['days_worked'].toString()) ?? 0).toStringAsFixed(2),
),
                _infoRow('Total Regular Hours', '${totalRegularHours.toStringAsFixed(2)} h'),
                _infoRow('Total Overtime Hours', '${totalOvertimeHours.toStringAsFixed(2)} h'),
              ] else if (payTypeLabel == 'Daily') ...[
                _infoRow('Days Worked', '${totalDaysWorked.toStringAsFixed(0)}'),
                _infoRow('Daily Rate', formatSyp(w['daily_rate'] ?? sites.firstOrNull?['daily_rate_snapshot'])),
              ] else ...[
                _infoRow('Regular Hours', '${totalRegularHours.toStringAsFixed(2)} h'),
                _infoRow('Overtime Hours', '${totalOvertimeHours.toStringAsFixed(2)} h'),
                _infoRow('Regular Rate', formatSyp(w['regular_rate'] ?? sites.firstOrNull?['hourly_rate_snapshot'])),
                _infoRow('Overtime Rate', formatSyp(w['overtime_rate'] ?? sites.firstOrNull?['overtime_hourly_rate_snapshot'])),
              ],

              _infoRow('Base Salary', formatSyp(totalBaseSalary)),
              _infoRow('Overtime Pay', formatSyp(totalOvertimePay)),

              const SizedBox(height: 12),
              Text('Per-site breakdown', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              ...sites.map((s) {
                final sType = s['pay_type'] ?? 'Hourly';
                final isDaily = sType == 'Daily';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(s['site_name']?.toString() ?? 'Site #${s['site_id']}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDaily ? Colors.purple.shade50 : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(sType, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDaily ? Colors.purple : Colors.blue)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (isDaily)
                        Text(
                          'Days: ${_num(s['days_worked']).toStringAsFixed(0)}  •  Rate: ${formatSyp(s['daily_rate_snapshot'])}  •  Total: ${formatSyp(s['base_salary'])}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        )
                      else
                        Text(
                          'Regular: ${_num(s['regular_hours_worked']).toStringAsFixed(2)}h @ ${formatSyp(s['hourly_rate_snapshot'])}  •  Overtime: ${_num(s['overtime_hours_worked']).toStringAsFixed(2)}h @ ${formatSyp(s['overtime_hourly_rate_snapshot'])}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                );
              }),

              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Net Salary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(formatSyp(w['net_salary']),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xff1a2a6c))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'This is a read-only payroll summary. Export the complete batch from the Excel button.',
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}