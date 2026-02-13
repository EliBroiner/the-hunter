import 'dart:ui' show PlatformDispatcher;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../configs/ranking_config.dart';
import '../services/ai_auto_tagger_service.dart';
import '../services/category_manager_service.dart';
import '../services/database_service.dart';
import '../services/favorites_service.dart';
import '../services/knowledge_base_service.dart';
import '../services/log_service.dart';
import '../services/recent_files_service.dart';
import '../services/secure_folder_service.dart';
import '../services/settings_service.dart';
import '../services/tags_service.dart';
import '../services/widget_service.dart';
import '../utils/smart_search_parser.dart';

/// אתחול האפליקציה — Firebase, App Check, RevenueCat, שירותים.
Future<void> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  appLog('CURRENT_PACKAGE_NAME: com.thehunter.the_hunter');

  await LogService.instance.clearLogs();

  await Firebase.initializeApp();

  final authUser = await FirebaseAuth.instance.authStateChanges().first;
  appLog(
    authUser == null
        ? 'AUTH: currentUser is null — Firestore/Storage writes will fail until user signs in'
        : 'AUTH: currentUser=${authUser.uid} (${authUser.isAnonymous ? "anonymous" : authUser.email ?? "unknown"})',
  );

  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidDebugProvider(
      debugToken: '9273D0C3-6F08-4825-9416-49FCD8ABA9B6',
    ),
    providerApple: const AppleDebugProvider(),
  );
  appLog('🛡️ App Check activated with FIXED debug token (9273D0C3-6F08-4825-9416-49FCD8ABA9B6).');

  try {
    final token = await FirebaseAppCheck.instance.getToken(true);
    if (token != null && token.isNotEmpty) {
      appLog('🛡️ App Check JWT received OK (len=${token.length}) — will be sent in X-Firebase-AppCheck');
    } else {
      appLog('❌ App Check getToken returned null/empty — API calls may get 401');
    }
  } catch (e) {
    appLog('❌ App Check getToken failed: $e — API calls may get 401');
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await Purchases.setLogLevel(LogLevel.debug);
  await Purchases.configure(
    PurchasesConfiguration('goog_ffZaXsWeIyIjAdbRlvAwEhwTDSZ'),
  );

  await DatabaseService.instance.init();
  await KnowledgeBaseService.instance.initialize();
  SmartSearchParser.knowledgeBaseService = KnowledgeBaseService.instance;
  await CategoryManagerService.instance.loadCategories();
  AiAutoTaggerService.instance.initialize();
  await SettingsService.instance.init();
  await RankingConfig.ensureLoaded();
  await FavoritesService.instance.init();
  await RecentFilesService.instance.init();
  await TagsService.instance.init();
  await WidgetService.instance.init();
  await SecureFolderService.instance.init();
}
