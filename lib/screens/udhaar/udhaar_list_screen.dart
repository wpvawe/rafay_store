import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/udhaar_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/udhaar_provider.dart';
import '../../screens/udhaar/contact_ledger_screen.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/undo_snackbar.dart';

class UdhaarListScreen extends StatefulWidget {
  const UdhaarListScreen({super.key});

  @override
  State<UdhaarListScreen> createState() => _UdhaarListScreenState();
}

class _UdhaarListScreenState extends State<UdhaarListScreen> {
  final _searchCtrl = TextEditingController();
  DateTime? _lastBackPress; // double-back-to-exit

  // Stored reference so dispose() can removeListener without context.read.
  UdhaarProvider? _udhaarProv;

  // Clears the initial shimmer on the first data notification from the provider,
  // instead of relying on an arbitrary Future.delayed timer.
  void _clearLoading() {
    if (_loading && mounted) {
      setState(() => _loading = false);
      _udhaarProv?.removeListener(_clearLoading);
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

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _udhaarProv = context.read<UdhaarProvider>();
      _udhaarProv!.addListener(_clearLoading);
      _udhaarProv!.startListening();
    });
  }

  @override
  void dispose() {
    _udhaarProv?.removeListener(_clearLoading);
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Immediately deletes the entry and shows a 15-second UNDO snackbar.
  Future<void> _deleteWithUndo(
      BuildContext ctx, UdhaarEntryModel entry) async {
    final provider = ctx.read<UdhaarProvider>();
    await provider.deleteEntry(entry.id);
    if (ctx.mounted) {
      UndoSnackbar.show(
        ctx,
        message: '"${entry.personName}" entry deleted',
        onUndo: () => provider.restoreEntry(entry),
      );
    }
  }

  Future<void> _confirmSettle(
      BuildContext ctx, UdhaarEntryModel entry) async {
    final user = ctx.read<AuthProvider>().currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: Colors.green, size: 22),
            SizedBox(width: 8),
            Text('Mark as Settled'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark "${entry.personName}" as settled?'),
            const SizedBox(height: 6),
            _InfoRow(
                icon: Icons.currency_rupee_rounded,
                label: entry.amountDisplay,
                color: entry.isGiven
                    ? Colors.red.shade600
                    : Colors.teal.shade600),
            _InfoRow(
                icon: entry.isGiven
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                label: entry.isGiven
                    ? 'Given ↑'
                    : 'Received ↓',
                color: Colors.grey.shade600),
            const SizedBox(height: 8),
            Text(
              'This will mark the debt as cleared. You can still view it under the "Settled" filter.',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Settle'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );
    if (confirmed == true && ctx.mounted) {
      await ctx
          .read<UdhaarProvider>()
          .settleEntry(entry: entry, settledBy: user);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('"${entry.personName}" marked as settled ✅'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final udhaar = context.watch<UdhaarProvider>();
    final auth = context.watch<AuthProvider>();
    final isViewer = auth.currentUser?.isViewer ?? false;
    final items = udhaar.items;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Udhaar Khata'),
        actions: [
          if (!isViewer)
            IconButton(
              icon: const Icon(Icons.filter_list_off_rounded),
              tooltip: 'Clear filters',
              onPressed: () {
                _searchCtrl.clear();
                udhaar.clearFilters();
                setState(() {});
              },
            ),
        ],
      ),
      floatingActionButton: isViewer
          ? null
          : FloatingActionButton.extended(
              heroTag: 'udhaar_fab',
              onPressed: () => context.push('/udhaar/add'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Entry'),
              shape: const StadiumBorder(),
            ),
      body: SafeArea(
        child: Column(
          children: [
            _SummaryCard(udhaar: udhaar),

            if (!isViewer)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              udhaar.setQuery('');
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onChanged: (v) {
                    udhaar.setQuery(v);
                    setState(() {});
                  },
                ),
              ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All (${udhaar.totalCount})',
                      selected: udhaar.statusFilter == null && udhaar.typeFilter == null,
                      onTap: () {
                        udhaar.setStatusFilter(null);
                        udhaar.setTypeFilter(null);
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Pending (${udhaar.pendingCount})',
                      selected: udhaar.statusFilter ==
                          AppConstants.udhaarPending,
                      selectedColor: Colors.orange,
                      onTap: () => udhaar
                          .setStatusFilter(AppConstants.udhaarPending),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Settled (${udhaar.settledCount})',
                      selected: udhaar.statusFilter ==
                          AppConstants.udhaarSettled,
                      selectedColor: Colors.green,
                      onTap: () => udhaar
                          .setStatusFilter(AppConstants.udhaarSettled),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Given ↑ (${udhaar.givenCount})',
                      selected: udhaar.typeFilter == AppConstants.udhaarGiven,
                      selectedColor: Colors.red.shade600,
                      onTap: () {
                        udhaar.setStatusFilter(null);
                        udhaar.setTypeFilter(
                          udhaar.typeFilter == AppConstants.udhaarGiven
                              ? null
                              : AppConstants.udhaarGiven,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Received ↓ (${udhaar.receivedCount})',
                      selected: udhaar.typeFilter == AppConstants.udhaarReceived,
                      selectedColor: Colors.teal.shade600,
                      onTap: () {
                        udhaar.setStatusFilter(null);
                        udhaar.setTypeFilter(
                          udhaar.typeFilter == AppConstants.udhaarReceived
                              ? null
                              : AppConstants.udhaarReceived,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 4),

            Expanded(
              child: _loading
                  ? _buildShimmer()
                  : items.isEmpty
                      ? _EmptyState(
                          hasFilter: udhaar.statusFilter != null ||
                              udhaar.typeFilter != null ||
                              udhaar.query.isNotEmpty,
                          onClear: () {
                            _searchCtrl.clear();
                            udhaar.clearFilters();
                            setState(() {});
                          },
                          isViewer: isViewer,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: items.length,
                          itemBuilder: (ctx, i) {
                            final entry = items[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _EntryCard(
                                entry: entry,
                                isViewer: isViewer,
                                onTap: (isViewer || entry.isSettled)
                                    ? null
                                    : () => context.push('/udhaar/edit',
                                        extra: entry),
                                onSettle: (entry.isSettled || isViewer)
                                    ? null
                                    : () => _confirmSettle(ctx, entry),
                                onDelete: isViewer
                                    ? null
                                    : () => _deleteWithUndo(ctx, entry),
                                onViewLedger: entry.hasContact
                                    ? () {
                                        final contactName = entry.personName;
                                        final contactType =
                                            entry.contactType ??
                                                AppConstants
                                                    .contactTypeCustomer;
                                        ctx.push(
                                          '/contact/ledger',
                                          extra: ContactLedgerArgs(
                                            contactId: entry.contactId!,
                                            contactName: contactName,
                                            contactType: contactType,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerLoading(
          child: ShimmerBox(
            width: double.infinity,
            height: 100,
            borderRadius: 12,
          ),
        ),
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.udhaar});
  final UdhaarProvider udhaar;

  @override
  Widget build(BuildContext context) {
    final net = udhaar.netBalance;
    final netColor =
        net >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(
              label: 'Given',
              value: 'Rs ${udhaar.totalGiven.toStringAsFixed(0)}',
              color: Colors.red.shade600,
              icon: Icons.arrow_upward_rounded,
            ),
          ),
          Container(width: 1, height: 48, color: Colors.grey.shade200),
          Expanded(
            child: _SummaryItem(
              label: 'Received',
              value: 'Rs ${udhaar.totalReceived.toStringAsFixed(0)}',
              color: Colors.teal.shade600,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
          Container(width: 1, height: 48, color: Colors.grey.shade200),
          Expanded(
            child: _SummaryItem(
              label: 'Balance',
              value:
                  '${net >= 0 ? '+' : ''}Rs ${net.abs().toStringAsFixed(0)}',
              color: netColor,
              icon: Icons.account_balance_wallet_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color)),
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center),
      ],
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final color = selectedColor ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white,
          border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: 1.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: selected ? color : Colors.grey.shade700)),
      ),
    );
  }
}

// ── Entry card ────────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.isViewer,
    this.onTap,
    this.onSettle,
    this.onDelete,
    this.onViewLedger,
  });

  final UdhaarEntryModel entry;
  final bool isViewer;
  final VoidCallback? onTap;
  final VoidCallback? onSettle;
  final VoidCallback? onDelete;
  final VoidCallback? onViewLedger;

  Color get _typeColor => entry.isGiven
      ? Colors.red.shade600
      : Colors.teal.shade600;

  Color get _typeBgColor => entry.isGiven
      ? Colors.red.shade50
      : Colors.teal.shade50;

  Color get _statusColor =>
      entry.isSettled ? Colors.green.shade700 : Colors.orange.shade700;

  Color get _statusBgColor =>
      entry.isSettled ? Colors.green.shade50 : Colors.orange.shade50;

  @override
  Widget build(BuildContext context) {
    final isSettled = entry.isSettled;

    final card = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: isSettled
                  ? Colors.green.shade100
                  : Colors.grey.shade200)),
      color: isSettled ? Colors.green.shade50.withValues(alpha: 0.3) : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: name + amount ──────────────────────────────
              Row(
                children: [
                  // Settled icon indicator
                  if (isSettled) ...[
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      entry.personName,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isSettled
                              ? Colors.grey.shade600
                              : Colors.black87),
                    ),
                  ),
                  Text(
                    entry.amountDisplay,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isSettled
                            ? Colors.grey.shade500
                            : _typeColor),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Badges + date ───────────────────────────────────────
              Row(
                children: [
                  _Badge(
                      label: entry.isGiven ? 'Given ↑' : 'Received ↓',
                      color: isSettled
                          ? Colors.grey.shade500
                          : _typeColor,
                      bgColor: isSettled
                          ? Colors.grey.shade100
                          : _typeBgColor),
                  const SizedBox(width: 6),
                  _Badge(
                      label: isSettled ? 'Settled' : 'Pending',
                      color: _statusColor,
                      bgColor: _statusBgColor),
                  const Spacer(),
                  Text(
                    _formatDate(entry.createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),

              // ── Settled date row ────────────────────────────────────
              if (isSettled && entry.settledAt != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.event_available_rounded,
                        size: 12, color: Colors.green.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Settled on ${_formatDate(entry.settledAt!)}'
                        '${entry.lastEditedBy.name.isNotEmpty ? ' · by ${entry.lastEditedBy.name}' : ''}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade600,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // ── Notes ───────────────────────────────────────────────
              if (entry.notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(entry.notes,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],

              // ── Read-only hint for settled entries ──────────────────
              if (isSettled && !isViewer) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Settled — read only',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic),
                    ),
                    const Spacer(),
                    if (onDelete != null)
                      GestureDetector(
                        onTap: onDelete,
                        child: Text(
                          'Delete',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ],

              // ── Action buttons (pending only) ───────────────────────
              if (!isSettled && !isViewer) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onViewLedger != null)
                      TextButton.icon(
                        icon: const Icon(
                            Icons.history_rounded,
                            size: 14),
                        label: const Text('History',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        onPressed: onViewLedger,
                      ),
                    if (onViewLedger != null) const SizedBox(width: 4),
                    if (onSettle != null)
                      TextButton.icon(
                        icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16),
                        label: const Text('Settle',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        onPressed: onSettle,
                      ),
                    if (onSettle != null) const SizedBox(width: 8),
                    if (onDelete != null)
                      TextButton.icon(
                        icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 16),
                        label: const Text('Delete',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        onPressed: onDelete,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // Dismissible swipe-to-delete only for pending entries to avoid accidents
    if (isViewer || isSettled) return card;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (onDelete == null) return false;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 22),
                SizedBox(width: 8),
                Text('Delete Entry'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Delete "${entry.personName}" entry of ${entry.amountDisplay}?'),
                const SizedBox(height: 6),
                Text(
                  'You can undo this action for 15 seconds after deletion.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dCtx, false),
                  child: const Text('Cancel')),
              FilledButton.icon(
                icon: const Icon(Icons.delete_rounded, size: 16),
                label: const Text('Delete'),
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dCtx, true),
              ),
            ],
          ),
        );
        if (confirmed == true) onDelete!();
        return false; // Never auto-dismiss — _deleteWithUndo handles it
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12)),
        child:
            const Icon(Icons.delete_outline_rounded, color: Colors.red),
      ),
      child: card,
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour > 12
        ? dt.hour - 12
        : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$min $ampm';
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.label,
      required this.color,
      required this.bgColor});
  final String label;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

// ── Small info row used in settle dialog ──────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasFilter,
    required this.onClear,
    required this.isViewer,
  });
  final bool hasFilter;
  final VoidCallback onClear;
  final bool isViewer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter
                  ? Icons.search_off_rounded
                  : Icons.menu_book_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? 'No entries match your filter'
                  : 'No udhaar entries yet',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try adjusting your search or clearing filters.'
                  : isViewer
                      ? 'Udhaar entries will appear here once added.'
                      : 'Tap + to add your first udhaar entry.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade600),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.filter_list_off_rounded,
                    size: 16),
                label: const Text('Clear Filters'),
                onPressed: onClear,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
