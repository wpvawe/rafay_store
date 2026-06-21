import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/customer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/undo_snackbar.dart';

class AddEditCustomerScreen extends StatefulWidget {
  const AddEditCustomerScreen({super.key, this.existingCustomer});
  final CustomerModel? existingCustomer;

  @override
  State<AddEditCustomerScreen> createState() => _AddEditCustomerScreenState();
}

class _AddEditCustomerScreenState extends State<AddEditCustomerScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  bool _isSaving = false;

  bool get _isEditing => widget.existingCustomer != null;

  // Original values for dirty-check
  String _origName = '';
  String _origPhone = '';
  String _origWhatsapp = '';
  String _origAddress = '';
  String _origNotes = '';

  bool get _hasChanges =>
      _name.text != _origName ||
      _phone.text != _origPhone ||
      _whatsapp.text != _origWhatsapp ||
      _address.text != _origAddress ||
      _notes.text != _origNotes;

  @override
  void initState() {
    super.initState();
    final c = widget.existingCustomer;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _whatsapp = TextEditingController(text: c?.whatsappNumber ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');

    // Snapshot originals
    _origName = _name.text;
    _origPhone = _phone.text;
    _origWhatsapp = _whatsapp.text;
    _origAddress = _address.text;
    _origNotes = _notes.text;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final provider = context.read<CustomerProvider>();
    setState(() => _isSaving = true);

    if (_isEditing) {
      await provider.updateCustomer(
        customer: widget.existingCustomer!,
        name: _name.text,
        phone: _phone.text,
        whatsappNumber: _whatsapp.text,
        address: _address.text,
        notes: _notes.text,
        editedBy: user,
      );
    } else {
      await provider.addCustomer(
        name: _name.text,
        phone: _phone.text,
        whatsappNumber: _whatsapp.text,
        address: _address.text,
        notes: _notes.text,
        addedBy: user,
      );
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (provider.isOfflinePending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved! Will sync when back online.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        provider.clearOfflinePending();
        context.pop();
      } else if (provider.error == null) {
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(provider.error!),
              backgroundColor: Colors.red),
        );
        provider.clearError();
      }
    }
  }

  /// Shows confirmation dialog, then deletes and pops back with an UNDO snackbar.
  Future<void> _deleteWithUndo() async {
    if (!_isEditing) return;
    final snapshot = widget.existingCustomer!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            const Text('Delete Customer?'),
          ],
        ),
        content: Text(
            'This will permanently delete "${snapshot.name}". You can undo within 15 seconds.'),
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

    if (confirmed != true || !mounted) return;
    final provider = context.read<CustomerProvider>();
    setState(() => _isSaving = true);
    await provider.deleteCustomer(snapshot.id);
    if (mounted) {
      UndoSnackbar.show(
        context,
        message: '"${snapshot.name}" deleted',
        onUndo: () => provider.restoreCustomer(snapshot),
      );
      context.pop();
    }
  }


  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 8),
          const Text('Discard Changes?'),
        ]),
        content: const Text(
            'You have unsaved changes. Are you sure you want to go back?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Editing')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Customer' : 'Add Customer'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
          },
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete',
              color: Colors.red,
              onPressed: _isSaving ? null : _deleteWithUndo,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _name,
                  label: 'Customer Name *',
                  hint: 'Full name',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _PhoneField(
                  controller: _phone,
                  label: 'Phone Number',
                  hint: '03XX-XXXXXXX',
                ),
                const SizedBox(height: 16),
                _PhoneField(
                  controller: _whatsapp,
                  label: 'WhatsApp Number',
                  hint: '03XX-XXXXXXX (if different)',
                  prefixIcon: Icons.chat_bubble_outline_rounded,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _address,
                  label: 'Address',
                  hint: 'Shop / area / city',
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _notes,
                  label: 'Notes (optional)',
                  hint: 'Any additional details…',
                  maxLines: 3,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(_isEditing ? 'Save Changes' : 'Add Customer'),
                  ),
                ),
               ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.label,
    required this.hint,
    this.prefixIcon = Icons.phone_outlined,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9\+\-\s]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
