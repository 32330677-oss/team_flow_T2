
import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import '../widgets/custom_app_bar.dart';

class ContractSitesScreen extends StatefulWidget {
  final int contractId;
  final String contractName;

  const ContractSitesScreen({
    super.key,
    required this.contractId,
    required this.contractName,
  });

  @override
  State<ContractSitesScreen> createState() => _ContractSitesScreenState();
}

class _ContractSitesScreenState extends State<ContractSitesScreen> {
  late final String _apiUrl;
  late final String _supervisorsUrl;

  List _sites = [];
  List _supervisors = [];

  bool _isLoading = true;
  bool _isLoadingSupervisors = false;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiUrl = '/sites';
    _supervisorsUrl = '/users/supervisors';
    _fetchSites();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _fetchSites() async {
    setState(() => _isLoading = true);

    try {
      final response = await ApiConfig.dio.get(
        '$_apiUrl/contract/${widget.contractId}',
      );

      if (response.data['status'] == 'success') {
        setState(() {
          _sites = response.data['data'];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load contract sites'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchActiveSupervisors() async {
    setState(() => _isLoadingSupervisors = true);

    try {
      final response = await ApiConfig.dio.get(_supervisorsUrl);

      if (response.data['status'] == 'success') {
        setState(() {
          _supervisors = (response.data['data'] as List)
              .where((supervisor) => supervisor['status'] == 'Active')
              .toList();

          _isLoadingSupervisors = false;
        });
      } else {
        setState(() => _isLoadingSupervisors = false);
      }
    } catch (e) {
      setState(() => _isLoadingSupervisors = false);
      print("🚨 Error fetching supervisors: $e");
    }
  }
Future<void> _saveSite({
  int? siteId,
  int? existingSupervisorId,
  bool supportsShifts = false,
}) async {
  if (!_formKey.currentState!.validate()) return;

  try {
    final data = {
      'site_name': _nameController.text.trim(),
      'location': _detailsController.text.trim(),
      'contract_id': widget.contractId,
      'supervisor_id': existingSupervisorId,
      'supports_shifts': supportsShifts ? 1 : 0,
    };

    if (siteId == null) {
      await ApiConfig.dio.post(
        _apiUrl,
        data: data,
      );
    } else {
      await ApiConfig.dio.put(
        '$_apiUrl/$siteId',
        data: data,
      );
    }

    Navigator.pop(context);

    _nameController.clear();
    _detailsController.clear();

    await _fetchSites();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          siteId == null
              ? 'Site created successfully!'
              : 'Site updated successfully!',
        ),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Operation failed'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  Future<void> _updateSiteStatus(
    int siteId,
    String newStatus,
  ) async {
    try {
      final response = await ApiConfig.dio.patch(
        '$_apiUrl/$siteId/status',
        data: {
          'status': newStatus,
        },
      );

      if (response.data['status'] == 'success') {
        await _fetchSites();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Site status updated to $newStatus'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update site status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // SHIFT SUPERVISORS
  // ============================================================

  Future<List<Map<String, dynamic>>> _fetchSiteShifts(
    int siteId,
  ) async {
    try {
      final response = await ApiConfig.dio.get(
        '$_apiUrl/$siteId/shifts',
      );

      if (response.data['status'] == 'success') {
        return (response.data['data'] as List)
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      return [];
    } catch (e) {
      print("🚨 Error fetching site shifts: $e");
      rethrow;
    }
  }

  Future<void> _saveShiftSupervisor({
    required int siteId,
    required String shiftType,
    required int? supervisorId,
  }) async {
    await ApiConfig.dio.put(
      '$_apiUrl/$siteId/shifts',
      data: {
        'shift_type': shiftType,
        'supervisor_id': supervisorId,
      },
    );
  }

  Future<void> _showShiftSupervisorsDialog(
    Map site,
  ) async {
    final int siteId = site['site_id'];

    await _fetchActiveSupervisors();

    if (!mounted) return;

    bool isLoading = true;
    bool isSaving = false;

    int? daySupervisorId;
    int? nightSupervisorId;

    try {
      final shifts = await _fetchSiteShifts(siteId);

      for (final shift in shifts) {
        final shiftType = shift['shift_type'];
        final supervisorId = shift['supervisor_id'];

        if (shiftType == 'Day') {
          daySupervisorId = supervisorId;
        } else if (shiftType == 'Night') {
          nightSupervisorId = supervisorId;
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load shift supervisors'),
          backgroundColor: Colors.red,
        ),
      );

      return;
    } finally {
      isLoading = false;
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Shift Supervisors',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 6),

                    Text(
                      site['site_name'] ?? '',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

                    if (isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Day Shift Supervisor',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.wb_sunny_outlined,
                            color: Colors.orange,
                          ),
                        ),
                        value: daySupervisorId,
                        hint: const Text('Select supervisor'),
                        items: _supervisors.map((supervisor) {
                          return DropdownMenuItem<int>(
                            value: supervisor['user_id'],
                            child: Text(
                              supervisor['full_name'] ??
                                  supervisor['username'] ??
                                  '',
                            ),
                          );
                        }).toList(),
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setModalState(() {
                                  daySupervisorId = value;
                                });
                              },
                      ),

                      const SizedBox(height: 14),

                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Night Shift Supervisor',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.nightlight_outlined,
                            color: Colors.indigo,
                          ),
                        ),
                        value: nightSupervisorId,
                        hint: const Text('Select supervisor'),
                        items: _supervisors.map((supervisor) {
                          return DropdownMenuItem<int>(
                            value: supervisor['user_id'],
                            child: Text(
                              supervisor['full_name'] ??
                                  supervisor['username'] ??
                                  '',
                            ),
                          );
                        }).toList(),
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setModalState(() {
                                  nightSupervisorId = value;
                                });
                              },
                      ),

                      const SizedBox(height: 20),

                      ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setModalState(() {
                                  isSaving = true;
                                });

                                try {
                                  await _saveShiftSupervisor(
                                    siteId: siteId,
                                    shiftType: 'Day',
                                    supervisorId: daySupervisorId,
                                  );

                                  await _saveShiftSupervisor(
                                    siteId: siteId,
                                    shiftType: 'Night',
                                    supervisorId: nightSupervisorId,
                                  );

                                  if (!context.mounted) return;

                                  Navigator.pop(context);

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Shift supervisors updated successfully',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } catch (e) {
                                  setModalState(() {
                                    isSaving = false;
                                  });

                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Failed to update shift supervisors',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffb21f1f),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Shift Supervisors',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

void _showSiteDialog({
  Map? site,
}) async {
  await _fetchActiveSupervisors();

  if (!mounted) return;

  _nameController.text =
      site != null ? site['site_name'] ?? '' : '';

  _detailsController.text =
      site != null ? site['location'] ?? '' : '';

  int? selectedSupervisorId =
      site != null ? site['supervisor_id'] : null;

  bool supportsShifts =
      site != null &&
      (site['supports_shifts'] == 1 ||
          site['supports_shifts'] == true);

  bool isSaving = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(20),
      ),
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  site == null
                      ? 'Add Site to ${widget.contractName}'
                      : 'Edit Site',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 15),

                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Site Name / Sector *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty
                          ? 'Please enter site name'
                          : null,
                ),

                const SizedBox(height: 12),

                TextFormField(
                  controller: _detailsController,
                  decoration: const InputDecoration(
                    labelText: 'Location Address or Details',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),

                // فقط عند إنشاء Site جديد
                if (site == null) ...[
                  const SizedBox(height: 12),

                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: supportsShifts,
                    title: const Text(
                      'Supports Day/Night shifts',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Enable this for sites that have Day and Night shifts.',
                    ),
                    secondary: const Icon(
                      Icons.schedule,
                      color: Colors.indigo,
                    ),
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setModalState(() {
                              supportsShifts = value ?? false;

                              // New shift site does not use
                              // the single site supervisor.
                              if (supportsShifts) {
                                selectedSupervisorId = null;
                              }
                            });
                          },
                  ),
                ],

                // Single supervisor only for normal sites
                if (!supportsShifts) ...[
                  const SizedBox(height: 12),

                  _isLoadingSupervisors
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                            labelText: 'Assign Supervisor',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(
                              Icons.person,
                              color: Colors.orange,
                            ),
                          ),
                          value: selectedSupervisorId,
                          hint: const Text(
                            'Select a supervisor (Optional)',
                          ),
                          items: _supervisors.map((supervisor) {
                            return DropdownMenuItem<int>(
                              value: supervisor['user_id'],
                              child: Text(
                                supervisor['full_name'] ??
                                    supervisor['username'] ??
                                    '',
                              ),
                            );
                          }).toList(),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setModalState(() {
                                    selectedSupervisorId = value;
                                  });
                                },
                        ),
                ],

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!_formKey.currentState!.validate()) {
                            return;
                          }

                          setModalState(() {
                            isSaving = true;
                          });

                          try {
                            await _saveSite(
                              siteId: site?['site_id'],
                              existingSupervisorId:
                                  selectedSupervisorId,
                              supportsShifts: supportsShifts,
                            );
                          } finally {
                            if (context.mounted) {
                              setModalState(() {
                                isSaving = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffb21f1f),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          site == null
                              ? 'Save Site'
                              : 'Update Site',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Active':
        return Colors.green.shade800;
      case 'Suspended':
        return Colors.orange.shade800;
      case 'Completed':
        return Colors.grey.shade700;
      default:
        return Colors.black87;
    }
  }

  Color _getStatusBgColor(String? status) {
    switch (status) {
      case 'Active':
        return Colors.green.shade100;
      case 'Suspended':
        return Colors.orange.shade100;
      case 'Completed':
        return Colors.grey.shade300;
      default:
        return Colors.grey.shade200;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Sites: ${widget.contractName}',
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSiteDialog(),
        backgroundColor: const Color(0xffb21f1f),
        child: const Icon(
          Icons.add,
          color: Colors.white,
        ),
      ),

      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _sites.isEmpty
              ? const Center(
                  child: Text(
                    'No sites registered for this contract yet',
                    style: TextStyle(fontSize: 15),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _sites.length,
                  itemBuilder: (context, index) {
                    final site = _sites[index];

                    final currentStatus =
                        site['site_status'] ?? 'Active';

                    final bool supportsShifts =
                        site['supports_shifts'] == 1 ||
                        site['supports_shifts'] == true;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(
                        vertical: 6,
                      ),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),

                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),

                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                site['site_name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            if (supportsShifts)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius:
                                      BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  'Shifts',
                                  style: TextStyle(
                                    color: Colors.indigo,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),

                  subtitle: Padding(
  padding: const EdgeInsets.only(
    top: 4.0,
  ),
  child: Text(
    supportsShifts
        ? 'Location: ${site['location'] ?? 'N/A'}\n'
          'Day Supervisor: ${site['day_supervisor_name'] ?? 'Not assigned'}\n'
          'Night Supervisor: ${site['night_supervisor_name'] ?? 'Not assigned'}'
        : 'Location: ${site['location'] ?? 'N/A'}\n'
          'Supervisor: ${site['supervisor_name'] ?? 'Not assigned'}',
  ),
),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _getStatusBgColor(
                                  currentStatus,
                                ),
                                borderRadius:
                                    BorderRadius.circular(6),
                              ),
                              child: Text(
                                currentStatus,
                                style: TextStyle(
                                  color:
                                      _getStatusColor(
                                    currentStatus,
                                  ),
                                  fontWeight:
                                      FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),

                            const SizedBox(width: 4),

                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showSiteDialog(
                                    site: site,
                                  );
                                } else if (value ==
                                    'shift_supervisors') {
                                  _showShiftSupervisorsDialog(
                                    site,
                                  );
                                } else if (value == 'Active' ||
                                    value == 'Suspended' ||
                                    value == 'Completed') {
                                  _updateSiteStatus(
                                    site['site_id'],
                                    value,
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Edit Site'),
                                    ],
                                  ),
                                ),

                                if (supportsShifts)
                                  const PopupMenuItem(
                                    value: 'shift_supervisors',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.schedule,
                                          size: 18,
                                          color: Colors.indigo,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Shift Supervisors',
                                        ),
                                      ],
                                    ),
                                  ),

                                const PopupMenuDivider(),

                                const PopupMenuItem(
                                  value: 'Active',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Set Active'),
                                    ],
                                  ),
                                ),

                                const PopupMenuItem(
                                  value: 'Suspended',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.pause_circle,
                                        color: Colors.orange,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Set Suspended'),
                                    ],
                                  ),
                                ),

                                const PopupMenuItem(
                                  value: 'Completed',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.done_all,
                                        color: Colors.grey,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Set Completed'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}