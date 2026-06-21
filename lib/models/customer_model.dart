import 'package:cloud_firestore/cloud_firestore.dart';
import 'demand_item_model.dart';

class CustomerModel {
  final String id;
  final String name;
  final String phone;
  final String whatsappNumber;
  final String address;
  final String notes;
  final AuditRef addedBy;
  final AuditRef lastEditedBy;
  final DateTime createdAt;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.whatsappNumber,
    required this.address,
    required this.notes,
    required this.addedBy,
    required this.lastEditedBy,
    required this.createdAt,
  });

  String get displayPhone =>
      whatsappNumber.isNotEmpty ? whatsappNumber : phone;

  factory CustomerModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CustomerModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      whatsappNumber: data['whatsappNumber'] as String? ?? '',
      address: data['address'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      addedBy:
          AuditRef.fromMap(data['addedBy'] as Map<String, dynamic>? ?? {}),
      lastEditedBy: AuditRef.fromMap(
          data['lastEditedBy'] as Map<String, dynamic>? ?? {}),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'phone': phone,
        'whatsappNumber': whatsappNumber,
        'address': address,
        'notes': notes,
        'addedBy': addedBy.toMap(),
        'lastEditedBy': lastEditedBy.toMap(),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  CustomerModel copyWith({
    String? name,
    String? phone,
    String? whatsappNumber,
    String? address,
    String? notes,
    AuditRef? lastEditedBy,
  }) =>
      CustomerModel(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        whatsappNumber: whatsappNumber ?? this.whatsappNumber,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        addedBy: addedBy,
        lastEditedBy: lastEditedBy ?? this.lastEditedBy,
        createdAt: createdAt,
      );
}
