import 'package:flutter/material.dart';

import '../services/biometric_device_mapping_service.dart';
import '../services/biometric_processing_service.dart'
    show BiometricApiException;
import '../widgets/app_data_table.dart';
import '../widgets/custom_app_bar.dart';

class DeviceIdMappingScreen extends StatefulWidget {
  const DeviceIdMappingScreen({super.key});

  @override
  State<DeviceIdMappingScreen> createState() =>
      _DeviceIdMappingScreenState();
}

class _DeviceIdMappingScreenState
    extends State<DeviceIdMappingScreen> {
  final _service = BiometricDeviceMappingService();

  String _entityType = 'Worker';

  List<UnmappedDevice> _devices = [];
  List<AvailableBiometricPerson> _people = [];

  final Map<String, int?> _selectedPeople = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        _service.getUnmappedDevices(),
        _service.getAvailablePeople(_entityType),
      ]);

      if (!mounted) return;

      setState(() {
        _devices = results[0] as List<UnmappedDevice>;
        _people = results[1] as List<AvailableBiometricPerson>;
        _selectedPeople.clear();
        _loading = false;
      });
    } on BiometricApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _changeEntityType(String type) async {
    if (_saving || _entityType == type) return;

    setState(() {
      _entityType = type;
      _loading = true;
      _error = null;
    });

    try {
      final people =
          await _service.getAvailablePeople(type);

      if (!mounted) return;

      setState(() {
        _people = people;
        _selectedPeople.clear();
        _loading = false;
      });
    } on BiometricApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

    String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Default = first punch date, but never before the person's start date.
  String _defaultEffective(UnmappedDevice d, AvailableBiometricPerson p) {
    final first = (d.firstPunch != null && d.firstPunch!.length >= 10)
        ? d.firstPunch!.substring(0, 10)
        : _fmtDate(DateTime.now());
    final start = p.startDate;
    return (start != null && start.compareTo(first) > 0) ? start : first;
  }

  Future<void> _mapDevice(UnmappedDevice device) async {
    final personId = _selectedPeople[device.deviceEmployeeId];
    if (personId == null) {
      _snack('Please select a $_entityType first.', Colors.orange.shade800);
      return;
    }
    final person = _people.firstWhere((p) => p.id == personId);
    String effectiveFrom = _defaultEffective(device, person);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Confirm Device ID Mapping'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Map device ID "${device.deviceEmployeeId}" to ${person.fullName}?\n'
                  'Type: $_entityType • Punches: ${device.punches}'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 16),
                label: Text('Effective from: $effectiveFrom'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.tryParse(effectiveFrom) ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setD(() => effectiveFrom = _fmtDate(picked));
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Punches from this date onward will resolve to this person. '
                'After mapping, run Biometric Processing to process the skipped punches.',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Map')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _service.createMapping(
        deviceEmployeeId: device.deviceEmployeeId,
        entityType: _entityType,
        entityId: person.id,
        effectiveFrom: effectiveFrom,
      );
      if (!mounted) return;
      _snack('Device ID ${device.deviceEmployeeId} mapped from $effectiveFrom.', Colors.green.shade700);
      await _load();
    } on BiometricApiException catch (e) {
      if (!mounted) return;
      _snack(e.message, e.statusCode == 409 ? Colors.orange.shade800 : Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _cut(String? value) {
    if (value == null || value.isEmpty) return '-';

    return value.length > 19
        ? value.substring(0, 19).replaceFirst('T', ' ')
        : value.replaceFirst('T', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Device ID Mapping',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed:
                (_loading || _saving) ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Map biometric device employee IDs to existing Workers or Staff. '
                    'Only unmapped device IDs and currently active available people are shown.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 16),

                  _typeSelector(),

                  const SizedBox(height: 16),

                  if (_error != null)
                    _errorBox(_error!),

                  _summary(),

                  const SizedBox(height: 14),

                  _mappingTable(),
                ],
              ),
            ),
    );
  }

  Widget _typeSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _typeButton(
              'Worker',
              Icons.engineering_outlined,
            ),
          ),
          Expanded(
            child: _typeButton(
              'Staff',
              Icons.badge_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeButton(
    String type,
    IconData icon,
  ) {
    final selected = _entityType == type;

    return FilledButton.icon(
      onPressed:
          _saving ? null : () => _changeEntityType(type),
      style: FilledButton.styleFrom(
        backgroundColor:
            selected ? AppColors.primary : Colors.transparent,
        foregroundColor:
            selected ? Colors.white : AppColors.textPrimary,
        elevation: 0,
      ),
      icon: Icon(icon),
      label: Text(type),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(
          color: Colors.red.shade200,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.fingerprint,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_devices.length} unmapped device ID'
              '${_devices.length == 1 ? '' : 's'} • '
              '${_people.length} available $_entityType'
              '${_people.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mappingTable() {
    return AppDataTableCard(
      title: 'Unmapped Device IDs',
      subtitle:
          'Select an active $_entityType for each device ID.',
      icon: Icons.fingerprint_rounded,
      accentColor: AppColors.primary,
      emptyMessage: 'No unmapped device IDs found.',
      columns:  [
        DataColumn(label: Text('  Device ID')),
        DataColumn(label: Text('  Punches')),
        DataColumn(label: Text('  First Punch')),
        DataColumn(label: Text('  Last Punch')),
        DataColumn(label: Text('  $_entityType')),
        DataColumn(label: Text('  Action')),
      ],
      rows: _devices.map(_deviceRow).toList(),
    );
  }

  DataRow _deviceRow(UnmappedDevice device) {
    Widget pad(Widget child) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      );
    }

    return DataRow(
      cells: [
        DataCell(
          pad(
            Text(
              device.deviceEmployeeId,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(
          pad(Text('${device.punches}')),
        ),
        DataCell(
          pad(Text(_cut(device.firstPunch))),
        ),
        DataCell(
          pad(Text(_cut(device.lastPunch))),
        ),
        DataCell(
          pad(
            SizedBox(
              width: 250,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value:
                      _selectedPeople[device.deviceEmployeeId],
                  hint: Text(
                    'Select $_entityType',
                  ),
                  items: _people.map((person) {
                    final label = person.position == null
                        ? '${person.fullName} (${person.uniqueId})'
                        : '${person.fullName} • ${person.position}';

                    return DropdownMenuItem<int>(
                      value: person.id,
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() {
                            _selectedPeople[
                                device.deviceEmployeeId] = value;
                          });
                        },
                ),
              ),
            ),
          ),
        ),
        DataCell(
          pad(
            FilledButton(
              onPressed:
                  _saving ? null : () => _mapDevice(device),
              child: const Text('Map'),
            ),
          ),
        ),
      ],
    );
  }
}