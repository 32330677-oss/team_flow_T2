import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'login_screen.dart';
import 'staff_supervisor_attendance_screen.dart';
import 'change_password_screen.dart';

class StaffSupervisorDashboard extends StatelessWidget {
  final int supervisorId;
  final String supervisorName;

  const StaffSupervisorDashboard({
    super.key,
    required this.supervisorId,
    required this.supervisorName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff1a2a6c),
        title: Text('Welcome, $supervisorName'),
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(supervisorName),
              accountEmail: Text(
                'Staff Supervisor ID: $supervisorId',
              ),
              decoration: const BoxDecoration(
                color: Color(0xff1a2a6c),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded, color: Color(0xff1a2a6c)),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.logout,
                color: Colors.red,
              ),
              title: const Text('Logout'),
              onTap: () async {
                const storage = FlutterSecureStorage();
                await storage.deleteAll();

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                  (r) => false,
                );
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(
            Icons.fact_check_rounded,
            color: Colors.white,
          ),
          label: const Text(
            'Take Staff Attendance',
            style: TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff1a2a6c),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const StaffSupervisorAttendanceScreen(),
            ),
          ),
        ),
      ),
    );
  }
}