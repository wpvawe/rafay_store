import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/demand_item_model.dart';
import '../models/supplier_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

class SupplierProvider extends ChangeNotifier {
  SupplierProvider({FirestoreService? firestoreService})
      : _db = firestoreService ?? FirestoreService();

  final FirestoreService _db;

  List<SupplierModel> _all = [];
  String _query = '';
  bool _isBusy = false;
  String? _error;
  bool _isOfflinePending = false;
  StreamSubscription<List<SupplierModel>>? _sub;

  List<SupplierModel> get suppliers => _query.isEmpty
      ? _all
      : _all
          .where((s) =>
              s.name.toLowerCase().contains(_query.toLowerCase()) ||
              s.company.toLowerCase().contains(_query.toLowerCase()) ||
              s.productsSupplied
                  .toLowerCase()
                  .contains(_query.toLowerCase()) ||
              // FIX: Search by phone number and whatsapp number too
              s.phoneNumber.contains(_query) ||
              s.whatsappNumber.contains(_query) ||
              s.additionalNumbers.any((n) => n.number.contains(_query)))
          .toList();

  /// All suppliers unfiltered (for pickers).
  List<SupplierModel> get all => _all;

  /// Total unfiltered supplier count.
  int get totalCount => _all.length;

  String get query => _query;
  bool get isBusy => _isBusy;
  String? get error => _error;
  bool get isOfflinePending => _isOfflinePending;

  void startListening() {
    if (_sub != null) return;
    _sub = _db.watchSuppliers().listen(
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

  Future<void> refreshOnce() async {
    try {
      final list = await _db.fetchSuppliersFromServer();
      _all = list;
      notifyListeners();
    } catch (_) {}
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void clearOfflinePending() {
    _isOfflinePending = false;
    notifyListeners();
  }

  Future<void> addSupplier({
    required String name,
    required String company,
    required String productsSupplied,
    required String whatsappNumber,
    required String phoneNumber,
    required List<AdditionalNumber> additionalNumbers,
    required UserModel addedBy,
  }) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      final audit =
          AuditRef(uid: addedBy.uid, name: addedBy.name, at: DateTime.now());
      final supplier = SupplierModel(
        id: '',
        name: name.trim(),
        company: company.trim(),
        productsSupplied: productsSupplied.trim(),
        whatsappNumber: whatsappNumber.trim(),
        phoneNumber: phoneNumber.trim(),
        additionalNumbers:
            additionalNumbers.where((n) => n.number.isNotEmpty).toList(),
        addedBy: audit,
        lastEditedBy: audit,
      );
      await _db.addSupplier(supplier);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateSupplier({
    required SupplierModel supplier,
    required String name,
    required String company,
    required String productsSupplied,
    required String whatsappNumber,
    required String phoneNumber,
    required List<AdditionalNumber> additionalNumbers,
    required UserModel editedBy,
  }) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      final updated = supplier.copyWith(
        name: name.trim(),
        company: company.trim(),
        productsSupplied: productsSupplied.trim(),
        whatsappNumber: whatsappNumber.trim(),
        phoneNumber: phoneNumber.trim(),
        additionalNumbers:
            additionalNumbers.where((n) => n.number.isNotEmpty).toList(),
        lastEditedBy: AuditRef(
            uid: editedBy.uid, name: editedBy.name, at: DateTime.now()),
      );
      await _db.updateSupplier(updated);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteSupplier(String id) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      await _db.deleteSupplier(id);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  /// Restores a previously deleted supplier using its original Firestore ID.
  /// Called when the user taps UNDO within 15 seconds of deleting.
  Future<void> restoreSupplier(SupplierModel supplier) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      await _db.restoreSupplier(supplier);
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
