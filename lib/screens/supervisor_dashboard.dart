import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'rejected_records_screen.dart';
import 'transfer_request_screen.dart';
import 'login_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'site_attendance_screen.dart';
import 'change_password_screen.dart';

class SupervisorDashboard extends StatefulWidget {
  final int supervisorId;
  final String supervisorName;

  const SupervisorDashboard({
    super.key,
    required this.supervisorId,
    required this.supervisorName,
  });

  @override
  _SupervisorDashboardState createState() => _SupervisorDashboardState();
}

class _SupervisorDashboardState extends State<SupervisorDashboard> {
  bool _isLoading = true;
  List<dynamic> _sites = [];

  @override
  void initState() {
    super.initState();
    _fetchSupervisorSites();
  }

  Future<void> _fetchSupervisorSites() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/sites/my-sites');
      List sitesList = [];
      if (response.data is List) {
        sitesList = response.data;
      } else if (response.data is Map && response.data['data'] != null) {
        sitesList = response.data['data'];
      }
      
      setState(() {
        _sites = sitesList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load sites: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate = DateFormat('yyyy/MM/dd').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xfff8f9fa),
      appBar: AppBar(
        backgroundColor: const Color(0xff1a2a6c),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, ${widget.supervisorName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(formattedDate, style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.normal)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
            tooltip: 'Rejected Records',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RejectedRecordsScreen())),
          ),
        ],
      ),

      // Sidebar / Drawer Navigation
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(widget.supervisorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              accountEmail: Text('Supervisor ID: ${widget.supervisorId}', style: const TextStyle(color: Colors.white70)),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 36, color: Color(0xff1a2a6c)),
              ),
              decoration: const BoxDecoration(color: Color(0xff1a2a6c)),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_rounded, color: Color(0xff1a2a6c)),
              title: const Text('My Sites Dashboard', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              title: const Text('Rejected Records', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RejectedRecordsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded, color: Color(0xff1a2a6c)),
              title: const Text('Worker Transfer Request', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransferRequestScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded, color: Color(0xff1a2a6c)),
              title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () async {
                const storage = FlutterSecureStorage();
                await storage.deleteAll();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),

      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xff1a2a6c)))
          : _sites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off_rounded, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('No sites assigned to you currently', style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select a site to manage attendance:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c)),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _sites.length,
                          itemBuilder: (context, index) {
                            final site = _sites[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                           onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SiteAttendanceScreen(
        siteId: site['site_id'],
        siteName: site['site_name'] ?? 'Site',
        shiftType: site['my_shift_type'] ?? 'Day', // ← جديد
      ),
    ),
  );
},
                                  child: Padding(
                                    padding: const EdgeInsets.all(18.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xff1a2a6c).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: const Icon(Icons.location_on_rounded, color: Color(0xff1a2a6c), size: 28),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                site['site_name'] ?? 'Site',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xff1a2a6c)),
                                              ),
                                              const SizedBox(height: 4),
                              Text(
  site['location'] ?? 'Tap to manage workers and attendance',
  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
),
if (site['supports_shifts'] == 1)
  Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
    child: Text(
      '${site['my_shift_type'] ?? 'Day'} Shift',
      style: TextStyle(color: Colors.indigo.shade700, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}