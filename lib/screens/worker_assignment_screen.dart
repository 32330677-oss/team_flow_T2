import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/searchable_picker_sheet.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_data_table.dart';

class WorkerAssignmentScreen extends StatefulWidget {
  const WorkerAssignmentScreen({Key? key}) : super(key: key);

  @override
  State<WorkerAssignmentScreen> createState() => _WorkerAssignmentScreenState();
}

class _WorkerAssignmentScreenState extends State<WorkerAssignmentScreen> {
  List<dynamic> _assignments = [];
  List<dynamic> _workers = [];
  List<dynamic> _sites = []; 
  bool _isLoading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final resWorkers = await ApiConfig.dio.get('/workers');
      if (resWorkers.statusCode == 200) _workers = resWorkers.data['data'] ?? [];
      
      final resSites = await ApiConfig.dio.get('/sites/all-sites');
      if (resSites.statusCode == 200) _sites = resSites.data['data'] ?? [];
      
      final resAssignments = await ApiConfig.dio.get('/assignments');
      if (resAssignments.statusCode == 200) _assignments = resAssignments.data['data'] ?? [];
      
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _deleteAssignment(int assignmentId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to end this worker assignment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiConfig.dio.delete('/assignments/$assignmentId');
      _loadData(); 
      _showSnackBar('Assignment ended successfully', Colors.blue);
    } catch (e) {
      _showSnackBar('Failed to end assignment', AppColors.danger);
    }
  }

  // دالة نقل العامل لموقع جديد
  Future<void> _transferWorker(Map<String, dynamic> assignment) async {
    final currentSiteId = int.tryParse(assignment['site_id']?.toString() ?? '0') ?? 0;
    final workerId = int.tryParse(assignment['worker_id']?.toString() ?? '0') ?? 0;
    final workerName = assignment['worker_name'] ?? 'Worker';

    // فلترة المواقع لإظهار المواقع الأخرى عدا الموقع الحالي
    final availableSites = _sites.where((s) {
      final sId = int.tryParse(s['site_id']?.toString() ?? '0') ?? 0;
      return sId != currentSiteId;
    }).toList();

    if (availableSites.isEmpty) {
      _showSnackBar('No other available sites to transfer to', Colors.orange);
      return;
    }

    // فتح شاشة بحث واختيار الموقع الجديد
    final pickedSite = await SearchablePickerSheet.show<dynamic>(
      context,
      title: 'Transfer $workerName to New Site',
      items: availableSites,
      labelBuilder: (s) => s['site_name'] ?? '',
    );

    if (pickedSite == null) return;

    final newSiteId = int.tryParse(pickedSite['site_id'].toString());
    final assignmentId = int.tryParse(assignment['assignment_id']?.toString() ?? '0');

    if (newSiteId == null || assignmentId == null) return;

    // إظهار مؤشر تحميل أو تنفيذ النقل
    try {
      // 1. حذف القديم أو تعديله حسب الـ API لديك (الطريقة القياسية: حذف التعيين القديم وإنشاء جديد أو استدعاء مسار النقل)
      // هنا سنقوم بحذف التعيين القديم وإنشاء التعيين الجديد في الموقع الجديد مباشرة لضمان سلامة الـ API
      await ApiConfig.dio.delete('/assignments/$assignmentId');
      
      final response = await ApiConfig.dio.post('/assignments', data: {
        'worker_id': workerId,
        'site_id': newSiteId,
        'shift_type': assignment['shift_type'],
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        _loadData();
        _showSnackBar('Worker transferred successfully!', Colors.green.shade700);
      }
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to transfer worker')
          : 'Failed to transfer worker';
      _showSnackBar(errorMessage, AppColors.danger);
    } catch (e) {
      _showSnackBar('Connection error during transfer', AppColors.danger);
    }
  }

  void _showSnackBar(String message, Color color, {Duration? duration}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<dynamic> _getWorkersForSite(int siteId) {
    return _assignments.where((item) {
      final sId = int.tryParse(item['site_id']?.toString() ?? '0') ?? 0;
      return sId == siteId;
    }).toList();
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddAssignmentSheet(
        workers: _workers,
        sites: _sites,
        onAssigned: () {
          _loadData();
          _showSnackBar('Assignment saved successfully!', Colors.green.shade700);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSites = _sites.where((site) {
      final siteName = site['site_name'].toString().toLowerCase();
      final siteId = int.tryParse(site['site_id']?.toString() ?? '0') ?? 0;
      final siteWorkers = _getWorkersForSite(siteId);
      
      final matchesSiteName = siteName.contains(_searchQuery.toLowerCase());
      final matchesWorkerName = siteWorkers.any((w) => 
        w['worker_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
      );

      return matchesSiteName || matchesWorkerName;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: const CustomAppBar(
        title: 'Workers & Sites Distribution',
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _buildStatCard('Sites', _sites.length.toString(), AppColors.primary),
                    const SizedBox(width: 10),
                    _buildStatCard('Assignments', _assignments.length.toString(), Colors.blue.shade700),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by site or worker...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filteredSites.isEmpty
                    ? const Center(child: Text('No sites found', style: TextStyle(color: Colors.grey, fontSize: 16)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredSites.length,
                        itemBuilder: (context, index) {
                          final site = filteredSites[index];
                          final siteId = int.tryParse(site['site_id']?.toString() ?? '0') ?? 0;
                          final siteWorkers = _getWorkersForSite(siteId);

                          // تحويل العمال إلى صفوف جدول مع إضافة زر النقل (Transfer) وزر الحذف
                          final rows = List.generate(siteWorkers.length, (wIndex) {
                            final assignment = siteWorkers[wIndex];
                            return DataRow(
                              cells: [
                                DataCell(Text('${wIndex + 1}')),
                                DataCell(
                                  Row(
                                    children: [
                                      const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(assignment['worker_name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // زر النقل (Transfer)
                                      IconButton(
                                        icon: const Icon(Icons.swap_horiz, color: Colors.blue, size: 20),
                                        tooltip: 'Transfer Worker',
                                        onPressed: () => _transferWorker(assignment),
                                      ),
                                      // زر الحذف (End Assignment)
                                      IconButton(
                                        icon: const Icon(Icons.delete_forever, color: AppColors.danger, size: 20),
                                        tooltip: 'End Assignment',
                                        onPressed: () => _deleteAssignment(assignment['assignment_id']),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          });

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: AppDataTableCard(
                              title: site['site_name'] ?? 'Unknown Site',
                              icon: Icons.business,
                              accentColor: AppColors.primary,
                              emptyMessage: 'No workers assigned to this site yet.',
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Workers: ${siteWorkers.length}',
                                  style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              columns: const [
                                DataColumn(label: Text('#')),
                                DataColumn(label: Text('Worker Name')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: rows,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _openAddSheet,
        child: const Icon(Icons.person_add_alt_1, color: Colors.white),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Text(title, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 5),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAssignmentSheet extends StatefulWidget {
  final List<dynamic> workers;
  final List<dynamic> sites;
  final VoidCallback onAssigned;

  const _AddAssignmentSheet({
    required this.workers,
    required this.sites,
    required this.onAssigned,
  });

  @override
  State<_AddAssignmentSheet> createState() => _AddAssignmentSheetState();
}

class _AddAssignmentSheetState extends State<_AddAssignmentSheet> {
  int? _selectedWorkerId;
  int? _selectedSiteId;
  Map<String, dynamic>? _selectedWorkerObj;
  Map<String, dynamic>? _selectedSiteObj;
  String _selectedShiftType = 'Day';
  bool _isSubmitting = false;
  String? _errorMessage;

  final _assignedDateController = TextEditingController(
    text: DateTime.now().toIso8601String().split('T')[0],
  );

  @override
  void dispose() {
    _assignedDateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (_selectedWorkerId == null || _selectedSiteId == null) {
      setState(() => _errorMessage = 'Please select both worker and site first');
      return;
    }

    final assignedDate = _assignedDateController.text.trim();
    if (assignedDate.isEmpty) {
      setState(() => _errorMessage = 'Please select an assignment date');
      return;
    }

    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    if (assignedDate != todayStr) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (confirmCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Backdated Assignment'),
          content: Text(
            'This worker will be assigned to the site starting from $assignedDate '
            'instead of today.\n\n'
            'Make sure this date is on or after the worker\'s Hire Date, otherwise '
            'the assignment will be rejected.\n\nContinue?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(confirmCtx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiConfig.dio.post('/assignments', data: {
        'worker_id': _selectedWorkerId,
        'site_id': _selectedSiteId,
        'assigned_date': assignedDate,
        'shift_type': (_selectedSiteObj?['supports_shifts'] == 1)
            ? _selectedShiftType
            : 'Day',
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        Navigator.pop(context);
        widget.onAssigned();
      }
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to save data')
          : 'Failed to save data';

      setState(() => _errorMessage = errorMessage);
    } catch (e) {
      setState(() => _errorMessage = 'Connection error, please try again');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20, left: 20, right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              'Assign Worker to Site', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            ),
          ),
          const SizedBox(height: 20),
          
          // حقل اختيار العامل
          InkWell(
            onTap: () async {
              final picked = await SearchablePickerSheet.show<dynamic>(
                context,
                title: 'Select Worker',
                items: widget.workers,
                labelBuilder: (w) => w['full_name'] ?? '',
                subtitleBuilder: (w) => 'ID: ${w['worker_unique_id'] ?? ''}',
              );
              if (picked != null) {
                setState(() {
                  _selectedWorkerObj = picked;
                  _selectedWorkerId = int.tryParse(picked['worker_id'].toString());
                  _errorMessage = null;
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Worker',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              child: Text(
                _selectedWorkerObj?['full_name'] ?? 'Click to search & select worker',
                style: TextStyle(
                  color: _selectedWorkerObj != null ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // حقل اختيار الموقع
          InkWell(
            onTap: () async {
              final picked = await SearchablePickerSheet.show<dynamic>(
                context,
                title: 'Select Site',
                items: widget.sites,
                labelBuilder: (s) => s['site_name'] ?? '',
              );
              if (picked != null) {
                setState(() {
                  _selectedSiteObj = picked;
                  _selectedSiteId = int.tryParse(picked['site_id'].toString());
                  _errorMessage = null;
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Site',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              child: Text(
                _selectedSiteObj?['site_name'] ?? 'Click to search & select site',
                style: TextStyle(
                  color: _selectedSiteObj != null ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // اختيار الشيفت (يظهر فقط إذا كان الموقع يدعم الشيفتات supports_shifts == 1)
          if (_selectedSiteObj?['supports_shifts'] == 1) ...[
            const Text(
              'Shift Type',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Day'),
                    value: 'Day',
                    groupValue: _selectedShiftType,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedShiftType = value);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Night'),
                    value: 'Night',
                    groupValue: _selectedShiftType,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedShiftType = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // حقل تاريخ التعيين
          TextField(
            controller: _assignedDateController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Assignment Date *',
              hintText: 'YYYY-MM-DD',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.event_available),
              helperText:
                  'Defaults to today. Backdate this if the worker actually started at this site earlier.',
              helperMaxLines: 3,
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_assignedDateController.text) ?? DateTime.now(),
                firstDate: DateTime(2015),
                lastDate: DateTime.now(),
                helpText: 'Select the assignment start date',
              );
              if (picked != null) {
                setState(() {
                  _assignedDateController.text =
                      "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                });
              }
            },
          ),
          
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue, // استبدل بـ AppColors.primary إذا كنت تعتمدها
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Save Assignment', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}