class AuthIdentityService {
  const AuthIdentityService._();

  static String normalizeEmail(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  static String normalizePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.length == 10) {
      return '+91$digits';
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }
    if ((value ?? '').trim().startsWith('+')) {
      return '+$digits';
    }
    return digits;
  }

  static bool phonesMatch(String? a, String? b) {
    final left = normalizePhone(a);
    final right = normalizePhone(b);
    return left.isNotEmpty && left == right;
  }
}
