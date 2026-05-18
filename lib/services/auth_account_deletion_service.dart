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
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final result = await callable.call();
    final data = result.data;
    if (data is Map && data['success'] == true) {
      return;
    }
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Account deletion did not complete successfully.',
    );
  }
}
