import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/demand_item_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

// ── Sort options ─────────────────────────────────────────────────────────────
enum DemandSortOption {
  urgentFirst,   // default
  nameAZ,
  nameZA,
  priceHigh,
  priceLow,
  dateNewest,
  dateOldest,
  qtyHigh,
}

class DemandProvider extends ChangeNotifier {
  DemandProvider({
    FirestoreService? firestoreService,
    NotificationService? notificationService,
  })  : _db = firestoreService ?? FirestoreService(),
        _notif = notificationService;

  final FirestoreService _db;
  final NotificationService? _notif;

  List<DemandItemModel> _all = [];
  Set<String> _knownIds = {};
  Map<String, String> _knownStatuses = {};
  Map<String, int> _knownStocks = {};           // ← stock snapshot for diff
  bool _initialLoadDone = false;
  String? _currentUserId;

  String _query = '';
  String? _statusFilter;
  String? _categoryFilter;
  DemandSortOption _sortOption = DemandSortOption.urgentFirst;
  bool _isBusy = false;
  String? _error;
  bool _isOfflinePending = false;
  StreamSubscription<List<DemandItemModel>>? _sub;

  final Map<String, String> _pendingNewItems = {};
  Timer? _notifBatchTimer;

  static const _statusNotifCooldown = Duration(seconds: 30);
  final Map<String, DateTime> _lastStatusNotifTime = {};
  static const _stockNotifCooldown = Duration(minutes: 5);
  final Map<String, DateTime> _lastStockNotifTime = {};

  bool _canSendStatusNotif(String itemId) {
    final last = _lastStatusNotifTime[itemId];
    if (last != null &&
        DateTime.now().difference(last) < _statusNotifCooldown) {
      return false;
    }
    _lastStatusNotifTime[itemId] = DateTime.now();
    return true;
  }

  bool _canSendStockNotif(String itemId) {
    final last = _lastStockNotifTime[itemId];
    if (last != null &&
        DateTime.now().difference(last) < _stockNotifCooldown) {
      return false;
    }
    _lastStockNotifTime[itemId] = DateTime.now();
    return true;
  }

  // ── Multi-select state ─────────────────────────────────────────────────────

  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  bool get selectMode => _selectMode;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;
  bool get allSelected =>
      items.isNotEmpty && items.every((e) => _selectedIds.contains(e.id));

  // ── Filtered list ──────────────────────────────────────────────────────────

  List<DemandItemModel> get items {
    var result = _all;

    if (_statusFilter != null) {
      result = result.where((e) => e.status == _statusFilter).toList();
    }

    if (_categoryFilter != null) {
      if (_categoryFilter == 'general') {
        result = result
            .where((e) => e.categoryId == null || e.categoryId!.isEmpty)
            .toList();
      } else {
        result =
            result.where((e) => e.categoryId == _categoryFilter).toList();
      }
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              e.notes.toLowerCase().contains(q) ||
              e.barcode.toLowerCase().contains(q))
          .toList();
    }

    switch (_sortOption) {
      case DemandSortOption.urgentFirst:
        result.sort((a, b) {
          if (a.isUrgent == b.isUrgent) return 0;
          return a.isUrgent ? -1 : 1;
        });
      case DemandSortOption.nameAZ:
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case DemandSortOption.nameZA:
        result.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case DemandSortOption.priceHigh:
        result.sort((a, b) => b.totalSellPrice.compareTo(a.totalSellPrice));
      case DemandSortOption.priceLow:
        result.sort((a, b) => a.totalSellPrice.compareTo(b.totalSellPrice));
      case DemandSortOption.dateNewest:
        result.sort((a, b) => b.lastEditedBy.at.compareTo(a.lastEditedBy.at));
      case DemandSortOption.dateOldest:
        result.sort((a, b) => a.lastEditedBy.at.compareTo(b.lastEditedBy.at));
      case DemandSortOption.qtyHigh:
        result.sort((a, b) => b.quantityInt.compareTo(a.quantityInt));
    }

    return result;
  }

  List<DemandItemModel> get urgentItems =>
      _all.where((e) => e.isUrgent).toList();
  List<DemandItemModel> get recentItems => _all.take(5).toList();

  /// Items that are marked Available but stock == 0
  List<DemandItemModel> get outOfStockItems =>
      _all.where((e) => e.isOutOfStock).toList();

  /// Items approaching reorder level
  List<DemandItemModel> get lowStockItems =>
      _all.where((e) => e.hasLowStock).toList();

  /// Items linked to a specific supplier
  List<DemandItemModel> itemsBySupplier(String supplierId) =>
      _all.where((e) => e.supplierId == supplierId).toList();

  int get urgentCount => _all.where((e) => e.isUrgent).length;
  int get pendingCount => _all.where((e) => e.isPending).length;
  int get availableCount => _all.where((e) => e.isAvailable).length;
  int get deferredCount => _all.where((e) => e.isDeferred).length;
  int get outOfStockCount => outOfStockItems.length;
  int get lowStockCount => lowStockItems.length;
  int get totalCount => _all.length;

  List<DemandItemModel> get allItems => List.unmodifiable(_all);

  // ── Pending + Urgent price totals (for summary section) ────────────────────

  List<DemandItemModel> get pendingUrgentItems =>
      _all.where((e) => e.isPending || e.isUrgent).toList();

  List<DemandItemModel> get deferredItems =>
      _all.where((e) => e.isDeferred).toList();

  int get pendingUrgentCount => pendingUrgentItems.length;
  int get deferredItemsCount => deferredItems.length;

  // ── Pending + Urgent totals (qty × price) ──────────────────────────────────

  double get totalPendingUrgentSellPrice =>
      pendingUrgentItems.fold(0.0, (s, e) => s + e.totalSellPrice);

  double? get totalPendingUrgentCostPrice {
    final priced =
        pendingUrgentItems.where((e) => e.costPrice != null).toList();
    if (priced.isEmpty) return null;
    return priced.fold<double>(0.0, (s, e) => s + e.totalCostPrice!);
  }

  double? get totalPendingUrgentWholesalePrice {
    final priced =
        pendingUrgentItems.where((e) => e.wholesalePrice != null).toList();
    if (priced.isEmpty) return null;
    return priced.fold<double>(0.0, (s, e) => s + e.totalWholesalePrice!);
  }

  // ── Deferred totals (qty × price) ──────────────────────────────────────────

  double get totalDeferredSellPrice =>
      deferredItems.fold(0.0, (s, e) => s + e.totalSellPrice);

  double? get totalDeferredCostPrice {
    final priced = deferredItems.where((e) => e.costPrice != null).toList();
    if (priced.isEmpty) return null;
    return priced.fold<double>(0.0, (s, e) => s + e.totalCostPrice!);
  }

  double? get totalDeferredWholesalePrice {
    final priced =
        deferredItems.where((e) => e.wholesalePrice != null).toList();
    if (priced.isEmpty) return null;
    return priced.fold<double>(0.0, (s, e) => s + e.totalWholesalePrice!);
  }

  DemandSortOption get sortOption => _sortOption;
  String get query => _query;
  String? get statusFilter => _statusFilter;
  String? get categoryFilter => _categoryFilter;
  bool get isBusy => _isBusy;
  String? get error => _error;
  bool get isOfflinePending => _isOfflinePending;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void startListening({String? currentUserId}) {
    if (currentUserId != null) _currentUserId = currentUserId;
    _sub?.cancel();
    _initialLoadDone = false;
    _sub = _db.watchDemandItems().listen(
      (list) {
        if (_initialLoadDone && _notif != null) {
          for (final item in list) {
            final isOtherUser = item.addedBy.uid != _currentUserId;

            if (!_knownIds.contains(item.id) && isOtherUser) {
              _enqueueBatchNotification(item.id, item.name);
            }

            if (_knownIds.contains(item.id)) {
              final prevStatus = _knownStatuses[item.id];
              final changedByOther = item.lastEditedBy.uid != _currentUserId;
              if (prevStatus != null &&
                  prevStatus != item.status &&
                  changedByOther) {
                _pendingNewItems.remove(item.id);
                if ((item.status == AppConstants.demandPending ||
                        item.status == AppConstants.demandUrgent) &&
                    _canSendStatusNotif(item.id)) {
                  _notif!.showForegroundStatusNotification(
                    item.name,
                    item.status,
                  );
                }
              }

              // ── Stock change notifications ────────────────────────────
              final prevStock = _knownStocks[item.id];
              if (prevStock != null && prevStock != item.stock &&
                  _canSendStockNotif(item.id)) {
                if (item.stock == 0 && item.isAvailable) {
                  _notif!.showOutOfStockNotification(item.name);
                } else if (item.hasLowStock && item.stock < (prevStock)) {
                  _notif!.showLowStockNotification(
                      item.name, item.stock, item.reorderLevel);
                }
              }
            }
          }
        }

        _knownIds = list.map((e) => e.id).toSet();
        _knownStatuses = {for (final e in list) e.id: e.status};
        _knownStocks   = {for (final e in list) e.id: e.stock};
        _all = list;
        _initialLoadDone = true;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        _sub = null;
        notifyListeners();
      },
    );
  }

  static const _batchWindow = Duration(milliseconds: 1500);

  void _enqueueBatchNotification(String itemId, String itemName) {
    _pendingNewItems[itemId] = itemName;
    _notifBatchTimer?.cancel();
    _notifBatchTimer = Timer(_batchWindow, _flushBatchNotification);
  }

  Future<void> _flushBatchNotification() async {
    if (_pendingNewItems.isEmpty || _notif == null) return;
    final names = _pendingNewItems.values.toList();
    final count = names.length;
    final firstName = names.first;
    _pendingNewItems.clear();
    if (count == 1) {
      await _notif!.showForegroundDemandNotification(firstName);
    } else {
      await _notif!.showForegroundBatchNotification(count, firstName);
    }
  }

  void stopListening() {
    _notifBatchTimer?.cancel();
    _pendingNewItems.clear();
    _sub?.cancel();
  }

  void setSortOption(DemandSortOption opt) {
    _sortOption = opt;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setStatusFilter(String? filter) {
    _statusFilter = filter;
    notifyListeners();
  }

  void setCategoryFilter(String? filter) {
    _categoryFilter = filter;
    notifyListeners();
  }

  /// Clears all active filters and resets sort to default (urgentFirst).
  void resetFilters() {
    _query = '';
    _statusFilter = null;
    _categoryFilter = null;
    _sortOption = DemandSortOption.urgentFirst;
    notifyListeners();
  }

  void clearOfflinePending() {
    _isOfflinePending = false;
    notifyListeners();
  }

  // ── Barcode uniqueness helpers ─────────────────────────────────────────────

  DemandItemModel? findByBarcode(String barcode, {String? excludeId}) {
    final code = barcode.trim().toLowerCase();
    if (code.isEmpty) return null;
    for (final item in _all) {
      if (excludeId != null && item.id == excludeId) continue;
      if (item.barcode.toLowerCase() == code) return item;
    }
    return null;
  }

  bool isBarcodeUnique(String barcode, {String? excludeId}) =>
      findByBarcode(barcode, excludeId: excludeId) == null;

  // ── CRUD operations ────────────────────────────────────────────────────────

  Future<void> addItem({
    required String name,
    required String quantity,
    required String unit,
    String packContents = '',
    required String notes,
    required UserModel addedBy,
    String? status,
    String? barcode,
    String? categoryId,
    bool suppressNotification = false,
    double sellPrice = 0.0,
    double? costPrice,
    double? wholesalePrice,
    int stock = 0,
    int reorderLevel = 0,
    String? supplierId,
  }) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      final audit = AuditRef(
          uid: addedBy.uid, name: addedBy.name, at: DateTime.now());
      final effectiveStatus = status ?? AppConstants.demandPending;
      // Auto-set status to available when stock > 0
      final resolvedStatus =
          stock > 0 ? AppConstants.demandAvailable : effectiveStatus;
      // Initial price history snapshot
      final initialHistory = <Map<String, dynamic>>[
        if (sellPrice > 0)
          {'type': 'sell', 'price': sellPrice, 'date': DateTime.now().toIso8601String()},
        if (costPrice != null)
          {'type': 'cost', 'price': costPrice, 'date': DateTime.now().toIso8601String()},
      ];
      final item = DemandItemModel(
        id: '',
        name: name.trim(),
        quantity: quantity.trim(),
        unit: unit,
        packContents: packContents.trim(),
        notes: notes.trim(),
        status: resolvedStatus,
        barcode: (barcode ?? '').trim(),
        addedBy: audit,
        lastEditedBy: audit,
        categoryId: categoryId,
        sellPrice: sellPrice,
        costPrice: costPrice,
        wholesalePrice: wholesalePrice,
        stock: stock,
        reorderLevel: reorderLevel,
        supplierId: supplierId,
        priceHistory: initialHistory,
      );
      await _db.addDemandItem(item);

      if (!suppressNotification) {
        _notif?.sendDemandNotification(name.trim());
      }
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> sendBulkAddNotification({
    required String firstItemName,
    required int itemCount,
  }) async {
    if (itemCount <= 0) return;
    await _notif?.sendDemandNotification(
      firstItemName,
      itemCount: itemCount,
    );
  }

  Future<void> updateItem({
    required DemandItemModel item,
    required String? name,
    required String? quantity,
    required String? unit,
    String? packContents,
    required String? notes,
    required String? status,
    String? barcode,
    String? categoryId,
    bool clearCategoryId = false,
    required UserModel editedBy,
    double? sellPrice,
    double? costPrice,
    bool clearCostPrice = false,
    double? wholesalePrice,
    bool clearWholesalePrice = false,
    int? stock,
    int? reorderLevel,
    String? supplierId,
    bool clearSupplierId = false,
  }) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      final previousStatus = item.status;
      final now = DateTime.now();

      // Build updated price history when prices change
      var updatedHistory = List<Map<String, dynamic>>.from(item.priceHistory);
      if (sellPrice != null && sellPrice != item.sellPrice && sellPrice > 0) {
        updatedHistory.add({
          'type': 'sell',
          'price': sellPrice,
          'date': now.toIso8601String(),
        });
        // Keep only last 20 snapshots
        if (updatedHistory.length > 20) {
          updatedHistory = updatedHistory.sublist(updatedHistory.length - 20);
        }
      }
      if (costPrice != null && costPrice != item.costPrice) {
        updatedHistory.add({
          'type': 'cost',
          'price': costPrice,
          'date': now.toIso8601String(),
        });
        if (updatedHistory.length > 20) {
          updatedHistory = updatedHistory.sublist(updatedHistory.length - 20);
        }
      }

      // Respect the user's explicit status choice — do NOT auto-override here.
      // (Auto-set to 'available' when stock>0 is only applied on *new* items via addItem.)
      final resolvedStatus = status;

      final updated = item.copyWith(
        name: name,
        quantity: quantity,
        unit: unit,
        packContents: packContents,
        notes: notes,
        status: resolvedStatus,
        barcode: barcode,
        lastEditedBy: AuditRef(
            uid: editedBy.uid, name: editedBy.name, at: now),
        categoryId: categoryId,
        clearCategoryId: clearCategoryId,
        sellPrice: sellPrice,
        costPrice: costPrice,
        clearCostPrice: clearCostPrice,
        wholesalePrice: wholesalePrice,
        clearWholesalePrice: clearWholesalePrice,
        stock: stock,
        reorderLevel: reorderLevel,
        supplierId: supplierId,
        clearSupplierId: clearSupplierId,
        priceHistory: updatedHistory,
      );
      await _db.updateDemandItem(updated);

      if (resolvedStatus != null &&
          resolvedStatus != previousStatus &&
          (resolvedStatus == AppConstants.demandPending ||
              resolvedStatus == AppConstants.demandUrgent) &&
          _canSendStatusNotif(updated.id)) {
        _notif?.sendDemandNotification(updated.name, statusChange: resolvedStatus);
      }
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteItem(String id) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      await _db.deleteDemandItem(id);
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) _selectMode = false;
      _lastStatusNotifTime.remove(id);
    } on TimeoutException {
      _isOfflinePending = true;
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) _selectMode = false;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> bulkUpdateStatus({
    required Set<String> ids,
    required String status,
    required UserModel editedBy,
  }) async {
    if (ids.isEmpty) return;
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      final now = DateTime.now();
      final audit = AuditRef(uid: editedBy.uid, name: editedBy.name, at: now);

      final toUpdate = <DemandItemModel>[];
      final toNotify = <DemandItemModel>[];

      for (final item in _all.where((e) => ids.contains(e.id))) {
        if (item.status == status) continue;
        final updated = item.copyWith(status: status, lastEditedBy: audit);
        toUpdate.add(updated);
        if ((status == AppConstants.demandPending ||
                status == AppConstants.demandUrgent) &&
            _canSendStatusNotif(item.id)) {
          toNotify.add(updated);
        }
      }

      await _db.batchUpdateDemandItems(toUpdate);

      for (final item in toNotify) {
        _notif?.sendDemandNotification(item.name, statusChange: status);
      }

      _selectMode = false;
      _selectedIds.clear();
    } on TimeoutException {
      _isOfflinePending = true;
      _selectMode = false;
      _selectedIds.clear();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteItems(Set<String> ids) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      await _db.deleteDemandItems(ids);
      _selectedIds.removeAll(ids);
      _selectMode = false;
      for (final id in ids) {
        _lastStatusNotifTime.remove(id);
      }
    } on TimeoutException {
      _isOfflinePending = true;
      _selectedIds.removeAll(ids);
      _selectMode = false;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> restoreItem(DemandItemModel item) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      await _db.restoreDemandItem(item);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteAllItems() async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      final allIds = _all.map((e) => e.id).toSet();
      await _db.deleteDemandItems(allIds);
      _selectedIds.clear();
      _selectMode = false;
      _lastStatusNotifTime.clear();
    } on TimeoutException {
      _isOfflinePending = true;
      _selectedIds.clear();
      _selectMode = false;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  // ── Multi-select helpers ───────────────────────────────────────────────────

  void enterSelectMode(String firstId) {
    _selectMode = true;
    _selectedIds.add(firstId);
    notifyListeners();
  }

  void exitSelectMode() {
    _selectMode = false;
    _selectedIds.clear();
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) _selectMode = false;
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds.addAll(items.map((e) => e.id));
    notifyListeners();
  }

  void deselectAll() {
    _selectedIds.clear();
    notifyListeners();
  }

  void clearError() => _clearError();

  void _setBusy(bool v) {
    _isBusy = v;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _notifBatchTimer?.cancel();
    _pendingNewItems.clear();
    _sub?.cancel();
    super.dispose();
  }
}
