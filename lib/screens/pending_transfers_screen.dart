import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/constants.dart';
import '../widgets/custom_app_bar.dart';
import '../screens/payroll_export_service.dart';

class PendingTransfersScreen extends StatefulWidget {
  const PendingTransfersScreen({super.key});

  @override
  State<PendingTransfersScreen> createState() => _PendingTransfersScreenState();
}

class _PendingTransfersScreenState extends State<PendingTransfersScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  List<dynamic> _requests = [];
  bool _isLoading = true;
  int? _processingId;

  @override
  void initState() {
    super.initState();
    _fetchPending();
  }

  Future<void> _fetchPending() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/transfers/pending');
      setState(() {
        _requests = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Failed to load transfer requests', Colors.red);
    }
  }

  Future<void> _downloadTransferDocument(int requestId) async {
    try {
      final response = await ApiConfig.dio.get<List<int>>(
        '/transfers/$requestId/document',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('Empty document');
      await PayrollExportService.exportBytes(
        bytes,
        'Transfer_Request_$requestId.docx',
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to download document')
          : 'Failed to download document';
      _showSnack(msg, Colors.red);
    } catch (_) {
      _showSnack('Failed to download document', Colors.red);
    }
  }

  Future<void> _review(int requestId, String status, {String? requestedEffectiveDate}) async {
    String? adminNote;
    String? effectiveDate;

    if (status == 'Approved') {
      // B3: the admin confirms the business date the transfer takes effect
      // (pre-filled with the date requested by the supervisor).
      effectiveDate = await _showApproveDialog(initialDate: requestedEffectiveDate);
      if (effectiveDate == null) return;
    } else if (status == 'Rejected') {
      // نافذة إدخال ملاحظات الأدمن عند الرفض
      adminNote = await _showRejectDialog();
      if (adminNote == null) return; // تم إلغاء العملية
    }

    setState(() => _processingId = requestId);
    try {
      final response = await ApiConfig.dio.put(
        '/transfers/$requestId/review',
        data: {
          'status': status,
          'admin_notes': adminNote,
          if (effectiveDate != null) 'effective_date': effectiveDate,
        },
      );
      if (response.data['status'] == 'success') {
        _showSnack(
          status == 'Approved'
              ? 'Request approved and worker transferred successfully'
              : 'Transfer request rejected',
          Colors.green,
        );
        await _fetchPending();
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      var msg = (data is Map ? data['message'] : null)?.toString() ?? 'Failed to process request';
      final conflicts = data is Map ? data['conflicts'] : null;
      if (conflicts is List && conflicts.isNotEmpty) {
        msg = '$msg\nConflicting dates: ${conflicts.take(5).map((c) => c is Map ? c['record_date'] : c).join(', ')}';
      }
      _showSnack(msg, Colors.red);
    } catch (e) {
      _showSnack('Server connection error', Colors.red);
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // نافذة تأكيد القبول
  Future<bool> asyncConfirmApprove() async => (await _showApproveDialog()) != null;

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Returns the chosen effective date (YYYY-MM-DD) or null when cancelled.
  Future<String?> _showApproveDialog({String? initialDate}) async {
    final today = DateTime.now();
    // B3: future-dated transfers are allowed (the requested date is kept as is).
    var picked = DateTime.tryParse(initialDate ?? '') ?? today;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Approve Transfer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The worker moves to the new site/shift from the effective date. '
                'The old assignment ends the day before. The approval date does not matter.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 16),
                label: Text('Effective date: ${_fmtDate(picked)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: DateTime(2023),
                    lastDate: today.add(const Duration(days: 365)),
                    helpText: 'Transfer effective date',
                  );
                  if (d != null) setD(() => picked = d);
                },
              ),
              if (initialDate != null && initialDate != _fmtDate(picked))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Requested by the supervisor: $initialDate',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Approve',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    return result == true ? _fmtDate(picked) : null;
  }

  // نافذة كتابة ملاحظات الرفض
  Future<String?> _showRejectDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Transfer Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide a reason for rejection (Admin Notes):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter reason here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              // Rejection reason is mandatory (stored and audited).
              if (controller.text.trim().length < 3) return;
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text(
              'Confirm Rejection',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Pending Transfer Requests',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPending,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 60,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No pending transfer requests',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchPending,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _requests.length,
                    itemBuilder: (context, index) {
                      final req = _requests[index];
                      final isProcessing =
                          _processingId == req['request_id'];

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: primaryColor,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      req['worker_name'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _siteChip(
  icon: Icons.logout,
  label: 'From',
  site: req['current_site_name'] ?? '',
  shiftType: req['current_shift_type'],
  color: Colors.grey.shade700,
),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  Expanded(
                                    child: _siteChip(
  icon: Icons.login,
  label: 'To',
  site: req['target_site_name'] ?? '',
  shiftType: req['target_shift_type'],
  color: Colors.green.shade700,
),
                                  ),
                                ],
                              ),
                              if ((req['request_reason'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Reason: ${req['request_reason']}',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'Effective date: ${req['effective_date'] ?? 'not set (choose when approving)'}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Requested by: ${req['requested_by_name'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _downloadTransferDocument(
                                        req['request_id'],
                                      ),
                                      icon: const Icon(
                                        Icons.description_outlined,
                                      ),
                                      label: const Text('Word Doc'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isProcessing
                                          ? null
                                          : () => _review(
                                                req['request_id'],
                                                'Rejected',
                                              ),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                      ),
                                      label: const Text(
                                        'Reject',
                                        style:
                                            TextStyle(color: Colors.red),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: isProcessing
                                          ? null
                                          : () => _review(
                                                req['request_id'],
                                                'Approved',
                                                requestedEffectiveDate:
                                                    req['effective_date']?.toString(),
                                              ),
                                      icon: isProcessing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                            ),
                                      label: const Text(
                                        'Approve',
                                        style: TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

Widget _siteChip({
  required IconData icon,
  required String label,
  required String site,
  required String? shiftType,
  required Color color,
}) {
  final bool isNight = shiftType == 'Night';

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        site,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      if (shiftType != null) ...[
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              isNight
                  ? Icons.nightlight_outlined
                  : Icons.wb_sunny_outlined,
              size: 13,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              shiftType!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ],
    ],
  );
}
}