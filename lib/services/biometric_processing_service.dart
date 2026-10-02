import 'package:dio/dio.dart';
import '../constants.dart';

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String? _str(dynamic v) {
  final s = v?.toString();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

/// Human-readable API failure (never contains stack traces / raw exceptions).
class BiometricApiException implements Exception {
  final String message;
  final int? statusCode;

  /// Extra machine-readable fields from the backend (e.g. code, lunch_period).
  final Map<String, dynamic> details;
  const BiometricApiException(this.message, {this.statusCode, this.details = const {}});
  String? get code => details['code']?.toString();
  @override
  String toString() => message;
}

/// Plain-language explanation for every backend result code (Phase 2).
String explainBiometricResult(String? result, {String deviceEmployeeId = ''}) {
  switch (result) {
    case 'unmapped':
      return 'Device employee $deviceEmployeeId is not mapped to a worker/staff member for this date. Map it, then Retry.';
    case 'no_assignment':
      return 'The worker has no site/shift assignment on the punch date.';
    case 'multiple_assignments':
      return 'The worker has more than one site/shift assignment on the punch date.';
    case 'worker_inactive_on_date':
      return 'The worker was Inactive on the punch date (status history).';
    case 'worker_status_unknown':
      return 'The worker is Inactive and has no status history, so the status on that date is unknown.';
    case 'site_not_active':
      return 'The site is not Active.';
    case 'staff_not_employed_on_date':
      return 'The staff member was not employed on the punch date.';
    case 'no_supervisor_assignment':
      return 'The staff member has no Staff Supervisor on the punch date. Assign one, then Retry.';
    case 'manual_record_exists':
      return 'A manual attendance record exists. Biometric never changes manual attendance.';
    case 'already_applied':
      return 'Already reflected on the attendance record.';
    case 'record_locked':
      return 'The attendance record is already Submitted/Approved.';
    case 'record_rejected':
      return 'The attendance record is Rejected and is being corrected by the supervisor.';
    case 'human_edited':
      return 'The record was edited by a person; biometric will not overwrite it.';
    case 'ambiguous_consecutive_in':
      return 'A new IN arrived while the previous session is still open. Decide: checkout, duplicate or new session.';
    case 'consecutive_in':
      return 'A second IN arrived for a session that is still open.';
    case 'earlier_in_same_day':
      return 'An IN earlier than the recorded check-in arrived for the same day.';
    case 'in_within_session':
      return 'An IN arrived between the recorded check-in and check-out.';
    case 'second_session_same_day':
      return 'An IN arrived after the day\'s session was already closed.';
    case 'out_without_in':
      return 'An OUT arrived but there is no earlier session to close.';
    case 'consecutive_out':
      return 'An OUT arrived after the session was already closed.';
    case 'out_within_session':
      return 'An OUT arrived between the recorded check-in and check-out.';
    case 'out_far_from_session':
      return 'The latest open session did not start on the OUT date or the day before.';
    case 'session_not_present':
      return 'The session is not marked Present.';
    case 'open_break':
      return 'The worker has an open break. End it, then Retry.';
    case 'invalid_duration':
      return 'Hours could not be calculated for this check-out.';
    case 'future_punch':
      return 'The punch date is in the future (check the device clock).';
    case 'punch_too_old':
      return 'The punch is older than the allowed window (counted from the punch time). '
          'An Admin can restore it for processing with a reason.';
    case 'long_duration':
      return 'The session would be unusually long (above the review threshold). It is NOT closed automatically: '
          'check for a forgotten check-out, then use it as check-out, enter the correct time, or mark it duplicate.';
    case 'payroll_period_finalized':
      return 'The punch date is inside a finalized or paid payroll period. Attendance there is locked; '
          'use the Admin correction workflow if a change is really needed.';
    case 'restored_for_processing':
      return 'Restored by an Admin for processing (window override).';
    case 'requeued':
      return 'Re-queued with the current employee mapping.';
    case 'recovered_orphan':
      return 'Raw punch recovered by the migration. Retry to process it, or dismiss it.';
    case 'marked_duplicate':
      return 'Marked as a duplicate punch by an admin.';
    case 'used_as_checkout':
      return 'Applied as a check-out by an admin decision.';
    case 'kept_as_new_in':
      return 'Kept as a new IN session by an admin decision.';
    case 'created':
      return 'Attendance session created.';
    case 'checked_out':
      return 'Check-out applied.';
    case 'exception':
      return 'An unexpected error occurred while processing this punch.';
    case null:
      return 'No result recorded.';
    default:
      return 'Backend result: $result';
  }
}

String biometricActionLabel(String action) {
  switch (action) {
    case 'use_as_checkout':
      return 'Use as Checkout';
    case 'enter_checkout':
      return 'Enter Checkout';
    case 'mark_duplicate':
      return 'Mark as Duplicate';
    case 'keep_as_new_in':
      return 'Keep as New IN';
    case 'map_employee':
      return 'Map Employee';
    case 'retry':
      return 'Retry';
    case 'dismiss':
      return 'Dismiss';
    case 'review_later':
      return 'Review Later';
    case 'restore_for_processing':
      return 'Restore for processing';
    case 'requeue':
      return 'Re-queue with current mapping';
    default:
      return action;
  }
}

class BiometricStatus {
  final int pending;
  final int processed;
  final int skipped;
  final int needsReview;
  final int invalid;
  final int failed;
  final int dismissed;
  final int total;

  const BiometricStatus({
    required this.pending,
    required this.processed,
    required this.skipped,
    required this.needsReview,
    required this.invalid,
    required this.failed,
    required this.dismissed,
    required this.total,
  });

  factory BiometricStatus.fromJson(Map<String, dynamic> j) => BiometricStatus(
        pending: _int(j['Pending']),
        processed: _int(j['Processed']),
        skipped: _int(j['Skipped']),
        needsReview: _int(j['NeedsReview']),
        invalid: _int(j['Invalid']),
        failed: _int(j['Failed']),
        dismissed: _int(j['Dismissed']),
        total: _int(j['total']),
      );
}

class BiometricRunSummary {
  final int selected;
  final int processed;
  final int skipped;
  final int needsReview;
  final int invalid;
  final int failed;
  final bool retryFailed;

  /// Measured on this device (backend does not return timestamps/duration).
  final DateTime requestedAt;
  final Duration roundTrip;

  const BiometricRunSummary({
    required this.selected,
    required this.processed,
    required this.skipped,
    required this.needsReview,
    required this.invalid,
    required this.failed,
    required this.retryFailed,
    required this.requestedAt,
    required this.roundTrip,
  });
}

class BiometricIssue {
  final int punchId;
  final String deviceEmployeeId;
  final String punchedAt;
  final String punchType;
  final String status;
  final String? result;
  final String? error;
  final int attempts;
  final String? processedAt;
  final int? processedByUserId;

  const BiometricIssue({
    required this.punchId,
    required this.deviceEmployeeId,
    required this.punchedAt,
    required this.punchType,
    required this.status,
    required this.result,
    required this.error,
    required this.attempts,
    required this.processedAt,
    required this.processedByUserId,
  });

  factory BiometricIssue.fromJson(Map<String, dynamic> j) => BiometricIssue(
        punchId: _int(j['punch_id']),
        deviceEmployeeId: j['device_employee_id']?.toString() ?? '',
        punchedAt: j['punched_at']?.toString() ?? '',
        punchType: j['punch_type']?.toString() ?? '',
        status: j['processing_status']?.toString() ?? '',
        result: _str(j['processing_result']),
        error: _str(j['processing_error']),
        attempts: _int(j['attempts']),
        processedAt: _str(j['processed_at']),
        processedByUserId:
            j['processed_by_user_id'] == null ? null : _int(j['processed_by_user_id']),
      );

  /// Plain-language explanation derived ONLY from the backend result code.
  String get explanation => explainBiometricResult(result, deviceEmployeeId: deviceEmployeeId);
}

/// The attendance record a review item relates to (worker or staff).
class ReviewTarget {
  final String table; // attendance | staff_attendance
  final int recordId;
  final String fullName;
  final String? uniqueId;
  final String? siteName;
  final String? shiftType;
  final String? recordDate;
  final String? checkIn;
  final String? checkOut;
  final String? status;
  final String? attendanceStatus;
  final String? source;

  const ReviewTarget({
    required this.table,
    required this.recordId,
    required this.fullName,
    this.uniqueId,
    this.siteName,
    this.shiftType,
    this.recordDate,
    this.checkIn,
    this.checkOut,
    this.status,
    this.attendanceStatus,
    this.source,
  });

  bool get isWorker => table == 'attendance';

  factory ReviewTarget.fromJson(Map<String, dynamic> j) => ReviewTarget(
        table: j['target_table']?.toString() ?? '',
        recordId: _int(j['record_id']),
        fullName: j['full_name']?.toString() ?? '',
        uniqueId: _str(j['unique_id']),
        siteName: _str(j['site_name']),
        shiftType: _str(j['shift_type']),
        recordDate: _str(j['record_date']),
        checkIn: _str(j['check_in_time']),
        checkOut: _str(j['check_out_time']),
        status: _str(j['status']),
        attendanceStatus: _str(j['attendance_status']),
        source: _str(j['source']),
      );
}

class ReviewMapping {
  final int id;
  final String entityType;
  final String? personName;
  final String? personUniqueId;
  final String? effectiveFrom;
  final String? effectiveTo;
  final bool active;

  const ReviewMapping({
    required this.id,
    required this.entityType,
    this.personName,
    this.personUniqueId,
    this.effectiveFrom,
    this.effectiveTo,
    required this.active,
  });

  factory ReviewMapping.fromJson(Map<String, dynamic> j) => ReviewMapping(
        id: _int(j['id']),
        entityType: j['entity_type']?.toString() ?? '',
        personName: _str(j['person_name']),
        personUniqueId: _str(j['person_unique_id']),
        effectiveFrom: _str(j['effective_from']),
        effectiveTo: _str(j['effective_to']),
        active: _int(j['active']) == 1,
      );
}

class ReviewItem {
  final int punchId;
  final String deviceEmployeeId;
  final String punchedAt;
  final String punchType;
  final String status;
  final String? result;
  final String? message;
  final int attempts;
  final String? resolutionNote;
  final String batchStatus;
  final ReviewMapping? mapping;
  final String? mappingSource; // used | current
  final ReviewTarget? target;
  final List<String> actions;

  const ReviewItem({
    required this.punchId,
    required this.deviceEmployeeId,
    required this.punchedAt,
    required this.punchType,
    required this.status,
    required this.result,
    required this.message,
    required this.attempts,
    required this.resolutionNote,
    required this.batchStatus,
    required this.mapping,
    required this.mappingSource,
    required this.target,
    required this.actions,
  });

  String get explanation =>
      message ?? explainBiometricResult(result, deviceEmployeeId: deviceEmployeeId);

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        punchId: _int(j['punch_id']),
        deviceEmployeeId: j['device_employee_id']?.toString() ?? '',
        punchedAt: j['punched_at']?.toString() ?? '',
        punchType: j['punch_type']?.toString() ?? '',
        status: j['processing_status']?.toString() ?? '',
        result: _str(j['processing_result']),
        message: _str(j['message']),
        attempts: _int(j['attempts']),
        resolutionNote: _str(j['resolution_note']),
        batchStatus: j['batch_status']?.toString() ?? '',
        mapping: j['mapping'] is Map ? ReviewMapping.fromJson(Map<String, dynamic>.from(j['mapping'] as Map)) : null,
        mappingSource: _str(j['mapping_source']),
        target: j['target'] is Map ? ReviewTarget.fromJson(Map<String, dynamic>.from(j['target'] as Map)) : null,
        actions: ((j['actions'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

class DailyReview {
  final String date;
  final Map<String, int> byStatus;
  final int stillUnresolvedTotal;
  final int resolvedToday;
  final Map<String, int> needsReviewByReason;
  final List<ReviewItem> items;
  final List<Map<String, dynamic>> missingCheckouts;
  final List<Map<String, dynamic>> orphanDrafts;
  final List<Map<String, dynamic>> unmappedDeviceIds;

  const DailyReview({
    required this.date,
    required this.byStatus,
    required this.stillUnresolvedTotal,
    required this.resolvedToday,
    required this.needsReviewByReason,
    required this.items,
    required this.missingCheckouts,
    required this.orphanDrafts,
    required this.unmappedDeviceIds,
  });

  factory DailyReview.fromJson(Map<String, dynamic> j) {
    final counts = Map<String, dynamic>.from((j['counts'] as Map?) ?? {});
    Map<String, int> ints(dynamic v) =>
        Map<String, dynamic>.from((v as Map?) ?? {}).map((k, val) => MapEntry(k, _int(val)));
    List<Map<String, dynamic>> maps(dynamic v) =>
        ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return DailyReview(
      date: j['date']?.toString() ?? '',
      byStatus: ints(counts['by_status']),
      stillUnresolvedTotal: _int(counts['still_unresolved_total']),
      resolvedToday: _int(counts['resolved_today']),
      needsReviewByReason: ints(counts['needs_review_by_reason']),
      items: ((j['items'] as List?) ?? [])
          .map((e) => ReviewItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      missingCheckouts: maps(j['missing_checkouts']),
      orphanDrafts: maps(j['orphan_drafts']),
      unmappedDeviceIds: maps(j['unmapped_device_ids']),
    );
  }
}

class BiometricProcessingService {
  static const _base = '/biometric/processing';

  static BiometricApiException _map(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final backendMsg =
          data is Map && data['message'] != null ? data['message'].toString() : null;
      final details = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      switch (code) {
        case 400:
          return BiometricApiException(backendMsg ?? 'Invalid request.', statusCode: 400, details: details);
        case 401:
          return const BiometricApiException('Your session is no longer valid.', statusCode: 401);
        case 403:
          return const BiometricApiException(
              'You do not have permission to access biometric processing.',
              statusCode: 403);
        case 404:
          return BiometricApiException(backendMsg ?? 'Not found.', statusCode: 404, details: details);
        case 409:
          return BiometricApiException(
              backendMsg ?? 'Biometric processing is already running. Please wait and try again.',
              statusCode: 409,
              details: details);
      }
      if (code != null && code >= 500) {
        return BiometricApiException(
            backendMsg ?? 'Server error while handling biometric processing.',
            statusCode: code);
      }
      return const BiometricApiException(
          'Could not reach the server. Check your connection and try again.');
    }
    return const BiometricApiException('Unexpected error. Please try again.');
  }

  Future<BiometricStatus> getBiometricProcessingStatus() async {
    try {
      final r = await ApiConfig.dio.get('$_base/status');
      return BiometricStatus.fromJson(Map<String, dynamic>.from(r.data['data'] as Map));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> getBiometricAttendance(String date) async {
    try {
      final r = await ApiConfig.dio.get('/biometric/attendance', queryParameters: {'date': date});
      List<Map<String, dynamic>> l(dynamic v) =>
          ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return {'workers': l(r.data['workers']), 'staff': l(r.data['staff'])};
    } catch (e) {
      throw _map(e);
    }
  }

  /// [clearCheckOut] (#16) clears a wrong check-out on a Draft. The raw punch
  /// is never changed.
  Future<void> editBiometricTimes({
    required bool isWorker,
    required int id,
    String? checkIn,
    String? checkOut,
    bool clearCheckOut = false,
    required String reason,
  }) async {
    try {
      await ApiConfig.dio.patch('/biometric/attendance/${isWorker ? 'worker' : 'staff'}/$id', data: {
        if (checkIn != null) 'check_in_time': checkIn,
        if (checkOut != null && !clearCheckOut) 'check_out_time': checkOut,
        if (clearCheckOut) 'clear_check_out': true,
        'reason': reason,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  // Same export the Payroll screen uses.
  Future<List<int>> downloadDailyAttendance(String date) async {
    try {
      final r = await ApiConfig.dio.get<List<int>>(
        '/admin/payroll/daily-attendance/export.xlsx',
        queryParameters: {'date': date},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 90)),
      );
      final bytes = r.data;
      if (bytes == null || bytes.isEmpty) {
        throw const BiometricApiException('Empty attendance report.');
      }
      return bytes;
    } catch (e) {
      if (e is BiometricApiException) rethrow;
      throw _map(e);
    }
  }

  Future<BiometricRunSummary> processBiometricPunches({
    int limit = 200,
    bool? retryFailed,
  }) async {
    final requestedAt = DateTime.now();
    final sw = Stopwatch()..start();
    try {
      final r = await ApiConfig.dio.post(
        '$_base/process',
        data: {
          'limit': limit,
          if (retryFailed != null) 'retry_failed': retryFailed,
        },
        // Processing up to 200 punches can exceed the global 10s timeout.
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );
      sw.stop();
      final d = Map<String, dynamic>.from(r.data['data'] as Map);
      return BiometricRunSummary(
        selected: _int(d['selected']),
        processed: _int(d['processed']),
        skipped: _int(d['skipped']),
        needsReview: _int(d['needs_review']),
        invalid: _int(d['invalid']),
        failed: _int(d['failed']),
        retryFailed: d['retry_failed'] == true,
        requestedAt: requestedAt,
        roundTrip: sw.elapsed,
      );
    } catch (e) {
      throw _map(e);
    }
  }

  /// [status] = null (NeedsReview + Failed) or one of
  /// NeedsReview | Failed | Invalid | Skipped | Dismissed.
  Future<List<BiometricIssue>> getBiometricProcessingIssues({
    String? status,
    int limit = 100,
  }) async {
    try {
      final r = await ApiConfig.dio.get('$_base/failed', queryParameters: {
        'limit': limit,
        if (status != null) 'status': status,
      });
      final list = (r.data['data'] as List?) ?? [];
      return list
          .map((e) => BiometricIssue.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw _map(e);
    }
  }

  // ------------------------------------------------------------------
  // Phase 2 — Daily Review
  // ------------------------------------------------------------------

  Future<DailyReview> getDailyReview(String date, {bool unresolvedOnly = false}) async {
    try {
      final r = await ApiConfig.dio.get('$_base/review', queryParameters: {
        'date': date,
        if (unresolvedOnly) 'scope': 'unresolved',
      });
      return DailyReview.fromJson(Map<String, dynamic>.from(r.data['data'] as Map));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> _action(String path, [Map<String, dynamic>? body]) async {
    try {
      final r = await ApiConfig.dio.post(path, data: body ?? {},
          options: Options(receiveTimeout: const Duration(seconds: 60)));
      return r.data['message']?.toString() ?? 'Done.';
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> retryItem(int punchId) => _action('$_base/items/$punchId/retry');

  Future<String> useAsCheckout(int punchId, int targetRecordId, {String? reason}) =>
      _action('$_base/items/$punchId/use-as-checkout', {
        'target_record_id': targetRecordId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

  Future<String> keepAsNewIn(int punchId, {String? reason}) =>
      _action('$_base/items/$punchId/keep-as-new-in', {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

  Future<String> markDuplicate(int punchId, {String? note}) =>
      _action('$_base/items/$punchId/mark-duplicate', {
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<String> reviewLater(int punchId, String note) =>
      _action('$_base/items/$punchId/review-later', {'note': note});

  Future<String> dismissItems(List<int> punchIds, String note) =>
      _action('$_base/items/dismiss', {'punch_ids': punchIds, 'note': note});

  Future<String> requeueItem(int punchId, String reason) =>
      _action('$_base/items/$punchId/requeue', {'reason': reason});

  /// D-04: an Invalid (too old) punch can be restored with a reason; it is
  /// then processed normally on the next run. Nothing is deleted.
  Future<String> restoreItem(int punchId, String reason) =>
      _action('$_base/items/$punchId/restore', {'reason': reason});

  /// Processing history (every attempt and admin decision) for one punch.
  Future<List<Map<String, dynamic>>> getItemHistory(int punchId) async {
    try {
      final r = await ApiConfig.dio.get('$_base/items/$punchId/history');
      final data = r.data is Map ? r.data['data'] : null;
      final list = data is Map ? (data['history'] ?? data['log'] ?? []) : (data ?? []);
      return (list as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> closeStaleBatch(int batchId, String reason) =>
      _action('$_base/batches/$batchId/close', {'reason': reason});

  /// D2 — Admin "Submit for review" for an orphaned biometric Draft.
  /// [lunchDecision] is only needed when the backend answers
  /// code LUNCH_DECISION_REQUIRED (workers).
  Future<String> adminSubmitForReview({
    required bool isWorker,
    required int recordId,
    required String reason,
    Map<String, dynamic>? lunchDecision,
  }) =>
      _action('$_base/records/submit-for-review', {
        'kind': isWorker ? 'Worker' : 'Staff',
        'record_id': recordId,
        'reason': reason,
        if (lunchDecision != null) 'lunch_decision': lunchDecision,
      });

  Future<Map<String, dynamic>> getMappingImpact(int mappingId) async {
    try {
      final r = await ApiConfig.dio.get('$_base/mapping-impact/$mappingId');
      return Map<String, dynamic>.from(r.data['data'] as Map);
    } catch (e) {
      throw _map(e);
    }
  }

  // ------------------------------------------------------------------
  // B4 — Lunch for biometric staff records
  // ------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getStaffLunchDay(String date) async {
    try {
      final r = await ApiConfig.dio.get('/staff-attendance/admin/lunch', queryParameters: {'date': date});
      return ((r.data['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> applyStaffLunch({
    required String date,
    required List<int> staffAttendanceIds,
    String? lunchStart,
    String? lunchEnd,
    bool remove = false,
  }) =>
      _action('/staff-attendance/admin/lunch/apply', {
        'date': date,
        'staff_attendance_ids': staffAttendanceIds,
        if (!remove) 'lunch_start': lunchStart,
        if (!remove) 'lunch_end': lunchEnd,
        if (remove) 'remove': true,
      });
}
