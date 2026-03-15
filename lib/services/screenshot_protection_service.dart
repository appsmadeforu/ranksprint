import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenshotProtectionService {
  static const MethodChannel _channel = MethodChannel(
    'ranksprint/screenshot_protection',
  );

  static bool get isEnabled {
    const configuredValue = String.fromEnvironment(
      'ENABLE_SCREENSHOT_PROTECTION',
      defaultValue: '',
    );

    if (configuredValue.isNotEmpty) {
      return configuredValue.toLowerCase() == 'true';
    }

    return kReleaseMode;
  }

  static Future<void> syncWithConfig() async {
    await setEnabled(isEnabled);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;

    try {
      await _channel.invokeMethod<void>('setEnabled', <String, dynamic>{
        'enabled': enabled,
      });
    } on PlatformException {
      // Keep startup resilient on platforms where screenshot protection
      // isn't wired yet.
    } on MissingPluginException {
      // Some desktop/mobile targets may not register the native bridge.
    }
  }
}
