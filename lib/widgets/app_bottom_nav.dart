import 'package:flutter/material.dart';

// Accent color used for selected state — matches AppColors.primary
const _kSelectedColor = Color(0xFFD32F2F);
const _kUnselectedColor = Color(0xFF6B7280);
const _kIndicatorColor = Color(0x26D32F2F); // primary @ 15 % opacity

/// Shared bottom navigation bar.
/// Non-viewer: 5 tabs — Home, Demand, Udhaar, Suppliers, Customers
/// Viewer:      2 tabs — Home, Demand
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    this.isViewer = false,
    this.onDestinationSelected,
  });

  final int currentIndex;
  final bool isViewer;
  final ValueChanged<int>? onDestinationSelected;

  // Explicit icon colors ensure visibility regardless of theme inheritance.
  static const _sel = IconThemeData(color: _kSelectedColor, size: 24);
  static const _unsel = IconThemeData(color: _kUnselectedColor, size: 24);

  static IconThemeData _it(bool selected) => selected ? _sel : _unsel;

  @override
  Widget build(BuildContext context) {
    if (isViewer) {
      return NavigationBar(
        selectedIndex: currentIndex.clamp(0, 1),
        onDestinationSelected: onDestinationSelected,
        backgroundColor: Colors.white,
        indicatorColor: _kIndicatorColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: const Duration(milliseconds: 250),
        destinations: [
          _dest(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
          _dest(1, Icons.menu_book_outlined, Icons.menu_book_rounded, 'Demand'),
        ],
      );
    }

    return NavigationBar(
      selectedIndex: currentIndex.clamp(0, 4),
      onDestinationSelected: onDestinationSelected,
      backgroundColor: Colors.white,
      indicatorColor: _kIndicatorColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      animationDuration: const Duration(milliseconds: 250),
      destinations: [
        _dest(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
        _dest(1, Icons.menu_book_outlined, Icons.menu_book_rounded, 'Demand'),
        _dest(2, Icons.account_balance_wallet_outlined,
            Icons.account_balance_wallet_rounded, 'Udhaar'),
        _dest(3, Icons.local_shipping_outlined, Icons.local_shipping_rounded,
            'Suppliers'),
        _dest(4, Icons.people_outline_rounded, Icons.people_rounded,
            'Customers'),
      ],
    );
  }

  NavigationDestination _dest(
    int index,
    IconData unselIcon,
    IconData selIcon,
    String label,
  ) {
    return NavigationDestination(
      icon: IconTheme(data: _it(false), child: Icon(unselIcon)),
      selectedIcon: IconTheme(data: _it(true), child: Icon(selIcon)),
      label: label,
    );
  }
}
