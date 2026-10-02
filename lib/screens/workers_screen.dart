import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/protected_image.dart';
import 'WorkerProfileScreen.dart';
import '../widgets/app_drawer.dart';
class WorkersScreen extends StatefulWidget {
  const WorkersScreen({Key? key}) : super(key: key);

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  XFile? _selectedPersonalPhoto;
  XFile? _selectedIdPhoto;
  final ImagePicker _picker = ImagePicker();
 String _paymentType = 'Daily'; // 'Hourly' or 'Daily'
final _dailyRateController = TextEditingController();
final _regularHourlyRateController = TextEditingController();
final _overtimeHourlyRateController = TextEditingController();
final _reasonController = TextEditingController(); // required only on edit when comp changes
// --- Bulk compensation update state ---
String _bulkPaymentType = 'Daily';
final _bulkDailyRateController = TextEditingController();
final _bulkRegularHourlyRateController = TextEditingController();
final _bulkOvertimeHourlyRateController = TextEditingController();
final _bulkReasonController = TextEditingController();
final _bulkEffectiveDateController = TextEditingController();
final _hireDateController = TextEditingController();
bool _bulkApplyToAll = true;
final Set<int> _bulkSelectedWorkerIds = <int>{};
bool _isBulkSubmitting = false;
  // دالة اختيار الصورة
  Future<void> _pickImage(bool isPersonal) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (isPersonal) {
          _selectedPersonalPhoto = image;
        } else {
          _selectedIdPhoto = image;
        }
      });
    }
  }

  final Color primaryColor = const Color(0xFF2563EB);

  List<dynamic> _workers = [];
  List<dynamic> _filteredWorkers = [];
  bool _isLoading = true;
  
  final TextEditingController _searchController = TextEditingController();

  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _positionController = TextEditingController();
  final _notesController = TextEditingController();
  final _mothersNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _locationController = TextEditingController();
final _effectiveDateController = TextEditingController();
  @override
  void initState() {
    super.initState();
    _fetchWorkers();
    _searchController.addListener(_filterWorkers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _nationalityController.dispose();
    _positionController.dispose();
    _notesController.dispose();
    _mothersNameController.dispose();
    _birthDateController.dispose();
    _birthPlaceController.dispose();
    _locationController.dispose();
    _dailyRateController.dispose();
_regularHourlyRateController.dispose();
_overtimeHourlyRateController.dispose();
_reasonController.dispose();
    _bulkDailyRateController.dispose();
_bulkRegularHourlyRateController.dispose();
_bulkOvertimeHourlyRateController.dispose();
_bulkReasonController.dispose();
_effectiveDateController.dispose();
_bulkEffectiveDateController.dispose();
_hireDateController.dispose();
    super.dispose();
  }

  int get _totalWorkers => _workers.length;
  int get _activeWorkers => _workers.where((w) => w['status'] == 'Active').length;
  int get _inactiveWorkers => _totalWorkers - _activeWorkers;

  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/workers');
      print('WORKERS RESPONSE: ${response.data}');
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _workers = response.data['data'];
          _filteredWorkers = _workers;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to fetch workers data', Colors.red);
    }
  }

  Future<void> _selectBirthDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        _birthDateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _filterWorkers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredWorkers = _workers.where((worker) {
        final name = (worker['full_name'] ?? '').toLowerCase();
        final code = (worker['worker_unique_id'] ?? '').toLowerCase();
        final position = (worker['job_position'] ?? '').toLowerCase();
        return name.contains(query) || code.contains(query) || position.contains(query);
      }).toList();
    });
  }

Future<void> _saveWorker({String? workerUniqueId, Map<String, dynamic>? originalWorker}) async {
  final name = _nameController.text.trim();
    

  if (name.isEmpty) {
    _showSnackBar('Please fill in the worker name', Colors.orange);
    return;
  }

  final isEditing = workerUniqueId != null;

  // فحص هل تم تعديل بيانات التعويض فعلياً مقارنة بالبيانات الأصلية (إذا كان تعديلاً)
  bool compensationChanged = true;
  if (isEditing && originalWorker != null) {
    final oldPaymentType = originalWorker['payment_type']?.toString() ?? 'Daily';
    final oldDailyRate = originalWorker['daily_rate']?.toString() ?? '';
    final oldRegularRate = originalWorker['regular_hourly_rate']?.toString() ?? '';
    final oldOvertimeRate = originalWorker['overtime_hourly_rate']?.toString() ?? '';
    final oldPosition = originalWorker['job_position']?.toString() ?? '';

    final currentDailyRate = _dailyRateController.text.trim();
    final currentRegularRate = _regularHourlyRateController.text.trim();
    final currentOvertimeRate = _overtimeHourlyRateController.text.trim();
    final currentPosition = _positionController.text.trim();

    // التحقق هل هناك أي تغيير حقيقي في الراتب أو نوعه أو الوظيفة
    compensationChanged = (oldPaymentType != _paymentType) ||
        (oldDailyRate != currentDailyRate) ||
        (oldRegularRate != currentRegularRate) ||
        (oldOvertimeRate != currentOvertimeRate) ||
        (oldPosition != currentPosition);
  }

  // إذا تغير التعويض، نتحقق من إدخال الحقول الإلزامية الخاصة به
  if (compensationChanged) {
    if (_paymentType == 'Hourly') {
      if (_regularHourlyRateController.text.trim().isEmpty ||
          _overtimeHourlyRateController.text.trim().isEmpty) {
        _showSnackBar('Regular and overtime hourly rates are required.', Colors.orange);
        return;
      }
    } else {
      if (_dailyRateController.text.trim().isEmpty) {
        _showSnackBar('Daily rate is required.', Colors.orange);
        return;
      }
    }

    if (isEditing && _reasonController.text.trim().isEmpty) {
      _showSnackBar('Please provide a reason for the compensation/position change.', Colors.orange);
      return;
    }
  }

  try {
   final Map<String, dynamic> mapData = {
      'full_name': name,
      'phone_number': _phoneController.text.trim(),
      'nationality': _nationalityController.text.trim(),
      'job_position': _positionController.text.trim(),
      'notes': _notesController.text.trim(),
      'mothers_name': _mothersNameController.text.trim(),
      'birth_place': _birthPlaceController.text.trim(),
      'location': _locationController.text.trim(),
    };

    // فقط عند إضافة عامل جديد: نرسل تاريخ التوظيف الفعلي (ممكن يكون بالماضي).
    // الباك اند أصلاً بيستخدمه لـ workers.hire_date وworkercompensationhistory.effective_from سوا.
    if (!isEditing && _hireDateController.text.trim().isNotEmpty) {
      mapData['hire_date'] = _hireDateController.text.trim();
    }

    // نرسل بيانات التعويض فقط إذا كانت جديدة (عند الإضافة) أو حدث تغيير فيها (عند التعديل)
    if (!isEditing || compensationChanged) {
      mapData['payment_type'] = _paymentType;
      if (_paymentType == 'Hourly') {
        mapData['regular_hourly_rate'] = _regularHourlyRateController.text.trim();
        mapData['overtime_hourly_rate'] = _overtimeHourlyRateController.text.trim();
      } else {
        mapData['daily_rate'] = _dailyRateController.text.trim();
      }

      if (isEditing) {
        mapData['reason'] = _reasonController.text.trim();

        if (_effectiveDateController.text.trim().isEmpty) {
          _showSnackBar('Please select the effective date for this change.', Colors.orange);
          return;
        }
        mapData['effective_from'] = _effectiveDateController.text.trim();
        // ❌ تم إزالة الـ clear من هنا لئلا يمسح التاريخ قبل الإرسال
      }
    }

    final birthDate = _birthDateController.text.trim();
    if (birthDate.isNotEmpty) mapData['birth_date'] = birthDate;

    if (_selectedPersonalPhoto != null) {
      final bytes = await _selectedPersonalPhoto!.readAsBytes();
      mapData['personal_photo'] = MultipartFile.fromBytes(bytes, filename: _selectedPersonalPhoto!.name);
    }
    if (_selectedIdPhoto != null) {
      final bytes = await _selectedIdPhoto!.readAsBytes();
      mapData['id_photo'] = MultipartFile.fromBytes(bytes, filename: _selectedIdPhoto!.name);
    }

    FormData formData = FormData.fromMap(mapData);

    if (workerUniqueId != null) {
      final response = await ApiConfig.dio.put('/workers/$workerUniqueId', data: formData);
      if (response.statusCode == 200) {
        // ✅ تم نقل مسح حقل التاريخ إلى هنا بعد نجاح العملية تماماً
        _effectiveDateController.clear(); 
        Navigator.pop(context);
        _clearControllers();
        _fetchWorkers();
        _showSnackBar('Worker updated successfully', Colors.green);
      }
    } else {
      final response = await ApiConfig.dio.post('/workers', data: formData);
      if (response.statusCode == 201) {
        Navigator.pop(context);
        _clearControllers();
        _fetchWorkers();
        _showSnackBar('Worker added successfully with auto ID', Colors.green);
      }
    }
  } on DioException catch (e) {
    final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Operation failed') : 'Operation failed';
    _showSnackBar(msg, Colors.red);
  } catch (e) {
    print("🚨 SAVE WORKER ERROR: $e");
    _showSnackBar('Operation failed: ${e.toString()}', Colors.red);
  }
}


void _openBulkCompensationSheet() {
  _bulkPaymentType = 'Daily';
  _bulkDailyRateController.clear();
  _bulkRegularHourlyRateController.clear();
  _bulkOvertimeHourlyRateController.clear();
  _bulkReasonController.clear();
  _bulkEffectiveDateController.text = DateTime.now().toIso8601String().split('T')[0];
  _bulkApplyToAll = true;
  _bulkSelectedWorkerIds.clear();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 24, left: 24, right: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Bulk Update Compensation',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor),
              ),
              const SizedBox(height: 6),
              Text(
                'This will update the payment type/rate for the selected workers and record it in their compensation history.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              Text('Payment Type *', style: TextStyle(fontWeight: FontWeight.w600, color: primaryColor)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hourly'),
                      value: 'Hourly',
                      groupValue: _bulkPaymentType,
                      onChanged: (value) => setModalState(() => _bulkPaymentType = value!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Daily'),
                      value: 'Daily',
                      groupValue: _bulkPaymentType,
                      onChanged: (value) => setModalState(() => _bulkPaymentType = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_bulkPaymentType == 'Hourly') ...[
                TextField(
                  controller: _bulkRegularHourlyRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Regular Hourly Rate *',
                    prefixIcon: Icon(Icons.schedule, color: primaryColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bulkOvertimeHourlyRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Overtime Hourly Rate *',
                    prefixIcon: Icon(Icons.timer_outlined, color: primaryColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _bulkDailyRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Daily Rate *',
                    prefixIcon: Icon(Icons.calendar_today, color: primaryColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              TextField(
                controller: _bulkReasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for change *',
                  hintText: 'مثال: تعديل عام لليومية حسب قرار الإدارة',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),
              TextField(
                controller: _bulkEffectiveDateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Effective Date *',
                  hintText: 'YYYY-MM-DD',
                  prefixIcon: Icon(Icons.event_available),
                  border: OutlineInputBorder(),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(_bulkEffectiveDateController.text) ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    helpText: 'Select the date this change actually takes effect for all selected workers',
                  );
                  if (picked != null) {
                    setModalState(() {
                      _bulkEffectiveDateController.text =
                          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                    });
                  }
                },
              ),

              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Apply to all active workers', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Uncheck to choose specific workers instead'),
                value: _bulkApplyToAll,
                onChanged: (value) => setModalState(() => _bulkApplyToAll = value ?? true),
              ),

              if (!_bulkApplyToAll) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _workers.length,
                    itemBuilder: (context, index) {
                      final worker = _workers[index];
                      final id = int.tryParse(worker['worker_id'].toString());
                      if (id == null) return const SizedBox.shrink();
                      final selected = _bulkSelectedWorkerIds.contains(id);
                      return CheckboxListTile(
                        dense: true,
                        title: Text(worker['full_name'] ?? ''),
                        subtitle: Text('ID: ${worker['worker_unique_id'] ?? ''}'),
                        value: selected,
                        onChanged: (checked) => setModalState(() {
                          if (checked == true) {
                            _bulkSelectedWorkerIds.add(id);
                          } else {
                            _bulkSelectedWorkerIds.remove(id);
                          }
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text('${_bulkSelectedWorkerIds.length} worker(s) selected', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isBulkSubmitting
                      ? null
                      : () => _submitBulkCompensation(setModalState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isBulkSubmitting
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Apply Bulk Update', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _submitBulkCompensation(void Function(void Function()) setModalState) async {
  final reason = _bulkReasonController.text.trim();
  if (reason.isEmpty) {
    _showSnackBar('Please provide a reason for the bulk change.', Colors.orange);
    return;
  }

  if (_bulkPaymentType == 'Hourly') {
    if (_bulkRegularHourlyRateController.text.trim().isEmpty ||
        _bulkOvertimeHourlyRateController.text.trim().isEmpty) {
      _showSnackBar('Regular and overtime hourly rates are required.', Colors.orange);
      return;
    }
  } else {
    if (_bulkDailyRateController.text.trim().isEmpty) {
      _showSnackBar('Daily rate is required.', Colors.orange);
      return;
    }
  }

  if (!_bulkApplyToAll && _bulkSelectedWorkerIds.isEmpty) {
    _showSnackBar('Please select at least one worker.', Colors.orange);
    return;
  }

  setModalState(() => _isBulkSubmitting = true);
  setState(() => _isBulkSubmitting = true);

  try {
    if (_bulkEffectiveDateController.text.trim().isEmpty) {
      _showSnackBar('Please select the effective date.', Colors.orange);
      return;
    }
    final effectiveDate = _bulkEffectiveDateController.text.trim();

    final Map<String, dynamic> data = {
      'payment_type': _bulkPaymentType,
      'reason': reason,
      'effective_from': effectiveDate,
    };
    if (_bulkPaymentType == 'Hourly') {
      data['regular_hourly_rate'] = _bulkRegularHourlyRateController.text.trim();
      data['overtime_hourly_rate'] = _bulkOvertimeHourlyRateController.text.trim();
    } else {
      data['daily_rate'] = _bulkDailyRateController.text.trim();
    }
    if (!_bulkApplyToAll) {
      data['worker_ids'] = _bulkSelectedWorkerIds.toList();
    }

    final response = await ApiConfig.dio.post('/workers/bulk-compensation', data: data);

    if (mounted) {
      Navigator.pop(context); // اقفل الشيت
      final message = response.data is Map && response.data['message'] != null
          ? response.data['message'].toString()
          : 'Bulk compensation updated successfully';
      _showSnackBar(message, Colors.green);
      _fetchWorkers();
    }
  } on DioException catch (e) {
    final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Bulk update failed') : 'Bulk update failed';
    setModalState(() => _isBulkSubmitting = false);
    setState(() => _isBulkSubmitting = false);
    _showSnackBar(msg, Colors.red);
  } catch (e) {
    setModalState(() => _isBulkSubmitting = false);
    setState(() => _isBulkSubmitting = false);
    _showSnackBar('Bulk update failed: ${e.toString()}', Colors.red);
  }
}




  // D1: a status change is recorded in the worker status history with the
  // date it takes effect, so historical attendance/biometric punches are
  // resolved against the status that applied on their own date.
  Future<void> _toggleWorkerStatus(String workerUniqueId, String currentStatus) async {
    final newStatus = currentStatus == 'Active' ? 'Inactive' : 'Active';
    DateTime effective = DateTime.now();
    final reasonCtl = TextEditingController();
    // §27 / R-14: becoming Inactive does not end assignments by itself. The
    // Admin may explicitly end them; the last assigned day is the day before
    // the Inactive date (inclusive semantics).
    bool endAssignments = false;
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Set $newStatus'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From which date is the worker $newStatus?'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 16),
                label: Text('Effective date: ${fmt(effective)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: effective,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setD(() => effective = picked);
                },
              ),
              const SizedBox(height: 4),
              Text('First day the new status applies. Past attendance keeps the status of its own date.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              if (newStatus == 'Inactive') ...[
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: endAssignments,
                  onChanged: (v) => setD(() => endAssignments = v == true),
                  title: const Text('Also end site assignments'),
                  subtitle: Text('Last assigned day: ${fmt(effective.subtract(const Duration(days: 1)))}'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtl,
                decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Set $newStatus')),
          ],
        ),
      ),
    );
    final reason = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (confirmed != true) return;
    try {
      final response = await ApiConfig.dio.put('/workers/$workerUniqueId', data: {
        'status': newStatus,
        'status_effective_date': fmt(effective),
        if (reason.isNotEmpty) 'status_reason': reason,
        if (newStatus == 'Inactive' && endAssignments)
          'end_assignments_last_day': fmt(effective.subtract(const Duration(days: 1))),
      });
      if (response.statusCode == 200) {
        _fetchWorkers();
        _showSnackBar('Worker status updated to $newStatus', Colors.blue);
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      _showSnackBar(data is Map && data['message'] != null ? data['message'].toString() : 'Failed to update status', Colors.red);
    } catch (e) {
      _showSnackBar('Failed to update status', Colors.red);
    }
  }

  void _openWorkerSheet({Map<String, dynamic>? worker}) {
    // تصفير الصور المختارة عند فتح النافذة الجديدة
    _selectedPersonalPhoto = null;
    _selectedIdPhoto = null;

    if (worker != null) {
      _codeController.text = worker['worker_unique_id']?.toString() ?? '';
      _nameController.text = worker['full_name']?.toString() ?? '';
      _phoneController.text = worker['phone_number']?.toString() ?? '';
      _nationalityController.text = worker['nationality']?.toString() ?? '';
      _positionController.text = worker['job_position']?.toString() ?? '';
      _notesController.text = worker['notes']?.toString() ?? '';
      _mothersNameController.text = worker['mothers_name']?.toString() ?? '';
      _birthDateController.text = worker['birth_date']?.toString().split('T')[0] ?? '';
      _birthPlaceController.text = worker['birth_place']?.toString() ?? '';
      _locationController.text = worker['location']?.toString() ?? '';
      _paymentType = worker['payment_type']?.toString() ?? 'Daily';
_dailyRateController.text = worker['daily_rate']?.toString() ?? '';
_regularHourlyRateController.text = worker['regular_hourly_rate']?.toString() ?? '';
_overtimeHourlyRateController.text = worker['overtime_hourly_rate']?.toString() ?? '';
_reasonController.clear();
_effectiveDateController.text = DateTime.now().toIso8601String().split('T')[0]; // default قابل للتعديل
    } else {
      _clearControllers();
    }

    final isEditing = worker != null;
    final String? workerUniqueId = worker?['worker_unique_id'];
    bool isSaving = false; 
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 24, left: 24, right: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Text(
                  isEditing ? 'Edit Worker Details' : 'Add New Worker',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor),
                ),
                const SizedBox(height: 20),
                
                if (isEditing) ...[
                  TextField(
                    controller: _codeController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Worker ID (Auto-generated)',
                      prefixIcon: Icon(Icons.badge_rounded, color: primaryColor),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                TextField(controller: _nameController, decoration: InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person_rounded, color: primaryColor))),
                const SizedBox(height: 12),
                TextField(controller: _mothersNameController, decoration: InputDecoration(labelText: "Mother's Name", prefixIcon: Icon(Icons.family_restroom_rounded, color: primaryColor))),
                const SizedBox(height: 12),
                TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_rounded, color: primaryColor))),
                const SizedBox(height: 12),
                TextField(controller: _nationalityController, decoration: InputDecoration(labelText: 'Nationality', prefixIcon: Icon(Icons.flag_rounded, color: primaryColor))),
                const SizedBox(height: 12),
                TextField(
                  controller: _birthDateController,
                  readOnly: true,
                  onTap: () => _selectBirthDate(context),
                  decoration: InputDecoration(
                    labelText: 'Birth Date',
                    hintText: 'YYYY-MM-DD',
                    prefixIcon: Icon(Icons.calendar_today_rounded, color: primaryColor),
                    suffixIcon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(controller: _birthPlaceController, decoration: InputDecoration(labelText: 'Birth Place', prefixIcon: Icon(Icons.location_city_rounded, color: primaryColor))),
                const SizedBox(height: 12),
                TextField(controller: _locationController, decoration: InputDecoration(labelText: 'Current Location / Address', prefixIcon: Icon(Icons.place_rounded, color: primaryColor))),
                const SizedBox(height: 12),
                TextField(controller: _positionController, decoration: InputDecoration(labelText: 'Job Position', prefixIcon: Icon(Icons.work_rounded, color: primaryColor))),
                const SizedBox(height: 16),
            const SizedBox(height: 16),
            if (!isEditing) ...[
  TextField(
    controller: _hireDateController,
    readOnly: true,
    decoration: InputDecoration(
      labelText: 'Hire Date *',
      hintText: 'YYYY-MM-DD',
      prefixIcon: Icon(Icons.event_available_rounded, color: primaryColor),
      suffixIcon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
      helperText:
          'Defaults to today. Set an earlier date if this worker actually started before today (needed for backdated attendance & payroll).',
      helperMaxLines: 3,
    ),
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(_hireDateController.text) ?? DateTime.now(),
        firstDate: DateTime(2015),
        lastDate: DateTime.now(),
        helpText: "Select the worker's actual hire date",
      );
      if (picked != null) {
        setModalState(() {
          _hireDateController.text =
              "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        });
      }
    },
  ),
  const SizedBox(height: 12),
],
Text('Payment Type *', style: TextStyle(fontWeight: FontWeight.w600, color: primaryColor)),
const SizedBox(height: 8),
Row(
  children: [
    Expanded(
      child: RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        title: const Text('Hourly'),
        value: 'Hourly',
        groupValue: _paymentType,
        onChanged: (value) => setModalState(() => _paymentType = value!),
      ),
    ),
    Expanded(
      child: RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        title: const Text('Daily'),
        value: 'Daily',
        groupValue: _paymentType,
        onChanged: (value) => setModalState(() => _paymentType = value!),
      ),
    ),
  ],
),
const SizedBox(height: 8),
if (_paymentType == 'Hourly') ...[
  TextField(
    controller: _regularHourlyRateController,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: 'Regular Hourly Rate *',
      prefixIcon: Icon(Icons.schedule, color: primaryColor),
    ),
  ),
  const SizedBox(height: 12),
  TextField(
    controller: _overtimeHourlyRateController,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: 'Overtime Hourly Rate *',
      prefixIcon: Icon(Icons.timer_outlined, color: primaryColor),
    ),
  ),
] else ...[
  TextField(
    controller: _dailyRateController,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: 'Daily Rate *',
      prefixIcon: Icon(Icons.calendar_today, color: primaryColor),
    ),
  ),
],
if (isEditing) ...[
  const SizedBox(height: 12),
  TextField(
    controller: _reasonController,
    maxLines: 2,
    decoration: const InputDecoration(
      labelText: 'Reason for change (required if payment/rate/position changed)',
      border: OutlineInputBorder(),
    ),
  ),
  const SizedBox(height: 12),
  TextField(
    controller: _effectiveDateController,
    readOnly: true,
    decoration: const InputDecoration(
      labelText: 'Effective Date *',
      hintText: 'YYYY-MM-DD',
      prefixIcon: Icon(Icons.event_available),
      border: OutlineInputBorder(),
    ),
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(_effectiveDateController.text) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        helpText: 'Select the date this change actually takes effect',
      );
      if (picked != null) {
        setModalState(() {
          _effectiveDateController.text =
              "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        });
      }
    },
  ),
],
                // أزرار اختيار الصور بدل الحقول النصية القديمة
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _pickImage(true);
                          setModalState(() {}); // لتحديث شكل الزر في الـ BottomSheet
                        },
                        icon: Icon(Icons.person_add_alt_1, color: primaryColor),
                        label: Text(_selectedPersonalPhoto == null ? 'Personal Photo' : 'Photo Selected',
                            style: TextStyle(fontSize: 12, color: primaryColor)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _pickImage(false);
                          setModalState(() {}); // لتحديث شكل الزر في الـ BottomSheet
                        },
                        icon: Icon(Icons.badge_outlined, color: primaryColor),
                        label: Text(_selectedIdPhoto == null ? 'ID Photo' : 'Photo Selected',
                            style: TextStyle(fontSize: 12, color: primaryColor)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(controller: _notesController, maxLines: 2, decoration: InputDecoration(labelText: 'Notes', prefixIcon: Icon(Icons.note_rounded, color: primaryColor))),
                const SizedBox(height: 24),
               const SizedBox(height: 24),
ElevatedButton(
  onPressed: isSaving
      ? null
      : () async {
          if (!isEditing) {
            final todayStr = DateTime.now().toIso8601String().split('T')[0];
            final chosenDate = _hireDateController.text.trim();
            if (chosenDate.isNotEmpty && chosenDate != todayStr) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (confirmCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Confirm Backdated Hire Date'),
                  content: Text(
                    "This worker's Hire Date will be set to $chosenDate instead of today.\n\n"
                    "Their initial compensation record will also start from $chosenDate.\n\n"
                    "If you're going to assign them to a site, make sure to use the same "
                    "(or a later) Assignment Date, so backdated attendance and payroll "
                    "generation work correctly.\n\n"
                    "Continue with $chosenDate as the hire date?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmCtx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                      onPressed: () => Navigator.pop(confirmCtx, true),
                      child: const Text('Confirm', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
            }
          }

          setModalState(() => isSaving = true);
          try {
            await _saveWorker(
              workerUniqueId: workerUniqueId,
              originalWorker: worker,
            );
          } finally {
            setModalState(() => isSaving = false);
          }
        },
  style: ElevatedButton.styleFrom(
    minimumSize: const Size.fromHeight(50),
    backgroundColor: primaryColor,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  child: isSaving
      ? const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : Text(
          isEditing ? 'Save Changes' : 'Add Worker',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
),
const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKPICard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

 void _clearControllers() {
  _codeController.clear();
  _nameController.clear();
  _phoneController.clear();
  _nationalityController.clear();
  _positionController.clear();
  _notesController.clear();
  _mothersNameController.clear();
  _birthDateController.clear();
  _birthPlaceController.clear();
  _locationController.clear();
  _dailyRateController.clear();
  _regularHourlyRateController.clear();
  _overtimeHourlyRateController.clear();
  _reasonController.clear();
  _effectiveDateController.clear();
  _paymentType = 'Daily';
  _selectedPersonalPhoto = null;
  _selectedIdPhoto = null;
  _hireDateController.text = DateTime.now().toIso8601String().split('T')[0];
}

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: bgColor, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const AppDrawer(),
     appBar: CustomAppBar(
  title: 'Workers Management',
  actions: [
    IconButton(
      icon: const Icon(Icons.price_change_rounded),
      tooltip: 'Bulk Update Compensation',
      onPressed: _openBulkCompensationSheet,
    ),
    IconButton(
      icon: const Icon(Icons.refresh_rounded),
      tooltip: 'Refresh',
      onPressed: _fetchWorkers,
    ),
  ],
),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openWorkerSheet(),
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Worker', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      _buildKPICard('Total', '$_totalWorkers', primaryColor, Icons.group_rounded),
                      const SizedBox(width: 8),
                      _buildKPICard('Active', '$_activeWorkers', Colors.green.shade700, Icons.check_circle_rounded),
                      const SizedBox(width: 8),
                      _buildKPICard('Inactive', '$_inactiveWorkers', Colors.red.shade700, Icons.cancel_rounded),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name, ID or position...',
                      prefixIcon: Icon(Icons.search_rounded, color: primaryColor),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _filterWorkers();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _filteredWorkers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off_rounded, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('No workers found', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: _filteredWorkers.length,
                          itemBuilder: (context, index) {
                            final worker = _filteredWorkers[index];
                            final isActive = worker['status'] == 'Active';
                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => WorkerProfileScreen(worker: worker),
                                    ),
                                  );
                                },
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: ProtectedAvatar(
                                  url: worker['personal_photo']?.toString(),
                                  backgroundColor: isActive ? primaryColor.withOpacity(0.1) : Colors.grey.shade200,
                                  iconColor: isActive ? primaryColor : Colors.grey,
                                ),
                                title: Text(
                                  worker['full_name'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const SizedBox(height: 4),

    Text(
      'ID: ${worker['worker_unique_id']} | Position: ${worker['job_position'] ?? 'N/A'}',
      style: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 13,
      ),
    ),

    const SizedBox(height: 4),

    // Active / Inactive badge
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.shade50
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: isActive
              ? Colors.green.shade700
              : Colors.red.shade700,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),

    // ==========================================
    // Assigned Site
    // ==========================================
    const SizedBox(height: 4),

    Builder(
      builder: (_) {
        final siteName = worker['assigned_site_name']?.toString();
        final isAssigned =
            siteName != null && siteName.trim().isNotEmpty;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: isAssigned
                ? Colors.green.shade50
                : Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on,
                size: 12,
                color: isAssigned
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  isAssigned
                      ? siteName!
                      : 'Not assigned to a site',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isAssigned
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  ],
),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openWorkerSheet(worker: worker);
                                    } else if (value == 'status') {
                                      _toggleWorkerStatus(worker['worker_unique_id'], worker['status']);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                                    PopupMenuItem(
                                      value: 'status',
                                      child: Row(
                                        children: [
                                          Icon(isActive ? Icons.block : Icons.check_circle, size: 18, color: isActive ? Colors.orange : Colors.green),
                                          const SizedBox(width: 8),
                                          Text(isActive ? 'Set Inactive' : 'Set Active'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}