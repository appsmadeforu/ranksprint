import 'package:flutter/material.dart';
import 'tests_screen.dart';
import 'pyq_screen.dart';
import 'analytics_screen.dart';
import 'profile_screen.dart';
import 'subscription_screen.dart';
import 'select_exam_home.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;

  final List<Widget> screens = const [
    SelectExamHome(),
    TestsScreen(),
    PyqScreen(),
    AnalyticsScreen(),
    ProfileScreen(),
  ];

  void navigateToSubscription() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        selectedItemColor: const Color(0xFF2F3E8F),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined),
            label: "Tests",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            label: "PYQs",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: "Analytics",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
