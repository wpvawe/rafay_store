import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/customer_model.dart';
import '../models/demand_item_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

class CustomerProvider extends ChangeNotifier {
  CustomerProvider({FirestoreService? firestoreService})
      : _db = firestoreService ?? FirestoreService();

  final FirestoreService _db;

  List<CustomerModel> _all = [];
  String _query = '';
  bool _isBusy = false;
  String? _error;
  bool _isOfflinePending = false;
  StreamSubscription<List<CustomerModel>>? _sub;

  List<CustomerModel> get customers => _query.isEmpty
      ? _all
      : _all
          .where((c) =>
              c.name.toLowerCase().contains(_query.toLowerCase()) ||
              c.phone.contains(_query) ||
              c.whatsappNumber.contains(_query) ||
              c.address.toLowerCase().contains(_query.toLowerCase()))
          .toList();

  List<CustomerModel> get all => _all;
  int get totalCount => _all.length;
  String get query => _query;
  bool get isBusy => _isBusy;
  String? get error => _error;
  bool get isOfflinePending => _isOfflinePending;

  void startListening() {
    if (_sub != null) return;
    _sub = _db.watchCustomers().listen(
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

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void clearQuery() {
    _query = '';
    notifyListeners();
  }

  void clearOfflinePending() {
    _isOfflinePending = false;
    notifyListeners();
  }

  Future<void> addCustomer({
    required String name,
    required String phone,
    required String whatsappNumber,
    required String address,
    required String notes,
    required UserModel addedBy,
  }) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      final audit =
          AuditRef(uid: addedBy.uid, name: addedBy.name, at: DateTime.now());
      final customer = CustomerModel(
        id: '',
        name: name.trim(),
        phone: phone.trim(),
        whatsappNumber: whatsappNumber.trim(),
        address: address.trim(),
        notes: notes.trim(),
        addedBy: audit,
        lastEditedBy: audit,
        createdAt: DateTime.now(),
      );
      await _db.addCustomer(customer);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateCustomer({
    required CustomerModel customer,
    required String name,
    required String phone,
    required String whatsappNumber,
    required String address,
    required String notes,
    required UserModel editedBy,
  }) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      final updated = customer.copyWith(
        name: name.trim(),
        phone: phone.trim(),
        whatsappNumber: whatsappNumber.trim(),
        address: address.trim(),
        notes: notes.trim(),
        lastEditedBy:
            AuditRef(uid: editedBy.uid, name: editedBy.name, at: DateTime.now()),
      );
      await _db.updateCustomer(updated);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteCustomer(String id) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      await _db.deleteCustomer(id);
    } on TimeoutException {
      _isOfflinePending = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  /// Restores a previously deleted customer using its original Firestore ID.
  /// Called when the user taps UNDO within 15 seconds of deleting.
  Future<void> restoreCustomer(CustomerModel customer) async {
    _setBusy(true);
    _clearError();
    _isOfflinePending = false;
    try {
      await _db.restoreCustomer(customer);
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
