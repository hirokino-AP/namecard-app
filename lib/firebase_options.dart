// lib/firebase_options.dart
// FlutterFire CLIの代わりに手動生成

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web is not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD660PbZIOZE4QyumpRl093mBpCy2cI8pc',
    appId: '1:1051281005126:ios:4cdcfb836865ed4e2ac847',
    messagingSenderId: '1051281005126',
    projectId: 'namecard-app-hirokino',
    storageBucket: 'namecard-app-hirokino.firebasestorage.app',
    iosClientId: '',
    iosBundleId: 'com.hirokino.namecardapp',
  );
}
