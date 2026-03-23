import 'package:flutter/material.dart';
import 'tests_screen.dart';
import 'pyq_screen.dart';
import 'analytics_screen.dart';
import 'profile_screen.dart';
import 'subscription_screen.dart';
import 'select_exam_home.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _index;
  late final List<bool> _visited;
  bool _hasScheduledPreload = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _visited = List<bool>.filled(5, false);
    _visited[_index] = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadRemainingTabs();
    });
  }

  void _preloadRemainingTabs() {
    if (!mounted || _hasScheduledPreload) return;
    _hasScheduledPreload = true;
    if (_visited.every((visited) => visited)) return;
    setState(() {
      for (var i = 0; i < _visited.length; i++) {
        _visited[i] = true;
      }
    });
  }

  void navigateToSubscription() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
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
        return const AnalyticsScreen();
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
