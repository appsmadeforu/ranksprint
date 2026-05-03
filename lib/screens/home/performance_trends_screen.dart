import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/performance_trends_data_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/top_header.dart';
import 'main_navigation.dart';
import 'test_solution_screen.dart';

typedef _Vm = PerformanceTrendsVm;
typedef _DeferredVmData = PerformanceTrendsDeferredVmData;
typedef _Window = PerformanceTrendsWindow;
typedef _P = PerformanceTrendsPoint;
typedef _SubjectMetric = PerformanceTrendsSubjectMetric;

class PerformanceTrendsScreen extends StatefulWidget {
  final String? initialExamId;

  const PerformanceTrendsScreen({super.key, this.initialExamId});

  @override
  State<PerformanceTrendsScreen> createState() =>
      _PerformanceTrendsScreenState();
}

class _PerformanceTrendsScreenState extends State<PerformanceTrendsScreen> {
  String? _examId;
  List<String> _examIds = [];
  _Window _window = _Window.d30;
  bool _showDeferredSections = false;
  String? _deferredSectionsKey;

  @override
  void initState() {
    super.initState();
    UserExamPreferenceService.preferredExamNotifier.addListener(
      _handlePreferredExamChanged,
    );
    _loadUserExams();
  }

  @override
  void dispose() {
    UserExamPreferenceService.preferredExamNotifier.removeListener(
      _handlePreferredExamChanged,
    );
    super.dispose();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final exams = List<String>.from(doc.data()?['selectedExams'] ?? []);
    final preferredExamId =
        widget.initialExamId != null && exams.contains(widget.initialExamId)
        ? widget.initialExamId
        : await UserExamPreferenceService.loadPreferredExamId(
            availableExamIds: exams,
          );
    final resolvedExamId = exams.contains(preferredExamId)
        ? preferredExamId
        : (exams.isNotEmpty ? exams.first : null);
    if (!mounted) return;
    setState(() {
      _examIds = exams;
      _examId = resolvedExamId;
    });
    _prefetchWindowData();
  }

  void _handlePreferredExamChanged() {
    final preferredExamId =
        UserExamPreferenceService.preferredExamNotifier.value;
    if (!mounted ||
        preferredExamId == null ||
        preferredExamId == _examId ||
        !_examIds.contains(preferredExamId)) {
      return;
    }

      setState(() {
        _examId = preferredExamId;
      });
    _prefetchWindowData();
  }

  Future<_Vm> _vmFutureFor(String uid) {
    return PerformanceTrendsDataService.vmFuture(
      userId: uid,
      examId: _examId!,
      window: _window,
    );
  }

  Future<double> _platformAvgFutureFor() {
    return PerformanceTrendsDataService.platformAvgFuture(
      examId: _examId!,
      window: _window,
    );
  }

  Future<_DeferredVmData> _deferredVmFutureFor(_Vm vm) {
    return PerformanceTrendsDataService.deferredVmFuture(vm);
  }

  void _scheduleDeferredSections(String contentKey) {
    if (_deferredSectionsKey == contentKey && _showDeferredSections) return;
    _deferredSectionsKey = contentKey;
    _showDeferredSections = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _deferredSectionsKey != contentKey) return;
      setState(() {
        _showDeferredSections = true;
      });
    });
  }

  void _prefetchWindowData() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final examId = _examId;
    if (uid == null || examId == null || examId.isEmpty) return;

    PerformanceTrendsDataService.prefetch(
      userId: uid,
      examId: examId,
      window: _window,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: _examId,
              userExamIds: _examIds,
              showBackButton: true,
              onExamChanged: (id) => setState(() {
                _examId = id;
                _showDeferredSections = false;
                _deferredSectionsKey = null;
                _prefetchWindowData();
              }),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _examId == null
                  ? const Center(child: Text('No exam selected'))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: _windowRow(),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: FutureBuilder<_Vm>(
                            key: ValueKey<String>('${_examId ?? ''}:${_window.name}'),
                            future: _vmFutureFor(uid),
                            builder: (context, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return _performanceSkeleton();
                              }
                              if (snap.hasError) {
                                return OfflineState(
                                  message:
                                      'Could not load trends. Please check your connection and try again.',
                                  onRetry: () {
                                    if (!mounted) return;
                                    setState(() {
                                      if (_examId != null && _examId!.isNotEmpty) {
                                        PerformanceTrendsDataService.invalidate(
                                          userId: uid,
                                          examId: _examId!,
                                          window: _window,
                                        );
                                      }
                                      _showDeferredSections = false;
                                      _deferredSectionsKey = null;
                                    });
                                    _prefetchWindowData();
                                  },
                                );
                              }
                              if (!snap.hasData) {
                                return const Center(
                                  child: Text('No performance data available'),
                                );
                              }
                              final vm = snap.data!;
                              final contentKey =
                                  '${_examId ?? ''}:${_window.name}:${vm.tests}';
                              _scheduleDeferredSections(contentKey);
                              return RefreshIndicator(
                                onRefresh: () async {
                                  if (!mounted) return;
                                  setState(() {
                                    if (_examId != null && _examId!.isNotEmpty) {
                                      PerformanceTrendsDataService.invalidate(
                                        userId: uid,
                                        examId: _examId!,
                                        window: _window,
                                      );
                                    }
                                    _showDeferredSections = false;
                                    _deferredSectionsKey = null;
                                  });
                                  _prefetchWindowData();
                                },
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                                  children: [
                                    FutureBuilder<_DeferredVmData>(
                                      future: _deferredVmFutureFor(vm),
                                      builder: (context, deferredSnap) {
                                        return _hero(
                                          vm,
                                          bestSubject:
                                              deferredSnap.data?.bestSubject ??
                                              vm.bestSubject,
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    FutureBuilder<double>(
                                      future: _platformAvgFutureFor(),
                                      builder: (context, platformSnap) {
                                        return _scoreTrend(vm, platformSnap.data);
                                      },
                                    ),
                                    FutureBuilder<_DeferredVmData>(
                                      future: _deferredVmFutureFor(vm),
                                      builder: (context, deferredSnap) {
                                        return _subjectCard(
                                          deferredSnap.data?.subjects ?? const [],
                                          isLoading: !deferredSnap.hasData,
                                        );
                                      },
                                    ),
                                    if (_showDeferredSections) ...[
                                      const SizedBox(height: 10),
                                      FutureBuilder<_DeferredVmData>(
                                        future: _deferredVmFutureFor(vm),
                                        builder: (context, deferredSnap) {
                                          if (!deferredSnap.hasData) {
                                            return _deferredSectionsPlaceholder();
                                          }
                                          final deferred = deferredSnap.data!;
                                          return Column(
                                            children: [
                                              _skills(vm, deferred),
                                              const SizedBox(height: 10),
                                              _weeklyActivity(vm),
                                              const SizedBox(height: 10),
                                              _performanceInsights(vm, deferred),
                                              const SizedBox(height: 10),
                                              _actionButtons(vm),
                                            ],
                                          );
                                        },
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 10),
                                      _deferredSectionsPlaceholder(),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(_Vm vm, {required String bestSubject}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF24439A), Color(0xFF3459B9)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Performance Trends',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Track your progress over time',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _window.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Current Average',
                  '${vm.avg.toStringAsFixed(0)}%',
                  '+${vm.delta.toStringAsFixed(0)}%',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _metric('Tests Attempted', '${vm.tests}', '')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
                Expanded(child: _metric('Best Subject', bestSubject, '')),
              const SizedBox(width: 8),
              Expanded(
                child: _metric('Total Time', _fmtMins(vm.totalMinutes), ''),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String value, String delta) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onPrimary.withValues(alpha: 0.78),
                    fontSize: 10,
                  ),
                ),
              ),
              if (delta.isNotEmpty)
                Text(
                  delta,
                  style: const TextStyle(
                    color: Color(0xFF86EFAC),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _windowRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: _Window.values.map((w) {
          final s = w == _window;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _window = w;
                    _showDeferredSections = false;
                    _deferredSectionsKey = null;
                    _prefetchWindowData();
                  }),
                  child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: s
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    w.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: s
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _scoreTrend(_Vm vm, double? platformAvg) {
    return _card(
      'Score Trend',
      Column(
        children: [
          SizedBox(
            height: 170,
            child: vm.points.length < 2
                ? const Center(
                    child: Text('Need at least 2 attempts to show trend'),
                  )
                : _TrendChart(points: vm.points, platformAvg: platformAvg),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _Legend(color: Color(0xFF1E40AF), text: 'Your Score'),
              SizedBox(width: 12),
              _Legend(color: Color(0xFFF97316), text: 'Platform Average'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _small(
                  'Your Average',
                  '${vm.avg.toStringAsFixed(0)}%',
                  const Color(0xFF1E40AF),
                ),
              ),
               Expanded(
                 child: _small(
                   'Platform Average',
                   platformAvg == null
                       ? 'Loading...'
                       : '${platformAvg.toStringAsFixed(0)}%',
                   const Color(0xFFF97316),
                 ),
               ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _small(String l, String v, Color c) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          l,
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          v,
          style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _subjectCard(List<_SubjectMetric> subjects, {bool isLoading = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return _card(
      'Subject-wise Performance',
      isLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            )
          : subjects.isEmpty
          ? Text(
              'No subject data available',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          : Column(
              children: subjects.map((s) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          s.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (s.accuracy / 100).clamp(0.0, 1.0),
                            minHeight: 12,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 34,
                        child: Text(
                          s.accuracy.toStringAsFixed(0),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _skills(_Vm vm, _DeferredVmData deferred) {
    final colorScheme = Theme.of(context).colorScheme;
    return _card(
      'Skills Assessment',
      Column(
        children: [
          SizedBox(
            height: 190,
            child: _Radar(
              items: [
                _R('Speed', vm.speed),
                _R('Accuracy', vm.skillAcc),
                _R('Consistency', vm.consistency),
                _R('Time Mgmt', vm.timeMgmt),
                _R('Difficulty', deferred.difficulty),
              ],
            ),
          ),
          Divider(height: 20, color: colorScheme.outlineVariant),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Best Skill',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deferred.bestSkill,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Focus Area',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deferred.focusArea,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFEA580C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weeklyActivity(_Vm vm) {
    final colorScheme = Theme.of(context).colorScheme;
    return _card(
      'Weekly Activity',
      vm.weekly.isEmpty
          ? Text(
              'No weekly activity yet',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          : Column(
              children: vm.weekly.map((w) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            w.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${w.score.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${w.attempts} tests',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _fmtMins(w.minutes),
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: (w.score / 100).clamp(0.0, 1.0),
                          backgroundColor:
                              colorScheme.surfaceContainerHighest,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _performanceInsights(_Vm vm, _DeferredVmData deferred) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: colorScheme.primary,
                child: Icon(
                  Icons.lightbulb,
                  color: colorScheme.onPrimary,
                  size: 12,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Performance Insights',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You\'ve improved by ${vm.delta.toStringAsFixed(0)}% in the last ${_window.label.toLowerCase()}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          ...deferred.insights.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      i,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(_Vm vm) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: vm.latestAttemptId == null ||
                    vm.latestAttemptData == null ||
                    vm.latestResultData == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TestSolutionScreen(
                          attemptId: vm.latestAttemptId!,
                          attemptData: vm.latestAttemptData!,
                          resultData: vm.latestResultData!,
                        ),
                      ),
                    );
                  },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              'View Solution',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () async {
              if (_examId != null && _examId!.isNotEmpty) {
                await UserExamPreferenceService.savePreferredExamId(_examId!);
              }
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MainNavigation(initialIndex: 1),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              'Take New Test',
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(String title, Widget child) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _performanceSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: const [
        _PerformanceSkeletonHero(),
        SizedBox(height: 10),
        _PerformanceSkeletonCard(height: 54),
        SizedBox(height: 10),
        _PerformanceSkeletonCard(height: 280),
        SizedBox(height: 10),
        _PerformanceSkeletonCard(height: 190),
      ],
    );
  }

  Widget _deferredSectionsPlaceholder() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const _SkeletonBlock(width: 20, height: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading the rest of your performance insights...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtMins(int mins) {
    if (mins <= 0) return '0m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
  }
}

class _PerformanceSkeletonHero extends StatelessWidget {
  const _PerformanceSkeletonHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF24439A), Color(0xFF3459B9)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _SkeletonBlock(width: double.infinity, height: 18)),
              const SizedBox(width: 12),
              const _SkeletonBlock(width: 92, height: 30, color: Colors.white),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: _SkeletonBlock(width: double.infinity, height: 72)),
              SizedBox(width: 8),
              Expanded(child: _SkeletonBlock(width: double.infinity, height: 72)),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(child: _SkeletonBlock(width: double.infinity, height: 72)),
              SizedBox(width: 8),
              Expanded(child: _SkeletonBlock(width: double.infinity, height: 72)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerformanceSkeletonCard extends StatelessWidget {
  final double height;

  const _PerformanceSkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonBlock(width: 160, height: 16),
          const SizedBox(height: 12),
          _SkeletonBlock(width: double.infinity, height: height),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.color = const Color(0xFFE2E8F0),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedColor = color == const Color(0xFFE2E8F0)
        ? colorScheme.surfaceContainerHighest
        : color;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: resolvedColor.withValues(
            alpha: color == Colors.white ? 0.2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.platformAvg});

  final List<_P> points;
  final double? platformAvg;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _TrendPainter(points, platformAvg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(points.first.date),
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              _fmt(points.last.date),
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[d.month - 1]} ${d.day}';
  }
}

class _TrendPainter extends CustomPainter {
  final List<_P> points;
  final double? platformAvg;
  _TrendPainter(this.points, this.platformAvg);

  @override
  void paint(Canvas canvas, Size size) {
    const l = 26.0;
    const r = 8.0;
    const t = 8.0;
    const b = 20.0;
    final left = l;
    final right = size.width - r;
    final top = t;
    final bottom = size.height - b;
    final w = right - left;
    final h = bottom - top;

    final grid = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = top + (h * i / 4);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final p = Path();
    final line = Paint()
      ..color = const Color(0xFF1E40AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dot = Paint()..color = const Color(0xFF1E40AF);
    for (int i = 0; i < points.length; i++) {
      final x = left + (w * i / math.max(1, points.length - 1));
      final y = bottom - (points[i].score.clamp(0, 100) / 100.0) * h;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.8, dot);
    }
    canvas.drawPath(p, line);

    if (platformAvg != null) {
      final py = bottom - (platformAvg!.clamp(0, 100) / 100.0) * h;
      final pp = Paint()
        ..color = const Color(0xFFF97316)
        ..strokeWidth = 1.5;
      double x = left;
      while (x < right) {
        canvas.drawLine(Offset(x, py), Offset(math.min(x + 5, right), py), pp);
        x += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.platformAvg != platformAvg;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 14, height: 2, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _R {
  final String label;
  final double value;
  const _R(this.label, this.value);
}

class _Radar extends StatelessWidget {
  final List<_R> items;
  const _Radar({required this.items});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarPainter(items),
      child: const SizedBox.expand(),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<_R> items;
  _RadarPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 8);
    final rad = math.min(size.width, size.height) * 0.34;
    final g = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int r = 1; r <= 4; r++) {
      canvas.drawPath(_poly(c, rad * (r / 4), items.length), g);
    }

    for (int i = 0; i < items.length; i++) {
      final a = _ang(i, items.length);
      final e = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      canvas.drawLine(c, e, g);
      final tp = TextPainter(
        text: TextSpan(
          text: items[i].label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          c.dx + (rad + 12) * math.cos(a) - tp.width / 2,
          c.dy + (rad + 12) * math.sin(a) - tp.height / 2,
        ),
      );
    }

    final v = Path();
    for (int i = 0; i < items.length; i++) {
      final rr = (items[i].value.clamp(0, 100) / 100.0) * rad;
      final a = _ang(i, items.length);
      final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      if (i == 0) {
        v.moveTo(p.dx, p.dy);
      } else {
        v.lineTo(p.dx, p.dy);
      }
    }
    v.close();

    final fill = Paint()
      ..color = const Color(0xFF4F46E5).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final st = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(v, fill);
    canvas.drawPath(v, st);
  }

  Path _poly(Offset c, double r, int n) {
    final p = Path();
    for (int i = 0; i < n; i++) {
      final a = _ang(i, n);
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    return p;
  }

  double _ang(int i, int n) => (-math.pi / 2) + (2 * math.pi * i / n);

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.items != items;
}
