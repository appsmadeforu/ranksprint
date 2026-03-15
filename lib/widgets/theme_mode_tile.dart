import 'package:flutter/material.dart';

import '../services/theme_mode_service.dart';

class ThemeModeTile extends StatelessWidget {
  const ThemeModeTile({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeModeService.instance;

    return AnimatedBuilder(
      animation: themeService,
      builder: (context, _) {
        final isDarkMode = themeService.isDarkMode;
        return SwitchListTile(
          secondary: Icon(
            isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          ),
          title: const Text('Dark Mode'),
          subtitle: Text(isDarkMode ? 'Enabled' : 'Disabled'),
          value: isDarkMode,
          onChanged: themeService.setDarkMode,
        );
      },
    );
  }
}
