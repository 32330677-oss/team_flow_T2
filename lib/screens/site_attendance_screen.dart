import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
import '../widgets/app_data_table.dart';
import 'rejected_records_screen.dart';
import 'package:intl/intl.dart';

// في تعريف الـ Widget، أضف الحقل الجديد:
class SiteAttendanceScreen extends StatefulWidget {
  final int siteId;
  final String siteName;
  final String shiftType; // 'Day' أو 'Night' — إلزامي الآن

  const SiteAttendanceScreen({
    super.key,
    required this.siteId,
    required this.siteName,
    this.shiftType = 'Day', // افتراضي للمواقع القديمة غير الشيفتية
  });

  @override
  _SiteAttendanceScreenState createState() => _SiteAttendanceScreenState();
}

class _SiteAttendanceScreenState extends State<SiteAttendanceScreen> {
  bool _isLoading = true;
  String _recordDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  final Set<int> _selectedWorkerIds = <int>{};

  List<dynamic> _workers = [];
  List<dynamic> _mySitesForTransfer = [];

  // bool
  TimeOfDay? _defaultLunchStart;
  TimeOfDay? _defaultLunchEnd;

  final Map<int, Map<String, TimeOfDay>> _lunchOverrides = {};
  final Set<int> _lunchExcludedWorkerIds = <int>{};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

Future<void> _fetchWorkers() async {
  if (!mounted) return;
  setState(() => _isLoading = true);
  try {
    final response = await ApiConfig.dio.get(
      '/attendance/sites/${widget.siteId}/workers',
      queryParameters: {
        'record_date': _recordDate,
        'shift_type': widget.shiftType, // ← جديد
      },
    );
    if (!mounted) return;
    setState(() {
      _workers = response.data['data'] ?? [];
      _lunchExcludedWorkerIds.clear();
      _lunchOverrides.clear();
      _isLoading = false;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showToast('Failed to load workers', Colors.red);
  }
}

  List<dynamic> get _lunchEligibleWorkers {
    return _workers.where((w) {
      final workflow = w['workflow_status']?.toString();
      final isDraft = workflow == null || workflow == 'Draft';

      return isDraft &&
          w['check_in_time'] != null &&
          w['check_out_time'] != null;
    }).toList();
  }

  List<dynamic> get _filteredWorkers {
    if (_searchQuery.trim().isEmpty) return _workers;

    final q = _searchQuery.trim().toLowerCase();

    return _workers
        .where(
          (w) => (w['full_name'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q),
        )
        .toList();
  }

 Future<void> _handleAction(
  String endpoint,
  int workerId, {
  Map<String, dynamic>? extraData,
}) async {
  if (!mounted) return;
  setState(() => _isLoading = true);
  try {
    final Map<String, dynamic> payload = {
      'worker_id': workerId,
      'site_id': widget.siteId,
      'record_date': _recordDate,
      'shift_type': widget.shiftType, // ← جديد
    };
    if (extraData != null) payload.addAll(extraData);
    await ApiConfig.dio.post(endpoint, data: payload);
    await _fetchWorkers();
  } on DioException catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    final data = e.response?.data;
    final msg = data is Map && data['message'] != null ? data['message'].toString() : 'Connection error';
    _showToast(msg, Colors.red);
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showToast('Connection error', Colors.red);
  }
}

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _editTimesDialog(Map worker) async {
    final attendanceId = worker['attendance_id'];

    if (attendanceId == null) {
      _showToast(
        'No attendance record to edit yet.',
        Colors.orange,
      );
      return;
    }

    DateTime? newCheckIn = worker['check_in_time'] != null
        ? DateTime.tryParse(
            worker['check_in_time']
                .toString()
                .replaceFirst(' ', 'T'),
          )
        : null;

    DateTime? newCheckOut = worker['check_out_time'] != null
        ? DateTime.tryParse(
            worker['check_out_time']
                .toString()
                .replaceFirst(' ', 'T'),
          )
        : null;

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Edit Times — ${worker['full_name'] ?? ''}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Check-in'),
                subtitle: Text(
                  newCheckIn == null
                      ? 'Not set'
                      : DateFormat(
                          'yyyy-MM-dd HH:mm',
                        ).format(newCheckIn!),
                ),
                trailing: const Icon(
                  Icons.edit,
                  size: 18,
                ),
                onTap: () async {
                  final picked = await _pickLocalDateTime(
                    helpText: 'Select New Check-in Time',
                    initial: newCheckIn,
                  );

                  if (picked != null) {
                    setDialogState(
                      () => newCheckIn = DateTime.parse(
                        picked.replaceFirst(' ', 'T'),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Check-out'),
                subtitle: Text(
                  newCheckOut == null
                      ? 'Not set'
                      : DateFormat(
                          'yyyy-MM-dd HH:mm',
                        ).format(newCheckOut!),
                ),
                trailing: const Icon(
                  Icons.edit,
                  size: 18,
                ),
                onTap: () async {
                  final picked = await _pickLocalDateTime(
                    helpText: 'Select New Check-out Time',
                    initial: newCheckOut,
                  );

                  if (picked != null) {
                    setDialogState(
                      () => newCheckOut = DateTime.parse(
                        picked.replaceFirst(' ', 'T'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                {
                  'checkIn': newCheckIn,
                  'checkOut': newCheckOut,
                },
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

 final payload = <String, dynamic>{
      'shift_type': widget.shiftType, // ← أضفها هنا
    };

    if (result['checkIn'] != null) {
      payload['check_in_time'] = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(result['checkIn']!);
    }

    if (result['checkOut'] != null) {
      payload['check_out_time'] = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(result['checkOut']!);
    }

    try {
      await ApiConfig.dio.patch(
        '/attendance/$attendanceId/edit-times',
        data: payload,
      );

      await _fetchWorkers();

      if (mounted) {
        _showToast(
          'Times updated successfully.',
          Colors.green,
        );
      }
    } on DioException catch (e) {
      final data = e.response?.data;

      _showToast(
        data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Failed to update times.',
        Colors.red,
      );
    }
  }

  Future<void> _chooseAttendanceDate() async {
    final current = DateTime.parse(_recordDate);

    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select attendance date',
    );

    if (selected == null || !mounted) return;

    setState(() {
      _recordDate = DateFormat(
        'yyyy-MM-dd',
      ).format(selected);

      _selectedWorkerIds.clear();
    });

    await _fetchWorkers();
  }

  void _setRecordDateFromManualDateTime(String value) {
    final parsed = DateTime.tryParse(value);

    if (parsed == null) return;

    final nextDate = DateFormat(
      'yyyy-MM-dd',
    ).format(parsed);

    if (nextDate != _recordDate && mounted) {
      setState(() => _recordDate = nextDate);
    }
  }

bool _canBulkCheckIn(Map worker) {
  final workflow = worker['workflow_status']?.toString();
  final isDraft = workflow == null || workflow == 'Draft';
  if (!isDraft) return false;

  // لا تعتبره "مؤهل" للـ bulk check-in إذا أصلاً مسجل عليه حالة صريحة
  // (Absent/Sick/Vacation/Holiday) ولسا ما دخل. هيك ما بينحط تشيك عليه
  // تلقائياً من "Select Eligible"، وما بيتغير حاله إلا لو السوبرفايزر
  // بيدوس عليه بايدو من القائمة الفردية.
  final attendanceStatus = worker['attendance_status']?.toString();
  final hasExplicitNonPresentStatus = worker['check_in_time'] == null &&
      attendanceStatus != null &&
      attendanceStatus != 'Present';

  return !hasExplicitNonPresentStatus;
}

  bool _canBulkCheckOut(Map worker) {
    final workflow = worker['workflow_status']?.toString();

    return workflow == 'Draft' &&
        worker['check_in_time'] != null &&
        worker['check_out_time'] == null;
  }
bool _canBulkAbsent(Map worker) {
  final workflow = worker['workflow_status']?.toString();
  final isDraft = workflow == null || workflow == 'Draft';

  return isDraft &&
      worker['check_in_time'] == null &&
      worker['check_out_time'] == null;
}

List<int> _eligibleSelectedWorkerIdsForAbsent() {
  return _workers
      .where((worker) {
        final id = int.tryParse(worker['worker_id'].toString());
        if (id == null || !_selectedWorkerIds.contains(id)) return false;
        return _canBulkAbsent(worker);
      })
      .map<int>((worker) => int.parse(worker['worker_id'].toString()))
      .toList();
}
  List<int> _eligibleSelectedWorkerIds(bool checkIn) {
    return _workers
        .where((worker) {
          final id = int.tryParse(
            worker['worker_id'].toString(),
          );

          if (id == null ||
              !_selectedWorkerIds.contains(id)) {
            return false;
          }

          return checkIn
              ? _canBulkCheckIn(worker) &&
                  worker['check_in_time'] == null
              : _canBulkCheckOut(worker);
        })
        .map<int>(
          (worker) => int.parse(
            worker['worker_id'].toString(),
          ),
        )
        .toList();
  }

Future<void> _bulkAttendanceAction({required bool checkIn}) async {
  final workerIds = _eligibleSelectedWorkerIds(checkIn);
  if (workerIds.isEmpty) {
    _showToast(
      checkIn ? 'Select workers who are not checked in.' : 'Select workers who are checked in and not checked out.',
      Colors.orange,
    );
    return;
  }
  final selectedDateTime = await _pickLocalDateTime(
    helpText: checkIn ? 'Select Bulk Check-In Time' : 'Select Bulk Check-Out Time',
  );
  if (selectedDateTime == null) return;
  if (checkIn) _setRecordDateFromManualDateTime(selectedDateTime);

  setState(() => _isLoading = true);
  try {
    final response = await ApiConfig.dio.post(
      checkIn ? '/attendance/bulk/checkin' : '/attendance/bulk/checkout',
      data: {
        'site_id': widget.siteId,
        'shift_type': widget.shiftType, // ← جديد
        'record_date': _recordDate,
        'worker_ids': workerIds,
        checkIn ? 'check_in_time'
            : 'check_out_time': selectedDateTime,
      },
    );

    final data = response.data is Map
        ? response.data as Map
        : <String, dynamic>{};

    final successful =
        (data['successful'] as List?)?.length ?? 0;

    if (mounted) {
      setState(() {
        _selectedWorkerIds.removeAll(workerIds);
        _isLoading = false;
      });

      _showToast(
        '$successful workers updated successfully.',
        Colors.green,
      );
    }

    await _fetchWorkers();
  } on DioException catch (e) {
    if (!mounted) return;

    setState(() => _isLoading = false);

    final data = e.response?.data;

    _showToast(
      data is Map && data['message'] != null
          ? data['message'].toString()
          : 'Bulk attendance action failed. No changes were saved.',
      Colors.red,
    );
  }
}

Future<void> _bulkMarkAbsent() async {
  final workerIds = _eligibleSelectedWorkerIdsForAbsent();

  if (workerIds.isEmpty) {
    _showToast(
      'Select workers who have not checked in and are not already submitted.',
      Colors.orange,
    );
    return;
  }

  final selectedNames = _workers
      .where((w) => workerIds.contains(int.tryParse(w['worker_id'].toString())))
      .map((w) => w['full_name']?.toString() ?? 'Worker')
      .toList();

  // ---- تأكيد صريح + عرض الأسماء المحددة (بس اللي عليهم check) ----
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.person_off_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Confirm Bulk Absence'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to mark ${workerIds.length} worker(s) as ABSENT for $_recordDate:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            ...selectedNames.map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This action cannot be applied to workers who already checked in.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Mark Absent', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (confirm != true) return;

  setState(() => _isLoading = true);

  try {
final response = await ApiConfig.dio.post(
  '/attendance/bulk/status',
  data: {
    'site_id': widget.siteId,
    'shift_type': widget.shiftType, // ← جديد
    'record_date': _recordDate,
    'worker_ids': workerIds,
    'attendance_status': 'Absent',
  },
);
    final data = response.data is Map ? response.data as Map : <String, dynamic>{};
    final successful = (data['successful'] as List?)?.length ?? workerIds.length;

    if (mounted) {
      setState(() {
        _selectedWorkerIds.removeAll(workerIds);
        _isLoading = false;
      });
      _showToast('$successful worker(s) marked as Absent.', Colors.red.shade700);
    }

    await _fetchWorkers();
  } on DioException catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    final data = e.response?.data;
    _showToast(
      data is Map && data['message'] != null
          ? data['message'].toString()
          : 'Bulk absence action failed. No changes were saved.',
      Colors.red,
    );
  }
}
  void _showToast(
    String message,
    Color color,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAttendanceStatusDialog(
    int workerId, {
    String? currentStatus,
  }) async {
    final selectedStatus = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text(
          'Set Worker Status',
        ),
        children: [
          _statusOption(
            dialogContext,
            'Absent',
            'Absent',
            Icons.person_off,
            Colors.red,
          ),
          _statusOption(
            dialogContext,
            'Sick',
            'Sick Leave',
            Icons.sick,
            Colors.orange,
          ),
          _statusOption(
            dialogContext,
            'Vacation',
            'Annual Leave',
            Icons.beach_access,
            Colors.blue,
          ),
          _statusOption(
            dialogContext,
            'Holiday',
            'Holiday',
            Icons.event,
            Colors.purple,
          ),
        ],
      ),
    );

    if (selectedStatus == null || !mounted) return;

    await _handleAction(
      '/attendance/status',
      workerId,
      extraData: {
        'attendance_status': selectedStatus,
        'remarks':
            '$selectedStatus - recorded by supervisor',
      },
    );
  }

  Widget _statusOption(
    BuildContext context,
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(
        context,
        value,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // Sends a local wall-clock datetime without UTC conversion.
  // The date is selected explicitly so a night shift can end after midnight.
  Future<String?> _pickLocalDateTime({
    required String helpText,
    DateTime? initial,
  }) async {
    final seed = initial ?? DateTime.parse(
      _recordDate,
    );

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(
        seed.year,
        seed.month,
        seed.day,
      ),
      firstDate: DateTime(
        seed.year,
        seed.month,
        seed.day,
      ).subtract(
        const Duration(days: 1),
      ),
      lastDate: DateTime(
        seed.year,
        seed.month,
        seed.day,
      ).add(
        const Duration(days: 2),
      ),
      helpText: 'Select date',
    );

    if (selectedDate == null || !mounted) {
      return null;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        seed,
      ),
      helpText: helpText,
    );

    if (selectedTime == null) return null;

    // Deliberately omit Z/toUtc():
    // backend stores supervisor-selected local time.
    return DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(
      DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      ),
    );
  }

  // -------------------------------------------------------------------
  // Opens a manual picker and sends a literal local wall-clock datetime.
  // The selected shift date is propagated separately as record_date.
 Future<void> _performCheckIn(
    int workerId,
  ) async {
    final selectedDateTime = await _pickLocalDateTime(
      helpText: 'Select Check-In Time',
    );

    if (selectedDateTime == null) return;

    _setRecordDateFromManualDateTime(
      selectedDateTime,
    );

    await _handleAction(
      '/attendance/checkin',
      workerId,
      extraData: {
        'check_in_time': selectedDateTime,
        'shift_type': widget.shiftType, // ← تأكد من إضافتها هنا أيضاً
      },
    );
  }

  Future<void> _performCheckOut(
    int workerId,
  ) async {
    final selectedDateTime = await _pickLocalDateTime(
      helpText: 'Select Check-Out Date and Time',
    );

    if (selectedDateTime == null) return;

    await _handleAction(
      '/attendance/checkout',
      workerId,
      extraData: {
        'check_out_time': selectedDateTime,
      },
    );
  }

  // NEW: manual end-of-break time picker, mirrors _performCheckOut.
  Future<void> _performEndLeave(
    int workerId,
  ) async {
    final selectedDateTime = await _pickLocalDateTime(
      helpText: 'Select Break End Date and Time',
    );

    if (selectedDateTime == null) return;

    await _handleAction(
      '/attendance/leave/end',
      workerId,
      extraData: {
        'leave_end_time': selectedDateTime,
      },
    );
  }

  // -------------------------------------------------------------------
  // UNCHANGED: leave/break type selection sheet.
  // -------------------------------------------------------------------
  Future<void> _startLeaveDialog(
    int workerId,
  ) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Wrap(
            runSpacing: 12,
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
              const SizedBox(height: 8),
              const Text(
                'Select Break / Leave Type',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff1a2a6c),
                ),
              ),
              const Divider(),
              _buildLeaveOption(
                ctx,
                'Rest',
                'Rest Break',
                Icons.free_breakfast,
                Colors.blue,
              ),
              _buildLeaveOption(
                ctx,
                'Lunch',
                'Lunch Break',
                Icons.lunch_dining,
                Colors.purple,
              ),
            ],
          ),
        ),
      ),
    );

    if (type == null) return;
    if (!mounted) return;

    // Select the calendar date explicitly so breaks can cross midnight safely.
    final selectedDateTime = await _pickLocalDateTime(
      helpText: 'Select Break Start Date and Time',
    );

    if (selectedDateTime == null) return;

    await _handleAction(
      '/attendance/leave/start',
      workerId,
      extraData: {
        'leave_type': type,
        'leave_start_time': selectedDateTime,
      },
    );
  }

  Widget _buildLeaveOption(
    BuildContext ctx,
    String value,
    String title,
    IconData icon,
    Color color,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: color,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => Navigator.pop(
        ctx,
        value,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Future<void> _openTransferSheet(
    Map worker,
  ) async {
    try {
      final res = await ApiConfig.dio.get(
        '/sites/my-sites',
      );

      _mySitesForTransfer = (res.data is List)
          ? res.data
          : (res.data['data'] ?? []);
    } catch (e) {
      _showToast(
        'Failed to load your assigned sites',
        Colors.red,
      );
      return;
    }

    if (!mounted) return;

    Map? selectedTargetSite;
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Transfer Worker: ${worker['full_name'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff1a2a6c),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
            Text(
  'Current Shift: ${widget.shiftType}',
  style: TextStyle(
    fontSize: 13,
    color: Colors.grey.shade600,
  ),
  textAlign: TextAlign.center,
),
                const SizedBox(height: 20),
                if (_mySitesForTransfer
                    .where(
                      (s) => s['site_id'] != widget.siteId,
                    )
                    .isEmpty)
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No other assigned sites available for transfer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<Map>(
                    decoration: InputDecoration(
                      labelText: 'Select Target Site',
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(
                        Icons.location_on,
                        color: Color(0xff1a2a6c),
                      ),
                    ),
                    value: selectedTargetSite,
                    items: _mySitesForTransfer
                        .where(
                          (s) =>
                              s['site_id'] != widget.siteId,
                        )
                        .map<DropdownMenuItem<Map>>(
                          (s) => DropdownMenuItem<Map>(
                            value: s,
                            child: Text(
                              s['site_name'] ?? '',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setModalState(
                      () => selectedTargetSite = value,
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed:
                      (selectedTargetSite == null ||
                              isSubmitting)
                          ? null
                          : () async {
                              setModalState(
                                () => isSubmitting = true,
                              );

                              try {
                                await ApiConfig.dio.post(
                                  '/transfers',
                                data: {
  'worker_id':
      worker['worker_id'],
  'current_site_id':
      widget.siteId,
  'current_shift_type':
      widget.shiftType,
  'target_site_id':
      selectedTargetSite!['site_id'],
},
                                );

                                if (!mounted) return;

                                Navigator.pop(
                                  sheetContext,
                                );

                                await _fetchWorkers();

                                if (!mounted) return;

                                _showToast(
                                  'Transfer request submitted successfully',
                                  Colors.green,
                                );
                              } on DioException catch (e) {
                                setModalState(
                                  () => isSubmitting = false,
                                );

                                final msg =
                                    e.response?.data[
                                            'message'] ??
                                        'Failed to submit request';

                                _showToast(
                                  msg,
                                  Colors.red,
                                );
                              }
                            },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send,
                          color: Colors.white,
                        ),
                  label: Text(
                    isSubmitting
                        ? 'Sending...'
                        : 'Send Transfer Request',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xff1a2a6c),
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _timeText(TimeOfDay? time) =>
      time == null
          ? ''
          : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _attendanceTimeText(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return '--:--';
    }

    final match = RegExp(
      r'(?:T| )(\d{2}:\d{2})',
    ).firstMatch(
      value.toString(),
    );

    return match?.group(1) ?? value.toString();
  }

  Future<TimeOfDay?> _pickLunchTime(
    String title,
    TimeOfDay? initial,
  ) async {
    return showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      helpText: title,
    );
  }

  Future<void> _chooseDefaultLunchStart() async {
    final value = await _pickLunchTime(
      'Select Lunch Start',
      _defaultLunchStart,
    );

    if (value != null && mounted) {
      setState(
        () => _defaultLunchStart = value,
      );
    }
  }

  Future<void> _chooseDefaultLunchEnd() async {
    final value = await _pickLunchTime(
      'Select Lunch End',
      _defaultLunchEnd,
    );

    if (value != null && mounted) {
      setState(
        () => _defaultLunchEnd = value,
      );
    }
  }

  Future<void> _editWorkerLunch(
    int workerId,
  ) async {
    final current = _lunchOverrides[workerId];

    final start = await _pickLunchTime(
      'Select Worker Lunch Start',
      current?['start'] ?? _defaultLunchStart,
    );

    if (start == null || !mounted) return;

    final end = await _pickLunchTime(
      'Select Worker Lunch End',
      current?['end'] ?? _defaultLunchEnd,
    );

    if (end == null || !mounted) return;

    setState(() {
      _lunchOverrides[workerId] = {
        'start': start,
        'end': end,
      };
    });
  }


Future<void> _saveLunchTimes() async {
  final eligibleIds = _lunchEligibleWorkers
      .map(
        (w) => int.parse(
          w['worker_id'].toString(),
        ),
      )
      .toSet();

  // تنظيف أي IDs قديمة ما عادت موجودة بالقائمة الحالية
  _lunchExcludedWorkerIds.removeWhere(
    (id) => !eligibleIds.contains(id),
  );

  _lunchOverrides.removeWhere(
    (id, _) => !eligibleIds.contains(id),
  );

  final includedIds = eligibleIds.difference(
    _lunchExcludedWorkerIds,
  );

  if (includedIds.isEmpty) {
    _showToast(
      'All workers are excluded — nothing to save.',
      Colors.orange,
    );
    return;
  }

  // إذا ما في Default Lunch، لازم كل عامل مشمول يكون عنده Override.
  final hasDefaultLunch =
      _defaultLunchStart != null &&
      _defaultLunchEnd != null;

  if (!hasDefaultLunch) {
    final missingOverrideIds = includedIds.where(
      (id) {
        final override = _lunchOverrides[id];

        return override == null ||
            override['start'] == null ||
            override['end'] == null;
      },
    ).toSet();

    if (missingOverrideIds.isNotEmpty) {
      _showToast(
        'Set a lunch time for all included workers or configure a default lunch period.',
        Colors.orange,
      );
      return;
    }
  }

  final overrides = <String, dynamic>{};

  for (final entry in _lunchOverrides.entries) {
    overrides[entry.key.toString()] = {
      'start_time': _timeText(
        entry.value['start'],
      ),
      'end_time': _timeText(
        entry.value['end'],
      ),
    };
  }

  setState(() => _isLoading = true);

  try {
final response = await ApiConfig.dio.post(
  '/attendance/lunch/bulk',
  data: {
    'siteId': widget.siteId,
    'shift_type': widget.shiftType, // ← جديد
    'date': _recordDate,
    'default_start_time': hasDefaultLunch ? _timeText(_defaultLunchStart) : null,
    'default_end_time': hasDefaultLunch ? _timeText(_defaultLunchEnd) : null,
    'overrides': overrides,
    'excluded_worker_ids': _lunchExcludedWorkerIds.toList(),
  },
);

    await _fetchWorkers();

    if (mounted &&
        response.data['status'] == 'success') {
      final saved =
          response.data['updated_records'] ??
              includedIds.length;

      _showToast(
        'Lunch times saved for $saved worker(s).',
        Colors.green,
      );
    }
  } on DioException catch (e) {
    if (!mounted) return;

    setState(() => _isLoading = false);

    final data = e.response?.data;

    _showToast(
      data is Map && data['message'] != null
          ? data['message'].toString()
          : 'Failed to save lunch times.',
      Colors.red,
    );
  }
}
  Future<void> _showMissingAttendanceDialog(
    List<Map<String, dynamic>> missingWorkers,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Attendance is incomplete'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record Present, Absent, Sick, Vacation, or Holiday for every assigned worker before submitting this day.',
              ),
              const SizedBox(height: 12),
              ...missingWorkers.map(
                (worker) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${worker['full_name'] ?? 'Unknown worker'}',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitDay() async {
    final missingWorkers = _workers
        .where((worker) => worker['attendance_id'] == null)
        .map<Map<String, dynamic>>(
          (worker) => Map<String, dynamic>.from(worker),
        )
        .toList();

    if (missingWorkers.isNotEmpty) {
      await _showMissingAttendanceDialog(missingWorkers);
      return;
    }

    bool hasActiveCheckIns = _workers.any(
      (w) => w['attendance_id'] != null,
    );

    if (!hasActiveCheckIns) {
      _showToast(
        'No active attendance records to submit.',
        Colors.orange,
      );
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Confirm Submission',
        ),
        content: const Text(
          'Are you sure you want to end the day and submit records for review? Make sure all workers have checked out.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  const Color(0xff1a2a6c),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text(
              'Submit',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _performSubmit();
  }

  Future<void> _performSubmit({
    List<Map<String, dynamic>>?
        confirmedLunchSkips,
  }) async {
    setState(() => _isLoading = true);

    try {
final response = await ApiConfig.dio.post(
  '/attendance/submit',
  data: {
    'siteId': widget.siteId,
    'shift_type': widget.shiftType, // ← جديد
    'record_date': _recordDate,
    if (confirmedLunchSkips != null && confirmedLunchSkips.isNotEmpty)
      'confirmed_lunch_skips': confirmedLunchSkips,
  },
);

      final data = response.data is Map
          ? response.data as Map
          : <String, dynamic>{};

      if (data['status'] == 'warning' &&
          data['requires_confirmation'] == true) {
        setState(() => _isLoading = false);

        final missingWorkers =
            (data['missing_workers'] as List)
                .cast<Map<String, dynamic>>();

        final reasonControllers = {
          for (var w in missingWorkers)
            w['attendance_id']:
                TextEditingController(),
        };

        final proceed =
            await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(16),
            ),
            title: const Text(
              'Missing Lunch Time',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These workers have no recorded lunch break. Please provide a reason for each to continue.',
                    style: TextStyle(
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...missingWorkers.map((w) {
                    return Padding(
                      padding:
                          const EdgeInsets.only(
                        bottom: 12,
                      ),
                      child: TextField(
                        controller:
                            reasonControllers[
                                w['attendance_id']],
                        decoration:
                            InputDecoration(
                          labelText:
                              '${w['full_name']} — reason',
                          border:
                              const OutlineInputBorder(),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  context,
                  false,
                ),
                child:
                    const Text('Cancel'),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.orange.shade800,
                ),
                onPressed: () =>
                    Navigator.pop(
                  context,
                  true,
                ),
                child: const Text(
                  'Confirm & Submit',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );

        if (proceed == true) {
          final skips =
              reasonControllers.entries
                  .where(
                    (e) => e.value.text
                        .trim()
                        .isNotEmpty,
                  )
                  .map(
                    (e) => {
                      'attendance_id':
                          e.key,
                      'reason':
                          e.value.text.trim(),
                    },
                  )
                  .toList();

          if (skips.length <
              missingWorkers.length) {
            if (mounted) {
              _showToast(
                'Please provide a reason for every listed worker.',
                Colors.orange,
              );
            }

            return;
          }

          await _performSubmit(
            confirmedLunchSkips: skips,
          );
        }

        return;
      }

      if (data['status'] == 'success') {
        await _fetchWorkers();

        if (!mounted) return;

        _showToast(
          'Day submitted successfully',
          Colors.green,
        );

        if (_workers.isEmpty) {
          Navigator.pop(context);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } on DioException catch (e) {
      setState(() => _isLoading = false);

      final responseData = e.response?.data;
      if (responseData is Map &&
          responseData['code'] == 'MISSING_ATTENDANCE_RECORDS') {
        final missingWorkers = (responseData['missing_workers'] as List? ?? [])
            .whereType<Map>()
            .map<Map<String, dynamic>>(
              (worker) => Map<String, dynamic>.from(worker),
            )
            .toList();

        if (missingWorkers.isNotEmpty) {
          await _showMissingAttendanceDialog(missingWorkers);
        } else {
          _showToast(
            responseData['message']?.toString() ?? 'Attendance is incomplete.',
            Colors.orange,
          );
        }
        return;
      }

      final msg = responseData is Map
          ? (responseData['message'] ??
              'Final submission failed. Ensure all workers have checked out.')
          : 'Final submission failed.';

      _showToast(
        msg,
        Colors.red,
      );
    } catch (e) {
      setState(() => _isLoading = false);

      _showToast(
        'Server connection error',
        Colors.red,
      );
    }
  }

  // -------------------------------------------------------------------
  // BULK ATTENDANCE UI
  // -------------------------------------------------------------------
  Widget _buildBulkAttendanceCard() {
    final eligibleCheckInIds = _workers
        .where((worker) {
          final id = int.tryParse(
            worker['worker_id'].toString(),
          );

          return id != null &&
              _canBulkCheckIn(worker) &&
              worker['check_in_time'] == null;
        })
        .map<int>(
          (worker) => int.parse(
            worker['worker_id'].toString(),
          ),
        )
        .toSet();

    final eligibleCheckOutIds = _workers
        .where((worker) {
          final id = int.tryParse(
            worker['worker_id'].toString(),
          );

          return id != null &&
              _canBulkCheckOut(worker);
        })
        .map<int>(
          (worker) => int.parse(
            worker['worker_id'].toString(),
          ),
        )
        .toSet();

    final selectedCheckInCount =
        _eligibleSelectedWorkerIds(true).length;
final selectedAbsentCount = _eligibleSelectedWorkerIdsForAbsent().length;

    final selectedCheckOutCount =
        _eligibleSelectedWorkerIds(false).length;

    final canSelectEligible =
        eligibleCheckInIds.isNotEmpty ||
        eligibleCheckOutIds.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xff1a2a6c,
                      ).withOpacity(0.08),
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: Color(0xff1a2a6c),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bulk Attendance',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 15,
                            color:
                                Color(0xff1a2a6c),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select workers from the table and apply attendance actions in bulk.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedWorkerIds.isNotEmpty)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xff1a2a6c,
                        ).withOpacity(0.08),
                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                      ),
                      child: Text(
                        '${_selectedWorkerIds.length} selected',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w700,
                          color:
                              Color(0xff1a2a6c),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Selection controls
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          !canSelectEligible
                              ? null
                              : () {
                                  setState(() {
                                    _selectedWorkerIds
                                        .addAll(
                                      eligibleCheckInIds,
                                    );

                                    _selectedWorkerIds
                                        .addAll(
                                      eligibleCheckOutIds,
                                    );
                                  });
                                },
                      icon: const Icon(
                        Icons.done_all_rounded,
                        size: 17,
                      ),
                      label: const Text(
                        'Select Eligible',
                      ),
                      style:
                          OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 10,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(9),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _selectedWorkerIds.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _selectedWorkerIds
                                        .clear();
                                  });
                                },
                      icon: const Icon(
                        Icons.clear_all_rounded,
                        size: 17,
                      ),
                      label: const Text(
                        'Clear Selection',
                      ),
                      style:
                          OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 10,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(9),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Bulk actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          selectedCheckInCount ==
                                  0
                              ? null
                              : () =>
                                  _bulkAttendanceAction(
                                    checkIn: true,
                                  ),
                      icon: const Icon(
                        Icons.login_rounded,
                        size: 18,
                      ),
                      label: Text(
                        selectedCheckInCount ==
                                0
                            ? 'Bulk Check-In'
                            : 'Check-In ($selectedCheckInCount)',
                      ),
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            Colors.green.shade700,
                        foregroundColor:
                            Colors.white,
                        disabledBackgroundColor:
                            Colors.grey.shade200,
                        disabledForegroundColor:
                            Colors.grey.shade500,
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 12,
                        ),
                        elevation: 0,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          selectedCheckOutCount ==
                                  0
                              ? null
                              : () =>
                                  _bulkAttendanceAction(
                                    checkIn: false,
                                  ),
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 18,
                      ),
                      label: Text(
                        selectedCheckOutCount ==
                                0
                            ? 'Bulk Check-Out'
                            : 'Check-Out ($selectedCheckOutCount)',
                      ),
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(
                          0xff1a2a6c,
                        ),
                        foregroundColor:
                            Colors.white,
                        disabledBackgroundColor:
                            Colors.grey.shade200,
                        disabledForegroundColor:
                            Colors.grey.shade500,
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 12,
                        ),
                        elevation: 0,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
const SizedBox(height: 8),
SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: selectedAbsentCount == 0 ? null : _bulkMarkAbsent,
    icon: const Icon(Icons.person_off_rounded, size: 18, color: Colors.red),
    label: Text(
      selectedAbsentCount == 0
          ? 'Bulk Mark Absent'
          : 'Mark Absent ($selectedAbsentCount)',
      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
    ),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Colors.red),
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
),
              if (_selectedWorkerIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Check-In applies only to selected workers without a check-in. '
                  'Check-Out applies only to selected workers with an open shift.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkersTable() {
    if (_filteredWorkers.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assignment_turned_in,
                size: 56,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 10),
              Text(
                _searchQuery.isEmpty
                    ? 'All workers accounted for or none available!'
                    : 'No workers match "$_searchQuery"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rows =
        _filteredWorkers.map<DataRow>((worker) {
      final workerId = int.parse(
        worker['worker_id'].toString(),
      );

      final hasCheckIn =
          worker['check_in_time'] != null;

      final hasCheckOut =
          worker['check_out_time'] != null;

      final workflowStatus =
          worker['workflow_status']?.toString();

      final attendanceStatus =
          worker['attendance_status']?.toString();

      final isSubmitted =
          workflowStatus == 'Submitted';

      final isDraft =
          workflowStatus == null ||
              workflowStatus == 'Draft';

      final isRejected =
          workflowStatus == 'Rejected';

      final isOnBreak =
          worker['current_leave_id'] != null;

      final status = isRejected
          ? 'Rejected'
          : attendanceStatus == 'Absent'
              ? 'Absent'
              : attendanceStatus == 'Sick'
                  ? 'Sick Leave'
                  : attendanceStatus == 'Vacation'
                      ? 'Annual Leave'
                      : attendanceStatus ==
                              'Holiday'
                          ? 'Holiday'
                          : isOnBreak
                              ? 'On Break'
                              : hasCheckOut
                                  ? 'Checked Out'
                                  : hasCheckIn
                                      ? 'Checked In'
                                      : 'Not Checked In';

      final statusColor = isRejected
          ? Colors.red
          : status == 'Absent'
              ? Colors.red
              : status == 'Sick Leave'
                  ? Colors.orange
                  : status == 'Annual Leave'
                      ? Colors.blue
                      : status == 'Holiday'
                          ? Colors.purple
                          : status == 'On Break'
                              ? Colors.orange
                              : status ==
                                      'Checked In'
                                  ? Colors.green
                                  : status ==
                                          'Checked Out'
                                      ? Colors.blue
                                      : Colors.grey;

      return DataRow(
        cells: [
          DataCell(
            SizedBox(
              width: 180,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        const Color(0xff1a2a6c)
                            .withOpacity(0.10),
                    child: Text(
                      (worker['full_name'] ?? 'W')
                          .toString()
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xff1a2a6c),
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      worker['full_name']
                              ?.toString() ??
                          'Worker',
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          DataCell(
            Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: statusColor
                    .withOpacity(0.10),
                borderRadius:
                    BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ),
          DataCell(
            Text(
              _attendanceTimeText(
                worker['check_in_time'],
              ),
            ),
          ),
          DataCell(
            Text(
              _attendanceTimeText(
                worker['check_out_time'],
              ),
            ),
          ),
          DataCell(
            PopupMenuButton<String>(
              tooltip: 'Worker actions',
              icon: const Icon(
                Icons.more_horiz,
                color: Color(0xff1a2a6c),
              ),
              onSelected:
                  (action) async {
                switch (action) {
                  case 'status':
                    await _showAttendanceStatusDialog(
                      workerId,
                      currentStatus:
                          attendanceStatus,
                    );
                    break;

                  case 'checkin':
                    await _performCheckIn(
                      workerId,
                    );
                    break;

                  case 'break':
                    if (isOnBreak) {
                      await _performEndLeave(
                        workerId,
                      );
                    } else {
                      await _startLeaveDialog(
                        workerId,
                      );
                    }
                    break;

                  case 'checkout':
                    await _performCheckOut(
                      workerId,
                    );
                    break;

                  case 'lunch':
                    await _editWorkerLunch(
                      workerId,
                    );
                    break;

                  case 'transfer':
                    await _openTransferSheet(
                      worker,
                    );
                    break;

                  case 'edit_times':
                    await _editTimesDialog(
                      worker,
                    );
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'status',
                  // The backend can safely clear a mistaken clock-in when
                  // correcting a Draft record to Absent/Sick/etc.
                  enabled: isDraft,
                  child: Text(
                    attendanceStatus == null
                        ? 'Set status'
                        : 'Edit status',
                  ),
                ),
                PopupMenuItem(
                  value: 'checkin',
                  enabled:
                      !hasCheckIn &&
                          !isRejected &&
                          isDraft,
                  child: const Text(
                    'Check In',
                  ),
                ),
                PopupMenuItem(
                  value: 'break',
                  enabled:
                      hasCheckIn &&
                          !hasCheckOut &&
                          !isSubmitted &&
                          !isRejected,
                  child: Text(
                    isOnBreak
                        ? 'End Break'
                        : 'Start Break',
                  ),
                ),
                PopupMenuItem(
                  value: 'checkout',
                  enabled:
                      hasCheckIn &&
                          !hasCheckOut &&
                          !isSubmitted &&
                          !isRejected,
                  child: const Text(
                    'Check Out',
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'edit_times',
                  enabled: hasCheckIn,
                  child: const Text(
                    'Edit Check-in / Check-out',
                  ),
                ),
                const PopupMenuItem(
                  value: 'lunch',
                  child: Text(
                    'Edit Lunch',
                  ),
                ),
                const PopupMenuItem(
                  value: 'transfer',
                  child: Text(
                    'Transfer Worker',
                  ),
                ),
              ],
            ),
          ),
          DataCell(
            Checkbox(
              value: _selectedWorkerIds
                  .contains(workerId),
              onChanged: (checked) =>
                  setState(() {
                if (checked == true) {
                  _selectedWorkerIds
                      .add(workerId);
                } else {
                  _selectedWorkerIds
                      .remove(workerId);
                }
              }),
            ),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12,
      ),
      child: AppDataTableCard(
        title: 'Workers Attendance',
        subtitle:
            '${_filteredWorkers.length} workers',
        icon: Icons.groups_rounded,
        accentColor:
            const Color(0xff1a2a6c),
        padding:
            const EdgeInsets.all(12),
        columns: const [
          DataColumn(
            label: Text('Worker'),
          ),
          DataColumn(
            label: Text('Status'),
          ),
          DataColumn(
            label: Text('Check In'),
          ),
          DataColumn(
            label: Text('Check Out'),
          ),
          DataColumn(
            label: Text('Actions'),
          ),
          DataColumn(
            label: Text('Select'),
          ),
        ],
        rows: rows,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        DateFormat('yyyy/MM/dd').format(
      DateTime.parse(_recordDate),
    );

    return Scaffold(
      backgroundColor:
          const Color(0xfff8f9fa),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff1a2a6c),
        elevation: 0,
     title: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(widget.siteName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
    Text('Daily Attendance — ${widget.shiftType} Shift', style: const TextStyle(fontSize: 11, color: Colors.white70)),
  ],
),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.amberAccent,
            ),
            tooltip: 'Rejected Records',
            onPressed: () =>
                Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const RejectedRecordsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(
                color: Color(0xff1a2a6c),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding:
                        const EdgeInsets.only(
                      bottom: 12,
                    ),
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.all(
                          16.0,
                        ),
                        child: Container(
                          decoration:
                              BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(
                              16,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withOpacity(
                                  0.04,
                                ),
                                blurRadius: 10,
                                offset:
                                    const Offset(
                                  0,
                                  4,
                                ),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.all(
                              16.0,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding:
                                      const EdgeInsets
                                          .all(
                                    12,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color: const Color(
                                      0xff1a2a6c,
                                    ).withOpacity(
                                      0.1,
                                    ),
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      12,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons
                                        .today_rounded,
                                    color: Color(
                                      0xff1a2a6c,
                                    ),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(
                                  width: 14,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            DateFormat(
                                              'yyyy/MM/dd',
                                            ).format(
                                              DateTime
                                                  .parse(
                                                _recordDate,
                                              ),
                                            ),
                                            style:
                                                const TextStyle(
                                              fontSize:
                                                  16,
                                              fontWeight:
                                                  FontWeight
                                                      .bold,
                                              color: Color(
                                                0xff1a2a6c,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          InkWell(
                                            onTap:
                                                _chooseAttendanceDate,
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                              6,
                                            ),
                                            child:
                                                Container(
                                              padding:
                                                  const EdgeInsets
                                                      .symmetric(
                                                horizontal:
                                                    8,
                                                vertical:
                                                    2,
                                              ),
                                              decoration:
                                                  BoxDecoration(
                                                color: Colors
                                                    .green
                                                    .shade50,
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                  6,
                                                ),
                                                border:
                                                    Border.all(
                                                  color: Colors
                                                      .green
                                                      .shade200,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize
                                                        .min,
                                                children:
                                                    const [
                                                  Text(
                                                    'Selected',
                                                    style:
                                                        TextStyle(
                                                      fontSize:
                                                          10,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold,
                                                      color:
                                                          Colors.green,
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width:
                                                        4,
                                                  ),
                                                  Icon(
                                                    Icons
                                                        .edit_calendar,
                                                    size:
                                                        13,
                                                    color:
                                                        Colors.green,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(
                                        height: 2,
                                      ),
                                      Text(
                                        'Tap the date to change the manual shift date',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors
                                              .grey
                                              .shade600,
                                          fontWeight:
                                              FontWeight
                                                  .w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          12,
                        ),
                        child: TextField(
                          controller:
                              _searchController,
                          onChanged: (value) =>
                              setState(
                            () => _searchQuery =
                                value,
                          ),
                          decoration:
                              InputDecoration(
                            hintText:
                                'Search worker by name...',
                            prefixIcon:
                                const Icon(
                              Icons.search,
                            ),
                            filled: true,
                            fillColor:
                                Colors.white,
                            suffixIcon:
                                _searchQuery.isEmpty
                                    ? null
                                    : IconButton(
                                        icon:
                                            const Icon(
                                          Icons.clear,
                                        ),
                                        onPressed:
                                            () {
                                          _searchController
                                              .clear();

                                          setState(
                                            () =>
                                                _searchQuery =
                                                    '',
                                          );
                                        },
                                      ),
                            contentPadding:
                                const EdgeInsets
                                    .symmetric(
                              vertical: 0,
                              horizontal: 16,
                            ),
                            border:
                                OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                14,
                              ),
                              borderSide:
                                  BorderSide.none,
                            ),
                          ),
                        ),
                      ),

                      // ==================================================
                      // BULK ATTENDANCE
                      // ==================================================
                      _buildBulkAttendanceCard(),

                      // ==================================================
                      // LUNCH BREAK — BULK ENTRY
                      // ==================================================
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          12,
                        ),
                        child: Card(
                          elevation: 0,
                          child: Padding(
                            padding:
                                const EdgeInsets.all(
                              14,
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons
                                          .lunch_dining,
                                      color: Color(
                                        0xff1a2a6c,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 8,
                                    ),
                                    const Text(
                                      'Lunch Break — Bulk Entry',
                                      style:
                                          TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                        fontSize: 15,
                                        color: Color(
                                          0xff1a2a6c,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: 4,
                                ),
                                Text(
                                  'All workers are checked by default. Uncheck anyone who had a different lunch time or did not take a break.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors
                                        .grey
                                        .shade600,
                                  ),
                                ),
                                const SizedBox(
                                  height: 12,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child:
                                          OutlinedButton
                                              .icon(
                                        onPressed:
                                            _chooseDefaultLunchStart,
                                        icon:
                                            const Icon(
                                          Icons
                                              .login_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          'Start: ${_timeText(_defaultLunchStart).isEmpty ? '--:--' : _timeText(_defaultLunchStart)}',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 8,
                                    ),
                                    Expanded(
                                      child:
                                          OutlinedButton
                                              .icon(
                                        onPressed:
                                            _chooseDefaultLunchEnd,
                                        icon:
                                            const Icon(
                                          Icons
                                              .logout_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          'End: ${_timeText(_defaultLunchEnd).isEmpty ? '--:--' : _timeText(_defaultLunchEnd)}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: 14,
                                ),
                                if (_lunchEligibleWorkers
                                    .isEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      'No workers with a completed shift (check-in & check-out) yet today.',
                                      style: TextStyle(
                                        color: Colors
                                            .grey
                                            .shade600,
                                        fontSize:
                                            12.5,
                                      ),
                                    ),
                                  )
                                else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child:
                                            Text(
                                          'Workers (${_lunchEligibleWorkers.length - _lunchExcludedWorkerIds.length}/${_lunchEligibleWorkers.length} included)',
                                          style:
                                              const TextStyle(
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                            fontSize:
                                                13,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed:
                                            () =>
                                                setState(
                                          () {
                                            if (_lunchExcludedWorkerIds
                                                .isEmpty) {
                                              _lunchExcludedWorkerIds
                                                  .addAll(
                                                _lunchEligibleWorkers
                                                    .map(
                                                  (w) => int
                                                      .parse(
                                                    w['worker_id']
                                                        .toString(),
                                                  ),
                                                ),
                                              );
                                            } else {
                                              _lunchExcludedWorkerIds
                                                  .clear();
                                            }
                                          },
                                        ),
                                        child: Text(
                                          _lunchExcludedWorkerIds
                                                  .isEmpty
                                              ? 'Uncheck all'
                                              : 'Check all',
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    constraints:
                                        const BoxConstraints(
                                      maxHeight: 280,
                                    ),
                                    decoration:
                                        BoxDecoration(
                                      border:
                                          Border.all(
                                        color: Colors
                                            .grey
                                            .shade200,
                                      ),
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        10,
                                      ),
                                    ),
                                    child: ListView
                                        .separated(
                                      shrinkWrap:
                                          true,
                                      itemCount:
                                          _lunchEligibleWorkers
                                              .length,
                                      separatorBuilder:
                                          (_, __) =>
                                              Divider(
                                        height: 1,
                                        color: Colors
                                            .grey
                                            .shade100,
                                      ),
                                      itemBuilder:
                                          (
                                        context,
                                        index,
                                      ) {
                                        final worker =
                                            _lunchEligibleWorkers[
                                                index];

                                        final workerId =
                                            int.parse(
                                          worker[
                                                  'worker_id']
                                              .toString(),
                                        );

                                        final isIncluded =
                                            !_lunchExcludedWorkerIds
                                                .contains(
                                          workerId,
                                        );

                                        final override =
                                            _lunchOverrides[
                                                workerId];

                                        return CheckboxListTile(
                                          dense: true,
                                          value:
                                              isIncluded,
                                          onChanged:
                                              (checked) =>
                                                  setState(
                                            () {
                                              if (checked ==
                                                  true) {
                                                _lunchExcludedWorkerIds
                                                    .remove(
                                                  workerId,
                                                );
                                              } else {
                                                _lunchExcludedWorkerIds
                                                    .add(
                                                  workerId,
                                                );
                                              }
                                            },
                                          ),
                                          title:
                                              Text(
                                            worker[
                                                        'full_name']
                                                    ?.toString() ??
                                                'Worker',
                                            style:
                                                const TextStyle(
                                              fontSize:
                                                  13.5,
                                              fontWeight:
                                                  FontWeight
                                                      .w500,
                                            ),
                                          ),
                                          subtitle:
                                              override !=
                                                      null
                                                  ? Text(
                                                      'Custom: ${_timeText(override['start'])} - ${_timeText(override['end'])}',
                                                      style:
                                                          TextStyle(
                                                        fontSize:
                                                            11,
                                                        color: Colors
                                                            .blue
                                                            .shade700,
                                                        fontWeight:
                                                            FontWeight
                                                                .w600,
                                                      ),
                                                    )
                                                  : Text(
                                                      isIncluded
                                                          ? 'Uses default lunch time'
                                                          : 'Excluded — no lunch will be recorded',
                                                      style:
                                                          TextStyle(
                                                        fontSize:
                                                            11,
                                                        color: isIncluded
                                                            ? Colors
                                                                .grey
                                                                .shade500
                                                            : Colors
                                                                .red
                                                                .shade400,
                                                        fontWeight: isIncluded
                                                            ? FontWeight
                                                                .normal
                                                            : FontWeight
                                                                .w600,
                                                      ),
                                                    ),
                                          secondary:
                                              IconButton(
                                            icon:
                                                Icon(
                                              Icons
                                                  .schedule_rounded,
                                              size: 20,
                                              color: override !=
                                                      null
                                                  ? Colors
                                                      .blue
                                                      .shade700
                                                  : Colors
                                                      .grey
                                                      .shade500,
                                            ),
                                            tooltip:
                                                'Set a different lunch time for this worker',
                                            onPressed:
                                                () async {
                                              await _editWorkerLunch(
                                                workerId,
                                              );

                                              // إذا حدد وقت خاص، ضمّن العامل تلقائياً حتى لو كان ملغى تعليمه
                                              if (_lunchOverrides
                                                  .containsKey(
                                                workerId,
                                              )) {
                                                setState(
                                                  () => _lunchExcludedWorkerIds
                                                      .remove(
                                                    workerId,
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(
                                  height: 14,
                                ),
                                SizedBox(
                                  width:
                                      double.infinity,
                                  child:
                                      ElevatedButton
                                          .icon(
                                    onPressed:
                                        _lunchEligibleWorkers
                                                .isEmpty
                                            ? null
                                            : _saveLunchTimes,
                                    icon:
                                        const Icon(
                                      Icons
                                          .save_alt_rounded,
                                      size: 18,
                                    ),
                                    label:
                                        const Text(
                                      'Save Lunch Times',
                                    ),
                                    style:
                                        ElevatedButton
                                            .styleFrom(
                                      backgroundColor:
                                          const Color(
                                        0xff1a2a6c,
                                      ),
                                      foregroundColor:
                                          Colors.white,
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                        vertical: 12,
                                      ),
                                      shape:
                                          RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                          10,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      _buildWorkersTable(),
                    ],
                  ),
                ),

                Container(
                  padding:
                      const EdgeInsets.all(16.0),
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child:
                        ElevatedButton.icon(
                      onPressed: _submitDay,
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Submit Day for Review',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(
                          0xff1a2a6c,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                            12,
                          ),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
