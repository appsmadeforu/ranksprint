import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthAccountDeletionService {
  const AuthAccountDeletionService._();

  static Future<void> deleteCurrentAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await user.getIdToken(true);
    final callable = FirebaseFunctions.instance.httpsCallable(
      'deleteUserAccount',
    );
    await callable.call();
  }
}
