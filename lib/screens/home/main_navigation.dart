import 'package:flutter/material.dart';
import 'tests_screen.dart';
import 'pyq_screen.dart';
import 'analytics_screen.dart';
import 'profile_screen.dart';
import 'subscription_screen.dart';
import 'select_exam_home.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  final String? initialAnalyticsExamId;

  const MainNavigation({
    Key? key,
    this.initialIndex = 0,
    this.initialAnalyticsExamId,
  }) : super(key: key);

  static _MainNavigationState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<_MainNavigationState>();
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _index;
  late final List<bool> _visited;
  String? _analyticsExamId;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _analyticsExamId = widget.initialAnalyticsExamId;
    _visited = List<bool>.filled(5, false);
    _visited[_index] = true;
  }

  void navigateToSubscription() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
  }

  void switchToTab(int index, {String? analyticsExamId}) {
    setState(() {
      _index = index;
      _visited[index] = true;
      if (analyticsExamId != null) {
        _analyticsExamId = analyticsExamId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Container(
        color: const Color(0xFFF5F6FA),
        child: IndexedStack(
          index: _index,
          children: List<Widget>.generate(5, (index) {
            if (!_visited[index]) {
              return const SizedBox.shrink();
            }
            return _buildScreen(index);
          }),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() {
          _index = value;
          _visited[value] = true;
        }),
        backgroundColor: const Color(0xFFF5F6FA),
        elevation: 0,
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

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const SelectExamHome();
      case 1:
        return const TestsScreen();
      case 2:
        return const PyqScreen();
      case 3:
        return AnalyticsScreen(initialExamId: _analyticsExamId);
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
