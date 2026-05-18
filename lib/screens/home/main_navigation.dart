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

  void switchToTab(
    int index, {
    String? testsExamId,
    String? analyticsExamId,
    int? analyticsTabIndex,
  }) {
    setState(() {
      _index = index;
      _visited[index] = true;
      if (testsExamId != null) {
        _testsExamId = testsExamId;
      }
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
        bottomNavigationBar: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                index: 0,
                icon: Icons.home_outlined,
                label: "Home",
              ),
              _navItem(
                index: 1,
                icon: Icons.description_outlined,
                label: "Tests",
              ),
              _navItem(
                index: 2,
                icon: Icons.menu_book_outlined,
                label: "PYQs",
              ),
              _navItem(
                index: 3,
                icon: Icons.bar_chart_outlined,
                label: "Analytics",
              ),
              _navItem(
                index: 4,
                icon: Icons.person_outline,
                label: "Profile",
              ),
            ],
          ),
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

  Widget _navItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _index == index;
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _index = index;
              _visited[index] = true;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              vertical: 10,
            ),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? (isDark
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF7EA6FF),
                            Color(0xFF5B84F1),
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primary,
                            colorScheme.primary.withValues(alpha: 0.88),
                          ],
                        ))
                  : null,
              color: isSelected
                  ? null
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isSelected && isDark
                  ? [
                      BoxShadow(
                        color: const Color(
                          0xFF7EA6FF,
                        ).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : isSelected
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: isSelected ? 1.08 : 1,
                  child: Icon(
                    icon,
                    size: 23,
                    color: isSelected
                        ? (isDark
                            ? const Color(0xFF0F172A)
                            : colorScheme.onPrimary)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: isSelected
                        ? (isDark
                            ? const Color(0xFF0F172A)
                            : colorScheme.onPrimary)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
