import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/screenshot_protection_service.dart';
import 'services/theme_mode_service.dart';
// import 'dev/dummy_feeder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.appAttestWithDeviceCheckFallback,
    );
  }
  await ScreenshotProtectionService.syncWithConfig();
  await ThemeModeService.instance.load();

  // Run feeder once in debug mode when you need dummy data.
  // Uncomment the import above, then uncomment this block:
  // if (kDebugMode) {
  //   try {
  //     await DummyFirestoreFeeder.seedSampleData();
  //   } catch (e) {
  //     print('Dummy feeder failed: $e');
  //   }
  // }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeModeService.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeModeService.instance.themeMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
