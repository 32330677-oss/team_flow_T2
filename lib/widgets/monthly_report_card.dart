import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../screens/payroll_export_service.dart';

/// Monthly hours & payroll Excel report card (used separately by the Worker
/// and Staff payroll pages — each passes its own endpoint).
///
/// The user picks a month + year, then optionally narrows the report to a
/// day range. The range picker is locked to the selected month: days before
/// the 1st and after the last day of that month are disabled.
class MonthlyReportCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String endpoint; // Excel, e.g. '/admin/payroll/monthly-report.xlsx'
  final String pdfEndpoint; // PDF,  e.g. '/admin/payroll/monthly-report.pdf'
  final String filePrefix; // e.g. 'labor_hours_payroll'

  const MonthlyReportCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.endpoint,
    required this.pdfEndpoint,
    required this.filePrefix,
  });

  @override
  State<MonthlyReportCard> createState() => _MonthlyReportCardState();
}

class _MonthlyReportCardState extends State<MonthlyReportCard> {
  static const Color _primary = Color(0xff1a2a6c);
  static const Color _soft = Color(0xffe8eef7);
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  late int _month;
  late int _year;
  late DateTimeRange _range;
  String? _busyFormat; // 'xlsx' | 'pdf' while a download is running
  bool get _busy => _busyFormat != null;
  String? _message;
  bool _isError = false;

  final _dayFmt = DateFormat('dd MMM yyyy');
  final _apiFmt = DateFormat('yyyy-MM-dd');

  DateTime get _monthStart => DateTime(_year, _month, 1);
  DateTime get _monthEnd => DateTime(_year, _month + 1, 0);
  int get _daysInMonth => _monthEnd.day;
  bool get _isFullMonth => _range.start.day == 1 && _range.end.day == _daysInMonth;
  int get _selectedDays => _range.end.difference(_range.start).inDays + 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
    _resetRange();
  }

  void _resetRange() => _range = DateTimeRange(start: _monthStart, end: _monthEnd);

  void _setMonthYear({int? month, int? year}) {
    setState(() {
      _month = month ?? _month;
      _year = year ?? _year;
      _resetRange(); // a new month always starts as the full month
      _message = null;
    });
  }

  void _setQuickRange(int fromDay, int toDay) {
    setState(() {
      _range = DateTimeRange(
        start: DateTime(_year, _month, fromDay),
        end: DateTime(_year, _month, toDay > _daysInMonth ? _daysInMonth : toDay),
      );
      _message = null;
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _monthStart, // locks everything before this month
      lastDate: _monthEnd, // locks everything after this month
      initialDateRange: _range,
      currentDate: _monthStart,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Select days in ${_months[_month - 1]} $_year',
      saveText: 'Apply',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: _primary,
                onPrimary: Colors.white,
                secondaryContainer: _soft,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _message = null;
      });
    }
  }

  Future<void> _generate(String format) async {
    final isPdf = format == 'pdf';
    setState(() {
      _busyFormat = format;
      _message = null;
    });
    try {
      final from = _apiFmt.format(_range.start);
      final to = _apiFmt.format(_range.end);
      final response = await ApiConfig.dio.get<List<int>>(
        isPdf ? widget.pdfEndpoint : widget.endpoint,
        queryParameters: {'month': _month, 'year': _year, 'from': from, 'to': to},
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('Empty report');
      final mm = _month.toString().padLeft(2, '0');
      final suffix = _isFullMonth ? '$_year-$mm' : '${from}_to_$to';
      await PayrollExportService.exportBytes(bytes, '${widget.filePrefix}_$suffix.$format');
      if (!mounted) return;
      setState(() {
        _isError = false;
        _message = isPdf
            ? 'PDF ready. Data flags (if any) are listed at the end of the report.'
            : 'Excel ready. Check the "Flags" sheet for any data issues.';
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
      if (mounted) setState(() => _busyFormat = null);
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: _primary),
        isDense: true,
        filled: true,
        fillColor: const Color(0xfff7f9fc),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
      );

  Widget _quickChip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: _busy ? null : (_) => onTap(),
        selectedColor: _primary,
        backgroundColor: _soft,
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : _primary,
        ),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );

  @override
  Widget build(BuildContext context) {
    final years = List.generate(DateTime.now().year - 2023 + 2, (i) => 2023 + i);
    final firstHalf = _range.start.day == 1 && _range.end.day == 15;
    final secondHalf = _range.start.day == 16 && _range.end.day == _daysInMonth;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _soft),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Header -------------------------------------------------
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.grid_on_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(widget.subtitle,
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.8))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Month / Year ---------------------------------------
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        value: _month,
                        decoration: _dec('Month', Icons.calendar_month_outlined),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i])),
                        ),
                        onChanged: _busy ? null : (v) => _setMonthYear(month: v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        value: _year,
                        decoration: _dec('Year', Icons.event_note_outlined),
                        items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                        onChanged: _busy ? null : (v) => _setMonthYear(year: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ---- Day range (locked to the month) --------------------
                Text('DAYS INCLUDED',
                    style: TextStyle(
                        fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _quickChip('Full month', _isFullMonth, () => _setQuickRange(1, _daysInMonth)),
                    _quickChip('1 – 15', firstHalf, () => _setQuickRange(1, 15)),
                    _quickChip('16 – $_daysInMonth', secondHalf, () => _setQuickRange(16, _daysInMonth)),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _busy ? null : _pickRange,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xfff7f9fc),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range_rounded, color: _primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('From  →  To',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              const SizedBox(height: 2),
                              Text(
                                '${_dayFmt.format(_range.start)}  →  ${_dayFmt.format(_range.end)}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primary),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(20)),
                          child: Text('$_selectedDays ${_selectedDays == 1 ? 'day' : 'days'}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _primary)),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.edit_calendar_outlined, size: 18, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Only days inside ${_months[_month - 1]} $_year can be selected.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 16),

                // ---- Actions: Excel + PDF --------------------------------
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : () => _generate('xlsx'),
                          icon: _busyFormat == 'xlsx'
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.table_view_rounded, color: Colors.white, size: 20),
                          label: Text(_busyFormat == 'xlsx' ? 'Generating...' : 'Excel Report',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            disabledBackgroundColor: _primary.withOpacity(0.55),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _generate('pdf'),
                          icon: _busyFormat == 'pdf'
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: _primary))
                              : const Icon(Icons.picture_as_pdf_rounded, color: Color(0xffc62828), size: 20),
                          label: Text(_busyFormat == 'pdf' ? 'Generating...' : 'Print PDF',
                              style: const TextStyle(color: _primary, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: _primary, width: 1.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isError ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _isError ? Colors.red.shade100 : Colors.green.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(_isError ? Icons.error_outline : Icons.check_circle_outline,
                            size: 18, color: _isError ? Colors.red.shade700 : Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_message!,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: _isError ? Colors.red.shade800 : Colors.green.shade800)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
