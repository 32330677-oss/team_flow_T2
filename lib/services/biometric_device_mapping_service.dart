import 'package:dio/dio.dart';
import '../constants.dart';
import 'biometric_processing_service.dart' show BiometricApiException;

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String? _str(dynamic v) {
  final s = v?.toString();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

class UnmappedDevice {
  final String deviceEmployeeId;
  final int punches;
  final String? firstPunch;
  final String? lastPunch;

  const UnmappedDevice({
    required this.deviceEmployeeId,
    required this.punches,
    this.firstPunch,
    this.lastPunch,
  });

  factory UnmappedDevice.fromJson(Map<String, dynamic> j) {
    return UnmappedDevice(
      deviceEmployeeId: j['device_employee_id']?.toString() ?? '',
      punches: _int(j['punches']),
      firstPunch: _str(j['first_punch']),
      lastPunch: _str(j['last_punch']),
    );
  }
}

class AvailableBiometricPerson {
  final int id;
  final String uniqueId;
  final String fullName;
  final String? position;

  final String? startDate;

  /// Only filled when the list was loaded with includeInactive (D5).
  final String? status;
  final String? terminationDate;

  const AvailableBiometricPerson({required this.id, required this.uniqueId,
      required this.fullName, this.position, this.startDate, this.status,
      this.terminationDate});

  bool get isActive => status == null || status == 'Active';

  factory AvailableBiometricPerson.fromJson(Map<String, dynamic> j) {
    final sd = _str(j['start_date']);
    final td = _str(j['termination_date']);
    return AvailableBiometricPerson(
      id: _int(j['worker_id'] ?? j['staff_id']),
      uniqueId: j['worker_unique_id']?.toString() ?? j['staff_unique_id']?.toString() ?? '',
      fullName: j['full_name']?.toString() ?? '',
      position: _str(j['position']),
      startDate: sd == null ? null : sd.substring(0, sd.length < 10 ? sd.length : 10),
      status: _str(j['status']),
      terminationDate: td == null ? null : td.substring(0, td.length < 10 ? td.length : 10),
    );
  }
}

class BiometricDeviceMappingService {
  static BiometricApiException _map(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final data = e.response?.data;

      final backendMsg =
          data is Map && data['message'] != null
              ? data['message'].toString()
              : null;

      switch (code) {
        case 400:
          return BiometricApiException(
            backendMsg ?? 'Invalid mapping request.',
            statusCode: 400,
          );

        case 401:
          return const BiometricApiException(
            'Your session is no longer valid.',
            statusCode: 401,
          );

        case 403:
          return const BiometricApiException(
            'You do not have permission to manage device mappings.',
            statusCode: 403,
          );

        case 404:
          return BiometricApiException(
            backendMsg ?? 'The selected device or person was not found.',
            statusCode: 404,
          );

        case 409:
          return BiometricApiException(
            backendMsg ?? 'This device ID is already mapped or the mapping conflicts with another mapping.',
            statusCode: 409,
          );
      }

      if (code != null && code >= 500) {
        return BiometricApiException(
          backendMsg ?? 'Server error while saving the device mapping.',
          statusCode: code,
        );
      }

      return const BiometricApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    return const BiometricApiException(
      'Unexpected error. Please try again.',
    );
  }

  Future<List<UnmappedDevice>> getUnmappedDevices() async {
    try {
      final r = await ApiConfig.dio.get(
        '/biometric/punches/unmapped',
      );

      final list = (r.data['data'] as List?) ?? [];

      return list
          .map(
            (e) => UnmappedDevice.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (e) {
      throw _map(e);
    }
  }

/// [includeInactive] (D5): every person, any status, for a CLOSED
/// historical mapping (effective_to required).
Future<List<AvailableBiometricPerson>> getAvailablePeople(
  String entityType, {
  bool includeInactive = false,
}) async {
  try {
    final r = await ApiConfig.dio.get(
      '/biometric/device-users/available',
      queryParameters: {
        'entity_type': entityType,
        if (includeInactive) 'include_inactive': '1',
      },
    );

    final list = (r.data['data'] as List?) ?? [];

    return list
        .map(
          (e) => AvailableBiometricPerson.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  } catch (e) {
    throw _map(e);
  }
}

  Future<void> createMapping({
    required String deviceEmployeeId,
    required String entityType,
    required int entityId,
    required String effectiveFrom,
    String? effectiveTo,
  }) async {
    try {
      await ApiConfig.dio.post(
        '/biometric/device-users',
        data: {
          'device_employee_id': deviceEmployeeId,
          'entity_type': entityType,
          if (entityType == 'Worker')
            'worker_id': entityId
          else
            'staff_id': entityId,
          'effective_from': effectiveFrom,
          if (effectiveTo != null) 'effective_to': effectiveTo,
        },
      );
    } catch (e) {
      throw _map(e);
    }
  }
}