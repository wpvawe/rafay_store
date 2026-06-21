// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
//
// Generated from android/app/google-services.json for project rafay-store-3eefc.
// iOS/macOS options use the Android API key — replace with values from
// GoogleService-Info.plist if you add an iOS app to the Firebase project.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBZOCFdG6NVchK6l5-DJO35lVG4tE7ZRYk',
    appId: '1:761475352831:web:d1c111acc2ea3de007e4ca',
    messagingSenderId: '761475352831',
    projectId: 'rafay-store-3eefc',
    authDomain: 'rafay-store-3eefc.firebaseapp.com',
    storageBucket: 'rafay-store-3eefc.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBZOCFdG6NVchK6l5-DJO35lVG4tE7ZRYk',
    appId: '1:761475352831:android:d1c111acc2ea3de007e4ca',
    messagingSenderId: '761475352831',
    projectId: 'rafay-store-3eefc',
    storageBucket: 'rafay-store-3eefc.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBZOCFdG6NVchK6l5-DJO35lVG4tE7ZRYk',
    appId: '1:761475352831:ios:d1c111acc2ea3de007e4ca',
    messagingSenderId: '761475352831',
    projectId: 'rafay-store-3eefc',
    storageBucket: 'rafay-store-3eefc.firebasestorage.app',
    iosBundleId: 'com.rafaystore.rafayStore',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBZOCFdG6NVchK6l5-DJO35lVG4tE7ZRYk',
    appId: '1:761475352831:ios:d1c111acc2ea3de007e4ca',
    messagingSenderId: '761475352831',
    projectId: 'rafay-store-3eefc',
    storageBucket: 'rafay-store-3eefc.firebasestorage.app',
    iosBundleId: 'com.rafaystore.rafayStore',
  );
}
