/// Application-wide constants.
abstract final class AppConstants {
  static const String appName = 'Rafay Store';
  static const String appVersion = '1.3.0';
  static const String storeAddress = 'Tanveer town near nlc bypass, Multan';

  static const String usersCollection = 'users';
  static const String demandItemsCollection = 'demandItems';
  static const String suppliersCollection = 'suppliers';
  static const String customersCollection = 'customers';
  static const String categoriesCollection = 'categories';

  // ── Udhaar Khata ──────────────────────────────────────────────────────────
  static const String udhaarCollection = 'udhaarEntries';
  static const String udhaarPending = 'pending';
  static const String udhaarSettled = 'settled';
  static const String udhaarGiven = 'given';
  static const String udhaarReceived = 'received';

  // ── Contact types (for Udhaar linking) ───────────────────────────────────
  static const String contactTypeCustomer = 'customer';
  static const String contactTypeSupplier = 'supplier';

  static const String roleAdmin = 'admin';
  static const String roleEditor = 'editor';
  static const String roleViewer = 'viewer';

  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';

  // Demand item statuses — 4 total
  static const String demandPending = 'pending';
  static const String demandAvailable = 'available';
  static const String demandDeferred = 'deferred';
  static const String demandUrgent = 'urgent';

  // Notification types
  static const String notifTypeDemand = 'demand';
  static const String notifTypeSupplier = 'supplier';
  static const String notifTypeUdhaar = 'udhaar';

  static const List<String> roles = [roleAdmin, roleEditor, roleViewer];

  /// Sentinel value used in the dropdown to trigger the custom-unit text field.
  /// Never persisted to Firestore — the actual typed string is saved instead.
  static const String demandUnitCustom = '__custom__';

  static const List<String> demandUnits = [
    // Weight
    'Gram', 'Kilogram', 'Ounce',
    // Volume
    'Litre', 'Millilitre',
    // Length
    'Millimeter', 'Centimeter', 'Meter', 'Inch', 'Foot',
    // Packaging
    'Box', 'Bag', 'Packet', 'Carton', 'Bottle', 'Crate', 'Sachet',
    'Pouch', 'Tin', 'Tray', 'Roll', 'Bundle', 'Dozen',
    // Count / General
    'Piece',
  ];

  static const String notifyApiBaseUrl = String.fromEnvironment(
    'NOTIFY_API_BASE_URL',
    defaultValue: 'https://rafay-store00.vercel.app/api',
  );

  static const String prefFcmToken = 'fcm_token';
}
