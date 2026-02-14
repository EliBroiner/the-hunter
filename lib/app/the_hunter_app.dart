import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../services/settings_service.dart';
import '../services/user_activity_service.dart';
import '../ui/screens/debug/ai_lab_screen.dart';
import '../ui/screens/debug/workflow_test_screen.dart';
import 'app_theme.dart';
import 'auth_wrapper.dart';
import '../screens/cloud_storage_screen.dart';
import '../screens/duplicates_screen.dart';
import '../screens/folder_selection_screen.dart';
import '../screens/prompt_management_screen.dart';
import '../screens/secure_folder_screen.dart';
import '../screens/subscription_screen.dart';
import '../screens/system_logs_screen.dart';

/// האפליקציה הראשית — MaterialApp עם routing
class TheHunterApp extends StatefulWidget {
  const TheHunterApp({super.key});

  @override
  State<TheHunterApp> createState() => _TheHunterAppState();

  static ThemeData get darkTheme => appThemeDark;
  static ThemeData get lightTheme => appThemeLight;
}

class _TheHunterAppState extends State<TheHunterApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // לא קוראים dispose() ברקע — מונע SocketException בהעלאה אטומית
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => UserActivityService.instance.onUserInteraction(),
      onPointerMove: (_) => UserActivityService.instance.onUserInteraction(),
      onPointerUp: (_) => UserActivityService.instance.onUserInteraction(),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: SettingsService.instance.themeModeNotifier,
        builder: (context, themeMode, child) {
          return ValueListenableBuilder<Locale>(
            valueListenable: SettingsService.instance.localeNotifier,
            builder: (context, locale, child) {
              return MaterialApp(
                title: 'The Hunter',
                debugShowCheckedModeBanner: false,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [
                  Locale('he', 'IL'),
                  Locale('en', 'US'),
                ],
                locale: locale,
                theme: TheHunterApp.lightTheme,
                darkTheme: TheHunterApp.darkTheme,
                themeMode: themeMode,
                home: const AuthWrapper(),
                routes: {
                  '/subscription': (context) => const SubscriptionScreen(),
                  '/folders': (context) => const FolderSelectionScreen(),
                  '/duplicates': (context) => const DuplicatesScreen(),
                  '/secure': (context) => const SecureFolderScreen(),
                  '/cloud': (context) => const CloudStorageScreen(),
                  '/ai-lab': (context) => const AiLabScreen(),
                  '/workflow-test': (context) => const WorkflowTestScreen(),
                  '/prompts': (context) => const PromptManagementScreen(),
                  '/system-logs': (context) => const SystemLogsScreen(),
                },
              );
            },
          );
        },
      ),
    );
  }
}
