import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/category_model.dart';
import '../../models/demand_item_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/demand_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../widgets/app_text_field.dart';
import 'barcode_scanner_screen.dart';

class AddEditDemandScreen extends StatefulWidget {
  const AddEditDemandScreen({super.key, this.existingItem});
  final DemandItemModel? existingItem;

  @override
  State<AddEditDemandScreen> createState() => _AddEditDemandScreenState();
}

class _AddEditDemandScreenState extends State<AddEditDemandScreen> {
  // ── Form keys per step ────────────────────────────────────────────────────
  final _formStep1 = GlobalKey<FormState>();
  final _formStep2 = GlobalKey<FormState>();
  final _formStep3 = GlobalKey<FormState>();
  final _formStep4 = GlobalKey<FormState>();


  int _currentStep = 0;
  static const _totalSteps = 4;

  // ── Controllers ───────────────────────────────────────────────────────────
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _packContents;
  late final TextEditingController _notes;
  late final TextEditingController _barcode;
  late final TextEditingController _sellPrice;
  late final TextEditingController _costPrice;
  late final TextEditingController _wholesalePrice;
  late final TextEditingController _stock;
  late final TextEditingController _reorderLevel;
  late final TextEditingController _customUnitCtrl;

  // ── FocusNodes for price field chaining ──────────────────────────────────
  final _costFocus = FocusNode();
  final _wholesaleFocus = FocusNode();

  // ── State ──────────────────────────────────────────────────────────────────────────
  late String _status;
  late String _unit;
  late bool _isCustomUnit;
  String? _categoryId;
  String? _selectedSupplierId;

  // ── Unsaved-changes tracking ───────────────────────────────────────────────
  late String _origName;
  late String _origQuantity;
  late String _origNotes;
  late String _origBarcode;
  late String _origSellPrice;
  late String _origCostPrice;
  late String _origWholesalePrice;
  late String _origStock;
  late String _origReorderLevel;
  late String _origStatus;
  late String? _origCategoryId;
  late String? _origSupplierId;

  bool get _hasChanges {
    return _name.text != _origName ||
        _quantity.text != _origQuantity ||
        _notes.text != _origNotes ||
        _barcode.text != _origBarcode ||
        _sellPrice.text != _origSellPrice ||
        _costPrice.text != _origCostPrice ||
        _wholesalePrice.text != _origWholesalePrice ||
        _stock.text != _origStock ||
        _reorderLevel.text != _origReorderLevel ||
        _status != _origStatus ||
        _categoryId != _origCategoryId ||
        _selectedSupplierId != _origSupplierId;
  }

  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    _name = TextEditingController(text: item?.name ?? '');
    _quantity = TextEditingController(text: item?.quantity ?? '1');
    _packContents = TextEditingController(text: item?.packContents ?? '');
    _notes = TextEditingController(text: item?.notes ?? '');
    _barcode = TextEditingController(text: item?.barcode ?? '');
    _status = item?.status ?? AppConstants.demandPending;
    _categoryId = item?.categoryId;
    _selectedSupplierId = item?.supplierId;

    // Migrate legacy 'Qty' unit to 'Piece' (Qty was removed from the list)
    final rawUnit = item?.unit ?? 'Piece';
    final savedUnit = rawUnit == 'Qty' ? 'Piece' : rawUnit;
    if (AppConstants.demandUnits.contains(savedUnit)) {
      _unit = savedUnit;
      _isCustomUnit = false;
      _customUnitCtrl = TextEditingController();
    } else {
      _unit = AppConstants.demandUnitCustom;
      _isCustomUnit = true;
      _customUnitCtrl = TextEditingController(text: savedUnit);
    }

    _sellPrice = TextEditingController(
      text: item != null ? _priceToText(item.sellPrice) : '0',
    );
    _costPrice = TextEditingController(
      text: item?.costPrice != null ? _priceToText(item!.costPrice!) : '',
    );
    _wholesalePrice = TextEditingController(
      text: item?.wholesalePrice != null ? _priceToText(item!.wholesalePrice!) : '',
    );
    _stock = TextEditingController(
      text: item != null ? item.stock.toString() : '0',
    );
    _reorderLevel = TextEditingController(
      text: item != null ? item.reorderLevel.toString() : '0',
    );

    // Snapshot original values for unsaved-changes detection
    _origName = _name.text;
    _origQuantity = _quantity.text;
    _origNotes = _notes.text;
    _origBarcode = _barcode.text;
    _origSellPrice = _sellPrice.text;
    _origCostPrice = _costPrice.text;
    _origWholesalePrice = _wholesalePrice.text;
    _origStock = _stock.text;
    _origReorderLevel = _reorderLevel.text;
    _origStatus = _status;
    _origCategoryId = _categoryId;
    _origSupplierId = _selectedSupplierId;

    // Real-time title update — rebuild AppBar when name changes
    _name.addListener(_onNameChanged);
  }

  /// Called whenever the item name field changes — triggers AppBar title rebuild.
  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  static String _priceToText(double p) =>
      p == p.truncateToDouble() ? p.toInt().toString() : p.toStringAsFixed(2);

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    _quantity.dispose();
    _packContents.dispose();
    _notes.dispose();
    _barcode.dispose();
    _customUnitCtrl.dispose();
    _sellPrice.dispose();
    _costPrice.dispose();
    _wholesalePrice.dispose();
    _stock.dispose();
    _reorderLevel.dispose();
    _costFocus.dispose();
    _wholesaleFocus.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        return _formStep1.currentState?.validate() ?? false;
      case 1:
        return _formStep2.currentState?.validate() ?? false;
      case 2:
        return _formStep3.currentState?.validate() ?? false;
      case 3:
        return _formStep4.currentState?.validate() ?? false;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (!_validateStep(_currentStep)) return;
    if (_currentStep < _totalSteps - 1) {
      FocusScope.of(context).unfocus();
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      FocusScope.of(context).unfocus();
      setState(() => _currentStep--);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  /// Save from ANY step — validates all steps sequentially before saving.
  Future<void> _submitFromAnyStep() async {
    // Validate steps 0..current, then submit
    for (int i = 0; i <= _currentStep; i++) {
      if (!_validateStep(i)) {
        // jump to the failing step
        setState(() => _currentStep = i);
        return;
      }
    }
    await _submit();
  }

  Future<void> _submit() async {
    // Validate only the current step — earlier steps were validated
    // at each "Continue" press (or _submitFromAnyStep), so they are already clean.
    if (!_validateStep(_currentStep)) return;

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final provider = context.read<DemandProvider>();

    final barcodeInput = _barcode.text.trim();
    if (barcodeInput.isNotEmpty) {
      final conflict = provider.findByBarcode(
        barcodeInput,
        excludeId: widget.existingItem?.id,
      );
      if (conflict != null && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Barcode Already Used'),
            content: Text(
              'Barcode "$barcodeInput" is already attached to item "${conflict.name}".\n\nDo you want to save anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE53935)),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    final sellPriceVal = double.tryParse(_sellPrice.text.trim()) ?? 0.0;
    final costPriceVal = _costPrice.text.trim().isNotEmpty
        ? double.tryParse(_costPrice.text.trim())
        : null;
    final wholesalePriceVal = _wholesalePrice.text.trim().isNotEmpty
        ? double.tryParse(_wholesalePrice.text.trim())
        : null;
    final stockVal = int.tryParse(_stock.text.trim()) ?? 0;
    final reorderLevelVal = int.tryParse(_reorderLevel.text.trim()) ?? 0;
    final effectiveUnit = _isCustomUnit
        ? (_customUnitCtrl.text.trim().isEmpty ? 'Piece' : _customUnitCtrl.text.trim())
        : _unit;
    final effectiveCategoryId =
        (_categoryId != null && _categoryId!.isNotEmpty) ? _categoryId : null;

    // Wrap provider calls in try-catch so that an unexpected exception
    // (e.g. Firestore SDK throwing before setting provider.error) does
    // not leave the loading spinner spinning forever.
    try {
      if (_isEditing) {
        await provider.updateItem(
          item: widget.existingItem!,
          name: _name.text.trim(),
          quantity: _quantity.text.trim(),
          unit: effectiveUnit,
          packContents: _packContents.text.trim(),
          notes: _notes.text.trim(),
          status: _status,
          barcode: _barcode.text.trim(),
          categoryId: effectiveCategoryId,
          clearCategoryId: effectiveCategoryId == null,
          editedBy: user,
          sellPrice: sellPriceVal,
          costPrice: costPriceVal,
          clearCostPrice: costPriceVal == null,
          wholesalePrice: wholesalePriceVal,
          clearWholesalePrice: wholesalePriceVal == null,
          stock: stockVal,
          reorderLevel: reorderLevelVal,
          supplierId: _selectedSupplierId,
          clearSupplierId: _selectedSupplierId == null,
        );
      } else {
        await provider.addItem(
          name: _name.text.trim(),
          quantity: _quantity.text.trim(),
          unit: effectiveUnit,
          packContents: _packContents.text.trim(),
          notes: _notes.text.trim(),
          addedBy: user,
          status: _status,
          barcode: _barcode.text.trim(),
          categoryId: effectiveCategoryId,
          sellPrice: sellPriceVal,
          costPrice: costPriceVal,
          wholesalePrice: wholesalePriceVal,
          stock: stockVal,
          reorderLevel: reorderLevelVal,
          supplierId: _selectedSupplierId,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
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
      context.pop();
    } else if (provider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error!),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else {
      context.pop();
    }
  }

  // ── Barcode scanner ───────────────────────────────────────────────────────

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(),
        fullscreenDialog: true,
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _barcode.text = result);
    }
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  Color _statusColor(String s) {
    switch (s) {
      case AppConstants.demandAvailable:
        return AppColors.statusAvailable;
      case AppConstants.demandDeferred:
        return AppColors.statusDeferred;
      case AppConstants.demandUrgent:
        return AppColors.statusUrgent;
      default:
        return AppColors.statusPending;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case AppConstants.demandAvailable:
        return Icons.check_circle_rounded;
      case AppConstants.demandDeferred:
        return Icons.pause_circle_rounded;
      case AppConstants.demandUrgent:
        return Icons.priority_high_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case AppConstants.demandAvailable:
        return 'Available';
      case AppConstants.demandDeferred:
        return 'Deferred';
      case AppConstants.demandUrgent:
        return 'Urgent';
      default:
        return 'Pending';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 22),
            const SizedBox(width: 8),
            const Text('Discard Changes?'),
          ],
        ),
        content: const Text(
            'You have unsaved changes. Are you sure you want to go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DemandProvider>();
    final isBusy = provider.isBusy;
    final isLastStep = _currentStep == _totalSteps - 1;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.onSurface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _confirmDiscard() && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Builder(builder: (_) {
            final enteredName = _name.text.trim();
            if (enteredName.isEmpty) {
              return Text(
                _isEditing ? 'Edit Item' : 'Add Item',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 18),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEditing ? 'Edit Item' : 'Add Item',
                  style: TextStyle(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: Colors.grey.shade500),
                ),
                Text(
                  enteredName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          }),
          // Quick-save button in AppBar — only in edit mode, any step
          actions: _isEditing
              ? [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: isBusy
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Tooltip(
                            message: 'Save now (any step)',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _submitFromAnyStep,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.save_rounded,
                                        size: 16, color: Colors.white),
                                    SizedBox(width: 5),
                                    Text(
                                      'Save',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ]
              : null,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: _StepIndicator(
              currentStep: _currentStep,
              totalSteps: _totalSteps,
              stepLabels: const ['Basic', 'Order', 'Pricing', 'Inventory'],
              stepIcons: const [
                Icons.info_outline_rounded,
                Icons.inventory_2_outlined,
                Icons.sell_outlined,
                Icons.warehouse_outlined,
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            // ── Page content ────────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_currentStep),
                  child: _buildCurrentStep(isBusy),
                ),
              ),
            ),

            // ── Bottom navigation bar ───────────────────────────────────────
            _BottomNav(
              currentStep: _currentStep,
              totalSteps: _totalSteps,
              isLastStep: isLastStep,
              isEditing: _isEditing,
              isBusy: isBusy,
              onBack: _prevStep,
              onNext: _nextStep,
              onSaveNow: _isEditing && !isLastStep ? _submitFromAnyStep : null,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step router — only builds the active step
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCurrentStep(bool isBusy) {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4(isBusy);
      default:
        return _buildStep1();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Status chip helper
  // ─────────────────────────────────────────────────────────────────────────

  Widget _statusChip(String s) {
    final selected = _status == s;
    final color = _statusColor(s);
    return GestureDetector(
      onTap: () => setState(() => _status = s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_statusIcon(s),
                size: 20,
                color: selected ? color : Colors.grey.shade500),
            const SizedBox(height: 4),
            Text(
              _statusLabel(s),
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 — Basic Info
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    final categoryProvider = context.watch<CategoryProvider>();
    final categories = categoryProvider.categories;

    // Guard: if categoryId no longer exists (deleted category), fall back to null
    final validCategoryId = (_categoryId != null &&
            categories.any((c) => c.id == _categoryId))
        ? _categoryId!
        : 'general';
    if (validCategoryId == 'general' && _categoryId != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _categoryId = null));
    }

    return Form(
      key: _formStep1,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          _StepCard(
            title: 'Item Name',
            icon: Icons.inventory_2_outlined,
            color: AppColors.primary,
            child: AppTextField(
              controller: _name,
              label: 'Item name *',
              prefixIcon: Icons.inventory_2_outlined,
              textInputAction: TextInputAction.done,
              autofocus: !_isEditing,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
          ),
          const SizedBox(height: 14),

          // ── Category ──────────────────────────────────────────────────
          _StepCard(
            title: 'Category',
            icon: Icons.label_outline_rounded,
            color: Colors.purple.shade600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: validCategoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'general',
                      child: Text(
                        'None (General)',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    // Exclude any Firestore category whose id=='general'
                    // (the default General category) to avoid duplicate values.
                    ...categories
                        .where((c) => c.id != 'general')
                        .map((CategoryModel c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text(c.name),
                            )),
                  ],
                  onChanged: (v) =>
                      setState(() => _categoryId = (v == 'general') ? null : v),
                ),
                const SizedBox(height: 4),
                Text(
                  'Items without a category go to "General"',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Status ────────────────────────────────────────────────────
          _StepCard(
            title: 'Status',
            icon: Icons.flag_outlined,
            color: _statusColor(_status),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Expanded(child: _statusChip(AppConstants.demandPending)),
                    const SizedBox(width: 10),
                    Expanded(child: _statusChip(AppConstants.demandUrgent)),
                  ],
                ),
                const SizedBox(height: 10),
                // Row 2: Available | Deferred
                Row(
                  children: <Widget>[
                    Expanded(child: _statusChip(AppConstants.demandAvailable)),
                    const SizedBox(width: 10),
                    Expanded(child: _statusChip(AppConstants.demandDeferred)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 — Order Details
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Form(
      key: _formStep2,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          // ── Quantity + Unit ────────────────────────────────────────────
          _StepCard(
            title: 'Order Quantity',
            icon: Icons.numbers_rounded,
            color: Colors.blue.shade700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _quantity,
                  label: 'Qty to order',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.numbers_rounded,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (int.tryParse(v.trim()) == null) return 'Numbers only';
                    if (int.parse(v.trim()) <= 0) return 'Min 1';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _unit,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Packaging type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: [
                    ...AppConstants.demandUnits.map(
                      (u) => DropdownMenuItem(value: u, child: Text(u)),
                    ),
                    const DropdownMenuItem(
                      value: AppConstants.demandUnitCustom,
                      child: Text(
                        'Custom…',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _unit = v;
                      _isCustomUnit = v == AppConstants.demandUnitCustom;
                      if (!_isCustomUnit) _customUnitCtrl.clear();
                    });
                  },
                ),
                if (_isCustomUnit) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _customUnitCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Custom packaging name',
                      hintText: 'e.g. Dozen, Roll, Bundle…',
                      prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                      filled: true,
                      fillColor: Colors.blue.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blue.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blue.shade200),
                      ),
                    ),
                    validator: (v) {
                      if (!_isCustomUnit) return null;
                      if (v == null || v.trim().isEmpty) {
                        return 'Custom packaging name required';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Pack Contents ──────────────────────────────────────────────
          _StepCard(
            title: 'Pack Contents',
            icon: Icons.open_in_new_rounded,
            color: Colors.teal.shade600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _packContents,
                  label: 'Contents per pack (optional)',
                  prefixIcon: Icons.open_in_new_rounded,
                  textInputAction: TextInputAction.next,
                  hint: 'e.g. 10 kg, 500 ml, 12 pcs',
                ),
                const SizedBox(height: 4),
                Text(
                  'What is inside each package — shown in WhatsApp messages as "2 Carton × 10 kg"',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Barcode ────────────────────────────────────────────────────
          _StepCard(
            title: 'Barcode / SKU',
            icon: Icons.qr_code_2_rounded,
            color: const Color(0xFFE53935),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _barcode,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Barcode or SKU',
                          hintText: 'Type or scan barcode',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                          fillColor: Colors.transparent,
                          filled: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _scanBarcode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_scanner_rounded,
                                size: 18, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Scan',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Notes ──────────────────────────────────────────────────────
          _StepCard(
            title: 'Notes',
            icon: Icons.notes_outlined,
            color: Colors.grey.shade600,
            child: AppTextField(
              controller: _notes,
              label: 'Additional notes (optional)',
              prefixIcon: Icons.notes_outlined,
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3 — Pricing
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep3() {
    return Form(
      key: _formStep3,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          _StepCard(
            title: 'Sell Price',
            icon: Icons.sell_rounded,
            color: AppColors.statusAvailable,
            child: _PriceField(
              controller: _sellPrice,
              label: 'Sell Price *',
              hint: '200',
              accentColor: AppColors.statusAvailable,
              icon: Icons.sell_rounded,
              textInputAction: TextInputAction.next,
              nextFocusNode: _costFocus,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Sell price is required';
                final p = double.tryParse(v.trim());
                if (p == null) return 'Enter a valid price';
                if (p < 0) return 'Price cannot be negative';
                return null;
              },
            ),
          ),
          const SizedBox(height: 14),

          _StepCard(
            title: 'Cost Price',
            icon: Icons.shopping_bag_outlined,
            color: AppColors.statusPending,
            subtitle: 'Optional — used for profit tracking',
            child: _PriceField(
              controller: _costPrice,
              label: 'Cost Price (optional)',
              hint: 'Leave empty if not applicable',
              accentColor: AppColors.statusPending,
              icon: Icons.shopping_bag_outlined,
              focusNode: _costFocus,
              textInputAction: TextInputAction.next,
              nextFocusNode: _wholesaleFocus,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final p = double.tryParse(v.trim());
                if (p == null) return 'Enter a valid price';
                if (p < 0) return 'Price cannot be negative';
                return null;
              },
            ),
          ),
          const SizedBox(height: 14),

          _StepCard(
            title: 'Wholesale Price',
            icon: Icons.storefront_outlined,
            color: AppColors.statusDeferred,
            subtitle: 'Optional — for bulk/wholesale buyers',
            child: _PriceField(
              controller: _wholesalePrice,
              label: 'Wholesale Price (optional)',
              hint: 'Leave empty if not applicable',
              accentColor: AppColors.statusDeferred,
              icon: Icons.storefront_outlined,
              focusNode: _wholesaleFocus,
              textInputAction: TextInputAction.done,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final p = double.tryParse(v.trim());
                if (p == null) return 'Enter a valid price';
                if (p < 0) return 'Price cannot be negative';
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 — Inventory + Summary
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep4(bool isBusy) {
    return Form(
      key: _formStep4,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          // ── Stock ──────────────────────────────────────────────────────
          _StepCard(
            title: 'Current Stock',
            icon: Icons.warehouse_outlined,
            color: AppColors.secondary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Stock Quantity',
                    hintText: '0',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                    fillColor: Colors.transparent,
                    filled: false,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Stock is required';
                    final p = int.tryParse(v.trim());
                    if (p == null) return 'Enter a valid number';
                    if (p < 0) return 'Stock cannot be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reorderLevel,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Low-Stock Alert Level',
                    hintText: '0',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                    fillColor: Colors.transparent,
                    filled: false,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null; // optional
                    final p = int.tryParse(v.trim());
                    if (p == null) return 'Enter a valid number';
                    if (p < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Alert when stock drops to or below this value. Set 0 to disable.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Supplier ─────────────────────────────────────────────────────
          Builder(builder: (ctx) {
            final suppliers =
                context.watch<SupplierProvider>().suppliers;
            if (suppliers.isEmpty) return const SizedBox.shrink();
            return _StepCard(
              title: 'Supplier',
              icon: Icons.storefront_rounded,
              color: const Color(0xFF1565C0),
              subtitle: 'Optional — link item to a supplier',
              child: DropdownButtonFormField<String?>(
                value: _selectedSupplierId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 4),
                  isDense: true,
                  fillColor: Colors.transparent,
                  filled: false,
                ),
                hint: const Text('No supplier linked',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey)),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey)),
                  ),
                  ...suppliers.map((s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(
                          s.name.isNotEmpty ? s.name : s.company,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                ],
                onChanged: (v) =>
                    setState(() => _selectedSupplierId = v),
              ),
            );
          }),
          const SizedBox(height: 20),

          // ── Summary Card ───────────────────────────────────────────────
          _SummaryCard(
            name: _name.text.trim().isEmpty ? '—' : _name.text.trim(),
            status: _status,
            statusColor: _statusColor(_status),
            statusIcon: _statusIcon(_status),
            statusLabel: _statusLabel(_status),
            qty: _quantity.text.trim(),
            unit: _isCustomUnit
                ? (_customUnitCtrl.text.trim().isEmpty
                    ? 'Piece'
                    : _customUnitCtrl.text.trim())
                : _unit,
            packContents: _packContents.text.trim(),
            sellPrice: _sellPrice.text.trim(),
            barcode: _barcode.text.trim(),
            stock: _stock.text.trim(),
            reorderLevel: _reorderLevel.text.trim(),
          ),
        ],
      ),
    );
  }
}

// ── Step Indicator ─────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
    required this.stepLabels,
    required this.stepIcons,
  });

  final int currentStep;
  final int totalSteps;
  final List<String> stepLabels;
  final List<IconData> stepIcons;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIdx = i ~/ 2;
            final done = stepIdx < currentStep;
            return Expanded(
              child: Container(
                height: 2,
                color: done ? AppColors.primary : Colors.grey.shade300,
              ),
            );
          }
          final stepIdx = i ~/ 2;
          final done = stepIdx < currentStep;
          final active = stepIdx == currentStep;
          final color = done || active ? AppColors.primary : Colors.grey.shade400;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.primary
                      : active
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : Colors.grey.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done || active ? AppColors.primary : Colors.grey.shade300,
                    width: active ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check_rounded,
                          size: 18, color: Colors.white)
                      : Icon(stepIcons[stepIdx],
                          size: 16,
                          color: active ? AppColors.primary : Colors.grey.shade400),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stepLabels[stepIdx],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Bottom Navigation Bar ──────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentStep,
    required this.totalSteps,
    required this.isLastStep,
    required this.isEditing,
    required this.isBusy,
    required this.onBack,
    required this.onNext,
    this.onSaveNow,
  });

  final int currentStep;
  final int totalSteps;
  final bool isLastStep;
  final bool isEditing;
  final bool isBusy;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback? onSaveNow;

  @override
  Widget build(BuildContext context) {

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button (step > 0)
          if (currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          if (currentStep > 0) const SizedBox(width: 10),



          // Continue / Save Item button
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: isBusy ? null : onNext,
              icon: isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      isLastStep
                          ? Icons.save_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
              label: Text(
                isLastStep ? 'Save Item' : 'Continue',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    isLastStep ? Colors.green.shade700 : AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step Card ──────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Summary Card ───────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.name,
    required this.status,
    required this.statusColor,
    required this.statusIcon,
    required this.statusLabel,
    required this.qty,
    required this.unit,
    required this.packContents,
    required this.sellPrice,
    required this.barcode,
    required this.stock,
    required this.reorderLevel,
  });

  final String name;
  final String status;
  final Color statusColor;
  final IconData statusIcon;
  final String statusLabel;
  final String qty;
  final String unit;
  final String packContents;
  final String sellPrice;
  final String barcode;
  final String stock;
  final String reorderLevel;

  @override
  Widget build(BuildContext context) {
    String qtyDisplay = '$qty $unit'.trim();
    if (packContents.isNotEmpty) qtyDisplay += ' × $packContents';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.05),
            AppColors.primary.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Review Summary',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SummaryRow(label: 'Item', value: name),
          _SummaryRow(label: 'Order', value: qtyDisplay),
          _SummaryRow(
            label: 'Status',
            value: statusLabel,
            valueColor: statusColor,
            valueIcon: statusIcon,
          ),
          if (sellPrice.isNotEmpty && sellPrice != '0')
            _SummaryRow(label: 'Sell Price', value: 'Rs. $sellPrice'),
          if (stock.isNotEmpty && stock != '0')
            _SummaryRow(label: 'Stock', value: '$stock units'),
          if (reorderLevel.isNotEmpty && reorderLevel != '0')
            _SummaryRow(label: 'Alert At', value: '≤ $reorderLevel units'),
          if (barcode.isNotEmpty)
            _SummaryRow(label: 'Barcode', value: barcode),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueIcon,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? valueIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          if (valueIcon != null)
            Icon(valueIcon, size: 13, color: valueColor ?? AppColors.onSurface),
          if (valueIcon != null) const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Keep-Alive Page Wrapper ────────────────────────────────────────────────────


// ── Price Field ────────────────────────────────────────────────────────────────

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.accentColor,
    required this.icon,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.focusNode,
    this.nextFocusNode,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final Color accentColor;
  final IconData icon;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      onFieldSubmitted: nextFocusNode != null
          ? (_) => FocusScope.of(context).requestFocus(nextFocusNode)
          : null,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: accentColor, size: 18),
        prefixText: 'Rs. ',
        prefixStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        isDense: true,
        fillColor: Colors.transparent,
        filled: false,
      ),
      validator: validator,
    );
  }
}
