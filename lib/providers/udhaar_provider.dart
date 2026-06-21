import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/demand_item_model.dart';
import '../models/udhaar_entry_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class UdhaarProvider extends ChangeNotifier {
  UdhaarProvider({
    FirestoreService? firestoreService,
    NotificationService? notificationService,
  })  : _db = firestoreService ?? FirestoreService(),
        _notif = notificationService;

  final FirestoreService _db;
  final NotificationService? _notif;

  List<UdhaarEntryModel> _all = [];
  String _query = '';
  String? _statusFilter;
  String? _typeFilter;
  bool _isBusy = false;
  String? _error;
  bool _isOfflinePending = false;
  StreamSubscription<List<UdhaarEntryModel>>? _sub;

  // ── Notification cooldown (per entry) ──────────────────────────────────────
  // Prevents duplicate push/foreground notifications when the same udhaar entry
  // is edited multiple times in rapid succession.
  static const _editNotifCooldown = Duration(seconds: 30);
  final Map<String, DateTime> _lastEditNotifTime = {};

  /// Returns true and stamps the time if the entry is outside its cooldown.
  bool _canSendEditNotif(String entryId) {
    final last = _lastEditNotifTime[entryId];
    if (last != null &&
        DateTime.now().difference(last) < _editNotifCooldown) {
      return false;
    }
    _lastEditNotifTime[entryId] = DateTime.now();
    return true;
  }

  // ── Filtered list for main udhaar screen ──────────────────────────────────

  List<UdhaarEntryModel> get items {
    var result = _all;
    if (_statusFilter != null) {
      result = result.where((e) => e.status == _statusFilter).toList();
    }
    if (_typeFilter != null) {
      result = result.where((e) => e.type == _typeFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((e) => e.personName.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  /// All entries for a specific contact (by contactId), newest first.
  List<UdhaarEntryModel> entriesForContact(String contactId) {
    final list = _all
        .where((e) => e.contactId == contactId)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Pending net balance for a contact:
  /// positive = they owe us (given > received), negative = we owe them.
  double pendingBalanceForContact(String contactId) {
    double given = 0, received = 0;
    for (final e in _all) {
      if (e.contactId != contactId || !e.isPending) continue;
      if (e.isGiven) {
        given += e.amount;
      } else {
        received += e.amount;
      }
    }
    return given - received;
  }

  // ── Summary stats for udhaar screen ──────────────────────────────────────

  double get totalGiven => _all
      .where((e) => e.isGiven && e.isPending)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get totalReceived => _all
      .where((e) => e.isReceived && e.isPending)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get netBalance => totalGiven - totalReceived;

  int get totalCount => _all.length;
  int get pendingCount => _all.where((e) => e.isPending).length;
  int get settledCount => _all.where((e) => e.isSettled).length;

  List<UdhaarEntryModel> get recentPending =>
      _all.where((e) => e.isPending).take(3).toList();

  /// Top 5 debtors (personName → total pending given amount), highest first.
  List<MapEntry<String, double>> get topDebtors {
    final map = <String, double>{};
    for (final e in _all) {
      if (e.isGiven && e.isPending) {
        map[e.personName] = (map[e.personName] ?? 0) + e.amount;
      }
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  String get query => _query;
  String? get statusFilter => _statusFilter;
  String? get typeFilter => _typeFilter;
  bool get isBusy => _isBusy;
  String? get error => _error;
  bool get isOfflinePending => _isOfflinePending;

  int get givenCount => _all.where((e) => e.isGiven).length;
  int get receivedCount => _all.where((e) => e.isReceived).length;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void startListening() {
    if (_sub != null) return;
    _sub = _db.watchUdhaarEntries().listen(
      (list) {
        _all = list;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        _sub = null;
        notifyListeners();
      },
    );
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  // ── Filter helpers ─────────────────────────────────────────────────────────

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setStatusFilter(String? status) {
    _statusFilter = status;
    notifyListeners();
  }

  void setTypeFilter(String? type) {
    _typeFilter = type;
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _statusFilter = null;
    _typeFilter = null;
    notifyListeners();
  }

  void clearOfflinePending() {
    _isOfflinePending = false;
    notifyListeners();
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  Future<void> addEntry({
    required String personName,
    required double amount,
    required String type,
    required String notes,
    required UserModel addedBy,
    String? contactId,
    String? contactType,
  }) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      final audit =
          AuditRef(uid: addedBy.uid, name: addedBy.name, at: DateTime.now());
      final entry = UdhaarEntryModel(
        id: '',
        personName: personName.trim(),
        amount: amount,
        type: type,
        status: AppConstants.udhaarPending,
        notes: notes.trim(),
        createdAt: DateTime.now(),
        addedBy: audit,
        lastEditedBy: audit,
        contactId: contactId,
        contactType: contactType,
      );
      await _db.addUdhaarEntry(entry);

      _notif?.showForegroundUdhaarAddedNotification(
        personName: personName.trim(),
        amount: amount,
        type: type,
      );
      _notif?.sendUdhaarNotification(
        personName: personName.trim(),
        amount: amount,
        type: type,
        action: 'added',
      );
    } on TimeoutException {
      // Data was written to local cache — will sync when online.
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateEntry({
    required UdhaarEntryModel entry,
    required String personName,
    required double amount,
    required String type,
    required String notes,
    required UserModel editedBy,
    DateTime? createdAt,
    String? contactId,
    String? contactType,
    bool clearContact = false,
  }) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      final updated = entry.copyWith(
        personName: personName.trim(),
        amount: amount,
        type: type,
        notes: notes.trim(),
        createdAt: createdAt,
        lastEditedBy: AuditRef(
            uid: editedBy.uid, name: editedBy.name, at: DateTime.now()),
        contactId: contactId,
        contactType: contactType,
        clearContact: clearContact,
      );
      await _db.updateUdhaarEntry(updated);

      if (_canSendEditNotif(entry.id)) {
        _notif?.showForegroundUdhaarEditedNotification(
          personName: personName.trim(),
          amount: amount,
        );
        _notif?.sendUdhaarNotification(
          personName: personName.trim(),
          amount: amount,
          type: type,
          action: 'edited',
        );
      }
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteEntry(String id) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      // Find entry before deleting for notification info.
      final entry = _all.firstWhere((e) => e.id == id,
          orElse: () => UdhaarEntryModel(
                id: id,
                personName: '',
                amount: 0,
                type: AppConstants.udhaarGiven,
                status: AppConstants.udhaarPending,
                notes: '',
                createdAt: DateTime.now(),
                addedBy:
                    AuditRef(uid: '', name: '', at: DateTime.now()),
                lastEditedBy:
                    AuditRef(uid: '', name: '', at: DateTime.now()),
              ));
      await _db.deleteUdhaarEntry(id);
      _lastEditNotifTime.remove(id); // free cooldown entry

      if (entry.personName.isNotEmpty) {
        _notif?.sendUdhaarNotification(
          personName: entry.personName,
          amount: entry.amount,
          type: entry.type,
          action: 'deleted',
        );
      }
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> settleEntry({
    required UdhaarEntryModel entry,
    required UserModel settledBy,
  }) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      await _db.settleUdhaarEntry(
        id: entry.id,
        settledBy: AuditRef(
            uid: settledBy.uid, name: settledBy.name, at: DateTime.now()),
      );

      _notif?.showForegroundUdhaarSettledNotification(
        personName: entry.personName,
        amount: entry.amount,
        type: entry.type,
      );
      _notif?.sendUdhaarNotification(
        personName: entry.personName,
        amount: entry.amount,
        type: entry.type,
        action: 'settled',
      );
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  /// Settles every pending entry for [contactId] in one Firestore batch.
  /// Returns the number of entries settled.
  Future<int> settleAllPendingForContact({
    required String contactId,
    required UserModel settledBy,
  }) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    int count = 0;
    try {
      final pending = _all
          .where((e) => e.contactId == contactId && e.isPending)
          .toList();
      if (pending.isEmpty) return 0;
      count = pending.length;

      final audit = AuditRef(
          uid: settledBy.uid, name: settledBy.name, at: DateTime.now());

      await _db.batchSettleUdhaarEntries(
        ids: pending.map((e) => e.id).toList(),
        settledBy: audit,
      );

      final totalAmount = pending.fold(0.0, (s, e) => s + e.amount);
      final dominantType = pending.where((e) => e.isGiven).length >=
              pending.where((e) => !e.isGiven).length
          ? AppConstants.udhaarGiven
          : AppConstants.udhaarReceived;
      _notif?.showForegroundUdhaarSettledNotification(
        personName: pending.first.personName,
        amount: totalAmount,
        type: dominantType,
      );
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
    return count;
  }

  /// Restores a previously deleted udhaar entry using its original Firestore ID.
  /// Called when the user taps UNDO within 15 seconds of deleting.
  Future<void> restoreEntry(UdhaarEntryModel entry) async {
    _setBusy(true);
    _error = null;
    _isOfflinePending = false;
    try {
      await _db.restoreUdhaarEntry(entry);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
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
    _sub?.cancel();
    super.dispose();
  }
}
