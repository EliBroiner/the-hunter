// File generated based on google-services.json
// To regenerate, run: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAZuDEU73yseSTbOePL7JDZRZhpHSIFKPI',
    appId: '1:105628026575:android:0c3876740b5f75971659ba',
    messagingSenderId: '105628026575',
    projectId: 'thehunter-485508',
    storageBucket: 'thehunter-485508.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBU_qXnoq_5SATLrMIa1O_iCbouI8W7pWs',
    appId: '1:105628026575:web:eb368f30c15634021659ba',
    messagingSenderId: '105628026575',
    projectId: 'thehunter-485508',
    authDomain: 'thehunter-485508.firebaseapp.com',
    storageBucket: 'thehunter-485508.firebasestorage.app',
    measurementId: 'G-VEXTJTZXNG',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyC4hIJ1298Cj19Cd21MVRONSRHMxUFQ1TE',
    appId: '1:105628026575:ios:e461800aff8c2fbe1659ba',
    messagingSenderId: '105628026575',
    projectId: 'thehunter-485508',
    storageBucket: 'thehunter-485508.firebasestorage.app',
    iosBundleId: 'com.thehunter.theHunter',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC4hIJ1298Cj19Cd21MVRONSRHMxUFQ1TE',
    appId: '1:105628026575:ios:e461800aff8c2fbe1659ba',
    messagingSenderId: '105628026575',
    projectId: 'thehunter-485508',
    storageBucket: 'thehunter-485508.firebasestorage.app',
    iosBundleId: 'com.thehunter.theHunter',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBU_qXnoq_5SATLrMIa1O_iCbouI8W7pWs',
    appId: '1:105628026575:web:1bfcb6d0d93e03fe1659ba',
    messagingSenderId: '105628026575',
    projectId: 'thehunter-485508',
    authDomain: 'thehunter-485508.firebaseapp.com',
    storageBucket: 'thehunter-485508.firebasestorage.app',
    measurementId: 'G-60WB825995',
  );

}