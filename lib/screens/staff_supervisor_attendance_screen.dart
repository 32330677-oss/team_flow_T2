import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

class StaffSupervisorAttendanceScreen extends StatefulWidget {
  const StaffSupervisorAttendanceScreen({super.key});

  @override
  State<StaffSupervisorAttendanceScreen> createState() =>
      _StaffSupervisorAttendanceScreenState();
}

class _StaffRow {
  final int staffId;
  final String uniqueId;
  final String fullName;
  final String position;
  final double standardHours;

  // Current status from staff_members: Active / Inactive
  final String staffCurrentStatus;

  String? status;

  DateTime checkInDate;
  DateTime checkOutDate;
  DateTime? lunchStart;
  DateTime? lunchEnd;

  TimeOfDay checkIn;
  TimeOfDay checkOut;

  bool existing;
  bool checkOutPending;
  /// Workflow status coming from the server:
  /// null (no record yet) / Draft / Submitted / Approved / Rejected
  String? workflowStatus;

  String? rejectionNote;

  /// 'Manual' / 'Biometric' (null when there is no record yet).
  final String? source;

  /// Exact values stored on the server ('YYYY-MM-DD HH:MM:SS', seconds kept).
  /// Unedited times are sent back exactly as stored (#2).
  final String? origCheckIn;
  final String? origCheckOut;

  /// #2: only rows the supervisor actually changed are sent on Save Draft.
  bool dirty = false;
  bool checkInEdited = false;
  bool checkOutEdited = false;

  bool get isBiometric => source == 'Biometric';
  bool get hasBiometricIn => isBiometric && origCheckIn != null;

  _StaffRow({
    required this.staffId,
    required this.uniqueId,
    required this.fullName,
    required this.position,
    required this.standardHours,
    required this.staffCurrentStatus,
    required this.checkInDate,
    required this.checkOutDate,
    this.lunchStart,
    this.lunchEnd,
    required this.status,
    required this.checkIn,
    required this.checkOut,
    required this.existing,
    this.checkOutPending = false,
    this.workflowStatus,
    this.rejectionNote,
    this.source,
    this.origCheckIn,
    this.origCheckOut,
  });

  /// Submitted is already in the admin queue; Approved is final.
  /// Inactive staff are also locked because historical records are view-only.
  bool get isLocked =>
      workflowStatus == 'Submitted' ||
      workflowStatus == 'Approved' ||
      staffCurrentStatus == 'Inactive';
}
class _StaffSupervisorAttendanceScreenState
    extends State<StaffSupervisorAttendanceScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  static const List<String> _statuses = [
    'Present',
    'Absent',
    'Sick',
    'Vacation',
    'Holiday',
  ];

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;

  /// Employees selected for bulk editing and draft saving.
  final Set<int> _selectedStaffIds = <int>{};
 

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<_StaffRow> _rows = [];

  TimeOfDay _globalCheckIn = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _globalCheckOut = const TimeOfDay(hour: 18, minute: 0);
  DateTime _globalCheckInDate = DateTime.now();
  DateTime _globalCheckOutDate = DateTime.now();
  DateTime? _globalLunchStart;
  DateTime? _globalLunchEnd;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

TimeOfDay _defaultCheckOutFor(double standardHours) {
  const defaultCheckInMinutes = 8 * 60; // 08:00

  final totalMinutes =
      defaultCheckInMinutes + (standardHours * 60).round();

  final normalized = totalMinutes % (24 * 60);

  return TimeOfDay(
    hour: normalized ~/ 60,
    minute: normalized % 60,
  );
}
  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  /// Yesterday is allowed because a night shift may start yesterday
  /// and finish after midnight.
  ///
  /// Only dates older than yesterday are considered backdated.
  bool get _isBackdated {
    final today = DateTime.now();

    final yesterday = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));

    final selected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    return selected.isBefore(yesterday);
  }

  // Same definition as the backend isFriday().
  bool get _isFridaySelected =>
      _selectedDate.weekday == DateTime.friday;

  Set<int> get _selectableIds =>
      _rows.where((r) => !r.isLocked).map((r) => r.staffId).toSet();

  int get _checkedCount {
    final selectable = _selectableIds;
    return _selectedStaffIds.where(selectable.contains).length;
  }

  /// Only counts checked employees that are ALSO Present — since Bulk
  /// Check-In / Check-Out / Lunch only ever apply to Present employees.
  int get _checkedPresentCount => _rows
      .where((r) =>
          _selectedStaffIds.contains(r.staffId) &&
          !r.isLocked &&
          r.status == 'Present')
      .length;

  /// Search filter — only affects which staff cards are rendered.
  /// Selection state, bulk actions, and save/submit always operate on
  /// the full _rows list, never on this filtered view.
  List<_StaffRow> get _filteredRows {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _rows;
    return _rows
        .where((r) =>
            r.fullName.toLowerCase().contains(query) ||
            r.uniqueId.toLowerCase().contains(query))
        .toList();
  }
  TimeOfDay? _parseTime(dynamic value) {
    if (value == null) return null;

    final s = value.toString();

    final match = RegExp(r'(\d{2}):(\d{2})').firstMatch(s);

    if (match == null) return null;

    return TimeOfDay(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
  }

  String _fmtDateTime(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value);

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  DateTime _combine(DateTime d, TimeOfDay t) =>
      DateTime(d.year, d.month, d.day, t.hour, t.minute);

  DateTime _resolveOut(_StaffRow row) {
    final inDt = _combine(row.checkInDate, row.checkIn);
    var outDt = _combine(row.checkOutDate, row.checkOut);
    if (!outDt.isAfter(inDt)) outDt = outDt.add(const Duration(days: 1));
    return outDt;
  }

  // ------------------------------------------------------------------
  // Loading
  //
  // When [justSavedIds] is provided this is a "silent" refresh after a save:
  // no full-screen spinner, and rows the supervisor did NOT just save keep
  // their unsaved on-screen edits.
  // ------------------------------------------------------------------
  Future<void> _loadDay({Set<int>? justSavedIds}) async {
    final saved = justSavedIds;
    final silent = saved != null;

    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await ApiConfig.dio.get(
        '/staff-attendance/supervisor/day',
        queryParameters: {'date': _dateStr},
      );

      final data = (response.data['data'] as List?) ?? [];

      final oldById = {
        for (final r in _rows) r.staffId: r,
      };

      String? exact(dynamic v) {
        final t = v?.toString();
        if (t == null || t.isEmpty || t == 'null') return null;
        final n = t.replaceFirst('T', ' ');
        return n.length >= 19 ? n.substring(0, 19) : n;
      }

      final newRows = data.map<_StaffRow>((raw) {
        final standard =
            (double.tryParse(raw['standard_minutes_snapshot']?.toString() ?? '') ?? 0) > 0
                ? (double.parse(raw['standard_minutes_snapshot'].toString()) / 60)
                : (double.tryParse(raw['standard_daily_hours']?.toString() ?? '8') ?? 8);

        final hasRecord =
            raw['staff_attendance_id'] != null;

        final note =
            raw['admin_rejection_notes']?.toString();

        final parsedIn = _parseDateTime(raw['check_in_time']);
        final parsedOut = _parseDateTime(raw['check_out_time']);

        // Default lunch window shown for any employee who doesn't have a
        // saved record yet — purely a UI suggestion, fully editable per row.
        final defaultLunchStart = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day, 12, 0,
        );
        final defaultLunchEnd = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day, 13, 0,
        );

        final row = _StaffRow(
          staffId: raw['staff_id'],
          uniqueId: raw['staff_unique_id']?.toString() ?? '',
          fullName: raw['full_name']?.toString() ?? '',
          position: raw['position']?.toString() ?? '-',
          standardHours: standard,
          staffCurrentStatus:
              raw['staff_current_status']?.toString() ?? 'Active',
          checkInDate: parsedIn ?? _selectedDate,
          checkOutDate: parsedOut ?? _selectedDate,
          lunchStart: _parseDateTime(raw['lunch_start_time']) ??
              (hasRecord ? null : defaultLunchStart),
          lunchEnd: _parseDateTime(raw['lunch_end_time']) ??
              (hasRecord ? null : defaultLunchEnd),
          // Default every not-yet-recorded row to Present, so the supervisor
          // only touches the exceptions (Absent/Sick/...). Once a record
          // exists on the server, its saved status always wins — this
          // fallback only fires for brand-new rows.
          status: raw['attendance_status']?.toString(),
          checkIn:
              _parseTime(raw['check_in_time']) ??
                  const TimeOfDay(
                    hour: 8,
                    minute: 0,
                  ),
       checkOut:
    _parseTime(raw['check_out_time']) ??
        _defaultCheckOutFor(standard),
                  existing: hasRecord,
          checkOutPending: hasRecord &&
              raw['check_in_time'] != null &&
              raw['check_out_time'] == null &&
              raw['attendance_status']?.toString() == 'Present',
          workflowStatus:
              hasRecord
                  ? raw['status']?.toString()
                  : null,
          rejectionNote:
              (note != null && note.trim().isNotEmpty)
                  ? note
                  : null,
          source: hasRecord ? raw['source']?.toString() : null,
          origCheckIn: exact(raw['check_in_time']),
          origCheckOut: exact(raw['check_out_time']),
        );

        // Keep unsaved local edits of rows that were not part of this save.
        if (saved != null &&
            !saved.contains(row.staffId) &&
            !row.isLocked) {
          final old = oldById[row.staffId];

                  if (old != null) {
            row.status = old.status;
            row.checkIn = old.checkIn;
            row.checkOut = old.checkOut;
            row.checkInDate = old.checkInDate;
            row.checkOutDate = old.checkOutDate;
            row.checkOutPending = old.checkOutPending;
            row.lunchStart = old.lunchStart;
            row.lunchEnd = old.lunchEnd;
            row.dirty = old.dirty;
            row.checkInEdited = old.checkInEdited;
            row.checkOutEdited = old.checkOutEdited;
          }
        }

        return row;
      }).toList();

      if (!mounted) return;

      setState(() {
        _rows = newRows;

        // Drop selections of rows that no longer exist
        // or became locked.
        _selectedStaffIds.removeWhere(
          (id) => !newRows.any(
            (r) => r.staffId == id && !r.isLocked,
          ),
        );

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      _showSnack(
        'Failed to load staff attendance',
        Colors.red,
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      helpText: 'Select attendance date (past dates allowed)',
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _globalCheckInDate = picked;
        _globalCheckOutDate = picked;
        _globalLunchStart = null;
        _globalLunchEnd = null;
        _selectedStaffIds.clear();
      });

      _loadDay();
    }
  }

  Future<void> _pickRowDate(_StaffRow row, {required bool checkIn}) async {
    final current = checkIn ? row.checkInDate : row.checkOutDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: checkIn ? 'Select check-in date' : 'Select check-out date',
    );
    if (picked == null || !mounted) return;
    // B5: picking a DATE never clears a missing check-out by itself; only an
    // explicit check-out TIME does.
    setState(() {
      row.dirty = true;
      if (checkIn) {
        row.checkInDate = picked;
        row.checkInEdited = true;
      } else {
        row.checkOutDate = picked;
        if (!row.checkOutPending) row.checkOutEdited = true;
      }
    });
  }

  Future<void> _pickGlobalDate({required bool checkIn}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: checkIn ? _globalCheckInDate : _globalCheckOutDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: checkIn ? 'Select bulk check-in date' : 'Select bulk check-out date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (checkIn) {
        _globalCheckInDate = picked;
      } else {
        _globalCheckOutDate = picked;
      }
    });
  }

  Future<DateTime?> _pickLunchDateTime(String title, DateTime? initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '$title date',
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: initial == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : TimeOfDay.fromDateTime(initial),
      helpText: '$title time',
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickRowLunch(_StaffRow row, {required bool start}) async {
    final value = await _pickLunchDateTime(
      start ? 'Lunch start' : 'Lunch end',
      start ? row.lunchStart : row.lunchEnd,
    );
    if (value == null || !mounted) return;
    setState(() {
      row.dirty = true;
      if (start) {
        row.lunchStart = value;
      } else {
        row.lunchEnd = value;
      }
    });
  }

  // ------------------------------------------------------------------
  // Bulk actions — each one is fully independent now: applying
  // Check-In does NOT touch Check-Out, and vice versa. All three
  // (Check-In / Check-Out / Lunch) only ever touch CHECKED employees
  // who are currently marked Present. This is local only: nothing is
  // sent to the server until Save Draft or Submit.
  // ------------------------------------------------------------------
  List<_StaffRow> _eligibleSelectedPresentRows() {
    return _rows
        .where((r) =>
            _selectedStaffIds.contains(r.staffId) &&
            !r.isLocked &&
            r.status == 'Present')
        .toList();
  }

  int _selectedNotLockedCount() {
    return _rows
        .where((r) => _selectedStaffIds.contains(r.staffId) && !r.isLocked)
        .length;
  }

  void _applyBulkCheckIn() {
    final totalSelected = _selectedNotLockedCount();
    if (totalSelected == 0) {
      _showSnack('Check at least one employee first.', Colors.orange);
      return;
    }

    // B5: rows that already have a biometric check-in are never overwritten
    // by the bulk preset (edit them one by one if really needed).
    final present = _eligibleSelectedPresentRows();
    final applicable = present.where((r) => !r.hasBiometricIn).toList();
    final biometricSkipped = present.length - applicable.length;
    final skippedCount = totalSelected - present.length;

    if (applicable.isEmpty) {
      _showSnack(
        biometricSkipped > 0
            ? 'All checked Present employees already have a biometric check-in — nothing to change.'
            : 'None of the checked employees are marked Present — Bulk Check-In only applies to Present employees.',
        Colors.orange,
      );
      return;
    }

    setState(() {
      for (final row in applicable) {
        row.checkIn = _globalCheckIn;
        row.checkInDate = _globalCheckInDate;
        row.checkInEdited = true;
        row.dirty = true;
      }
    });

    _showSnack(
      'Check-in applied to ${applicable.length} employee(s).'
      '${biometricSkipped > 0 ? ' $biometricSkipped kept their biometric check-in.' : ''}'
      '${skippedCount > 0 ? ' $skippedCount skipped (not Present).' : ''}'
      ' Remember to Save Draft or Submit.',
      Colors.blue.shade700,
    );
  }

  Future<void> _applyBulkCheckOut() async {
    final totalSelected = _selectedNotLockedCount();
    if (totalSelected == 0) {
      _showSnack('Check at least one employee first.', Colors.orange);
      return;
    }

    final applicable = _eligibleSelectedPresentRows();
    final skippedCount = totalSelected - applicable.length;

    if (applicable.isEmpty) {
      _showSnack(
        'None of the checked employees are marked Present — Bulk Check-Out only applies to Present employees.',
        Colors.orange,
      );
      return;
    }

    // B5: Bulk Check-Out is an explicit supervisor decision, so it also
    // fills rows that were waiting for their check-out.
    final waiting = applicable.where((r) => r.checkOutPending).length;
    if (waiting > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter check-out'),
          content: Text(
            '$waiting of the checked employees have no check-out yet (waiting for the biometric OUT). '
            'Set their check-out to ${_fmtTime(_globalCheckOut)}?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Set check-out')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() {
      for (final row in applicable) {
        row.checkOut = _globalCheckOut;
        row.checkOutDate = _globalCheckOutDate;
        row.checkOutPending = false;
        row.checkOutEdited = true;
        row.dirty = true;
      }
    });

    _showSnack(
      skippedCount > 0
          ? 'Check-out applied to ${applicable.length} employee(s). $skippedCount skipped (not Present).'
          : 'Check-out applied to ${applicable.length} employee(s). Remember to Save Draft or Submit.',
      Colors.blue.shade700,
    );
  }

  void _applyBulkLunch() {
    if (_globalLunchStart == null || _globalLunchEnd == null) {
      _showSnack('Set both a lunch start and end time first.', Colors.orange);
      return;
    }

    final totalSelected = _selectedNotLockedCount();
    if (totalSelected == 0) {
      _showSnack('Check at least one employee first.', Colors.orange);
      return;
    }

    final applicable = _eligibleSelectedPresentRows();
    final skippedCount = totalSelected - applicable.length;

    if (applicable.isEmpty) {
      _showSnack(
        'None of the checked employees are marked Present — Bulk Lunch only applies to Present employees.',
        Colors.orange,
      );
      return;
    }

    setState(() {
      for (final row in applicable) {
        row.lunchStart = _globalLunchStart;
        row.lunchEnd = _globalLunchEnd;
        row.dirty = true;
      }
    });

    _showSnack(
      skippedCount > 0
          ? 'Lunch applied to ${applicable.length} employee(s). $skippedCount skipped (not Present).'
          : 'Lunch applied to ${applicable.length} employee(s). Remember to Save Draft or Submit.',
      Colors.blue.shade700,
    );
  }

Future<void> _saveAllAsDraft() async {
  if (_isSaving) return;

  // #2: only rows the supervisor actually changed are sent. Untouched
  // (e.g. biometric) rows are never re-saved, so their times stay exact.
  // A biometric row still waiting for its OUT may be saved IN-only (#3).
  final rows = _rows
      .where((r) =>
          r.dirty &&
          !r.isLocked &&
          r.workflowStatus != 'Rejected' &&
          r.status != null &&
          !(r.status == 'Present' && r.checkOutPending && !r.hasBiometricIn))
      .toList();
  if (rows.isEmpty) {
    _showSnack('No changes to save for this date.', Colors.orange);
    return;
  }
  await _saveRows(rows, mode: 'draft');
}
  // Submit the current date. Selected editable rows carry unsaved edits;
  // existing Draft rows are promoted atomically by the backend.
Future<void> _submitAttendance() async {
  if (_isSaving) return;

  final requiredRows = _rows.where((r) =>
      !r.isLocked &&
      r.workflowStatus != 'Rejected').toList();

  final missing = requiredRows
      .where((r) => r.status == null || !_statuses.contains(r.status))
      .toList();

  if (missing.isNotEmpty) {
    final names = missing.map((r) => r.fullName).join(', ');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Please select an attendance status for: $names',
        ),
      ),
    );
    return;
  }

  final pending = requiredRows
      .where((r) => r.status == 'Present' && r.checkOutPending)
      .toList();

  if (pending.isNotEmpty) {
    _showSnack(
      'Missing check-out (wait for the biometric OUT or enter it manually): '
      '${pending.map((r) => r.fullName).join(', ')}',
      Colors.orange,
    );
    return;
  }

  // #2: unchanged rows are not re-sent; the backend promotes the existing
  // Drafts of this date and validates every staff member.
  await _saveRows(
    requiredRows.where((r) => r.dirty || !r.existing).toList(),
    mode: 'submit',
    submitDay: true,
  );
}

  // ------------------------------------------------------------------
  // Submit one employee directly for Admin review.
  // ------------------------------------------------------------------
  Future<void> _saveOne(_StaffRow row) async {
    if (row.isLocked || _isSaving || row.workflowStatus != 'Rejected') return;
    await _saveRows([row], mode: 'submit', resubmitRejected: true);
  }

  // ------------------------------------------------------------------
  // Save / Submit.
  //
  // mode:
  //   draft  -> Draft
  //   submit -> Submitted
  //
  // This matches the backend exactly.
  // ------------------------------------------------------------------
  Future<void> _saveRows(
    List<_StaffRow> rowsToSave, {
    required String mode,
    bool submitDay = false,
    bool resubmitRejected = false,
  }) async {
    final rows =
        rowsToSave.where((r) => !r.isLocked).toList();

    if (rows.isEmpty && !submitDay || _isSaving) return;

    final isDraft = mode == 'draft';

    // --------------------------------------------------------------
    // 1) Confirmation for bulk operations and old dates.
    // Yesterday is intentionally NOT considered backdated.
    // --------------------------------------------------------------
    if (rows.length > 1 || _isBackdated) {
    final counts = <String, int>{};

for (final r in rows) {
  final status = r.status ?? 'Not set';
  counts[status] =
      (counts[status] ?? 0) + 1;
}

      final summary = counts.entries
          .map((e) => '${e.value} ${e.key}')
          .join('  •  ');

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            isDraft
                ? (_isBackdated
                    ? 'Backdated Draft'
                    : 'Save Draft')
                : (_isBackdated
                    ? 'Backdated Attendance'
                    : 'Submit for Review'),
          ),
          content: Text(
            '${rows.length} employee(s) for $_dateStr\n'
            '$summary\n\n'
            '${_isBackdated ? 'This date is older than yesterday.\n' : ''}'
            '${isDraft
                ? 'They will be saved as Draft. '
                    'Draft records are not sent to the admin '
                    'and are not included in payroll.'
                : 'They will be sent to the admin for approval.'}',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDraft
                    ? Colors.blue.shade700
                    : (_isBackdated
                        ? Colors.orange.shade800
                        : primaryColor),
              ),
              onPressed: () =>
                  Navigator.pop(ctx, true),
              child: Text(
                isDraft ? 'Save Draft' : 'Submit',
                style: const TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) {
        return;
      }
    }

    // --------------------------------------------------------------
    // 2) Friday confirmation.
    //
    // Required by backend in BOTH draft and submit modes.
    // --------------------------------------------------------------
    bool fridayConfirmed = false;

    if (_isFridaySelected &&
        rows.any((r) => r.status == 'Present')) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Friday Attendance'),
          content: const Text(
            'Friday is normally a non-working day. '
            'Are you sure you want to register attendance '
            'for the staff marked Present on this Friday?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
              onPressed: () =>
                  Navigator.pop(ctx, true),
              child: const Text(
                'Confirm',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) {
        return;
      }

      fridayConfirmed = true;
    }

    setState(() => _isSaving = true);

    try {
      final entries = rows.map((row) {
        final map = <String, dynamic>{
          'staff_id': row.staffId,
          'attendance_status': row.status,
        };

        if (row.status == 'Present') {
          // #2: an unedited stored time is sent back exactly (seconds kept).
          map['check_in_time'] = (!row.checkInEdited && row.origCheckIn != null)
              ? row.origCheckIn
              : _fmtDateTime(_combine(row.checkInDate, row.checkIn));

          // B5: a missing check-out is never invented.
          if (!row.checkOutPending) {
            map['check_out_time'] = (!row.checkOutEdited && row.origCheckOut != null)
                ? row.origCheckOut
                : _fmtDateTime(_resolveOut(row));
          }

          if (row.lunchStart != null && row.lunchEnd != null) {
            map['lunch_start_time'] = _fmtDateTime(row.lunchStart!);
            map['lunch_end_time'] = _fmtDateTime(row.lunchEnd!);
          }

          if (_isFridaySelected) {
            map['friday_confirmed'] = fridayConfirmed;
          }
        }

        return map;
      }).toList();

      final response = await ApiConfig.dio.post(
        resubmitRejected
            ? '/staff-attendance/supervisor/resubmit-rejected'
            : '/staff-attendance/supervisor/bulk-set',
        data: {
          'record_date': _dateStr,
          'mode': mode,
          'entries': entries,
          if (submitDay) 'submit_day': true,
          if (resubmitRejected) 'resubmit_rejected': true,
        },
      );

      final data =
          response.data is Map
              ? response.data as Map
              : {};

      final results =
          data['data'] is Map
              ? data['data'] as Map
              : {};

      final skipped =
          (results['skipped'] as List?) ?? [];

      final updatedIds =
          ((results['updated'] as List?) ?? [])
              .map((e) => int.tryParse('$e'))
              .whereType<int>()
              .toSet();

      if (skipped.isNotEmpty) {
        final names = {for (final r in _rows) r.staffId: r.fullName};
        final details = skipped.take(3).map((s) {
          if (s is! Map) return '$s';
          final n = names[int.tryParse('${s['staff_id']}')] ?? s['staff_id'];
          return '$n: ${s['reason']}';
        }).join('\n');

        _showSnack(
          isDraft
              ? '${updatedIds.length} saved as Draft, '
                  '${skipped.length} skipped\n$details'
              : '${updatedIds.length} submitted, '
                  '${skipped.length} skipped\n$details',
          Colors.orange,
        );
      } else {
        _showSnack(
          isDraft
              ? '${updatedIds.length} attendance record(s) saved as Draft.'
              : '${updatedIds.length} submitted for admin review.',
          isDraft
              ? Colors.blue.shade700
              : Colors.green.shade700,
        );
      }

      if (mounted) {
        // Only records actually saved/updated are unchecked.
        // Skipped records stay checked.
        setState(() {
          _selectedStaffIds.removeAll(updatedIds);
        });
      }

      await _loadDay(
        justSavedIds: updatedIds,
      );
    } on DioException catch (e) {
      final msg =
          e.response?.data is Map
              ? (e.response?.data['message'] ??
                  'Failed to save')
              : 'Failed to save';

      _showSnack(
        msg.toString(),
        Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSnack(
    String message,
    Color color,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ------------------------------------------------------------------
  // UI helpers
  // ------------------------------------------------------------------
  Widget _timeField(
    TimeOfDay value,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value,
        );
        if (picked != null) onChanged(picked);
      },
      icon: const Icon(Icons.access_time, size: 16),
      label: Text(_fmtTime(value)),
    );
  }

  Widget _chip(
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _workflowBadge(_StaffRow row) {
    switch (row.workflowStatus) {
      case 'Draft':
        return _chip(
          'Draft',
          Colors.blue.shade700,
        );

      case 'Approved':
        return _chip(
          'Approved',
          Colors.green.shade700,
        );

      case 'Submitted':
        return _chip(
          'Submitted',
          Colors.orange.shade800,
        );

      case 'Rejected':
        return _chip(
          'Rejected',
          Colors.red.shade700,
        );

      default:
        return _chip(
          'Not recorded',
          Colors.grey.shade600,
        );
    }
  }

  Widget _buildBulkPresetCard() {
    final checkedPresent = _checkedPresentCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: primaryColor),
              const SizedBox(width: 6),
              const Text(
                'Bulk Preset (optional)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Only needed when several employees share the same check-in/out or lunch. '
            'Check-in, check-out, and lunch each apply independently — use only what you need.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('In: '),
              _timeField(
                _globalCheckIn,
                (v) => setState(() => _globalCheckIn = v),
              ),
              const SizedBox(width: 20),
              const Text('Out: '),
              _timeField(
                _globalCheckOut,
                (v) => setState(() => _globalCheckOut = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: checkedPresent == 0 ? null : _applyBulkCheckIn,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    checkedPresent == 0
                        ? 'Bulk Check-In'
                        : 'Bulk Check-In ($checkedPresent)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: checkedPresent == 0 ? null : _applyBulkCheckOut,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(
                    checkedPresent == 0
                        ? 'Bulk Check-Out'
                        : 'Bulk Check-Out ($checkedPresent)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final v = await _pickLunchDateTime(
                      'Lunch start',
                      _globalLunchStart,
                    );
                    if (v != null && mounted) {
                      setState(() => _globalLunchStart = v);
                    }
                  },
                  icon: const Icon(Icons.restaurant, size: 16),
                  label: Text(
                    _globalLunchStart == null
                        ? 'Lunch start'
                        : DateFormat('HH:mm').format(_globalLunchStart!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final v = await _pickLunchDateTime(
                      'Lunch end',
                      _globalLunchEnd,
                    );
                    if (v != null && mounted) {
                      setState(() => _globalLunchEnd = v);
                    }
                  },
                  icon: const Icon(Icons.restaurant_menu, size: 16),
                  label: Text(
                    _globalLunchEnd == null
                        ? 'Lunch end'
                        : DateFormat('HH:mm').format(_globalLunchEnd!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: checkedPresent == 0 ? null : _applyBulkLunch,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: Text(
                checkedPresent == 0
                    ? 'Check employees below to enable'
                    : 'Apply Lunch to Selected ($checkedPresent)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'This only fills the fields locally — it does not save anything by itself.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar() {
    final selectableIds =
        _selectableIds;

    final checked =
        _checkedCount;

    final allChecked =
        selectableIds.isNotEmpty &&
        checked == selectableIds.length;

    return Container(
      margin:
          const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allChecked
                ? true
                : (checked == 0
                    ? false
                    : null),
            tristate: true,
                     onChanged:
                selectableIds.isEmpty
                    ? null
                    : (_) => setState(() {
                          if (allChecked) {
                            _selectedStaffIds.clear();
                          } else {
                            _selectedStaffIds
                              ..clear()
                              ..addAll(selectableIds);
                            for (final row in _rows) {
                              if (selectableIds.contains(row.staffId) &&
                                  row.status == null) {
                                row.status = 'Present';
                                row.dirty = true;
                              }
                            }
                          }
                        }),
          ),
          Expanded(
            child: Text(
              checked == 0
                  ? 'Check employees to apply the Bulk Preset above to them'
      : '$checked of ${selectableIds.length} checked for Bulk Preset',
              style: const TextStyle(
                fontWeight:
                    FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (checked > 0)
            TextButton(
              onPressed: () =>
                  setState(
                _selectedStaffIds.clear,
              ),
              child:
                  const Text('Clear'),
            ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(
    _StaffRow row,
  ) {
    final locked =
        row.isLocked;

    final isSelected =
        !locked &&
        _selectedStaffIds
            .contains(row.staffId);

    final _out = _resolveOut(row);
    final isOvernight = DateTime(_out.year, _out.month, _out.day).isAfter(
      DateTime(row.checkInDate.year, row.checkInDate.month, row.checkInDate.day),
    );

    return Card(
      margin:
          const EdgeInsets.only(bottom: 8),
      color: locked
          ? Colors.grey.shade100
          : (isSelected
              ? primaryColor
                  .withOpacity(0.04)
              : null),
      child: Padding(
        padding:
            const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                        Checkbox(
                  value: isSelected,
                  onChanged: locked
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selectedStaffIds.add(row.staffId);
                              // Checking a staff member with no status yet
                              // defaults it to Present — never overwrites
                              // an already-chosen status (e.g. Absent).
                              if (row.status == null) {
                                row.status = 'Present';
                                row.dirty = true;
                              }
                            } else {
                              _selectedStaffIds.remove(row.staffId);
                            }
                          }),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.fullName,
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${row.uniqueId} • ${row.position}',
                        style:
                            TextStyle(
                          fontSize: 11,
                          color:
                              Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _workflowBadge(row),
                          if (row.isBiometric)
                            _chip('Biometric', Colors.indigo),
                          if (row.checkOutPending)
                            _chip('Check-out missing', Colors.orange.shade800),
                          if (row.dirty && !row.isLocked)
                            _chip('Unsaved change', Colors.teal.shade700),
                        ],
                      ),
                    ],
                  ),
                ),
         DropdownButton<String>(
  value: row.status,
  items: _statuses
      .map(
        (s) => DropdownMenuItem(
      value: s,
      child: Text(s),
    ),
  )
      .toList(),
  onChanged: locked
      ? null
      : (v) => setState(() {
            if (v != null && v != row.status) {
              row.status = v;
              row.dirty = true;
            }
          }),
),
                IconButton(
                  tooltip: row.workflowStatus == 'Rejected'
                      ? 'Resubmit this employee'
                      : 'Submit this employee only',
                  icon: Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: locked
                        ? Colors.grey
                        : Colors.green,
                  ),
                  onPressed:
                      (locked || _isSaving || row.workflowStatus != 'Rejected')
                          ? null
                          : () => _saveOne(row),
                ),
              ],
            ),

            // --------------------------------------------------------
            // Rejection reason
            // --------------------------------------------------------
            if (row.rejectionNote != null) ...[
              const SizedBox(height: 8),
              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(8),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.red.shade50,
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
                child: Text(
                  'Admin note: ${row.rejectionNote}',
                  style: TextStyle(
                    color:
                        Colors.red.shade800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],

            // --------------------------------------------------------
            // Approved = locked
            // --------------------------------------------------------
            if (locked) ...[
              const SizedBox(height: 6),
              Text(
                '${row.workflowStatus == 'Submitted' ? 'Submitted — waiting for admin review' : (row.workflowStatus == 'Approved' ? 'Approved by admin — locked' : 'Inactive staff — view only')} '
                '${row.status == 'Present' ? '(${_fmtTime(row.checkIn)} → ${row.checkOutPending ? 'check-out missing' : _fmtTime(row.checkOut)})' : '(${row.status ?? '-'})'}',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      Colors.grey.shade700,
                ),
              ),
            ]

            // --------------------------------------------------------
            // Editable attendance
            // --------------------------------------------------------
            else if (row.status ==
                'Present') ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment:
                    MainAxisAlignment
                        .spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Check-in',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors
                              .grey
                              .shade600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _pickRowDate(row, checkIn: true),
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text(DateFormat('yyyy-MM-dd').format(row.checkInDate)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                        ),
                      ),
                      _timeField(
                        row.checkIn,
                        (v) => setState(() {
                          row.checkIn = v;
                          row.checkInEdited = true;
                          row.dirty = true;
                        }),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Check-out',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors
                              .grey
                              .shade600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _pickRowDate(row, checkIn: false),
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text(DateFormat('yyyy-MM-dd').format(row.checkOutDate)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                        ),
                      ),
                      row.checkOutPending
                          ? OutlinedButton.icon(
                              // B5: the missing OUT is shown as missing; it is
                              // only filled by an explicit time choice.
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: row.checkOut,
                                  helpText: 'Enter the real check-out time',
                                );
                                if (picked != null && mounted) {
                                  setState(() {
                                    row.checkOut = picked;
                                    row.checkOutPending = false;
                                    row.checkOutEdited = true;
                                    row.dirty = true;
                                  });
                                }
                              },
                              icon: Icon(Icons.timer_off_outlined, size: 16, color: Colors.orange.shade800),
                              label: Text('— enter check-out',
                                  style: TextStyle(color: Colors.orange.shade800)),
                            )
                          : _timeField(
                              row.checkOut,
                              (v) => setState(() {
                                row.checkOut = v;
                                row.checkOutPending = false;
                                row.checkOutEdited = true;
                                row.dirty = true;
                              }),
                            ),
                    ],
                  ),
                ],
              ),
              if (isOvernight && !row.checkOutPending)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    top: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons
                            .nightlight_round,
                        size: 13,
                        color: Colors
                            .indigo
                            .shade400,
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Text(
                        'Overnight shift — check-out counted on the next day',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors
                              .indigo
                              .shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickRowLunch(row, start: true),
                      child: Text(
                        row.lunchStart == null
                            ? 'Lunch start'
                            : 'Lunch start\n${DateFormat('yyyy-MM-dd HH:mm').format(row.lunchStart!)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickRowLunch(row, start: false),
                      child: Text(
                        row.lunchEnd == null
                            ? 'Lunch end'
                            : 'Lunch end\n${DateFormat('yyyy-MM-dd HH:mm').format(row.lunchEnd!)}',
                      ),
                    ),
                  ),
                ],
              ),
              if (row.lunchStart != null || row.lunchEnd != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      row.lunchStart = null;
                      row.lunchEnd = null;
                      row.dirty = true;
                    }),
                    child: const Text('Clear lunch'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final checked = _checkedCount;
    final canSaveDraft =
        _rows.any((r) => !r.isLocked && r.workflowStatus != 'Rejected');
    final canSubmitAttendance = _rows.any((r) =>
        !r.isLocked &&
        r.workflowStatus != 'Rejected');

    return Scaffold(
      backgroundColor:
          Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Staff Attendance',
        actions: [
          IconButton(
            icon:
                const Icon(Icons.refresh),
            onPressed: () =>
                _loadDay(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : Column(
              children: [
                // ----------------------------------------------------
                // Date header
                // ----------------------------------------------------
                Container(
                  margin:
                      const EdgeInsets.all(
                    12,
                  ),
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration:
                      BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius
                            .circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color:
                            primaryColor,
                        size: 18,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child:
                            GestureDetector(
                          onTap:
                              _pickDate,
                          child: Text(
                            DateFormat(
                              'EEEE, dd MMM yyyy',
                            ).format(
                              _selectedDate,
                            ),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      ),
                      if (_isFridaySelected)
                        Container(
                          margin:
                              const EdgeInsets
                                  .only(
                            right: 6,
                          ),
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration:
                              BoxDecoration(
                            color: Colors
                                .deepPurple
                                .shade50,
                            borderRadius:
                                BorderRadius
                                    .circular(
                              8,
                            ),
                          ),
                          child: Text(
                            'Friday',
                            style: TextStyle(
                              color: Colors
                                  .deepPurple
                                  .shade700,
                              fontSize: 11,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      if (_isBackdated)
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration:
                              BoxDecoration(
                            color: Colors
                                .orange
                                .shade50,
                            borderRadius:
                                BorderRadius
                                    .circular(
                              8,
                            ),
                          ),
                          child: Text(
                            'Backdated',
                            style: TextStyle(
                              color: Colors
                                  .orange
                                  .shade800,
                              fontSize: 11,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      TextButton.icon(
                        onPressed:
                            _pickDate,
                        icon: const Icon(
                          Icons
                              .edit_calendar,
                          size: 16,
                        ),
                        label:
                            const Text(
                          'Change',
                        ),
                      ),
                    ],
                  ),
                ),

                // ----------------------------------------------------
                // Friday banner
                // ----------------------------------------------------
                if (_isFridaySelected)
                  Container(
                    margin:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 12,
                    ),
                    padding:
                        const EdgeInsets.all(
                      10,
                    ),
                    decoration:
                        BoxDecoration(
                      color: Colors
                          .deepPurple
                          .shade50,
                      borderRadius:
                          BorderRadius
                              .circular(
                        10,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons
                              .info_outline,
                          size: 16,
                          color: Colors
                              .deepPurple
                              .shade700,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Text(
                            'Friday is normally a non-working day. '
                            'Marking anyone Present will require confirmation '
                            'before saving or submitting.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors
                                  .deepPurple
                                  .shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),

                // ----------------------------------------------------
                // Search
                // ----------------------------------------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search staff by name or ID...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // ----------------------------------------------------
                // Staff list
                // ----------------------------------------------------
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(
                          child: Text('No active staff found'),
                        )
                      : _filteredRows.isEmpty
                          ? Center(
                              child: Text(
                                'No staff match "$_searchQuery"',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => _loadDay(),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),

                                // Bulk time card + selection toolbar + staff rows
                                itemCount: _filteredRows.length + 2,

                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return _buildBulkPresetCard();
                                  }

                                  if (index == 1) {
                                    return _buildSelectionToolbar();
                                  }

                                  return _buildStaffCard(
                                    _filteredRows[index - 2],
                                  );
                                },
                              ),
                            ),
                ),

                // ----------------------------------------------------
                // Bottom actions
                // ----------------------------------------------------
                Container(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  color: Colors.white,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .stretch,
                      children: [
                        // ------------------------------------------------
                        // Save Draft + Submit Attendance
                        // ------------------------------------------------
                        Row(
                          children: [
                          Expanded(
  child: SizedBox(
    height: 50,
    child: OutlinedButton.icon(
      onPressed:
          (_isSaving || !canSaveDraft)
              ? null
              : _saveAllAsDraft,
      icon:
          _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(
                  Icons.save_outlined,
                ),
      label: const Text(
        'Save Draft (All)',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blue.shade700,
        side: BorderSide(color: Colors.blue.shade700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  ),
),
                            const SizedBox(
                              width: 10,
                            ),
                            Expanded(
                              child:
                                  SizedBox(
                                height: 50,
                                child:
                                    ElevatedButton.icon(
                                  onPressed:
                                      (_isSaving || !canSubmitAttendance)
                                          ? null
                                          : _submitAttendance,
                                  icon:
                                      _isSaving
                                          ? const SizedBox(
                                              width:
                                                  18,
                                              height:
                                                  18,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth:
                                                    2,
                                                color:
                                                    Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons
                                                  .send_rounded,
                                              color:
                                                  Colors.white,
                                            ),
                                  label:
                                      Text(
                                    _isSaving
                                        ? 'Submitting...'
                                        : 'Submit Attendance',
                                    style:
                                        const TextStyle(
                                      color:
                                          Colors.white,
                                      fontSize:
                                          13.5,
                                      fontWeight:
                                          FontWeight
                                              .bold,
                                    ),
                                    textAlign:
                                        TextAlign
                                            .center,
                                  ),
                                  style:
                                      ElevatedButton
                                          .styleFrom(
                                    backgroundColor:
                                        primaryColor,
                                    disabledBackgroundColor:
                                        Colors
                                            .grey
                                            .shade400,
                                    shape:
                                        RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}