import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_data_table.dart';
import 'staff_lifecycle_screen.dart';
import 'staff_supervisor_assignment_screen.dart';
import 'staff_overtime_screen.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({Key? key}) : super(key: key);

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final String _apiUrl = '/staff';

  List<dynamic> _staffList = [];
  bool _isLoading = true;
  String _searchQuery = "";

  List<dynamic> _staffSupervisorsForBulk = [];
  final Set<int> _bulkAssignSelectedStaffIds = <int>{};
  int? _bulkAssignSelectedSupervisorId;
  final TextEditingController _bulkAssignDateController =
      TextEditingController();
  final TextEditingController _bulkAssignNotesController =
      TextEditingController();
  bool _isBulkAssignSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _bulkAssignDateController.dispose();
    _bulkAssignNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get(_apiUrl);
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _staffList = response.data['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error loading staff: $e');
      _showSnackBar('Failed to load staff members', AppColors.danger);
    }
    setState(() => _isLoading = false);
  }

  void _showSnackBar(String message, Color color, {Duration? duration}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _openAddOrEditSheet({Map<String, dynamic>? staff}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddEditStaffSheet(
        staff: staff,
        apiUrl: _apiUrl,
        onSaved: () {
          _loadStaff();
          _showSnackBar(
            staff == null
                ? 'Staff member added successfully!'
                : 'Staff member updated successfully!',
            Colors.green.shade700,
          );
        },
      ),
    );
  }

  void _openLifecycleScreen(Map<String, dynamic> staff) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffLifecycleScreen(staff: staff),
      ),
    ).then((_) => _loadStaff());
  }

  void _openSupervisorAssignmentScreen(Map<String, dynamic> staff) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffSupervisorAssignmentScreen(staff: staff),
      ),
    ).then((_) => _loadStaff());
  }

  void _openOvertimeScreen(Map<String, dynamic> staff) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffOvertimeScreen(staff: staff),
      ),
    );
  }

  Future<void> _openBulkAssignSupervisorSheet() async {
    try {
      final response = await ApiConfig.dio.get(
        '/users/supervisors',
        queryParameters: {'role': 'StaffSupervisor'},
      );
      _staffSupervisorsForBulk =
          (response.data['data'] as List? ?? [])
              .where((s) => s['status'] == 'Active')
              .toList();
    } catch (_) {
      _showSnackBar(
        'Failed to load staff supervisors',
        AppColors.danger,
      );
      return;
    }

    if (!mounted) return;

    if (_staffSupervisorsForBulk.isEmpty) {
      _showSnackBar(
        'No active Staff Supervisors available.',
        Colors.orange,
      );
      return;
    }

    _bulkAssignSelectedStaffIds.clear();
    _bulkAssignSelectedSupervisorId = null;
    _bulkAssignDateController.text =
        DateTime.now().toIso8601String().split('T')[0];
    _bulkAssignNotesController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bulk Assign Staff Supervisor',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This assigns ONE supervisor to all selected staff members. Each staff member keeps their own independent assignment history.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),

                DropdownButtonFormField<int>(
                  value: _bulkAssignSelectedSupervisorId,
                  decoration: const InputDecoration(
                    labelText: 'Staff Supervisor *',
                    border: OutlineInputBorder(),
                  ),
                  items: _staffSupervisorsForBulk
                      .map<DropdownMenuItem<int>>(
                        (s) => DropdownMenuItem(
                          value: s['user_id'] as int,
                          child: Text(s['full_name'] ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setModalState(
                    () => _bulkAssignSelectedSupervisorId = v,
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _bulkAssignDateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Effective Date *',
                    prefixIcon: Icon(Icons.event_available),
                    border: OutlineInputBorder(),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setModalState(() {
                        _bulkAssignDateController.text =
                            picked.toIso8601String().split('T')[0];
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _bulkAssignNotesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Text(
                      'Select Staff (${_bulkAssignSelectedStaffIds.length} selected)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                  TextButton(
  onPressed: () => setModalState(() {
    final selectableStaff = _staffList
        .where(
          (s) =>
              s['status'] != 'Terminated' &&
              s['status'] != 'Inactive',
        )
        .map<int>(
          (s) => s['staff_id'] as int,
        )
        .toList();

    if (_bulkAssignSelectedStaffIds.length ==
        selectableStaff.length) {
      _bulkAssignSelectedStaffIds.clear();
    } else {
      _bulkAssignSelectedStaffIds
        ..clear()
        ..addAll(selectableStaff);
    }
  }),
  child: Builder(
    builder: (_) {
      final selectableCount = _staffList
          .where(
            (s) =>
                s['status'] != 'Terminated' &&
                s['status'] != 'Inactive',
          )
          .length;

      return Text(
        _bulkAssignSelectedStaffIds.length ==
                selectableCount
            ? 'Deselect All'
            : 'Select All',
      );
    },
  ),
),
                  ],
                ),

                Container(
                  constraints: const BoxConstraints(
                    maxHeight: 280,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _staffList.length,
                    itemBuilder: (context, index) {
                      final staff = _staffList[index];
                      final id = staff['staff_id'] as int;
                      final isDisabled =
    staff['status'] == 'Terminated' ||
    staff['status'] == 'Inactive';
                      final selected =
                          _bulkAssignSelectedStaffIds.contains(id);

                      return CheckboxListTile(
                        dense: true,
                        enabled: !isDisabled,
                        value: selected,
                        title: Text(
                          staff['full_name'] ?? '',
                        ),
                        subtitle: Text(
                         '${staff['staff_unique_id'] ?? ''}${isDisabled ? ' • ${staff['status']}' : ''}'
                        ),
                        onChanged: isDisabled
                            ? null
                            : (checked) => setModalState(() {
                                  if (checked == true) {
                                    _bulkAssignSelectedStaffIds.add(id);
                                  } else {
                                    _bulkAssignSelectedStaffIds.remove(id);
                                  }
                                }),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isBulkAssignSubmitting
                        ? null
                        : () => _submitBulkAssignSupervisor(
                              setModalState,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isBulkAssignSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Assign Supervisor to Selected',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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

  Future<void> _submitBulkAssignSupervisor(
    void Function(void Function()) setModalState,
  ) async {
    if (_bulkAssignSelectedSupervisorId == null) {
      _showSnackBar(
        'Please select a supervisor.',
        Colors.orange,
      );
      return;
    }

    if (_bulkAssignSelectedStaffIds.isEmpty) {
      _showSnackBar(
        'Please select at least one staff member.',
        Colors.orange,
      );
      return;
    }

    setModalState(
      () => _isBulkAssignSubmitting = true,
    );
    setState(
      () => _isBulkAssignSubmitting = true,
    );

    try {
      final response = await ApiConfig.dio.post(
        '/staff/supervisor-assignments/bulk',
        data: {
          'staff_ids': _bulkAssignSelectedStaffIds.toList(),
          'supervisor_user_id': _bulkAssignSelectedSupervisorId,
          'assigned_date':
              _bulkAssignDateController.text.trim(),
          'notes':
              _bulkAssignNotesController.text.trim().isEmpty
                  ? null
                  : _bulkAssignNotesController.text.trim(),
        },
      );

      if (mounted) {
        Navigator.pop(context);

        final message =
            response.data is Map &&
                    response.data['message'] != null
                ? response.data['message'].toString()
                : 'Supervisor assigned successfully';

        _showSnackBar(
          message,
          Colors.green.shade700,
        );

        _loadStaff();
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ??
              'Bulk assign failed')
          : 'Bulk assign failed';

      setModalState(
        () => _isBulkAssignSubmitting = false,
      );
      setState(
        () => _isBulkAssignSubmitting = false,
      );

      _showSnackBar(
        msg,
        AppColors.danger,
      );
    } catch (e) {
      setModalState(
        () => _isBulkAssignSubmitting = false,
      );
      setState(
        () => _isBulkAssignSubmitting = false,
      );

      _showSnackBar(
        'Bulk assign failed: ${e.toString()}',
        AppColors.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredStaff = _staffList.where((s) {
      final fullName =
          (s['full_name'] ?? '').toString().toLowerCase();
      final position =
          (s['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return fullName.contains(query) ||
          position.contains(query);
    }).toList();

    final activeCount =
        _staffList.where((s) => s['status'] == 'Active').length;

    final inactiveCount =
        _staffList.where((s) => s['status'] == 'Inactive').length;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Staff Management',
        actions: [
          IconButton(
            icon: const Icon(
              Icons.supervisor_account_rounded,
            ),
            tooltip: 'Bulk Assign Supervisor',
            onPressed: _openBulkAssignSupervisorSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _buildStatCard(
                        'Total',
                        _staffList.length.toString(),
                        AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      _buildStatCard(
                        'Active',
                        activeCount.toString(),
                        Colors.green.shade700,
                      ),
                      const SizedBox(width: 10),
                      _buildStatCard(
                        'Inactive',
                        inactiveCount.toString(),
                        AppColors.danger,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  child: TextField(
                    onChanged: (val) =>
                        setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText:
                          'Search by name or position...',
                      prefixIcon:
                          const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filteredStaff.isEmpty
                      ? const Center(
                          child: Text(
                            'No staff members found',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView(
                          padding:
                              const EdgeInsets.all(12),
                          children: [
                            AppDataTableCard(
                              title: 'Staff List',
                              icon: Icons.badge_rounded,
                              accentColor:
                                  AppColors.primary,
                              emptyMessage:
                                  'No staff members registered yet.',
                              trailing: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration:
                                    BoxDecoration(
                                  color:
                                      Colors.blue.shade50,
                                  borderRadius:
                                      BorderRadius.circular(
                                    10,
                                  ),
                                ),
                                child: Text(
                                  'Total: ${filteredStaff.length}',
                                  style: TextStyle(
                                    color:
                                        Colors.blue.shade900,
                                    fontWeight:
                                        FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              columns: const [
                                DataColumn(
                                  label: Text('#'),
                                ),
                                DataColumn(
                                  label: Text('Staff Info'),
                                ),
                                DataColumn(
                                  label: Text('Salary'),
                                ),
                                DataColumn(
                                  label: Text('Status'),
                                ),
                                DataColumn(
                                  label: Text('Actions'),
                                ),
                              ],
                              rows: List.generate(
                                filteredStaff.length,
                                (index) {
                                  final stf =
                                      filteredStaff[index];

                                  final status =
                                      stf['status']
                                              ?.toString() ??
                                          'Inactive';

                                  final isActive =
                                      status == 'Active';
                                  final isTerminated =
                                      status ==
                                          'Terminated';

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          '${index + 1}',
                                        ),
                                      ),
                                      DataCell(
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          mainAxisAlignment:
                                              MainAxisAlignment
                                                  .center,
                                          children: [
                                            Text(
                                              stf['full_name'] ??
                                                  'N/A',
                                              style:
                                                  const TextStyle(
                                                fontWeight:
                                                    FontWeight
                                                        .bold,
                                              ),
                                            ),
                                            Text(
                                              '${stf['staff_unique_id'] ?? ''} • ${stf['position'] ?? 'No Position'}',
                                              style:
                                                  const TextStyle(
                                                fontSize: 11,
                                                color:
                                                    Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${stf['monthly_salary'] ?? '0.00'}',
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding:
                                              const EdgeInsets
                                                  .symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration:
                                              BoxDecoration(
                                            color: isActive
                                                ? Colors.green
                                                    .shade50
                                                : isTerminated
                                                    ? Colors
                                                        .grey
                                                        .shade200
                                                    : Colors
                                                        .red
                                                        .shade50,
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              color: isActive
                                                  ? Colors.green
                                                      .shade700
                                                  : isTerminated
                                                      ? Colors
                                                          .grey
                                                          .shade700
                                                      : Colors
                                                          .red
                                                          .shade700,
                                              fontSize: 11,
                                              fontWeight:
                                                  FontWeight
                                                      .bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize:
                                              MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon:
                                                  const Icon(
                                                Icons
                                                    .edit_rounded,
                                                color:
                                                    Colors.blue,
                                                size: 20,
                                              ),
                                              tooltip: 'Edit',
                                              onPressed: () =>
                                                  _openAddOrEditSheet(
                                                staff: stf,
                                              ),
                                            ),

                                            // All staff status changes
                                            // now go through the lifecycle screen.
                                            IconButton(
                                              icon:
                                                  const Icon(
                                                Icons
                                                    .swap_horiz,
                                              ),
                                              tooltip:
                                                  'Change status',
                                              onPressed: () =>
                                                  _openLifecycleScreen(
                                                    stf,
                                                  ),
                                            ),

                                            PopupMenuButton<
                                                String>(
                                              icon:
                                                  const Icon(
                                                Icons.more_vert,
                                                size: 20,
                                                color:
                                                    Colors.grey,
                                              ),
                                              onSelected:
                                                  (value) {
                                                if (value ==
                                                    'edit') {
                                                  _openAddOrEditSheet(
                                                    staff: stf,
                                                  );
                                                } else if (value ==
                                                    'lifecycle') {
                                                  _openLifecycleScreen(
                                                    stf,
                                                  );
                                                } else if (value ==
                                                    'supervisor') {
                                                  _openSupervisorAssignmentScreen(
                                                    stf,
                                                  );
                                                } else if (value ==
                                                    'overtime') {
                                                  _openOvertimeScreen(
                                                    stf,
                                                  );
                                                }
                                              },
                                              itemBuilder:
                                                  (context) => [
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .edit,
                                                        size:
                                                            18,
                                                        color:
                                                            Colors.blue,
                                                      ),
                                                      SizedBox(
                                                        width:
                                                            8,
                                                      ),
                                                      Text(
                                                        'Edit',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value:
                                                      'lifecycle',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .timeline,
                                                        size:
                                                            18,
                                                        color:
                                                            Colors.purple,
                                                      ),
                                                      SizedBox(
                                                        width:
                                                            8,
                                                      ),
                                                      Text(
                                                        'Lifecycle & Site',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value:
                                                      'supervisor',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .supervisor_account,
                                                        size:
                                                            18,
                                                        color:
                                                            Colors.teal,
                                                      ),
                                                      SizedBox(
                                                        width:
                                                            8,
                                                      ),
                                                      Text(
                                                        'Assign Supervisor',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value:
                                                      'overtime',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .more_time_rounded,
                                                        size:
                                                            18,
                                                        color:
                                                            Colors
                                                                .deepOrange,
                                                      ),
                                                      SizedBox(
                                                        width:
                                                            8,
                                                      ),
                                                      Text(
                                                        'Monthly Extra time Ledger',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () =>
            _openAddOrEditSheet(),
        child: const Icon(
          Icons.person_add_alt_1,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddEditStaffSheet extends StatefulWidget {
  final Map<String, dynamic>? staff;
  final String apiUrl;
  final VoidCallback onSaved;

  const _AddEditStaffSheet({
    this.staff,
    required this.apiUrl,
    required this.onSaved,
  });

  @override
  State<_AddEditStaffSheet> createState() =>
      _AddEditStaffSheetState();
}

class _AddEditStaffSheetState
    extends State<_AddEditStaffSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _positionController;
  late TextEditingController _hireDateController;
  late TextEditingController _salaryController;
  late TextEditingController _dailyHoursController;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.staff?['full_name'] ?? '',
    );

    _phoneController = TextEditingController(
      text: widget.staff?['phone_number'] ?? '',
    );

    _positionController = TextEditingController(
      text: widget.staff?['position'] ?? '',
    );

    _hireDateController = TextEditingController(
      text: widget.staff?['hire_date']?.toString().split('T').first
          ?? DateTime.now().toIso8601String().split('T').first,
    );

    _salaryController = TextEditingController(
      text:
          widget.staff?['monthly_salary']?.toString() ??
              '',
    );

    _dailyHoursController = TextEditingController(
      text:
          widget.staff?['standard_daily_hours']
                  ?.toString() ??
              '8.00',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    _hireDateController.dispose();
    _salaryController.dispose();
    _dailyHoursController.dispose();
    super.dispose();
  }

  // D3: when salary or standard hours change, ask from which date the new
  // values apply (history keeps the old values for earlier dates).
  Future<Map<String, String>?> _askCompensationChange() async {
    DateTime effective = DateTime.now();
    final reasonCtl = TextEditingController();
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Salary / hours change'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('From which date do the new values apply? Earlier dates keep the old values.'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 16),
                label: Text('Effective from: ${fmt(effective)}'),
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
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtl,
                decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      ),
    );
    final reason = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (ok != true) return null;
    return {
      'compensation_effective_from': fmt(effective),
      if (reason.isNotEmpty) 'compensation_reason': reason,
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    Map<String, String>? compensationChange;
    if (widget.staff != null) {
      final oldSalary = double.tryParse('${widget.staff?['monthly_salary'] ?? ''}');
      final oldHours = double.tryParse('${widget.staff?['standard_daily_hours'] ?? ''}');
      final newSalary = double.tryParse(_salaryController.text.trim());
      final newHours = double.tryParse(_dailyHoursController.text.trim()) ?? 8.00;
      if (oldSalary != newSalary || oldHours != newHours) {
        compensationChange = await _askCompensationChange();
        if (compensationChange == null) return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final isEditing = widget.staff != null;
      final staffId = widget.staff?['staff_id'];

      final payload = {
        'full_name':
            _nameController.text.trim(),
        'phone_number':
            _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
        'position':
            _positionController.text.trim().isEmpty
                ? null
                : _positionController.text.trim(),
        'hire_date': _hireDateController.text.trim(),
        'monthly_salary':
            double.parse(
          _salaryController.text.trim(),
        ),
        'standard_daily_hours':
            double.tryParse(
                  _dailyHoursController.text.trim(),
                ) ??
                8.00,
        if (compensationChange != null) ...compensationChange,
      };

      if (isEditing) {
        final response =
            await ApiConfig.dio.put(
          '${widget.apiUrl}/$staffId',
          data: payload,
        );

        if (response.statusCode == 200) {
          Navigator.pop(context);
          widget.onSaved();
        }
      } else {
        final response =
            await ApiConfig.dio.post(
          widget.apiUrl,
          data: payload,
        );

        if (response.statusCode == 201 ||
            response.statusCode == 200) {
          Navigator.pop(context);
          widget.onSaved();
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ??
              'Operation failed')
          : 'Operation failed';

      setState(
        () => _errorMessage = msg,
      );
    } catch (e) {
      setState(
        () => _errorMessage =
            'Connection error, please try again',
      );
    } finally {
      if (mounted) {
        setState(
          () => _isSubmitting = false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.staff != null;

    return Container(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
                20,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  isEditing
                      ? 'Edit Staff Member'
                      : 'Add New Staff Member',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.person),
                ),
                validator: (val) =>
                    val == null || val.isEmpty
                        ? 'Please enter full name'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType:
                    TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller:
                    _positionController,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Position / Job Title',
                  border:
                      OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.work_outline,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hireDateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Hire Date *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event_available),
                ),
                onTap: () async {
                  final current = DateTime.tryParse(_hireDateController.text);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: current ?? DateTime.now(),
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    _hireDateController.text =
                        '${picked.year.toString().padLeft(4, '0')}-'
                        '${picked.month.toString().padLeft(2, '0')}-'
                        '${picked.day.toString().padLeft(2, '0')}';
                  }
                },
                validator: (value) {
                  final date = DateTime.tryParse(value ?? '');
                  return date == null ? 'Please select a valid hire date' : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller:
                    _salaryController,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Monthly Salary *',
                  border:
                      OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.attach_money,
                  ),
                ),
                validator: (val) {
                  if (val == null ||
                      val.isEmpty) {
                    return 'Please enter monthly salary';
                  }

                  if (double.tryParse(val) ==
                          null ||
                      double.parse(val) < 0) {
                    return 'Invalid salary value';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller:
                    _dailyHoursController,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Standard Daily Hours',
                  border:
                      OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.access_time,
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Colors.red.shade50,
                    border: Border.all(
                      color:
                          Colors.red.shade300,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      10,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color:
                            AppColors.danger,
                        size: 22,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color:
                                Colors.red.shade900,
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      10,
                    ),
                  ),
                ),
                onPressed:
                    _isSubmitting
                        ? null
                        : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEditing
                            ? 'Update Staff Member'
                            : 'Save Staff Member',
                        style:
                            const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
