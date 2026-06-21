import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/category_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/demand_provider.dart';
import 'providers/supplier_provider.dart';
import 'providers/udhaar_provider.dart';
import 'router.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    const channel = AndroidNotificationChannel(
      'rafay_store_high',
      'Rafay Store Notifications',
      description: 'Important updates from Rafay Store',
      importance: Importance.high,
      playSound: true,
      enableLights: true,
    );

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveBackgroundNotificationResponse: _bgNotifResponse,
    );

    final title = (message.data['title'] as String?)?.trim().isNotEmpty == true
        ? message.data['title'] as String
        : 'Rafay Store';
    final body = (message.data['body'] as String?)?.trim().isNotEmpty == true
        ? message.data['body'] as String
        : 'You have a new update.';

    await plugin.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'rafay_store_high',
          'Rafay Store Notifications',
          channelDescription: 'Important updates from Rafay Store',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableLights: true,
          ticker: title,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: 'Rafay Store',
          ),
        ),
      ),
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
void _bgNotifResponse(NotificationResponse response) {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const RafayStoreApp());
}

class RafayStoreApp extends StatelessWidget {
  const RafayStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirestoreService>(create: (_) => FirestoreService()),
        Provider<NotificationService>(
          create: (ctx) => NotificationService(
            firestoreService: ctx.read<FirestoreService>(),
          ),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (ctx) => AuthProvider(
            firestoreService: ctx.read<FirestoreService>(),
          ),
        ),
        ChangeNotifierProvider<DemandProvider>(
          create: (ctx) => DemandProvider(
            firestoreService: ctx.read<FirestoreService>(),
            notificationService: ctx.read<NotificationService>(),
          ),
        ),
        ChangeNotifierProvider<SupplierProvider>(
          create: (ctx) => SupplierProvider(
            firestoreService: ctx.read<FirestoreService>(),
          ),
        ),
        ChangeNotifierProvider<UdhaarProvider>(
          create: (ctx) => UdhaarProvider(
            firestoreService: ctx.read<FirestoreService>(),
            notificationService: ctx.read<NotificationService>(),
          ),
        ),
        ChangeNotifierProvider<CustomerProvider>(
          create: (ctx) => CustomerProvider(
            firestoreService: ctx.read<FirestoreService>(),
          ),
        ),
        ChangeNotifierProvider<CategoryProvider>(
          create: (ctx) => CategoryProvider(
            firestoreService: ctx.read<FirestoreService>(),
          ),
        ),
      ],
      child: const _RouterRoot(),
    );
  }
}

class _RouterRoot extends StatefulWidget {
  const _RouterRoot();

  @override
  State<_RouterRoot> createState() => _RouterRootState();
}

class _RouterRootState extends State<_RouterRoot> with WidgetsBindingObserver {
  late final _router = buildRouter(context);
  bool _notifInitialised = false;

  // ── Double-back-to-exit ──────────────────────────────────────────────────
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<AuthProvider>().addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<AuthProvider>().removeListener(_onAuthChanged);
    super.dispose();
  }

  /// Called by Android when the system back button is pressed.
  /// Returning true  = event consumed (do NOT exit).
  /// Returning false = event not handled → system will exit the app.
  @override
  Future<bool> didPopRoute() async {
    // Delegate to the router first — this triggers PopScope widgets
    // in the current screen (e.g. double-back-to-exit in each tab).
    final handled = await _router.routerDelegate.popRoute();
    if (handled) return true;

    // Fallback: if no screen PopScope handled it, apply double-back here.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      return false; // second press within 2 s → let system exit
    }
    _lastBackPress = now;
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Press back again to exit'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    return true; // first press → consumed, show toast
  }

  void _onAuthChanged() {
    final auth = context.read<AuthProvider>();
    if (!_notifInitialised &&
        auth.status == AuthStatus.authenticated &&
        auth.currentUser != null) {
      _notifInitialised = true;
      context.read<NotificationService>().init(uid: auth.currentUser!.uid);
      context.read<CustomerProvider>().startListening();
      context.read<UdhaarProvider>().startListening();
      context.read<CategoryProvider>().startListening();
    }
    if (auth.status == AuthStatus.unauthenticated) {
      _notifInitialised = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Rafay Store',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
      scaffoldMessengerKey: _messengerKey,
    );
  }
}
