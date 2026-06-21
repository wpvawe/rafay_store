import 'dart:convert';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'firestore_service.dart';

// NOTE: firebaseMessagingBackgroundHandler is defined in main.dart (top-level,
// @pragma vm:entry-point). It must NOT be duplicated here — Dart raises a
// compile-time name-conflict error when the same top-level symbol is defined in
// two imported libraries. Keeping it in main.dart only is the correct pattern.

class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    FirestoreService? firestoreService,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _db = firestoreService ?? FirestoreService();

  final FirebaseMessaging _messaging;
  final FirestoreService _db;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  int _notifId = 0;

  static const _channelId = 'rafay_store_high';
  static const _channelName = 'Rafay Store Notifications';
  static const _channelDesc = 'Important updates from Rafay Store';
  static const _brandColor = Color(0xFFD32F2F);

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDesc,
    importance: Importance.high,
    playSound: true,
    enableLights: true,
    ledColor: _brandColor,
  );

  Future<void> init({required String uid}) async {
    await _messaging.requestPermission(
        alert: true, badge: true, sound: true);

    // Suppress FCM's own foreground heads-up — we handle it ourselves via
    // flutter_local_notifications to avoid duplicates.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (_) {},
      onDidReceiveBackgroundNotificationResponse: _bgLocalNotifCallback,
    );

    final token = await _messaging.getToken();
    if (token != null) await _db.updateFcmToken(uid: uid, token: token);
    _messaging.onTokenRefresh
        .listen((t) => _db.updateFcmToken(uid: uid, token: t));

    // Handle FCM data-only messages that arrive while app is in FOREGROUND.
    // Background/terminated messages are handled by firebaseMessagingBackgroundHandler
    // in main.dart — no duplicate handling here.
    FirebaseMessaging.onMessage.listen(_handleForegroundFcmMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((_) {});
  }

  Future<void> _handleForegroundFcmMessage(RemoteMessage message) async {
    final type = message.data['type'] as String?;

    // Demand stream listener already shows foreground demand notifications
    // via showForegroundDemandNotification — skip raw FCM to avoid duplicates.
    if (type == AppConstants.notifTypeDemand) return;

    // Udhaar provider shows its own foreground notification after the Firestore
    // write succeeds — skip the FCM echo to avoid duplicates.
    if (type == AppConstants.notifTypeUdhaar) return;

    final title = _dataStr(message.data['title']) ?? AppConstants.appName;
    final body =
        _dataStr(message.data['body']) ?? 'You have a new update.';
    await _showNotif(title, body);
  }

  // ── Demand notifications ────────────────────────────────────────────────────

  Future<void> showForegroundDemandNotification(String itemName) async {
    await _showNotif(
      '📦 New Demand Item',
      '"$itemName" has been added to the demand list.',
    );
  }

  Future<void> showForegroundBatchNotification(
      int count, String firstName) async {
    await _showNotif(
      '📦 $count New Demand Items',
      '$count new items have been added to the demand list.',
    );
  }

  Future<void> showForegroundStatusNotification(
      String itemName, String newStatus) async {
    if (newStatus != AppConstants.demandPending &&
        newStatus != AppConstants.demandUrgent) return;
    final isUrgent = newStatus == AppConstants.demandUrgent;
    await _showNotif(
      isUrgent ? '🚨 Urgent Item' : '🕐 Item Marked Pending',
      isUrgent
          ? '"$itemName" has been marked as URGENT!'
          : '"$itemName" has been marked as Pending.',
    );
  }

  // ── Stock alert notifications ─────────────────────────────────────────────

  /// Fires when an item's stock drops to 0 (Out of Stock).
  Future<void> showOutOfStockNotification(String itemName) async {
    await _showNotif(
      '🚫 Out of Stock',
      '"$itemName" is now OUT OF STOCK. Reorder immediately!',
    );
  }

  /// Fires when an item's stock drops to or below its reorder level.
  Future<void> showLowStockNotification(
      String itemName, int stock, int reorderLevel) async {
    await _showNotif(
      '⚠️ Low Stock Alert',
      '"$itemName" is running low — only $stock left (reorder at $reorderLevel).',
    );
  }

  /// Send push to approved non-viewer users.
  /// The backend excludes the authenticated user who performed the action.
  Future<void> sendDemandNotification(
    String itemName, {
    String? statusChange,
    int itemCount = 1,
  }) async {
    try {
      if (AppConstants.notifyApiBaseUrl.isEmpty) return;
      if (statusChange != null &&
          statusChange != AppConstants.demandPending &&
          statusChange != AppConstants.demandUrgent) return;
      final headers = await _authHeaders();
      if (headers == null) return;
      await http.post(
        Uri.parse('${AppConstants.notifyApiBaseUrl}/notify/demand'),
        headers: headers,
        body: jsonEncode({
          'itemName': itemName,
          if (statusChange == null && itemCount > 1) 'itemCount': itemCount,
          if (statusChange != null) 'statusChange': statusChange,
        }),
      );
    } catch (_) {}
  }

  // ── Udhaar notifications ────────────────────────────────────────────────────

  Future<void> showForegroundUdhaarAddedNotification({
    required String personName,
    required double amount,
    required String type,
  }) async {
    final isGiven = type == AppConstants.udhaarGiven;
    final title = isGiven
        ? '💳 Udhaar Given — Rs ${amount.toStringAsFixed(0)}'
        : '💰 Udhaar Received — Rs ${amount.toStringAsFixed(0)}';
    final body = isGiven
        ? 'Rs ${amount.toStringAsFixed(0)} given to "$personName".'
        : 'Rs ${amount.toStringAsFixed(0)} received from "$personName".';
    await _showNotif(title, body);
  }

  Future<void> showForegroundUdhaarEditedNotification({
    required String personName,
    required double amount,
  }) async {
    await _showNotif(
      '✏️ Udhaar Updated',
      '"$personName" entry updated to Rs ${amount.toStringAsFixed(0)}.',
    );
  }

  Future<void> showForegroundUdhaarSettledNotification({
    required String personName,
    required double amount,
    required String type,
  }) async {
    final body = type == AppConstants.udhaarGiven
        ? '"$personName" settled Rs ${amount.toStringAsFixed(0)}. ✅'
        : 'Rs ${amount.toStringAsFixed(0)} settled with "$personName". ✅';
    await _showNotif('✅ Udhaar Settled', body);
  }

  /// Sends push notification to all approved non-viewer devices for udhaar.
  /// Falls back silently if the backend endpoint is unavailable.
  Future<void> sendUdhaarNotification({
    required String personName,
    required double amount,
    required String type,
    required String action, // 'added' | 'edited' | 'settled' | 'deleted'
  }) async {
    try {
      if (AppConstants.notifyApiBaseUrl.isEmpty) return;
      final headers = await _authHeaders();
      if (headers == null) return;

      final isGiven = type == AppConstants.udhaarGiven;
      late final String title;
      late final String body;

      switch (action) {
        case 'added':
          title = isGiven
              ? '💳 Udhaar Given — Rs ${amount.toStringAsFixed(0)}'
              : '💰 Udhaar Received — Rs ${amount.toStringAsFixed(0)}';
          body = isGiven
              ? 'Rs ${amount.toStringAsFixed(0)} given to "$personName".'
              : 'Rs ${amount.toStringAsFixed(0)} received from "$personName".';
          break;
        case 'edited':
          title = '✏️ Udhaar Updated';
          body =
              '"$personName" entry updated to Rs ${amount.toStringAsFixed(0)}.';
          break;
        case 'settled':
          title = '✅ Udhaar Settled';
          body =
              '"$personName" settled for Rs ${amount.toStringAsFixed(0)}.';
          break;
        case 'deleted':
          title = '🗑️ Udhaar Entry Deleted';
          body =
              '"$personName" Rs ${amount.toStringAsFixed(0)} entry deleted.';
          break;
        default:
          return;
      }

      await http.post(
        Uri.parse('${AppConstants.notifyApiBaseUrl}/notify/udhaar'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'body': body,
          'type': AppConstants.notifTypeUdhaar,
          'action': action,
          'personName': personName,
          'amount': amount,
          'udhaarType': type,
        }),
      );
    } catch (_) {
      // Silently ignore — local foreground notification was already shown.
    }
  }

  // ── Internal helper ─────────────────────────────────────────────────────────

  Future<void> _showNotif(String title, String body) async {
    await _localNotifications.show(
      _notifId = (_notifId + 1) % 10000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: _brandColor,
          playSound: true,
          enableLights: true,
          ledColor: _brandColor,
          ledOnMs: 1000,
          ledOffMs: 500,
          ticker: title,
          category: AndroidNotificationCategory.status,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: AppConstants.appName,
          ),
        ),
      ),
    );
  }

  String? _dataStr(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  Future<Map<String, String>?> _authHeaders() async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null || idToken.isEmpty) return null;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
  }
}

/// Top-level callback for background LOCAL notification responses.
/// Must be a top-level function decorated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void _bgLocalNotifCallback(NotificationResponse response) {}
