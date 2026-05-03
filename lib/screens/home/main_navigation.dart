import 'package:flutter/material.dart';
import 'tests_screen.dart';
import 'pyq_screen.dart';
import 'analytics_screen.dart';
import 'profile_screen.dart';
import '../../services/subscription_access_service.dart';
import 'subscription_screen.dart';
import 'select_exam_home.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  final String? initialTestsExamId;
  final String? initialAnalyticsExamId;
  final int initialAnalyticsTabIndex;

  const MainNavigation({
    Key? key,
    this.initialIndex = 0,
    this.initialTestsExamId,
    this.initialAnalyticsExamId,
    this.initialAnalyticsTabIndex = 0,
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
  String? _testsExamId;
  String? _analyticsExamId;
  late int _analyticsTabIndex;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _testsExamId = widget.initialTestsExamId;
    _analyticsExamId = widget.initialAnalyticsExamId;
    _analyticsTabIndex = widget.initialAnalyticsTabIndex;
    _visited = List<bool>.filled(5, false);
    _visited[_index] = true;
  }

  void navigateToSubscription() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    ).then((subscribed) {
      if (subscribed == true) {
        SubscriptionAccessService.clearCache();
      }
    });
  }

  void switchToTab(int index, {String? analyticsExamId, int? analyticsTabIndex}) {
    setState(() {
      _index = index;
      _visited[index] = true;
      if (analyticsExamId != null) {
        _analyticsExamId = analyticsExamId;
      }
      if (analyticsTabIndex != null) {
        _analyticsTabIndex = analyticsTabIndex;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _index == 0) return;
        setState(() {
          _index = 0;
          _visited[0] = true;
        });
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Container(
          color: theme.scaffoldBackgroundColor,
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
          backgroundColor: colorScheme.surface,
          elevation: 0,
          selectedItemColor: colorScheme.primary,
          unselectedItemColor: colorScheme.onSurfaceVariant,
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
      ),
    );
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const SelectExamHome();
      case 1:
        return TestsScreen(selectedExam: _testsExamId);
      case 2:
        return const PyqScreen();
      case 3:
        return AnalyticsScreen(
          initialExamId: _analyticsExamId,
          initialTabIndex: _analyticsTabIndex,
        );
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
