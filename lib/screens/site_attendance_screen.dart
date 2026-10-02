import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:team_flow/constants.dart';

import '../widgets/help_tip.dart';
import 'rejected_records_screen.dart';

/// Supervisor daily attendance for ONE site + shift.
///
/// Redesigned (2026-10):
///  * one clear day header (previous / next day, calendar, Today) — future
///    dates cannot be opened;
///  * banners that explain WHY something is blocked (payroll locked, previous
///    week still in Draft, day already submitted);
///  * counters that double as filters, plus search;
///  * one card per worker with the next logical action as a button and the
///    rest in a menu; selection for bulk actions in a bottom bar;
///  * check-in time is always on the selected date; check-out / break end can
///    be on the next calendar day (night shift);
///  * a readiness line under the Submit button lists what is still missing.
class SiteAttendanceScreen extends StatefulWidget {
  final int siteId;
  final String siteName;
  final String shiftType; // 'Day' or 'Night'

  const SiteAttendanceScreen({
    super.key,
    required this.siteId,
    required this.siteName,
    this.shiftType = 'Day',
  });

  @override
  State<SiteAttendanceScreen> createState() => _SiteAttendanceScreenState();
}

enum _Filter { all, notRecorded, working, onBreak, checkedOut, leave, submitted, rejected, flagged }

class _SiteAttendanceScreenState extends State<SiteAttendanceScreen> {
  static const Color _primary = Color(0xff1a2a6c);

  bool _initialLoading = true;
  bool _busy = false;
  String? _loadError;
  late String _recordDate;
  String _businessToday = DateFormat('yyyy-MM-dd').format(DateTime.now());

  List<Map<String, dynamic>> _workers = [];
  Map<String, dynamic> _day = {};
  final Set<int> _selected = <int>{};
  _Filter _filter = _Filter.all;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  // Lunch (bulk) state
  TimeOfDay? _lunchStart;
  TimeOfDay? _lunchEnd;
  final Map<int, Map<String, TimeOfDay>> _lunchOverrides = {};
  final Set<int> _lunchExcluded = <int>{};

  @override
  void initState() {
    super.initState();
    _recordDate = _businessToday;
    _load(initial: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  int _id(Map w) => int.tryParse(w['worker_id'].toString()) ?? 0;

  Future<void> _load({bool initial = false}) async {
    if (!mounted) return;
    setState(() {
      if (initial) _initialLoading = true;
      _busy = !initial;
      _loadError = null;
    });
    try {
      final res = await ApiConfig.dio.get(
        '/attendance/sites/${widget.siteId}/workers',
        queryParameters: {'record_date': _recordDate, 'shift_type': widget.shiftType},
      );
      final data = res.data is Map ? res.data as Map : <String, dynamic>{};
      final list = (data['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _workers = list;
        _day = data['day'] is Map ? Map<String, dynamic>.from(data['day'] as Map) : <String, dynamic>{};
        final today = _day['business_today']?.toString();
        if (today != null && today.length == 10) _businessToday = today;
        _selected.removeWhere((id) => !_workers.any((w) => _id(w) == id));
        _lunchOverrides.clear();
        _lunchExcluded.clear();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = _msg(e, 'Failed to load workers.'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'Failed to load workers.');
    } finally {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _busy = false;
        });
      }
    }
  }

  String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
      if (e.response == null) return 'Connection error. Check your network.';
    }
    return fallback;
  }

  void _toast(String message, {Color color = Colors.green}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  /// Runs one API call with a non-blocking progress bar, then reloads.
  Future<bool> _run(Future<Response<dynamic>> Function() call, {String? success}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final res = await call();
      final data = res.data;
      final serverMsg = data is Map && data['message'] != null ? data['message'].toString() : null;
      await _load();
      final flagged = serverMsg != null && serverMsg.contains('Flagged for review');
      _toast(flagged ? serverMsg : (success ?? serverMsg ?? 'Saved.'),
          color: flagged ? Colors.orange.shade800 : Colors.green);
      return true;
    } on DioException catch (e) {
      if (mounted) setState(() => _busy = false);
      final d = e.response?.data;
      final code = d is Map ? d['code']?.toString() : null;
      if (code == 'PREVIOUS_WEEK_UNSUBMITTED' || code == 'PAYROLL_PERIOD_FINALIZED') {
        await _load();
      }
      _toast(_msg(e, 'Action failed. Nothing was saved.'), color: Colors.red.shade700);
      return false;
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _toast('Action failed. Nothing was saved.', color: Colors.red.shade700);
      return false;
    }
  }

  Map<String, dynamic> _base(int workerId) => {
        'worker_id': workerId,
        'site_id': widget.siteId,
        'record_date': _recordDate,
        'shift_type': widget.shiftType,
      };

  // ------------------------------------------------------------ state helpers

  bool get _locked => _day['payroll_locked'] == true;
  List get _prevWeekDrafts => (_day['previous_week_drafts'] as List?) ?? const [];

  String? _workflow(Map w) => w['workflow_status']?.toString();
  bool _isDraftOrNone(Map w) => _workflow(w) == null || _workflow(w) == 'Draft';
  bool _hasIn(Map w) => w['check_in_time'] != null;
  bool _hasOut(Map w) => w['check_out_time'] != null;
  bool _onBreak(Map w) => w['current_leave_id'] != null;
  bool _isLeave(Map w) {
    final s = w['attendance_status']?.toString();
    return w['attendance_id'] != null && s != null && s != 'Present';
  }

  /// Record that belongs to the previous calendar day (night shift still open).
  bool _isCarryOver(Map w) {
    final d = w['attendance_record_date']?.toString();
    return d != null && d != _recordDate;
  }

  _Filter _categoryOf(Map w) {
    final wf = _workflow(w);
    if (wf == 'Rejected') return _Filter.rejected;
    if (wf == 'Submitted' || wf == 'Approved') return _Filter.submitted;
    if (w['attendance_id'] == null) return _Filter.notRecorded;
    if (_isLeave(w)) return _Filter.leave;
    if (_onBreak(w)) return _Filter.onBreak;
    if (_hasIn(w) && !_hasOut(w)) return _Filter.working;
    return _Filter.checkedOut;
  }

  int _count(_Filter f) {
    if (f == _Filter.all) return _workers.length;
    if (f == _Filter.flagged) return _workers.where((w) => w['anomaly_code'] != null).length;
    return _workers.where((w) => _categoryOf(w) == f).length;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _workers.where((w) {
      if (_filter == _Filter.flagged && w['anomaly_code'] == null) return false;
      if (_filter != _Filter.all && _filter != _Filter.flagged && _categoryOf(w) != _filter) return false;
      if (q.isEmpty) return true;
      final name = (w['full_name'] ?? '').toString().toLowerCase();
      final uid = (w['worker_unique_id'] ?? '').toString().toLowerCase();
      return name.contains(q) || uid.contains(q);
    }).toList();
  }

  bool _canCheckIn(Map w) => !_locked && _isDraftOrNone(w) && w['attendance_id'] == null;
  bool _canCheckOut(Map w) => !_locked && _workflow(w) == 'Draft' && _hasIn(w) && !_hasOut(w) && !_onBreak(w);
  bool _canSetStatus(Map w) => !_locked && _isDraftOrNone(w) && !_hasIn(w) && !_hasOut(w) && !_isCarryOver(w);
  bool _canBreak(Map w) => !_locked && _workflow(w) == 'Draft' && _hasIn(w) && !_hasOut(w);
  bool _canEditTimes(Map w) => !_locked && _workflow(w) == 'Draft' && _hasIn(w);

  // Readiness for "Submit day" (the backend re-checks everything).
  List<String> get _blockers {
    final out = <String>[];
    if (_locked) out.add('payroll period locked');
    if (_day['is_future'] == true) out.add('future date');
    if (_prevWeekDrafts.isNotEmpty) out.add('previous week has Draft days');
    final notRecorded = _workers.where((w) => w['attendance_id'] == null && w['active_on_date'] != false).length;
    if (notRecorded > 0) out.add('$notRecorded not recorded');
    final open = _workers.where((w) => _workflow(w) == 'Draft' && _hasIn(w) && !_hasOut(w)).length;
    if (open > 0) out.add('$open still checked in');
    final breaks = _workers.where((w) => _workflow(w) == 'Draft' && _onBreak(w)).length;
    if (breaks > 0) out.add('$breaks on break');
    return out;
  }

  bool get _hasDraftToSubmit => _workers.any((w) => _workflow(w) == 'Draft');
  bool get _allSubmitted =>
      _workers.isNotEmpty && _workers.every((w) => _workflow(w) == 'Submitted' || _workflow(w) == 'Approved');

  // ------------------------------------------------------------- pickers

  DateTime get _dateObj => DateTime.parse(_recordDate);

  String _fmt(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  String _hm(dynamic value) {
    if (value == null) return '--:--';
    final m = RegExp(r'(?:T| )(\d{2}:\d{2})').firstMatch(value.toString());
    return m?.group(1) ?? value.toString();
  }

  String _dayLabel(dynamic value) {
    if (value == null) return '';
    final s = value.toString().replaceFirst('T', ' ');
    if (s.length < 10) return '';
    final d = s.substring(0, 10);
    return d == _recordDate ? '' : ' (${DateFormat('d MMM').format(DateTime.parse(d))})';
  }

  /// Time on the selected attendance date (check-in, bulk check-in).
  Future<String?> _pickTimeOnRecordDate(String help, {TimeOfDay? initial}) async {
    final t = await showTimePicker(context: context, initialTime: initial ?? TimeOfDay.now(), helpText: help);
    if (t == null) return null;
    final d = _dateObj;
    return _fmt(DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  /// Time on the attendance date OR the next day (night shift check-out / break end).
  Future<String?> _pickTimeSameOrNextDay(String help, {DateTime? base}) async {
    final start = base ?? _dateObj;
    final startDay = DateTime(start.year, start.month, start.day);
    final nextDay = startDay.add(const Duration(days: 1));
    DateTime chosenDay = startDay;
    if (widget.shiftType == 'Night' || base != null) {
      final picked = await showDialog<DateTime>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(help),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, startDay),
              child: ListTile(
                leading: const Icon(Icons.today_rounded),
                title: Text('Same day — ${DateFormat('EEE d MMM').format(startDay)}'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, nextDay),
              child: ListTile(
                leading: const Icon(Icons.nights_stay_rounded),
                title: Text('Next day — ${DateFormat('EEE d MMM').format(nextDay)}'),
                subtitle: const Text('Night shift that ends after midnight'),
              ),
            ),
          ],
        ),
      );
      if (picked == null) return null;
      chosenDay = picked;
    }
    if (!mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now(), helpText: help);
    if (t == null) return null;
    return _fmt(DateTime(chosenDay.year, chosenDay.month, chosenDay.day, t.hour, t.minute));
  }

  DateTime? _parse(dynamic v) => v == null ? null : DateTime.tryParse(v.toString().replaceFirst(' ', 'T'));

  // ------------------------------------------------------------- actions

  Future<void> _changeDate(DateTime d) async {
    final today = DateTime.parse(_businessToday);
    if (d.isAfter(today)) {
      _toast('Future dates cannot be recorded.', color: Colors.orange.shade800);
      return;
    }
    setState(() {
      _recordDate = DateFormat('yyyy-MM-dd').format(d);
      _selected.clear();
    });
    await _load();
  }

  Future<void> _pickDate() async {
    final today = DateTime.parse(_businessToday);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateObj.isAfter(today) ? today : _dateObj,
      firstDate: DateTime(2024),
      lastDate: today,
      helpText: 'Attendance date',
    );
    if (picked != null) await _changeDate(picked);
  }

  Future<void> _checkIn(Map w) async {
    final t = await _pickTimeOnRecordDate('Check-in time — ${w['full_name']}');
    if (t == null) return;
    await _run(() => ApiConfig.dio.post('/attendance/checkin', data: {..._base(_id(w)), 'check_in_time': t}),
        success: 'Checked in.');
  }

  Future<void> _checkOut(Map w) async {
    final t = await _pickTimeSameOrNextDay('Check-out — ${w['full_name']}', base: _parse(w['check_in_time']));
    if (t == null) return;
    final recordDate = w['attendance_record_date']?.toString() ?? _recordDate;
    await _run(() => ApiConfig.dio.post('/attendance/checkout', data: {
          ..._base(_id(w)),
          'record_date': recordDate,
          'check_out_time': t,
        }));
  }

  Future<void> _setStatus(Map w) async {
    final status = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Status — ${w['full_name']}'),
        children: [
          _statusOption(ctx, 'Absent', 'Absent', Icons.person_off_rounded, Colors.red),
          _statusOption(ctx, 'Sick', 'Sick leave', Icons.sick_rounded, Colors.orange),
          _statusOption(ctx, 'Vacation', 'Annual leave', Icons.beach_access_rounded, Colors.blue),
          _statusOption(ctx, 'Holiday', 'Holiday', Icons.event_rounded, Colors.purple),
        ],
      ),
    );
    if (status == null) return;
    await _run(() => ApiConfig.dio.post('/attendance/status', data: {
          ..._base(_id(w)),
          'attendance_status': status,
          'remarks': '$status - recorded by supervisor',
        }), success: 'Status saved.');
  }

  Widget _statusOption(BuildContext ctx, String value, String label, IconData icon, Color color) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Row(children: [Icon(icon, color: color), const SizedBox(width: 12), Text(label, style: const TextStyle(fontSize: 15))]),
    );
  }

  Future<void> _toggleBreak(Map w) async {
    final recordDate = w['attendance_record_date']?.toString() ?? _recordDate;
    if (_onBreak(w)) {
      final t = await _pickTimeSameOrNextDay('Break end — ${w['full_name']}', base: _parse(w['check_in_time']));
      if (t == null) return;
      await _run(() => ApiConfig.dio.post('/attendance/leave/end',
          data: {..._base(_id(w)), 'record_date': recordDate, 'leave_end_time': t}), success: 'Break ended.');
      return;
    }
    final type = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          const ListTile(title: Text('Start a break', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.free_breakfast_rounded, color: Colors.blue),
            title: const Text('Rest break'),
            subtitle: const Text('Always deducted from working hours'),
            onTap: () => Navigator.pop(ctx, 'Rest'),
          ),
          ListTile(
            leading: const Icon(Icons.lunch_dining_rounded, color: Colors.purple),
            title: const Text('Lunch break'),
            subtitle: const Text('Deducted unless lunch is paid (Attendance Settings)'),
            onTap: () => Navigator.pop(ctx, 'Lunch'),
          ),
        ]),
      ),
    );
    if (type == null) return;
    final t = await _pickTimeSameOrNextDay('Break start — ${w['full_name']}', base: _parse(w['check_in_time']));
    if (t == null) return;
    await _run(() => ApiConfig.dio.post('/attendance/leave/start',
        data: {..._base(_id(w)), 'record_date': recordDate, 'leave_type': type, 'leave_start_time': t}),
        success: 'Break started.');
  }

  Future<void> _editTimes(Map w) async {
    DateTime? newIn = _parse(w['check_in_time']);
    DateTime? newOut = _parse(w['check_out_time']);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit times — ${w['full_name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.login_rounded),
              title: const Text('Check-in'),
              subtitle: Text(newIn == null ? 'Not set' : DateFormat('EEE d MMM, HH:mm').format(newIn!)),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () async {
                final t = await showTimePicker(
                    context: ctx, initialTime: newIn != null ? TimeOfDay.fromDateTime(newIn!) : TimeOfDay.now());
                if (t != null) {
                  final base = newIn ?? _dateObj;
                  setD(() => newIn = DateTime(base.year, base.month, base.day, t.hour, t.minute));
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Check-out'),
              subtitle: Text(newOut == null ? 'Not set' : DateFormat('EEE d MMM, HH:mm').format(newOut!)),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () async {
                final s = await _pickTimeSameOrNextDay('Check-out', base: newIn);
                if (s != null) setD(() => newOut = DateTime.parse(s.replaceFirst(' ', 'T')));
              },
            ),
            const SizedBox(height: 6),
            Text('The check-in stays on the attendance date. A night-shift check-out may be on the next day.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result != true) return;
    final payload = <String, dynamic>{'shift_type': widget.shiftType};
    if (newIn != null) payload['check_in_time'] = _fmt(newIn!);
    if (newOut != null) payload['check_out_time'] = _fmt(newOut!);
    await _run(() => ApiConfig.dio.patch('/attendance/${w['attendance_id']}/edit-times', data: payload),
        success: 'Times updated.');
  }

  // ------------------------------------------------------------- bulk

  List<int> _eligible(bool Function(Map) test) =>
      _workers.where((w) => _selected.contains(_id(w)) && test(w)).map(_id).toList();

  Future<void> _bulkCheckIn() async {
    final ids = _eligible(_canCheckIn);
    if (ids.isEmpty) return _toast('None of the selected workers can be checked in.', color: Colors.orange.shade800);
    final t = await _pickTimeOnRecordDate('Check-in time for ${ids.length} worker(s)');
    if (t == null) return;
    final ok = await _run(() => ApiConfig.dio.post('/attendance/bulk/checkin', data: {
          'site_id': widget.siteId, 'shift_type': widget.shiftType, 'record_date': _recordDate,
          'worker_ids': ids, 'check_in_time': t,
        }), success: '${ids.length} worker(s) checked in.');
    if (ok) setState(_selected.clear);
  }

  Future<void> _bulkCheckOut() async {
    final ids = _eligible(_canCheckOut);
    if (ids.isEmpty) return _toast('None of the selected workers has an open shift.', color: Colors.orange.shade800);
    final t = await _pickTimeSameOrNextDay('Check-out time for ${ids.length} worker(s)');
    if (t == null) return;
    final ok = await _run(() => ApiConfig.dio.post('/attendance/bulk/checkout', data: {
          'site_id': widget.siteId, 'shift_type': widget.shiftType, 'record_date': _recordDate,
          'worker_ids': ids, 'check_out_time': t,
        }), success: '${ids.length} worker(s) checked out.');
    if (ok) setState(_selected.clear);
  }

  Future<void> _bulkAbsent() async {
    final ids = _eligible(_canSetStatus);
    if (ids.isEmpty) return _toast('Only workers without clock activity can be marked absent.', color: Colors.orange.shade800);
    final names = _workers.where((w) => ids.contains(_id(w))).map((w) => w['full_name'].toString()).toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark absent?'),
        content: SingleChildScrollView(
          child: Text('${ids.length} worker(s) will be marked ABSENT on ${DateFormat('EEE d MMM yyyy').format(_dateObj)}:\n\n• ${names.join('\n• ')}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark absent'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _run(() => ApiConfig.dio.post('/attendance/bulk/status', data: {
          'site_id': widget.siteId, 'shift_type': widget.shiftType, 'record_date': _recordDate,
          'worker_ids': ids, 'attendance_status': 'Absent',
        }), success: '${ids.length} worker(s) marked absent.');
    if (ok) setState(_selected.clear);
  }

  // ------------------------------------------------------------- lunch

  List<Map<String, dynamic>> get _lunchEligible =>
      _workers.where((w) => _workflow(w) == 'Draft' && _hasIn(w) && _hasOut(w)).toList();

  String _t(TimeOfDay? t) =>
      t == null ? '--:--' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _saveLunch() async {
    final eligible = _lunchEligible.map(_id).toSet();
    final included = eligible.difference(_lunchExcluded);
    if (included.isEmpty) return _toast('Every worker is excluded — nothing to save.', color: Colors.orange.shade800);
    final hasDefault = _lunchStart != null && _lunchEnd != null;
    if (!hasDefault && included.any((id) => _lunchOverrides[id] == null)) {
      return _toast('Set the default lunch time, or a custom time for every included worker.', color: Colors.orange.shade800);
    }
    final overrides = <String, dynamic>{};
    _lunchOverrides.forEach((id, v) {
      overrides['$id'] = {'start_time': _t(v['start']), 'end_time': _t(v['end'])};
    });
    await _run(() => ApiConfig.dio.post('/attendance/lunch/bulk', data: {
          'siteId': widget.siteId,
          'shift_type': widget.shiftType,
          'date': _recordDate,
          'default_start_time': hasDefault ? _t(_lunchStart) : null,
          'default_end_time': hasDefault ? _t(_lunchEnd) : null,
          'overrides': overrides,
          'excluded_worker_ids': _lunchExcluded.toList(),
        }));
  }

  // ------------------------------------------------------------- submit

  Future<void> _submitDay({List<Map<String, dynamic>>? lunchSkips}) async {
    if (lunchSkips == null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Submit the day for review?'),
          content: Text(
              'All Draft records of ${widget.siteName} (${widget.shiftType}) on ${DateFormat('EEE d MMM yyyy').format(_dateObj)} '
              'will be sent to the Admin. After submitting you can no longer change them; the Admin approves or rejects them.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() => _busy = true);
    try {
      final res = await ApiConfig.dio.post('/attendance/submit', data: {
        'siteId': widget.siteId,
        'shift_type': widget.shiftType,
        'record_date': _recordDate,
        if (lunchSkips != null) 'lunch_decisions': lunchSkips,
      });
      final data = res.data is Map ? res.data as Map : <String, dynamic>{};
      if (data['requires_confirmation'] == true) {
        setState(() => _busy = false);
        final missing = (data['missing_workers'] as List? ?? []).whereType<Map>().toList();
        final skips = await _askLunchReasons(missing);
        if (skips != null) await _submitDay(lunchSkips: skips);
        return;
      }
      await _load();
      _toast('Day submitted: ${data['submitted_records'] ?? 0} record(s) sent for review.');
    } on DioException catch (e) {
      setState(() => _busy = false);
      final d = e.response?.data;
      if (d is Map && d['code'] == 'MISSING_ATTENDANCE_RECORDS') {
        final names = (d['missing_workers'] as List? ?? []).whereType<Map>().map((m) => m['full_name']).join(', ');
        await HelpTip.show(context, 'Attendance is incomplete',
            'Record Present (check-in/out), Absent, Sick, Vacation or Holiday for every assigned worker first:\n\n$names');
        setState(() => _filter = _Filter.notRecorded);
        return;
      }
      if (d is Map && d['open_workers'] is List) {
        final names = (d['open_workers'] as List).whereType<Map>().map((m) => m['full_name']).join(', ');
        await HelpTip.show(context, 'Shifts still open', '${d['message']}\n\n$names');
        return;
      }
      await _load();
      _toast(_msg(e, 'Submission failed.'), color: Colors.red.shade700);
    }
  }

  Future<List<Map<String, dynamic>>?> _askLunchReasons(List<Map> missing) async {
    final decisions = <dynamic, bool>{};
    final reasons = {for (final m in missing) m['attendance_id']: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('No lunch recorded'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('For each worker: did they work through lunch? If yes, give a reason (it becomes overtime). '
                    'If not, the site lunch period is deducted.', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                ...missing.map((m) {
                  final id = m['attendance_id'];
                  final worked = decisions[id] ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Row(children: [
                        ChoiceChip(
                          label: const Text('Did not work lunch'),
                          selected: !worked,
                          onSelected: (_) => setD(() => decisions[id] = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Worked through lunch'),
                          selected: worked,
                          onSelected: (_) => setD(() => decisions[id] = true),
                        ),
                      ]),
                      if (worked)
                        TextField(
                          controller: reasons[id],
                          decoration: const InputDecoration(labelText: 'Reason (required)', isDense: true),
                        ),
                    ]),
                  );
                }),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm & submit')),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    final result = <Map<String, dynamic>>[];
    for (final m in missing) {
      final id = m['attendance_id'];
      final worked = decisions[id] ?? false;
      final reason = reasons[id]!.text.trim();
      if (worked && reason.isEmpty) {
        _toast('A reason is required for ${m['full_name']}.', color: Colors.orange.shade800);
        return null;
      }
      result.add({'attendance_id': id, 'worked_through_lunch': worked, 'reason': reason});
    }
    // Sent as lunch_decisions: each item says explicitly whether the worker
    // worked through lunch (true) or took it (false). confirmed_lunch_skips
    // would treat every item that has a reason as "worked through".
    return result;
  }

  // ------------------------------------------------------------- transfer

  Future<void> _transfer(Map w) async {
    List sites = [];
    try {
      final res = await ApiConfig.dio.get('/sites/all-sites');
      sites = res.data is Map ? (res.data['data'] as List? ?? []) : (res.data as List? ?? []);
    } catch (e) {
      return _toast('Failed to load sites.', color: Colors.red.shade700);
    }
    if (!mounted) return;
    Map? target;
    String targetShift = 'Day';
    DateTime effective = DateTime.parse(_businessToday);
    final reason = TextEditingController();
    bool sending = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setS) {
          final supportsShifts = target != null && (target!['supports_shifts'] == 1 || target!['supports_shifts'] == true);
          final sameAsCurrent = target != null &&
              int.tryParse(target!['site_id'].toString()) == widget.siteId &&
              targetShift == widget.shiftType;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(sheet).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('Transfer request — ${w['full_name']}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primary)),
                const SizedBox(height: 4),
                Text('From ${widget.siteName} (${widget.shiftType}). The Admin approves the request.',
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                DropdownButtonFormField<Map>(
                  value: target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Target site', border: OutlineInputBorder()),
                  items: sites
                      .whereType<Map>()
                      .map((s) => DropdownMenuItem<Map>(value: s, child: Text(s['site_name'].toString())))
                      .toList(),
                  onChanged: (v) => setS(() {
                    target = v;
                    final shifts = v != null && (v['supports_shifts'] == 1 || v['supports_shifts'] == true);
                    if (!shifts) targetShift = 'Day';
                  }),
                ),
                if (supportsShifts) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Day', label: Text('Day shift'), icon: Icon(Icons.wb_sunny_rounded)),
                      ButtonSegment(value: 'Night', label: Text('Night shift'), icon: Icon(Icons.nights_stay_rounded)),
                    ],
                    selected: {targetShift},
                    onSelectionChanged: (s) => setS(() => targetShift = s.first),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('First day at the new site'),
                  subtitle: Text('${DateFormat('EEE d MMM yyyy').format(effective)} — the last day here is the day before'),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final d = await showDatePicker(
                        context: sheet, initialDate: effective, firstDate: DateTime(2024), lastDate: DateTime(2100));
                    if (d != null) setS(() => effective = d);
                  },
                ),
                TextField(
                  controller: reason,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
                ),
                if (sameAsCurrent)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('The target is the current site and shift.', style: TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: (target == null || sameAsCurrent || sending)
                      ? null
                      : () async {
                          if (reason.text.trim().length < 3) {
                            _toast('Please enter a reason.', color: Colors.orange.shade800);
                            return;
                          }
                          setS(() => sending = true);
                          try {
                            await ApiConfig.dio.post('/transfers', data: {
                              'worker_id': _id(w),
                              'current_site_id': widget.siteId,
                              'current_shift_type': widget.shiftType,
                              'target_site_id': target!['site_id'],
                              'target_shift_type': targetShift,
                              'effective_date': DateFormat('yyyy-MM-dd').format(effective),
                              'transfer_reason': reason.text.trim(),
                            });
                            if (sheet.mounted) Navigator.pop(sheet);
                            _toast('Transfer request sent to the Admin.');
                          } on DioException catch (e) {
                            setS(() => sending = false);
                            _toast(_msg(e, 'Failed to send the request.'), color: Colors.red.shade700);
                          }
                        },
                  icon: const Icon(Icons.send_rounded),
                  label: Text(sending ? 'Sending...' : 'Send transfer request'),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f6fa),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.siteName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('${widget.shiftType} shift — daily attendance', style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          IconButton(
            tooltip: 'How this page works',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => HelpTip.show(context, 'Daily attendance',
                '${HelpTexts.workflow}\n\n${HelpTexts.futureDates}\n\n${HelpTexts.previousWeek}'),
          ),
          IconButton(
            tooltip: 'Rejected records',
            icon: const Icon(Icons.assignment_late_rounded, color: Colors.amberAccent),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const RejectedRecordsScreen()));
              _load();
            },
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _busy ? null : () => _load()),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _busy
              ? const LinearProgressIndicator(minHeight: 3, color: Colors.amberAccent, backgroundColor: Colors.transparent)
              : const SizedBox(height: 3),
        ),
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _loadError != null && _workers.isEmpty
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      _dayHeader(),
                      ..._banners(),
                      const SizedBox(height: 8),
                      _filterChips(),
                      const SizedBox(height: 8),
                      _searchField(),
                      const SizedBox(height: 10),
                      _workerGrid(),
                      const SizedBox(height: 12),
                      if (_lunchEligible.isNotEmpty) _lunchCard(),
                    ],
                  ),
                ),
      bottomNavigationBar: _initialLoading ? null : _bottomBar(),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(_loadError ?? 'Failed to load.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: () => _load(initial: true), icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ]),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14), Color? color}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe5e7eb)),
      ),
      child: child,
    );
  }

  Widget _dayHeader() {
    final today = DateTime.parse(_businessToday);
    final isToday = _recordDate == _businessToday;
    final canNext = _dateObj.isBefore(today);
    return _card(
      child: Row(children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: _busy ? null : () => _changeDate(_dateObj.subtract(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _busy ? null : _pickDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                Text(DateFormat('EEEE').format(_dateObj),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(DateFormat('d MMMM yyyy').format(_dateObj),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _primary)),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_calendar_rounded, size: 16, color: _primary),
                ]),
                if (_day['week_start'] != null)
                  Text('Week ${_short(_day['week_start'])} – ${_short(_day['week_end'])}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
          ),
        ),
        if (!isToday)
          TextButton(onPressed: _busy ? null : () => _changeDate(today), child: const Text('Today')),
        IconButton(
          tooltip: canNext ? 'Next day' : 'Future dates cannot be recorded',
          onPressed: (_busy || !canNext) ? null : () => _changeDate(_dateObj.add(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
    );
  }

  String _short(dynamic d) {
    final s = d?.toString();
    if (s == null || s.length < 10) return '';
    return DateFormat('d MMM').format(DateTime.parse(s.substring(0, 10)));
  }

  List<Widget> _banners() {
    final list = <Widget>[];
    if (_locked) {
      list.add(_banner(
        icon: Icons.lock_rounded,
        color: Colors.red.shade700,
        text: 'Payroll for this date is finalized (batch #${_day['payroll_lock_batch_id']}). Attendance is read-only.',
        help: HelpTexts.payrollLocked,
      ));
    }
    if (_prevWeekDrafts.isNotEmpty) {
      final days = _prevWeekDrafts.whereType<Map>().toList();
      list.add(_card(
        color: Colors.amber.shade50,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Last week still has Draft attendance. Submit it before submitting this day.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const HelpTip(title: 'Previous week rule', message: HelpTexts.previousWeek),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: days.map((d) {
              final date = d['record_date'].toString();
              return ActionChip(
                avatar: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text('${DateFormat('EEE d MMM').format(DateTime.parse(date))} · ${d['drafts']} draft'),
                onPressed: () => _changeDate(DateTime.parse(date)),
              );
            }).toList(),
          ),
        ]),
      ));
    }
    if (_allSubmitted) {
      list.add(_banner(
        icon: Icons.verified_rounded,
        color: Colors.indigo,
        text: 'This day has been submitted. The Admin will approve or reject the records.',
        help: HelpTexts.workflow,
      ));
    }
    return list
        .map((w) => Padding(padding: const EdgeInsets.only(top: 8), child: w))
        .toList();
  }

  Widget _banner({required IconData icon, required Color color, required String text, String? help}) {
    return _card(
      color: color.withOpacity(0.07),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        if (help != null) HelpTip(title: 'Why?', message: help, color: color),
      ]),
    );
  }

  Widget _filterChips() {
    final defs = <(_Filter, String, IconData, Color)>[
      (_Filter.all, 'All', Icons.groups_rounded, _primary),
      (_Filter.notRecorded, 'Not recorded', Icons.radio_button_unchecked_rounded, Colors.grey.shade700),
      (_Filter.working, 'Working', Icons.play_circle_fill_rounded, Colors.green.shade700),
      (_Filter.onBreak, 'On break', Icons.coffee_rounded, Colors.orange.shade800),
      (_Filter.checkedOut, 'Checked out', Icons.check_circle_rounded, Colors.blue.shade700),
      (_Filter.leave, 'Absent / leave', Icons.event_busy_rounded, Colors.purple),
      (_Filter.submitted, 'Submitted', Icons.send_rounded, Colors.indigo),
      (_Filter.rejected, 'Rejected', Icons.assignment_late_rounded, Colors.red.shade700),
      (_Filter.flagged, 'Flagged', Icons.report_rounded, Colors.deepOrange),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: defs.where((d) => d.$1 == _Filter.all || _count(d.$1) > 0).map((d) {
          final selected = _filter == d.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(d.$3, size: 16, color: selected ? Colors.white : d.$4),
              label: Text('${d.$2}  ${_count(d.$1)}'),
              labelStyle: TextStyle(color: selected ? Colors.white : d.$4, fontWeight: FontWeight.w600),
              selectedColor: d.$4,
              backgroundColor: Colors.white,
              side: BorderSide(color: d.$4.withOpacity(0.35)),
              onSelected: (_) => setState(() => _filter = selected ? _Filter.all : d.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _searchField() {
    final visibleIds = _visible.map(_id).toSet();
    final allVisibleSelected = visibleIds.isNotEmpty && visibleIds.every(_selected.contains);
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search name or worker ID',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    }),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: allVisibleSelected ? 'Clear selection' : 'Select all shown',
        child: OutlinedButton.icon(
          onPressed: _locked || visibleIds.isEmpty
              ? null
              : () => setState(() {
                    if (allVisibleSelected) {
                      _selected.removeAll(visibleIds);
                    } else {
                      _selected.addAll(visibleIds);
                    }
                  }),
          icon: Icon(allVisibleSelected ? Icons.deselect_rounded : Icons.select_all_rounded, size: 18),
          label: Text(allVisibleSelected ? 'Clear' : 'Select'),
        ),
      ),
    ]);
  }

  Widget _workerGrid() {
    final list = _visible;
    if (list.isEmpty) {
      return _card(
        child: SizedBox(
          height: 160,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.person_search_rounded, size: 46, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                _workers.isEmpty
                    ? 'No workers are assigned to this site and shift on this date.'
                    : 'No worker matches the current filter / search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ]),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 700 ? 2 : 1);
      const gap = 10.0;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: list.map((w) => SizedBox(width: width, child: _workerCard(w))).toList(),
      );
    });
  }

  (String, Color, IconData) _stateOf(Map w) {
    final wf = _workflow(w);
    final s = w['attendance_status']?.toString();
    if (w['attendance_id'] == null) return ('Not recorded', Colors.grey.shade600, Icons.radio_button_unchecked_rounded);
    if (s == 'Absent') return ('Absent', Colors.red.shade700, Icons.person_off_rounded);
    if (s == 'Sick') return ('Sick leave', Colors.orange.shade800, Icons.sick_rounded);
    if (s == 'Vacation') return ('Annual leave', Colors.blue.shade700, Icons.beach_access_rounded);
    if (s == 'Holiday') return ('Holiday', Colors.purple, Icons.event_rounded);
    if (_onBreak(w)) {
      return ('On ${(w['current_leave_type'] ?? 'break').toString().toLowerCase()} break', Colors.orange.shade800, Icons.coffee_rounded);
    }
    if (_hasIn(w) && !_hasOut(w)) return ('Working', Colors.green.shade700, Icons.play_circle_fill_rounded);
    if (wf == null) return ('Not recorded', Colors.grey.shade600, Icons.radio_button_unchecked_rounded);
    return ('Checked out', Colors.blue.shade700, Icons.check_circle_rounded);
  }

  Widget _workerCard(Map<String, dynamic> w) {
    final id = _id(w);
    final name = (w['full_name'] ?? 'Worker').toString();
    final initials = name.trim().isEmpty ? 'W' : name.trim().substring(0, 1).toUpperCase();
    final (label, color, icon) = _stateOf(w);
    final wf = _workflow(w);
    final selected = _selected.contains(id);
    final hours = w['total_working_hours'] != null
        ? (double.tryParse(w['total_working_hours'].toString()) ?? 0) + (double.tryParse((w['overtime_hours'] ?? '0').toString()) ?? 0)
        : null;
    final selectable = !_locked && (_canCheckIn(w) || _canCheckOut(w) || _canSetStatus(w));

    Widget? primary;
    if (_canCheckIn(w)) {
      primary = Row(children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: _busy ? null : () => _checkIn(w),
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Check in'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy || !_canSetStatus(w) ? null : () => _setStatus(w),
            icon: const Icon(Icons.event_busy_rounded, size: 18),
            label: const Text('Absent / leave'),
          ),
        ),
      ]);
    } else if (_canCheckOut(w)) {
      primary = Row(children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _primary),
            onPressed: _busy ? null : () => _checkOut(w),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Check out'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _toggleBreak(w),
            icon: const Icon(Icons.coffee_rounded, size: 18),
            label: const Text('Start break'),
          ),
        ),
      ]);
    } else if (_canBreak(w) && _onBreak(w)) {
      primary = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
          onPressed: _busy ? null : () => _toggleBreak(w),
          icon: const Icon(Icons.timer_off_rounded, size: 18),
          label: const Text('End break'),
        ),
      );
    }

    final menu = <PopupMenuEntry<String>>[
      if (_canEditTimes(w)) const PopupMenuItem(value: 'times', child: Text('Edit check-in / check-out')),
      if (_canSetStatus(w) && w['attendance_id'] != null) const PopupMenuItem(value: 'status', child: Text('Change status')),
      if (_canBreak(w) && !_onBreak(w) && !_canCheckOut(w)) const PopupMenuItem(value: 'break', child: Text('Start break')),
      const PopupMenuItem(value: 'transfer', child: Text('Request transfer')),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? _primary : const Color(0xffe5e7eb), width: selected ? 1.6 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Checkbox(
            value: selected,
            onChanged: selectable
                ? (v) => setState(() {
                      if (v == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    })
                : null,
          ),
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withOpacity(0.12),
            child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text([w['worker_unique_id'], w['job_position']].where((x) => x != null && x.toString().isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ),
          if (menu.isNotEmpty && !_locked)
            PopupMenuButton<String>(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_vert_rounded),
              itemBuilder: (_) => menu,
              onSelected: (v) {
                switch (v) {
                  case 'times':
                    _editTimes(w);
                    break;
                  case 'status':
                    _setStatus(w);
                    break;
                  case 'break':
                    _toggleBreak(w);
                    break;
                  case 'transfer':
                    _transfer(w);
                    break;
                }
              },
            ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusPill(label: label, color: color, icon: icon),
              if (wf != null && wf != 'Draft') StatusPill(label: wf, color: WorkflowColors.of(wf)),
              if (wf == 'Draft') StatusPill(label: 'Draft', color: WorkflowColors.of('Draft')),
              if (_isCarryOver(w)) StatusPill(label: 'Started ${_short(w['attendance_record_date'])}', color: Colors.teal, icon: Icons.nights_stay_rounded),
              if (w['attendance_source'] == 'Biometric') StatusPill(label: 'Biometric', color: Colors.cyan.shade800, icon: Icons.fingerprint_rounded),
            ]),
            if (w['attendance_status'] == null || w['attendance_status'] == 'Present') ...[
              const SizedBox(height: 8),
              Row(children: [
                _timeBox('In', '${_hm(w['check_in_time'])}${_dayLabel(w['check_in_time'])}'),
                _timeBox('Out', '${_hm(w['check_out_time'])}${_dayLabel(w['check_out_time'])}'),
                _timeBox('Hours', hours == null ? '—' : hours.toStringAsFixed(2)),
              ]),
            ],
            if (w['anomaly_code'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.report_rounded, size: 16, color: Colors.deepOrange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text((w['anomaly_detail'] ?? 'Unusually long shift').toString(),
                        style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
                  ),
                  const HelpTip(title: 'Flagged for review', message: HelpTexts.longShift, size: 16),
                ]),
              ),
            ],
            if (wf == 'Rejected' && (w['admin_rejection_notes'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Rejected: ${w['admin_rejection_notes']} — fix it in Rejected Records.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
            ],
            if (primary != null) ...[const SizedBox(height: 10), primary],
          ]),
        ),
      ]),
    );
  }

  Widget _timeBox(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(color: const Color(0xfff5f6fa), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _lunchCard() {
    final eligible = _lunchEligible;
    final includedCount = eligible.where((w) => !_lunchExcluded.contains(_id(w))).length;
    return _card(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.lunch_dining_rounded, color: _primary),
          title: const Text('Lunch break (bulk)', style: TextStyle(fontWeight: FontWeight.bold, color: _primary)),
          subtitle: Text('$includedCount of ${eligible.length} checked-out worker(s) included'),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            Text('Set one lunch period for everybody, uncheck anyone who did not take lunch, '
                'or give a worker a different time.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _lunchStart ?? const TimeOfDay(hour: 12, minute: 0));
                    if (t != null) setState(() => _lunchStart = t);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text('Start ${_t(_lunchStart)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _lunchEnd ?? const TimeOfDay(hour: 13, minute: 0));
                    if (t != null) setState(() => _lunchEnd = t);
                  },
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text('End ${_t(_lunchEnd)}'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            ...eligible.map((w) {
              final id = _id(w);
              final included = !_lunchExcluded.contains(id);
              final o = _lunchOverrides[id];
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: included,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _lunchExcluded.remove(id);
                  } else {
                    _lunchExcluded.add(id);
                  }
                }),
                title: Text(w['full_name'].toString()),
                subtitle: Text(o != null
                    ? 'Custom ${_t(o['start'])} – ${_t(o['end'])}'
                    : (included ? (Map.from(w)['lunch_count'].toString() != '0' ? 'Lunch already recorded (will be updated)' : 'Uses the default time') : 'No lunch recorded')),
                secondary: IconButton(
                  tooltip: 'Different time for this worker',
                  icon: Icon(Icons.schedule_rounded, color: o != null ? Colors.blue.shade700 : null),
                  onPressed: () async {
                    final s = await showTimePicker(context: context, initialTime: o?['start'] ?? _lunchStart ?? const TimeOfDay(hour: 12, minute: 0), helpText: 'Lunch start');
                    if (s == null || !mounted) return;
                    final e = await showTimePicker(context: context, initialTime: o?['end'] ?? _lunchEnd ?? const TimeOfDay(hour: 13, minute: 0), helpText: 'Lunch end');
                    if (e == null) return;
                    setState(() {
                      _lunchOverrides[id] = {'start': s, 'end': e};
                      _lunchExcluded.remove(id);
                    });
                  },
                ),
              );
            }),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _primary),
                onPressed: _busy || _locked ? null : _saveLunch,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save lunch times'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    if (_selected.isNotEmpty) {
      final nIn = _eligible(_canCheckIn).length;
      final nOut = _eligible(_canCheckOut).length;
      final nAbs = _eligible(_canSetStatus).length;
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(color: _primary),
          child: Row(children: [
            Text('${_selected.length} selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const Spacer(),
            Wrap(spacing: 6, children: [
              FilledButton.tonal(onPressed: nIn == 0 || _busy ? null : _bulkCheckIn, child: Text('Check in ($nIn)')),
              FilledButton.tonal(onPressed: nOut == 0 || _busy ? null : _bulkCheckOut, child: Text('Check out ($nOut)')),
              FilledButton.tonal(onPressed: nAbs == 0 || _busy ? null : _bulkAbsent, child: Text('Absent ($nAbs)')),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: () => setState(_selected.clear),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ]),
          ]),
        ),
      );
    }
    final blockers = _blockers;
    final canSubmit = !_busy && _hasDraftToSubmit && blockers.isEmpty;
    final status = !_hasDraftToSubmit
        ? (_allSubmitted ? 'Day already submitted.' : 'Nothing to submit yet.')
        : (blockers.isEmpty ? 'Ready to submit.' : 'Before submitting: ${blockers.join(' · ')}');
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -2)),
        ]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(blockers.isEmpty && _hasDraftToSubmit ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 16, color: blockers.isEmpty && _hasDraftToSubmit ? Colors.green.shade700 : Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(child: Text(status, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))),
            const HelpTip(title: 'Submitting a day', message: '${HelpTexts.workflow}\n\n${HelpTexts.previousWeek}', size: 16),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _primary),
              onPressed: canSubmit ? () => _submitDay() : null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Submit day for review', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}
