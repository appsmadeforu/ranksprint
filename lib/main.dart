import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ranksprint/dev/seed_data.dart';
import 'firebase_options.dart';
import 'screens/auth_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Run the full seeder only in debug mode to avoid overwriting production data on every startup.
  if (kDebugMode) {
    try {
      await FullFirestoreSeeder.seed();
    } catch (e) {
      // swallow seeder errors in debug but print for visibility
      if (kDebugMode) {
        print('Seeder failed: $e');
      }
    }
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthWrapper(),
    );
  }
}
