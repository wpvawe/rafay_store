import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/udhaar_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../providers/udhaar_provider.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/undo_snackbar.dart';

/// Carries a pre-selected contact when opening "Add Entry" from a ledger.
class PrefilledContact {
  final String contactId;
  final String contactName;
  final String contactType;
  const PrefilledContact({
    required this.contactId,
    required this.contactName,
    required this.contactType,
  });
}

/// Unified contact entry (customers + suppliers) used by the picker.
class _ContactEntry {
  final String id;
  final String name;
  final String subtitle;
  final String type; // AppConstants.contactTypeCustomer | contactTypeSupplier

  const _ContactEntry({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.type,
  });

  bool get isCustomer => type == AppConstants.contactTypeCustomer;
  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';
  Color get accentColor =>
      isCustomer ? const Color(0xFF1565C0) : const Color(0xFF283593);
  String get typeLabel => isCustomer ? 'Customer' : 'Supplier';
}

class AddEditUdhaarScreen extends StatefulWidget {
  const AddEditUdhaarScreen({
    super.key,
    this.existingEntry,
    this.prefilledContact,
  });
  final UdhaarEntryModel? existingEntry;

  /// Pre-selected contact when opening from ContactLedgerScreen.
  final PrefilledContact? prefilledContact;

  @override
  State<AddEditUdhaarScreen> createState() => _AddEditUdhaarScreenState();
}

class _AddEditUdhaarScreenState extends State<AddEditUdhaarScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late String _type;
  bool _isSaving = false;
  late DateTime _selectedCreatedAt;

  // Selected contact — can be customer OR supplier regardless of type
  String? _selectedContactId;
  String? _selectedContactType;
  String _selectedContactName = '';

  bool get _isEditing => widget.existingEntry != null;
  bool get _isSettled => widget.existingEntry?.isSettled ?? false;

  Color get _typeColor => _type == AppConstants.udhaarGiven
      ? Colors.red.shade600
      : Colors.teal.shade600;

  @override
  void initState() {
    super.initState();
    final entry = widget.existingEntry;
    _amount = TextEditingController(
        text: entry != null ? entry.amount.toStringAsFixed(0) : '');
    _notes = TextEditingController(text: entry?.notes ?? '');
    _type = entry?.type ?? AppConstants.udhaarGiven;
    _selectedCreatedAt = entry?.createdAt ?? DateTime.now();

    if (entry != null) {
      _selectedContactId = entry.contactId;
      _selectedContactType = entry.contactType;
      _selectedContactName = entry.personName;
    } else if (widget.prefilledContact != null) {
      final pf = widget.prefilledContact!;
      _selectedContactId = pf.contactId;
      _selectedContactType = pf.contactType;
      _selectedContactName = pf.contactName;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ── Date / time picker ────────────────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedCreatedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(minutes: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedCreatedAt),
    );
    if (time == null || !mounted) return;

    setState(() {
      _selectedCreatedAt = DateTime(
        date.year, date.month, date.day,
        time.hour, time.minute,
      );
    });
  }

  String _fmtDateTime(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$min $ampm';
  }

  // ── Unified contact picker ─────────────────────────────────────────────────

  List<_ContactEntry> _buildAllContacts() {
    final customers = context.read<CustomerProvider>().all;
    final suppliers = context.read<SupplierProvider>().all;
    return [
      ...customers.map((c) => _ContactEntry(
            id: c.id,
            name: c.name,
            subtitle:
                c.whatsappNumber.isNotEmpty ? c.whatsappNumber : c.phone,
            type: AppConstants.contactTypeCustomer,
          )),
      ...suppliers.map((s) => _ContactEntry(
            id: s.id,
            name: s.name,
            subtitle: s.company.isNotEmpty ? s.company : s.whatsappNumber,
            type: AppConstants.contactTypeSupplier,
          )),
    ];
  }

  Future<void> _openContactPicker() async {
    if (_isSettled) return;
    final allContacts = _buildAllContacts();
    final result = await showModalBottomSheet<_ContactEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnifiedContactPickerSheet(
        contacts: allContacts,
        onAddCustomer: () {
          Navigator.pop(context);
          context.push('/customer/add');
        },
        onAddSupplier: () {
          Navigator.pop(context);
          context.push('/supplier/add');
        },
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedContactId = result.id;
        _selectedContactType = result.type;
        _selectedContactName = result.name;
      });
    }
  }

  // ── Save / settle / delete ────────────────────────────────────────────────

  Future<void> _save() async {
    if (_isSettled) return;
    // Allow saving when editing a legacy entry that has personName but no contactId
    final hasContact = (_selectedContactId != null && _selectedContactId!.isNotEmpty) ||
        (_selectedContactName.trim().isNotEmpty);
    if (!hasContact) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer or supplier'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final udhaar = context.read<UdhaarProvider>();
    setState(() => _isSaving = true);

    final amount = double.tryParse(_amount.text.trim()) ?? 0;

    if (_isEditing) {
      await udhaar.updateEntry(
        entry: widget.existingEntry!,
        personName: _selectedContactName,
        amount: amount,
        type: _type,
        notes: _notes.text,
        editedBy: user,
        createdAt: _selectedCreatedAt,
        contactId: _selectedContactId,
        contactType: _selectedContactType,
      );
    } else {
      await udhaar.addEntry(
        personName: _selectedContactName,
        amount: amount,
        type: _type,
        notes: _notes.text,
        addedBy: user,
        contactId: _selectedContactId,
        contactType: _selectedContactType,
      );
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (udhaar.isOfflinePending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved! Will sync when back online.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        udhaar.clearOfflinePending();
        context.pop();
      } else if (udhaar.error == null) {
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(udhaar.error!), backgroundColor: Colors.red),
        );
        udhaar.clearError();
      }
    }
  }

  Future<void> _settle() async {
    if (_isSettled) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null || !_isEditing) return;

    final entry = widget.existingEntry!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${entry.personName}" ka udhaar settle karen?',
                style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _ReadOnlyRow(
              icon: Icons.currency_rupee_rounded,
              label: entry.amountDisplay,
              color: entry.isGiven
                  ? Colors.red.shade600
                  : Colors.teal.shade600,
            ),
            _ReadOnlyRow(
              icon: entry.isGiven
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              label: entry.isGiven
                  ? 'Given ↑'
                  : 'Received ↓',
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 10),
            Text(
              'Settle hone ke baad yeh entry read-only ho jaegi.',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Settle Now'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);
      await context
          .read<UdhaarProvider>()
          .settleEntry(entry: entry, settledBy: user);
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${entry.personName}" settled ✅'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      }
    }
  }

  /// Immediately deletes the entry and shows a 15-second UNDO snackbar,
  /// then pops back to the previous screen.
  Future<void> _deleteWithUndo() async {
    if (!_isEditing) return;
    final entry = widget.existingEntry!;
    final provider = context.read<UdhaarProvider>();
    await provider.deleteEntry(entry.id);
    if (mounted) {
      UndoSnackbar.show(
        context,
        message: '"${entry.personName}" entry deleted',
        onUndo: () => provider.restoreEntry(entry),
      );
      context.pop();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isViewer =
        context.watch<AuthProvider>().currentUser?.isViewer ?? false;

    if (_isSettled) {
      return _SettledDetailView(
        entry: widget.existingEntry!,
        onDelete: isViewer ? null : _deleteWithUndo,
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Entry' : 'Add Udhaar Entry'),
        actions: [
          if (_isEditing)
            TextButton.icon(
              icon: const Icon(Icons.check_circle_outline_rounded,
                  size: 18),
              label: const Text('Settle'),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              onPressed: _isSaving ? null : _settle,
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
                // ── Type toggle ──────────────────────────────────────────
                Text('Udhaar Type',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                _TypeToggle(
                  value: _type,
                  onChanged: (t) => setState(() => _type = t),
                ),
                const SizedBox(height: 20),

                // ── Contact picker ───────────────────────────────────────
                Text('Select Contact (Customer / Supplier)',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                _ContactPickerButton(
                  selectedName: _selectedContactName,
                  selectedType: _selectedContactType,
                  typeColor: _typeColor,
                  onTap: _openContactPicker,
                  onClear: _selectedContactName.isNotEmpty
                      ? () => setState(() {
                            _selectedContactId = null;
                            _selectedContactType = null;
                            _selectedContactName = '';
                          })
                      : null,
                ),
                const SizedBox(height: 20),

                // ── Amount ───────────────────────────────────────────────
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[\d.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount (Rs)',
                    hintText: '0',
                    prefixIcon: const Icon(
                        Icons.currency_rupee_rounded,
                        size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Amount is required';
                    }
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) {
                      return 'Enter a valid amount greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ── Notes ────────────────────────────────────────────────
                AppTextField(
                  controller: _notes,
                  label: 'Notes (optional)',
                  hint: 'Koi aur detail likhein…',
                  maxLines: 3,
                ),

                // ── Entry Date & Time (editable for admin/editor) ─────────
                if (_isEditing) ...[
                  const SizedBox(height: 20),
                  Text('Entry Date & Time',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Builder(builder: (ctx) {
                    final canEdit =
                        ctx.read<AuthProvider>().currentUser?.canWrite ??
                            false;
                    return InkWell(
                      onTap: canEdit ? _pickDateTime : null,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 18,
                                color: canEdit
                                    ? Colors.blue.shade400
                                    : Colors.grey.shade400),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _fmtDateTime(_selectedCreatedAt),
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black87),
                              ),
                            ),
                            if (canEdit)
                              Icon(Icons.edit_outlined,
                                  size: 15,
                                  color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 32),

                // ── Save ─────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : Text(
                            _isEditing ? 'Save Changes' : 'Add Entry'),
                  ),
                ),

                if (_isEditing && !isViewer) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 16),
                      label: const Text('Delete Entry'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red)),
                      onPressed: _isSaving ? null : _deleteWithUndo,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Settled read-only view ────────────────────────────────────────────────────

class _SettledDetailView extends StatelessWidget {
  const _SettledDetailView(
      {required this.entry, this.onDelete});
  final UdhaarEntryModel entry;
  final VoidCallback? onDelete;

  String _fmt(DateTime dt) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}, $hour:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isGiven = entry.isGiven;
    final typeColor =
        isGiven ? Colors.red.shade600 : Colors.teal.shade600;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Udhaar Detail'),
        actions: [
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: Colors.red.shade400),
              tooltip: 'Delete entry',
              onPressed: onDelete,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Settled banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Settled',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green,
                                  fontSize: 15)),
                          if (entry.settledAt != null)
                            Text('on ${_fmt(entry.settledAt!)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 12, color: Colors.green),
                          const SizedBox(width: 4),
                          Text('Read-only',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _DetailCard(
                child: Column(
                  children: [
                    _DetailRow(
                        label: 'Person',
                        value: entry.personName,
                        icon: Icons.person_outline_rounded,
                        valueStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Divider(height: 24),
                    _DetailRow(
                        label: 'Amount',
                        value: entry.amountDisplay,
                        icon: Icons.currency_rupee_rounded,
                        valueStyle: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: typeColor)),
                    const Divider(height: 24),
                    _DetailRow(
                        label: 'Type',
                        value: isGiven
                            ? 'Given ↑'
                            : 'Received ↓',
                        icon: isGiven
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        valueColor: typeColor),
                    const Divider(height: 24),
                    _DetailRow(
                        label: 'Date Added',
                        value: _fmt(entry.createdAt),
                        icon: Icons.calendar_today_outlined),
                    if (entry.settledAt != null) ...[
                      const Divider(height: 24),
                      _DetailRow(
                          label: 'Settled On',
                          value: _fmt(entry.settledAt!),
                          icon: Icons.event_available_rounded,
                          valueColor: Colors.green.shade700),
                    ],
                  ],
                ),
              ),

              if (entry.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                _DetailCard(
                  child: _DetailRow(
                      label: 'Notes',
                      value: entry.notes,
                      icon: Icons.notes_rounded),
                ),
              ],

              const SizedBox(height: 16),
              _DetailCard(
                child: Column(
                  children: [
                    _DetailRow(
                        label: 'Added by',
                        value: entry.addedBy.name,
                        icon: Icons.person_add_outlined),
                    if (entry.settledAt != null) ...[
                      const Divider(height: 24),
                      _DetailRow(
                          label: 'Settled by',
                          value: entry.lastEditedBy.name.isNotEmpty
                              ? entry.lastEditedBy.name
                              : entry.addedBy.name,
                          icon: Icons.how_to_reg_rounded,
                          valueColor: Colors.green.shade700),
                    ] else if (entry.lastEditedBy.uid != entry.addedBy.uid ||
                        entry.lastEditedBy.at != entry.addedBy.at) ...[
                      const Divider(height: 24),
                      _DetailRow(
                          label: 'Last edited',
                          value: entry.lastEditedBy.name,
                          icon: Icons.edit_outlined),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared card / row widgets ─────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.valueStyle,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade400),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(
                value,
                style: valueStyle ??
                    TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: valueColor ?? Colors.black87),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow(
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

// ── Contact picker button (unified) ──────────────────────────────────────────

class _ContactPickerButton extends StatelessWidget {
  const _ContactPickerButton({
    required this.selectedName,
    required this.selectedType,
    required this.typeColor,
    required this.onTap,
    this.onClear,
  });
  final String selectedName;
  final String? selectedType;
  final Color typeColor;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  bool get _isSelected => selectedName.isNotEmpty;

  String get _typeBadge {
    if (selectedType == AppConstants.contactTypeCustomer) {
      return 'Customer';
    } else if (selectedType == AppConstants.contactTypeSupplier) {
      return 'Supplier';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _isSelected
              ? typeColor.withValues(alpha: 0.06)
              : Colors.white,
          border: Border.all(
            color: _isSelected ? typeColor : Colors.grey.shade300,
            width: _isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _isSelected
                  ? (_typeBadge == 'Customer'
                      ? Icons.person_rounded
                      : Icons.local_shipping_rounded)
                  : Icons.person_search_rounded,
              color: _isSelected ? typeColor : Colors.grey.shade400,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isSelected
                        ? selectedName
                        : 'Select customer or supplier',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isSelected
                          ? Colors.black87
                          : Colors.grey.shade500,
                      fontWeight: _isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_isSelected && _typeBadge.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _typeBadge,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: typeColor),
                      ),
                    ),
                ],
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded,
                    size: 18, color: Colors.grey.shade400),
              )
            else
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Unified contact picker bottom sheet ──────────────────────────────────────

class _UnifiedContactPickerSheet extends StatefulWidget {
  const _UnifiedContactPickerSheet({
    required this.contacts,
    required this.onAddCustomer,
    required this.onAddSupplier,
  });
  final List<_ContactEntry> contacts;
  final VoidCallback onAddCustomer;
  final VoidCallback onAddSupplier;

  @override
  State<_UnifiedContactPickerSheet> createState() =>
      _UnifiedContactPickerSheetState();
}

class _UnifiedContactPickerSheetState
    extends State<_UnifiedContactPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_ContactEntry> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.contacts;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.contacts;
      } else {
        final lower = q.toLowerCase();
        _filtered = widget.contacts
            .where((e) =>
                e.name.toLowerCase().contains(lower) ||
                e.subtitle.toLowerCase().contains(lower) ||
                e.typeLabel.toLowerCase().contains(lower))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Select Contact',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text('Customers & Suppliers',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'Add new',
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'customer',
                          child: Row(
                            children: [
                              Icon(Icons.person_add_rounded,
                                  size: 16, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Add Customer'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'supplier',
                          child: Row(
                            children: [
                              Icon(Icons.local_shipping_rounded,
                                  size: 16, color: Colors.indigo),
                              SizedBox(width: 8),
                              Text('Add Supplier'),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (val) {
                        if (val == 'customer') {
                          widget.onAddCustomer();
                        } else {
                          widget.onAddSupplier();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, company…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onChanged: _onSearch,
                ),
              ),

              // Stats bar
              if (widget.contacts.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _TypeCountBadge(
                        count: widget.contacts
                            .where((e) => e.isCustomer)
                            .length,
                        label: 'Customers',
                        color: Colors.blue,
                        icon: Icons.person_rounded,
                      ),
                      const SizedBox(width: 8),
                      _TypeCountBadge(
                        count: widget.contacts
                            .where((e) => !e.isCustomer)
                            .length,
                        label: 'Suppliers',
                        color: Colors.indigo,
                        icon: Icons.local_shipping_rounded,
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 4),

              // List
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded,
                                size: 48,
                                color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              widget.contacts.isEmpty
                                  ? 'No customers or suppliers.\nAdd one first.'
                                  : 'No results found.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final entry = _filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: entry.accentColor
                                  .withValues(alpha: 0.12),
                              child: Text(entry.initial,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: entry.accentColor,
                                      fontSize: 15)),
                            ),
                            title: Text(entry.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: entry.subtitle.isNotEmpty
                                ? Text(entry.subtitle,
                                    style: const TextStyle(fontSize: 12))
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: entry.accentColor
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.typeLabel,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: entry.accentColor),
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            onTap: () =>
                                Navigator.pop(context, entry),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TypeCountBadge extends StatelessWidget {
  const _TypeCountBadge({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });
  final int count;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text('$count $label',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Type toggle ───────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TypeOption(
            label: 'Given (Paid Out)',
            subtitle: 'You paid out — they owe you',
            icon: Icons.arrow_upward_rounded,
            color: Colors.red.shade600,
            selected: value == AppConstants.udhaarGiven,
            onTap: () => onChanged(AppConstants.udhaarGiven),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TypeOption(
            label: 'Received (Credit)',
            subtitle: 'They paid you — you owe them',
            icon: Icons.arrow_downward_rounded,
            color: Colors.teal.shade600,
            selected: value == AppConstants.udhaarReceived,
            onTap: () => onChanged(AppConstants.udhaarReceived),
          ),
        ),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.08) : Colors.white,
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? color : Colors.grey.shade400,
                size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: selected
                              ? color
                              : Colors.grey.shade700)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                      maxLines: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
