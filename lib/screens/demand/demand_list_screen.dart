import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/category_model.dart';
import '../../models/demand_item_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/demand_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../services/import_service.dart';
import '../../widgets/undo_snackbar.dart';
import '../../services/search_history_service.dart';
import '../../widgets/shimmer_loading.dart';
import 'barcode_scanner_screen.dart';

class DemandListScreen extends StatefulWidget {
  const DemandListScreen({super.key});

  @override
  State<DemandListScreen> createState() => _DemandListScreenState();
}

class _DemandListScreenState extends State<DemandListScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  bool _loading = true;

  // Stored provider reference for safe listener cleanup in dispose().
  DemandProvider? _demandProv;
  List<String> _history = [];
  bool _showHistory = false;
  bool _barcodeSearchMode = false;
  bool _statusExpanded = false;
  bool _sortExpanded = false;
  bool _categoryExpanded = false;
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
    _loadHistory();
    _searchFocus.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AuthProvider>().currentUser?.uid;
      _demandProv = context.read<DemandProvider>();
      _demandProv!.startListening(currentUserId: uid);
      // Only reset filters when no filter was pre-set from another screen
      // (e.g. Home screen status buttons or Category screen set filters
      //  before navigating here — resetting unconditionally broke those).
      if (_demandProv!.statusFilter == null && _demandProv!.categoryFilter == null) {
        _searchCtrl.clear();
      }
      context.read<SupplierProvider>().startListening();
      context.read<CategoryProvider>().startListening();
      // Clear shimmer on first data event instead of a fixed 800 ms delay.
      _demandProv!.addListener(_clearDemandLoading);
    });
  }

  Future<void> _loadHistory() async {
    final h = await SearchHistoryService.load();
    if (mounted) setState(() => _history = h);
  }

  void _onFocusChange() {
    setState(() {
      _showHistory = _searchFocus.hasFocus && _searchCtrl.text.isEmpty;
    });
  }

  Future<void> _submitSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await SearchHistoryService.add(q);
    await _loadHistory();
    setState(() => _showHistory = false);
  }

  Future<void> _openBarcodeSearch(DemandProvider demand) async {
    _searchFocus.unfocus();
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(),
        fullscreenDialog: true,
      ),
    );
    if (code != null && code.isNotEmpty && mounted) {
      _searchCtrl.text = code;
      demand.setQuery(code);
      SearchHistoryService.add(code);
      _loadHistory();
      setState(() {
        _showHistory = false;
        _barcodeSearchMode = true;
      });
    }
  }

  void _applyHistoryItem(String query, DemandProvider demand) {
    _searchCtrl.text = query;
    _searchCtrl.selection = TextSelection.collapsed(offset: query.length);
    demand.setQuery(query);
    _searchFocus.unfocus();
    setState(() => _showHistory = false);
    SearchHistoryService.add(query);
  }

  Future<void> _removeHistoryItem(String query) async {
    await SearchHistoryService.remove(query);
    await _loadHistory();
  }

  void _clearDemandLoading() {
    if (_loading && mounted) {
      setState(() => _loading = false);
      _demandProv?.removeListener(_clearDemandLoading);
    }
  }

  @override
  void dispose() {
    _demandProv?.removeListener(_clearDemandLoading);
    _searchFocus.removeListener(_onFocusChange);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Full reset: clears filters + search + collapses panels.
  /// Use only when user explicitly wants to clear everything.
  void _resetFiltersAndState() {
    if (!mounted) return;
    context.read<DemandProvider>().resetFilters();
    _searchCtrl.clear();
    setState(() {
      _statusExpanded = false;
      _sortExpanded = false;
      _categoryExpanded = false;
    });
  }

  /// Lightweight: only collapses filter panels — preserves active filters.
  /// Use after returning from sub-screens (Edit, Add, Categories, Pricing)
  /// so the user comes back to the same filtered view they left.
  void _collapseFilterPanels() {
    if (!mounted) return;
    setState(() {
      _statusExpanded = false;
      _sortExpanded = false;
      _categoryExpanded = false;
    });
  }

  // â”€â”€ Status helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Color _chipBgColor(String status) {
    switch (status) {
      case AppConstants.demandAvailable:
        return AppColors.statusAvailableBg;
      case AppConstants.demandDeferred:
        return AppColors.statusDeferredBg;
      case AppConstants.demandUrgent:
        return AppColors.statusUrgentBg;
      case 'out_of_stock':
        return const Color(0xFFFFEBEE);
      default:
        return AppColors.statusPendingBg;
    }
  }

  Color _chipTextColor(String status) {
    switch (status) {
      case AppConstants.demandAvailable:
        return AppColors.statusAvailable;
      case AppConstants.demandDeferred:
        return AppColors.statusDeferred;
      case AppConstants.demandUrgent:
        return AppColors.statusUrgent;
      case 'out_of_stock':
        return const Color(0xFFB71C1C);
      default:
        return AppColors.statusPending;
    }
  }

  String _chipLabel(String status) {
    switch (status) {
      case AppConstants.demandAvailable:
        return 'Available';
      case AppConstants.demandDeferred:
        return 'Deferred';
      case AppConstants.demandUrgent:
        return 'Urgent';
      case 'out_of_stock':
        return 'Out of Stock';
      default:
        return 'Pending';
    }
  }

  IconData _chipIcon(String status) {
    switch (status) {
      case AppConstants.demandAvailable:
        return Icons.check_circle_outline_rounded;
      case AppConstants.demandDeferred:
        return Icons.pause_circle_outline_rounded;
      case AppConstants.demandUrgent:
        return Icons.priority_high_rounded;
      case 'out_of_stock':
        return Icons.remove_shopping_cart_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    final today = DateTime(now.year, now.month, now.day);
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    if (dtDay == today) return 'Today ${DateFormat('HH:mm').format(dt)}';
    final yesterday = today.subtract(const Duration(days: 1));
    if (dtDay == yesterday) return 'Yesterday';
    if (dt.year == now.year) return DateFormat('d MMM').format(dt);
    return DateFormat('d MMM yyyy').format(dt);
  }

  // ── Status picker bottom sheet ──────────────────────────────────────────────

  void _showStatusPicker(BuildContext context, DemandItemModel item) {
    final auth = context.read<AuthProvider>();
    if (!auth.canEdit) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final statuses = [
          (AppConstants.demandPending, 'Pending', AppColors.statusPending,
              Icons.schedule_rounded),
          (AppConstants.demandAvailable, 'Available', AppColors.statusAvailable,
              Icons.check_circle_rounded),
          (AppConstants.demandDeferred, 'Deferred', AppColors.statusDeferred,
              Icons.pause_circle_rounded),
          (AppConstants.demandUrgent, 'Urgent', AppColors.statusUrgent,
              Icons.priority_high_rounded),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Change Status',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(item.name,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Divider(height: 20),
                ...statuses.map((s) {
                  final isSelected = item.status == s.$1;
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: s.$3.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(s.$4, color: s.$3, size: 20),
                    ),
                    title: Text(s.$2,
                        style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500)),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: s.$3)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!isSelected) _setStatus(context, item, s.$1);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setStatus(
      BuildContext context, DemandItemModel item, String newStatus) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    await context.read<DemandProvider>().updateItem(
          item: item,
          name: null,
          quantity: null,
          unit: null,
          notes: null,
          status: newStatus,
          editedBy: user,
        );
  }

  void _showBulkStatusPicker(BuildContext context) {
    final demand = context.read<DemandProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final count = demand.selectedCount;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final statuses = [
          (AppConstants.demandPending, 'Pending', AppColors.statusPending,
              Icons.schedule_rounded),
          (AppConstants.demandAvailable, 'Available', AppColors.statusAvailable,
              Icons.check_circle_rounded),
          (AppConstants.demandDeferred, 'Deferred', AppColors.statusDeferred,
              Icons.pause_circle_rounded),
          (AppConstants.demandUrgent, 'Urgent', AppColors.statusUrgent,
              Icons.priority_high_rounded),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Change Status',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(
                          'Apply to $count selected item${count == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                const Divider(height: 20),
                ...statuses.map((s) => ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: s.$3.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(s.$4, color: s.$3, size: 20),
                      ),
                      title: Text(s.$2,
                          style:
                              const TextStyle(fontWeight: FontWeight.w500)),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.read<DemandProvider>().bulkUpdateStatus(
                              ids: Set.from(demand.selectedIds),
                              status: s.$1,
                              editedBy: user,
                            );
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  // â”€â”€ WhatsApp share â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _buildWhatsAppMessage(DemandItemModel item) {
    final statusLabel = _chipLabel(item.status);
    final lines = <String>[
      '📦 *Demand Request — Rafay Store*',
      '',
      '*Item:* ${item.name}',
    ];
    final qtyWa = item.quantityWhatsApp;
    if (qtyWa.isNotEmpty) {
      lines.add('*Order:* $qtyWa');
    }
    lines.add('*Status:* $statusLabel');
    if (item.notes.isNotEmpty) {
      lines
        ..add('')
        ..add('*Notes:* ${item.notes}');
    }
    lines
      ..add('')
      ..add('📍 ${AppConstants.storeAddress}')
      ..add('_${AppConstants.appName} v${AppConstants.appVersion}_');
    return lines.join('\n');
  }

  String _buildBulkWhatsAppMessage(List<DemandItemModel> selectedItems) {
    final urgent = selectedItems.where((e) => e.isUrgent).toList();
    final pending = selectedItems.where((e) => e.isPending).toList();
    final available = selectedItems.where((e) => e.isAvailable).toList();
    final deferred = selectedItems.where((e) => e.isDeferred).toList();

    final lines = <String>[
      '📦 *Bulk Demand Request — Rafay Store*',
      '',
      'Total: ${selectedItems.length} items',
    ];

    void addSection(
        String emoji, String label, List<DemandItemModel> items) {
      if (items.isEmpty) return;
      lines
        ..add('')
        ..add('$emoji *$label (${items.length}):*');
      for (final item in items) {
        final qty = item.quantityWhatsApp;
        final qtyPart = qty.isNotEmpty ? ' ($qty)' : '';
        lines.add('• ${item.name}$qtyPart');
        if (item.notes.isNotEmpty) {
          lines.add('  Notes: ${item.notes}');
        }
      }
    }

    addSection('🚨', 'Urgent', urgent);
    addSection('⏳', 'Pending', pending);
    addSection('✅', 'Available', available);
    addSection('⏸️', 'Deferred', deferred);

    lines
      ..add('')
      ..add('📍 ${AppConstants.storeAddress}')
      ..add('_${AppConstants.appName} v${AppConstants.appVersion}_');
    return lines.join('\n');
  }


  Future<void> _launchWhatsApp(
      {required String message,
      String phone = '',
      required BuildContext ctx}) async {
    final sanitised = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final encoded = Uri.encodeComponent(message);

    // ── Bypass canLaunchUrl entirely — it returns null on Android 11+ even
    //    when WhatsApp IS installed, because intent resolution is restricted.
    //    Instead just try to launch and catch the PlatformException.

    // 1️⃣  whatsapp:// deep-link — opens the app directly, no browser
    final waUri = sanitised.isEmpty
        ? Uri.parse('whatsapp://send?text=$encoded')
        : Uri.parse('whatsapp://send?phone=$sanitised&text=$encoded');
    try {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {
      // WhatsApp not installed or can't handle — fall through
    }

    // 2️⃣  wa.me universal link — opens in browser / WhatsApp web
    final waMeUri = sanitised.isEmpty
        ? Uri.parse('https://wa.me/?text=$encoded')
        : Uri.parse('https://wa.me/$sanitised?text=$encoded');
    try {
      await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {
      // also failed
    }

    // 3️⃣  Nothing worked — show snackbar
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
            content: Text('Could not open WhatsApp. Is it installed?'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _showWhatsAppShareSheet(BuildContext context, String message,
      {String headerTitle = ''}) {
    final suppliers = context
        .read<SupplierProvider>()
        .suppliers
        .where((s) => s.whatsappNumber.isNotEmpty)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: suppliers.isEmpty ? 0.35 : 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.25,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.chat_rounded,
                        color: Color(0xFF25D366), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Share on WhatsApp',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        if (headerTitle.isNotEmpty)
                          Text(headerTitle,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.preview_rounded,
                              size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 5),
                          Text('Message preview',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500)),
                        ]),
                        const SizedBox(height: 8),
                        Text(message,
                            style: const TextStyle(fontSize: 12.5, height: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _WhatsAppTile(
                    avatar: const Icon(Icons.contacts_rounded,
                        color: Color(0xFF25D366), size: 22),
                    title: 'Share with any contact',
                    subtitle: 'Opens WhatsApp — you choose who to send to',
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchWhatsApp(message: message, ctx: context);
                    },
                  ),
                  if (suppliers.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Row(children: [
                        Icon(Icons.people_outline,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Text('Send directly to a supplier',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    ...suppliers.map((s) => _WhatsAppTile(
                          avatar: CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.green.shade50,
                            child: Text(
                                s.name.isNotEmpty
                                    ? s.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green.shade700)),
                          ),
                          title: s.name,
                          subtitle: s.company.isNotEmpty
                              ? s.company
                              : s.whatsappNumber,
                          trailing: Text(s.whatsappNumber,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _launchWhatsApp(
                                message: message,
                                phone: s.whatsappNumber,
                                ctx: context);
                          },
                        )),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Text('No suppliers with WhatsApp numbers yet.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade400)),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Item Detail popup (tap) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showItemDetails(BuildContext context, DemandItemModel item,
      bool canEdit, bool isAdmin, [bool isViewer = false]) {
    final dateFmt = DateFormat('MMM d, yyyy  h:mm a');
    final cats = context.read<CategoryProvider>().categories;
    final catId = item.categoryId ?? '';
    final catName = catId.isEmpty
        ? 'General'
        : cats.firstWhere((c) => c.id == catId,
            orElse: () => CategoryModel(id: catId, name: 'General')).name;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final statusBg = _chipBgColor(item.status);
        final statusTxt = _chipTextColor(item.status);
        final statusLbl = _chipLabel(item.status);
        final statusIco = _chipIcon(item.status);

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (_, scrollCtrl) => SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              // â”€â”€ Handle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              // â”€â”€ Item name + status â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: item.isUrgent
                              ? AppColors.statusUrgent
                              : AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: statusTxt.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIco, size: 13, color: statusTxt),
                          const SizedBox(width: 5),
                          Text(statusLbl,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: statusTxt)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Quantity + Category row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.quantity.isNotEmpty && item.quantity != '0')
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.straighten_rounded,
                              size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(item.quantityDisplay,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600)),
                        ],
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.label_rounded,
                              size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            catName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),

              // â”€â”€ Scrollable content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  children: [
                    // â”€â”€ Pricing section (hidden for viewer) â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (!isViewer) ...[
                    _DetailSectionTitle(
                        icon: Icons.sell_rounded,
                        title: 'Pricing',
                        color: AppColors.statusAvailable),
                    const SizedBox(height: 10),

                    _PriceDetailRow(
                      label: 'Sell Price',
                      value: item.sellPriceDisplay,
                      icon: Icons.sell_rounded,
                      color: AppColors.statusAvailable,
                      isMain: true,
                    ),
                    if (item.costPriceDisplay != null) ...[
                      const SizedBox(height: 8),
                      _PriceDetailRow(
                        label: 'Cost Price',
                        value: item.costPriceDisplay!,
                        icon: Icons.shopping_bag_outlined,
                        color: Colors.grey.shade700,
                        isMain: false,
                      ),
                    ],
                    if (item.wholesalePriceDisplay != null) ...[
                      const SizedBox(height: 8),
                      _PriceDetailRow(
                        label: 'Wholesale Price',
                        value: item.wholesalePriceDisplay!,
                        icon: Icons.storefront_outlined,
                        color: Colors.grey.shade700,
                        isMain: false,
                      ),
                    ],

                    const SizedBox(height: 16),
                    ], // end !isViewer pricing

                    // â”€â”€ Price History section (hidden for viewer) â”€â”€â”€â”€â”€â”€
                    if (!isViewer && item.priceHistory.isNotEmpty) ...[
                      _DetailSectionTitle(
                          icon: Icons.history_rounded,
                          title: 'Price History',
                          color: const Color(0xFF6750A4)),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF6750A4).withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF6750A4)
                                  .withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          children: [
                            ...([...item.priceHistory]
                                  ..sort((a, b) {
                                    DateTime toDate(dynamic d) {
                                      if (d is DateTime) return d;
                                      if (d is String) {
                                        return DateTime.tryParse(d) ?? DateTime(2000);
                                      }
                                      try {
                                        return (d as dynamic).toDate() as DateTime;
                                      } catch (_) {
                                        return DateTime(2000);
                                      }
                                    }
                                    return toDate(b['date'])
                                        .compareTo(toDate(a['date']));
                                  }))
                                .take(5)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                              final i = entry.key;
                              final ph = entry.value;
                              final rawDate = ph['date'];
                              DateTime dt;
                              try {
                                if (rawDate is DateTime) {
                                  dt = rawDate;
                                } else if (rawDate is String) {
                                  dt = DateTime.tryParse(rawDate) ?? DateTime(2000);
                                } else {
                                  dt = (rawDate as dynamic).toDate() as DateTime;
                                }
                              } catch (_) {
                                dt = DateTime(2000);
                              }
                              final price =
                                  (ph['price'] as num?)?.toDouble() ?? 0.0;
                              final type =
                                  ph['type'] as String? ?? 'sell';
                              final isSell = type == 'sell';
                              final typeColor = isSell
                                  ? AppColors.statusAvailable
                                  : AppColors.statusPending;
                              final typeLabel = isSell ? 'Sell' : 'Cost';
                              // Inline price formatter (same as model)
                              final priceStr = price == price.truncateToDouble()
                                  ? 'Rs. ${price.toInt()}'
                                  : 'Rs. ${price.toStringAsFixed(2)}';
                              final dateStr = DateFormat('MMM d, yyyy')
                                  .format(dt);
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: typeColor
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(typeLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: typeColor,
                                              )),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          priceStr,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1A1A2E),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (i <
                                      (item.priceHistory.length > 5
                                              ? 5
                                              : item.priceHistory.length) -
                                          1)
                                    Divider(
                                        height: 1,
                                        color: Colors.grey.shade200),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // â”€â”€ Inventory section (hidden for viewer) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (!isViewer) ...[
                    _DetailSectionTitle(
                        icon: Icons.warehouse_outlined,
                        title: 'Inventory',
                        color: AppColors.secondary),
                    const SizedBox(height: 10),
                    _StockDetailRow(
                      stock: item.stock,
                      reorderLevel: item.reorderLevel,
                    ),
                    ], // end !isViewer inventory

                    // â”€â”€ Barcode â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (item.hasBarcode) ...[
                      const SizedBox(height: 16),
                      _DetailSectionTitle(
                          icon: Icons.qr_code_2_rounded,
                          title: 'Barcode / SKU',
                          color: const Color(0xFFE53935)),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: item.barcode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Barcode copied: ${item.barcode}'),
                                duration: const Duration(seconds: 2)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935)
                                .withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFFE53935)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.qr_code_2_rounded,
                                  color: Color(0xFFE53935), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.barcode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    letterSpacing: 1.2,
                                    color: Color(0xFFE53935),
                                  ),
                                ),
                              ),
                              const Icon(Icons.copy_rounded,
                                  size: 14, color: Color(0xFFE53935)),
                              const SizedBox(width: 4),
                              Text('Copy',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // â”€â”€ Notes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (item.notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DetailSectionTitle(
                          icon: Icons.notes_rounded,
                          title: 'Notes',
                          color: AppColors.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          item.notes,
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.5),
                        ),
                      ),
                    ],

                    // â”€â”€ Audit info â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _AuditRow(
                            icon: Icons.person_add_alt_1_rounded,
                            label: 'Added by',
                            name: item.addedBy.name,
                            date: dateFmt.format(item.addedBy.at),
                          ),
                          const SizedBox(height: 8),
                          _AuditRow(
                            icon: Icons.edit_rounded,
                            label: 'Last edited by',
                            name: item.lastEditedBy.name,
                            date: dateFmt.format(item.lastEditedBy.at),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // â”€â”€ Action buttons strip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 10, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border:
                      Border(top: BorderSide(color: Colors.grey.shade200)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, -2)),
                  ],
                ),
                child: Row(
                  children: [
                    if (canEdit) ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.edit_outlined,
                          label: 'Edit',
                          color: AppColors.primary,
                          onTap: () async {
                            Navigator.pop(ctx);
                            await context.push('/demand/edit', extra: item);
                            _collapseFilterPanels();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Status',
                          color: _chipTextColor(item.status),
                          onTap: () {
                            Navigator.pop(ctx);
                            Future.delayed(
                                const Duration(milliseconds: 150), () {
                              if (context.mounted) {
                                _showStatusPicker(context, item);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!isViewer)
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.chat_rounded,
                        label: 'Share',
                        color: const Color(0xFF25D366),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showWhatsAppShareSheet(
                              context, _buildWhatsAppMessage(item),
                              headerTitle: item.name);
                        },
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          color: Colors.red,
                          onTap: () {
                            Navigator.pop(ctx);
                            _deleteWithUndo(context, item);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  // â”€â”€ Long-press action sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showItemActions(BuildContext context, DemandItemModel item,
      bool canEdit, bool isAdmin, [bool isViewer = false]) {
    final demand = context.read<DemandProvider>();
    if (demand.selectMode) {
      demand.toggleSelection(item.id);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text(item.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              Text('${item.quantityDisplay} · ${_chipLabel(item.status)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const Divider(height: 24),
              if (canEdit)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/demand/edit', extra: item);
                  },
                ),
              if (item.hasBarcode)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.qr_code_2_rounded,
                      color: Color(0xFFE53935)),
                  title: const Text('Copy Barcode',
                      style: TextStyle(color: Color(0xFFE53935))),
                  subtitle: Text(item.barcode,
                      style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.copy_rounded, size: 16),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: item.barcode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Barcode copied: ${item.barcode}'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),

              if (canEdit)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_chipIcon(item.status),
                      color: _chipTextColor(item.status)),
                  title: const Text('Change Status'),
                  subtitle: Text('Current: ${_chipLabel(item.status)}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (context.mounted) _showStatusPicker(context, item);
                    });
                  },
                ),

              if (!isViewer)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.chat_rounded,
                      color: Color(0xFF25D366), size: 20),
                ),
                title: const Text('Share on WhatsApp',
                    style: TextStyle(
                        color: Color(0xFF128C7E),
                        fontWeight: FontWeight.w500)),
                subtitle: const Text(
                    'Send this item to a supplier or contact',
                    style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showWhatsAppShareSheet(context, _buildWhatsAppMessage(item),
                      headerTitle: item.name);
                },
              ),

              if (isAdmin)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_box_outlined,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text('Select',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.read<DemandProvider>().enterSelectMode(item.id);
                  },
                ),

              if (isAdmin)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteWithUndo(context, item);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ Quick Price Edit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showQuickEdit(BuildContext context, DemandItemModel item) {
    final sellCtrl = TextEditingController(
        text: item.sellPrice > 0 ? item.sellPrice.toStringAsFixed(0) : '');
    final costCtrl = TextEditingController(
        text: item.costPrice != null
            ? item.costPrice!.toStringAsFixed(0)
            : '');
    final wsCtrl = TextEditingController(
        text: item.wholesalePrice != null
            ? item.wholesalePrice!.toStringAsFixed(0)
            : '');
    final qtyCtrl = TextEditingController(
        text: item.quantity.isNotEmpty && item.quantity != '0'
            ? item.quantity
            : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_rounded,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Quick Edit',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(item.name,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                // -- Quantity ----------------------------------------
                TextField(
                  controller: qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  decoration: InputDecoration(
                    labelText: 'Order Quantity',
                    hintText: 'e.g. 5',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.straighten_rounded,
                          color: Colors.blue.shade600, size: 18),
                    ),
                    suffixText: item.unit.isNotEmpty ? item.unit : 'Piece',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.blue.shade600, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 13),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                // -- Sell Price --------------------------------------
                _QuickPriceField(
                  controller: sellCtrl,
                  label: 'Sell Price',
                  icon: Icons.sell_rounded,
                  color: Colors.green.shade600,
                  hint: 'Required',
                ),
                const SizedBox(height: 10),
                // -- Cost Price --------------------------------------
                _QuickPriceField(
                  controller: costCtrl,
                  label: 'Cost Price',
                  icon: Icons.shopping_cart_rounded,
                  color: Colors.orange.shade600,
                  hint: 'Optional',
                ),
                const SizedBox(height: 10),
                // -- Wholesale Price ---------------------------------
                _QuickPriceField(
                  controller: wsCtrl,
                  label: 'Wholesale Price',
                  icon: Icons.local_shipping_rounded,
                  color: Colors.purple.shade600,
                  hint: 'Optional',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save Changes',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      final demand = context.read<DemandProvider>();
                      final user =
                          context.read<AuthProvider>().currentUser;
                      if (user == null) return;
                      final newSell =
                          double.tryParse(sellCtrl.text.trim()) ??
                              item.sellPrice;
                      final rawCost = costCtrl.text.trim();
                      final rawWs = wsCtrl.text.trim();
                      final rawQty = qtyCtrl.text.trim();
                      final newCost = rawCost.isNotEmpty
                          ? double.tryParse(rawCost)
                          : null;
                      final newWs = rawWs.isNotEmpty
                          ? double.tryParse(rawWs)
                          : null;
                      final newQty = rawQty.isEmpty ? '0' : rawQty;
                      await demand.updateItem(
                        item: item,
                        name: item.name,
                        quantity: newQty,
                        unit: item.unit,
                        notes: item.notes,
                        status: item.status,
                        barcode:
                            item.barcode.isNotEmpty ? item.barcode : null,
                        categoryId: item.categoryId,
                        editedBy: user,
                        sellPrice: newSell,
                        costPrice: newCost,
                        clearCostPrice:
                            newCost == null && item.costPrice != null,
                        wholesalePrice: newWs,
                        clearWholesalePrice:
                            newWs == null && item.wholesalePrice != null,
                        stock: item.stock,
                      );
                      if (!context.mounted) return;
                      // Check if provider stored an error during the update
                      final err = context.read<DemandProvider>().error;
                      if (err != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Save failed: $err'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('"${item.name}" updated ✓'),
                          backgroundColor: AppColors.primary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Delete helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _deleteWithUndo(BuildContext ctx, DemandItemModel item) async {
    final provider = ctx.read<DemandProvider>();
    await provider.deleteItem(item.id);
    if (ctx.mounted) {
      UndoSnackbar.show(
        ctx,
        message: '"${item.name}" deleted',
        onUndo: () => provider.restoreItem(item),
      );
    }
  }

  Future<void> _confirmDeleteSelected(BuildContext ctx) async {
    final demand = ctx.read<DemandProvider>();
    final count = demand.selectedCount;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Text('Delete $count item${count == 1 ? '' : 's'}?'),
          ],
        ),
        content: Text(
            'This will permanently delete $count item${count == 1 ? '' : 's'}. This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete $count'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctx.mounted) {
      await ctx
          .read<DemandProvider>()
          .deleteItems(Set.from(demand.selectedIds));
    }
  }

  Future<void> _confirmDeleteAll(BuildContext ctx) async {
    final count = ctx.read<DemandProvider>().totalCount;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete ALL items?'),
        content: Text(
            'This will permanently delete all $count items. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctx.mounted) {
      await ctx.read<DemandProvider>().deleteAllItems();
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final demand = context.watch<DemandProvider>();
    final auth = context.watch<AuthProvider>();
    final canEdit = auth.canEdit;
    final isAdmin = auth.currentUser?.isAdmin ?? false;

    // Auto-expand category panel when a category filter is active
    // (e.g. when returning from the Category Management screen)
    if (demand.categoryFilter != null && !_categoryExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _categoryExpanded = true);
      });
    }
    // Auto-expand status panel when a status filter is active
    // (e.g. when arriving from home screen overview tiles)
    if (demand.statusFilter != null && !_statusExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _statusExpanded = true);
      });
    }
    final isViewer = auth.currentUser?.isViewer ?? false;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.divider,
        leading: demand.selectMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => demand.exitSelectMode(),
              )
            : null,
        title: demand.selectMode
            ? Text(
                '${demand.selectedCount} selected',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Demand Book',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (demand.totalCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${demand.totalCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
        actions: demand.selectMode
            ? []
            : [
                if (canEdit)
                  IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    tooltip: 'Import from CSV/Excel',
                    onPressed: () => ImportService.importFromFile(context),
                  ),
                PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) async {
                      if (v == 'delete_all') _confirmDeleteAll(context);
                      if (v == 'categories') {
                        await context.push('/demand/categories');
                        _collapseFilterPanels();
                      }
                      if (v == 'pricing') {
                        await context.push('/demand/pricing');
                        _collapseFilterPanels();
                      }
                    },
                    itemBuilder: (_) => [
                      if (!isViewer)
                        const PopupMenuItem(
                          value: 'pricing',
                          child: Row(children: [
                            Icon(Icons.price_change_rounded,
                                color: Color(0xFF7E57C2), size: 20),
                            SizedBox(width: 8),
                            Text('Pricing Analytics'),
                          ]),
                        ),
                      if (!isViewer)
                        const PopupMenuItem(
                          value: 'categories',
                          child: Row(children: [
                            Icon(Icons.label_outline_rounded,
                                color: Colors.purple, size: 20),
                            SizedBox(width: 8),
                            Text('Manage Categories'),
                          ]),
                        ),
                      if (isAdmin)
                        const PopupMenuItem(
                          value: 'delete_all',
                          child: Row(children: [
                            Icon(Icons.delete_forever,
                                color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Delete All',
                                style: TextStyle(color: Colors.red)),
                          ]),
                        ),
                    ]),
              ],
      ),
      floatingActionButton: !demand.selectMode && canEdit
          ? FloatingActionButton.extended(
              heroTag: 'demand_fab',
              onPressed: () async {
                await context.push('/demand/add');
                _collapseFilterPanels();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Item',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      body: Column(
        children: [
          // â”€â”€ Search bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (!demand.selectMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchBar(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    hintText: _barcodeSearchMode
                        ? 'Barcode: ${_searchCtrl.text}'
                        : 'Search by name, notes or barcodeâ€¦',
                    leading: _barcodeSearchMode
                        ? const Icon(Icons.qr_code_scanner_rounded,
                            color: Color(0xFFE53935))
                        : Icon(Icons.search_rounded,
                            color: Colors.grey.shade500),
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(
                        Colors.grey.shade100),
                    side: WidgetStatePropertyAll(
                        BorderSide(color: Colors.grey.shade200)),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    trailing: [
                      IconButton(
                        icon: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: _barcodeSearchMode
                              ? const Color(0xFFE53935)
                              : Colors.grey.shade500,
                        ),
                        tooltip: 'Search by barcode scan',
                        onPressed: () => _openBarcodeSearch(demand),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.clear_rounded,
                              color: Colors.grey.shade500),
                          onPressed: () {
                            _searchCtrl.clear();
                            demand.setQuery('');
                            setState(() => _barcodeSearchMode = false);
                          },
                        ),
                    ],
                    onChanged: (v) {
                      demand.setQuery(v);
                      setState(() {
                        _showHistory = v.isEmpty && _searchFocus.hasFocus;
                        if (v.isEmpty) _barcodeSearchMode = false;
                      });
                    },
                    onSubmitted: _submitSearch,
                  ),
                  if (_barcodeSearchMode && _searchCtrl.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code_2_rounded,
                              size: 13, color: Color(0xFFE53935)),
                          const SizedBox(width: 4),
                          Text(
                            'Barcode search active',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              demand.setQuery('');
                              setState(() => _barcodeSearchMode = false);
                            },
                            child: const Text('Clear',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFE53935),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // â”€â”€ Status filter (collapsible, default collapsed) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (!demand.selectMode) ...[
            GestureDetector(
              onTap: () =>
                  setState(() => _statusExpanded = !_statusExpanded),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.filter_list_rounded,
                        size: 15,
                        color: demand.statusFilter != null
                            ? AppColors.primary
                            : Colors.grey.shade500),
                    const SizedBox(width: 7),
                    Text('Status',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700)),
                    const SizedBox(width: 6),
                    if (demand.statusFilter != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          demand.statusFilter!,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary),
                        ),
                      )
                    else
                      Text('${demand.totalCount} items',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Icon(
                      _statusExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
            if (_statusExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    children: [
                      _StatusFilterChip(
                        label: 'All',
                        count: demand.totalCount,
                        selected: demand.statusFilter == null,
                        color: AppColors.onSurface,
                        icon: Icons.list_rounded,
                        onTap: () => demand.setStatusFilter(null),
                      ),
                      const SizedBox(width: 6),
                      _StatusFilterChip(
                        label: 'Pending',
                        count: demand.pendingCount,
                        selected: demand.statusFilter ==
                            AppConstants.demandPending,
                        color: AppColors.statusPending,
                        icon: Icons.schedule_rounded,
                        onTap: () => demand.setStatusFilter(
                            demand.statusFilter == AppConstants.demandPending
                                ? null
                                : AppConstants.demandPending),
                      ),
                      const SizedBox(width: 6),
                      _StatusFilterChip(
                        label: 'Available',
                        count: demand.availableCount,
                        selected: demand.statusFilter ==
                            AppConstants.demandAvailable,
                        color: AppColors.statusAvailable,
                        icon: Icons.check_circle_outline_rounded,
                        onTap: () => demand.setStatusFilter(
                            demand.statusFilter ==
                                    AppConstants.demandAvailable
                                ? null
                                : AppConstants.demandAvailable),
                      ),
                      const SizedBox(width: 6),
                      _StatusFilterChip(
                        label: 'Deferred',
                        count: demand.deferredCount,
                        selected: demand.statusFilter ==
                            AppConstants.demandDeferred,
                        color: AppColors.statusDeferred,
                        icon: Icons.pause_circle_outline_rounded,
                        onTap: () => demand.setStatusFilter(
                            demand.statusFilter ==
                                    AppConstants.demandDeferred
                                ? null
                                : AppConstants.demandDeferred),
                      ),
                      const SizedBox(width: 6),
                      _StatusFilterChip(
                        label: 'Urgent',
                        count: demand.urgentCount,
                        selected: demand.statusFilter ==
                            AppConstants.demandUrgent,
                        color: AppColors.statusUrgent,
                        icon: Icons.priority_high_rounded,
                        onTap: () => demand.setStatusFilter(
                            demand.statusFilter == AppConstants.demandUrgent
                                ? null
                                : AppConstants.demandUrgent),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          // â”€â”€ Sort (collapsible, default collapsed) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (!demand.selectMode) ...[
            GestureDetector(
              onTap: () => setState(() => _sortExpanded = !_sortExpanded),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sort_rounded,
                        size: 15, color: Colors.indigo.shade400),
                    const SizedBox(width: 7),
                    Text('Sort',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700)),
                    const SizedBox(width: 6),
                    Builder(builder: (_) {
                      final opt = _SortBar._options.firstWhere(
                        (o) => o.$1 == demand.sortOption,
                        orElse: () => _SortBar._options.first,
                      );
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(opt.$3,
                                size: 10,
                                color: Colors.indigo.shade600),
                            const SizedBox(width: 3),
                            Text(opt.$2,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.indigo.shade600)),
                          ],
                        ),
                      );
                    }),
                    const Spacer(),
                    Icon(
                      _sortExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
            if (_sortExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    children: _SortBar._options.map((opt) {
                      final isActive = demand.sortOption == opt.$1;
                      return Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: GestureDetector(
                          onTap: () => demand.setSortOption(opt.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.primary
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive
                                    ? AppColors.primary
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(opt.$3,
                                    size: 11,
                                    color: isActive
                                        ? Colors.white
                                        : Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(opt.$2,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isActive
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isActive
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],

          // â”€â”€ Category filter (collapsible, with item counts) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (!demand.selectMode)
            Consumer<CategoryProvider>(
              builder: (context, catProvider, _) {
                final categories = catProvider.categories;
                if (categories.length <= 1) return const SizedBox.shrink();
                final allItems = demand.allItems;
                final catCounts = <String, int>{
                  for (final cat in categories)
                    cat.id: cat.id == 'general'
                        ? allItems
                            .where((e) => e.isGeneralCategory)
                            .length
                        : allItems
                            .where((e) => e.categoryId == cat.id)
                            .length,
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: () => setState(
                          () => _categoryExpanded = !_categoryExpanded),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.label_rounded,
                                size: 15,
                                color: demand.categoryFilter != null
                                    ? Colors.purple.shade600
                                    : Colors.purple.shade300),
                            const SizedBox(width: 7),
                            Text('Category',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700)),
                            const SizedBox(width: 6),
                            if (demand.categoryFilter != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  categories
                                      .firstWhere(
                                        (c) =>
                                            c.id == demand.categoryFilter,
                                        orElse: () => categories.first,
                                      )
                                      .name,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.purple.shade700),
                                ),
                              )
                            else
                              Text('${categories.length} categories',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade400,
                                      fontWeight: FontWeight.w500)),
                            const Spacer(),
                            Icon(
                              _categoryExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_categoryExpanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          height: 42,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.fromLTRB(12, 4, 12, 0),
                            children: categories.map((cat) {
                              final activeFilter = demand.categoryFilter;
                              final isActive = (cat.id == 'general')
                                  ? activeFilter == 'general'
                                  : activeFilter == cat.id;
                              final count = catCounts[cat.id] ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () {
                                    if (isActive) {
                                      demand.setCategoryFilter(null);
                                    } else {
                                      demand.setCategoryFilter(cat.id);
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? Colors.purple.shade600
                                          : Colors.purple.shade50,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isActive
                                            ? Colors.purple.shade600
                                            : Colors.purple.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          cat.name,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isActive
                                                ? Colors.white
                                                : Colors.purple.shade700,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? Colors.white
                                                    .withValues(alpha: 0.25)
                                                : Colors.purple.shade100,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '$count',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: isActive
                                                  ? Colors.white
                                                  : Colors.purple.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          // â”€â”€ Selection bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (demand.selectMode)
            Container(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: Icon(
                      demand.allSelected
                          ? Icons.deselect
                          : Icons.select_all,
                      size: 18,
                    ),
                    label: Text(
                        demand.allSelected ? 'Deselect All' : 'Select All',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => demand.allSelected
                        ? demand.deselectAll()
                        : demand.selectAll(),
                  ),
                  const Spacer(),
                  if (canEdit && demand.selectedCount > 0)
                    IconButton(
                      icon: const Icon(Icons.swap_horiz_rounded),
                      tooltip: 'Change status',
                      onPressed: () => _showBulkStatusPicker(context),
                    ),
                  if (!isViewer && demand.selectedCount > 0)
                    IconButton(
                      icon: const Icon(Icons.chat_rounded,
                          color: Color(0xFF25D366)),
                      tooltip: 'Share on WhatsApp',
                      onPressed: () {
                        final selected = demand.items
                            .where(
                                (e) => demand.selectedIds.contains(e.id))
                            .toList();
                        final msg = _buildBulkWhatsAppMessage(selected);
                        _showWhatsAppShareSheet(context, msg,
                            headerTitle: '${demand.selectedCount} items');
                      },
                    ),
                  if (isAdmin && demand.selectedCount > 0)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      tooltip: 'Delete selected',
                      onPressed: () => _confirmDeleteSelected(context),
                    ),
                ],
              ),
            ),

          // â”€â”€ Search history â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_showHistory && _history.isNotEmpty)
            _buildSearchHistory(demand),

          // â”€â”€ List â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Expanded(child: _buildList(context, demand, canEdit, isAdmin, isViewer)),
        ],
      ),
      ),
    );
  }

  Widget _buildSearchHistory(DemandProvider demand) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      color: Colors.white,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('Recent Searches',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600)),
          ),
          ..._history.map((q) => ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                leading: Icon(Icons.history_rounded,
                    size: 18, color: Colors.grey.shade400),
                title: Text(q, style: const TextStyle(fontSize: 14)),
                trailing: IconButton(
                  icon:
                      Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                  tooltip: 'Remove',
                  onPressed: () => _removeHistoryItem(q),
                ),
                onTap: () => _applyHistoryItem(q, demand),
              )),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, DemandProvider demand, bool canEdit, bool isAdmin, [bool isViewer = false]) {
    if (_loading) {
      return ShimmerList(
          count: 6, itemBuilder: (_, __) => const DemandItemShimmer());
    }

    if (demand.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded,
                  color: Colors.red.shade400, size: 40),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(demand.error!,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              onPressed: () {
                demand.clearError();
                demand.startListening();
              },
            ),
          ],
        ),
      );
    }

    if (demand.items.isEmpty) {
      final hasFilter = demand.query.isNotEmpty ||
          demand.statusFilter != null ||
          demand.categoryFilter != null;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasFilter
                    ? Icons.search_off_rounded
                    : Icons.menu_book_rounded,
                size: 52,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilter ? 'No matching items' : 'No items yet',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                hasFilter
                    ? 'Try changing the search or filter'
                    : 'Tap + Add Item to build your demand list',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final uid = context.read<AuthProvider>().currentUser?.uid;
        demand.startListening(currentUserId: uid);
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
        itemCount: demand.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final item = demand.items[i];
          final isSelected = demand.selectedIds.contains(item.id);
          final effStatus = item.effectiveStatus;
          // Supplier name lookup
          final supplierName = item.supplierId != null
              ? context
                  .read<SupplierProvider>()
                  .suppliers
                  .where((s) => s.id == item.supplierId)
                  .map((s) => s.name)
                  .firstOrNull
              : null;
          // Category name lookup — falls back to 'General'
          final categoryName = (item.categoryId == null ||
                  item.categoryId!.isEmpty)
              ? 'General'
              : (context
                      .read<CategoryProvider>()
                      .categories
                      .where((c) => c.id == item.categoryId)
                      .map((c) => c.name)
                      .firstOrNull ??
                  'General');
          final card = _DemandCard(
            item: item,
            canEdit: canEdit,
            isAdmin: isAdmin,
            isViewer: isViewer,
            isSelected: isSelected,
            isSelectMode: demand.selectMode,
            chipBgColor: _chipBgColor(effStatus),
            chipTextColor: _chipTextColor(effStatus),
            chipLabel: _chipLabel(effStatus),
            dateLabel: _formatDate(item.lastEditedBy.at),
            supplierName: isViewer ? null : supplierName,
            categoryName: categoryName,
            onTap: demand.selectMode
                ? () => demand.toggleSelection(item.id)
                : () => _showItemDetails(context, item, canEdit, isAdmin, isViewer),
            onLongPress: () =>
                _showItemActions(context, item, canEdit, isAdmin, isViewer),
            onStatusTap: canEdit && !demand.selectMode
                ? () => _showStatusPicker(context, item)
                : null,
            onEdit: canEdit && !demand.selectMode
                ? () => _showQuickEdit(context, item)
                : null,
          );

          if (!canEdit || demand.selectMode) return card;

          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.horizontal,
            confirmDismiss: (direction) async {
              final newStatus =
                  direction == DismissDirection.startToEnd
                      ? AppConstants.demandUrgent
                      : AppConstants.demandAvailable;
              if (item.status == newStatus) return false;

              // â”€â”€ Confirmation dialog before status change â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              final newLabel = newStatus == AppConstants.demandUrgent
                  ? 'Urgent'
                  : 'Available';
              final newColor = newStatus == AppConstants.demandUrgent
                  ? AppColors.statusUrgent
                  : AppColors.statusAvailable;
              final newIcon = newStatus == AppConstants.demandUrgent
                  ? Icons.priority_high_rounded
                  : Icons.check_circle_rounded;

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dlgCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: newColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(newIcon, color: newColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text('Change Status?',
                          style: TextStyle(fontSize: 16)),
                    ],
                  ),
                  content: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade700),
                      children: [
                        const TextSpan(text: 'Mark '),
                        TextSpan(
                          text: '"${item.name}"',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E)),
                        ),
                        const TextSpan(text: ' as '),
                        TextSpan(
                          text: newLabel,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: newColor),
                        ),
                        const TextSpan(text: '?'),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dlgCtx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: newColor),
                      onPressed: () => Navigator.pop(dlgCtx, true),
                      child: Text('Mark $newLabel'),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return false;
              await _setStatus(context, item, newStatus);
              return false;
            },
            background: Container(
              decoration: BoxDecoration(
                color: AppColors.statusUrgent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.statusUrgent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.priority_high_rounded,
                        color: AppColors.statusUrgent, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text('Urgent',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.statusUrgent,
                          fontSize: 13)),
                ],
              ),
            ),
            secondaryBackground: Container(
              decoration: BoxDecoration(
                color: AppColors.statusAvailable.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Available',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.statusAvailable,
                          fontSize: 13)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.statusAvailable.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_circle_rounded,
                        color: AppColors.statusAvailable, size: 20),
                  ),
                ],
              ),
            ),
            child: card,
          );
        },
      ),
    );
  }
}

// â”€â”€ WhatsApp tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WhatsAppTile extends StatelessWidget {
  const _WhatsAppTile({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final Widget avatar;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!
            ],
            const SizedBox(width: 4),
            const Icon(Icons.send_rounded,
                size: 18, color: Color(0xFF25D366)),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Detail popup helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DetailSectionTitle extends StatelessWidget {
  const _DetailSectionTitle({
    required this.icon,
    required this.title,
    required this.color,
  });
  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 7),
        Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.3)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withValues(alpha: 0.2))),
      ],
    );
  }
}

class _PriceDetailRow extends StatelessWidget {
  const _PriceDetailRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isMain,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: 14, vertical: isMain ? 12 : 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isMain ? 0.07 : 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: color.withValues(alpha: isMain ? 0.2 : 0.12),
            width: isMain ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: isMain ? 18 : 15),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: isMain ? 14 : 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: isMain ? 17 : 14,
                  fontWeight:
                      isMain ? FontWeight.w800 : FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

class _StockDetailRow extends StatelessWidget {
  const _StockDetailRow({required this.stock, this.reorderLevel = 0});
  final int stock;
  final int reorderLevel;

  @override
  Widget build(BuildContext context) {
    // Use actual reorderLevel if set; fall back to hardcoded 50 only when disabled (0)
    final effectiveThreshold = reorderLevel > 0 ? reorderLevel : 50;
    final isLow = stock <= effectiveThreshold;
    final isOut = stock == 0;
    final color = isOut
        ? AppColors.statusUrgent
        : isLow
            ? Colors.orange.shade700
            : AppColors.secondary;
    final label = isOut
        ? 'Out of Stock'
        : reorderLevel > 0 && isLow
            ? 'Low — $stock / $reorderLevel alert'
            : '$stock units';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_rounded, color: color, size: 16),
          const SizedBox(width: 10),
          Text(
              isOut
                  ? 'Out of Stock'
                  : isLow
                      ? 'Stock Low'
                      : 'Stock Available',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          if (isLow)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.warning_amber_rounded,
                  size: 14, color: color),
            ),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({
    required this.icon,
    required this.label,
    required this.name,
    required this.date,
  });
  final IconData icon;
  final String label;
  final String name;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text('$label: ',
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            name.isNotEmpty ? '$name · $date' : date,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Status filter chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? Colors.white : color,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.28)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Demand item card ──────────────────────────────────────────────────────────

class _DemandCard extends StatelessWidget {
  const _DemandCard({
    required this.item,
    required this.canEdit,
    required this.isAdmin,
    this.isViewer = false,
    required this.isSelected,
    required this.isSelectMode,
    required this.chipBgColor,
    required this.chipTextColor,
    required this.chipLabel,
    required this.dateLabel,
    this.supplierName,
    this.categoryName,
    this.onTap,
    this.onLongPress,
    this.onStatusTap,
    this.onEdit,
  });

  final DemandItemModel item;
  final bool canEdit;
  final bool isAdmin;
  final bool isViewer;
  final bool isSelected;
  final bool isSelectMode;
  final Color chipBgColor;
  final Color chipTextColor;
  final String chipLabel;
  final String dateLabel;
  final String? supplierName;
  final String? categoryName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onStatusTap;
  final VoidCallback? onEdit;

  static IconData _statusIcon(String status) {
    switch (status) {
      case AppConstants.demandAvailable:
        return Icons.check_circle_rounded;
      case AppConstants.demandDeferred:
        return Icons.pause_circle_rounded;
      case AppConstants.demandUrgent:
        return Icons.priority_high_rounded;
      case 'out_of_stock':
        return Icons.remove_shopping_cart_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = chipTextColor;
    final isUrgent = item.isUrgent;

    final Color cardBg = isSelected
        ? Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.35)
        : isUrgent
            ? AppColors.statusUrgentBg
            : Colors.white;

    final Color borderColor = isSelected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
        : isUrgent
            ? AppColors.statusUrgent.withValues(alpha: 0.22)
            : AppColors.divider;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: accentColor, width: 4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkbox in select mode
                  if (isSelectMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 10, top: 2),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade400,
                        size: 22,
                      ),
                    ),

                  // â”€â”€ Main content column â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: isUrgent
                                      ? AppColors.statusUrgent
                                      : const Color(0xFF1A1A2E),
                                  letterSpacing: -0.2,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Status chip
                            GestureDetector(
                              onTap: onStatusTap,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: chipBgColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: accentColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _statusIcon(item.effectiveStatus),
                                      size: 11,
                                      color: chipTextColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      chipLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: chipTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        // -- Row 2: category + quantity ------------------
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 5,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Category badge
                            if (categoryName != null &&
                                categoryName!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                      color: Colors.purple.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.label_rounded,
                                        size: 9,
                                        color: Colors.purple.shade600),
                                    const SizedBox(width: 3),
                                    Text(
                                      categoryName!,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Quantity badge
                            if (item.quantity.isNotEmpty &&
                                item.quantity != '0')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                      color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.straighten_rounded,
                                        size: 9,
                                        color: Colors.grey.shade600),
                                    const SizedBox(width: 3),
                                    Text(
                                      item.quantityDisplay,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),


                          ],
                        ),

                        // â”€â”€ Notes row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        if (item.notes.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(Icons.notes_rounded,
                                    size: 12,
                                    color: Colors.grey.shade400),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.notes,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    height: 1.4,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // -- Supplier + Barcode row (same line) -----------
                        if ((supplierName != null &&
                            supplierName!.isNotEmpty) ||
                            item.hasBarcode) ...[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 5,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (supplierName != null &&
                                  supplierName!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE3F2FD),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: const Color(0xFF90CAF9)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.storefront_rounded,
                                          size: 10,
                                          color: Color(0xFF1565C0)),
                                      const SizedBox(width: 4),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 120),
                                        child: Text(
                                          supplierName!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1565C0),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (item.hasBarcode)
                                GestureDetector(
                                  onTap: () => Clipboard.setData(
                                      ClipboardData(text: item.barcode)),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE53935)
                                          .withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFFE53935)
                                              .withValues(alpha: 0.25)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                            Icons.qr_code_2_rounded,
                                            size: 10,
                                            color: Color(0xFFE53935)),
                                        const SizedBox(width: 3),
                                        ConstrainedBox(
                                          constraints:
                                              const BoxConstraints(maxWidth: 100),
                                          child: Text(
                                            item.barcode,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFE53935),
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Flexible(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (!isViewer &&
                                      item.costPriceDisplay != null)
                                    _PricePill(
                                      value: item.costPriceDisplay!,
                                      color: AppColors.statusAvailable,
                                      icon: Icons.price_check_rounded,
                                    ),
                                  if (!isViewer)
                                    _PricePill(
                                      value: item.sellPriceDisplay,
                                      color: const Color(0xFF1565C0),
                                      icon: Icons.sell_rounded,
                                    ),
                                  if (!isViewer)
                                    _StockPill(
                                      stock: item.stock,
                                      reorderLevel: item.reorderLevel,
                                      isOutOfStock: item.isOutOfStock,
                                    ),
                                ],
                              ),
                            ),
                            if (!isViewer &&
                                canEdit &&
                                !isSelectMode &&
                                onEdit != null) ...[
                              const SizedBox(width: 6),
                              _EditPill(onTap: onEdit!),
                            ],
                          ],
                        ),
                        // -- Footer: date ----------------------------------------
                        const SizedBox(height: 5),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Colors.grey.shade200,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                  size: 9, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(
                                dateLabel,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w400,
                                ),
                            ),
                          ],
                        ),
                      ],
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

// â”€â”€ Price pill â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PricePill extends StatelessWidget {
  const _PricePill({
    required this.value,
    required this.color,
    required this.icon,
  });

  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Stock pill â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StockPill extends StatelessWidget {
  const _StockPill({
    required this.stock,
    this.reorderLevel = 0,
    this.isOutOfStock = false,
  });
  final int stock;
  final int reorderLevel;
  final bool isOutOfStock;

  @override
  Widget build(BuildContext context) {
    if (isOutOfStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEF9A9A)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.remove_shopping_cart_rounded,
                size: 11, color: Color(0xFFB71C1C)),
            SizedBox(width: 4),
            Text(
              'Out of Stock',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB71C1C),
              ),
            ),
          ],
        ),
      );
    }
    // Use actual reorderLevel if set, otherwise fall back to 50
    final effectiveThreshold = reorderLevel > 0 ? reorderLevel : 50;
    final isLow = stock > 0 && stock <= effectiveThreshold;
    final color = isLow ? AppColors.statusUrgent : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isLow
            ? AppColors.statusUrgent.withValues(alpha: 0.07)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLow
              ? AppColors.statusUrgent.withValues(alpha: 0.25)
              : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLow ? Icons.warning_amber_rounded : Icons.inventory_2_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isLow && reorderLevel > 0 ? '$stock/$reorderLevel' : '$stock',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Combined edit pill -------------------------------------------------------

class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_rounded, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              'Quick Edit',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Pending / Urgent / Deferred summary section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PendingUrgentSummarySection extends StatefulWidget {
  const _PendingUrgentSummarySection({required this.demand});
  final DemandProvider demand;

  @override
  State<_PendingUrgentSummarySection> createState() =>
      _PendingUrgentSummarySectionState();
}

class _PendingUrgentSummarySectionState
    extends State<_PendingUrgentSummarySection> {

  String _fmt(double price) {
    if (price == price.truncateToDouble()) return 'Rs. ${price.toInt()}';
    return 'Rs. ${price.toStringAsFixed(2)}';
  }

  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final demand = widget.demand;
    // Pending + Urgent totals
    final puSell = demand.totalPendingUrgentSellPrice;
    final puCost = demand.totalPendingUrgentCostPrice;
    final puWholesale = demand.totalPendingUrgentWholesalePrice;
    final puCount = demand.pendingUrgentCount;
    final pendingCnt = demand.pendingCount;
    final urgentCnt = demand.urgentCount;

    // Deferred totals
    final defSell = demand.totalDeferredSellPrice;
    final defCost = demand.totalDeferredCostPrice;
    final defWholesale = demand.totalDeferredWholesalePrice;
    final defCount = demand.deferredItemsCount;

    // Collapsed header: show a single summary chip bar
    if (_collapsed) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.statusPending.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.bar_chart_rounded,
                  size: 13, color: AppColors.statusPending),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Summary  •  ${puCount + defCount} items  •  '
                'Sell: ${_fmt(puSell + defSell)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _collapsed = false),
              child: Row(
                children: [
                  Text('Expand',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // â”€â”€ Collapse toggle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.statusPending.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(Icons.bar_chart_rounded,
                    size: 12, color: AppColors.statusPending),
              ),
              const SizedBox(width: 6),
              Text(
                'Price Summary',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _collapsed = true),
                child: Row(
                  children: [
                    Text('Collapse',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_up_rounded,
                        size: 16, color: Colors.grey.shade500),
                  ],
                ),
              ),
            ],
          ),
        ),

        // â”€â”€ Pending + Urgent block â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if (puCount > 0)
          _SummaryBlock(
            title: 'Pending & Urgent',
            count: puCount,
            pills: [
              _SummaryCountPill(
                icon: Icons.schedule_rounded,
                label: '$pendingCnt',
                color: AppColors.statusPending,
              ),
              const SizedBox(width: 5),
              _SummaryCountPill(
                icon: Icons.priority_high_rounded,
                label: '$urgentCnt',
                color: AppColors.statusUrgent,
              ),
            ],
            iconColor: AppColors.statusPending,
            sellTotal: puSell,
            costTotal: puCost,
            wholesaleTotal: puWholesale,
            fmt: _fmt,
          ),

        if (puCount > 0 && defCount > 0) const SizedBox(height: 8),

        // â”€â”€ Deferred block â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if (defCount > 0)
          _SummaryBlock(
            title: 'Deferred',
            count: defCount,
            pills: [
              _SummaryCountPill(
                icon: Icons.hourglass_bottom_rounded,
                label: '$defCount',
                color: AppColors.statusDeferred,
              ),
            ],
            iconColor: AppColors.statusDeferred,
            sellTotal: defSell,
            costTotal: defCost,
            wholesaleTotal: defWholesale,
            fmt: _fmt,
          ),
      ],
    );
  }
}



class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.title,
    required this.count,
    required this.pills,
    required this.iconColor,
    required this.sellTotal,
    required this.costTotal,
    required this.wholesaleTotal,
    required this.fmt,
  });

  final String title;
  final int count;
  final List<Widget> pills;
  final Color iconColor;
  final double sellTotal;
  final double? costTotal;
  final double? wholesaleTotal;
  final String Function(double) fmt;

  @override
  Widget build(BuildContext context) {
    final hasCost = costTotal != null;
    final hasWholesale = wholesaleTotal != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
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
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.bar_chart_rounded,
                    size: 14, color: iconColor),
              ),
              const SizedBox(width: 7),
              Text(
                '$title — $count items',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              ...pills,
            ],
          ),
          const SizedBox(height: 10),
          // Price tiles row
          Row(
            children: [
              Expanded(
                child: _SummaryPriceTile(
                  label: 'Sell Total',
                  value: fmt(sellTotal),
                  icon: Icons.sell_rounded,
                  color: AppColors.statusAvailable,
                  isMain: true,
                ),
              ),
              if (hasCost) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _SummaryPriceTile(
                    label: 'Cost Total',
                    value: fmt(costTotal!),
                    icon: Icons.shopping_bag_outlined,
                    color: AppColors.statusPending,
                    isMain: false,
                  ),
                ),
              ],
              if (hasWholesale) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _SummaryPriceTile(
                    label: 'Wholesale',
                    value: fmt(wholesaleTotal!),
                    icon: Icons.local_shipping_outlined,
                    color: AppColors.secondary,
                    isMain: false,
                  ),
                ),
              ],
            ],
          ),
          if (!hasCost && !hasWholesale) ...[
            const SizedBox(height: 5),
            Text(
              'Cost/wholesale prices not set — edit items to add them.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}



class _SummaryCountPill extends StatelessWidget {
  const _SummaryCountPill({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryPriceTile extends StatelessWidget {
  const _SummaryPriceTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isMain,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isMain ? 0.09 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: isMain ? 13 : 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Quick Price Field â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _QuickPriceField extends StatelessWidget {
  const _QuickPriceField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.color,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color color;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, size: 18),
        ),
        prefixText: 'Rs ',
        prefixStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        isDense: true,
      ),
    );
  }
}

// â”€â”€ Sort Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SortBar extends StatelessWidget {
  const _SortBar({required this.current, required this.onChanged});

  final DemandSortOption current;
  final ValueChanged<DemandSortOption> onChanged;

  static const _options = [
    (DemandSortOption.urgentFirst, 'Urgent First', Icons.priority_high_rounded),
    (DemandSortOption.nameAZ, 'Name Aâ†’Z', Icons.sort_by_alpha_rounded),
    (DemandSortOption.nameZA, 'Name Zâ†’A', Icons.sort_by_alpha_rounded),
    (DemandSortOption.priceHigh, 'Price â†“', Icons.attach_money_rounded),
    (DemandSortOption.priceLow, 'Price â†‘', Icons.attach_money_rounded),
    (DemandSortOption.dateNewest, 'Newest', Icons.schedule_rounded),
    (DemandSortOption.dateOldest, 'Oldest', Icons.history_rounded),
    (DemandSortOption.qtyHigh, 'Qty â†“', Icons.format_list_numbered_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        children: [
          // Label
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 1),
            child: Center(
              child: Text(
                'Sort:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ),
          ..._options.map((opt) {
            final isActive = current == opt.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onChanged(opt.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive
                          ? AppColors.primary
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        opt.$3,
                        size: 11,
                        color: isActive
                            ? Colors.white
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        opt.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isActive
                              ? Colors.white
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

