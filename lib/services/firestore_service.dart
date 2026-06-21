import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import '../models/category_model.dart';
import '../models/customer_model.dart';
import '../models/demand_item_model.dart';
import '../models/supplier_model.dart';
import '../models/udhaar_entry_model.dart';
import '../models/user_model.dart';

/// All Firestore read/write operations for the app.
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _kWriteTimeout = Duration(seconds: 5);

  // ─── Collection references ─────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(AppConstants.usersCollection);

  CollectionReference<Map<String, dynamic>> get _demandItems =>
      _db.collection(AppConstants.demandItemsCollection);

  CollectionReference<Map<String, dynamic>> get _suppliers =>
      _db.collection(AppConstants.suppliersCollection);

  CollectionReference<Map<String, dynamic>> get _udhaarEntries =>
      _db.collection(AppConstants.udhaarCollection);

  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection(AppConstants.customersCollection);

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection(AppConstants.categoriesCollection);

  // ─── User operations ───────────────────────────────────────────────────────

  Future<void> createUser(UserModel user) =>
      _users.doc(user.uid).set(user.toFirestore());

  Future<UserModel?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Stream<UserModel?> watchUser(String uid) =>
      _users.doc(uid).snapshots().map(
            (doc) => doc.exists ? UserModel.fromFirestore(doc) : null,
          );

  Stream<List<UserModel>> watchAllUsers() => _users
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(UserModel.fromFirestore).toList());

  Future<void> updateUserStatus({
    required String uid,
    required String status,
  }) =>
      _users.doc(uid).update({'status': status});

  Future<void> updateUserRole({
    required String uid,
    required String role,
  }) =>
      _users.doc(uid).update({'role': role});

  Future<void> updateFcmToken({
    required String uid,
    required String token,
  }) =>
      _users.doc(uid).set({'fcmToken': token}, SetOptions(merge: true));

  Future<List<String>> getApprovedFcmTokens({String? excludeUid}) async {
    final snap = await _users
        .where('status', isEqualTo: AppConstants.statusApproved)
        .get();
    return snap.docs
        .where((doc) => excludeUid == null || doc.id != excludeUid)
        .map((doc) => doc.data()['fcmToken'] as String?)
        .whereType<String>()
        .toList();
  }

  Future<List<String>> getApprovedNonViewerFcmTokens(
      {String? excludeUid}) async {
    final snap = await _users
        .where('status', isEqualTo: AppConstants.statusApproved)
        .get();
    return snap.docs
        .where((doc) => doc.data()['role'] != AppConstants.roleViewer)
        .where((doc) => excludeUid == null || doc.id != excludeUid)
        .map((doc) => doc.data()['fcmToken'] as String?)
        .whereType<String>()
        .toList();
  }

  // ─── Category operations ───────────────────────────────────────────────────

  Stream<List<CategoryModel>> watchCategories() => _categories
      .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs.map(CategoryModel.fromFirestore).toList());

  Future<DocumentReference> addCategory(CategoryModel category) =>
      _categories.add(category.toFirestore()).timeout(_kWriteTimeout);

  Future<void> updateCategory(CategoryModel category) =>
      _categories
          .doc(category.id)
          .update(category.toFirestore())
          .timeout(_kWriteTimeout);

  Future<void> deleteCategory(String id) =>
      _categories.doc(id).delete().timeout(_kWriteTimeout);

  // ─── Demand item operations ────────────────────────────────────────────────

  Stream<List<DemandItemModel>> watchDemandItems() => _demandItems
      .orderBy('addedBy.at', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(DemandItemModel.fromFirestore).toList());

  Future<DocumentReference> addDemandItem(DemandItemModel item) =>
      _demandItems.add(item.toFirestore()).timeout(_kWriteTimeout);

  Future<void> updateDemandItem(DemandItemModel item) =>
      _demandItems.doc(item.id).update(item.toFirestore()).timeout(_kWriteTimeout);

  Future<void> batchUpdateDemandItems(List<DemandItemModel> items) async {
    if (items.isEmpty) return;
    const batchSize = 500;
    for (int i = 0; i < items.length; i += batchSize) {
      final batch = _db.batch();
      final chunk = items.sublist(
        i,
        (i + batchSize) > items.length ? items.length : (i + batchSize),
      );
      for (final item in chunk) {
        batch.update(_demandItems.doc(item.id), item.toFirestore());
      }
      await batch.commit().timeout(_kWriteTimeout);
    }
  }

  Future<void> deleteDemandItem(String id) =>
      _demandItems.doc(id).delete().timeout(_kWriteTimeout);

  Future<void> deleteDemandItems(Set<String> ids) async {
    if (ids.isEmpty) return;
    const batchSize = 500;
    final idList = ids.toList();
    for (int i = 0; i < idList.length; i += batchSize) {
      final batch = _db.batch();
      final chunk = idList.sublist(
        i,
        i + batchSize > idList.length ? idList.length : i + batchSize,
      );
      for (final id in chunk) {
        batch.delete(_demandItems.doc(id));
      }
      await batch.commit().timeout(_kWriteTimeout);
    }
  }

  // ─── Supplier operations ───────────────────────────────────────────────────

  Stream<List<SupplierModel>> watchSuppliers() => _suppliers
      .orderBy('addedBy.at', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(SupplierModel.fromFirestore).toList());

  Future<List<SupplierModel>> fetchSuppliersFromServer() async {
    final snap = await _suppliers
        .orderBy('addedBy.at', descending: true)
        .get(const GetOptions(source: Source.server));
    return snap.docs.map(SupplierModel.fromFirestore).toList();
  }

  Future<DocumentReference> addSupplier(SupplierModel supplier) =>
      _suppliers.add(supplier.toFirestore()).timeout(_kWriteTimeout);

  Future<void> updateSupplier(SupplierModel supplier) =>
      _suppliers.doc(supplier.id).update(supplier.toFirestore()).timeout(_kWriteTimeout);

  Future<void> deleteSupplier(String id) =>
      _suppliers.doc(id).delete().timeout(_kWriteTimeout);

  // ─── Customer operations ───────────────────────────────────────────────────

  Stream<List<CustomerModel>> watchCustomers() => _customers
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(CustomerModel.fromFirestore).toList());

  Future<DocumentReference> addCustomer(CustomerModel customer) =>
      _customers.add(customer.toFirestore()).timeout(_kWriteTimeout);

  Future<void> updateCustomer(CustomerModel customer) =>
      _customers.doc(customer.id).update(customer.toFirestore()).timeout(_kWriteTimeout);

  Future<void> deleteCustomer(String id) =>
      _customers.doc(id).delete().timeout(_kWriteTimeout);

  // ─── Udhaar Khata operations ───────────────────────────────────────────────

  Stream<List<UdhaarEntryModel>> watchUdhaarEntries() => _udhaarEntries
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(UdhaarEntryModel.fromFirestore).toList());

  Future<DocumentReference> addUdhaarEntry(UdhaarEntryModel entry) =>
      _udhaarEntries.add(entry.toFirestore()).timeout(_kWriteTimeout);

  Future<void> updateUdhaarEntry(UdhaarEntryModel entry) =>
      _udhaarEntries.doc(entry.id).update(entry.toFirestore()).timeout(_kWriteTimeout);

  Future<void> deleteUdhaarEntry(String id) =>
      _udhaarEntries.doc(id).delete().timeout(_kWriteTimeout);

  Future<void> settleUdhaarEntry({
    required String id,
    required AuditRef settledBy,
  }) =>
      _udhaarEntries.doc(id).update({
        'status': AppConstants.udhaarSettled,
        'settledAt': Timestamp.fromDate(DateTime.now()),
        'lastEditedBy': settledBy.toMap(),
      }).timeout(_kWriteTimeout);

  Future<void> batchSettleUdhaarEntries({
    required List<String> ids,
    required AuditRef settledBy,
  }) async {
    if (ids.isEmpty) return;
    final now = Timestamp.fromDate(DateTime.now());
    const batchSize = 500;
    for (int i = 0; i < ids.length; i += batchSize) {
      final batch = _db.batch();
      final chunk = ids.sublist(
        i,
        (i + batchSize) > ids.length ? ids.length : (i + batchSize),
      );
      for (final id in chunk) {
        batch.update(_udhaarEntries.doc(id), {
          'status': AppConstants.udhaarSettled,
          'settledAt': now,
          'lastEditedBy': settledBy.toMap(),
        });
      }
      await batch.commit().timeout(_kWriteTimeout);
    }
  }

  // ─── Undo / restore operations ─────────────────────────────────────────────

  Future<void> restoreDemandItem(DemandItemModel item) =>
      _demandItems.doc(item.id).set(item.toFirestore()).timeout(_kWriteTimeout);

  Future<void> restoreSupplier(SupplierModel supplier) =>
      _suppliers.doc(supplier.id).set(supplier.toFirestore()).timeout(_kWriteTimeout);

  Future<void> restoreCustomer(CustomerModel customer) =>
      _customers.doc(customer.id).set(customer.toFirestore()).timeout(_kWriteTimeout);

  Future<void> restoreUdhaarEntry(UdhaarEntryModel entry) =>
      _udhaarEntries.doc(entry.id).set(entry.toFirestore()).timeout(_kWriteTimeout);
}
