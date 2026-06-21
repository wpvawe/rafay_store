import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../models/supplier_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../widgets/undo_snackbar.dart';
import '../udhaar/contact_ledger_screen.dart';

class SupplierDetailScreen extends StatelessWidget {
  const SupplierDetailScreen({super.key, required this.supplier});

  final SupplierModel supplier;

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
    final uri = Uri.parse('https://wa.me/$cleaned');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
      }
    }
  }

  /// Shows confirmation dialog, then deletes and navigates back.
  Future<void> _deleteWithUndo(BuildContext context, SupplierModel live) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            const Text('Delete Supplier?'),
          ],
        ),
        content: Text(
            'This will permanently delete "${live.name}". You can undo within 15 seconds.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final provider = context.read<SupplierProvider>();
    await provider.deleteSupplier(live.id);
    if (context.mounted) {
      UndoSnackbar.show(
        context,
        message: '"${live.name}" deleted',
        onUndo: () => provider.restoreSupplier(live),
      );
      context.go('/suppliers');
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<SupplierProvider>().suppliers.where((s) => s.id == supplier.id).firstOrNull ?? supplier;
    final canEdit = context.watch<AuthProvider>().canEdit;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(live.name),
        actions: [
          if (canEdit) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => context.push('/supplier/edit', extra: live),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () => _deleteWithUndo(context, live),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListView(

        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                live.name.isNotEmpty ? live.name[0].toUpperCase() : '?',
                style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(live.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
          if (live.company.isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(child: Text(live.company, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600))),
          ],
          const SizedBox(height: 24),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Column(
              children: [
                if (live.productsSupplied.isNotEmpty)
                  _InfoTile(icon: Icons.inventory_2_outlined, label: 'Products Supplied', value: live.productsSupplied),

                if (live.whatsappNumber.isNotEmpty) ...[
                  const Divider(height: 1),
                  _InfoTile(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    value: live.whatsappNumber,
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      tooltip: 'Open WhatsApp',
                      onPressed: () => _launchWhatsApp(context, live.whatsappNumber),
                    ),
                  ),
                ],

                if (live.phoneNumber.isNotEmpty) ...[
                  const Divider(height: 1),
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: live.phoneNumber,
                    trailing: IconButton(
                      icon: const Icon(Icons.call, size: 20),
                      tooltip: 'Call',
                      onPressed: () => _launchPhone(context, live.phoneNumber),
                    ),
                  ),
                ],

                // Typed additional numbers
                for (final addNum in live.additionalNumbers) ...[
                  const Divider(height: 1),
                  _InfoTile(
                    icon: addNum.isWhatsApp ? Icons.chat_outlined : Icons.phone_in_talk_outlined,
                    label: addNum.isWhatsApp ? 'Additional WhatsApp' : 'Additional Phone',
                    value: addNum.number,
                    trailing: IconButton(
                      icon: Icon(addNum.isWhatsApp ? Icons.open_in_new : Icons.call, size: 20),
                      tooltip: addNum.isWhatsApp ? 'Open WhatsApp' : 'Call',
                      onPressed: addNum.isWhatsApp
                          ? () => _launchWhatsApp(context, addNum.number)
                          : () => _launchPhone(context, addNum.number),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              if (live.whatsappNumber.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launchWhatsApp(context, live.whatsappNumber),
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                  ),
                ),
              if (live.whatsappNumber.isNotEmpty && live.phoneNumber.isNotEmpty)
                const SizedBox(width: 12),
              if (live.phoneNumber.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launchPhone(context, live.phoneNumber),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(
                '/contact/ledger',
                extra: ContactLedgerArgs(
                  contactId: live.id,
                  contactName: live.name,
                  contactType: AppConstants.contactTypeSupplier,
                  contactPhone: live.phoneNumber.isNotEmpty
                      ? live.phoneNumber
                      : null,
                  contactWhatsapp: live.whatsappNumber.isNotEmpty
                      ? live.whatsappNumber
                      : null,
                ),
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Udhaar Ledger dekhein'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 28),
          Text('Audit', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(
            'Added by ${live.addedBy.name} on ${AppUtils.formatDate(live.addedBy.at)}',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          if (live.lastEditedBy.uid != live.addedBy.uid || live.lastEditedBy.at != live.addedBy.at)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Last edited by ${live.lastEditedBy.name} on ${AppUtils.formatDate(live.lastEditedBy.at)}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value, this.trailing});

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
