import 'package:flutter/material.dart';

/// Shared helper for showing a 15-second floating SnackBar with an UNDO action.
///
/// Usage:
/// ```dart
/// final provider = context.read<DemandProvider>();
/// final snapshot = item; // capture before delete
/// await provider.deleteItem(item.id);
/// if (context.mounted) {
///   UndoSnackbar.show(
///     context,
///     message: '"${item.name}" deleted',
///     onUndo: () => provider.restoreItem(snapshot),
///   );
/// }
/// ```
///
/// The snackbar uses the root [ScaffoldMessenger] so it persists across
/// navigation events (e.g. popping back to a list after deleting on a
/// detail screen).
class UndoSnackbar {
  UndoSnackbar._();

  static void show(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    Duration duration = const Duration(seconds: 15),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: const Color(0xFFFDD835),
            onPressed: onUndo,
          ),
        ),
      );
  }
}
