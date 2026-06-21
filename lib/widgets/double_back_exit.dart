import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps [child] with double-back-to-exit behaviour.
///
/// First back press → shows "Press back again to exit" snackbar.
/// Second back press (within 2 s) → exits the app via [SystemNavigator.pop].
///
/// Usage:
/// ```dart
/// return DoubleBackExit(child: Scaffold(...));
/// ```
class DoubleBackExit extends StatefulWidget {
  const DoubleBackExit({super.key, required this.child});
  final Widget child;

  @override
  State<DoubleBackExit> createState() => _DoubleBackExitState();
}

class _DoubleBackExitState extends State<DoubleBackExit> {
  DateTime? _lastBackPress;

  Future<bool> _onBack() async {
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return true;
    }
    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: widget.child,
    );
  }
}
