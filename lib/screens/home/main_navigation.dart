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

  // Keep screens in the same order as the BottomNavigationBar items
  final screens = [
    const SelectExamHome(),
    const TestsScreen(),
    const PyqScreen(),
    const AnalyticsScreen(),
    const ProfileScreen(),
  ];

  // Method to navigate to subscription screen
  void navigateToSubscription() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SubscriptionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        selectedItemColor: const Color(0xFF2F3E8F),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined),
              label: "Tests"),
          BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              label: "PYQs"),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              label: "Analytics"),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: "Profile"),
        ],
      ),
    );
  }
}
