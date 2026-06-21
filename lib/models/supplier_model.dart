import 'package:cloud_firestore/cloud_firestore.dart';
import 'demand_item_model.dart';

/// Represents a typed additional contact number for a supplier.
/// Handles both legacy String format (stored as phone) and the new Map format.
class AdditionalNumber {
  final String type; // 'whatsapp' or 'phone'
  final String number;

  const AdditionalNumber({required this.type, required this.number});

  bool get isWhatsApp => type == 'whatsapp';
  bool get isPhone => type == 'phone';

  /// Parses from Firestore — handles both old String and new Map format.
  factory AdditionalNumber.fromFirestore(dynamic data) {
    if (data is String) {
      return AdditionalNumber(type: 'phone', number: data);
    }
    if (data is Map<String, dynamic>) {
      return AdditionalNumber(
        type: data['type'] as String? ?? 'phone',
        number: data['number'] as String? ?? '',
      );
    }
    return const AdditionalNumber(type: 'phone', number: '');
  }

  Map<String, dynamic> toMap() => {'type': type, 'number': number};

  String get displayLabel => isWhatsApp ? 'WhatsApp' : 'Phone';
}

class SupplierModel {
  final String id;
  final String name;
  final String company;
  final String productsSupplied;
  final String whatsappNumber;
  final String phoneNumber;
  final List<AdditionalNumber> additionalNumbers;
  final AuditRef addedBy;
  final AuditRef lastEditedBy;

  const SupplierModel({
    required this.id,
    required this.name,
    required this.company,
    required this.productsSupplied,
    required this.whatsappNumber,
    required this.phoneNumber,
    required this.additionalNumbers,
    required this.addedBy,
    required this.lastEditedBy,
  });

  factory SupplierModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawNums = data['additionalNumbers'] as List<dynamic>? ?? [];
    return SupplierModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      company: data['company'] as String? ?? '',
      productsSupplied: data['productsSupplied'] as String? ?? '',
      whatsappNumber: data['whatsappNumber'] as String? ?? '',
      phoneNumber: data['phoneNumber'] as String? ?? '',
      additionalNumbers: rawNums.map(AdditionalNumber.fromFirestore).toList(),
      addedBy: AuditRef.fromMap(data['addedBy'] as Map<String, dynamic>? ?? {}),
      lastEditedBy: AuditRef.fromMap(data['lastEditedBy'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'company': company,
        'productsSupplied': productsSupplied,
        'whatsappNumber': whatsappNumber,
        'phoneNumber': phoneNumber,
        'additionalNumbers': additionalNumbers.map((n) => n.toMap()).toList(),
        'addedBy': addedBy.toMap(),
        'lastEditedBy': lastEditedBy.toMap(),
      };

  SupplierModel copyWith({
    String? name,
    String? company,
    String? productsSupplied,
    String? whatsappNumber,
    String? phoneNumber,
    List<AdditionalNumber>? additionalNumbers,
    AuditRef? lastEditedBy,
  }) =>
      SupplierModel(
        id: id,
        name: name ?? this.name,
        company: company ?? this.company,
        productsSupplied: productsSupplied ?? this.productsSupplied,
        whatsappNumber: whatsappNumber ?? this.whatsappNumber,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        additionalNumbers: additionalNumbers ?? this.additionalNumbers,
        addedBy: addedBy,
        lastEditedBy: lastEditedBy ?? this.lastEditedBy,
      );
}
