import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/supplier_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../providers/udhaar_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/shimmer_loading.dart';
import '../udhaar/contact_ledger_screen.dart';

class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({super.key});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  DateTime? _lastBackPress; // double-back-to-exit

  // Stored reference so dispose() can removeListener without context.read.
  SupplierProvider? _supplierProv;

  // Clears the initial shimmer on the first data notification from the provider,
  // instead of relying on an arbitrary Future.delayed timer.
  void _clearLoading() {
    if (_loading && mounted) {
      setState(() => _loading = false);
      _supplierProv?.removeListener(_clearLoading);
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
      _supplierProv = context.read<SupplierProvider>();
      // If provider already has data (started before screen opened), clear immediately
      if (_supplierProv!.totalCount > 0 || _supplierProv!.error != null) {
        setState(() => _loading = false);
      } else {
        _supplierProv!.addListener(_clearLoading);
        // 3-second fallback in case stream never fires a new event
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _loading) setState(() => _loading = false);
        });
      }
      _supplierProv!.startListening();
    });
  }

  @override
  void dispose() {
    _supplierProv?.removeListener(_clearLoading);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchPhone(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open dialler')));
      }
    }
  }

  Future<void> _launchWhatsApp(BuildContext context, String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
    String intl = cleaned;
    if (intl.startsWith('0') && intl.length == 11) {
      intl = '92${intl.substring(1)}';
    } else if (intl.startsWith('3') && intl.length == 10) {
      intl = '92$intl';
    }
    final uri = Uri.parse('https://wa.me/$intl');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SupplierProvider>();
    final auth = context.watch<AuthProvider>();
    final canEdit = auth.canEdit;
    final totalCount = prov.totalCount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              heroTag: 'supplier_fab',
              onPressed: () => context.push('/supplier/add'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add Supplier'),
              shape: const StadiumBorder(),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, number…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          prov.setQuery('');
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              onChanged: (v) {
                prov.setQuery(v);
                setState(() {});
              },
            ),
          ),

          // Total count header
          if (!_loading && totalCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
              child: Row(
                children: [
                  Icon(Icons.people_outline, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text(
                    prov.query.isNotEmpty
                        ? '${prov.suppliers.length} of $totalCount suppliers'
                        : '$totalCount supplier${totalCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          Expanded(child: _buildList(context, prov)),
        ],
      ),
      ),
    );
  }

  Widget _buildList(BuildContext context, SupplierProvider prov) {
    // Must call watch before any early returns so Flutter consistently
    // tracks this dependency regardless of loading/error state.
    final udhaar = context.watch<UdhaarProvider>();

    if (_loading) {
      return ShimmerList(count: 5, itemBuilder: (_, __) => const SupplierItemShimmer());
    }

    if (prov.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            Text(prov.error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                prov.clearError();
                prov.startListening();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (prov.suppliers.isEmpty) {
      return EmptyState(
        message: prov.query.isNotEmpty
            ? 'No suppliers match "${prov.query}".'
            : 'No suppliers found.\nTap + to add one.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async => prov.startListening(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: prov.suppliers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final SupplierModel s = prov.suppliers[i];
          return _SupplierCard(
            supplier: s,
            pendingBalance: udhaar.pendingBalanceForContact(s.id),
            onTap: () => context.push('/supplier/detail', extra: s),
            onCall: s.phoneNumber.isNotEmpty ? () => _launchPhone(context, s.phoneNumber) : null,
            onWhatsApp: s.whatsappNumber.isNotEmpty ? () => _launchWhatsApp(context, s.whatsappNumber) : null,
            onLedger: () => context.push(
              '/contact/ledger',
              extra: ContactLedgerArgs(
                contactId: s.id,
                contactName: s.name,
                contactType: AppConstants.contactTypeSupplier,
                contactPhone: s.phoneNumber.isNotEmpty ? s.phoneNumber : null,
                contactWhatsapp: s.whatsappNumber.isNotEmpty ? s.whatsappNumber : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.pendingBalance,
    required this.onTap,
    required this.onLedger,
    this.onCall,
    this.onWhatsApp,
  });

  final SupplierModel supplier;
  final double pendingBalance;
  final VoidCallback onTap;
  final VoidCallback onLedger;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                radius: 22,
                child: Text(
                  supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                  style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (supplier.company.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(supplier.company, style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w500)),
                    ],
                    if (supplier.productsSupplied.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(supplier.productsSupplied, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                    if (pendingBalance != 0) ...[
                      const SizedBox(height: 4),
                      _SupplierBalanceBadge(balance: pendingBalance),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (onWhatsApp != null) ...[
                          _ContactButton(icon: Icons.chat_rounded, label: 'WhatsApp', color: const Color(0xFF25D366), onTap: onWhatsApp!),
                          const SizedBox(width: 6),
                        ],
                        if (onCall != null) ...[
                          _ContactButton(icon: Icons.call_rounded, label: 'Call', color: theme.colorScheme.primary, onTap: onCall!),
                          const SizedBox(width: 6),
                        ],
                        _ContactButton(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Ledger',
                          color: Colors.indigo.shade600,
                          onTap: onLedger,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierBalanceBadge extends StatelessWidget {
  const _SupplierBalanceBadge({required this.balance});
  final double balance;

  @override
  Widget build(BuildContext context) {
    final isPositive = balance > 0;
    final color = isPositive ? Colors.orange.shade700 : Colors.teal.shade600;
    final bgColor = isPositive ? Colors.orange.shade50 : Colors.teal.shade50;
    final label = isPositive
        ? 'Baaki: Rs ${balance.abs().toStringAsFixed(0)}'
        : 'Wapas: Rs ${balance.abs().toStringAsFixed(0)}';
    final icon = isPositive
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

class _ContactButton extends StatelessWidget {
  const _ContactButton({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
