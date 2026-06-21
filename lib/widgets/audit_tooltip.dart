import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/demand_item_model.dart';

/// Shows "Added by X on DATE · Last edited by Y on DATE" in a tooltip.
class AuditTooltip extends StatelessWidget {
  const AuditTooltip({
    super.key,
    required this.addedBy,
    required this.lastEditedBy,
    required this.child,
  });

  final AuditRef addedBy;
  final AuditRef lastEditedBy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy, h:mm a');
    final message =
        'Added by ${addedBy.name} on ${fmt.format(addedBy.at)}\n'
        'Last edited by ${lastEditedBy.name} on ${fmt.format(lastEditedBy.at)}';

    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: child,
    );
  }
}
