import 'package:dio/dio.dart';
import '../constants.dart';
import 'biometric_processing_service.dart' show BiometricApiException;

int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
String? _s(dynamic v) {
  final s = v?.toString();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

class ImportBatch {
  final int id;
  final String sourceFile;
  final String status;
  final int total, inserted, duplicates, errors;
  final String? importedAt;
  final String? createdAt;

  const ImportBatch({
    required this.id, required this.sourceFile, required this.status,
    required this.total, required this.inserted, required this.duplicates,
    required this.errors, this.importedAt, this.createdAt,
  });

  factory ImportBatch.fromJson(Map<String, dynamic> j) => ImportBatch(
        id: _i(j['id']),
        sourceFile: j['source_file']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        total: _i(j['total_rows']),
        inserted: _i(j['inserted_rows']),
        duplicates: _i(j['duplicate_rows']),
        errors: _i(j['error_rows']),
        importedAt: _s(j['imported_at']),
        createdAt: _s(j['created_at']),
      );
}

class ConnectorStatus {
  final bool enabled, running;
  final int incomingFiles, failedFiles;
  const ConnectorStatus({
    required this.enabled, required this.running,
    required this.incomingFiles, required this.failedFiles,
  });
  factory ConnectorStatus.fromJson(Map<String, dynamic> j) => ConnectorStatus(
        enabled: j['enabled'] == true,
        running: j['running'] == true,
        incomingFiles: _i(j['incoming_files']),
        failedFiles: _i(j['failed_files']),
      );
}

class ImportRunResult {
  final String? savedAs;
  final int exitCode;
  final bool timedOut;
  final List<String> output;
  const ImportRunResult({
    this.savedAs, required this.exitCode, required this.timedOut, required this.output,
  });
  factory ImportRunResult.fromJson(Map<String, dynamic> j) => ImportRunResult(
        savedAs: _s(j['saved_as']),
        exitCode: _i(j['exit_code']),
        timedOut: j['timed_out'] == true,
        output: ((j['output'] as List?) ?? []).map((e) => '$e').toList(),
      );
}

class ImportBatchDetail {
  final ImportBatch batch;
  final Map<String, int> processing;
  final List<Map<String, dynamic>> errors;
  const ImportBatchDetail({required this.batch, required this.processing, required this.errors});
}

class BiometricImportService {
  static BiometricApiException _map(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final msg = data is Map && data['message'] != null ? data['message'].toString() : null;
      final code = e.response?.statusCode;
      if (msg != null) return BiometricApiException(msg, statusCode: code);
      if (code == 403) {
        return const BiometricApiException('You do not have permission to import biometric files.', statusCode: 403);
      }
      return const BiometricApiException('Could not reach the server. Check your connection and try again.');
    }
    return const BiometricApiException('Unexpected error. Please try again.');
  }

  Future<({List<ImportBatch> batches, ConnectorStatus connector})> getBatches({int limit = 30}) async {
    try {
      final r = await ApiConfig.dio.get('/biometric/import-batches', queryParameters: {'limit': limit});
      final list = (r.data['data'] as List? ?? [])
          .map((e) => ImportBatch.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final connector = ConnectorStatus.fromJson(Map<String, dynamic>.from(r.data['connector'] as Map));
      return (batches: list, connector: connector);
    } catch (e) {
      throw _map(e);
    }
  }

  Future<ImportBatchDetail> getBatch(int id) async {
    try {
      final r = await ApiConfig.dio.get('/biometric/import-batches/$id');
      final d = Map<String, dynamic>.from(r.data['data'] as Map);
      final proc = Map<String, dynamic>.from(d['processing'] as Map? ?? {});
      return ImportBatchDetail(
        batch: ImportBatch.fromJson(Map<String, dynamic>.from(d['batch'] as Map)),
        processing: {for (final e in proc.entries) e.key: _i(e.value)},
        errors: (d['errors'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    } catch (e) {
      throw _map(e);
    }
  }

  Future<ImportRunResult> uploadAndImport(List<int> bytes, String fileName) async {
    try {
      final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName)});
      final r = await ApiConfig.dio.post(
        '/biometric/import-file',
        data: form,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 180),
        ),
      );
      return ImportRunResult.fromJson(Map<String, dynamic>.from(r.data['data'] as Map));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<ImportRunResult> runConnector() async {
    try {
      final r = await ApiConfig.dio.post(
        '/biometric/import-run',
        options: Options(receiveTimeout: const Duration(seconds: 180)),
      );
      return ImportRunResult.fromJson(Map<String, dynamic>.from(r.data['data'] as Map));
    } catch (e) {
      throw _map(e);
    }
  }
}