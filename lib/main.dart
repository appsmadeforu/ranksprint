import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_wrapper.dart';
// import 'dev/dummy_feeder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthWrapper(),
    );
  }
}
