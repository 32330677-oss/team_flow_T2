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
  const BiometricApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class BiometricStatus {
  final int pending;
  final int processed;
  final int skipped;
  final int failed;
  final int total;

  const BiometricStatus({
    required this.pending,
    required this.processed,
    required this.skipped,
    required this.failed,
    required this.total,
  });

  factory BiometricStatus.fromJson(Map<String, dynamic> j) => BiometricStatus(
        pending: _int(j['Pending']),
        processed: _int(j['Processed']),
        skipped: _int(j['Skipped']),
        failed: _int(j['Failed']),
        total: _int(j['total']),
      );
}

class BiometricRunSummary {
  final int selected;
  final int processed;
  final int skipped;
  final int failed;
  final bool retryFailed;
  final bool retrySkipped;

  /// Measured on this device (backend does not return timestamps/duration).
  final DateTime requestedAt;
  final Duration roundTrip;

  const BiometricRunSummary({
    required this.selected,
    required this.processed,
    required this.skipped,
    required this.failed,
    required this.retryFailed,
    required this.retrySkipped,
    required this.requestedAt,
    required this.roundTrip,
  });
}

class BiometricIssue {
  final int punchId;
  final String deviceEmployeeId;
  final String punchedAt;
  final String punchType;
  final String status; // Skipped | Failed
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
  String get explanation {
    switch (result) {
      case 'unmapped':
        return 'Device employee $deviceEmployeeId is not mapped to a worker/staff account for this date.';
      case 'no_assignment':
        return 'The mapped worker has no site assignment on the punch date.';
      case 'outside_shift_window':
        return 'The punch time is outside the worker\'s Night shift window.';
      case 'no_open_attendance':
        return 'An OUT punch arrived but there is no attendance record to close.';
      case 'no_check_in':
        return 'An OUT punch arrived but the attendance record has no check-in.';
      case 'invalid_checkout_time':
        return 'The OUT time is not after the existing check-in. Needs review.';
      case 'exception':
        return 'An unexpected error occurred while processing this punch.';
      case null:
        return 'No result recorded.';
      default:
        return 'Backend result: $result';
    }
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
      switch (code) {
        case 400:
          return BiometricApiException(backendMsg ?? 'Invalid request.', statusCode: 400);
        case 401:
          return const BiometricApiException('Your session is no longer valid.', statusCode: 401);
        case 403:
          return const BiometricApiException(
              'You do not have permission to access biometric processing.',
              statusCode: 403);
        case 409:
          return const BiometricApiException(
              'Biometric processing is already running. Please wait and try again.',
              statusCode: 409);
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

  Future<BiometricRunSummary> processBiometricPunches({
    int limit = 200,
    bool? retrySkipped,
    bool? retryFailed,
  }) async {
    final requestedAt = DateTime.now();
    final sw = Stopwatch()..start();
    try {
      final r = await ApiConfig.dio.post(
        '$_base/process',
        data: {
          'limit': limit,
          if (retrySkipped != null) 'retry_skipped': retrySkipped,
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
        failed: _int(d['failed']),
        retryFailed: d['retry_failed'] == true,
        retrySkipped: d['retry_skipped'] == true,
        requestedAt: requestedAt,
        roundTrip: sw.elapsed,
      );
    } catch (e) {
      throw _map(e);
    }
  }

  /// [status] = null (both), 'Skipped' or 'Failed'.
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
}