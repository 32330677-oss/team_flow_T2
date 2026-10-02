import 'package:flutter/material.dart';

/// Small contextual help (§32). Hidden until tapped: a compact info icon that
/// opens a short explanation. Use next to anything a user may not understand
/// (why a button is disabled, what a status means, date rules...).
class HelpTip extends StatelessWidget {
  final String title;
  final String message;
  final double size;
  final Color? color;

  const HelpTip({
    super.key,
    required this.title,
    required this.message,
    this.size = 18,
    this.color,
  });

  static Future<void> show(BuildContext context, String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xff1a2a6c)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message, style: const TextStyle(fontSize: 14, height: 1.45)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: title,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size + 12, minHeight: size + 12),
      icon: Icon(Icons.help_outline_rounded, size: size, color: color ?? Colors.grey.shade600),
      onPressed: () => show(context, title, message),
    );
  }
}

/// Colored pill used for workflow / attendance states.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Workflow state colors shared by supervisor and admin screens.
class WorkflowColors {
  static Color of(String? workflow) {
    switch (workflow) {
      case 'Submitted':
        return Colors.indigo;
      case 'Approved':
        return Colors.green.shade700;
      case 'Rejected':
        return Colors.red.shade700;
      case 'Draft':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }
}

/// Texts reused by several screens so the same rule is explained the same way.
class HelpTexts {
  static const workflow =
      'Draft: saved by the supervisor, can still be changed.\n'
      'Submitted: sent to the Admin for review; the supervisor can no longer change it.\n'
      'Approved: accepted by the Admin; only approved days are paid.\n'
      'Rejected: sent back by the Admin with a reason; correct it and resubmit from Rejected Records.';

  static const futureDates =
      'Attendance can only be recorded for today or past dates. A future date cannot be marked '
      'Absent, Sick, Vacation or Holiday, and cannot be submitted.\n\n'
      'Night shift: a shift is recorded on the date it STARTED. Its check-out may be on the next '
      'calendar day (for example IN 12 Oct 19:00, OUT 13 Oct 05:00) — that is normal.';

  static const previousWeek =
      'A day can only be submitted when the previous week (Saturday to Friday) has no attendance '
      'records still in Draft for this site and shift. Days without any record (for example a Friday '
      'with no work) never block. Submit the listed days first.';

  static const payrollLocked =
      'This date is inside a payroll period that is Finalized or Paid. Normal attendance changes are '
      'locked so the finalized payroll is never changed silently. An Admin can still correct a record '
      'with "Correct attendance" (reason required); the correction is logged and the payroll team sees '
      'it as an open adjustment.';

  static const longShift =
      'The session is unusually long compared with the review threshold set in Attendance Settings. '
      'This is only a warning: it never changes the record or the shift. Check for a forgotten '
      'check-out or a wrong time. The Admin must confirm (or correct) the record before approving it.';

  static const assignmentDates =
      'Start date = first day assigned. Last day = the LAST day the worker is still assigned (it counts). '
      'Example: last day 30 Sep means 30 Sep is an assigned day and 1 Oct is the first day outside.\n\n'
      'Transfer date = FIRST day at the new site; the old assignment automatically ends the day before.';
}

/// Asks for the LAST assigned day (inclusive) before ending an assignment.
/// Returns 'YYYY-MM-DD' or null when cancelled.
Future<String?> pickLastAssignedDay(BuildContext context, {required String title, required String message}) async {
  final now = DateTime.now();
  DateTime picked = DateTime(now.year, now.month, now.day);
  String fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Row(children: [
          Expanded(child: Text(title)),
          const HelpTip(title: 'Assignment dates', message: HelpTexts.assignmentDates),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text('Last assigned day: ${fmt(picked)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: picked,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setD(() => picked = d);
              },
            ),
            const SizedBox(height: 4),
            Text('This day still counts as assigned.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End assignment'),
          ),
        ],
      ),
    ),
  );
  return ok == true ? fmt(picked) : null;
}
