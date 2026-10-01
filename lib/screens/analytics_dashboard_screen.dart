// Live Site Operations dashboard (Admin home screen).
//
// Data: GET /api/main-dashboard/live           (whole operation, today)
//       GET /api/main-dashboard/sites/:siteId  (drill-down)
// Both endpoints are Admin-only on the backend.
//
// Delivery is POLLING (the backend has no WebSocket/SSE). The screen says so,
// shows when the data was last refreshed, and marks it stale when a refresh
// fails or is overdue. Polling pauses while another screen is on top or the
// app is in the background.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:team_flow/constants.dart';

import 'admin_attendance_screen.dart';
import 'biometric_import_screen.dart';
import 'biometric_processing_screen.dart';
import 'contract_sites_screen.dart';
import 'device_id_mapping_screen.dart';
import 'hr_management_screen.dart';
import 'login_screen.dart';
import 'payroll_screen.dart';
import 'pending_transfers_screen.dart';
import 'project_management_screen.dart';
import 'staff_attendance_payroll_hub.dart';
import 'supervisor_management_screen.dart';
import 'worker_assignment_screen.dart';
import 'workers_screen.dart';

// ---------------------------------------------------------------------------
// Palette (the app's own navy brand; status colors used sparingly)
// ---------------------------------------------------------------------------
class OpsColors {
  static const Color navy = Color(0xff1a2a6c);
  static const Color accent = Color(0xfffdbb2d);
  static const Color page = Color(0xFFF4F6FB);
  static const Color card = Colors.white;
  static const Color border = Color(0xffe3e7ef);
  static const Color text = Color(0xff1f2937);
  static const Color muted = Color(0xff6b7280);
  static const Color critical = Color(0xffb21f1f);
  static const Color warning = Color(0xffc25e00);
  static const Color action = Color(0xff2a4d8f);
  static const Color ok = Color(0xff2e7d32);
  static const Color info = Color(0xff6b7280);
}

Color severityColor(String severity) {
  switch (severity) {
    case 'critical':
      return OpsColors.critical;
    case 'warning':
      return OpsColors.warning;
    case 'action':
      return OpsColors.action;
    case 'ok':
      return OpsColors.ok;
    default:
      return OpsColors.info;
  }
}

String severityLabel(String severity) {
  switch (severity) {
    case 'critical':
      return 'Critical';
    case 'warning':
      return 'Needs attention';
    case 'action':
      return 'Awaiting decision';
    case 'ok':
      return 'OK';
    default:
      return 'Info';
  }
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------
int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

bool _bool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _list(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

/// 'YYYY-MM-DD HH:MM:SS' (wall clock) -> 'HH:mm', prefixed with the day when
/// it is not [businessDate].
String _clock(String? value, String businessDate) {
  if (value == null || value.length < 16) return '—';
  final day = value.substring(0, 10);
  final time = value.substring(11, 16);
  if (day == businessDate) return time;
  final parsed = DateTime.tryParse(day);
  if (parsed == null) return '$day $time';
  return '${DateFormat('MMM d').format(parsed)} $time';
}

String _day(String? value) {
  if (value == null || value.length < 10) return '—';
  final parsed = DateTime.tryParse(value.substring(0, 10));
  return parsed == null ? value : DateFormat('MMM d, yyyy').format(parsed);
}

String _dioMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) return '${data['message']}';
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'The server did not answer in time.';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server.';
    }
    final code = error.response?.statusCode;
    if (code != null) return 'Server error ($code).';
  }
  return 'Unexpected error.';
}

// ---------------------------------------------------------------------------
// Models (field names match GET /api/main-dashboard/live exactly)
// ---------------------------------------------------------------------------
class OpsException {
  final String severity;
  final String code;
  final String title;
  final String detail;
  final int? siteId;
  final String? siteName;
  final String? shiftType;
  final int count;
  final String? action;

  OpsException.fromJson(Map<String, dynamic> j)
      : severity = _str(j['severity']) ?? 'info',
        code = _str(j['code']) ?? '',
        title = _str(j['title']) ?? '',
        detail = _str(j['detail']) ?? '',
        siteId = j['site_id'] == null ? null : _int(j['site_id']),
        siteName = _str(j['site_name']),
        shiftType = _str(j['shift_type']),
        count = _int(j['count']),
        action = _str(j['action']);
}

class OpsSupervisor {
  final int userId;
  final String? fullName;
  final String? status;
  final String? role;
  final bool valid;

  OpsSupervisor.fromJson(Map<String, dynamic> j)
      : userId = _int(j['user_id']),
        fullName = _str(j['full_name']),
        status = _str(j['status']),
        role = _str(j['role']),
        valid = _bool(j['valid']);
}

class OpsUnit {
  final String shiftType;
  final bool isShiftSite;
  final OpsSupervisor? supervisor;
  final bool hasValidSupervisor;
  final int expected;
  final int recorded;
  final int notRecorded;
  final int present;
  final int onSiteNow;
  final int onBreak;
  final int checkedOut;
  final int carriedOverOpen;
  final int absent;
  final int sick;
  final int vacation;
  final int holiday;
  final int wfDraft;
  final int wfSubmitted;
  final int wfApproved;
  final int wfRejected;
  final int backlogSubmitted;
  final int backlogRejected;
  final int backlogOverdueDraft;
  final int transfersOutgoing;
  final int transfersIncoming;
  final int biometricUnresolved;
  final int unassignedAttendance;
  final String? payrollLastCoveredEnd;
  final int payrollNotReady;
  final String? lastCheckEvent;
  final String completion;
  final List<OpsException> exceptions;

  OpsUnit.fromJson(Map<String, dynamic> j)
      : shiftType = _str(j['shift_type']) ?? 'Day',
        isShiftSite = _bool(j['is_shift_site']),
        supervisor = j['supervisor'] is Map
            ? OpsSupervisor.fromJson(_map(j['supervisor']))
            : null,
        hasValidSupervisor = _bool(j['has_valid_supervisor']),
        expected = _int(j['expected']),
        recorded = _int(j['recorded']),
        notRecorded = _int(j['not_recorded']),
        present = _int(j['present']),
        onSiteNow = _int(j['on_site_now']),
        onBreak = _int(j['on_break']),
        checkedOut = _int(j['checked_out']),
        carriedOverOpen = _int(j['carried_over_open']),
        absent = _int(j['absent']),
        sick = _int(j['sick']),
        vacation = _int(j['vacation']),
        holiday = _int(j['holiday']),
        wfDraft = _int(_map(j['workflow'])['draft']),
        wfSubmitted = _int(_map(j['workflow'])['submitted']),
        wfApproved = _int(_map(j['workflow'])['approved']),
        wfRejected = _int(_map(j['workflow'])['rejected']),
        backlogSubmitted = _int(_map(j['backlog'])['submitted']),
        backlogRejected = _int(_map(j['backlog'])['rejected']),
        backlogOverdueDraft = _int(_map(j['backlog'])['overdue_draft']),
        transfersOutgoing = _int(_map(j['transfers'])['outgoing']),
        transfersIncoming = _int(_map(j['transfers'])['incoming']),
        biometricUnresolved = _int(j['biometric_unresolved']),
        unassignedAttendance = _int(j['unassigned_attendance']),
        payrollLastCoveredEnd = _str(_map(j['payroll'])['last_covered_end']),
        payrollNotReady = _int(_map(j['payroll'])['not_ready']),
        lastCheckEvent = _str(j['last_check_event']),
        completion = _str(j['completion']) ?? 'no_workers',
        exceptions =
            _list(j['exceptions']).map(OpsException.fromJson).toList();

  String get worstSeverity {
    const rank = {'critical': 0, 'warning': 1, 'action': 2, 'info': 3};
    String? worst;
    for (final e in exceptions) {
      if (e.severity == 'info') continue;
      if (worst == null || (rank[e.severity] ?? 9) < (rank[worst] ?? 9)) {
        worst = e.severity;
      }
    }
    return worst ?? 'ok';
  }
}

class OpsSite {
  final int siteId;
  final String siteName;
  final String? location;
  final int? contractId;
  final String? contractName;
  final String? projectName;
  final bool supportsShifts;
  final String attention;
  final int expected;
  final List<OpsUnit> units;

  OpsSite.fromJson(Map<String, dynamic> j)
      : siteId = _int(j['site_id']),
        siteName = _str(j['site_name']) ?? 'Site',
        location = _str(j['location']),
        contractId = j['contract_id'] == null ? null : _int(j['contract_id']),
        contractName = _str(j['contract_name']),
        projectName = _str(j['project_name']),
        supportsShifts = _bool(j['supports_shifts']),
        attention = _str(j['attention']) ?? 'ok',
        expected = _int(j['expected']),
        units = _list(j['units']).map(OpsUnit.fromJson).toList();
}

class OpsLive {
  final String businessDate;
  final bool isToday;
  final String generatedAt;
  final int refreshSeconds;
  final Map<String, dynamic> rules;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> backlog;
  final List<OpsException> exceptions;
  final List<OpsSite> sites;
  final Map<String, dynamic> transfers;
  final Map<String, dynamic> biometric;
  final Map<String, dynamic> payroll;
  final Map<String, dynamic> staff;

  OpsLive.fromJson(Map<String, dynamic> j)
      : businessDate = _str(j['business_date']) ?? '',
        isToday = _bool(j['is_today']),
        generatedAt = _str(j['generated_at']) ?? '',
        refreshSeconds = _int(j['refresh_seconds']) > 0
            ? _int(j['refresh_seconds'])
            : 60,
        rules = _map(j['rules']),
        summary = _map(j['summary']),
        backlog = _map(j['backlog']),
        exceptions =
            _list(j['exceptions']).map(OpsException.fromJson).toList(),
        sites = _list(j['sites']).map(OpsSite.fromJson).toList(),
        transfers = _map(j['transfers']),
        biometric = _map(j['biometric']),
        payroll = _map(j['payroll']),
        staff = _map(j['staff']);
}

// ---------------------------------------------------------------------------
// Polling controller shared by the dashboard and the site drill-down.
// ---------------------------------------------------------------------------
mixin _PollingMixin<T extends StatefulWidget> on State<T> {
  Timer? _pollTimer;
  AppLifecycleListener? _lifecycle;
  bool refreshing = false;
  DateTime? lastSuccess;
  String? lastError;
  int refreshSeconds = 60;
  bool _paused = false; // app hidden
  bool _covered = false; // another screen is on top

  Future<void> fetch();

  void startPolling() {
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _paused = false;
        if (!_covered) refresh();
      },
      onHide: () {
        _paused = true;
        _pollTimer?.cancel();
      },
    );
    refresh();
  }

  void stopPolling() {
    _lifecycle?.dispose();
    _pollTimer?.cancel();
  }

  void _schedule() {
    _pollTimer?.cancel();
    if (_paused || _covered) return;
    _pollTimer = Timer(Duration(seconds: refreshSeconds), refresh);
  }

  Future<void> refresh() async {
    if (refreshing || !mounted) return;
    setState(() => refreshing = true);
    try {
      await fetch();
      lastSuccess = DateTime.now();
      lastError = null;
    } catch (e) {
      lastError = _dioMessage(e);
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
        _schedule();
      }
    }
  }

  bool get isStale {
    if (lastSuccess == null) return false;
    if (lastError != null) return true;
    return DateTime.now().difference(lastSuccess!) >
        Duration(seconds: refreshSeconds * 2 + 15);
  }

  /// Pushes [page], pausing polling while it is on top, then refreshes.
  Future<void> openPage(Widget page) async {
    _covered = true;
    _pollTimer?.cancel();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    _covered = false;
    refresh();
  }
}

// ---------------------------------------------------------------------------
// "Last updated" indicator. Rebuilds itself every 10 s only.
// ---------------------------------------------------------------------------
class _LiveIndicator extends StatefulWidget {
  final DateTime? lastSuccess;
  final bool refreshing;
  final bool stale;
  final String? error;
  final int refreshSeconds;

  const _LiveIndicator({
    required this.lastSuccess,
    required this.refreshing,
    required this.stale,
    required this.error,
    required this.refreshSeconds,
  });

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 15) return 'just now';
    if (s < 60) return '${s}s ago';
    final m = s ~/ 60;
    if (m < 60) return '${m}m ago';
    return DateFormat('HH:mm').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;
    if (widget.refreshing) {
      color = OpsColors.action;
      label = 'Refreshing…';
      icon = Icons.sync_rounded;
    } else if (widget.lastSuccess == null) {
      color = widget.error != null ? OpsColors.critical : OpsColors.muted;
      label = widget.error != null ? 'Not loaded' : 'Loading…';
      icon = Icons.cloud_off_rounded;
    } else if (widget.stale) {
      color = OpsColors.warning;
      label = 'Stale · updated ${_ago(widget.lastSuccess!)}';
      icon = Icons.warning_amber_rounded;
    } else {
      color = OpsColors.ok;
      label = 'Updated ${_ago(widget.lastSuccess!)}';
      icon = Icons.check_circle_outline_rounded;
    }
    return Tooltip(
      message:
          'Polling every ${widget.refreshSeconds}s (the server does not push updates).'
          '${widget.lastSuccess != null ? '\nLast successful refresh: ${DateFormat('HH:mm:ss').format(widget.lastSuccess!)}' : ''}'
          '${widget.error != null ? '\nLast error: ${widget.error}' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.refreshing
                ? SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: color),
                  )
                : Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('· every ${widget.refreshSeconds}s',
                style:
                    const TextStyle(color: OpsColors.muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation shared by dashboard and drill-down
// ---------------------------------------------------------------------------
Widget? _destinationFor(String? action, {OpsSite? site}) {
  switch (action) {
    case 'attendance_review':
      return const AdminAttendanceScreen();
    case 'transfers':
      return const PendingTransfersScreen();
    case 'biometric_review':
      return const BiometricProcessingScreen(initialTab: 1);
    case 'biometric_processing':
      return const BiometricProcessingScreen();
    case 'assignments':
      return const WorkerAssignmentScreen();
    case 'payroll':
      return const PayrollScreen();
    case 'staff':
      return const StaffAttendancePayrollHub();
    case 'supervisors':
      if (site != null && site.contractId != null) {
        return ContractSitesScreen(
          contractId: site.contractId!,
          contractName: site.contractName ?? 'Contract',
        );
      }
      return const SupervisorManagementScreen();
    default:
      return null;
  }
}

String _actionLabel(String? action) {
  switch (action) {
    case 'attendance_review':
      return 'Review';
    case 'transfers':
      return 'Transfers';
    case 'biometric_review':
      return 'Biometric review';
    case 'biometric_processing':
      return 'Process';
    case 'assignments':
      return 'Assignments';
    case 'payroll':
      return 'Payroll';
    case 'staff':
      return 'Staff';
    case 'supervisors':
      return 'Shift setup';
    case 'site':
      return 'Open site';
    default:
      return 'Open';
  }
}

// ===========================================================================
// DASHBOARD
// ===========================================================================
class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen>
    with _PollingMixin<AnalyticsDashboardScreen> {
  OpsLive? _live;
  String _adminName = 'Admin';
  bool _showInfo = false;
  bool _showAllExceptions = false;
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    _loadAdminName();
    startPolling();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  Future<void> _loadAdminName() async {
    final name = await ApiConfig.storage.read(key: 'user_name');
    if (mounted && name != null && name.trim().isNotEmpty) {
      setState(() => _adminName = name.trim().split(' ').first);
    }
  }

  @override
  Future<void> fetch() async {
    try {
      final response = await ApiConfig.dio.get('/main-dashboard/live');
      final body = response.data;
      if (body is! Map || body['data'] is! Map) {
        throw const FormatException('Unexpected response');
      }
      final live = OpsLive.fromJson(_map(body['data']));
      if (!mounted) return;
      setState(() {
        _live = live;
        _forbidden = false;
        refreshSeconds = live.refreshSeconds;
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 && mounted) {
        setState(() => _forbidden = true);
      }
      rethrow;
    }
  }

  void _openSite(OpsSite site, {String? shift}) {
    openPage(_SiteOperationsPage(
      siteId: site.siteId,
      siteName: site.siteName,
      initialShift: shift,
    ));
  }

  void _runAction(OpsException e) {
    final site = _live?.sites.where((s) => s.siteId == e.siteId).firstOrNull;
    if (e.action == 'site' && site != null) {
      _openSite(site, shift: e.shiftType);
      return;
    }
    final page = _destinationFor(e.action, site: site);
    if (page != null) openPage(page);
  }

  // ---------------------------------------------------------------- shell
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final content = _buildMain(showMenu: !wide);
      if (wide) {
        return Scaffold(
          backgroundColor: OpsColors.page,
          body: Row(children: [
            _Sidebar(onOpen: openPage, onLogout: _confirmLogout),
            Expanded(child: content),
          ]),
        );
      }
      return Scaffold(
        backgroundColor: OpsColors.page,
        drawer: Drawer(
          backgroundColor: OpsColors.navy,
          child: _Sidebar(
            onOpen: (page) {
              Navigator.pop(context);
              return openPage(page);
            },
            onLogout: () {
              Navigator.pop(context);
              _confirmLogout();
            },
          ),
        ),
        body: content,
      );
    });
  }

  Future<void> _logout() async {
    await ApiConfig.storage.delete(key: 'jwt_token');
    await ApiConfig.storage.delete(key: 'user_role');
    await ApiConfig.storage.delete(key: 'user_id');
    await ApiConfig.storage.delete(key: 'user_name');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: OpsColors.critical,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  Widget _buildMain({required bool showMenu}) {
    final live = _live;
    return Column(
      children: [
        _topBar(showMenu: showMenu),
        if (live != null && isStale) _staleBanner(),
        Expanded(
          child: live == null
              ? _initialState()
              : RefreshIndicator(
                  onRefresh: refresh,
                  child: LayoutBuilder(builder: (context, c) {
                    final pad = c.maxWidth < 600 ? 12.0 : 20.0;
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
                      children: [
                        _statusStrip(live),
                        const SizedBox(height: 16),
                        _attentionPanel(live),
                        const SizedBox(height: 16),
                        _sitesPanel(live, c.maxWidth - pad * 2),
                        const SizedBox(height: 16),
                        _supportingFacts(live),
                        const SizedBox(height: 16),
                        _rulesPanel(live),
                      ],
                    );
                  }),
                ),
        ),
      ],
    );
  }

  Widget _initialState() {
    if (_forbidden) {
      return const _CenteredMessage(
        icon: Icons.lock_outline_rounded,
        title: 'Not authorized',
        message: 'The operations dashboard is available to Admin accounts only.',
      );
    }
    if (lastError != null && !refreshing) {
      return _CenteredMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load the dashboard',
        message: lastError!,
        onRetry: refresh,
      );
    }
    return const Center(
        child: CircularProgressIndicator(color: OpsColors.navy));
  }

  Widget _topBar({required bool showMenu}) {
    final live = _live;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: OpsColors.border)),
      ),
      child: Builder(
        builder: (ctx) => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          spacing: 12,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (showMenu)
                IconButton(
                  icon: const Icon(Icons.menu_rounded, color: OpsColors.text),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Live Site Operations',
                      style: TextStyle(
                          color: OpsColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  Text(
                    live == null
                        ? 'Loading…'
                        : '${live.isToday ? 'Today' : 'Date'} · ${_day(live.businessDate)} (Asia/Beirut)',
                    style:
                        const TextStyle(color: OpsColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _LiveIndicator(
                lastSuccess: lastSuccess,
                refreshing: refreshing,
                stale: isStale,
                error: lastError,
                refreshSeconds: refreshSeconds,
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Refresh now',
                onPressed: refreshing ? null : refresh,
                icon: const Icon(Icons.refresh_rounded, color: OpsColors.navy),
              ),
              const SizedBox(width: 4),
              const CircleAvatar(
                radius: 15,
                backgroundColor: OpsColors.navy,
                child: Icon(Icons.person, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 6),
              Text(_adminName,
                  style: const TextStyle(
                      color: OpsColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _staleBanner() {
    return Container(
      width: double.infinity,
      color: OpsColors.warning.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: OpsColors.warning, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Showing data from ${lastSuccess == null ? '—' : DateFormat('HH:mm:ss').format(lastSuccess!)}. '
            '${lastError != null ? 'Last refresh failed: $lastError ' : 'Refresh is overdue. '}'
            'Figures may not reflect the current situation.',
            style: const TextStyle(color: OpsColors.warning, fontSize: 12.5),
          ),
        ),
        TextButton(onPressed: refresh, child: const Text('Retry')),
      ]),
    );
  }

  // ------------------------------------------------------ 1. status strip
  Widget _statusStrip(OpsLive live) {
    final s = live.summary;
    final wf = _map(s['workflow']);
    final b = live.backlog;
    final expected = _int(s['expected']);
    final recorded = _int(s['recorded']);
    final ratio = expected == 0 ? 0.0 : recorded / expected;

    final figures = <_Figure>[
      _Figure('Expected', expected, OpsColors.text,
          hint: 'Active workers assigned to an Active site/shift today'),
      _Figure('On site now', _int(s['on_site_now']), OpsColors.ok,
          hint: 'Checked in, not checked out, not on a break'),
      _Figure('On break', _int(s['on_break']), OpsColors.action),
      _Figure('Checked out', _int(s['checked_out']), OpsColors.muted),
      _Figure('Absent', _int(s['absent']), OpsColors.critical),
      _Figure('Sick', _int(s['sick']), OpsColors.warning),
      _Figure('Vacation', _int(s['vacation']), OpsColors.muted),
      _Figure('Holiday', _int(s['holiday']), OpsColors.muted),
      _Figure('Not recorded', _int(s['not_recorded']), OpsColors.warning,
          hint: 'Expected workers with no attendance record yet'),
    ];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_int(s['active_sites'])} active sites · ${_int(s['sites_with_workers'])} with workers',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: OpsColors.text,
                    fontSize: 14),
              ),
              if (_int(s['sites_needing_attention']) > 0)
                _Pill(
                    '${_int(s['sites_needing_attention'])} need attention',
                    OpsColors.warning),
              if (_int(s['units_without_supervisor']) > 0)
                _Pill(
                    '${_int(s['units_without_supervisor'])} shift(s) without supervisor',
                    OpsColors.critical),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: OpsColors.border,
                  color: OpsColors.navy,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('$recorded / $expected recorded',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: OpsColors.text,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: figures.map((f) => _FigureTile(figure: f)).toList(),
          ),
          const Divider(height: 26, color: OpsColors.border),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _inlineStat('Today\'s records',
                  'Draft ${_int(wf['draft'])} · Submitted ${_int(wf['submitted'])} · Approved ${_int(wf['approved'])} · Rejected ${_int(wf['rejected'])}'),
              _backlogLink(
                  'Awaiting your review',
                  _int(b['submitted']),
                  _str(b['submitted_oldest']),
                  OpsColors.action,
                  () => openPage(const AdminAttendanceScreen())),
              _backlogLink(
                  'Rejected, awaiting supervisor',
                  _int(b['rejected']),
                  _str(b['rejected_oldest']),
                  OpsColors.warning,
                  () => openPage(const AdminAttendanceScreen())),
              _backlogLink('Days not submitted', _int(b['overdue_draft']),
                  _str(b['overdue_draft_oldest']), OpsColors.warning, null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inlineStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: OpsColors.muted, fontSize: 11.5)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: OpsColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _backlogLink(String label, int count, String? oldest, Color color,
      VoidCallback? onTap) {
    final active = count > 0;
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: OpsColors.muted, fontSize: 11.5)),
        const SizedBox(height: 2),
        Text(
          active
              ? '$count${oldest != null ? ' · since ${_day(oldest)}' : ''}'
              : 'None',
          style: TextStyle(
              color: active ? color : OpsColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              decoration: active && onTap != null
                  ? TextDecoration.underline
                  : TextDecoration.none),
        ),
      ],
    );
    if (!active || onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }

  // -------------------------------------------------- 2. needs attention
  Widget _attentionPanel(OpsLive live) {
    final actionable =
        live.exceptions.where((e) => e.severity != 'info').toList();
    final info = live.exceptions.where((e) => e.severity == 'info').toList();
    final visible =
        _showAllExceptions ? actionable : actionable.take(8).toList();

    return _Panel(
      title: 'Needs attention',
      subtitle: actionable.isEmpty
          ? 'No open problems found in the current data.'
          : '${actionable.length} item(s), most severe first',
      trailing: info.isEmpty
          ? null
          : TextButton(
              onPressed: () => setState(() => _showInfo = !_showInfo),
              child: Text(_showInfo
                  ? 'Hide informational'
                  : 'Informational (${info.length})'),
            ),
      child: Column(
        children: [
          if (actionable.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: OpsColors.ok, size: 20),
                SizedBox(width: 8),
                Text('All sites are operating without exceptions.',
                    style: TextStyle(color: OpsColors.ok)),
              ]),
            ),
          ...visible.map((e) => _ExceptionRow(e: e, onAction: _runAction)),
          if (actionable.length > 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _showAllExceptions = !_showAllExceptions),
                child: Text(_showAllExceptions
                    ? 'Show fewer'
                    : 'Show all ${actionable.length}'),
              ),
            ),
          if (_showInfo) ...info.map((e) => _ExceptionRow(e: e, onAction: _runAction)),
        ],
      ),
    );
  }

  // ----------------------------------------------------- 3. sites table
  Widget _sitesPanel(OpsLive live, double width) {
    final table = width >= 1080;
    return _Panel(
      title: 'Sites',
      subtitle:
          'One row per site and shift. Day and Night are never combined. Tap a row for workers and issues.',
      child: live.sites.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('There are no Active sites.',
                  style: TextStyle(color: OpsColors.muted)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (table) const _UnitHeaderRow(),
                for (final site in live.sites) ...[
                  _SiteHeader(site: site, onTap: () => _openSite(site)),
                  if (site.units.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Text('No workers assigned and no shifts configured.',
                          style:
                              TextStyle(color: OpsColors.muted, fontSize: 12.5)),
                    ),
                  for (final unit in site.units)
                    table
                        ? _UnitTableRow(
                            site: site,
                            unit: unit,
                            businessDate: live.businessDate,
                            onTap: () =>
                                _openSite(site, shift: unit.shiftType),
                          )
                        : _UnitCard(
                            site: site,
                            unit: unit,
                            businessDate: live.businessDate,
                            onTap: () =>
                                _openSite(site, shift: unit.shiftType),
                          ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  // ------------------------------------------- 4. supporting facts
  Widget _supportingFacts(OpsLive live) {
    final bio = live.biometric;
    final pay = live.payroll;
    final staff = live.staff;
    final tr = live.transfers;

    final cards = <Widget>[
      _FactCard(
        icon: Icons.fingerprint_rounded,
        title: 'Biometric',
        onTap: () => openPage(const BiometricProcessingScreen(initialTab: 1)),
        lines: _bool(bio['available'])
            ? [
                _FactLine('Unresolved punches',
                    '${_int(bio['unresolved_total'])}',
                    color: _int(bio['unresolved_total']) > 0
                        ? OpsColors.warning
                        : null),
                _FactLine('Pending processing', '${_int(bio['pending_queue'])}'),
                _FactLine(
                    'Drafts nobody can review',
                    '${_int(_map(bio['orphan_drafts'])['workers']) + _int(_map(bio['orphan_drafts'])['staff'])}'),
                _FactLine('Latest punch received',
                    _clock(_str(bio['last_punch_at']), live.businessDate)),
                _FactLine(
                    'Last import',
                    bio['last_import'] is Map
                        ? '#${_int(_map(bio['last_import'])['batch_id'])} · ${_str(_map(bio['last_import'])['status']) ?? '—'}'
                        : '—'),
              ]
            : [
                _FactLine('Status',
                    _str(bio['reason']) ?? 'Not available',
                    color: OpsColors.muted)
              ],
      ),
      _FactCard(
        icon: Icons.swap_horiz_rounded,
        title: 'Transfers',
        onTap: () => openPage(const PendingTransfersScreen()),
        lines: [
          _FactLine('Pending requests', '${_int(tr['pending'])}',
              color: _int(tr['pending']) > 0 ? OpsColors.action : null),
          _FactLine('Oldest request',
              _str(tr['oldest_created_at']) == null
                  ? '—'
                  : _day(_str(tr['oldest_created_at']))),
        ],
      ),
      _FactCard(
        icon: Icons.payments_rounded,
        title: 'Worker payroll',
        onTap: () => openPage(const PayrollScreen()),
        lines: _bool(pay['available'])
            ? _payrollLines(pay)
            : [
                _FactLine('Status', _str(pay['reason']) ?? 'Not available',
                    color: OpsColors.muted)
              ],
      ),
      _FactCard(
        icon: Icons.badge_rounded,
        title: 'Staff attendance (separate)',
        onTap: () => openPage(const StaffAttendancePayrollHub()),
        lines: _bool(staff['available'])
            ? [
                if (_bool(staff['is_friday']))
                  _FactLine('Today', 'Friday (staff rest day)',
                      color: OpsColors.muted),
                _FactLine('Recorded today',
                    '${_int(staff['recorded_today'])} of ${_int(staff['active_staff'])} active staff'),
                _FactLine('Statuses today', _staffStatuses(staff)),
                _FactLine('Waiting for review',
                    '${_int(_map(staff['backlog'])['submitted'])}',
                    color: _int(_map(staff['backlog'])['submitted']) > 0
                        ? OpsColors.action
                        : null),
                _FactLine('Rejected',
                    '${_int(_map(staff['backlog'])['rejected'])}',
                    color: _int(_map(staff['backlog'])['rejected']) > 0
                        ? OpsColors.warning
                        : null),
              ]
            : [
                _FactLine('Status', _str(staff['reason']) ?? 'Not available',
                    color: OpsColors.muted)
              ],
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 620 ? 2 : 1);
      final w = (c.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map((card) => SizedBox(width: w, child: card)).toList(),
      );
    });
  }

  List<_FactLine> _payrollLines(Map<String, dynamic> pay) {
    final latest = _map(pay['latest_batch']);
    final open = _list(pay['open_batches']);
    String stateLabel(String? state) {
      switch (state) {
        case 'paid':
          return 'Paid';
        case 'awaiting_payment':
          return 'Finalized, not paid';
        case 'awaiting_finalization':
          return 'Generated, not finalized';
        default:
          return '—';
      }
    }

    return [
      _FactLine(
          'Latest batch',
          latest.isEmpty
              ? 'None'
              : '#${_int(latest['batch_id'])} · ${_day(_str(latest['start_date']))} → ${_day(_str(latest['end_date']))}'),
      _FactLine('Latest batch state',
          latest.isEmpty ? '—' : stateLabel(_str(latest['state']))),
      _FactLine('Batches awaiting action', '${open.length}',
          color: open.isNotEmpty ? OpsColors.action : null),
      const _FactLine('Pays', 'Approved attendance only',
          color: OpsColors.muted),
    ];
  }

  String _staffStatuses(Map<String, dynamic> staff) {
    final m = _map(staff['by_attendance_status']);
    if (m.isEmpty) return '—';
    return m.entries.map((e) => '${e.key} ${_int(e.value)}').join(' · ');
  }

  // ---------------------------------------------------- 5. rules footnote
  Widget _rulesPanel(OpsLive live) {
    final r = live.rules;
    final high = _map(r['high_absence']);
    final notAvailable = (r['not_available'] is List)
        ? (r['not_available'] as List).map((e) => '$e').toList()
        : <String>[];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OpsColors.border),
        ),
        child: ExpansionTile(
          leading: const Icon(Icons.info_outline_rounded,
              color: OpsColors.muted, size: 20),
          title: const Text('How these numbers are calculated',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ruleLine('Expected', _str(r['expected_workers'])),
            _ruleLine('Record for today', _str(r['record_for_date'])),
            _ruleLine('Day not submitted', _str(r['overdue_draft'])),
            _ruleLine('Supervisor required', _str(r['supervisor_required'])),
            _ruleLine('Payroll-ready', _str(r['payroll_ready'])),
            _ruleLine('High absence', _str(high['description'])),
            if (notAvailable.isNotEmpty)
              _ruleLine('Not calculated', notAvailable.join(' ')),
            _ruleLine('Refresh',
                'Polled every ${live.refreshSeconds}s. Server time of this snapshot: ${live.generatedAt}.'),
          ],
        ),
      ),
    );
  }

  Widget _ruleLine(String label, String? text) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
              color: OpsColors.text, fontSize: 12.5, fontFamily: 'Cairo'),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar (the Admin home keeps the full navigation)
// ---------------------------------------------------------------------------
class _NavItem {
  final IconData icon;
  final String label;
  final Widget Function() build;
  const _NavItem(this.icon, this.label, this.build);
}

class _Sidebar extends StatelessWidget {
  final Future<void> Function(Widget page) onOpen;
  final VoidCallback onLogout;

  const _Sidebar({required this.onOpen, required this.onLogout});

  static final List<_NavItem> _items = [
    _NavItem(Icons.engineering_rounded, 'Workers', () => const WorkersScreen()),
    _NavItem(Icons.fact_check_rounded, 'Attendance Review',
        () => const AdminAttendanceScreen()),
    _NavItem(Icons.payments_rounded, 'Payroll', () => const PayrollScreen()),
    _NavItem(Icons.business_rounded, 'Projects',
        () => const ProjectManagementScreen()),
    _NavItem(Icons.alt_route_rounded, 'Worker Distribution',
        () => const WorkerAssignmentScreen()),
    _NavItem(Icons.people_alt_rounded, 'HR Management',
        () => const HRManagementScreen()),
    _NavItem(Icons.swap_horiz_rounded, 'Transfer Requests',
        () => const PendingTransfersScreen()),
    _NavItem(Icons.badge_rounded, 'Staff Attendance & Payroll',
        () => const StaffAttendancePayrollHub()),
    _NavItem(Icons.manage_accounts_rounded, 'Supervisors Management',
        () => const SupervisorManagementScreen()),
    _NavItem(Icons.fingerprint_rounded, 'Biometric Processing',
        () => const BiometricProcessingScreen()),
    _NavItem(Icons.upload_file_rounded, 'Biometric Import',
        () => const BiometricImportScreen()),
    _NavItem(Icons.link_rounded, 'Device ID Mapping',
        () => const DeviceIdMappingScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: OpsColors.navy,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 4),
              child: Text('ASIK ENGINEERING CONSTRUCTION',
                  maxLines: 2,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.8)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('Admin Panel',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12)),
            ),
            _tile(Icons.monitor_heart_rounded, 'Live Operations', null,
                selected: true),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _items
                    .map((i) => _tile(i.icon, i.label, () => onOpen(i.build())))
                    .toList(),
              ),
            ),
            _tile(Icons.logout_rounded, 'Log Out', onLogout),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback? onTap,
      {bool selected = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(icon,
                  size: 20,
                  color: selected ? OpsColors.accent : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13.5)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small building blocks
// ---------------------------------------------------------------------------
class _Panel extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const _Panel({this.title, this.subtitle, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OpsColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OpsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title!,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: OpsColors.text)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 12, color: OpsColors.muted)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _Figure {
  final String label;
  final int value;
  final Color color;
  final String? hint;
  const _Figure(this.label, this.value, this.color, {this.hint});
}

class _FigureTile extends StatelessWidget {
  final _Figure figure;
  const _FigureTile({required this.figure});

  @override
  Widget build(BuildContext context) {
    final zero = figure.value == 0;
    final tile = Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: OpsColors.page,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${figure.value}',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: zero ? OpsColors.muted : figure.color)),
          Text(figure.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: OpsColors.muted)),
        ],
      ),
    );
    return figure.hint == null
        ? tile
        : Tooltip(message: figure.hint!, child: tile);
  }
}

class _ExceptionRow extends StatelessWidget {
  final OpsException e;
  final void Function(OpsException e) onAction;
  const _ExceptionRow({required this.e, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final color = severityColor(e.severity);
    final where = [
      if (e.siteName != null) e.siteName!,
      if (e.shiftType != null) '${e.shiftType} shift',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(e.title,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    if (where.isNotEmpty)
                      Text(where,
                          style: const TextStyle(
                              color: OpsColors.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(e.detail,
                    style: const TextStyle(
                        color: OpsColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          if (e.action != null)
            TextButton(
              onPressed: () => onAction(e),
              child: Text(_actionLabel(e.action)),
            ),
        ],
      ),
    );
  }
}

String completionLabel(String completion) {
  switch (completion) {
    case 'no_workers':
      return 'No workers';
    case 'not_started':
      return 'Not started';
    case 'in_progress':
      return 'In progress';
    case 'all_recorded':
      return 'Recorded, not submitted';
    case 'has_rejected':
      return 'Has rejected';
    case 'submitted':
      return 'Submitted';
    case 'approved':
      return 'Approved';
    default:
      return completion;
  }
}

Color completionColor(String completion) {
  switch (completion) {
    case 'approved':
      return OpsColors.ok;
    case 'submitted':
      return OpsColors.action;
    case 'has_rejected':
      return OpsColors.warning;
    case 'all_recorded':
    case 'in_progress':
      return OpsColors.navy;
    default:
      return OpsColors.muted;
  }
}

String supervisorText(OpsUnit u) {
  final s = u.supervisor;
  if (s == null) return 'No supervisor';
  final name = s.fullName ?? 'User #${s.userId}';
  if (!s.valid) return '$name (${s.status != 'Active' ? s.status : s.role})';
  return name;
}

class _SiteHeader extends StatelessWidget {
  final OpsSite site;
  final VoidCallback onTap;
  const _SiteHeader({required this.site, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = severityColor(site.attention);
    final meta = [
      if (site.projectName != null) site.projectName!,
      if (site.contractName != null) site.contractName!,
      if (site.location != null) site.location!,
      site.supportsShifts ? 'Day/Night shifts' : 'Single shift',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: OpsColors.border)),
        ),
        child: Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(site.siteName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: OpsColors.text)),
                Text(meta,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: OpsColors.muted)),
              ],
            ),
          ),
          if (site.attention != 'ok')
            _Pill(severityLabel(site.attention), color),
          const Icon(Icons.chevron_right_rounded, color: OpsColors.muted),
        ]),
      ),
    );
  }
}

// Column widths for the wide table.
const List<double> _colW = [
  70, // shift
  170, // supervisor
  64, // expected
  130, // recorded
  60, // on site
  52, // break
  52, // out
  52, // absent
  48, // sick
  48, // vac
  48, // hol
  64, // not rec
  150, // workflow
  64, // issues
];

class _UnitHeaderRow extends StatelessWidget {
  const _UnitHeaderRow();

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Shift', 'Supervisor', 'Expected', 'Recorded', 'On site', 'Break',
      'Out', 'Absent', 'Sick', 'Vac.', 'Hol.', 'Not rec.', 'Status', 'Issues',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 6, 12, 6),
      color: OpsColors.page,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            SizedBox(
              width: _colW[i],
              child: Text(labels[i],
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: OpsColors.muted,
                      fontWeight: FontWeight.w700)),
            ),
          const Expanded(
            child: Text('Last check-in/out',
                style: TextStyle(
                    fontSize: 11.5,
                    color: OpsColors.muted,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _UnitTableRow extends StatelessWidget {
  final OpsSite site;
  final OpsUnit unit;
  final String businessDate;
  final VoidCallback onTap;

  const _UnitTableRow({
    required this.site,
    required this.unit,
    required this.businessDate,
    required this.onTap,
  });

  Widget _n(int v, {Color? color, int index = 0}) {
    return SizedBox(
      width: _colW[index],
      child: Text(
        v == 0 ? '–' : '$v',
        style: TextStyle(
          fontSize: 13,
          fontWeight: v == 0 ? FontWeight.normal : FontWeight.w600,
          color: v == 0 ? OpsColors.muted : (color ?? OpsColors.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = unit;
    final issues =
        u.exceptions.where((e) => e.severity != 'info').toList();
    final worst = u.worstSeverity;
    final ratio = u.expected == 0 ? 0.0 : u.recorded / u.expected;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 7, 12, 7),
        child: Row(
          children: [
            SizedBox(
              width: _colW[0],
              child: _ShiftBadge(u.shiftType, isShiftSite: u.isShiftSite),
            ),
            SizedBox(
              width: _colW[1],
              child: Text(supervisorText(u),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: u.hasValidSupervisor || u.expected == 0
                          ? OpsColors.text
                          : OpsColors.critical,
                      fontWeight: u.hasValidSupervisor
                          ? FontWeight.normal
                          : FontWeight.w700)),
            ),
            _n(u.expected, index: 2),
            SizedBox(
              width: _colW[3],
              child: Row(children: [
                Text('${u.recorded}/${u.expected}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: OpsColors.border,
                      color: OpsColors.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ]),
            ),
            _n(u.onSiteNow, color: OpsColors.ok, index: 4),
            _n(u.onBreak, color: OpsColors.action, index: 5),
            _n(u.checkedOut, index: 6),
            _n(u.absent, color: OpsColors.critical, index: 7),
            _n(u.sick, color: OpsColors.warning, index: 8),
            _n(u.vacation, index: 9),
            _n(u.holiday, index: 10),
            _n(u.notRecorded, color: OpsColors.warning, index: 11),
            SizedBox(
              width: _colW[12],
              child: Text(completionLabel(u.completion),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: completionColor(u.completion))),
            ),
            SizedBox(
              width: _colW[13],
              child: issues.isEmpty
                  ? const Text('–',
                      style: TextStyle(color: OpsColors.muted, fontSize: 13))
                  : Tooltip(
                      message: issues.map((e) => '• ${e.title}').join('\n'),
                      child: _Pill('${issues.length}', severityColor(worst)),
                    ),
            ),
            Expanded(
              child: Text(
                _clock(u.lastCheckEvent, businessDate),
                style: const TextStyle(fontSize: 12.5, color: OpsColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  final OpsSite site;
  final OpsUnit unit;
  final String businessDate;
  final VoidCallback onTap;

  const _UnitCard({
    required this.site,
    required this.unit,
    required this.businessDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final u = unit;
    final issues = u.exceptions.where((e) => e.severity != 'info').toList();
    final ratio = u.expected == 0 ? 0.0 : u.recorded / u.expected;
    final metrics = <MapEntry<String, int>>[
      MapEntry('On site', u.onSiteNow),
      MapEntry('Break', u.onBreak),
      MapEntry('Out', u.checkedOut),
      MapEntry('Absent', u.absent),
      MapEntry('Sick', u.sick),
      MapEntry('Vacation', u.vacation),
      MapEntry('Holiday', u.holiday),
      MapEntry('Not recorded', u.notRecorded),
    ].where((e) => e.value > 0).toList();

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: OpsColors.page,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _ShiftBadge(u.shiftType, isShiftSite: u.isShiftSite),
              const SizedBox(width: 8),
              Expanded(
                child: Text(supervisorText(u),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: u.hasValidSupervisor || u.expected == 0
                            ? OpsColors.text
                            : OpsColors.critical)),
              ),
              Text(completionLabel(u.completion),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: completionColor(u.completion))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text('${u.recorded}/${u.expected} recorded',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: OpsColors.border,
                    color: OpsColors.navy,
                  ),
                ),
              ),
            ]),
            if (metrics.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(metrics.map((e) => '${e.key} ${e.value}').join(' · '),
                  style:
                      const TextStyle(fontSize: 12.5, color: OpsColors.text)),
            ],
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: issues
                    .map((e) => _Pill(e.title, severityColor(e.severity)))
                    .toList(),
              ),
            ],
            const SizedBox(height: 4),
            Text('Last check-in/out: ${_clock(u.lastCheckEvent, businessDate)}',
                style:
                    const TextStyle(fontSize: 11.5, color: OpsColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _ShiftBadge extends StatelessWidget {
  final String shift;
  final bool isShiftSite;
  const _ShiftBadge(this.shift, {required this.isShiftSite});

  @override
  Widget build(BuildContext context) {
    final night = shift == 'Night';
    if (!isShiftSite && !night) {
      return const Text('Site',
          style: TextStyle(fontSize: 12.5, color: OpsColors.muted));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(night ? Icons.nightlight_round : Icons.wb_sunny_rounded,
          size: 14, color: night ? OpsColors.navy : OpsColors.warning),
      const SizedBox(width: 4),
      Text(shift,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _FactLine {
  final String label;
  final String value;
  final Color? color;
  const _FactLine(this.label, this.value, {this.color});
}

class _FactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_FactLine> lines;
  final VoidCallback onTap;

  const _FactCard({
    required this.icon,
    required this.title,
    required this.lines,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: OpsColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: OpsColors.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13.5)),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: OpsColors.muted, size: 18),
              ]),
              const SizedBox(height: 8),
              ...lines.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(l.label,
                              style: const TextStyle(
                                  fontSize: 12.5, color: OpsColors.muted)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(l.value,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: l.color ?? OpsColors.text)),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function()? onRetry;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: OpsColors.muted),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: OpsColors.muted)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// SITE DRILL-DOWN
// ===========================================================================
class _SiteOperationsPage extends StatefulWidget {
  final int siteId;
  final String siteName;
  final String? initialShift;

  const _SiteOperationsPage({
    required this.siteId,
    required this.siteName,
    this.initialShift,
  });

  @override
  State<_SiteOperationsPage> createState() => _SiteOperationsPageState();
}

class _SiteOperationsPageState extends State<_SiteOperationsPage>
    with _PollingMixin<_SiteOperationsPage> {
  Map<String, dynamic>? _data;
  OpsSite? _site;
  String? _shift; // null = all shifts
  String _stateFilter = 'all';
  bool _notFound = false;

  static const Map<String, String> _stateLabels = {
    'all': 'All',
    'not_recorded': 'Not recorded',
    'on_site': 'On site',
    'on_break': 'On break',
    'checked_out': 'Checked out',
    'present': 'Present',
    'absent': 'Absent',
    'sick': 'Sick',
    'vacation': 'Vacation',
    'holiday': 'Holiday',
  };

  @override
  void initState() {
    super.initState();
    _shift = widget.initialShift;
    startPolling();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    try {
      final response =
          await ApiConfig.dio.get('/main-dashboard/sites/${widget.siteId}');
      final body = response.data;
      if (body is! Map || body['data'] is! Map) {
        throw const FormatException('Unexpected response');
      }
      final data = _map(body['data']);
      if (!mounted) return;
      setState(() {
        _data = data;
        _site = OpsSite.fromJson(_map(data['site']));
        _notFound = false;
        if (_shift != null &&
            !_site!.units.any((u) => u.shiftType == _shift)) {
          _shift = null;
        }
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 && mounted) {
        setState(() => _notFound = true);
      }
      rethrow;
    }
  }

  void _go(String? action) {
    final page = _destinationFor(action, site: _site);
    if (page != null) openPage(page);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final site = _site;
    return Scaffold(
      backgroundColor: OpsColors.page,
      appBar: AppBar(
        backgroundColor: OpsColors.navy,
        foregroundColor: Colors.white,
        title: Text(site?.siteName ?? widget.siteName),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _LiveIndicator(
                lastSuccess: lastSuccess,
                refreshing: refreshing,
                stale: isStale,
                error: lastError,
                refreshSeconds: refreshSeconds,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh now',
            onPressed: refreshing ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: data == null || site == null
          ? (_notFound
              ? const _CenteredMessage(
                  icon: Icons.location_off_rounded,
                  title: 'Site not available',
                  message: 'This site was not found or is no longer Active.',
                )
              : (lastError != null && !refreshing
                  ? _CenteredMessage(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load the site',
                      message: lastError!,
                      onRetry: refresh,
                    )
                  : const Center(
                      child:
                          CircularProgressIndicator(color: OpsColors.navy))))
          : RefreshIndicator(
              onRefresh: refresh,
              child: LayoutBuilder(builder: (context, c) {
                final pad = c.maxWidth < 600 ? 12.0 : 20.0;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(pad, 14, pad, 40),
                  children: [
                    if (isStale)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _Pill(
                            'Stale data${lastError != null ? ' — $lastError' : ''}',
                            OpsColors.warning),
                      ),
                    _siteHeader(site, data),
                    const SizedBox(height: 14),
                    _shiftSummaries(site, _str(data['business_date']) ?? ''),
                    const SizedBox(height: 14),
                    _workersPanel(data),
                    const SizedBox(height: 14),
                    _actionRecordsPanel(data),
                    const SizedBox(height: 14),
                    _transfersPanel(data),
                    const SizedBox(height: 14),
                    _biometricPanel(data),
                    if (_list(data['unassigned_attendance']).isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _unassignedPanel(data),
                    ],
                  ],
                );
              }),
            ),
    );
  }

  Widget _siteHeader(OpsSite site, Map<String, dynamic> data) {
    final meta = [
      if (site.projectName != null) 'Project: ${site.projectName}',
      if (site.contractName != null) 'Contract: ${site.contractName}',
      if (site.location != null) site.location!,
      site.supportsShifts ? 'Day/Night shifts' : 'Single shift',
      '${_bool(data['is_today']) ? 'Today' : 'Date'}: ${_day(_str(data['business_date']))}',
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(meta.join(' · '),
              style: const TextStyle(color: OpsColors.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _go('attendance_review'),
              icon: const Icon(Icons.fact_check_rounded, size: 18),
              label: const Text('Attendance review'),
            ),
            OutlinedButton.icon(
              onPressed: () => _go('transfers'),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Transfers'),
            ),
            OutlinedButton.icon(
              onPressed: () => _go('biometric_review'),
              icon: const Icon(Icons.fingerprint_rounded, size: 18),
              label: const Text('Biometric review'),
            ),
            if (site.contractId != null)
              OutlinedButton.icon(
                onPressed: () => _go('supervisors'),
                icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                label: const Text('Shift & supervisor setup'),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _shiftSummaries(OpsSite site, String businessDate) {
    if (site.units.isEmpty) {
      return const _Panel(
        child: Text('No workers are assigned to this site today.',
            style: TextStyle(color: OpsColors.muted)),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 && site.units.length > 1 ? 2 : 1;
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: site.units
            .map((u) => SizedBox(
                width: w, child: _shiftSummaryCard(u, businessDate)))
            .toList(),
      );
    });
  }

  Widget _shiftSummaryCard(OpsUnit u, String businessDate) {
    final selected = _shift == u.shiftType;
    final figures = <_Figure>[
      _Figure('Expected', u.expected, OpsColors.text),
      _Figure('On site', u.onSiteNow, OpsColors.ok),
      _Figure('On break', u.onBreak, OpsColors.action),
      _Figure('Checked out', u.checkedOut, OpsColors.muted),
      _Figure('Absent', u.absent, OpsColors.critical),
      _Figure('Sick', u.sick, OpsColors.warning),
      _Figure('Vacation', u.vacation, OpsColors.muted),
      _Figure('Holiday', u.holiday, OpsColors.muted),
      _Figure('Not recorded', u.notRecorded, OpsColors.warning),
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _shift = selected ? null : u.shiftType),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? OpsColors.navy : OpsColors.border,
                width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _ShiftBadge(u.shiftType, isShiftSite: u.isShiftSite),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Supervisor: ${supervisorText(u)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: u.hasValidSupervisor || u.expected == 0
                              ? OpsColors.text
                              : OpsColors.critical,
                          fontWeight: FontWeight.w600)),
                ),
                Text(completionLabel(u.completion),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: completionColor(u.completion))),
              ]),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    figures.map((f) => _FigureTile(figure: f)).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                'Records today: Draft ${u.wfDraft} · Submitted ${u.wfSubmitted} · Approved ${u.wfApproved} · Rejected ${u.wfRejected}'
                '${u.carriedOverOpen > 0 ? ' · ${u.carriedOverOpen} still open from yesterday' : ''}',
                style: const TextStyle(fontSize: 12, color: OpsColors.muted),
              ),
              Text(
                'Payroll: covered through ${u.payrollLastCoveredEnd == null ? 'never' : _day(u.payrollLastCoveredEnd)}'
                ' · ${u.payrollNotReady} record(s) since then not Approved',
                style: const TextStyle(fontSize: 12, color: OpsColors.muted),
              ),
              Text('Last check-in/out: ${_clock(u.lastCheckEvent, businessDate)}',
                  style:
                      const TextStyle(fontSize: 12, color: OpsColors.muted)),
              if (u.exceptions.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...u.exceptions.map((e) => _ExceptionRow(
                      e: e,
                      onAction: (ex) {
                        if (ex.action == 'site') {
                          setState(() {
                            _shift = ex.shiftType;
                            _stateFilter = ex.code == 'MISSING_RECORDS' ||
                                    ex.code == 'NOT_STARTED'
                                ? 'not_recorded'
                                : (ex.code == 'HIGH_ABSENCE'
                                    ? 'absent'
                                    : _stateFilter);
                          });
                        } else {
                          _go(ex.action);
                        }
                      },
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _workersPanel(Map<String, dynamic> data) {
    final businessDate = _str(data['business_date']) ?? '';
    final all = _list(data['workers'])
        .where((w) => _shift == null || w['shift_type'] == _shift)
        .toList();
    final counts = <String, int>{'all': all.length};
    for (final w in all) {
      final s = _str(w['state']) ?? 'present';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final rows = _stateFilter == 'all'
        ? all
        : all.where((w) => w['state'] == _stateFilter).toList();

    return _Panel(
      title: 'Workers${_shift != null ? ' · $_shift shift' : ''}',
      subtitle:
          'Expected workers and their record for ${_day(businessDate)}. Tap a shift card above to filter by shift.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _stateLabels.entries
                .where((e) => e.key == 'all' || (counts[e.key] ?? 0) > 0)
                .map((e) => ChoiceChip(
                      label: Text('${e.value} (${counts[e.key] ?? 0})'),
                      selected: _stateFilter == e.key,
                      onSelected: (_) =>
                          setState(() => _stateFilter = e.key),
                      selectedColor: OpsColors.navy.withValues(alpha: 0.12),
                      labelStyle: const TextStyle(fontSize: 12),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No workers in this view.',
                  style: TextStyle(color: OpsColors.muted)),
            ),
          ...rows.map((w) => _workerRow(w, businessDate)),
        ],
      ),
    );
  }

  Widget _workerRow(Map<String, dynamic> w, String businessDate) {
    final state = _str(w['state']) ?? 'present';
    final color = _stateColor(state);
    final fromYesterday = _bool(w['from_previous_day']);
    final times = w['attendance_id'] == null
        ? ''
        : 'In ${_clock(_str(w['check_in_time']), businessDate)} · Out ${_clock(_str(w['check_out_time']), businessDate)}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OpsColors.border)),
      ),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_str(w['full_name']) ?? '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(
                [
                  if (_str(w['worker_unique_id']) != null)
                    _str(w['worker_unique_id'])!,
                  if (_str(w['job_position']) != null)
                    _str(w['job_position'])!,
                  if (_shift == null) '${w['shift_type']} shift',
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5, color: OpsColors.muted),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            _Pill(_stateLabels[state] ?? state, color),
            if (fromYesterday) const _Pill('From yesterday', OpsColors.muted),
            if (_str(w['source']) == 'Biometric')
              const _Pill('Biometric', OpsColors.action),
          ]),
        ),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (times.isNotEmpty)
                Text(times,
                    style: const TextStyle(
                        fontSize: 12, color: OpsColors.text)),
              if (_str(w['workflow_status']) != null)
                Text(_str(w['workflow_status'])!,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: _str(w['workflow_status']) == 'Rejected'
                            ? OpsColors.warning
                            : OpsColors.muted)),
            ],
          ),
        ),
      ]),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'on_site':
        return OpsColors.ok;
      case 'on_break':
        return OpsColors.action;
      case 'absent':
        return OpsColors.critical;
      case 'sick':
      case 'not_recorded':
        return OpsColors.warning;
      default:
        return OpsColors.muted;
    }
  }

  Widget _actionRecordsPanel(Map<String, dynamic> data) {
    final rows = _list(data['records_needing_action'])
        .where((r) => _shift == null || r['shift_type'] == _shift)
        .toList();
    const reasonLabels = {
      'awaiting_admin_review': 'Waiting for your review',
      'awaiting_resubmission': 'Rejected — waiting for supervisor',
      'day_not_submitted': 'Day not submitted (still Draft)',
    };
    const reasonColors = {
      'awaiting_admin_review': OpsColors.action,
      'awaiting_resubmission': OpsColors.warning,
      'day_not_submitted': OpsColors.warning,
    };
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      groups.putIfAbsent(_str(r['reason']) ?? 'other', () => []).add(r);
    }
    return _Panel(
      title: 'Attendance needing action',
      subtitle: rows.isEmpty
          ? 'Nothing waiting at this site.'
          : '${rows.length} record(s), oldest first',
      trailing: rows.isEmpty
          ? null
          : TextButton(
              onPressed: () => _go('attendance_review'),
              child: const Text('Open review')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text('${reasonLabels[entry.key] ?? entry.key} (${entry.value.length})',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: reasonColors[entry.key] ?? OpsColors.text)),
            ),
            ...entry.value.take(50).map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(
                        width: 100,
                        child: Text(_day(_str(r['record_date'])),
                            style: const TextStyle(fontSize: 12))),
                    SizedBox(
                        width: 56,
                        child: Text('${r['shift_type']}',
                            style: const TextStyle(
                                fontSize: 12, color: OpsColors.muted))),
                    Expanded(
                      child: Text(
                        '${_str(r['full_name']) ?? '—'} · ${_str(r['attendance_status']) ?? ''}'
                        '${_str(r['admin_rejection_notes']) != null ? ' — “${_str(r['admin_rejection_notes'])}”' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ]),
                )),
            if (entry.value.length > 50)
              Text('+ ${entry.value.length - 50} more',
                  style:
                      const TextStyle(fontSize: 12, color: OpsColors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _transfersPanel(Map<String, dynamic> data) {
    final rows = _list(data['transfers']).where((t) {
      if (_shift == null) return true;
      return t['current_shift_type'] == _shift ||
          t['target_shift_type'] == _shift;
    }).toList();
    return _Panel(
      title: 'Pending transfers',
      subtitle: rows.isEmpty
          ? 'No pending transfer touches this site.'
          : '${rows.length} request(s) waiting for a decision',
      trailing: rows.isEmpty
          ? null
          : TextButton(
              onPressed: () => _go('transfers'), child: const Text('Decide')),
      child: Column(
        children: rows
            .map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    _Pill(
                        t['direction'] == 'outgoing'
                            ? 'Outgoing'
                            : (t['direction'] == 'incoming'
                                ? 'Incoming'
                                : 'Shift change'),
                        t['direction'] == 'outgoing'
                            ? OpsColors.warning
                            : OpsColors.action),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_str(t['worker_name']) ?? '—'}: ${t['current_site_name']} (${t['current_shift_type']}) → ${t['target_site_name']} (${t['target_shift_type']})'
                        ' · effective ${_day(_str(t['effective_date']))}'
                        ' · requested by ${_str(t['requested_by_name']) ?? '—'}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  Widget _biometricPanel(Map<String, dynamic> data) {
    final bio = _map(data['biometric']);
    if (!_bool(bio['available'])) {
      return const _Panel(
        title: 'Biometric review',
        child: Text('Biometric review data is not available.',
            style: TextStyle(color: OpsColors.muted)),
      );
    }
    final businessDate = _str(data['business_date']) ?? '';
    final rows = _list(bio['items'])
        .where((r) => _shift == null || r['shift_type'] == _shift)
        .toList();
    return _Panel(
      title: 'Biometric punches needing review',
      subtitle: rows.isEmpty
          ? 'No unresolved punch is linked to this site.'
          : '${rows.length} punch(es) linked to attendance at this site',
      trailing: rows.isEmpty
          ? null
          : TextButton(
              onPressed: () => _go('biometric_review'),
              child: const Text('Open review')),
      child: Column(
        children: rows
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(
                        width: 110,
                        child: Text(
                            _clock(_str(r['punched_at']), businessDate),
                            style: const TextStyle(fontSize: 12))),
                    SizedBox(
                        width: 44,
                        child: Text('${r['punch_type']}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Text(
                        '${_str(r['full_name']) ?? '—'} · ${r['shift_type']} · ${_str(r['processing_status'])}: ${_str(r['processing_result']) ?? '—'}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  Widget _unassignedPanel(Map<String, dynamic> data) {
    final rows = _list(data['unassigned_attendance']);
    return _Panel(
      title: 'Attendance without an assignment',
      subtitle:
          'Records dated today for workers who have no effective assignment to this site/shift today.',
      trailing: TextButton(
          onPressed: () => _go('assignments'),
          child: const Text('Assignments')),
      child: Column(
        children: rows
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(
                        width: 56,
                        child: Text('${r['shift_type']}',
                            style: const TextStyle(
                                fontSize: 12, color: OpsColors.muted))),
                    Expanded(
                      child: Text(
                          '${_str(r['full_name']) ?? '—'} · ${_str(r['attendance_status']) ?? ''} · ${_str(r['workflow_status']) ?? ''}',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }
}
