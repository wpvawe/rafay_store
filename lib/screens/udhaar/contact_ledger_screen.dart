import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/udhaar_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/udhaar_provider.dart';
import '../../widgets/undo_snackbar.dart';
import 'add_edit_udhaar_screen.dart';

/// Args passed via GoRouter `extra` to this screen.
class ContactLedgerArgs {
  final String contactId;
  final String contactName;
  final String contactType; // AppConstants.contactTypeCustomer | contactTypeSupplier
  final String? contactPhone;
  final String? contactWhatsapp;

  const ContactLedgerArgs({
    required this.contactId,
    required this.contactName,
    required this.contactType,
    this.contactPhone,
    this.contactWhatsapp,
  });

  bool get isCustomer => contactType == AppConstants.contactTypeCustomer;
  bool get hasPhone =>
      (contactPhone != null && contactPhone!.isNotEmpty) ||
      (contactWhatsapp != null && contactWhatsapp!.isNotEmpty);

  bool get hasWhatsApp =>
      contactWhatsapp != null && contactWhatsapp!.isNotEmpty;
}

/// Per-contact udhaar ledger.
/// Shows full history, running balance, quick-dial actions, and allows adding new entries.
class ContactLedgerScreen extends StatefulWidget {
  const ContactLedgerScreen({super.key, required this.args});
  final ContactLedgerArgs args;

  @override
  State<ContactLedgerScreen> createState() => _ContactLedgerScreenState();
}

class _ContactLedgerScreenState extends State<ContactLedgerScreen> {
  String _filter = 'all'; // 'all' | 'pending' | 'settled'

  ContactLedgerArgs get _args => widget.args;

  Color get _accentColor =>
      _args.isCustomer ? Colors.blue.shade700 : Colors.indigo.shade700;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UdhaarProvider>().startListening();
    });
  }

  List<UdhaarEntryModel> _filtered(List<UdhaarEntryModel> all) {
    return switch (_filter) {
      'pending' => all.where((e) => e.isPending).toList(),
      'settled' => all.where((e) => e.isSettled).toList(),
      _ => all,
    };
  }

  Future<void> _addEntry(BuildContext ctx) async {
    await ctx.push(
      '/udhaar/add',
      extra: PrefilledContact(
        contactId: _args.contactId,
        contactName: _args.contactName,
        contactType: _args.contactType,
      ),
    );
  }

  Future<void> _editEntry(UdhaarEntryModel entry) async {
    await context.push('/udhaar/edit', extra: entry);
  }

  Future<void> _launchPhone(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone app open nahi ho saka')),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
    String intl = cleaned;
    if (intl.startsWith('0') && intl.length == 11) {
      intl = '92${intl.substring(1)}';
    } else if (intl.startsWith('3') && intl.length == 10) {
      intl = '92$intl';
    }
    final uri = Uri.parse('https://wa.me/$intl');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp open nahi ho saka')),
        );
      }
    }
  }

  Future<void> _confirmSettleAll(BuildContext ctx) async {
    final user = ctx.read<AuthProvider>().currentUser;
    if (user == null) return;

    final udhaar = ctx.read<UdhaarProvider>();
    final allEntries = udhaar.entriesForContact(_args.contactId);
    final pending = allEntries.where((e) => e.isPending).toList();
    if (pending.isEmpty) return;

    final totalAmount =
        pending.fold(0.0, (s, e) => s + e.amount);
    final count = pending.length;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.done_all_rounded, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Text('Settle All Pending'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settle all $count pending entr${count == 1 ? 'y' : 'ies'} '
              'for "${_args.contactName}"?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.currency_rupee_rounded,
                      size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Total: Rs ${totalAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.green.shade700),
                  ),
                  const Spacer(),
                  Text(
                    '$count entries',
                    style: TextStyle(
                        fontSize: 12, color: Colors.green.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Yeh action sabhi pending entries ko settled mark kar dega. '
              'Aap انہیں baad mein "Settled" filter mein dekh sakte hain.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: const Text('Settle All'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && ctx.mounted) {
      final settled = await ctx.read<UdhaarProvider>().settleAllPendingForContact(
            contactId: _args.contactId,
            settledBy: user,
          );
      if (ctx.mounted) {
        if (ctx.read<UdhaarProvider>().isOfflinePending) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('Saved offline — sync hoga jab internet aaye.'),
              backgroundColor: Colors.orange,
            ),
          );
          ctx.read<UdhaarProvider>().clearOfflinePending();
        } else if (ctx.read<UdhaarProvider>().error == null) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                  '$settled entr${settled == 1 ? 'y' : 'ies'} settled ✅'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        } else {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(ctx.read<UdhaarProvider>().error!),
              backgroundColor: Colors.red,
            ),
          );
          ctx.read<UdhaarProvider>().clearError();
        }
      }
    }
  }

  Future<void> _confirmSettle(
      BuildContext ctx, UdhaarEntryModel entry) async {
    final user = ctx.read<AuthProvider>().currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: Colors.green, size: 22),
            SizedBox(width: 8),
            Text('Mark as Settled'),
          ],
        ),
        content: Text(
            'Mark "${entry.personName}" (${entry.amountDisplay}) as settled?'),
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
      await ctx.read<UdhaarProvider>().settleEntry(
            entry: entry,
            settledBy: user,
          );
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('"${entry.personName}" marked as settled ✅'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final udhaar = context.watch<UdhaarProvider>();
    final auth = context.watch<AuthProvider>();
    final isViewer = auth.currentUser?.isViewer ?? false;

    final allEntries = udhaar.entriesForContact(_args.contactId);
    final entries = _filtered(allEntries);

    final totalGiven = allEntries
        .where((e) => e.isGiven && e.isPending)
        .fold(0.0, (s, e) => s + e.amount);
    final totalReceived = allEntries
        .where((e) => e.isReceived && e.isPending)
        .fold(0.0, (s, e) => s + e.amount);
    final totalSettled = allEntries
        .where((e) => e.isSettled)
        .fold(0.0, (s, e) => s + e.amount);
    final net = totalGiven - totalReceived;

    final pendingCount =
        allEntries.where((e) => e.isPending).length;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_args.contactName,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            Text(
              _args.isCustomer ? 'Customer Ledger' : 'Supplier Ledger',
              style: TextStyle(
                  fontSize: 12,
                  color: _accentColor,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          if (!isViewer && pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.done_all_rounded, size: 17),
                label: Text('Settle All ($pendingCount)'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: udhaar.isBusy
                    ? null
                    : () => _confirmSettleAll(context),
              ),
            ),
        ],
      ),
      floatingActionButton: isViewer
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addEntry(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Entry'),
            ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Balance summary card ──────────────────────────────────
            _BalanceCard(
              contactName: _args.contactName,
              isCustomer: _args.isCustomer,
              accentColor: _accentColor,
              totalGiven: totalGiven,
              totalReceived: totalReceived,
              totalSettled: totalSettled,
              net: net,
              entryCount: allEntries.length,
            ),

            // ── NEW: Quick-dial action bar ─────────────────────────────
            if (_args.hasPhone)
              _QuickContactBar(
                phone: _args.contactPhone,
                whatsapp: _args.contactWhatsapp,
                accentColor: _accentColor,
                onCall: _args.contactPhone != null &&
                        _args.contactPhone!.isNotEmpty
                    ? () => _launchPhone(_args.contactPhone!)
                    : null,
                onWhatsApp: _args.hasWhatsApp
                    ? () => _launchWhatsApp(_args.contactWhatsapp!)
                    : null,
              ),

            // ── Filter chips ──────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Chip(
                        label: 'All (${allEntries.length})',
                        selected: _filter == 'all',
                        onTap: () => setState(() => _filter = 'all')),
                    const SizedBox(width: 8),
                    _Chip(
                      label:
                          'Pending (${allEntries.where((e) => e.isPending).length})',
                      selected: _filter == 'pending',
                      color: Colors.orange,
                      onTap: () => setState(() => _filter = 'pending'),
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      label:
                          'Settled (${allEntries.where((e) => e.isSettled).length})',
                      selected: _filter == 'settled',
                      color: Colors.green,
                      onTap: () => setState(() => _filter = 'settled'),
                    ),
                  ],
                ),
              ),
            ),

            // ── Entry list ────────────────────────────────────────────
            Expanded(
              child: entries.isEmpty
                  ? _EmptyState(
                      hasFilter: _filter != 'all',
                      onClear: () => setState(() => _filter = 'all'),
                      contactName: _args.contactName,
                      isViewer: isViewer,
                      onAdd: () => _addEntry(context),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final entry = entries[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _LedgerEntryCard(
                            entry: entry,
                            isViewer: isViewer,
                            onTap: (isViewer || entry.isSettled)
                                ? null
                                : () => _editEntry(entry),
                            onSettle: (entry.isSettled || isViewer)
                                ? null
                                : () => _confirmSettle(ctx, entry),
                            onDelete: isViewer
                                ? null
                                : () => _deleteWithUndo(ctx, entry),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── NEW: Quick contact action bar ─────────────────────────────────────────────

class _QuickContactBar extends StatelessWidget {
  const _QuickContactBar({
    required this.phone,
    required this.whatsapp,
    required this.accentColor,
    this.onCall,
    this.onWhatsApp,
  });

  final String? phone;
  final String? whatsapp;
  final Color accentColor;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final displayNumber =
        (whatsapp != null && whatsapp!.isNotEmpty) ? whatsapp! : phone ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_in_talk_rounded,
              size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayNumber,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700),
            ),
          ),
          if (onCall != null) ...[
            _ActionBtn(
              icon: Icons.call_rounded,
              label: 'Call',
              color: accentColor,
              onTap: onCall!,
            ),
            const SizedBox(width: 8),
          ],
          if (onWhatsApp != null)
            _ActionBtn(
              icon: Icons.chat_rounded,
              label: 'WhatsApp',
              color: const Color(0xFF25D366),
              onTap: onWhatsApp!,
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Balance summary card ──────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.contactName,
    required this.isCustomer,
    required this.accentColor,
    required this.totalGiven,
    required this.totalReceived,
    required this.totalSettled,
    required this.net,
    required this.entryCount,
  });
  final String contactName;
  final bool isCustomer;
  final Color accentColor;
  final double totalGiven;
  final double totalReceived;
  final double totalSettled;
  final double net;
  final int entryCount;

  String _fmt(double v) => 'Rs ${v.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final netPositive = net >= 0;
    final netLabel = isCustomer
        ? (netPositive ? 'They owe you' : 'You owe them')
        : (netPositive ? 'You overpaid' : 'You owe them');
    final netColor =
        netPositive ? Colors.red.shade600 : Colors.green.shade600;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: accentColor.withValues(alpha: 0.15),
                  child: Text(
                    contactName.isNotEmpty
                        ? contactName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contactName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('$entryCount entries total',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt(net.abs()),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: netColor),
                    ),
                    Text(netLabel,
                        style:
                            TextStyle(fontSize: 11, color: netColor)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: _StatItem(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Given',
                    value: _fmt(totalGiven),
                    color: Colors.red.shade600,
                  ),
                ),
                Container(
                    width: 1, height: 40, color: Colors.grey.shade200),
                Expanded(
                  child: _StatItem(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Received',
                    value: _fmt(totalReceived),
                    color: Colors.teal.shade600,
                  ),
                ),
                Container(
                    width: 1, height: 40, color: Colors.grey.shade200),
                Expanded(
                  child: _StatItem(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Settled',
                    value: _fmt(totalSettled),
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color)),
        Text(label,
            style:
                const TextStyle(fontSize: 9, color: Colors.grey),
            textAlign: TextAlign.center),
      ],
    );
  }
}

// ── Ledger entry card ─────────────────────────────────────────────────────────

class _LedgerEntryCard extends StatelessWidget {
  const _LedgerEntryCard({
    required this.entry,
    required this.isViewer,
    this.onTap,
    this.onSettle,
    this.onDelete,
  });
  final UdhaarEntryModel entry;
  final bool isViewer;
  final VoidCallback? onTap;
  final VoidCallback? onSettle;
  final VoidCallback? onDelete;

  Color get _typeColor =>
      entry.isGiven ? Colors.red.shade600 : Colors.teal.shade600;
  Color get _typeBg =>
      entry.isGiven ? Colors.red.shade50 : Colors.teal.shade50;
  Color get _statusColor =>
      entry.isSettled ? Colors.green.shade700 : Colors.orange.shade700;
  Color get _statusBg =>
      entry.isSettled ? Colors.green.shade50 : Colors.orange.shade50;

  String _fmt(DateTime dt) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour > 12
        ? dt.hour - 12
        : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}, $hour:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: entry.isSettled
                  ? Colors.green.shade100
                  : Colors.grey.shade200)),
      color: entry.isSettled
          ? Colors.green.shade50.withValues(alpha: 0.3)
          : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (entry.isSettled)
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 15),
                  if (entry.isSettled) const SizedBox(width: 6),
                  _Badge(
                      label: entry.isGiven ? 'Given ↑' : 'Received ↓',
                      color: entry.isSettled
                          ? Colors.grey.shade500
                          : _typeColor,
                      bg: entry.isSettled
                          ? Colors.grey.shade100
                          : _typeBg),
                  const SizedBox(width: 6),
                  _Badge(
                      label: entry.isSettled ? 'Settled' : 'Pending',
                      color: _statusColor,
                      bg: _statusBg),
                  const Spacer(),
                  Text(
                    entry.amountDisplay,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: entry.isSettled
                            ? Colors.grey.shade500
                            : _typeColor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(_fmt(entry.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  if (entry.isSettled && entry.settledAt != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.event_available_rounded,
                        size: 11, color: Colors.green.shade500),
                    const SizedBox(width: 4),
                    Text('Settled ${_fmt(entry.settledAt!)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade600)),
                  ],
                ],
              ),
              if (entry.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(entry.notes,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
              if (!isViewer && !entry.isSettled) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onSettle != null)
                      TextButton.icon(
                        icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15),
                        label: const Text('Settle',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onSettle,
                      ),
                    if (onSettle != null) const SizedBox(width: 8),
                    if (onDelete != null)
                      TextButton.icon(
                        icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 15),
                        label: const Text('Delete',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onDelete,
                      ),
                  ],
                ),
              ],
              if (!isViewer && entry.isSettled) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 11, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text('Read only',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade400)),
                    const Spacer(),
                    if (onDelete != null)
                      TextButton.icon(
                        icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 14),
                        label: const Text('Delete',
                            style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
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
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.label, required this.color, required this.bg});
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? c : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasFilter,
    required this.onClear,
    required this.contactName,
    required this.isViewer,
    required this.onAdd,
  });
  final bool hasFilter;
  final VoidCallback onClear;
  final String contactName;
  final bool isViewer;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (hasFilter) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off_rounded,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('No entries for this filter',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: onClear,
                child: const Text('Show all entries')),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No entries for $contactName',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          if (!isViewer) ...[
            Text('Tap + to add first entry',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Entry'),
              onPressed: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}
