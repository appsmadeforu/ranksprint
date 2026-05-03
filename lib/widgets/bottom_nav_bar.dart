import 'package:flutter/material.dart';
import '../screens/home/tests_screen.dart';
import '../screens/home/pyq_screen.dart';
import '../screens/home/analytics_screen.dart';
import '../screens/home/profile_screen.dart';

class CommonBottomNavBar extends StatelessWidget {
  final int currentIndex;

  const CommonBottomNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          Widget screen;
          switch (index) {
            case 0:
              screen = const TestsScreen();
              break;
            case 1:
              screen = const PyqScreen();
              break;
            case 2:
              screen = const AnalyticsScreen();
              break;
            case 3:
              screen = const ProfileScreen();
              break;
            default:
              screen = const TestsScreen();
          }

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => screen),
            (route) => false,
          );
        },
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined),
            label: 'Tests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            label: 'PYQ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
