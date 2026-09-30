import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../screens/payroll_export_service.dart';

class MonthlyReportCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String endpoint; // e.g. '/admin/payroll/monthly-report.xlsx'
  final String filePrefix; // e.g. 'labor_hours_payroll'

  const MonthlyReportCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.endpoint,
    required this.filePrefix,
  });

  @override
  State<MonthlyReportCard> createState() => _MonthlyReportCardState();
}

class _MonthlyReportCardState extends State<MonthlyReportCard> {
  static const Color _primary = Color(0xff1a2a6c);
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  late int _month;
  late int _year;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await ApiConfig.dio.get<List<int>>(
        widget.endpoint,
        queryParameters: {'month': _month, 'year': _year},
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('Empty report');
      final mm = _month.toString().padLeft(2, '0');
      await PayrollExportService.exportBytes(bytes, '${widget.filePrefix}_$_year-$mm.xlsx');
      if (!mounted) return;
      setState(() {
        _isError = false;
        _message = 'Report ready. Check the "Flags" sheet for any data issues.';
      });
    } on DioException catch (e) {
      var msg = 'Failed to generate the report.';
      final raw = e.response?.data;
      if (raw is List<int>) {
        try {
          final decoded = jsonDecode(utf8.decode(raw));
          if (decoded is Map && decoded['message'] != null) msg = decoded['message'].toString();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _isError = true;
        _message = msg;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _message = 'Failed to generate the report.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = List.generate(DateTime.now().year - 2023 + 2, (i) => 2023 + i);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primary)),
          const SizedBox(height: 4),
          Text(widget.subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  value: _month,
                  decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder()),
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i])),
                  ),
                  onChanged: _busy ? null : (v) => setState(() => _month = v ?? _month),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: _year,
                  decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                  items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                  onChanged: _busy ? null : (v) => setState(() => _year = v ?? _year),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.table_view, color: Colors.white),
              label: Text(_busy ? 'Generating...' : 'Generate Excel Report',
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(_isError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18, color: _isError ? Colors.red : Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_message!,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: _isError ? Colors.red.shade800 : Colors.green.shade800)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}