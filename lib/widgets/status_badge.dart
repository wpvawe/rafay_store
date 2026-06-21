import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Coloured chip that shows a demand item status.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = _resolve(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  (Color, String) _resolve(String s) {
    switch (s) {
      case AppConstants.demandPending:
        return (Colors.orange, 'Pending');
      case AppConstants.demandAvailable:
        return (Colors.green, 'Available');
      case AppConstants.demandDeferred:
        return (Colors.grey, 'Deferred');
      case AppConstants.demandUrgent:
        return (Colors.red, 'Urgent');
      default:
        return (Colors.blueGrey, s);
    }
  }
}
