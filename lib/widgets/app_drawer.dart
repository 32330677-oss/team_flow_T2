import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import '../screens/analytics_dashboard_screen.dart';
import '../screens/workers_screen.dart';
import '../screens/admin_attendance_screen.dart';
import '../screens/payroll_screen.dart';
import '../screens/project_management_screen.dart';
import '../screens/worker_assignment_screen.dart';
import '../screens/hr_management_screen.dart';
import '../screens/pending_transfers_screen.dart';
import '../screens/staff_attendance_payroll_hub.dart';
import '../screens/supervisor_management_screen.dart';
import '../screens/biometric_processing_screen.dart';
import '../screens/biometric_import_screen.dart';
import '../screens/change_password_screen.dart';
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  static const Color _sidebarColor = Color(0xff1a2a6c);
  static const Color _sidebarAccent = Color(0xfffdbb2d);



void _confirmLogout() {
  final rootContext = ApiConfig.navigatorKey.currentContext;
  if (rootContext == null) return;

  showDialog(
    context: rootContext,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Log Out'),
      content: const Text('Are you sure you want to log out?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            Navigator.pop(ctx);
            ApiConfig.logout();
          },
          child: const Text('Log Out', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

  void _go(BuildContext context, Widget destination) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    final items = <_DrawerItem>[
      _DrawerItem(Icons.dashboard_rounded, 'Dashboard', (ctx) {
        Navigator.pop(ctx);
        Navigator.pushAndRemoveUntil(
          ctx,
          MaterialPageRoute(builder: (_) => const AnalyticsDashboardScreen()),
          (route) => false,
        );
      }),
      _DrawerItem(Icons.engineering_rounded, 'Workers', (ctx) => _go(ctx, const WorkersScreen())),
      _DrawerItem(Icons.fact_check_rounded, 'Attendance Review', (ctx) => _go(ctx, const AdminAttendanceScreen())),
      _DrawerItem(Icons.payments_rounded, 'Payroll', (ctx) => _go(ctx, const PayrollScreen())),
      _DrawerItem(Icons.business_rounded, 'Projects', (ctx) => _go(ctx, const ProjectManagementScreen())),
      _DrawerItem(Icons.alt_route_rounded, 'Worker Distribution', (ctx) => _go(ctx, const WorkerAssignmentScreen())),
      _DrawerItem(Icons.people_alt_rounded, 'HR Management', (ctx) => _go(ctx, const HRManagementScreen())),
      _DrawerItem(Icons.swap_horiz_rounded, 'Transfer Requests', (ctx) => _go(ctx, const PendingTransfersScreen())),
      _DrawerItem(Icons.badge_rounded, 'Staff Attendance & Payroll', (ctx) => _go(ctx, const StaffAttendancePayrollHub())),
      _DrawerItem(Icons.manage_accounts_rounded, 'Supervisors Management', (ctx) => _go(ctx, const SupervisorManagementScreen())),
            _DrawerItem(Icons.fingerprint_rounded, 'Biometric Processing',
          (ctx) => _go(ctx, const BiometricProcessingScreen())),
                _DrawerItem(Icons.upload_file_rounded, 'Biometric Import',
          (ctx) => _go(ctx, const BiometricImportScreen())),
    ];

    return Drawer(
      child: Container(
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
                            'ASIK ENGINEERING CONSTRUCTION',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      children: items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Material(
                              color: Colors.white.withOpacity(0.08),
                              child: InkWell(
                                onTap: () => item.onTap(context),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        item.icon,
                                        color: Colors.white70,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // C-19: password change reachable from every role's menu.
                  ListTile(
                    leading: const Icon(Icons.lock_reset_rounded, color: Colors.white70),
                    title: const Text('Change Password',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Material(
                        color: Colors.red.withOpacity(0.25),
                        child: InkWell(
                          onTap: () {
  Navigator.pop(context);
  _confirmLogout();
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
                                  color: Colors.white,
                                  size: 22,
                                ),
                                SizedBox(width: 14),
                                Text(
                                  'Log Out',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
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
      ),
    );
  }
}

class _DrawerItem {
  final IconData icon;
  final String label;
  final void Function(BuildContext context) onTap;
  _DrawerItem(this.icon, this.label, this.onTap);
}