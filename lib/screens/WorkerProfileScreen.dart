import 'package:flutter/material.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/protected_image.dart';

class WorkerProfileScreen extends StatelessWidget {
  final Map<String, dynamic> worker;

  const WorkerProfileScreen({Key? key, required this.worker}) : super(key: key);

  final Color primaryColor = const Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    final isActive = worker['status'] == 'Active';
    final String? idPhotoUrl = worker['id_photo'];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: const CustomAppBar(title: 'Worker Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. بطاقة التعريف الأساسية (الرأسية)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ProtectedAvatar(
                    url: worker['personal_photo']?.toString(),
                    radius: 35,
                    backgroundColor: primaryColor.withOpacity(0.1),
                    iconColor: primaryColor,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          worker['full_name'] ?? 'No Name',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${worker['worker_unique_id']} | ${worker['job_position'] ?? 'No Position'}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              color: isActive ? Colors.green.shade700 : Colors.red.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. تفاصيل البيانات الشخصية والوظيفية
            const Text('Personal & Job Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildInfoRow(Icons.phone_rounded, 'Phone Number', worker['phone_number']),
                  _buildDivider(),
                  _buildInfoRow(Icons.family_restroom_rounded, "Mother's Name", worker['mothers_name']),
                  _buildDivider(),
                  _buildInfoRow(Icons.flag_rounded, 'Nationality', worker['nationality']),
                  _buildDivider(),
                  _buildInfoRow(Icons.calendar_today_rounded, 'Birth Date', worker['birth_date']?.toString().split('T')[0]),
                  _buildDivider(),
                  _buildInfoRow(Icons.location_city_rounded, 'Birth Place', worker['birth_place']),
                  _buildDivider(),
                  _buildInfoRow(Icons.place_rounded, 'Location / Address', worker['location']),
                  _buildDivider(),
                  _buildInfoRow(Icons.date_range_rounded, 'Hire Date', worker['hire_date']?.toString().split('T')[0]),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. ملاحظات المدير
            if (worker['notes'] != null && worker['notes'].toString().isNotEmpty) ...[
              const Text('Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(worker['notes'], style: TextStyle(color: Colors.grey.shade700)),
              ),
              const SizedBox(height: 16),
            ],
// عدّل الـ class لتصبح StatefulWidget بدل StatelessWidget، أو أضف Fetch منفصل
// أبسط حل: أضف الويدجت التالي مباشرة بالـ build باستخدام FutureBuilder

const SizedBox(height: 16),
const Text('Compensation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
Container(
  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
  child: Column(
    children: [
      _buildInfoRow(Icons.payments_outlined, 'Payment Type', worker['payment_type']?.toString()),
      _buildDivider(),
      if (worker['payment_type'] == 'Daily')
        _buildInfoRow(Icons.calendar_today, 'Daily Rate', worker['daily_rate']?.toString())
      else ...[
        _buildInfoRow(Icons.schedule, 'Regular Hourly Rate', worker['regular_hourly_rate']?.toString()),
        _buildDivider(),
        _buildInfoRow(Icons.timer_outlined, 'Overtime Hourly Rate', worker['overtime_hourly_rate']?.toString()),
      ],
    ],
  ),
),
const SizedBox(height: 12),
FutureBuilder(
  future: ApiConfig.dio.get('/workers/${worker['worker_id']}/compensation-history'),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return const SizedBox.shrink();
    final data = (snapshot.data as dynamic).data['data'] as List;
    if (data.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: const Text('Rate History', style: TextStyle(fontWeight: FontWeight.bold)),
      children: data.map<Widget>((row) {
        final rate = row['payment_type'] == 'Daily'
            ? 'Daily: ${row['daily_rate']}'
            : 'Regular: ${row['regular_hourly_rate']} / OT: ${row['overtime_hourly_rate']}';
        return ListTile(
          dense: true,
          title: Text(rate),
          subtitle: Text(
            '${row['effective_from']} → ${row['effective_to'] ?? 'Present'}\n'
            'Reason: ${row['reason'] ?? '-'} • By: ${row['changed_by_name'] ?? '-'}',
          ),
        );
      }).toList(),
    );
  },
),
            // 4. زر تحميل الهوية بدلاً من عرضها مباشرة
            const Text('ID & Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.picture_as_pdf_rounded, color: primaryColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Worker ID Document',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (idPhotoUrl != null && idPhotoUrl.toString().trim().isNotEmpty)
                              ? 'Click to view ID'
                              : 'No ID provided',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: (idPhotoUrl != null && idPhotoUrl.toString().trim().isNotEmpty && idPhotoUrl.toString().startsWith('http'))
                        ? () => showProtectedImageDialog(context, idPhotoUrl, title: 'ID document')
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: primaryColor),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const Spacer(),
          Text(
            (value != null && value.isNotEmpty) ? value : 'N/A',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, color: Colors.grey.shade100);
  }
}