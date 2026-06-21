import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import 'demand_item_model.dart';

/// A single entry in the Udhaar Khata (credit ledger).
/// [type] is either [AppConstants.udhaarGiven] (shop gave credit to a customer)
/// or [AppConstants.udhaarReceived] (shop received credit from a supplier).
/// [status] is either [AppConstants.udhaarPending] or [AppConstants.udhaarSettled].
/// [contactId] optionally links to a customer or supplier document.
/// [contactType] is either [AppConstants.contactTypeCustomer] or [AppConstants.contactTypeSupplier].
class UdhaarEntryModel {
  final String id;
  final String personName;
  final double amount;
  final String type;
  final String status;
  final String notes;
  final DateTime createdAt;
  final AuditRef addedBy;
  final AuditRef lastEditedBy;
  final DateTime? settledAt;
  final String? contactId;
  final String? contactType;

  const UdhaarEntryModel({
    required this.id,
    required this.personName,
    required this.amount,
    required this.type,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.addedBy,
    required this.lastEditedBy,
    this.settledAt,
    this.contactId,
    this.contactType,
  });

  bool get isSettled => status == AppConstants.udhaarSettled;
  bool get isPending => status == AppConstants.udhaarPending;
  bool get isGiven => type == AppConstants.udhaarGiven;
  bool get isReceived => type == AppConstants.udhaarReceived;
  bool get hasContact => contactId != null && contactId!.isNotEmpty;

  String get typeDisplay => isGiven ? 'Given' : 'Received';
  String get amountDisplay => 'Rs ${amount.toStringAsFixed(0)}';

  factory UdhaarEntryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UdhaarEntryModel(
      id: doc.id,
      personName: data['personName'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      type: data['type'] as String? ?? AppConstants.udhaarGiven,
      status: data['status'] as String? ?? AppConstants.udhaarPending,
      notes: data['notes'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      addedBy: AuditRef.fromMap(data['addedBy'] as Map<String, dynamic>? ?? {}),
      lastEditedBy: AuditRef.fromMap(
          data['lastEditedBy'] as Map<String, dynamic>? ?? {}),
      settledAt: (data['settledAt'] as Timestamp?)?.toDate(),
      contactId: data['contactId'] as String?,
      contactType: data['contactType'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'personName': personName,
        'amount': amount,
        'type': type,
        'status': status,
        'notes': notes,
        'createdAt': Timestamp.fromDate(createdAt),
        'addedBy': addedBy.toMap(),
        'lastEditedBy': lastEditedBy.toMap(),
        if (settledAt != null) 'settledAt': Timestamp.fromDate(settledAt!),
        if (contactId != null) 'contactId': contactId,
        if (contactType != null) 'contactType': contactType,
      };

  UdhaarEntryModel copyWith({
    String? personName,
    double? amount,
    String? type,
    String? status,
    String? notes,
    DateTime? createdAt,
    AuditRef? lastEditedBy,
    DateTime? settledAt,
    bool clearSettledAt = false,
    String? contactId,
    String? contactType,
    bool clearContact = false,
  }) =>
      UdhaarEntryModel(
        id: id,
        personName: personName ?? this.personName,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        addedBy: addedBy,
        lastEditedBy: lastEditedBy ?? this.lastEditedBy,
        settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
        contactId: clearContact ? null : (contactId ?? this.contactId),
        contactType: clearContact ? null : (contactType ?? this.contactType),
      );
}
