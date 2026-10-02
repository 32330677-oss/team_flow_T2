import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/constants.dart';
import '../widgets/searchable_picker_sheet.dart';
import '../screens/payroll_export_service.dart'; // reuse generic byte export/share

class TransferRequestScreen extends StatefulWidget {
  const TransferRequestScreen({super.key});

  @override
  State<TransferRequestScreen> createState() => _TransferRequestScreenState();
}

class _TransferRequestScreenState extends State<TransferRequestScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isLoadingWorkers = false;

  List<dynamic> _supervisorSites = []; // مواقع المشرف الخاصة به
  List<dynamic> _allSites = [];        // كل مواقع الشركة (للنقل إليها)
  List<dynamic> _workersInSite = [];   // عمال الموقع الحالي فقط

  Map<String, dynamic>? _selectedWorker;
  Map<String, dynamic>? _selectedCurrentSite;
  Map<String, dynamic>? _selectedTargetSite;
String? _selectedCurrentShiftType;
String? _selectedTargetShiftType;
  // B3: the business date the transfer should take effect (default today).
  DateTime _effectiveDate = DateTime.now();
  // C-11: a reason is mandatory for every transfer request.
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String get _effectiveDateStr =>
      '${_effectiveDate.year.toString().padLeft(4, '0')}-${_effectiveDate.month.toString().padLeft(2, '0')}-${_effectiveDate.day.toString().padLeft(2, '0')}';

  Future<void> _pickEffectiveDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      helpText: 'Transfer effective date',
    );
    if (picked != null) setState(() => _effectiveDate = picked);
  }
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // دالة مساعدة لاستخراج القائمة بغض النظر عن هيكل الـ JSON القادم
  List<dynamic> _parseListResponse(dynamic responseData) {
    if (responseData is List) {
      return responseData;
    } else if (responseData is Map) {
      if (responseData['data'] is List) {
        return responseData['data'];
      }
    }
    return [];
  }

  // 1. جلب مواقع المشرف ومواقع الشركة في البداية
Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiConfig.dio.get('/sites/my-sites'),      // مواقع المشرف الحالية
        ApiConfig.dio.get('/sites/all-sites'),     // تم التعديل هنا لتتم إضافة /sites/ بشكل صحيح
      ]);

      setState(() {
        _supervisorSites = _parseListResponse(results[0].data);
        _allSites = _parseListResponse(results[1].data);
        _isLoading = false;
      });
    } catch (e) {
      if (e is DioException) {
        print('==============================');
        print('DIOC EXCEPTION CAUGHT!');
        print('Failed URL Path: ${e.requestOptions.path}');
        print('Status Code: ${e.response?.statusCode}');
        print('Response Data: ${e.response?.data}');
        print('==============================');
      } else {
        print('General Error: $e');
      }
      
      setState(() => _isLoading = false);
      _showSnack('Failed to load sites data', Colors.red);
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
    await PayrollExportService.exportBytes(bytes, 'Transfer_Request_$requestId.docx');
  } on DioException catch (e) {
    final msg = e.response?.data is Map
        ? (e.response?.data['message'] ?? 'Failed to download document')
        : 'Failed to download document';
    _showSnack(msg, Colors.red);
  } catch (_) {
    _showSnack('Failed to download document', Colors.red);
  }
}
  // 2. جلب العمال التابعين للموقع الحالي الذي يختاره المشرف
Future<void> _loadWorkersForSite(int siteId) async {
    setState(() {
      _isLoadingWorkers = true;
      _selectedWorker = null; // إعادة تعيين العامل عند تغيير الموقع
    });
    try {
      // إرسال التاريخ الحالي بصيغة YYYY-MM-DD لتجنب خطأ السيرفر
      final String today = DateTime.now().toIso8601String().split('T')[0];

      final response = await ApiConfig.dio.get(
        '/attendance/sites/$siteId/workers',
        queryParameters: {
  'record_date': today,
  'shift_type': _selectedCurrentShiftType,
},
      );
      
      setState(() {
        _workersInSite = _parseListResponse(response.data);
        _isLoadingWorkers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingWorkers = false;
        _workersInSite = [];
      });
      _showSnack('Failed to load workers for this site', Colors.red);
    }
  }

Future<void> _pickCurrentSite() async {
  if (_supervisorSites.isEmpty) {
    _showSnack('No supervisor sites available', Colors.orange);
    return;
  }

  final picked = await SearchablePickerSheet.show<dynamic>(
    context,
    title: 'Select Current Site',
    items: _supervisorSites,
    labelBuilder: (s) => s['site_name'] ?? '',
  );

  if (picked == null) return;

  setState(() {
    _selectedCurrentSite = picked;
    _selectedCurrentShiftType = null;
    _selectedWorker = null;
    _workersInSite = [];
  });

  if (!mounted) return;

  final selectedShift = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select Current Shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Day'),
            onTap: () => Navigator.pop(context, 'Day'),
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Night'),
            onTap: () => Navigator.pop(context, 'Night'),
          ),
        ],
      ),
    ),
  );

  if (selectedShift == null) {
    setState(() {
      _selectedCurrentSite = null;
      _selectedCurrentShiftType = null;
      _workersInSite = [];
    });
    return;
  }

  setState(() {
    _selectedCurrentShiftType = selectedShift;
  });

  if (picked['site_id'] != null) {
    await _loadWorkersForSite(picked['site_id']);
  }
}



Future<void> _pickTargetShift() async {
  final selectedShift = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select Target Shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Day'),
            onTap: () => Navigator.pop(context, 'Day'),
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Night'),
            onTap: () => Navigator.pop(context, 'Night'),
          ),
        ],
      ),
    ),
  );

  if (selectedShift != null) {
    setState(() {
      _selectedTargetShiftType = selectedShift;
    });
  }
}

  Future<void> _pickWorker() async {
    if (_selectedCurrentSite == null) {
      _showSnack('Please select the current site first', Colors.orange);
      return;
    }
    if (_workersInSite.isEmpty) {
      _showSnack('No active workers available in this site', Colors.orange);
      return;
    }

    final picked = await SearchablePickerSheet.show<dynamic>(
      context,
      title: 'Select Worker',
      items: _workersInSite,
      labelBuilder: (w) => w['full_name'] ?? '',
      subtitleBuilder: (w) => 'ID: ${w['worker_unique_id'] ?? w['worker_id'] ?? ''}',
    );
    if (picked != null) setState(() => _selectedWorker = picked);
  }

  Future<void> _pickTargetSite() async {
    if (_allSites.isEmpty) {
      _showSnack('No target sites available', Colors.orange);
      return;
    }
    final picked = await SearchablePickerSheet.show<dynamic>(
      context,
      title: 'Select Target Site',
      items: _allSites,
      labelBuilder: (s) => s['site_name'] ?? '',
    );
    if (picked != null) setState(() => _selectedTargetSite = picked);
  }

Future<void> _submit() async {
if (_selectedWorker == null ||
    _selectedCurrentSite == null ||
    _selectedCurrentShiftType == null ||
    _selectedTargetSite == null ||
    _selectedTargetShiftType == null) {
    _showSnack('Please fill in all fields', Colors.orange);
    return;
  }

  if (_selectedCurrentSite!['site_id'] ==
        _selectedTargetSite!['site_id'] &&
    _selectedCurrentShiftType == _selectedTargetShiftType) {
  _showSnack(
    'Target site and shift cannot be the same as current',
    Colors.orange,
  );
  return;
}

  if (_reasonController.text.trim().length < 5) {
    _showSnack('Please enter the reason for the transfer (min. 5 characters)', Colors.orange);
    return;
  }

  setState(() => _isSubmitting = true);

  try {
 final response = await ApiConfig.dio.post('/transfers', data: {
  'transfer_reason': _reasonController.text.trim(),
  'worker_id': _selectedWorker!['worker_id'],
  'current_site_id': _selectedCurrentSite!['site_id'],
  'current_shift_type': _selectedCurrentShiftType,
  'target_site_id': _selectedTargetSite!['site_id'],
  'target_shift_type': _selectedTargetShiftType,
  'effective_date': _effectiveDateStr,
});

    if (!mounted) return;

    final requestId =
        response.data is Map ? response.data['request_id'] : null;

    _showSnack(
      'Transfer request submitted successfully',
      Colors.green,
    );

    if (requestId != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Transfer Request Created'),
          content: Text('Request ID: #$requestId'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _downloadTransferDocument(requestId);
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Transfer Document'),
            ),
          ],
        ),
      );
    }

setState(() {
  _selectedWorker = null;
  _selectedCurrentSite = null;
  _selectedCurrentShiftType = null;
  _selectedTargetSite = null;
  _selectedTargetShiftType = null;
  _workersInSite = [];
});
  } on DioException catch (e) {
    String msg = e.response?.data['message'] ?? 'Failed to submit request';
    _showSnack(msg, Colors.red);
  } catch (e) {
    _showSnack('Server connection error', Colors.red);
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Widget _buildSelector({
    required String label,
    required IconData icon,
    required String? value,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(icon, color: primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(
                      value ?? 'Click to search & select',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: value != null ? Colors.black87 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Worker Transfer Request',
          style: TextStyle(color: Colors.white), // 👈 أضف هذا السطر
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white), // 👈 وأضف هذا السطر أيضاً
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSelector(
                    label: 'Current Site',
                    icon: Icons.location_on_outlined,
                    value: _selectedCurrentSite?['site_name'],
                    onTap: _pickCurrentSite,
                  ),
                  const SizedBox(height: 16),
                  _buildSelector(
                    label: 'Worker',
                    icon: Icons.person,
                    value: _selectedWorker?['full_name'],
                    onTap: _pickWorker,
                    isLoading: _isLoadingWorkers,
                  ),
                  const SizedBox(height: 16),
      _buildSelector(
  label: 'Target Site',
  icon: Icons.location_on,
  value: _selectedTargetSite?['site_name'],
  onTap: _pickTargetSite,
),
const SizedBox(height: 16),
_buildSelector(
  label: 'Target Shift',
  icon: Icons.schedule,
  value: _selectedTargetShiftType,
  onTap: _pickTargetShift,
),
const SizedBox(height: 16),
_buildSelector(
  label: 'Effective Date (first day at the new site)',
  icon: Icons.event,
  value: _effectiveDateStr,
  onTap: _pickEffectiveDate,
),
const SizedBox(height: 16),
TextField(
  controller: _reasonController,
  maxLines: 3,
  maxLength: 500,
  decoration: InputDecoration(
    labelText: 'Reason for transfer (required)',
    hintText: 'Why should this worker move?',
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
),
const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit Request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}