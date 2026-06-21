import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/supplier_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/supplier_provider.dart';

/// Holds the state for one additional number row.
class _ExtraNum {
  String type; // 'whatsapp' or 'phone'
  final TextEditingController ctrl;

  _ExtraNum({this.type = 'phone', String initialNumber = ''})
      : ctrl = TextEditingController(text: initialNumber);

  void dispose() => ctrl.dispose();
}

class AddEditSupplierScreen extends StatefulWidget {
  const AddEditSupplierScreen({super.key, this.existingSupplier});

  final SupplierModel? existingSupplier;

  @override
  State<AddEditSupplierScreen> createState() => _AddEditSupplierScreenState();
}

class _AddEditSupplierScreenState extends State<AddEditSupplierScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _productsCtrl;
  late final TextEditingController _whatsappCtrl;
  late final TextEditingController _phoneCtrl;

  final List<_ExtraNum> _extras = [];

  bool get _isEditing => widget.existingSupplier != null;

  // Unsaved-changes tracking
  String _origName = '';
  String _origCompany = '';
  String _origProducts = '';
  String _origWhatsapp = '';
  String _origPhone = '';

  bool get _hasChanges =>
      _nameCtrl.text != _origName ||
      _companyCtrl.text != _origCompany ||
      _productsCtrl.text != _origProducts ||
      _whatsappCtrl.text != _origWhatsapp ||
      _phoneCtrl.text != _origPhone;

  @override
  void initState() {
    super.initState();
    final s = widget.existingSupplier;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _companyCtrl = TextEditingController(text: s?.company ?? '');
    _productsCtrl = TextEditingController(text: s?.productsSupplied ?? '');
    _whatsappCtrl = TextEditingController(text: s?.whatsappNumber ?? '');
    _phoneCtrl = TextEditingController(text: s?.phoneNumber ?? '');

    if (s != null) {
      for (final an in s.additionalNumbers) {
        _extras.add(_ExtraNum(type: an.type, initialNumber: an.number));
      }
    }

    // Snapshot originals
    _origName = _nameCtrl.text;
    _origCompany = _companyCtrl.text;
    _origProducts = _productsCtrl.text;
    _origWhatsapp = _whatsappCtrl.text;
    _origPhone = _phoneCtrl.text;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _productsCtrl.dispose();
    _whatsappCtrl.dispose();
    _phoneCtrl.dispose();
    for (final e in _extras) e.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final provider = context.read<SupplierProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final additionalNumbers = _extras
        .where((e) => e.ctrl.text.trim().isNotEmpty)
        .map((e) => AdditionalNumber(type: e.type, number: e.ctrl.text.trim()))
        .toList();

    if (_isEditing) {
      await provider.updateSupplier(
        supplier: widget.existingSupplier!,
        name: _nameCtrl.text,
        company: _companyCtrl.text,
        productsSupplied: _productsCtrl.text,
        whatsappNumber: _whatsappCtrl.text,
        phoneNumber: _phoneCtrl.text,
        additionalNumbers: additionalNumbers,
        editedBy: user,
      );
    } else {
      await provider.addSupplier(
        name: _nameCtrl.text,
        company: _companyCtrl.text,
        productsSupplied: _productsCtrl.text,
        whatsappNumber: _whatsappCtrl.text,
        phoneNumber: _phoneCtrl.text,
        additionalNumbers: additionalNumbers,
        addedBy: user,
      );
    }

    if (!mounted) return;
    if (provider.isOfflinePending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved! Will sync when back online.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      provider.clearOfflinePending();
      // Use context.pop() consistently for both edit and add paths.
      // context.go('/suppliers') was used for new items but it resets the
      // entire navigation stack, which loses any caller context. pop() is
      // correct here because the add screen is always pushed on top of
      // the supplier list screen.
      context.pop();
      return;
    }
    if (provider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error!), backgroundColor: Colors.red),
      );
      return;
    }
    if (!mounted) return;
    context.pop();
  }

  void _addExtraNumber() {
    setState(() => _extras.add(_ExtraNum(type: 'phone')));
  }

  void _removeExtraNumber(int index) {
    setState(() {
      _extras[index].dispose();
      _extras.removeAt(index);
    });
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool required = false,
    int maxLines = 1,
    String? Function(String?)? extraValidator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, hintText: hint),
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) {
            return '$label is required';
          }
          return extraValidator?.call(v);
        },
      ),
    );
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
    final provider = context.watch<SupplierProvider>();
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Supplier' : 'Add Supplier'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildField(ctrl: _nameCtrl, label: 'Supplier Name', required: true),
              _buildField(ctrl: _companyCtrl, label: 'Company', hint: 'Company or shop name'),
              _buildField(ctrl: _productsCtrl, label: 'Products Supplied', hint: 'e.g. Electronics, Cloth, Toys…', maxLines: 2),
              _buildField(ctrl: _whatsappCtrl, label: 'WhatsApp Number', hint: '+92 3xx xxxxxxx', keyboardType: TextInputType.phone, extraValidator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                if (digits.length < 10) return 'Enter a valid phone number';
                return null;
              }),
              _buildField(ctrl: _phoneCtrl, label: 'Phone Number', hint: '+92 3xx xxxxxxx', keyboardType: TextInputType.phone, extraValidator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                if (digits.length < 10) return 'Enter a valid phone number';
                return null;
              }),

              // ── Additional typed numbers ────────────────────────────────
              if (_extras.isNotEmpty) ...[
                Text(
                  'Additional Numbers',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                ...List.generate(_extras.length, (i) {
                  final extra = _extras[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Type picker
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: extra.type,
                              borderRadius: BorderRadius.circular(12),
                              items: [
                                DropdownMenuItem(
                                  value: 'phone',
                                  child: Row(children: [
                                    const Icon(Icons.call_rounded, size: 16, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    const Text('Phone', style: TextStyle(fontSize: 13)),
                                  ]),
                                ),
                                DropdownMenuItem(
                                  value: 'whatsapp',
                                  child: Row(children: [
                                    const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF25D366)),
                                    const SizedBox(width: 6),
                                    const Text('WhatsApp', style: TextStyle(fontSize: 13)),
                                  ]),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => extra.type = v);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: extra.ctrl,
                            decoration: InputDecoration(
                              labelText: 'Number ${i + 1}',
                              hintText: '+92 3xx xxxxxxx',
                              prefixIcon: extra.type == 'whatsapp'
                                  ? const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 18)
                                  : const Icon(Icons.call_rounded, color: Colors.blue, size: 18),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: () => _removeExtraNumber(i),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],

              TextButton.icon(
                onPressed: _addExtraNumber,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add another number'),
              ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: provider.isBusy ? null : _submit,
                child: provider.isBusy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEditing ? 'Save Changes' : 'Add Supplier'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
