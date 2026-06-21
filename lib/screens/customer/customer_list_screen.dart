import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/customer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/udhaar_provider.dart';
import '../../screens/udhaar/contact_ledger_screen.dart';
import '../../widgets/shimmer_loading.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  DateTime? _lastBackPress; // double-back-to-exit

  // Stored reference so dispose() can removeListener without context.read.
  CustomerProvider? _customerProv;

  // Clears the initial shimmer on the first data notification from the provider,
  // instead of relying on an arbitrary Future.delayed timer.
  void _clearLoading() {
    if (_loading && mounted) {
      setState(() => _loading = false);
      _customerProv?.removeListener(_clearLoading);
    }
  }

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
      _customerProv = context.read<CustomerProvider>();
      _customerProv!.addListener(_clearLoading);
      _customerProv!.startListening();
    });
  }

  @override
  void dispose() {
    _customerProv?.removeListener(_clearLoading);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openLedger(BuildContext ctx, CustomerModel c) {
    ctx.push(
      '/contact/ledger',
      extra: ContactLedgerArgs(
        contactId: c.id,
        contactName: c.name,
        contactType: AppConstants.contactTypeCustomer,
        contactPhone: c.phone.isNotEmpty ? c.phone : null,
        contactWhatsapp:
            c.whatsappNumber.isNotEmpty ? c.whatsappNumber : null,
      ),
    );
  }

  void _editCustomer(BuildContext ctx, CustomerModel c) {
    ctx.push('/customer/edit', extra: c);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final auth = context.watch<AuthProvider>();
    final udhaar = context.watch<UdhaarProvider>();
    final isViewer = auth.currentUser?.isViewer ?? false;
    final customers = provider.customers;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          if (provider.query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.filter_list_off_rounded),
              tooltip: 'Clear search',
              onPressed: () {
                _searchCtrl.clear();
                provider.setQuery('');
                setState(() {});
              },
            ),
        ],
      ),
      floatingActionButton: isViewer
          ? null
          : FloatingActionButton.extended(
              heroTag: 'customer_fab',
              onPressed: () => context.push('/customer/add'),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add Customer'),
              shape: const StadiumBorder(),
            ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SearchBar(
                controller: _searchCtrl,
                hintText: 'Search by name, phone, address…',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor:
                    WidgetStatePropertyAll(Colors.grey.shade100),
                side: WidgetStatePropertyAll(
                    BorderSide(color: Colors.grey.shade200)),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                trailing: [
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        provider.setQuery('');
                        setState(() {});
                      },
                    ),
                ],
                onChanged: (v) {
                  provider.setQuery(v);
                  setState(() {});
                },
              ),
            ),

            // ── Summary / count row ───────────────────────────────────
            if (!_loading && provider.totalCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
                child: Row(
                  children: [
                    Icon(Icons.people_outline,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      provider.query.isNotEmpty
                          ? '${customers.length} of ${provider.totalCount} customers'
                          : '${provider.totalCount} customer${provider.totalCount == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

            // ── Hint row ──────────────────────────────────────────────
            if (!isViewer)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to see udhaar history • Long press to edit',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 4),

            // ── List ──────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? _buildShimmer()
                  : customers.isEmpty
                      ? _EmptyState(
                          hasSearch: provider.query.isNotEmpty,
                          isViewer: isViewer,
                          onClear: () {
                            _searchCtrl.clear();
                            provider.setQuery('');
                            setState(() {});
                          },
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            provider.stopListening();
                            provider.startListening();
                            await Future.delayed(
                                const Duration(milliseconds: 600));
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: customers.length,
                            itemBuilder: (ctx, i) {
                              final c = customers[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _CustomerCard(
                                  customer: c,
                                  isViewer: isViewer,
                                  pendingBalance:
                                      udhaar.pendingBalanceForContact(c.id),
                                  onTap: () => _openLedger(ctx, c),
                                  onLongPress: isViewer
                                      ? null
                                      : () => _editCustomer(ctx, c),
                                  onEdit: isViewer
                                      ? null
                                      : () => _editCustomer(ctx, c),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      ), // close child: Scaffold
    ); // close PopScope
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerLoading(
          child: ShimmerBox(
              width: double.infinity, height: 80, borderRadius: 12),
        ),
      ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.isViewer,
    required this.pendingBalance,
    this.onTap,
    this.onLongPress,
    this.onEdit,
  });
  final CustomerModel customer;
  final bool isViewer;
  final double pendingBalance;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final hasPhone =
        customer.phone.isNotEmpty || customer.whatsappNumber.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.blue.shade50,
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue.shade700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    if (hasPhone) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (customer.whatsappNumber.isNotEmpty) ...[
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 12, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text(customer.whatsappNumber,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600)),
                          ] else ...[
                            Icon(Icons.phone_outlined,
                                size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(customer.phone,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600)),
                          ],
                        ],
                      ),
                    ],
                    if (customer.address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(customer.address,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                    if (pendingBalance != 0) ...[
                      const SizedBox(height: 5),
                      _BalanceBadge(balance: pendingBalance),
                    ],
                  ],
                ),
              ),
              if (!isViewer) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 12,
                                color: Colors.blue.shade600),
                            const SizedBox(width: 3),
                            Text(
                              'Ledger',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_outlined,
                                size: 12,
                                color: Colors.grey.shade600),
                            const SizedBox(width: 3),
                            Text(
                              'Edit',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Balance badge ─────────────────────────────────────────────────────────────

class _BalanceBadge extends StatelessWidget {
  const _BalanceBadge({required this.balance});
  final double balance;

  @override
  Widget build(BuildContext context) {
    final isPositive = balance > 0;
    final color = isPositive ? Colors.red.shade600 : Colors.teal.shade600;
    final bgColor = isPositive ? Colors.red.shade50 : Colors.teal.shade50;
    final label = isPositive
        ? 'Baaki: Rs ${balance.abs().toStringAsFixed(0)}'
        : 'Wapas: Rs ${balance.abs().toStringAsFixed(0)}';
    final icon = isPositive
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasSearch,
    required this.isViewer,
    required this.onClear,
  });
  final bool hasSearch;
  final bool isViewer;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (hasSearch) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('No customers found',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: onClear, child: const Text('Clear search')),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline_rounded,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No customers yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          if (!isViewer)
            Text('Tap + to add your first customer',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
