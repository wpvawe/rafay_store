import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'app_bottom_nav.dart';

class ScaffoldShell extends StatelessWidget {
  const ScaffoldShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  static int indexFromLocation(String location, bool isViewer) {
    if (isViewer) {
      if (location.startsWith('/demand')) return 1;
      return 0;
    }
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/demand')) return 1;
    if (location.startsWith('/udhaar')) return 2;
    if (location.startsWith('/suppliers')) return 3;
    if (location.startsWith('/customers')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isViewer = auth.currentUser?.isViewer ?? false;
    final index = ScaffoldShell.indexFromLocation(location, isViewer);

    // Each tab screen (HomeScreen, DemandListScreen, UdhaarListScreen,
    // SupplierListScreen, CustomerListScreen) has its own PopScope with
    // double-back-to-exit logic. ScaffoldShell just provides the bottom nav.
    return Scaffold(
      body: child,
      bottomNavigationBar: AppBottomNav(
        currentIndex: index,
        isViewer: isViewer,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/home');
            case 1: context.go('/demand');
            case 2 when !isViewer: context.go('/udhaar');
            case 3 when !isViewer: context.go('/suppliers');
            case 4 when !isViewer: context.go('/customers');
          }
        },
      ),
    );
  }
}
