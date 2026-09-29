import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:team_flow/constants.dart';
import 'biometric_processing_screen.dart';
import 'login_screen.dart';
import 'project_management_screen.dart';
import 'worker_assignment_screen.dart';
import 'hr_management_screen.dart';
import 'workers_screen.dart';
import 'supervisor_management_screen.dart';
import 'pending_transfers_screen.dart';
import 'staff_attendance_payroll_hub.dart';
import 'payroll_screen.dart';
import 'admin_attendance_screen.dart';
import 'biometric_import_screen.dart';
import 'device_id_mapping_screen.dart';
class DashColors {
  // Dark-mode surface colors: a deeper shade of the app's own navy brand
  // color instead of an unrelated tech-blue palette, so night mode still
  // feels like the same app as the rest of the project.
  static const Color bg = Color(0xFF0E1830);
  static const Color sidebar = Color(0xff1a2a6c);
  static const Color card = Color(0xFF16224A);
  static const Color cardBorder = Color(0xFF2C3B66);

  static const Color textMain = Color(0xFFECEFF6);
  static const Color textMuted = Color(0xFFA9B2C8);

  // Brand accent colors — shared with the rest of the app (login screen
  // gradient, payroll/admin dashboards, status badges) instead of a
  // separate unrelated palette.
  static const Color blue = Color(0xff2a4d8f);

  static const Color green = Color(0xff2e7d32);
  static const Color orange = Color(0xffed6c02);
  static const Color red = Color(0xffb21f1f);
  static const Color purple = Color(0xff6a1b9a);
}

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState
    extends State<AnalyticsDashboardScreen>
    with TickerProviderStateMixin {
  static const Color _sidebarColor = Color(0xff1a2a6c);
  static const Color _sidebarAccent = Color(0xfffdbb2d);

  // Day theme primary blue used by the rest of the project.
  static const Color _dayPrimary = Color(0xff1a2a6c);

  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _isDarkMode = true;

  Map<String, dynamic>? _data;
  String _adminName = 'Admin';

  DateTime _startDate =
      DateTime.now().subtract(const Duration(days: 13));
  DateTime _endDate = DateTime.now();

  Timer? _pulseTimer;
  bool _pulseOn = false;

  late AnimationController _entryController;
  late AnimationController _pulseController;

  final List<_SidebarItem> _items = const [
    _SidebarItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _SidebarItem(icon: Icons.engineering_rounded, label: 'Workers'),
    _SidebarItem(icon: Icons.fact_check_rounded, label: 'Attendance Review'),
    _SidebarItem(icon: Icons.payments_rounded, label: 'Payroll'),
    _SidebarItem(icon: Icons.business_rounded, label: 'Projects'),
    _SidebarItem(
      icon: Icons.alt_route_rounded,
      label: 'Worker Distribution',
    ),
    _SidebarItem(icon: Icons.people_alt_rounded, label: 'HR Management'),
    _SidebarItem(
      icon: Icons.swap_horiz_rounded,
      label: 'Transfer Requests',
    ),
    _SidebarItem(
      icon: Icons.badge_rounded,
      label: 'Staff Attendance & Payroll',
    ),
    _SidebarItem(
      icon: Icons.manage_accounts_rounded,
      label: 'Supervisors Management',
    ),
        _SidebarItem(
      icon: Icons.fingerprint_rounded,
      label: 'Biometric Processing',
    ),
        _SidebarItem(
      icon: Icons.upload_file_rounded,
      label: 'Biometric Import',
    ),
    _SidebarItem(
  icon: Icons.link_rounded,
  label: 'Device ID Mapping',
),
  ];

  Color get _pageBg =>
      _isDarkMode ? DashColors.bg : const Color(0xFFF4F6FB);

  Color get _cardBg =>
      _isDarkMode ? DashColors.card : Colors.white;

  Color get _borderColor =>
      _isDarkMode
          ? DashColors.cardBorder
          : const Color(0xffe5e7eb);

  Color get _mainText =>
      _isDarkMode
          ? DashColors.textMain
          : const Color(0xff1f2937);

  Color get _mutedText =>
      _isDarkMode
          ? DashColors.textMuted
          : const Color(0xff6b7280);

  Color get _gridColor =>
      _isDarkMode
          ? DashColors.cardBorder
          : const Color(0xffe5e7eb);

  Color get _primaryColor =>
      _isDarkMode ? DashColors.blue : _dayPrimary;

  Color get _softPrimary =>
      _primaryColor.withOpacity(_isDarkMode ? 0.14 : 0.08);

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    _pulseTimer = Timer.periodic(
      const Duration(milliseconds: 1300),
      (_) {
        if (mounted) {
          setState(() => _pulseOn = !_pulseOn);
        }
      },
    );

    _loadAdminName();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminName() async {
    final name = await ApiConfig.storage.read(key: 'user_name');

    if (mounted && name != null && name.trim().isNotEmpty) {
      setState(() => _adminName = name.split(' ').first);
    }
  }

  String get _startStr =>
      DateFormat('yyyy-MM-dd').format(_startDate);

  String get _endStr =>
      DateFormat('yyyy-MM-dd').format(_endDate);

  Future<void> _loadDashboardData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await ApiConfig.dio.get(
        '/main-dashboard/overview',
        queryParameters: {
          'start_date': _startStr,
          'end_date': _endStr,
        },
      );

      if (!mounted) return;

      setState(() {
        _data = response.data['data'];
        _isLoading = false;
      });

      _entryController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to load dashboard data.'),
          backgroundColor: DashColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: _endDate,
      ),
      builder: (context, child) {
        return Theme(
          data: _isDarkMode
              ? ThemeData.dark().copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: _primaryColor,
                    surface: DashColors.card,
                  ),
                  dialogTheme: const DialogThemeData(
                    backgroundColor: DashColors.card,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: ColorScheme.light(
                    primary: _dayPrimary,
                    surface: Colors.white,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });

      _loadDashboardData();
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    await ApiConfig.storage.delete(key: 'jwt_token');
    await ApiConfig.storage.delete(key: 'user_role');
    await ApiConfig.storage.delete(key: 'user_id');
    await ApiConfig.storage.delete(key: 'user_name');

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
        (route) => false,
      );
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          'Log Out',
          style: TextStyle(color: _mainText),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: _mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: _mutedText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DashColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout(context);
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _onSelectItem(int index) {
    if (index == 0) {
      setState(() => _selectedIndex = 0);
      return;
    }

    setState(() => _selectedIndex = index);

    Widget destination;

    switch (index) {
      case 1:
        destination = const WorkersScreen();
        break;
      case 2:
        destination = const AdminAttendanceScreen();
        break;
      case 3:
        destination = const PayrollScreen();
        break;
      case 4:
        destination = const ProjectManagementScreen();
        break;
      case 5:
        destination = const WorkerAssignmentScreen();
        break;
      case 6:
        destination = const HRManagementScreen();
        break;
      case 7:
        destination = const PendingTransfersScreen();
        break;
      case 8:
        destination = const StaffAttendancePayrollHub();
        break;
      case 9:
        destination = const SupervisorManagementScreen();
        break;
      case 10:
        destination = const BiometricProcessingScreen();
        break;
      case 11:
        destination = const BiometricImportScreen();
        break;
        case 12:
  destination = const DeviceIdMappingScreen();
  break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destination),
    ).then((_) {
      if (mounted) {
        setState(() => _selectedIndex = 0);
        _loadDashboardData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          return Scaffold(
            backgroundColor: _pageBg,
            body: Row(
              children: [
                _buildSidebar(isPermanent: true),
                Expanded(
                  child: _buildMainContent(
                    showMenuButton: false,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: _pageBg,
          drawer: Drawer(
            backgroundColor: _sidebarColor,
            child: _buildSidebar(isPermanent: false),
          ),
          body: _buildMainContent(
            showMenuButton: true,
          ),
        );
      },
    );
  }

  Widget _buildSidebar({required bool isPermanent}) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: _sidebarColor,
        image: const DecorationImage(
          image: AssetImage(
            'assets/images/sidebar_background.png',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.55),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.group_work_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'ASIK ENGINEERING CONSTRCTION',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Admin Panel',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: _items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isSelected =
                          _selectedIndex == index;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Material(
                          color: isSelected
                              ? Colors.white.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(12),
                            onTap: () {
                              if (!isPermanent) {
                                Navigator.pop(context);
                              }

                              _onSelectItem(index);
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    color: isSelected
                                        ? _sidebarAccent
                                        : Colors.white70,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(12),
                      onTap: () {
                        if (!isPermanent) {
                          Navigator.pop(context);
                        }

                        _confirmLogout(context);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                            SizedBox(width: 14),
                            Text(
                              'Log Out',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent({
    bool showMenuButton = false,
  }) {
    return Container(
      color: _pageBg,
      child: Column(
        children: [
          _buildTopBar(
            showMenuButton: showMenuButton,
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: _primaryColor,
                    ),
                  )
                : _data == null
                    ? Center(
                        child: Text(
                          'No data',
                          style: TextStyle(
                            color: _mutedText,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDashboardData,
                        color: _primaryColor,
                        backgroundColor: _cardBg,
                        child: SingleChildScrollView(
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          padding:
                              const EdgeInsets.fromLTRB(
                            18,
                            18,
                            18,
                            42,
                          ),
                          child: _buildBody(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar({
    bool showMenuButton = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _pageBg,
        border: Border(
          bottom: BorderSide(
            color: _borderColor,
          ),
        ),
      ),
      child: Builder(
        builder: (context) => Row(
          children: [
            if (showMenuButton) ...[
              IconButton(
                icon: Icon(
                  Icons.menu_rounded,
                  color: _mainText,
                ),
                onPressed: () =>
                    Scaffold.of(context).openDrawer(),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(),
                visualDensity:
                    VisualDensity.compact,
              ),
              const SizedBox(width: 12),
            ],

            Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_rounded,
                    color: _primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Dashboard Overview',
                    style: TextStyle(
                      color: _mainText,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              margin:
                  const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius:
                    BorderRadius.circular(10),
                border: Border.all(
                  color: _borderColor,
                ),
              ),
              child: IconButton(
                tooltip: 'Refresh',
                icon: Icon(
                  Icons.refresh_rounded,
                  color: _primaryColor,
                  size: 20,
                ),
                onPressed: _loadDashboardData,
              ),
            ),

            Container(
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius:
                    BorderRadius.circular(10),
                border: Border.all(
                  color: _borderColor,
                ),
              ),
              child: IconButton(
                tooltip: _isDarkMode
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                icon: Icon(
                  _isDarkMode
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: _isDarkMode
                      ? DashColors.orange
                      : _dayPrimary,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _isDarkMode = !_isDarkMode;
                  });
                },
              ),
            ),

            const SizedBox(width: 10),

            CircleAvatar(
              radius: 17,
              backgroundColor: _primaryColor,
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 17,
              ),
            ),

            const SizedBox(width: 8),

            Text(
              _adminName,
              style: TextStyle(
                color: _mainText,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final kpis =
        (_data!['kpis'] as Map?)?.cast<String, dynamic>() ??
            {};

    final liveSites =
        ((_data!['live_sites'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final onLeaveNow =
        ((_data!['on_leave_now'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final attendanceOverview =
        ((_data!['attendance_overview'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final dailyHours =
        ((_data!['daily_hours_series'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final positions =
        ((_data!['workers_by_position'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final topSites =
        ((_data!['top_sites'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final lastPaid =
        _data!['last_paid_payroll'] != null
            ? Map<String, dynamic>.from(
                _data!['last_paid_payroll'],
              )
            : null;

    final latestBatch =
        _data!['latest_payroll_batch'] != null
            ? Map<String, dynamic>.from(
                _data!['latest_payroll_batch'],
              )
            : null;

    final hour = DateTime.now().hour;

    final greeting = hour < 12
        ? 'Good Morning'
        : (hour < 18
            ? 'Good Afternoon'
            : 'Good Evening');

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOut,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _buildHeroHeader(
            greeting,
            kpis,
          ),

          const SizedBox(height: 18),

          _buildKpiGrid(kpis),

          const SizedBox(height: 18),

          _buildOperationalPulse(
            kpis,
            onLeaveNow,
            liveSites,
          ),

          const SizedBox(height: 18),

          _sectionCard(
            title: 'Live Site Operations',
            subtitle:
                'Real-time view of assigned workers and site activity',
            leadingIcon:
                Icons.location_city_rounded,
            child: _liveSitesList(liveSites),
          ),

          const SizedBox(height: 18),

          _sectionCard(
            title: 'Attendance Trend',
            subtitle:
                'Daily workforce attendance for the selected period',
            leadingIcon:
                Icons.bar_chart_rounded,
            legend: [
              _legendDot(
                DashColors.green,
                'Present',
              ),
              _legendDot(
                DashColors.orange,
                'On Leave',
              ),
              _legendDot(
                DashColors.red,
                'Absent',
              ),
            ],
            child: SizedBox(
              height: 250,
              child:
                  _attendanceBarChart(
                attendanceOverview,
              ),
            ),
          ),

          const SizedBox(height: 18),

          _sectionCard(
            title: 'Working Hours',
            subtitle:
                'Regular hours compared with overtime',
            leadingIcon:
                Icons.schedule_rounded,
            legend: [
              _legendDot(
                _primaryColor,
                'Regular Hours',
              ),
              _legendDot(
                DashColors.purple,
                'Overtime Hours',
              ),
            ],
            child: SizedBox(
              height: 225,
              child: _hoursTrendChart(
                dailyHours,
              ),
            ),
          ),

          const SizedBox(height: 18),

          _payrollSection(
            lastPaid,
            latestBatch,
          ),

          const SizedBox(height: 18),

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _sectionCard(
                  title: 'Workers by Position',
                  subtitle:
                      'Current active workforce distribution',
                  leadingIcon:
                      Icons.badge_rounded,
                  child:
                      _positionDonut(positions),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 5,
                child: _sectionCard(
                  title: 'Top Sites by Workforce',
                  subtitle:
                      'Sites with the largest active workforce',
                  leadingIcon:
                      Icons.apartment_rounded,
                  child:
                      _topSitesList(topSites),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          _sectionCard(
            title: 'Quick Actions',
            subtitle:
                'Common administration tasks',
            leadingIcon:
                Icons.flash_on_rounded,
            child: _quickActionsGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(
    String greeting,
    Map<String, dynamic> kpis,
  ) {
    final total =
        _number(kpis['total_workers']);

    final working =
        _number(kpis['currently_working_now']);

    final present =
        _number(kpis['present_today']);

    final leave =
        _number(kpis['on_leave_today']);

    final absent =
        _number(kpis['absent_today']);

    final attendanceRate =
        _double(kpis['attendance_rate']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: _borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              _isDarkMode ? 0.12 : 0.04,
            ),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 720;

          final left = Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _softPrimary,
                      borderRadius:
                          BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.waving_hand_rounded,
                      color: _primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$greeting, $_adminName 👋',
                      style: TextStyle(
                        color: _mainText,
                        fontSize: 22,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 9),

              Text(
                'Here is your live workforce snapshot. '
                'You can quickly see where people are working, '
                'who is away, and which sites need attention.',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 15),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _miniMetric(
                    Icons.groups_rounded,
                    '$total',
                    'Assigned',
                    _primaryColor,
                  ),
                  _miniMetric(
                    Icons.work_history_rounded,
                    '$working',
                    'Working now',
                    DashColors.green,
                  ),
                  _miniMetric(
                    Icons.event_available_rounded,
                    '$present',
                    'Present',
                    DashColors.green,
                  ),
                  _miniMetric(
                    Icons.beach_access_rounded,
                    '$leave',
                    'On leave',
                    DashColors.orange,
                  ),
                  _miniMetric(
                    Icons.person_off_rounded,
                    '$absent',
                    'Absent',
                    DashColors.red,
                  ),
                ],
              ),
            ],
          );

          final right = SizedBox(
            width: compact ? double.infinity : 185,
            child: _attendanceGauge(
              attendanceRate,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                left,
                const SizedBox(height: 20),
                right,
              ],
            );
          }

          return Row(
            crossAxisAlignment:
                CrossAxisAlignment.center,
            children: [
              Expanded(child: left),
              const SizedBox(width: 30),
              right,
            ],
          );
        },
      ),
    );
  }

  Widget _miniMetric(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(
          _isDarkMode ? 0.08 : 0.055,
        ),
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: _mainText,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: _mutedText,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceGauge(
    double rate,
  ) {
    final normalized =
        (rate / 100).clamp(0.0, 1.0);

    return Column(
      children: [
        SizedBox(
          width: 125,
          height: 125,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: 1,
                strokeWidth: 10,
                color: _borderColor,
              ),
              CircularProgressIndicator(
                value: normalized,
                strokeWidth: 10,
                color: _primaryColor,
              ),
              Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Text(
                    '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%',
                    style: TextStyle(
                      color: _mainText,
                      fontSize: 22,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Attendance',
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Selected day',
          style: TextStyle(
            color: _mutedText,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDateRange,
          borderRadius:
              BorderRadius.circular(10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: _softPrimary,
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: _primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '${DateFormat('MMM d').format(_startDate)} — '
                  '${DateFormat('MMM d').format(_endDate)}',
                  style: TextStyle(
                    color: _mainText,
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiGrid(
    Map<String, dynamic> kpis,
  ) {
    final cards = [
      _modernKpiCard(
        icon: Icons.groups_rounded,
        color: _primaryColor,
        title: 'Assigned Workforce',
        value:
            '${kpis['total_workers'] ?? 0}',
        subtitle:
            'Active workers assigned to sites',
        progress: 1,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const WorkersScreen(),
            ),
          );
        },
      ),
      _modernKpiCard(
        icon: Icons.directions_walk_rounded,
        color: DashColors.green,
        title: 'Working Right Now',
        value:
            '${kpis['currently_working_now'] ?? 0}',
        subtitle:
            'Checked in and still active',
        progress: _safeRatio(
          _number(kpis['currently_working_now']),
          _number(kpis['total_workers']),
        ),
      ),
      _modernKpiCard(
        icon: Icons.event_available_rounded,
        color: DashColors.green,
        title: 'Present Today',
        value:
            '${kpis['present_today'] ?? 0}',
        subtitle:
            '${kpis['attendance_rate'] ?? 0}% attendance rate',
        progress: _safeRatio(
          _number(kpis['present_today']),
          _number(kpis['total_workers']),
        ),
      ),
      _modernKpiCard(
        icon: Icons.beach_access_rounded,
        color: DashColors.orange,
        title: 'On Leave Today',
        value:
            '${kpis['on_leave_today'] ?? 0}',
        subtitle:
            'Sick / Vacation / Holiday',
        progress: _safeRatio(
          _number(kpis['on_leave_today']),
          _number(kpis['total_workers']),
        ),
      ),
      _modernKpiCard(
        icon: Icons.person_off_rounded,
        color: DashColors.red,
        title: 'Absent Today',
        value:
            '${kpis['absent_today'] ?? 0}',
        subtitle:
            'Assigned workers not present',
        progress: _safeRatio(
          _number(kpis['absent_today']),
          _number(kpis['total_workers']),
        ),
      ),
      _modernKpiCard(
        icon: Icons.rate_review_rounded,
        color: DashColors.orange,
        title: 'Attendance Review',
        value:
            '${kpis['pending_reviews'] ?? 0}',
        subtitle:
            '${kpis['rejected_records'] ?? 0} rejected records',
        progress: null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const AdminAttendanceScreen(),
            ),
          ).then(
            (_) => _loadDashboardData(),
          );
        },
      ),
    ];

  return LayoutBuilder(
      builder: (context, constraints) {
        int columns;

        if (constraints.maxWidth >= 1150) {
          columns = 3;
        } else if (constraints.maxWidth >= 720) {
          columns = 2;
        } else {
          columns = 1;
        }

        // ارتفاع ثابت مبني على محتوى الكرت نفسه (أيقونة + عنوان + رقم +
        // شريط تقدم)، وليس على عرض الشاشة كالسابق (childAspectRatio)،
        // مع مراعاة تكبير الخط (accessibility) حتى لا يعود الـ overflow
        // لو المستخدم كبّر حجم الخط من إعدادات الجهاز.
        final textScaler = MediaQuery.textScalerOf(context);
        final cardHeight = textScaler.scale(150.0).clamp(150.0, 195.0);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: cardHeight, // بدل childAspectRatio
          ),
          itemBuilder: (_, index) => cards[index],
        );
      },
    );
  }

  Widget _modernKpiCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
    double? progress,
    VoidCallback? onTap,
  }) {
    final child = AnimatedContainer(
      duration:
          const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(
            _isDarkMode ? 0.22 : 0.14,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(
              _isDarkMode ? 0.035 : 0.025,
            ),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.22),
                      color.withOpacity(0.07),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 21,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.more_horiz_rounded,
                color: _mutedText,
                size: 19,
              ),
            ],
          ),

          const SizedBox(height: 11),

          Text(
            title,
            style: TextStyle(
              color: _mutedText,
              fontSize: 11,
              fontWeight:
                  FontWeight.w500,
            ),
          ),

          const SizedBox(height: 2),

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: _mainText,
                  fontSize: 25,
                  fontWeight:
                      FontWeight.bold,
                  height: 1,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 2,
                  ),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 9.5,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(8),
              child:
                  LinearProgressIndicator(
                value: progress.clamp(
                  0.0,
                  1.0,
                ),
                minHeight: 5,
                backgroundColor:
                    _borderColor,
                valueColor:
                    AlwaysStoppedAnimation(
                  color,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      borderRadius:
          BorderRadius.circular(18),
      onTap: onTap,
      child: child,
    );
  }

  Widget _buildOperationalPulse(
    Map<String, dynamic> kpis,
    List<Map<String, dynamic>> onLeaveNow,
    List<Map<String, dynamic>> sites,
  ) {
    final working =
        _number(kpis['currently_working_now']);

    final total =
        _number(kpis['total_workers']);

    final breakNow =
        _number(kpis['on_break_now']);

    final pending =
        _number(kpis['pending_reviews']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 900;

        final pulse = _workforcePulseCard(
          working,
          total,
          breakNow,
        );

      final away = _liveAwayCard(
  onLeaveNow,
  currentlyWorking: working, // working = _number(kpis['currently_working_now'])
);

        final attention =
            _attentionCard(
          pending,
          sites,
        );

        if (compact) {
          return Column(
            children: [
              pulse,
              const SizedBox(height: 12),
              away,
              const SizedBox(height: 12),
              attention,
            ],
          );
        }

  return Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(
      flex: 4,
      child: pulse,
    ),
    const SizedBox(width: 12),
    Expanded(
      flex: 5,
      child: away,
    ),
    const SizedBox(width: 12),
    Expanded(
      flex: 4,
      child: attention,
    ),
  ],
);
      },
    );
  }

  Widget _workforcePulseCard(
    int working,
    int total,
    int breakNow,
  ) {
    final ratio = _safeRatio(
      working,
      total,
    );

    return _smallDashboardCard(
      color: DashColors.green,
      icon: Icons.radar_rounded,
      title: 'WORKFORCE PULSE',
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation:
                    _pulseController,
                builder: (_, __) {
                  final scale =
                      0.92 +
                          (_pulseController
                                  .value *
                              0.10);

                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration:
                          BoxDecoration(
                        shape: BoxShape.circle,
                        color: DashColors
                            .green
                            .withOpacity(
                          0.10 +
                              (_pulseController
                                      .value *
                                  0.08),
                        ),
                        border: Border.all(
                          color: DashColors
                              .green
                              .withOpacity(
                            0.25,
                          ),
                        ),
                      ),
                      child: const Icon(
                        Icons
                            .directions_walk_rounded,
                        color:
                            DashColors.green,
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$working workers',
                      style: TextStyle(
                        color: _mainText,
                        fontSize: 21,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    Text(
                      'are working right now',
                      style: TextStyle(
                        color: _mutedText,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(8),
            child:
                LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor:
                  _borderColor,
              valueColor:
                  const AlwaysStoppedAnimation(
                DashColors.green,
              ),
            ),
          ),

          const SizedBox(height: 7),

          Row(
            children: [
              Text(
                '${(ratio * 100).toStringAsFixed(0)}% of assigned workforce',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 9.5,
                ),
              ),
              const Spacer(),
              if (breakNow > 0)
                Text(
                  '$breakNow on break',
                  style: const TextStyle(
                    color:
                        DashColors.orange,
                    fontSize: 9.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

Widget _liveAwayCard(
  List<Map<String, dynamic>> people, {
  required int currentlyWorking,
}) {
  return _smallDashboardCard(
    color: DashColors.orange,
    icon: Icons.airline_seat_recline_normal_rounded,
    title: 'OUTSIDE SITE NOW',
    child: currentlyWorking == 0
        ? Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _mutedText, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No workers have checked in yet today.',
                  style: TextStyle(color: _mutedText, fontSize: 11),
                ),
              ),
            ],
          )
        : people.isEmpty
            ? Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: DashColors.green, size: 21),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Everyone is currently on site.',
                      style: TextStyle(color: _mutedText, fontSize: 11),
                    ),
                  ),
                ],
              )
            : SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: people.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => _awayPersonChip(people[index]),
                ),
              ),
  );
}
  

  Widget _awayPersonChip(
    Map<String, dynamic> person,
  ) {
    final type =
        person['leave_type']
                ?.toString() ??
            'Break';

    final site =
        person['site_name']
                ?.toString() ??
            'Site';

    final name =
        person['full_name']
                ?.toString() ??
            'Worker';

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final opacity =
            0.12 +
                (_pulseController.value *
                    0.08);

        return Container(
          width: 165,
          padding:
              const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: DashColors.orange
                .withOpacity(opacity),
            borderRadius:
                BorderRadius.circular(12),
            border: Border.all(
              color: DashColors.orange
                  .withOpacity(0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        const BoxDecoration(
                      color:
                          DashColors.orange,
                      shape:
                          BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _mainText,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '$type • $site',
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatTime(
                  person['leave_start_time'],
                ),
                style: const TextStyle(
                  color:
                      DashColors.orange,
                  fontSize: 9,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _attentionCard(
    int pending,
    List<Map<String, dynamic>> sites,
  ) {
    final needsAttention =
        sites.where((s) {
      final working =
          _number(s['currently_working']);

      final assigned =
          _number(s['assigned_workers']);

      final submitted =
          s['is_submitted'] == true;

      return !submitted &&
          assigned > 0 &&
          working == 0;
    }).length;

    return _smallDashboardCard(
      color: pending > 0 ||
              needsAttention > 0
          ? DashColors.orange
          : DashColors.green,
      icon:
          pending > 0 ||
                  needsAttention > 0
              ? Icons.priority_high_rounded
              : Icons.verified_rounded,
      title: 'ADMIN ATTENTION',
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${pending + needsAttention}',
                style: TextStyle(
                  color: _mainText,
                  fontSize: 25,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'items may need your review',
                  style: TextStyle(
                    color: _mutedText,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _attentionLine(
            Icons.fact_check_rounded,
            '$pending attendance reviews',
          ),
          const SizedBox(height: 6),
          _attentionLine(
            Icons.location_off_rounded,
            '$needsAttention site(s) with no active worker',
          ),
        ],
      ),
    );
  }

  Widget _attentionLine(
    IconData icon,
    String text,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color: _mutedText,
          size: 14,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: _mutedText,
              fontSize: 9.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallDashboardCard({
    required Color color,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color: color.withOpacity(
            _isDarkMode ? 0.20 : 0.13,
          ),
        ),
      ),
child: Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            color: color,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    child,
  ],
),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    IconData? leadingIcon,
    List<Widget>? legend,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: _borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              _isDarkMode ? 0.06 : 0.025,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              if (leadingIcon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _softPrimary,
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                  child: Icon(
                    leadingIcon,
                    color: _primaryColor,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _mainText,
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (legend != null)
                Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children: legend,
                ),
            ],
          ),
          const SizedBox(height: 15),
          child,
        ],
      ),
    );
  }

  Widget _legendDot(
    Color color,
    String label,
  ) {
    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: _mutedText,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  Widget _liveSitesList(
    List<Map<String, dynamic>> sites,
  ) {
    if (sites.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(
          vertical: 25,
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off_rounded,
              color: _mutedText,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'No active sites with assigned workers yet.',
              style: TextStyle(
                color: _mutedText,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: sites.map((site) {
            return _liveSiteCard(site);
          }).toList(),
        );
      },
    );
  }

  Widget _liveSiteCard(
    Map<String, dynamic> site,
  ) {
    final assigned =
        _number(site['assigned_workers']);

    final working =
        _number(site['currently_working']);

    final checkedIn =
        _number(site['checked_in_today']);

    final breakNow =
        _number(site['on_break_now']);

    final leave =
        _number(site['on_leave_today']);

    final absent =
        _number(site['absent_today']);

    final submitted =
        site['is_submitted'] == true;

    final activeRatio =
        _safeRatio(working, assigned);

    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    if (checkedIn == 0) {
      statusLabel = 'Not started';
      statusColor = _mutedText;
      statusIcon =
          Icons.schedule_rounded;
    } else if (submitted) {
      statusLabel = 'Day submitted';
      statusColor = _primaryColor;
      statusIcon =
          Icons.check_circle_rounded;
    } else if (working > 0) {
      statusLabel = 'In progress';
      statusColor = DashColors.green;
      statusIcon =
          Icons.play_circle_fill_rounded;
    } else {
      statusLabel =
          'Pending submission';
      statusColor = DashColors.orange;
      statusIcon =
          Icons.pending_actions_rounded;
    }

    return Container(
      margin:
          const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _isDarkMode
            ? DashColors.bg
            : const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: _borderColor,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 650;

          final siteInfo = Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        statusColor.withOpacity(
                      0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      11,
                    ),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    size: 19,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        site['site_name']
                                ?.toString() ??
                            'Site',
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _mainText,
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$working working / $assigned assigned',
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final stats = Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _siteStat(
                      Icons.work_rounded,
                      working,
                      'Working',
                      DashColors.green,
                    ),
                    _siteStat(
                      Icons.coffee_rounded,
                      breakNow,
                      'Break',
                      DashColors.orange,
                    ),
                    _siteStat(
                      Icons.beach_access_rounded,
                      leave,
                      'Leave',
                      DashColors.orange,
                    ),
                    _siteStat(
                      Icons.person_off_rounded,
                      absent,
                      'Absent',
                      DashColors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(8),
                  child:
                      LinearProgressIndicator(
                    value: activeRatio,
                    minHeight: 5,
                    backgroundColor:
                        _borderColor,
                    valueColor:
                        AlwaysStoppedAnimation(
                      statusColor,
                    ),
                  ),
                ),
              ],
            ),
          );

          final status = Container(
            width: compact ? null : 135,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color:
                  statusColor.withOpacity(
                0.09,
              ),
              borderRadius:
                  BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  statusIcon,
                  color: statusColor,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    statusLabel,
                    overflow:
                        TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9.5,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              children: [
                Row(
                  children: [
                    siteInfo,
                    status,
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    stats,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              siteInfo,
              const SizedBox(width: 15),
              stats,
              const SizedBox(width: 15),
              status,
            ],
          );
        },
      ),
    );
  }

  Widget _siteStat(
    IconData icon,
    int value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$value',
              style: TextStyle(
                color: _mainText,
                fontSize: 11,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: _mutedText,
                fontSize: 8.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceBarChart(
    List<Map<String, dynamic>> series,
  ) {
    if (series.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    double maxVal = 1;

    for (final e in series) {
      final present =
          _number(e['present'])
              .toDouble();

      final leave =
          _number(e['on_leave'])
              .toDouble();

      final absent =
          _number(e['absent'])
              .toDouble();

      for (final value in [
        present,
        leave,
        absent,
      ]) {
        if (value > maxVal) {
          maxVal = value;
        }
      }
    }

    const barWidth = 13.0;
    const groupWidth = 82.0;

    final chartWidth =
        series.length * groupWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            chartWidth < constraints.maxWidth
                ? constraints.maxWidth
                : chartWidth;

        return SingleChildScrollView(
          scrollDirection:
              Axis.horizontal,
          child: SizedBox(
            width: width,
            child: BarChart(
              BarChartData(
                maxY:
                    maxVal +
                        (maxVal * 0.25) +
                        1,
                groupsSpace: 22,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine:
                      (v) => FlLine(
                    color: _gridColor,
                    strokeWidth: 1,
                  ),
                ),
                borderData:
                    FlBorderData(
                  show: false,
                ),
                titlesData:
                    FlTitlesData(
                  leftTitles:
                      AxisTitles(
                    sideTitles:
                        SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget:
                          (v, m) => Text(
                        '${v.toInt()}',
                        style:
                            TextStyle(
                          color:
                              _mutedText,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  rightTitles:
                      const AxisTitles(
                    sideTitles:
                        SideTitles(
                      showTitles: false,
                    ),
                  ),
                  topTitles:
                      const AxisTitles(
                    sideTitles:
                        SideTitles(
                      showTitles: false,
                    ),
                  ),
                  bottomTitles:
                      AxisTitles(
                    sideTitles:
                        SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget:
                          (v, m) {
                        final index =
                            v.toInt();

                        if (index < 0 ||
                            index >=
                                series
                                    .length) {
                          return const SizedBox
                              .shrink();
                        }

                        final date =
                            DateTime.parse(
                          series[index]
                              ['date']
                              .toString(),
                        );

                        return Padding(
                          padding:
                              const EdgeInsets
                                  .only(
                            top: 6,
                          ),
                          child: Text(
                            DateFormat(
                              'MMM d',
                            ).format(date),
                            style:
                                TextStyle(
                              color:
                                  _mutedText,
                              fontSize: 9,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups:
                    List.generate(
                  series.length,
                  (i) {
                    final present =
                        _number(
                      series[i]
                          ['present'],
                    ).toDouble();

                    final leave =
                        _number(
                      series[i]
                          ['on_leave'],
                    ).toDouble();

                    final absent =
                        _number(
                      series[i]
                          ['absent'],
                    ).toDouble();

                    return BarChartGroupData(
                      x: i,
                      barsSpace: 5,
                      barRods: [
                        BarChartRodData(
                          toY: present,
                          width: barWidth,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            4,
                          ),
                          color:
                              DashColors
                                  .green,
                        ),
                        BarChartRodData(
                          toY: leave,
                          width: barWidth,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            4,
                          ),
                          color:
                              DashColors
                                  .orange,
                        ),
                        BarChartRodData(
                          toY: absent,
                          width: barWidth,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            4,
                          ),
                          color:
                              DashColors.red,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hoursTrendChart(
    List<Map<String, dynamic>> series,
  ) {
    if (series.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    double maxVal = 1;

    for (final e in series) {
      final regular =
          _double(e['regular_hours']);

      final overtime =
          _double(e['overtime_hours']);

      if (regular > maxVal) {
        maxVal = regular;
      }

      if (overtime > maxVal) {
        maxVal = overtime;
      }
    }

    return BarChart(
      BarChartData(
        maxY:
            maxVal +
                (maxVal * 0.25) +
                1,
        groupsSpace: 14,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine:
              (v) => FlLine(
            color: _gridColor,
            strokeWidth: 1,
          ),
        ),
        borderData:
            FlBorderData(
          show: false,
        ),
        titlesData:
            FlTitlesData(
          leftTitles:
              AxisTitles(
            sideTitles:
                SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget:
                  (v, m) => Text(
                '${v.toInt()}h',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 9,
                ),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(
            sideTitles:
                SideTitles(
              showTitles: false,
            ),
          ),
          topTitles:
              const AxisTitles(
            sideTitles:
                SideTitles(
              showTitles: false,
            ),
          ),
          bottomTitles:
              AxisTitles(
            sideTitles:
                SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval:
                  (series.length / 6)
                      .ceilToDouble()
                      .clamp(1, 999),
              getTitlesWidget:
                  (v, m) {
                final index =
                    v.toInt();

                if (index < 0 ||
                    index >=
                        series.length) {
                  return const SizedBox
                      .shrink();
                }

                final date =
                    DateTime.parse(
                  series[index]
                      ['date']
                      .toString(),
                );

                return Padding(
                  padding:
                      const EdgeInsets
                          .only(
                    top: 6,
                  ),
                  child: Text(
                    DateFormat(
                      'MMM d',
                    ).format(date),
                    style: TextStyle(
                      color:
                          _mutedText,
                      fontSize: 9,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups:
            List.generate(
          series.length,
          (i) {
            final regular =
                _double(
              series[i]
                  ['regular_hours'],
            );

            final overtime =
                _double(
              series[i]
                  ['overtime_hours'],
            );

            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: regular,
                  width:
                      series.length > 10
                          ? 4
                          : 7,
                  borderRadius:
                      BorderRadius
                          .circular(
                    2,
                  ),
                  color:
                      _primaryColor,
                ),
                BarChartRodData(
                  toY: overtime,
                  width:
                      series.length > 10
                          ? 4
                          : 7,
                  borderRadius:
                      BorderRadius
                          .circular(
                    2,
                  ),
                  color:
                      DashColors
                          .purple,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _payrollSection(
    Map<String, dynamic>? lastPaid,
    Map<String, dynamic>? latestBatch,
  ) {
    String money(dynamic value) {
      final amount =
          double.tryParse(
                value?.toString() ?? '0',
              ) ??
              0;

      return '${NumberFormat(
        '#,##0',
        'en_US',
      ).format(amount)} ل.س';
    }

    return _sectionCard(
      title: 'Payroll Snapshot',
      subtitle:
          'Latest payment and current payroll batch',
      leadingIcon:
          Icons.account_balance_wallet_rounded,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          if (lastPaid != null)
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: DashColors
                        .green
                        .withOpacity(0.12),
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: const Icon(
                    Icons
                        .check_circle_rounded,
                    color:
                        DashColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Last Paid Payment',
                        style: TextStyle(
                          color:
                              _mutedText,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        money(
                          lastPaid[
                              'total_amount'],
                        ),
                        style: TextStyle(
                          color: _mainText,
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${lastPaid['period']} • '
                        '${lastPaid['total_workers']} workers'
                        '${lastPaid['paid_date'] != null ? ' • paid ${lastPaid['paid_date']}' : ''}',
                        style: TextStyle(
                          color:
                              _mutedText,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  Icons
                      .info_outline_rounded,
                  color: _mutedText,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No payroll has been marked as paid yet.',
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

          if (latestBatch != null &&
              latestBatch['status'] !=
                  'Paid') ...[
            const Divider(height: 25),
            Container(
              padding:
                  const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DashColors
                    .orange
                    .withOpacity(0.07),
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
                border: Border.all(
                  color: DashColors
                      .orange
                      .withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons
                        .hourglass_bottom_rounded,
                    color:
                        DashColors.orange,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Batch #${latestBatch['batch_id']} '
                      '(${latestBatch['period']}) is '
                      '${latestBatch['status']} — '
                      '${money(latestBatch['total_amount'])} '
                      'for ${latestBatch['total_workers']} workers, '
                      'not yet paid.',
                      style: TextStyle(
                        color: _mainText,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    _primaryColor,
                side: BorderSide(
                  color: _primaryColor
                      .withOpacity(0.35),
                ),
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 13,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const PayrollScreen(),
                  ),
                ).then(
                  (_) =>
                      _loadDashboardData(),
                );
              },
              icon: const Icon(
                Icons.payments_outlined,
                size: 18,
              ),
              label:
                  const Text('Open Payroll'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionDonut(
    List<Map<String, dynamic>> positions,
  ) {
    if (positions.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.all(20),
        child: Text(
          'No data',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    final colors = [
      _primaryColor,
      DashColors.green,
      DashColors.orange,
      DashColors.purple,
      DashColors.red,
      Colors.tealAccent,
      Colors.pinkAccent,
    ];

    final total =
        positions.fold<int>(
      0,
      (sum, e) =>
          sum + _number(e['count']),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 500;

        final chart = SizedBox(
          width: 145,
          height: 145,
          child: Stack(
            alignment:
                Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 39,
                  sections:
                      List.generate(
                    positions.length,
                    (i) {
                      final count =
                          _number(
                        positions[i]
                            ['count'],
                      );

                      return PieChartSectionData(
                        value:
                            count.toDouble(),
                        color: colors[
                            i %
                                colors
                                    .length],
                        radius: 25,
                        showTitle:
                            false,
                      );
                    },
                  ),
                ),
              ),
              Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: TextStyle(
                      color: _mainText,
                      fontSize: 19,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Total',
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final legend = Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children:
              List.generate(
            positions.length,
            (i) {
              final count =
                  _number(
                positions[i]['count'],
              );

              final pct = total > 0
                  ? (count /
                          total *
                          100)
                      .toStringAsFixed(1)
                  : '0.0';

              return Padding(
                padding:
                    const EdgeInsets
                        .symmetric(
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(
                        color: colors[
                            i %
                                colors
                                    .length],
                        shape:
                            BoxShape.circle,
                      ),
                    ),
                    const SizedBox(
                        width: 8),
                    Expanded(
                      child: Text(
                        positions[i]
                                ['position']
                            ?.toString() ??
                            'Other',
                        style:
                            TextStyle(
                          color:
                              _mainText,
                          fontSize: 11,
                        ),
                        overflow:
                            TextOverflow
                                .ellipsis,
                      ),
                    ),
                    Text(
                      '$count ($pct%)',
                      style:
                          TextStyle(
                        color:
                            _mutedText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );

        if (compact) {
          return Column(
            children: [
              chart,
              const SizedBox(height: 12),
              legend,
            ],
          );
        }

        return Row(
          children: [
            chart,
            const SizedBox(width: 16),
            Expanded(child: legend),
          ],
        );
      },
    );
  }

  Widget _topSitesList(
    List<Map<String, dynamic>> sites,
  ) {
    if (sites.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.all(20),
        child: Text(
          'No data',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    final maxCount =
        sites.fold<int>(
      1,
      (max, e) {
        final count =
            _number(e['worker_count']);

        return count > max
            ? count
            : max;
      },
    );

    return Column(
      children: sites.map((site) {
        final count =
            _number(
          site['worker_count'],
        );

        final ratio =
            count / maxCount;

        return Padding(
          padding:
              const EdgeInsets.symmetric(
            vertical: 7,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 105,
                child: Text(
                  site['site_name']
                          ?.toString() ??
                      'Site',
                  style: TextStyle(
                    color: _mainText,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w500,
                  ),
                  overflow:
                      TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    6,
                  ),
                  child:
                      LinearProgressIndicator(
                    value: ratio.clamp(
                      0.0,
                      1.0,
                    ),
                    minHeight: 9,
                    backgroundColor:
                        _borderColor,
                    valueColor:
                        AlwaysStoppedAnimation(
                      _primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$count',
                style: TextStyle(
                  color: _mainText,
                  fontWeight:
                      FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _quickActionsGrid() {
    final actions = [
      _QuickAction(
        Icons.person_add_alt_1_rounded,
        'Add New Worker',
        DashColors.green,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const WorkersScreen(),
            ),
          ).then(
            (_) => _loadDashboardData(),
          );
        },
      ),
      _QuickAction(
        Icons.fact_check_rounded,
        'Review Attendance',
        _primaryColor,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const AdminAttendanceScreen(),
            ),
          ).then(
            (_) => _loadDashboardData(),
          );
        },
      ),
      _QuickAction(
        Icons.account_balance_wallet_rounded,
        'Open Payroll',
        DashColors.orange,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const PayrollScreen(),
            ),
          ).then(
            (_) => _loadDashboardData(),
          );
        },
      ),
      _QuickAction(
        Icons.swap_horiz_rounded,
        'Transfer Requests',
        DashColors.purple,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const PendingTransfersScreen(),
            ),
          ).then(
            (_) => _loadDashboardData(),
          );
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 850
                ? 4
                : constraints.maxWidth >=
                        520
                    ? 2
                    : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio:
                columns == 1 ? 5 : 2.5,
          ),
          itemBuilder: (_, index) {
            final action =
                actions[index];

            return Material(
              color: action.color
                  .withOpacity(
                _isDarkMode
                    ? 0.09
                    : 0.055,
              ),
              borderRadius:
                  BorderRadius.circular(
                13,
              ),
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
                onTap: action.onTap,
                child: Padding(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration:
                            BoxDecoration(
                          color: action
                              .color
                              .withOpacity(
                            0.13,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            9,
                          ),
                        ),
                        child: Icon(
                          action.icon,
                          color:
                              action.color,
                          size: 17,
                        ),
                      ),
                      const SizedBox(
                          width: 9),
                      Expanded(
                        child: Text(
                          action.label,
                          style: TextStyle(
                            color:
                                action.color,
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      Icon(
                        Icons
                            .arrow_forward_ios_rounded,
                        color:
                            action.color
                                .withOpacity(
                          0.55,
                        ),
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _safeRatio(
    int value,
    int total,
  ) {
    if (total <= 0) return 0;
    return (value / total)
        .clamp(0.0, 1.0);
  }

  int _number(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  double _double(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  String _formatTime(dynamic value) {
    if (value == null) {
      return 'Started recently';
    }

    final raw = value.toString();

    try {
      final parsed =
          DateTime.tryParse(raw);

      if (parsed != null) {
        return DateFormat(
          'HH:mm',
        ).format(parsed);
      }
    } catch (_) {}

    if (raw.length >= 16) {
      return raw.substring(11, 16);
    }

    return raw;
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction(
    this.icon,
    this.label,
    this.color,
    this.onTap,
  );
}

class _SidebarItem {
  final IconData icon;
  final String label;

  const _SidebarItem({
    required this.icon,
    required this.label,
  });
}