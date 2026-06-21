import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

class AuditRef {
  final String uid;
  final String name;
  final DateTime at;

  const AuditRef({required this.uid, required this.name, required this.at});

  factory AuditRef.fromMap(Map<String, dynamic> map) => AuditRef(
        uid: map['uid'] as String? ?? '',
        name: map['name'] as String? ?? '',
        at: (map['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'at': Timestamp.fromDate(at),
      };
}

/// Safe cast helper — returns an empty map instead of throwing if the
/// value is null or the wrong Firestore type (guards against old schema docs).
Map<String, dynamic> _safeMap(dynamic value) {
  if (value == null) return {};
  if (value is Map<String, dynamic>) return value;
  // Firestore can also return LinkedHashMap — cast via intermediate dynamic
  try {
    return Map<String, dynamic>.from(value as Map);
  } catch (_) {
    return {};
  }
}

/// A single item in the store demand book.
class DemandItemModel {
  final String id;
  final String name;

  /// How many packages/units to order (demand quantity).
  final String quantity;

  /// Packaging type: Carton, Box, Bag, Packet, Sachet, Piece, Bottle, etc.
  final String unit;

  /// What is inside each package — e.g. "10 kg", "500 ml", "12 pcs".
  /// Optional — leave empty if not applicable.
  final String packContents;

  final String notes;
  final String status;
  final String barcode;
  final AuditRef addedBy;
  final AuditRef lastEditedBy;

  // ── Category ─────────────────────────────────────────────────────────────
  /// Category ID. Null or empty means "General" (default category).
  final String? categoryId;

  // ── Pricing fields ──────────────────────────────────────────────────────────
  final double sellPrice;
  final double? costPrice;
  final double? wholesalePrice;

  // ── Inventory ───────────────────────────────────────────────────────────────
  /// Current number of packages in stock.
  final int stock;

  /// Minimum stock level before reorder is needed. 0 = disabled.
  final int reorderLevel;

  // ── Supplier ─────────────────────────────────────────────────────────────
  final String? supplierId;

  // ── Price History ─────────────────────────────────────────────────────────
  /// List of price snapshots: [{price, date, type:'sell'/'cost'}]
  final List<Map<String, dynamic>> priceHistory;

  const DemandItemModel({
    required this.id,
    required this.name,
    required this.quantity,
    this.unit = 'Piece',
    this.packContents = '',
    required this.notes,
    required this.status,
    this.barcode = '',
    required this.addedBy,
    required this.lastEditedBy,
    this.categoryId,
    this.sellPrice = 0.0,
    this.costPrice,
    this.wholesalePrice,
    this.stock = 0,
    this.reorderLevel = 0,
    this.supplierId,
    this.priceHistory = const [],
  });

  bool get isUrgent => status == AppConstants.demandUrgent;
  bool get isPending => status == AppConstants.demandPending;
  bool get isAvailable => status == AppConstants.demandAvailable;
  bool get isDeferred => status == AppConstants.demandDeferred;
  bool get hasBarcode => barcode.isNotEmpty;
  bool get hasPackContents => packContents.isNotEmpty;

  /// True if the item belongs to the General (default) category
  bool get isGeneralCategory => categoryId == null || categoryId!.isEmpty;

  /// True when stock is 0 AND the item is marked available
  /// (reorderLevel > 0 confirms the user is actively tracking stock)
  bool get isOutOfStock => stock == 0 && (isAvailable || isPending || isUrgent) && reorderLevel > 0;

  /// True when stock > 0 but at or below reorder level (low stock warning)
  bool get hasLowStock =>
      reorderLevel > 0 && stock > 0 && stock <= reorderLevel;

  /// Display status string — overrides 'available' to 'Out of Stock' when stock == 0
  String get effectiveStatus =>
      (isAvailable && isOutOfStock) ? 'out_of_stock' : status;

  /// e.g. "2 Carton (10 kg each)" or "5 Bag" or "1 Piece"
  String get quantityDisplay {
    final base = '$quantity $unit'.trim();
    if (packContents.isNotEmpty) return '$base ($packContents each)';
    return base;
  }

  /// Short label for WhatsApp — e.g. "2 Carton × 10 kg"
  String get quantityWhatsApp {
    if (quantity.isEmpty || quantity == '0') return '';
    final base = '$quantity $unit'.trim();
    if (packContents.isNotEmpty) return '$base × $packContents';
    return base;
  }

  String get sellPriceDisplay => _formatPrice(sellPrice);
  String? get costPriceDisplay =>
      costPrice != null ? _formatPrice(costPrice!) : null;
  String? get wholesalePriceDisplay =>
      wholesalePrice != null ? _formatPrice(wholesalePrice!) : null;

  // ── Quantity-aware helpers ────────────────────────────────────────────────
  /// Parsed demand quantity as int (defaults to 1 when blank / invalid).
  int get quantityInt => int.tryParse(quantity.trim()) ?? 1;

  /// Total sell value = sellPrice × quantityInt
  double get totalSellPrice => sellPrice * quantityInt;

  /// Total cost value = costPrice × quantityInt  (null if costPrice not set)
  double? get totalCostPrice =>
      costPrice != null ? costPrice! * quantityInt : null;

  /// Total wholesale value = wholesalePrice × quantityInt  (null if not set)
  double? get totalWholesalePrice =>
      wholesalePrice != null ? wholesalePrice! * quantityInt : null;

  String get totalSellDisplay => _formatPrice(totalSellPrice);
  String? get totalCostDisplay =>
      totalCostPrice != null ? _formatPrice(totalCostPrice!) : null;
  String? get totalWholesaleDisplay =>
      totalWholesalePrice != null ? _formatPrice(totalWholesalePrice!) : null;

  static String _formatPrice(double price) {
    if (price == price.truncateToDouble()) {
      return 'Rs. ${price.toInt()}';
    }
    return 'Rs. ${price.toStringAsFixed(2)}';
  }

  /// Parses a Firestore document.  Wrapped in try/catch so a single malformed
  /// document (old schema, unexpected type) never crashes the whole stream.
  factory DemandItemModel.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>? ?? {};

      var storedStatus =
          data['status'] as String? ?? AppConstants.demandPending;

      final legacyIsUrgent = data['isUrgent'] as bool? ?? false;
      if (legacyIsUrgent && storedStatus == AppConstants.demandPending) {
        storedStatus = AppConstants.demandUrgent;
      }

      return DemandItemModel(
        id: doc.id,
        name: data['name'] as String? ?? '',
        quantity: data['quantity'] as String? ?? '',
        unit: data['unit'] as String? ?? 'Piece',
        packContents: data['packContents'] as String? ?? '',
        notes: data['notes'] as String? ?? '',
        status: storedStatus,
        barcode: data['barcode'] as String? ?? '',
        addedBy: AuditRef.fromMap(_safeMap(data['addedBy'])),
        lastEditedBy: AuditRef.fromMap(_safeMap(data['lastEditedBy'])),
        categoryId: data['categoryId'] as String?,
        sellPrice: (data['sellPrice'] as num?)?.toDouble() ?? 0.0,
        costPrice: (data['costPrice'] as num?)?.toDouble(),
        wholesalePrice: (data['wholesalePrice'] as num?)?.toDouble(),
        stock: (data['stock'] as num?)?.toInt() ?? 0,
        reorderLevel: (data['reorderLevel'] as num?)?.toInt() ?? 0,
        supplierId: data['supplierId'] as String?,
        priceHistory: _parsePriceHistory(data['priceHistory']),
      );
    } catch (e) {
      // Fallback for any document with unexpected data — keeps the stream alive.
      return DemandItemModel(
        id: doc.id,
        name: '(Error loading item)',
        quantity: '0',
        notes: 'Data parse error: $e',
        status: AppConstants.demandPending,
        addedBy: AuditRef(uid: '', name: '', at: DateTime.now()),
        lastEditedBy: AuditRef(uid: '', name: '', at: DateTime.now()),
      );
    }
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'packContents': packContents,
      'notes': notes,
      'status': status,
      'barcode': barcode,
      'isUrgent': false,
      'addedBy': addedBy.toMap(),
      'lastEditedBy': lastEditedBy.toMap(),
      'categoryId': (categoryId != null && categoryId!.isNotEmpty) ? categoryId : null,
      'sellPrice': sellPrice,
      'stock': stock,
      'reorderLevel': reorderLevel,
      'supplierId': supplierId,
      'priceHistory': priceHistory,
    };
    if (costPrice != null) {
      map['costPrice'] = costPrice;
    } else {
      map['costPrice'] = null;
    }
    if (wholesalePrice != null) {
      map['wholesalePrice'] = wholesalePrice;
    } else {
      map['wholesalePrice'] = null;
    }
    return map;
  }

  /// Parse Firestore priceHistory list safely
  static List<Map<String, dynamic>> _parsePriceHistory(dynamic raw) {
    if (raw == null) return [];
    try {
      return (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  DemandItemModel copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? packContents,
    String? notes,
    String? status,
    String? barcode,
    AuditRef? lastEditedBy,
    String? categoryId,
    bool clearCategoryId = false,
    double? sellPrice,
    double? costPrice,
    bool clearCostPrice = false,
    double? wholesalePrice,
    bool clearWholesalePrice = false,
    int? stock,
    int? reorderLevel,
    String? supplierId,
    bool clearSupplierId = false,
    List<Map<String, dynamic>>? priceHistory,
  }) =>
      DemandItemModel(
        id: id,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        packContents: packContents ?? this.packContents,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        barcode: barcode ?? this.barcode,
        addedBy: addedBy,
        lastEditedBy: lastEditedBy ?? this.lastEditedBy,
        categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
        sellPrice: sellPrice ?? this.sellPrice,
        costPrice: clearCostPrice ? null : (costPrice ?? this.costPrice),
        wholesalePrice: clearWholesalePrice
            ? null
            : (wholesalePrice ?? this.wholesalePrice),
        stock: stock ?? this.stock,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        supplierId: clearSupplierId ? null : (supplierId ?? this.supplierId),
        priceHistory: priceHistory ?? this.priceHistory,
      );
}
