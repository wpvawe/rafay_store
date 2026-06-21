import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/demand_item_model.dart';
import '../../models/udhaar_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/demand_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../providers/udhaar_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _lastBackPress; // double-back-to-exit

  Future<void> _onBack() async {
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      final isViewer = user?.isViewer ?? false;
      context
          .read<DemandProvider>()
          .startListening(currentUserId: user?.uid);
      if (!isViewer) {
        context.read<SupplierProvider>().startListening();
        context.read<UdhaarProvider>().startListening();
        context.read<CustomerProvider>().startListening();
      }
    });
  }


  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good Night';
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    if (h < 21) return 'Good Evening';
    return 'Good Night';
  }

  String _todayDate() {
    const months = [
      'January', 'February', 'March', 'April', 'May',
      'June', 'July', 'August', 'September', 'October',
      'November', 'December',
    ];
    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final demand = context.watch<DemandProvider>();
    final supplier = context.watch<SupplierProvider>();
    final auth = context.watch<AuthProvider>();
    final udhaar = context.watch<UdhaarProvider>();
    final customer = context.watch<CustomerProvider>();

    final isAdmin = auth.currentUser?.isAdmin ?? false;
    final isViewer = auth.currentUser?.isViewer ?? false;
    final userName = auth.currentUser?.name ?? '';

    final pendingCount = demand.pendingCount;
    final urgentCount = demand.urgentCount;
    final urgentItems = demand.urgentItems;
    final totalDemand = demand.totalCount;
    final availableCount = demand.availableCount;
    final deferredCount = demand.deferredCount;
    // ignore: unused_local_variable
    final totalSuppliers = supplier.totalCount;
    // ignore: unused_local_variable
    final totalCustomers = customer.totalCount;
    final pendingUrgentSellTotal = demand.totalPendingUrgentSellPrice;
    final pendingUrgentCostTotal = demand.totalPendingUrgentCostPrice;
    final pendingUrgentWholesaleTotal = demand.totalPendingUrgentWholesalePrice;
    final pendingUrgentCount = demand.pendingUrgentCount;
    final lowStockItems = demand.lowStockItems;
    final outOfStockItems = demand.outOfStockItems;
    final outOfStockCount = demand.outOfStockCount;
    final lowStockCount = demand.lowStockCount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Rafay Store',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
          centerTitle: false,
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings_outlined),
                tooltip: 'User Management',
                onPressed: () => context.push('/admin/users'),
              ),
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.smart_toy_outlined),
                tooltip: 'AI Assistant',
                onPressed: () => context.push('/admin/ai-chat'),
              ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign out',
              onPressed: () => context.read<AuthProvider>().signOut(),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              final user = context.read<AuthProvider>().currentUser;
              final isViewer = user?.isViewer ?? false;
              context.read<DemandProvider>().startListening(currentUserId: user?.uid);
              if (!isViewer) {
                context.read<SupplierProvider>().startListening();
                context.read<UdhaarProvider>().startListening();
                context.read<CustomerProvider>().startListening();
              }
              await Future.delayed(const Duration(milliseconds: 600));
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Hero greeting ─────────────────────────────────
                  _HeroCard(
                    greeting: _greeting(),
                    userName: userName,
                    date: _todayDate(),
                    isViewer: isViewer,
                    isAdmin: isAdmin,
                    pendingCount: pendingCount,
                    urgentCount: urgentCount,
                    totalDemand: totalDemand,
                  ),
                  const SizedBox(height: 20),

                  // ── 2. Key metrics grid ───────────────────────────────
                  const _SectionLabel(label: 'Overview'),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _MetricTile(
                        icon: Icons.menu_book_rounded,
                        label: 'Total\nDemand',
                        value: '$totalDemand',
                        color: Colors.blue.shade700,
                        bgColor: Colors.blue.shade50,
                        onTap: () => context.go('/demand'),
                      ),
                      _MetricTile(
                        icon: Icons.pending_actions_rounded,
                        label: 'Pending',
                        value: '$pendingCount',
                        color: Colors.orange.shade700,
                        bgColor: Colors.orange.shade50,
                        onTap: () {
                          context
                              .read<DemandProvider>()
                              .setStatusFilter(
                                  AppConstants.demandPending);
                          context.go('/demand');
                        },
                      ),
                      _MetricTile(
                        icon: Icons.priority_high_rounded,
                        label: 'Urgent',
                        value: '$urgentCount',
                        color: Colors.red.shade600,
                        bgColor: Colors.red.shade50,
                        onTap: () {
                          context
                              .read<DemandProvider>()
                              .setStatusFilter(
                                  AppConstants.demandUrgent);
                          context.go('/demand');
                        },
                      ),
                      _MetricTile(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Available',
                        value: '$availableCount',
                        color: Colors.green.shade700,
                        bgColor: Colors.green.shade50,
                        onTap: () {
                          context
                              .read<DemandProvider>()
                              .setStatusFilter(
                                  AppConstants.demandAvailable);
                          context.go('/demand');
                        },
                      ),
                      _MetricTile(
                        icon: Icons.hourglass_bottom_rounded,
                        label: 'Deferred',
                        value: '$deferredCount',
                        color: Colors.blueGrey.shade600,
                        bgColor: Colors.blueGrey.shade50,
                        onTap: () {
                          context
                              .read<DemandProvider>()
                              .setStatusFilter(AppConstants.demandDeferred);
                          context.go('/demand');
                        },
                      ),
                      _MetricTile(
                        icon: Icons.check_circle_rounded,
                        label: 'Done %',
                        value: totalDemand > 0
                            ? '${(availableCount * 100 ~/ totalDemand)}%'
                            : '0%',
                        color: Colors.green.shade700,
                        bgColor: Colors.green.shade50,
                        onTap: () {
                          context
                              .read<DemandProvider>()
                              .setStatusFilter(AppConstants.demandAvailable);
                          context.go('/demand');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 3. Pricing Summary (hidden for viewer) ─────────────
                  if (!isViewer && pendingUrgentCount > 0) ...[
                    _PricingSummaryCard(
                      sellTotal: pendingUrgentSellTotal,
                      costTotal: pendingUrgentCostTotal,
                      wholesaleTotal: pendingUrgentWholesaleTotal,
                      pendingUrgentCount: pendingUrgentCount,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 4. Quick Actions (hidden for viewer) ───────────
                  if (!isViewer) ...[
                    const _SectionLabel(label: 'Quick Actions'),
                    const SizedBox(height: 10),
                    _QuickActions(isViewer: isViewer, isAdmin: isAdmin),
                    const SizedBox(height: 20),
                  ],

                  // ── 5. Demand Status Pie Chart ────────────────────────
                  if (totalDemand > 0) ...[
                    const _SectionLabel(label: 'Demand Status'),
                    const SizedBox(height: 10),
                    _DemandPieChartCard(
                      total: totalDemand,
                      pending: pendingCount,
                      available: availableCount,
                      deferred: deferredCount,
                      urgent: urgentCount,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── 6. Urgent Items ───────────────────────────────────
                  if (urgentCount > 0) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.statusUrgent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.priority_high_rounded,
                                  size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('$urgentCount Urgent',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Items',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            context
                                .read<DemandProvider>()
                                .setStatusFilter(
                                    AppConstants.demandUrgent);
                            context.go('/demand');
                          },
                          child: const Text('View all',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...urgentItems.take(3).map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _UrgentItemTile(
                            item: item,
                            hidePrice: isViewer,
                            onTap: () {
                              context
                                  .read<DemandProvider>()
                                  .setStatusFilter(
                                      AppConstants.demandUrgent);
                              context.go('/demand');
                            },
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],

                  // ── 6b. Out of Stock + Low Stock Alerts (hidden for viewer) ──
                  if (!isViewer && (outOfStockCount > 0 || lowStockCount > 0)) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (outOfStockCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB71C1C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                    Icons.remove_shopping_cart_rounded,
                                    size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text('$outOfStockCount Out of Stock',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        if (outOfStockCount > 0 && lowStockCount > 0)
                          const SizedBox(width: 6),
                        if (lowStockCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text('$lowStockCount Low Stock',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.go('/demand'),
                          child: const Text('View all',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Show out-of-stock first, then low-stock
                    ...[
                      ...outOfStockItems,
                      ...lowStockItems,
                    ].take(3).map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _StockAlertTile(
                            item: item,
                            onTap: () => context.go('/demand'),
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],

                  // ── 7. Udhaar Overview ────────────────────────────────
                  if (!isViewer) ...[
                    const _SectionLabel(label: 'Udhaar Overview'),
                    const SizedBox(height: 10),
                    _UdhaarOverviewCard(udhaar: udhaar),
                    const SizedBox(height: 20),

                    if (udhaar.topDebtors.isNotEmpty) ...[
                      Row(
                        children: [
                          const _SectionLabel(label: 'Top Debtors'),
                          const Spacer(),
                          TextButton(
                            onPressed: () => context.go('/udhaar'),
                            child: const Text('View All',
                                style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _TopDebtorsCard(debtors: udhaar.topDebtors),
                      const SizedBox(height: 20),
                    ],
                  ],

                  // ── 8. Recent Udhaar ──────────────────────────────────
                  if (!isViewer && udhaar.recentPending.isNotEmpty) ...[
                    Row(
                      children: [
                        const _SectionLabel(label: 'Recent Udhaar'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.go('/udhaar'),
                          child: const Text('View All',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...udhaar.recentPending.map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _RecentUdhaarTile(
                            entry: entry,
                            onTap: () => context.go('/udhaar'),
                          ),
                        )),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E)),
    );
  }
}

// ── Hero greeting card ────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.greeting,
    required this.userName,
    required this.date,
    required this.isViewer,
    required this.isAdmin,
    required this.pendingCount,
    required this.urgentCount,
    required this.totalDemand,
  });
  final String greeting;
  final String userName;
  final String date;
  final bool isViewer;
  final bool isAdmin;
  final int pendingCount;
  final int urgentCount;
  final int totalDemand;

  @override
  Widget build(BuildContext context) {
    final attentionCount = pendingCount + urgentCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(
                  userName.isNotEmpty ? userName : 'Welcome!',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isAdmin
                            ? 'Admin'
                            : isViewer
                                ? 'Viewer'
                                : 'Editor',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.calendar_today_rounded,
                        color: Colors.white60, size: 12),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(date,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                if (totalDemand > 0) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _HeroStatBadge(
                        label: '$totalDemand items',
                        icon: Icons.menu_book_rounded,
                      ),
                      if (attentionCount > 0)
                        _HeroStatBadge(
                          label: '$attentionCount attention',
                          icon: Icons.notifications_active_rounded,
                          isAlert: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }
}

class _HeroStatBadge extends StatelessWidget {
  const _HeroStatBadge({
    required this.label,
    required this.icon,
    this.isAlert = false,
  });
  final String label;
  final IconData icon;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAlert
            ? Colors.orange.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAlert
              ? Colors.orange.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Animated metric tile ──────────────────────────────────────────────────────
// value may be a plain integer string ("42") or an integer+suffix ("75%").
// When the numeric part changes, TweenAnimationBuilder smoothly counts from
// the previous value to the new one instead of snapping instantly.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  /// Split "75%" → (75.0, "%") or "42" → (42.0, "").
  static (double, String) _parse(String v) {
    final suffix = v.endsWith('%') ? '%' : '';
    final numeric = double.tryParse(v.replaceAll('%', '')) ?? 0;
    return (numeric, suffix);
  }

  @override
  Widget build(BuildContext context) {
    final (target, suffix) = _parse(value);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TweenAnimationBuilder automatically re-animates whenever
                // `end` (= target) changes, smoothly counting to the new value.
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: target),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOut,
                  builder: (_, animVal, __) => Text(
                    '${animVal.round()}$suffix',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: color,
                        height: 1),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Demand Status Pie Chart Card ──────────────────────────────────────────────

class _DemandPieChartCard extends StatelessWidget {
  const _DemandPieChartCard({
    required this.total,
    required this.pending,
    required this.available,
    required this.deferred,
    required this.urgent,
  });
  final int total;
  final int pending;
  final int available;
  final int deferred;
  final int urgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Donut chart
          SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _DonutChartPainter(
                sections: [
                  _PieSection(AppColors.statusPending, pending.toDouble()),
                  _PieSection(
                      AppColors.statusAvailable, available.toDouble()),
                  _PieSection(
                      AppColors.statusDeferred, deferred.toDouble()),
                  _PieSection(AppColors.statusUrgent, urgent.toDouble()),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E)),
                    ),
                    const Text(
                      'Total',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PieLegendRow(
                    label: 'Pending',
                    count: pending,
                    total: total,
                    color: AppColors.statusPending),
                const SizedBox(height: 8),
                _PieLegendRow(
                    label: 'Available',
                    count: available,
                    total: total,
                    color: AppColors.statusAvailable),
                const SizedBox(height: 8),
                _PieLegendRow(
                    label: 'Deferred',
                    count: deferred,
                    total: total,
                    color: AppColors.statusDeferred),
                const SizedBox(height: 8),
                _PieLegendRow(
                    label: 'Urgent',
                    count: urgent,
                    total: total,
                    color: AppColors.statusUrgent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PieLegendRow extends StatelessWidget {
  const _PieLegendRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });
  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151))),
        ),
        Text('$count',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 4),
        Text('($pct%)',
            style:
                const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

class _PieSection {
  final Color color;
  final double value;
  const _PieSection(this.color, this.value);
}

class _DonutChartPainter extends CustomPainter {
  final List<_PieSection> sections;
  const _DonutChartPainter({required this.sections});

  @override
  void paint(Canvas canvas, Size size) {
    final total =
        sections.fold<double>(0, (s, e) => s + e.value);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.36;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    double startAngle = -math.pi / 2;
    const gap = 0.04;

    for (final section in sections) {
      if (section.value == 0) continue;
      final sweepAngle =
          (section.value / total) * 2 * math.pi - gap;
      paint.color = section.color;
      canvas.drawArc(
        Rect.fromCircle(
            center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += (section.value / total) * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.sections != sections;
}

// ── Udhaar Overview Card ──────────────────────────────────────────────────────

class _UdhaarOverviewCard extends StatelessWidget {
  const _UdhaarOverviewCard({required this.udhaar});
  final UdhaarProvider udhaar;

  @override
  Widget build(BuildContext context) {
    final net = udhaar.netBalance;
    final isPositive = net >= 0;

    return GestureDetector(
      onTap: () => context.go('/udhaar'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.indigo,
                      size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Udhaar Ledger',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      Text('Tap to view all entries',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Net: ${isPositive ? '+' : ''}Rs ${net.abs().toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isPositive
                            ? Colors.green.shade700
                            : Colors.red.shade700),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 13, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 14),
            // 3 stat boxes
            Row(
              children: [
                _UdhaarStatBox(
                  label: 'Total Given',
                  value: 'Rs ${udhaar.totalGiven.toStringAsFixed(0)}',
                  icon: Icons.arrow_upward_rounded,
                  color: Colors.red.shade600,
                  bg: Colors.red.shade50,
                ),
                const SizedBox(width: 10),
                _UdhaarStatBox(
                  label: 'Total Received',
                  value:
                      'Rs ${udhaar.totalReceived.toStringAsFixed(0)}',
                  icon: Icons.arrow_downward_rounded,
                  color: Colors.teal.shade600,
                  bg: Colors.teal.shade50,
                ),
                const SizedBox(width: 10),
                _UdhaarStatBox(
                  label: 'Settled',
                  value: '${udhaar.settledCount}',
                  icon: Icons.check_circle_outline_rounded,
                  color: Colors.green.shade600,
                  bg: Colors.green.shade50,
                ),
              ],
            ),
            // Given vs Received progress bar
            if (udhaar.totalGiven > 0 || udhaar.totalReceived > 0) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    if (udhaar.totalGiven > 0)
                      Expanded(
                        flex: udhaar.totalGiven.round().clamp(1, 9999),
                        child: Container(
                            height: 6, color: Colors.red.shade400),
                      ),
                    if (udhaar.totalReceived > 0)
                      Expanded(
                        flex:
                            udhaar.totalReceived.round().clamp(1, 9999),
                        child: Container(
                            height: 6, color: Colors.teal.shade400),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Text('Given (money out)',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600)),
                  ]),
                  Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        color: Colors.teal.shade400),
                    const SizedBox(width: 4),
                    Text('Received (money in)',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600)),
                  ]),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UdhaarStatBox extends StatelessWidget {
  const _UdhaarStatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bg,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── Top Debtors Card ──────────────────────────────────────────────────────────

class _TopDebtorsCard extends StatelessWidget {
  const _TopDebtorsCard({required this.debtors});
  final List<MapEntry<String, double>> debtors;

  @override
  Widget build(BuildContext context) {
    final maxAmount = debtors.isEmpty ? 1.0 : debtors.first.value;
    final rankColors = [
      Colors.amber.shade600,
      Colors.grey.shade500,
      Colors.brown.shade400,
      Colors.blueGrey.shade400,
      Colors.blueGrey.shade300,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: debtors.asMap().entries.map((entry) {
          final rank = entry.key;
          final name = entry.value.key;
          final amount = entry.value.value;
          final pct = maxAmount > 0 ? amount / maxAmount : 0.0;
          final rankColor = rank < rankColors.length
              ? rankColors[rank]
              : Colors.grey.shade400;

          return Padding(
            padding: EdgeInsets.only(
                bottom: rank < debtors.length - 1 ? 12 : 0),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: Text('#${rank + 1}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: rankColor)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary.withValues(alpha: 0.65)),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Rs ${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.red),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.isViewer, required this.isAdmin});
  final bool isViewer;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final buttons = <_ActionButton>[
      if (!isViewer) ...[
        _ActionButton(
          icon: Icons.add_circle_rounded,
          label: '+ Demand',
          color: Colors.blue.shade600,
          bgColor: Colors.blue.shade50,
          onTap: () => context.push('/demand/add'),
        ),
        _ActionButton(
          icon: Icons.label_rounded,
          label: 'Categories',
          color: Colors.purple.shade600,
          bgColor: Colors.purple.shade50,
          onTap: () => context.push('/demand/categories'),
        ),
        _ActionButton(
          icon: Icons.analytics_rounded,
          label: 'Pricing',
          color: Colors.deepPurple.shade600,
          bgColor: Colors.deepPurple.shade50,
          onTap: () => context.push('/demand/pricing'),
        ),
      ],
    ];

    if (!isViewer) {
      buttons.addAll([
        _ActionButton(
          icon: Icons.account_balance_wallet_rounded,
          label: '+ Udhaar',
          color: Colors.indigo.shade600,
          bgColor: Colors.indigo.shade50,
          onTap: () => context.push('/udhaar/add'),
        ),
        _ActionButton(
          icon: Icons.people_rounded,
          label: 'Customers',
          color: Colors.teal.shade600,
          bgColor: Colors.teal.shade50,
          onTap: () => context.go('/customers'),
        ),
        _ActionButton(
          icon: Icons.local_shipping_rounded,
          label: 'Suppliers',
          color: Colors.green.shade600,
          bgColor: Colors.green.shade50,
          onTap: () => context.go('/suppliers'),
        ),
      ]);
    }

    if (isAdmin) {
      buttons.add(_ActionButton(
        icon: Icons.smart_toy_rounded,
        label: 'AI Chat',
        color: Colors.orange.shade700,
        bgColor: Colors.orange.shade50,
        onTap: () => context.push('/admin/ai-chat'),
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            buttons[i],
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Urgent item tile ──────────────────────────────────────────────────────────

class _UrgentItemTile extends StatelessWidget {
  const _UrgentItemTile({required this.item, required this.onTap, this.hidePrice = false});
  final DemandItemModel item;
  final VoidCallback onTap;
  final bool hidePrice;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.statusUrgentBg)),
      color: AppColors.statusUrgentBg,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.priority_high_rounded,
                  size: 16, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    if (item.quantity.isNotEmpty &&
                        item.quantity != '0')
                      Text(item.quantityDisplay,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!hidePrice)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.green.shade700
                            .withValues(alpha: 0.25),
                        width: 1),
                  ),
                  child: Text(
                    item.sellPriceDisplay,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade800),
                  ),
                ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 12, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Recent udhaar tile ────────────────────────────────────────────────────────

class _RecentUdhaarTile extends StatelessWidget {
  const _RecentUdhaarTile({required this.entry, required this.onTap});
  final UdhaarEntryModel entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGiven = entry.isGiven;
    final typeColor =
        isGiven ? Colors.red.shade600 : Colors.teal.shade600;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade200)),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                    isGiven
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: typeColor,
                    size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.personName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(isGiven ? 'Given (you gave)' : 'Received (came in)',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Text(entry.amountDisplay,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: typeColor)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pricing Summary Card ──────────────────────────────────────────────────────

class _PricingSummaryCard extends StatelessWidget {
  const _PricingSummaryCard({
    required this.sellTotal,
    required this.costTotal,
    required this.wholesaleTotal,
    required this.pendingUrgentCount,
  });
  final double sellTotal;
  final double? costTotal;
  final double? wholesaleTotal;
  final int pendingUrgentCount;

  @override
  Widget build(BuildContext context) {
    final profit = costTotal != null ? sellTotal - costTotal! : null;
    final marginPct = profit != null && costTotal! > 0
        ? (profit / costTotal! * 100)
        : null;

    return GestureDetector(
      onTap: () => context.push('/demand/pricing'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade100, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.analytics_rounded,
                      size: 18, color: Colors.green.shade700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pricing Summary',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      Text(
                        'Pending + Urgent ($pendingUrgentCount items)',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Analytics',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 10, color: Colors.green.shade700),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Row 1: Sell | Cost | Wholesale
            Row(
              children: [
                _PriceSummaryTile(
                  label: 'Total Sell',
                  value: 'Rs ${sellTotal.toStringAsFixed(0)}',
                  icon: Icons.sell_rounded,
                  color: Colors.green.shade700,
                  bg: Colors.green.shade50,
                ),
                const SizedBox(width: 10),
                costTotal != null
                    ? _PriceSummaryTile(
                        label: 'Total Cost',
                        value: 'Rs ${costTotal!.toStringAsFixed(0)}',
                        icon: Icons.shopping_cart_rounded,
                        color: Colors.blue.shade700,
                        bg: Colors.blue.shade50,
                      )
                    : _PriceSummaryTile(
                        label: 'Cost',
                        value: 'Not set',
                        icon: Icons.shopping_cart_outlined,
                        color: Colors.grey.shade500,
                        bg: Colors.grey.shade100,
                      ),
                const SizedBox(width: 10),
                wholesaleTotal != null
                    ? _PriceSummaryTile(
                        label: 'Wholesale',
                        value: 'Rs ${wholesaleTotal!.toStringAsFixed(0)}',
                        icon: Icons.local_shipping_outlined,
                        color: Colors.purple.shade700,
                        bg: Colors.purple.shade50,
                      )
                    : _PriceSummaryTile(
                        label: 'Wholesale',
                        value: 'Not set',
                        icon: Icons.local_shipping_outlined,
                        color: Colors.grey.shade500,
                        bg: Colors.grey.shade100,
                      ),
              ],
            ),

            // Row 2: Profit margin (only when cost is set)
            if (profit != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: profit >= 0
                      ? Colors.teal.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.trending_up_rounded,
                        size: 14,
                        color: profit >= 0
                            ? Colors.teal.shade700
                            : Colors.red.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Gross Profit: Rs ${profit.toStringAsFixed(0)}'
                      '${marginPct != null ? '  (${marginPct.toStringAsFixed(1)}% margin)' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: profit >= 0
                            ? Colors.teal.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriceSummaryTile extends StatelessWidget {
  const _PriceSummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bg,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── Stock Alert Tile ──────────────────────────────────────────────────────────

class _StockAlertTile extends StatelessWidget {
  const _StockAlertTile({required this.item, required this.onTap});

  final DemandItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOut = item.isOutOfStock;
    final badgeColor =
        isOut ? const Color(0xFFB71C1C) : Colors.orange.shade700;
    final badgeBg = isOut ? const Color(0xFFFFEBEE) : Colors.orange.shade50;
    final badgeBorder =
        isOut ? const Color(0xFFEF9A9A) : Colors.orange.shade200;
    final badgeLabel = isOut
        ? 'Out of Stock'
        : item.reorderLevel > 0
            ? 'Low: ${item.stock}/${item.reorderLevel}'
            : 'Stock: ${item.stock}';
    final badgeIcon = isOut
        ? Icons.remove_shopping_cart_rounded
        : Icons.warning_amber_rounded;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOut
                ? const Color(0xFFFFCDD2)
                : Colors.orange.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: badgeColor.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left color bar
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),

            // Item info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.quantityDisplay,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),

            // Stock badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, size: 11, color: badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
