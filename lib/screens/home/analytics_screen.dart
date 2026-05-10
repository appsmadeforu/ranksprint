import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/exam_metadata_cache_service.dart';
import '../../services/result_data_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/top_header.dart';
import 'main_navigation.dart';
import 'subject_insights_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialExamId;

  const AnalyticsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialExamId,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with TickerProviderStateMixin {
  String? selectedExamId;
  List<String> userExamIds = [];
  final TextEditingController _leaderboardSearchController =
      TextEditingController();
  final ScrollController _leaderboardScrollController = ScrollController();
  String _leaderboardQuery = '';
  final Map<String, String> _userNameCache = <String, String>{};
  final Set<String> _pendingUserNameIds = <String>{};
  final Map<String, Future<_DashboardVm>> _dashboardFutureCache =
      <String, Future<_DashboardVm>>{};
  final Map<String, Future<List<_LeaderboardRow>>> _leaderboardFutureCache =
      <String, Future<List<_LeaderboardRow>>>{};
  final Map<String, Future<_CompetitionVm>> _competitionFutureCache =
      <String, Future<_CompetitionVm>>{};
  final Set<String> _dashboardPrefetchKeys = <String>{};
  final ValueNotifier<_DashboardTrendMode> _trendModeNotifier = ValueNotifier(
    _DashboardTrendMode.avg,
  );
  final ValueNotifier<_SubjectViewMode> _subjectViewModeNotifier =
      ValueNotifier(_SubjectViewMode.score);
  final ValueNotifier<int> _heroPageIndexNotifier = ValueNotifier(0);
  final PageController _heroPageController = PageController();
  late final AnimationController _liveBlinkController;
  late final TabController _tabController;
  late final List<bool> _visitedTabs;
  bool _showDeferredDashboardSections = false;
  String? _deferredDashboardKey;
  final Map<String, List<_LeaderboardRow>> _leaderboardRowsByExam =
      <String, List<_LeaderboardRow>>{};
  final Map<String, DocumentSnapshot<Map<String, dynamic>>?>
  _leaderboardLastDocsByExam =
      <String, DocumentSnapshot<Map<String, dynamic>>?>{};
  final Set<String> _leaderboardLoadingExams = <String>{};
  final Set<String> _leaderboardLoadedExams = <String>{};
  final Set<String> _leaderboardHasMoreExams = <String>{};
  final Map<String, String?> _leaderboardErrorByExam = <String, String?>{};

  @override
  void initState() {
    super.initState();
    final initialTabIndex = widget.initialTabIndex.clamp(0, 1);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialTabIndex,
    )..addListener(_handleTabChanged);
    _visitedTabs = List<bool>.filled(2, false);
    _visitedTabs[initialTabIndex] = true;
    _liveBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _leaderboardScrollController.addListener(_handleLeaderboardScroll);
    UserExamPreferenceService.preferredExamNotifier.addListener(
      _handlePreferredExamChanged,
    );
    _loadUserExams();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final exams = List<String>.from(doc.data()?['selectedExams'] ?? []);
    final preferredExamId = await UserExamPreferenceService.loadPreferredExamId(
      availableExamIds: exams,
    );
    final resolvedExamId =
        widget.initialExamId != null && exams.contains(widget.initialExamId)
        ? widget.initialExamId
        : exams.contains(preferredExamId)
        ? preferredExamId
        : (exams.isNotEmpty ? exams.first : null);
    if (!mounted) return;
    setState(() {
      userExamIds = exams;
      selectedExamId = resolvedExamId;
    });
    _prefetchDashboardForSelectedExam();
  }

  @override
  void didUpdateWidget(covariant AnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextTabIndex = widget.initialTabIndex.clamp(0, 1);
    if (_tabController.index != nextTabIndex) {
      _tabController.animateTo(nextTabIndex);
      _visitedTabs[nextTabIndex] = true;
    }

    final nextExamId = widget.initialExamId;
    if (nextExamId != null &&
        nextExamId.isNotEmpty &&
        nextExamId != selectedExamId &&
        userExamIds.contains(nextExamId)) {
      setState(() {
        selectedExamId = nextExamId;
        _showDeferredDashboardSections = false;
        _deferredDashboardKey = null;
      });
      _prefetchDashboardForSelectedExam();
    }
  }

  @override
  void dispose() {
    UserExamPreferenceService.preferredExamNotifier.removeListener(
      _handlePreferredExamChanged,
    );
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _trendModeNotifier.dispose();
    _subjectViewModeNotifier.dispose();
    _heroPageIndexNotifier.dispose();
    _leaderboardSearchController.dispose();
    _leaderboardScrollController
      ..removeListener(_handleLeaderboardScroll)
      ..dispose();
    _heroPageController.dispose();
    _liveBlinkController.dispose();
    super.dispose();
  }

  void _handlePreferredExamChanged() {
    final preferredExamId =
        UserExamPreferenceService.preferredExamNotifier.value;
    if (!mounted ||
        preferredExamId == null ||
        preferredExamId == selectedExamId ||
        !userExamIds.contains(preferredExamId)) {
      return;
    }

    setState(() {
      selectedExamId = preferredExamId;
      _dashboardFutureCache.clear();
      _leaderboardFutureCache.remove(preferredExamId);
      _competitionFutureCache.remove(preferredExamId);
      _resetLeaderboardPaging(preferredExamId);
      _dashboardPrefetchKeys.clear();
      _showDeferredDashboardSections = false;
      _deferredDashboardKey = null;
    });
    _prefetchDashboardForSelectedExam();
  }

  void _handleTabChanged() {
    final index = _tabController.index;
    if (_tabController.indexIsChanging) {
      return;
    }
    if (_visitedTabs[index]) {
      setState(() {});
      return;
    }
    setState(() {
      _visitedTabs[index] = true;
    });
  }

  void _scheduleDeferredDashboardSections(String dashboardKey) {
    if (_deferredDashboardKey == dashboardKey &&
        _showDeferredDashboardSections) {
      return;
    }
    _deferredDashboardKey = dashboardKey;
    _showDeferredDashboardSections = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _deferredDashboardKey != dashboardKey) return;
      setState(() {
        _showDeferredDashboardSections = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (examId) {
                if (!mounted) return;
                setState(() {
                  selectedExamId = examId;
                  _dashboardFutureCache.clear();
                  _leaderboardFutureCache.remove(examId);
                  _competitionFutureCache.remove(examId);
                  _resetLeaderboardPaging(examId);
                  _dashboardPrefetchKeys.clear();
                  _showDeferredDashboardSections = false;
                  _deferredDashboardKey = null;
                });
                _prefetchDashboardForSelectedExam();
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: selectedExamId == null
                  ? const Center(child: Text('No exam selected'))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withValues(
                                    alpha: 0.10,
                                  ),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(14),
                                ),
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor: colorScheme.onPrimary,
                              unselectedLabelColor:
                                  colorScheme.onSurfaceVariant,
                              dividerColor: Colors.transparent,
                              tabs: [
                                Tab(text: 'Dashboard'),
                                Tab(text: 'Leaderboard'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: IndexedStack(
                            index: _tabController.index,
                            children: [
                              _visitedTabs[0]
                                  ? _buildDashboard()
                                  : const SizedBox.shrink(),
                              _visitedTabs[1]
                                  ? _buildLeaderboard()
                                  : const SizedBox.shrink(),
                            ],
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

  Widget _buildLeaderboard() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final examId = selectedExamId;
    if (examId == null || examId.isEmpty) {
      return const Center(child: Text('No leaderboard data'));
    }
    _ensureLeaderboardLoaded(examId);

    final error = _leaderboardErrorByExam[examId];
    if (error != null) {
      return const OfflineState(
        message:
            'Could not load leaderboard. Please check your connection and try again.',
      );
    }

    final allRows = _leaderboardRowsByExam[examId] ?? const <_LeaderboardRow>[];
    final isLoading = _leaderboardLoadingExams.contains(examId);
    final isLoaded = _leaderboardLoadedExams.contains(examId);
    if (!isLoaded && allRows.isEmpty) {
      return _leaderboardSkeleton();
    }
    if (isLoaded && allRows.isEmpty) {
      return const Center(child: Text('No leaderboard data'));
    }

    final visibleRows = allRows.where(_matchesLeaderboardQuery).toList();
    if (visibleRows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _buildLeaderboardSearch(),
            const Expanded(
              child: Center(child: Text('No leaderboard matches found')),
            ),
          ],
        ),
      );
    }

    final hasMore = _leaderboardHasMoreExams.contains(examId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildLeaderboardSearch(),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.builder(
              controller: _leaderboardScrollController,
              itemCount: visibleRows.length + ((hasMore || isLoading) ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= visibleRows.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text('Loading more leaderboard entries...'),
                    ),
                  );
                }
                final row = visibleRows[index];
                return _buildLeaderboardCard(
                  row: row,
                  isCurrentUser:
                      currentUser != null &&
                      currentUser.uid == row.entry.userId,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleLeaderboardScroll() {
    final examId = selectedExamId;
    if (examId == null || examId.isEmpty) return;
    if (!_leaderboardHasMoreExams.contains(examId)) return;
    if (_leaderboardLoadingExams.contains(examId)) return;
    if (!_leaderboardScrollController.hasClients) return;
    final position = _leaderboardScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreLeaderboardRows(examId);
    }
  }

  void _ensureLeaderboardLoaded(String examId) {
    if (_leaderboardLoadedExams.contains(examId) ||
        _leaderboardLoadingExams.contains(examId)) {
      return;
    }
    _loadMoreLeaderboardRows(examId, reset: true);
  }

  void _resetLeaderboardPaging(String? examId) {
    if (examId == null || examId.isEmpty) return;
    _leaderboardRowsByExam.remove(examId);
    _leaderboardLastDocsByExam.remove(examId);
    _leaderboardLoadingExams.remove(examId);
    _leaderboardLoadedExams.remove(examId);
    _leaderboardHasMoreExams.remove(examId);
    _leaderboardErrorByExam.remove(examId);
  }

  Future<void> _loadMoreLeaderboardRows(
    String examId, {
    bool reset = false,
  }) async {
    if (examId.isEmpty) return;
    if (_leaderboardLoadingExams.contains(examId)) return;
    if (!reset &&
        _leaderboardLoadedExams.contains(examId) &&
        !_leaderboardHasMoreExams.contains(examId)) {
      return;
    }

    _leaderboardLoadingExams.add(examId);
    _leaderboardErrorByExam.remove(examId);
    if (mounted) {
      setState(() {});
    }

    try {
      final pageSize = reset ? 40 : 30;
      final summaryRows = await _loadLeaderboardSummaryPage(
        examId: examId,
        pageSize: pageSize,
        startAfter: reset ? null : _leaderboardLastDocsByExam[examId],
      );
      if (summaryRows != null) {
        final rows = reset
            ? summaryRows.rows
            : <_LeaderboardRow>[
                ...?_leaderboardRowsByExam[examId],
                ...summaryRows.rows,
              ];
        _ensureLeaderboardDisplayNames(rows.map((row) => row.entry.userId));
        _leaderboardRowsByExam[examId] = rows;
        _leaderboardLastDocsByExam[examId] = summaryRows.lastDoc;
        if (summaryRows.rows.length < pageSize) {
          _leaderboardHasMoreExams.remove(examId);
        } else {
          _leaderboardHasMoreExams.add(examId);
        }
        _leaderboardLoadedExams.add(examId);
      } else {
        await _loadMoreLeaderboardRowsFromResults(examId, reset: reset);
      }
    } catch (_) {
      _leaderboardErrorByExam[examId] = 'load_failed';
    } finally {
      _leaderboardLoadingExams.remove(examId);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadMoreLeaderboardRowsFromResults(
    String examId, {
    required bool reset,
  }) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('results')
        .where('examId', isEqualTo: examId)
        .orderBy('createdAt', descending: true)
        .limit(reset ? 40 : 30);
    final lastDoc = reset ? null : _leaderboardLastDocsByExam[examId];
    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snap = await query.get();
    final docs = snap.docs;
    final fetchedEntries = _aggregateLeaderboard(docs);
    await _loadUserDisplayNames(fetchedEntries.map((entry) => entry.userId));

    final existingRows = reset
        ? <_LeaderboardRow>[]
        : List<_LeaderboardRow>.from(
            _leaderboardRowsByExam[examId] ?? const <_LeaderboardRow>[],
          );
    final byUser = <String, _LeaderboardAgg>{
      for (final row in existingRows) row.entry.userId: row.entry,
    };
    for (final entry in fetchedEntries) {
      byUser[entry.userId] = entry;
    }

    final mergedEntries = byUser.values.toList()
      ..sort((a, b) {
        final scoreCompare = b.avgScore.compareTo(a.avgScore);
        if (scoreCompare != 0) return scoreCompare;
        final percentileCompare = b.avgPercentile.compareTo(a.avgPercentile);
        if (percentileCompare != 0) return percentileCompare;
        return a.userId.compareTo(b.userId);
      });
    _ensureLeaderboardDisplayNames(mergedEntries.map((entry) => entry.userId));
    _leaderboardRowsByExam[examId] = _rowsFromEntries(mergedEntries);
    _leaderboardLastDocsByExam[examId] = docs.isEmpty ? lastDoc : docs.last;
    if (docs.length < (reset ? 40 : 30)) {
      _leaderboardHasMoreExams.remove(examId);
    } else {
      _leaderboardHasMoreExams.add(examId);
    }
    _leaderboardLoadedExams.add(examId);
  }

  Future<_LeaderboardPage?> _loadLeaderboardSummaryPage({
    required String examId,
    required int pageSize,
    required DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .collection('leaderboard')
          .orderBy('avgScore', descending: true)
          .orderBy('avgPercentile', descending: true)
          .limit(pageSize);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snap = await query.get();
      if (snap.docs.isEmpty && startAfter == null) {
        return null;
      }
      final rows = snap.docs
          .map(_leaderboardRowFromSummaryDoc)
          .whereType<_LeaderboardRow>()
          .toList(growable: false);
      if (rows.isEmpty && startAfter == null) {
        return null;
      }
      await _loadUserDisplayNames(rows.map((row) => row.entry.userId));
      return _LeaderboardPage(
        rows: rows,
        lastDoc: snap.docs.isEmpty ? startAfter : snap.docs.last,
      );
    } catch (_) {
      return null;
    }
  }

  _LeaderboardRow? _leaderboardRowFromSummaryDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final userId = (data['userId'] ?? doc.id).toString().trim();
    if (userId.isEmpty) return null;
    final agg = _LeaderboardAgg(userId: userId)
      ..testsTaken = _toInt(data['testsTaken']) ?? 0
      ..totalScore =
          (_toDouble(data['avgScore']) ?? 0) * (_toInt(data['testsTaken']) ?? 0)
      ..totalPercentile =
          (_toDouble(data['avgPercentile']) ?? 0) *
          (_toInt(data['testsTaken']) ?? 0)
      ..bestScore = _toDouble(data['bestScore']) ?? 0
      ..avgScore = _toDouble(data['avgScore']) ?? 0
      ..avgPercentile = _toDouble(data['avgPercentile']) ?? 0;
    final displayName = _compactLeaderboardName(
      (data['displayName'] ?? userId).toString(),
    );
    _userNameCache[userId] = displayName;
    return _LeaderboardRow(
      entry: agg,
      rank: _toInt(data['rank']) ?? 0,
      displayName: displayName,
    );
  }

  Widget _buildLeaderboardSearch() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _leaderboardSearchController,
        onChanged: (value) {
          setState(() {
            _leaderboardQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: 'Search by name or rank...',
          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: colorScheme.surface,
        ),
      ),
    );
  }

  List<_LeaderboardRow> _rowsFromEntries(List<_LeaderboardAgg> entries) {
    return List.generate(entries.length, (index) {
      final entry = entries[index];
      return _LeaderboardRow(
        entry: entry,
        rank: index + 1,
        displayName: _userNameCache[entry.userId] ?? entry.userId,
      );
    });
  }

  void _ensureLeaderboardDisplayNames(Iterable<String> userIds) {
    final missing = userIds
        .where(
          (id) =>
              id.isNotEmpty &&
              !_userNameCache.containsKey(id) &&
              !_pendingUserNameIds.contains(id),
        )
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    _pendingUserNameIds.addAll(missing);
    _loadUserDisplayNames(missing);
  }

  Future<void> _loadUserDisplayNames(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;

    for (int i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final rawName = (data['name'] ?? data['displayName'] ?? doc.id)
              .toString();
          _userNameCache[doc.id] = _compactLeaderboardName(rawName);
        }

        for (final id in chunk) {
          _userNameCache.putIfAbsent(id, () => id);
        }
      } catch (_) {
        for (final id in chunk) {
          _userNameCache.putIfAbsent(id, () => id);
        }
      }
    }
    _pendingUserNameIds.removeAll(ids);
    if (mounted) {
      setState(() {});
    }
  }

  bool _matchesLeaderboardQuery(_LeaderboardRow row) {
    if (_leaderboardQuery.isEmpty) return true;

    return row.displayName.toLowerCase().contains(_leaderboardQuery) ||
        row.rank.toString().contains(_leaderboardQuery);
  }

  String _compactLeaderboardName(String rawName) {
    final parts = rawName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return rawName.trim();
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last}';
  }

  double _leaderboardPercentile(Map<String, dynamic> data, double score) {
    final raw =
        (data['percentile'] as num?)?.toDouble() ??
        (data['avgPercentile'] as num?)?.toDouble() ??
        (data['percentileScore'] as num?)?.toDouble() ??
        (data['percentage'] as num?)?.toDouble();
    final fallback = raw == null || raw <= 0 ? score : raw;
    return fallback.clamp(0.0, 100.0);
  }

  Widget _buildLeaderboardCard({
    required _LeaderboardRow row,
    required bool isCurrentUser,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final rank = row.rank;
    final badgeColor = isCurrentUser
        ? const Color(0xFF2F6FEB)
        : rank == 1
        ? Colors.amber
        : rank == 2
        ? Colors.grey
        : rank == 3
        ? Colors.brown
        : const Color(0xFFEFF3FF);
    final badgeForeground = isCurrentUser || rank <= 3
        ? Colors.white
        : const Color(0xFF2F6FEB);
    final cardBorderColor = isCurrentUser
        ? const Color(0xFF2F6FEB)
        : Colors.transparent;
    final titleColor = isCurrentUser ? colorScheme.onPrimary : colorScheme.onSurface;
    final captionColor = isCurrentUser
        ? colorScheme.onPrimary.withValues(alpha: 0.82)
        : colorScheme.onSurfaceVariant;
    final scoreColor = isCurrentUser
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        elevation: isCurrentUser ? 10 : 6,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: isCurrentUser
                ? const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF60A5FA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isCurrentUser ? null : colorScheme.surface,
            boxShadow: isCurrentUser
                ? const [
                    BoxShadow(
                      color: Color(0x332F6FEB),
                      blurRadius: 22,
                      offset: Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: isCurrentUser
                  ? colorScheme.primaryContainer.withValues(alpha: 0.20)
                  : colorScheme.surface,
              border: Border.all(color: cardBorderColor, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: badgeColor,
                  ),
                  child: Center(
                    child: rank <= 3
                        ? Icon(Icons.emoji_events, color: badgeForeground)
                        : Text(
                            '#$rank',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: badgeForeground,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.displayName,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                              ),
                            ),
                          ),
                          if (isCurrentUser)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2F6FEB),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${row.entry.testsTaken} tests - ${row.entry.avgPercentile.toStringAsFixed(1)} %ile',
                        style: TextStyle(fontSize: 13, color: captionColor),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      row.entry.avgScore.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCurrentUser ? 'your score' : 'avg score',
                      style: TextStyle(fontSize: 12, color: captionColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('User not logged in'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('testAttempts')
          .where('examId', isEqualTo: selectedExamId)
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return OfflineState(
            message:
                'Could not load analytics. Please check your connection and try again.',
            onRetry: () {
              if (!mounted) return;
              setState(() {
                _dashboardFutureCache.clear();
                if (selectedExamId != null) {
                  _leaderboardFutureCache.remove(selectedExamId);
                  _competitionFutureCache.remove(selectedExamId);
                  _resetLeaderboardPaging(selectedExamId);
                }
              });
            },
          );
        }
        if (!snap.hasData) {
          return _dashboardSkeleton();
        }

        final attempts =
            snap.data!.docs.where((doc) {
              final status = (doc.data()['status'] ?? 'completed')
                  .toString()
                  .toLowerCase();
              return status == 'completed';
            }).toList()..sort((a, b) {
              final aTs =
                  _toDate(a.data()['submittedAt']) ??
                  _toDate(a.data()['startedAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final bTs =
                  _toDate(b.data()['submittedAt']) ??
                  _toDate(b.data()['startedAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return aTs.compareTo(bTs);
            });

        final dashboardCacheKey = attempts.isEmpty
            ? '${user.uid}|${selectedExamId!}|empty'
            : _dashboardCacheKey(
                userId: user.uid,
                examId: selectedExamId!,
                attempts: attempts,
              );

        return FutureBuilder<_DashboardVm>(
          future: _dashboardFutureCache.putIfAbsent(dashboardCacheKey, () {
            if (attempts.isEmpty) {
              return _emptyDashboardVm(selectedExamId!);
            }
            return _loadDashboardVm(user.uid, selectedExamId!, attempts);
          }),
          builder: (context, vmSnap) {
            if (vmSnap.hasError) {
              return OfflineState(
                message:
                    'Could not load analytics. Please check your connection and try again.',
                onRetry: () {
                  if (!mounted) return;
                  setState(() {
                    _dashboardFutureCache.clear();
                    if (selectedExamId != null) {
                      _leaderboardFutureCache.remove(selectedExamId);
                      _competitionFutureCache.remove(selectedExamId);
                      _resetLeaderboardPaging(selectedExamId);
                    }
                  });
                },
              );
            }
            if (!vmSnap.hasData) {
              return _dashboardSkeleton();
            }

            final vm = vmSnap.data!;
            _scheduleDeferredDashboardSections(dashboardCacheKey);

            return RefreshIndicator(
              onRefresh: () async {
                if (!mounted) return;
                setState(() {});
                _dashboardFutureCache.clear();
                _leaderboardFutureCache.remove(selectedExamId);
                _competitionFutureCache.remove(selectedExamId);
                _resetLeaderboardPaging(selectedExamId);
                _showDeferredDashboardSections = false;
                _deferredDashboardKey = null;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
                children: [
                  _dashboardHero(vm),
                  if (vm.needsMoreDataForDeepAnalysis) ...[
                    const SizedBox(height: 14),
                    _analysisHintCard(),
                  ],
                  const SizedBox(height: 14),
                  _performanceTrendCard(vm),
                  const SizedBox(height: 14),
                  _subjectWiseCard(vm),
                  if (_showDeferredDashboardSections) ...[
                    const SizedBox(height: 14),
                    _chapterHeatmapCard(vm),
                    const SizedBox(height: 14),
                    _timeAnalyticsCard(vm),
                    const SizedBox(height: 14),
                    _riskBehaviourCard(vm),
                    const SizedBox(height: 14),
                    _competitionComparisonCard(vm),
                    const SizedBox(height: 14),
                    _consistencyRadarCard(vm),
                    const SizedBox(height: 14),
                    _recommendationsCard(vm),
                  ] else ...[
                    const SizedBox(height: 14),
                    _deferredSectionsPlaceholder(),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _dashboardHero(_DashboardVm vm) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Analytics',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${vm.testsTaken} tests analyzed - Updated ${_relativeTime(vm.lastUpdated)}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F9EA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBDE9C9)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.35, end: 1).animate(
                      CurvedAnimation(
                        parent: _liveBlinkController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: const Icon(
                      Icons.circle,
                      size: 10,
                      color: Color(0xFF31B56A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Live',
                    style: TextStyle(
                      color: Color(0xFF1E8B4B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Performance Overview',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            GestureDetector(
              onTap: _goToNextHeroPage,
              child: Text(
                'Swipe ->',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 308,
          child: PageView(
            controller: _heroPageController,
            onPageChanged: _handleHeroPageChanged,
            children: [
              _readinessHeroCard(vm),
              _accuracySpeedHeroCard(vm),
              _rankProjectionHeroCard(vm),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<int>(
          valueListenable: _heroPageIndexNotifier,
          builder: (context, heroPageIndex, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                final selected = index == heroPageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF2E4BCB)
                        : const Color(0xFFC8D1EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _analysisHintCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF4C95D)),
      ),
      child: const Text(
        'Take at least 3 tests to unlock deeper analysis.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8A5A11),
        ),
      ),
    );
  }

  void _prefetchDashboardForSelectedExam() {
    final user = FirebaseAuth.instance.currentUser;
    final examId = selectedExamId;
    if (user == null || examId == null || examId.isEmpty) return;
    final prefetchKey = '${user.uid}|$examId';
    if (_dashboardPrefetchKeys.contains(prefetchKey)) return;
    _dashboardPrefetchKeys.add(prefetchKey);

    FirebaseFirestore.instance
        .collection('testAttempts')
        .where('examId', isEqualTo: examId)
        .where('userId', isEqualTo: user.uid)
        .get()
        .then((snap) {
          final attempts =
              snap.docs.where((doc) {
                final status = (doc.data()['status'] ?? 'completed')
                    .toString()
                    .toLowerCase();
                return status == 'completed';
              }).toList()..sort((a, b) {
                final aTs =
                    _toDate(a.data()['submittedAt']) ??
                    _toDate(a.data()['startedAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final bTs =
                    _toDate(b.data()['submittedAt']) ??
                    _toDate(b.data()['startedAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return aTs.compareTo(bTs);
              });
          if (attempts.isEmpty) return;
          final dashboardCacheKey = _dashboardCacheKey(
            userId: user.uid,
            examId: examId,
            attempts: attempts,
          );
          _dashboardFutureCache.putIfAbsent(
            dashboardCacheKey,
            () => _loadDashboardVm(user.uid, examId, attempts),
          );
        })
        .catchError((_) {});
  }

  String _dashboardCacheKey({
    required String userId,
    required String examId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  }) {
    final stamp = attempts
        .map((doc) {
          final data = doc.data();
          final ts =
              (_toDate(data['submittedAt']) ?? _toDate(data['startedAt']))
                  ?.millisecondsSinceEpoch ??
              0;
          return '${doc.id}:$ts';
        })
        .join('|');
    return '$userId|$examId|$stamp';
  }

  void _handleHeroPageChanged(int index) {
    if (_heroPageIndexNotifier.value == index) return;
    _heroPageIndexNotifier.value = index;
  }

  void _goToNextHeroPage() {
    if (!_heroPageController.hasClients) return;
    final position = _heroPageController.position;
    if (position.isScrollingNotifier.value) return;
    final nextPage = (_heroPageIndexNotifier.value + 1) % 3;
    _heroPageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Widget _glassStat({
    required String label,
    required String value,
    String? helper,
    Color? emphasize,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFFDCE4FF), fontSize: 9),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: emphasize ?? Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 3),
            Text(
              helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFD6E1FF), fontSize: 8),
            ),
          ],
        ],
      ),
    );
  }

  Widget _readinessHeroCard(_DashboardVm vm) {
    return _heroShell(
      colors: const [Color(0xFF2A409F), Color(0xFF3D63DB)],
      badgeText: '${vm.delta >= 0 ? '+' : ''}${vm.delta.toStringAsFixed(0)}',
      badgeSuffix: '%',
      badgeIcon: Icons.trending_up_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(
            eyebrow: 'EXAM READINESS',
            title: vm.examName,
            subtitle: 'Updated ${_relativeTime(vm.lastUpdated)}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (vm.readiness / 100).clamp(0.0, 1.0),
                        strokeWidth: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF66EA8A),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${vm.readiness.round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Ready',
                          style: TextStyle(
                            color: Color(0xFFD6E1FF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _glassStat(
                            label: 'Rank',
                            value: vm.bestRank > 0 ? '#${vm.bestRank}' : '-',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _glassStat(
                            label: 'Percentile',
                            value: vm.avgPercentile.toStringAsFixed(1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _glassStat(
                            label: 'Avg Score',
                            value: '${vm.avgScore.round()}/100',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _glassStat(
                            label: 'Tests Done',
                            value: '${vm.testsTaken}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF39C87D).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF7BE495).withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              vm.delta >= 0
                  ? '+${vm.delta.toStringAsFixed(0)} marks improvement in last 3 tests!'
                  : '${vm.delta.toStringAsFixed(0)} marks against your recent 3 tests.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankProjectionHeroCard(_DashboardVm vm) {
    return _heroShell(
      colors: const [Color(0xFF4A3096), Color(0xFF5A3DB4)],
      badgeText: 'Improving',
      badgeIcon: Icons.arrow_upward_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(
            eyebrow: 'RANK PROJECTION',
            title: 'AI Predicted Range',
            subtitle: 'Based on ${vm.testsTaken} mock tests',
          ),
          const SizedBox(height: 8),
          const Text(
            'Predicted Rank',
            style: TextStyle(color: Color(0xFFD7CBFF), fontSize: 10),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                _predictedRankRange(vm),
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rank Trend (lower = better)',
                  style: TextStyle(color: Color(0xFFD7CBFF), fontSize: 10),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: _SparkLine(points: _rankProjectionPoints(vm)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accuracySpeedHeroCard(_DashboardVm vm) {
    final total = math.max(
      1,
      vm.totalCorrect + vm.totalSkipped + vm.totalIncorrect,
    );
    final accuracy = vm.totalCorrect * 100.0 / total;
    final skip = vm.totalSkipped * 100.0 / total;
    final wrong = vm.totalIncorrect * 100.0 / total;

    return _heroShell(
      colors: const [Color(0xFF15528D), Color(0xFF2872B3)],
      badgeText: '',
      badgeIcon: Icons.gps_fixed_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(
            eyebrow: 'ACCURACY & SPEED',
            title: 'Last 5 Tests Average',
            subtitle: 'Updated ${_relativeTime(vm.lastUpdated)}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _glassStat(
                  label: 'Accuracy',
                  value: '${accuracy.round()}%',
                  helper:
                      '${vm.delta >= 0 ? '+' : ''}${vm.delta.toStringAsFixed(0)} this week',
                  emphasize: const Color(0xFF66EA8A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _glassStat(
                  label: 'Avg Time/Q',
                  value: '${vm.avgSecondsPerQuestion.toStringAsFixed(0)}s',
                  helper: 'Optimal range',
                  emphasize: const Color(0xFFFFC142),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _glassStat(
                  label: vm.hasNegativeMarking ? 'Neg Marks' : 'Marks Lost',
                  value:
                      '${vm.hasNegativeMarking ? '-' : ''}${_formatDashboardMetric(vm.marksLost)}',
                  helper:
                      '${vm.hasNegativeMarking ? '-' : ''}${_formatDashboardMetric(vm.avgMarksLostPerTest)} avg/test',
                  emphasize: const Color(0xFFFF7474),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Correct',
                  style: TextStyle(color: Color(0xFFD6E1FF), fontSize: 11),
                ),
              ),
              Text(
                'Skip',
                style: TextStyle(color: Color(0xFFD6E1FF), fontSize: 11),
              ),
              SizedBox(width: 52),
              Text(
                'Wrong',
                style: TextStyle(color: Color(0xFFD6E1FF), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: math.max(1, accuracy.round()),
                    child: Container(color: const Color(0xFF41E188)),
                  ),
                  Expanded(
                    flex: math.max(1, skip.round()),
                    child: Container(color: const Color(0xFFFFC232)),
                  ),
                  Expanded(
                    flex: math.max(1, wrong.round()),
                    child: Container(color: const Color(0xFFFF7474)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${accuracy.round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              Text(
                '${skip.round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              const Spacer(),
              Text(
                '${wrong.round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroShell({
    required List<Color> colors,
    required Widget child,
    required String badgeText,
    required IconData badgeIcon,
    String? badgeSuffix,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26233A8B),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -10,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -22,
            bottom: -30,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF63D598).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          badgeIcon,
                          size: 14,
                          color: const Color(0xFF66EA8A),
                        ),
                        if (badgeText.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '$badgeText${badgeSuffix ?? ''}',
                            style: const TextStyle(
                              color: Color(0xFF66EA8A),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              child,
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroHeader({
    required String eyebrow,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: Color(0xFFD6E1FF),
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFFD6E1FF), fontSize: 10),
        ),
      ],
    );
  }

  String _predictedRankRange(_DashboardVm vm) {
    final baseRank = vm.bestRank > 0
        ? vm.bestRank
        : math.max(200, ((100 - vm.avgPercentile) * 20).round());
    final lower = math.max(1, (baseRank * 0.82).round());
    final upper = math.max(lower + 1, (baseRank * 1.12).round());
    return '#${_compactNumber(lower)}-${_compactNumber(upper)}';
  }

  List<double> _rankProjectionPoints(_DashboardVm vm) {
    final baseRank = vm.bestRank > 0
        ? vm.bestRank.toDouble()
        : math.max(200, ((100 - vm.avgPercentile) * 20).round()).toDouble();
    final source = vm.trendPoints.isEmpty
        ? <double>[baseRank, baseRank * 0.96, baseRank * 0.92, baseRank * 0.88]
        : vm.trendPoints
              .map((point) => math.max(1.0, baseRank - point.score * 3.2))
              .toList();
    return source.take(6).toList();
  }

  String _compactNumber(int value) {
    final text = value.toString();
    final parts = <String>[];
    for (int i = 0; i < text.length; i++) {
      final fromEnd = text.length - i;
      parts.add(text[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) {
        parts.add(',');
      }
    }
    return parts.join();
  }

  Widget _performanceTrendCard(_DashboardVm vm) {
    return ValueListenableBuilder<_DashboardTrendMode>(
      valueListenable: _trendModeNotifier,
      builder: (context, trendMode, child) {
        final displayPoints = _displayTrendPoints(vm.trendPoints, trendMode);
        final competitionFuture = _competitionFutureFor(vm);
        return _dashboardSection(
          title: 'Performance Trend',
          subtitle:
              'Last ${vm.testsTaken} tests - score out of 100 - competitors average from live results',
          trailing: _segmentedPill<_DashboardTrendMode>(
            value: trendMode,
            options: const {
              _DashboardTrendMode.avg: 'AVG',
              _DashboardTrendMode.max: 'MAX',
            },
            onChanged: (mode) => _trendModeNotifier.value = mode,
          ),
          child: Column(
            children: [
              SizedBox(
                height: 190,
                child: FutureBuilder<_CompetitionVm>(
                  future: competitionFuture,
                  builder: (context, competitionSnap) {
                    final platformAvg = competitionSnap.data?.platformAvg ?? 0.0;
                    return _TrendChart(
                      points: displayPoints,
                      platformAvg: platformAvg,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: _StatChip(label: 'You', dotColor: Color(0xFF315CF7)),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: _StatChip(
                      label: 'Competitors Avg',
                      dotColor: Color(0xFF9EA4B2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniMetric(
                      label: 'Best',
                      value: '${vm.maxScore.round()}',
                      color: const Color(0xFF1B45D0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SubjectInsightsScreen(examId: selectedExamId ?? ''),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2D4FCA),
                  side: const BorderSide(color: Color(0xFFD9DFF0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text(
                  'View Full Performance',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _subjectWiseCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Subject Wise Performance',
      subtitle: 'Your score, accuracy, and average time by subject',
      child: ValueListenableBuilder<_SubjectViewMode>(
        valueListenable: _subjectViewModeNotifier,
        builder: (context, subjectViewMode, child) {
          final subjects = vm.subjects.isEmpty
              ? _placeholderSubjects()
              : vm.subjects;
          return Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _segmentedPill<_SubjectViewMode>(
                  value: subjectViewMode,
                  options: const {
                    _SubjectViewMode.score: 'Score',
                    _SubjectViewMode.accuracy: 'Accuracy',
                    _SubjectViewMode.time: 'Time',
                  },
                  onChanged: (mode) => _subjectViewModeNotifier.value = mode,
                  expand: true,
                ),
              ),
              const SizedBox(height: 14),
              Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: subjects.take(4).map((subject) {
                        final maxValue = _subjectMaxValue(
                          subjects,
                          subjectViewMode,
                        );
                        final value = _subjectMetricValue(
                          subject,
                          subjectViewMode,
                        );
                        final normalizedHeight = maxValue <= 0
                            ? 0.0
                            : 120 * (value / maxValue);
                        final height = value <= 0
                            ? 0.0
                            : normalizedHeight.clamp(10.0, 120.0);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Column(
                              children: [
                                Text(
                                  _subjectMetricLabel(subject, subjectViewMode),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  height: 126,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    height: height,
                                    decoration: BoxDecoration(
                                      color: _subjectColor(subject.name),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  subject.shortName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF6C748A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: subjects.take(4).map((subject) {
                        return _LegendDot(
                          color: _subjectColor(subject.name),
                          label: subject.name,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF4C95D)),
                    ),
                    child: Text(
                      vm.subjects.isEmpty
                          ? 'Take at least 3 tests to unlock deeper subject analysis.'
                          : 'A weak accuracy dip was detected in ${vm.focusSubject}.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A5A11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _SubjectExplorerScreen(vm: vm),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2D4FCA),
                      side: const BorderSide(color: Color(0xFFD9DFF0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text(
                      'View Subject Insights',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  List<_SubjectMetric> _placeholderSubjects() {
    return [
      _SubjectMetric('Subject 1'),
      _SubjectMetric('Subject 2'),
      _SubjectMetric('Subject 3'),
      _SubjectMetric('Subject 4'),
    ];
  }

  Widget _dashboardSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
      children: const [
        _DashboardSkeletonHero(),
        SizedBox(height: 14),
        _DashboardSkeletonCard(height: 260),
        SizedBox(height: 14),
        _DashboardSkeletonCard(height: 320),
        SizedBox(height: 14),
        _DashboardSkeletonCard(height: 220),
      ],
    );
  }

  Widget _deferredSectionsPlaceholder() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading the rest of your analytics...',
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

  Widget _leaderboardSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildLeaderboardSearch(),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _leaderboardSkeletonCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardSkeletonCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant, width: 1.2),
      ),
      child: const Row(
        children: [
          _SkeletonBlock(width: 56, height: 56, radius: 28),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: 150, height: 16),
                SizedBox(height: 10),
                _SkeletonBlock(width: 120, height: 12),
              ],
            ),
          ),
          SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SkeletonBlock(width: 42, height: 20),
              SizedBox(height: 8),
              _SkeletonBlock(width: 58, height: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chapterHeatmapCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Chapter Proficiency Heatmap',
      subtitle: 'Topic-level accuracy from your answered questions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._groupedChapterRows(vm.chapters),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _ChapterExplorerScreen(vm: vm),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFF3E8),
              foregroundColor: const Color(0xFFAA5A11),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              minimumSize: const Size.fromHeight(42),
            ),
            child: const Text(
              'View Chapter Insights',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeAnalyticsCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Time Management Analytics',
      subtitle: 'Timer per question and time score from recent attempts',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _miniSurface(
                  title: 'Time per Subject',
                  child: Column(
                    children: [
                      SizedBox(
                        height: 120,
                        child: _DonutChart(slices: vm.timeSlices),
                      ),
                      const SizedBox(height: 10),
                      ...vm.timeSlices.map(
                        (slice) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: slice.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${slice.label} ${slice.value.round()}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF6C748A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniSurface(
                  title: 'Time vs Score',
                  child: Column(
                    children: [
                      SizedBox(
                        height: 120,
                        child: _SparkLine(points: vm.timeScoreTrend),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF3FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Best ${vm.avgSecondsPerQuestion.toStringAsFixed(1)} s/question',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF3352D6),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD6E1FF)),
            ),
            child: Text(
              vm.timeInsight,
              style: const TextStyle(fontSize: 12, color: Color(0xFF49608F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskBehaviourCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Risk Behaviour Analytics',
      subtitle: 'Attempt quality based on correct, wrong, and skipped answers',
      child: Column(
        children: [
          SizedBox(height: 150, child: _BarSparkChart(values: vm.riskBars)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              final cardWidth = compact
                  ? (constraints.maxWidth - 8) / 2
                  : (constraints.maxWidth - 16) / 3;

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _riskStatCard(
                      label: vm.hasNegativeMarking
                          ? 'Neg. Marks Lost'
                          : 'Marks Lost',
                      value:
                          '${vm.hasNegativeMarking ? '-' : ''}${_formatDashboardMetric(vm.marksLost)}',
                      subtitle: vm.hasNegativeMarking
                          ? 'from wrong answers'
                          : 'potential score from wrong answers',
                      tone: _RiskTone.red,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _riskStatCard(
                      label: 'Risk Accuracy',
                      value: '${vm.riskAccuracy.toStringAsFixed(0)}%',
                      subtitle: 'on attempted questions',
                      tone: _RiskTone.orange,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _riskStatCard(
                      label: 'Safe Attempts',
                      value: '${vm.safeAttempts.toStringAsFixed(0)}%',
                      subtitle: 'precision zone',
                      tone: _RiskTone.green,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _competitionComparisonCard(_DashboardVm vm) {
    final colorScheme = Theme.of(context).colorScheme;
    final competitionFuture = _competitionFutureFor(vm);
    return _dashboardSection(
      title: 'Competition Comparison',
      subtitle:
          'Your exam-level standing against current live leaderboard stats',
      child: FutureBuilder<_CompetitionVm>(
        future: competitionFuture,
        builder: (context, competitionSnap) {
          if (competitionSnap.connectionState == ConnectionState.waiting &&
              !competitionSnap.hasData) {
            return const _DashboardSkeletonCard(height: 180);
          }

          final competition = competitionSnap.data;
          if (competition == null) {
            return Text(
              'Competition data is not available right now.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            );
          }

          return Column(
            children: [
              ...competition.comparisonRows.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _comparisonRow(row),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  competition.rankGapText,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _comparisonRow(_ComparisonRow row) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Text(
              row.totalLabel,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _compareLine('You', row.you, const Color(0xFF4B72F1)),
        const SizedBox(height: 6),
        _compareLine('Average', row.average, const Color(0xFFF2A126)),
        const SizedBox(height: 6),
        _compareLine('Topper', row.topper, const Color(0xFF24B26A)),
      ],
    );
  }

  Widget _compareLine(String label, double value, Color color) {
    final colorScheme = Theme.of(context).colorScheme;
    final safeValue = value.clamp(0.0, 100.0);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: safeValue / 100,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            safeValue.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _consistencyRadarCard(_DashboardVm vm) {
    final colorScheme = Theme.of(context).colorScheme;
    return _dashboardSection(
      title: 'Consistency Radar',
      subtitle: 'Multi-dimension performance snapshot',
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: _Radar(
              items: [
                _RadarPoint('Accuracy Stability', vm.accuracyStability),
                _RadarPoint('Score Balance', vm.scoreBalance),
                _RadarPoint('Test Frequency', vm.testFrequency),
                _RadarPoint('Time Discipline', vm.timeMgmt),
                _RadarPoint('Attempt Pace', vm.speed),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFF4ECFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD9C7FF)),
            ),
            child: Column(
              children: [
                Text(
                  vm.consistencyLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B46C1),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your routine stays steadier when you keep a fixed test rhythm.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationsCard(_DashboardVm vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F317B), Color(0xFF31479F)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1F317B),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Focus Recommendations',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Personalized from ${vm.testsTaken} completed tests',
            style: const TextStyle(color: Color(0xFFCDD6FF), fontSize: 11),
          ),
          const SizedBox(height: 14),
          ...vm.recommendations.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: const TextStyle(
                            color: Color(0xFFD2DAFF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Total Gain Potential  +${vm.gainPotential.round()} Marks',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF73F49A),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if ((selectedExamId ?? '').isNotEmpty) {
                  await UserExamPreferenceService.savePreferredExamId(
                    selectedExamId!,
                  );
                }
                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MainNavigation(initialIndex: 1),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F317B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(
                'Start New Mock Test',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSection({
    required String title,
    required Widget child,
    String? subtitle,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _segmentedPill<T>({
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
    bool expand = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: options.entries.map((entry) {
          final selected = entry.key == value;
          final segment = GestureDetector(
            onTap: () => onChanged(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                entry.value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
          if (!expand) return segment;
          return Expanded(child: segment);
        }).toList(),
      ),
    );
  }

  Widget _miniSurface({required String title, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
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

  Widget _riskStatCard({
    required String label,
    required String value,
    required String subtitle,
    required _RiskTone tone,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = switch (tone) {
      _RiskTone.red => (
        bg: const Color(0xFFFFF0EF),
        border: const Color(0xFFFFD8D4),
        text: const Color(0xFFDC4C3E),
      ),
      _RiskTone.orange => (
        bg: const Color(0xFFFFF7EB),
        border: const Color(0xFFF7DEB2),
        text: const Color(0xFFA96A00),
      ),
      _RiskTone.green => (
        bg: const Color(0xFFF0FFF3),
        border: const Color(0xFFC7EFCF),
        text: const Color(0xFF149750),
      ),
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 138),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: style.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  double _subjectMetricValue(
    _SubjectMetric subject,
    _SubjectViewMode subjectViewMode,
  ) {
    switch (subjectViewMode) {
      case _SubjectViewMode.score:
        return subject.score;
      case _SubjectViewMode.accuracy:
        return subject.accuracy;
      case _SubjectViewMode.time:
        return subject.avgSeconds;
    }
  }

  double _subjectMaxValue(
    List<_SubjectMetric> subjects,
    _SubjectViewMode subjectViewMode,
  ) {
    if (subjects.isEmpty) return 1;
    var maxValue = 0.0;
    for (final subject in subjects.take(4)) {
      maxValue = math.max(
        maxValue,
        _subjectMetricValue(subject, subjectViewMode),
      );
    }
    return maxValue <= 0 ? 1 : maxValue;
  }

  String _subjectMetricLabel(
    _SubjectMetric subject,
    _SubjectViewMode subjectViewMode,
  ) {
    switch (subjectViewMode) {
      case _SubjectViewMode.score:
        return subject.score.toStringAsFixed(0);
      case _SubjectViewMode.accuracy:
        return '${subject.accuracy.toStringAsFixed(0)}%';
      case _SubjectViewMode.time:
        return '${subject.avgSeconds.toStringAsFixed(0)}s';
    }
  }

  List<Widget> _groupedChapterRows(List<_ChapterMetric> chapters) {
    final colorScheme = Theme.of(context).colorScheme;
    if (chapters.isEmpty) {
      return const [Text('No chapter-level data available yet')];
    }

    final bySubject = <String, List<_ChapterMetric>>{};
    for (final chapter in chapters.take(12)) {
      bySubject
          .putIfAbsent(chapter.subject, () => <_ChapterMetric>[])
          .add(chapter);
    }

    return bySubject.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.key,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value.map((chapter) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: chapter.badgeColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: chapter.badgeColor.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.shortName,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${chapter.proficiency.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: chapter.badgeColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<_TrendPoint> _displayTrendPoints(
    List<_TrendPoint> points,
    _DashboardTrendMode trendMode,
  ) {
    if (trendMode == _DashboardTrendMode.avg) return points;

    final out = <_TrendPoint>[];
    var currentMax = 0.0;
    for (final point in points) {
      currentMax = math.max(currentMax, point.score);
      out.add(
        _TrendPoint(
          label: point.label,
          score: currentMax,
          date: point.date,
          extra: point.extra,
        ),
      );
    }
    return out;
  }

  Future<_DashboardVm> _loadDashboardVm(
    String userId,
    String examId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final attemptSignature = _dashboardAttemptSignature(attempts);
    final cachedVm = await _loadCachedDashboardVm(
      userId: userId,
      examId: examId,
      attemptSignature: attemptSignature,
    );
    if (cachedVm != null) {
      return cachedVm;
    }

    final resultMap = await ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: userId,
      examId: examId,
    );
    final asyncDeps = await Future.wait<dynamic>([
      FirebaseFirestore.instance.collection('exams').doc(examId).get(),
      _loadQuestionDetails(attempts, resultMap),
      _loadTestConfigs(attempts),
    ]);
    final examDoc = asyncDeps[0] as DocumentSnapshot<Map<String, dynamic>>;
    final examName = (examDoc.data()?['name'] ?? 'Selected Exam').toString();
    final detail = asyncDeps[1] as _QuestionDetailBundle;
    final testConfigs = asyncDeps[2] as Map<String, Map<String, dynamic>>;

    final trendPoints = <_TrendPoint>[];
    final riskBars = <double>[];
    final timeScoreTrend = <double>[];

    double totalScore = 0;
    double totalPercentile = 0;
    double maxScore = 0;
    int bestRank = 0;
    int totalMinutes = 0;
    int totalQuestions = 0;
    int totalCorrect = 0;
    int totalIncorrect = 0;
    int totalSkipped = 0;
    double totalMarksLost = 0;
    var hasNegativeMarking = false;
    double totalSecondsPerQuestion = 0;
    int secondsPerQuestionCount = 0;
    DateTime lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);

    for (int i = 0; i < attempts.length; i++) {
      final attempt = attempts[i].data();
      final result = resultMap[attempts[i].id] ?? const <String, dynamic>{};
      final date =
          _toDate(attempt['submittedAt']) ??
          _toDate(attempt['startedAt']) ??
          DateTime.now();
      if (date.isAfter(lastUpdated)) {
        lastUpdated = date;
      }

      final score = _scorePct(attempt, result);
      final percentile = (_toDouble(result['percentile']) ?? score).clamp(
        0.0,
        100.0,
      );
      final rank = _toInt(result['rank']) ?? 0;
      final normalizedCounts = ResultDataService.normalizeCounts(
        attempt: attempt,
        result: result,
      );
      final correct = normalizedCounts['correct'] ?? 0;
      final incorrect = normalizedCounts['incorrect'] ?? 0;
      final unanswered = normalizedCounts['unanswered'] ?? 0;
      final testConfig =
          testConfigs['$examId|${(attempt['testId'] ?? '').toString()}'];
      final negativeMarkingEnabled =
          (testConfig?['negativeMarkingEnabled'] == true) ||
          ((_toDouble(testConfig?['negativeMarks']) ?? 0) > 0);
      final penaltyPerWrong = _toDouble(testConfig?['negativeMarks']) ?? 0.0;
      final marksPerQuestion =
          _toDouble(testConfig?['marksPerQuestion']) ??
          _toDouble(testConfig?['positiveMarks']) ??
          0.0;
      if (negativeMarkingEnabled) {
        hasNegativeMarking = true;
      }
      totalMarksLost +=
          incorrect *
          (negativeMarkingEnabled ? penaltyPerWrong : marksPerQuestion);
      final questionCount = (correct + incorrect + unanswered) > 0
          ? (correct + incorrect + unanswered)
          : detail.totalQuestionsForAttempt(attempts[i].id);

      final secondsPerQuestion = _secondsPerQuestion(
        attempt,
        result,
        questionCount,
      );
      if (secondsPerQuestion != null) {
        totalSecondsPerQuestion += secondsPerQuestion;
        secondsPerQuestionCount++;
        timeScoreTrend.add(math.max(0.0, 100 - secondsPerQuestion));
      } else {
        timeScoreTrend.add(score);
      }

      totalScore += score;
      totalPercentile += percentile;
      maxScore = math.max(maxScore, score);
      if (rank > 0 && (bestRank == 0 || rank < bestRank)) {
        bestRank = rank;
      }
      totalQuestions += questionCount;
      totalCorrect += correct;
      totalIncorrect += incorrect;
      totalSkipped += unanswered;
      totalMinutes += _attemptMinutes(attempt);
      riskBars.add(incorrect.toDouble());
      trendPoints.add(
        _TrendPoint(
          label: 'T${i + 1}',
          score: score,
          date: date,
          extra: percentile,
        ),
      );
    }

    final avgScore = totalScore / attempts.length;
    final avgPercentile = totalPercentile / attempts.length;
    final avgSecondsPerQuestion = secondsPerQuestionCount == 0
        ? 0.0
        : totalSecondsPerQuestion / secondsPerQuestionCount;

    final subjects = detail.subjects.values.toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    final chapters = detail.chapters.values.toList()
      ..sort((a, b) => a.proficiency.compareTo(b.proficiency));
    final chapterAttempts = detail.chapterAttempts;

    final consistency = _consistencyScore(trendPoints);
    final scoreBalance = _scoreBalance(subjects);
    final frequency = _testFrequency(attempts);
    final timeMgmt = (100 - (avgSecondsPerQuestion * 0.9)).clamp(0.0, 100.0);
    final speed = (100 - (avgSecondsPerQuestion * 1.1)).clamp(0.0, 100.0);
    final accuracyStability = consistency;
    final readiness =
        ((avgScore * 0.45) +
                (consistency * 0.2) +
                (timeMgmt * 0.15) +
                (_coverageScore(subjects) * 0.2))
            .clamp(0.0, 100.0);

    final firstHalfAvg = _halfAverage(trendPoints, true);
    final secondHalfAvg = _halfAverage(trendPoints, false);
    final delta = secondHalfAvg - firstHalfAvg;
    final riskAccuracy = totalCorrect + totalIncorrect == 0
        ? 0.0
        : (totalCorrect * 100.0 / (totalCorrect + totalIncorrect));
    final safeAttempts = totalQuestions == 0
        ? 0.0
        : (totalCorrect * 100.0 / totalQuestions);
    final focusSubject = subjects.isEmpty ? 'General' : subjects.last.name;

    final timeSlices = _timeSlicesForSubjects(subjects);

    final weakChapters = chapters.take(3).toList();
    final fallbackRecommendations = weakChapters.isEmpty
        ? <_Recommendation>[
            const _Recommendation(
              title: 'Attempt More Tests',
              subtitle: 'Complete a few more papers to unlock recommendations',
              icon: Icons.timeline_rounded,
            ),
          ]
        : weakChapters.map((chapter) {
            return _Recommendation(
              title: chapter.name,
              subtitle:
                  '${chapter.subject} - ${math.max(0, 100 - chapter.proficiency.round())}% focus potential',
              icon: Icons.auto_awesome,
            );
          }).toList();
    final fallbackGainPotential = weakChapters.fold<double>(
      0,
      (sum, chapter) => sum + (100 - chapter.proficiency) * 0.15,
    );
    final dbRecommendations = await _loadDbRecommendations(
      userId: userId,
      examId: examId,
    );
    final recommendationSignature = _buildRecommendationSignature(
      attempts: attempts,
      recommendations: fallbackRecommendations,
      gainPotential: fallbackGainPotential,
    );
    final recommendations =
        dbRecommendations?.recommendations ?? fallbackRecommendations;
    final gainPotential =
        dbRecommendations?.gainPotential ?? fallbackGainPotential;
    final recommendationTestsTaken =
        dbRecommendations?.testsTaken ?? attempts.length;
    if (dbRecommendations == null ||
        dbRecommendations.signature != recommendationSignature) {
      _persistComputedRecommendations(
        userId: userId,
        examId: examId,
        testsTaken: attempts.length,
        gainPotential: fallbackGainPotential,
        recommendations: fallbackRecommendations,
        signature: recommendationSignature,
      );
    }

    final consistencyLabel = consistency >= 75
        ? 'Highly Consistent Performer'
        : consistency >= 55
        ? 'Moderately Consistent Performer'
        : 'Consistency Needs Work';

    final timeInsight = avgSecondsPerQuestion <= 35
        ? 'Your timing is efficient. Keep this pace without compromising accuracy.'
        : avgSecondsPerQuestion <= 75
        ? 'Your pacing is balanced, but a few quicker decisions can boost attempts.'
        : 'You spend too long on harder questions. Try a faster review loop.';

    final vm = _DashboardVm(
      examName: examName,
      lastUpdated: lastUpdated == DateTime.fromMillisecondsSinceEpoch(0)
          ? DateTime.now()
          : lastUpdated,
      testsTaken: recommendationTestsTaken,
      totalQuestions: totalQuestions,
      totalMinutes: totalMinutes,
      avgScore: avgScore,
      maxScore: maxScore,
      avgPercentile: avgPercentile,
      bestRank: bestRank,
      readiness: readiness,
      delta: delta,
      focusSubject: focusSubject,
      totalCorrect: totalCorrect,
      totalIncorrect: totalIncorrect,
      totalSkipped: totalSkipped,
      avgSecondsPerQuestion: avgSecondsPerQuestion,
      trendPoints: trendPoints,
      subjects: subjects,
      chapters: chapters,
      chapterAttempts: chapterAttempts,
      timeSlices: timeSlices,
      timeScoreTrend: timeScoreTrend,
      timeInsight: timeInsight,
      riskBars: riskBars.take(6).toList(),
      marksLost: totalMarksLost,
      hasNegativeMarking: hasNegativeMarking,
      riskAccuracy: riskAccuracy,
      safeAttempts: safeAttempts,
      accuracyStability: accuracyStability,
      scoreBalance: scoreBalance,
      testFrequency: frequency,
      timeMgmt: timeMgmt,
      speed: speed,
      consistencyLabel: consistencyLabel,
      recommendations: recommendations,
      gainPotential: gainPotential,
    );
    _persistDashboardSummary(
      userId: userId,
      examId: examId,
      attemptSignature: attemptSignature,
      vm: vm,
    );
    return vm;
  }

  Future<_DashboardVm> _emptyDashboardVm(String examId) async {
    try {
      final examDoc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .get();
      final examName = (examDoc.data()?['name'] ?? 'Selected Exam').toString();
      return _DashboardVm.empty(examName: examName);
    } catch (_) {
      return _DashboardVm.empty();
    }
  }

  String _dashboardAttemptSignature(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) {
    return attempts
        .map((doc) {
          final data = doc.data();
          final stamp =
              (_toDate(data['submittedAt']) ?? _toDate(data['startedAt']))
                  ?.millisecondsSinceEpoch ??
              0;
          return '${doc.id}:$stamp:${(data['status'] ?? '').toString()}';
        })
        .join('|');
  }

  Future<_DashboardVm?> _loadCachedDashboardVm({
    required String userId,
    required String examId,
    required String attemptSignature,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('examAnalytics')
          .doc(examId)
          .get();
      final data = doc.data();
      if (data == null) return null;
      if ((data['attemptSignature'] ?? '').toString() != attemptSignature) {
        return null;
      }
      return _dashboardVmFromSummary(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistDashboardSummary({
    required String userId,
    required String examId,
    required String attemptSignature,
    required _DashboardVm vm,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('examAnalytics')
          .doc(examId)
          .set({
            'schemaVersion': 1,
            'attemptSignature': attemptSignature,
            'summary': _dashboardVmToSummary(vm),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Keep analytics resilient if summary persistence fails.
    }
  }

  _DashboardVm? _dashboardVmFromSummary(Map<String, dynamic> data) {
    final summary = data['summary'];
    if (summary is! Map) return null;
    final map = Map<String, dynamic>.from(
      summary.map((key, value) => MapEntry(key.toString(), value)),
    );

    final trendPoints = _mapList(
      map['trendPoints'],
    ).map(_trendPointFromMap).whereType<_TrendPoint>().toList(growable: false);
    final subjects = _mapList(map['subjects'])
        .map(_subjectMetricFromMap)
        .whereType<_SubjectMetric>()
        .toList(growable: false);
    final chapters = _mapList(map['chapters'])
        .map(_chapterMetricFromMap)
        .whereType<_ChapterMetric>()
        .toList(growable: false);
    final chapterAttempts = _mapList(map['chapterAttempts'])
        .map(_chapterAttemptMetricFromMap)
        .whereType<_ChapterAttemptMetric>()
        .toList(growable: false);
    final timeSlices = _mapList(
      map['timeSlices'],
    ).map(_timeSliceFromMap).whereType<_TimeSlice>().toList(growable: false);
    final recommendations = _mapList(map['recommendations'])
        .map(_recommendationFromMap)
        .whereType<_Recommendation>()
        .toList(growable: false);

    final examName = (map['examName'] ?? '').toString().trim();
    if (examName.isEmpty) return null;

    return _DashboardVm(
      examName: examName,
      lastUpdated:
          _toDate(map['lastUpdated']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      testsTaken: _toInt(map['testsTaken']) ?? 0,
      totalQuestions: _toInt(map['totalQuestions']) ?? 0,
      totalMinutes: _toInt(map['totalMinutes']) ?? 0,
      avgScore: _toDouble(map['avgScore']) ?? 0,
      maxScore: _toDouble(map['maxScore']) ?? 0,
      avgPercentile: _toDouble(map['avgPercentile']) ?? 0,
      bestRank: _toInt(map['bestRank']) ?? 0,
      readiness: _toDouble(map['readiness']) ?? 0,
      delta: _toDouble(map['delta']) ?? 0,
      focusSubject: (map['focusSubject'] ?? 'General').toString(),
      totalCorrect: _toInt(map['totalCorrect']) ?? 0,
      totalIncorrect: _toInt(map['totalIncorrect']) ?? 0,
      totalSkipped: _toInt(map['totalSkipped']) ?? 0,
      avgSecondsPerQuestion: _toDouble(map['avgSecondsPerQuestion']) ?? 0,
      trendPoints: trendPoints,
      subjects: subjects,
      chapters: chapters,
      chapterAttempts: chapterAttempts,
      timeSlices: timeSlices,
      timeScoreTrend: _doubleList(map['timeScoreTrend']),
      timeInsight: (map['timeInsight'] ?? '').toString(),
      riskBars: _doubleList(map['riskBars']),
      marksLost: _toDouble(map['marksLost']) ?? 0,
      hasNegativeMarking: map['hasNegativeMarking'] == true,
      riskAccuracy: _toDouble(map['riskAccuracy']) ?? 0,
      safeAttempts: _toDouble(map['safeAttempts']) ?? 0,
      accuracyStability: _toDouble(map['accuracyStability']) ?? 0,
      scoreBalance: _toDouble(map['scoreBalance']) ?? 0,
      testFrequency: _toDouble(map['testFrequency']) ?? 0,
      timeMgmt: _toDouble(map['timeMgmt']) ?? 0,
      speed: _toDouble(map['speed']) ?? 0,
      consistencyLabel: (map['consistencyLabel'] ?? '').toString(),
      recommendations: recommendations,
      gainPotential: _toDouble(map['gainPotential']) ?? 0,
    );
  }

  Map<String, dynamic> _dashboardVmToSummary(_DashboardVm vm) {
    return {
      'examName': vm.examName,
      'lastUpdated': Timestamp.fromDate(vm.lastUpdated),
      'testsTaken': vm.testsTaken,
      'totalQuestions': vm.totalQuestions,
      'totalMinutes': vm.totalMinutes,
      'avgScore': vm.avgScore,
      'maxScore': vm.maxScore,
      'avgPercentile': vm.avgPercentile,
      'bestRank': vm.bestRank,
      'readiness': vm.readiness,
      'delta': vm.delta,
      'focusSubject': vm.focusSubject,
      'totalCorrect': vm.totalCorrect,
      'totalIncorrect': vm.totalIncorrect,
      'totalSkipped': vm.totalSkipped,
      'avgSecondsPerQuestion': vm.avgSecondsPerQuestion,
      'trendPoints': vm.trendPoints.map(_trendPointToMap).toList(),
      'subjects': vm.subjects.map(_subjectMetricToMap).toList(),
      'chapters': vm.chapters.map(_chapterMetricToMap).toList(),
      'chapterAttempts': vm.chapterAttempts
          .map(_chapterAttemptMetricToMap)
          .toList(),
      'timeSlices': vm.timeSlices.map(_timeSliceToMap).toList(),
      'timeScoreTrend': vm.timeScoreTrend,
      'timeInsight': vm.timeInsight,
      'riskBars': vm.riskBars,
      'marksLost': vm.marksLost,
      'hasNegativeMarking': vm.hasNegativeMarking,
      'riskAccuracy': vm.riskAccuracy,
      'safeAttempts': vm.safeAttempts,
      'accuracyStability': vm.accuracyStability,
      'scoreBalance': vm.scoreBalance,
      'testFrequency': vm.testFrequency,
      'timeMgmt': vm.timeMgmt,
      'speed': vm.speed,
      'consistencyLabel': vm.consistencyLabel,
      'recommendations': vm.recommendations.map(_recommendationToMap).toList(),
      'gainPotential': vm.gainPotential,
    };
  }

  List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  List<double> _doubleList(dynamic raw) {
    if (raw is! List) return const <double>[];
    return raw.map((item) => _toDouble(item) ?? 0).toList(growable: false);
  }

  Map<String, dynamic> _trendPointToMap(_TrendPoint point) => {
    'label': point.label,
    'score': point.score,
    'date': Timestamp.fromDate(point.date),
    'extra': point.extra,
  };

  _TrendPoint? _trendPointFromMap(Map<String, dynamic> map) {
    final label = (map['label'] ?? '').toString();
    final date = _toDate(map['date']);
    if (label.isEmpty || date == null) return null;
    return _TrendPoint(
      label: label,
      score: _toDouble(map['score']) ?? 0,
      date: date,
      extra: _toDouble(map['extra']) ?? 0,
    );
  }

  Map<String, dynamic> _subjectMetricToMap(_SubjectMetric metric) => {
    'name': metric.name,
    'total': metric.total,
    'attempted': metric.attempted,
    'correct': metric.correct,
    'totalSeconds': metric.totalSeconds,
  };

  _SubjectMetric? _subjectMetricFromMap(Map<String, dynamic> map) {
    final name = (map['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final metric = _SubjectMetric(name);
    metric.total = _toInt(map['total']) ?? 0;
    metric.attempted = _toInt(map['attempted']) ?? 0;
    metric.correct = _toInt(map['correct']) ?? 0;
    metric.totalSeconds = _toDouble(map['totalSeconds']) ?? 0;
    return metric;
  }

  Map<String, dynamic> _chapterMetricToMap(_ChapterMetric metric) => {
    'name': metric.name,
    'subject': metric.subject,
    'total': metric.total,
    'attempted': metric.attempted,
    'correct': metric.correct,
  };

  _ChapterMetric? _chapterMetricFromMap(Map<String, dynamic> map) {
    final name = (map['name'] ?? '').toString().trim();
    final subject = (map['subject'] ?? '').toString().trim();
    if (name.isEmpty || subject.isEmpty) return null;
    final metric = _ChapterMetric(name: name, subject: subject);
    metric.total = _toInt(map['total']) ?? 0;
    metric.attempted = _toInt(map['attempted']) ?? 0;
    metric.correct = _toInt(map['correct']) ?? 0;
    return metric;
  }

  Map<String, dynamic> _chapterAttemptMetricToMap(
    _ChapterAttemptMetric metric,
  ) => {
    'label': metric.label,
    'date': Timestamp.fromDate(metric.date),
    'subject': metric.subject,
    'chapter': metric.chapter,
    'accuracy': metric.accuracy,
    'avgMinutesPerQuestion': metric.avgMinutesPerQuestion,
    'totalQuestions': metric.totalQuestions,
    'attempted': metric.attempted,
    'correct': metric.correct,
    'skipped': metric.skipped,
  };

  _ChapterAttemptMetric? _chapterAttemptMetricFromMap(
    Map<String, dynamic> map,
  ) {
    final label = (map['label'] ?? '').toString().trim();
    final subject = (map['subject'] ?? '').toString().trim();
    final chapter = (map['chapter'] ?? '').toString().trim();
    final date = _toDate(map['date']);
    if (label.isEmpty || subject.isEmpty || chapter.isEmpty || date == null) {
      return null;
    }
    return _ChapterAttemptMetric(
      label: label,
      date: date,
      subject: subject,
      chapter: chapter,
      accuracy: _toDouble(map['accuracy']) ?? 0,
      avgMinutesPerQuestion: _toDouble(map['avgMinutesPerQuestion']) ?? 0,
      totalQuestions: _toInt(map['totalQuestions']) ?? 0,
      attempted: _toInt(map['attempted']) ?? 0,
      correct: _toInt(map['correct']) ?? 0,
      skipped: _toInt(map['skipped']) ?? 0,
    );
  }

  Map<String, dynamic> _timeSliceToMap(_TimeSlice slice) => {
    'label': slice.label,
    'value': slice.value,
    'color': slice.color.value,
  };

  _TimeSlice? _timeSliceFromMap(Map<String, dynamic> map) {
    final label = (map['label'] ?? '').toString().trim();
    if (label.isEmpty) return null;
    return _TimeSlice(
      label: label,
      value: _toDouble(map['value']) ?? 0,
      color: Color(_toInt(map['color']) ?? 0xFF9AA5B1),
    );
  }

  Map<String, dynamic> _recommendationToMap(_Recommendation item) => {
    'title': item.title,
    'subtitle': item.subtitle,
    'icon': _recommendationIconName(item.icon),
  };

  _Recommendation? _recommendationFromMap(Map<String, dynamic> map) {
    final title = (map['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    return _Recommendation(
      title: title,
      subtitle: (map['subtitle'] ?? '').toString(),
      icon: _recommendationIcon((map['icon'] ?? '').toString()),
    );
  }

  Future<_DbRecommendationPayload?> _loadDbRecommendations({
    required String userId,
    required String examId,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('examRecommendations')
          .doc(examId)
          .get();
      final data = doc.data();
      if (data == null) return null;

      final rawItems = data['recommendations'];
      final items = <_Recommendation>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          final title = (map['title'] ?? '').toString().trim();
          if (title.isEmpty) continue;
          final subject = (map['subject'] ?? '').toString().trim();
          final subtitleRaw = (map['subtitle'] ?? '').toString().trim();
          final focusPotential = _toDouble(map['focusPotential']);
          final subtitle = subtitleRaw.isNotEmpty
              ? subtitleRaw
              : subject.isNotEmpty && focusPotential != null
              ? '$subject - ${focusPotential.round()}% focus potential'
              : subject;
          items.add(
            _Recommendation(
              title: title,
              subtitle: subtitle,
              icon: _recommendationIcon((map['icon'] ?? '').toString()),
            ),
          );
        }
      }

      if (items.isEmpty) return null;
      return _DbRecommendationPayload(
        testsTaken: _toInt(data['testsTaken']),
        gainPotential: _toDouble(data['gainPotential']),
        recommendations: items,
        signature: (data['signature'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistComputedRecommendations({
    required String userId,
    required String examId,
    required int testsTaken,
    required double gainPotential,
    required List<_Recommendation> recommendations,
    required String signature,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('examRecommendations')
          .doc(examId)
          .set({
            'testsTaken': testsTaken,
            'gainPotential': gainPotential,
            'recommendations': recommendations
                .map(
                  (item) => {
                    'title': item.title,
                    'subtitle': item.subtitle,
                    'icon': _recommendationIconName(item.icon),
                  },
                )
                .toList(),
            'signature': signature,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Keep analytics resilient if recommendation persistence fails.
    }
  }

  String _buildRecommendationSignature({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    required List<_Recommendation> recommendations,
    required double gainPotential,
  }) {
    final attemptStamp = attempts
        .map((doc) {
          final data = doc.data();
          final stamp =
              (_toDate(data['submittedAt']) ?? _toDate(data['startedAt']))
                  ?.millisecondsSinceEpoch ??
              0;
          return '${doc.id}:$stamp';
        })
        .join('|');
    final recommendationStamp = recommendations
        .map((item) => '${item.title}:${item.subtitle}')
        .join('|');
    return '$attemptStamp::$recommendationStamp::${gainPotential.toStringAsFixed(2)}';
  }

  IconData _recommendationIcon(String rawIcon) {
    switch (rawIcon.trim().toLowerCase()) {
      case 'timeline':
      case 'timeline_rounded':
        return Icons.timeline_rounded;
      case 'book':
      case 'menu_book':
        return Icons.menu_book_rounded;
      case 'bolt':
      case 'flash':
        return Icons.bolt_rounded;
      case 'science':
        return Icons.science_rounded;
      case 'auto_awesome':
      case 'sparkles':
      default:
        return Icons.auto_awesome;
    }
  }

  String _recommendationIconName(IconData icon) {
    if (icon == Icons.timeline_rounded) return 'timeline_rounded';
    if (icon == Icons.menu_book_rounded) return 'menu_book_rounded';
    if (icon == Icons.bolt_rounded) return 'bolt';
    if (icon == Icons.science_rounded) return 'science';
    if (icon == Icons.auto_graph_rounded) return 'auto_graph';
    if (icon == Icons.biotech_rounded) return 'biotech';
    return 'auto_awesome';
  }

  Future<_QuestionDetailBundle> _loadQuestionDetails(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> resultMap,
  ) async {
    final subjects = <String, _SubjectMetric>{};
    final chapters = <String, _ChapterMetric>{};
    final totalsByAttempt = <String, int>{};
    final chapterAttempts = <_ChapterAttemptMetric>[];
    final questionLoads =
        <String, Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>{};
    final sectionNameLoads = <String, Future<Map<String, String>>>{};

    for (final attemptDoc in attempts) {
      final attempt = attemptDoc.data();
      final examId = (attempt['examId'] ?? '').toString();
      final testId = (attempt['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;

      final cacheKey = '$examId|$testId';
      final embeddedQuestions = _readEmbeddedQuestions(
        resultMap[attemptDoc.id]?['question'] ?? attempt['question'],
      );
      if (embeddedQuestions.isEmpty) {
        questionLoads.putIfAbsent(
          cacheKey,
          () => ExamMetadataCacheService.getQuestions(examId, testId),
        );
      }
      sectionNameLoads.putIfAbsent(
        cacheKey,
        () => _loadSectionNames(examId, testId),
      );
    }

    await Future.wait<dynamic>([
      ...questionLoads.values,
      ...sectionNameLoads.values,
    ]);

    for (int attemptIndex = 0; attemptIndex < attempts.length; attemptIndex++) {
      final attemptDoc = attempts[attemptIndex];
      final attempt = attemptDoc.data();
      final examId = (attempt['examId'] ?? '').toString();
      final testId = (attempt['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;

      final cacheKey = '$examId|$testId';
      final embeddedQuestions = _readEmbeddedQuestions(
        resultMap[attemptDoc.id]?['question'] ?? attempt['question'],
      );
      List<QueryDocumentSnapshot<Map<String, dynamic>>> firestoreQuestions =
          const [];
      if (embeddedQuestions.isEmpty) {
        firestoreQuestions = await questionLoads[cacheKey] ?? const [];
      }

      final sectionNames =
          await sectionNameLoads[cacheKey] ?? const <String, String>{};
      final totalQuestions = embeddedQuestions.isNotEmpty
          ? embeddedQuestions.length
          : firestoreQuestions.length;
      totalsByAttempt[attemptDoc.id] = totalQuestions;
      final answers = _answersMap(
        resultMap[attemptDoc.id]?['answers'] ?? attempt['answers'],
      );
      final perQuestionSeconds =
          _secondsPerQuestion(
            attempt,
            resultMap[attemptDoc.id] ?? const <String, dynamic>{},
            totalQuestions,
          ) ??
          0.0;
      final attemptChapterMetrics = <String, _ChapterMetric>{};
      final attemptDate =
          _toDate(attempt['submittedAt']) ??
          _toDate(attempt['startedAt']) ??
          DateTime.now();
      final label = 'T${attemptIndex + 1}';

      if (embeddedQuestions.isNotEmpty) {
        for (final question in embeddedQuestions) {
          final questionId = (question['__id'] ?? question['id'] ?? '')
              .toString();
          final subjectName = _subjectName(question, sectionNames);
          final chapterName = _chapterName(question, subjectName);
          final selected = _normalizeAnswerValue(answers[questionId] ?? '');
          final correct = _optionLetter(question['correctOption']);
          final isAttempted = selected.isNotEmpty;
          final isCorrect = isAttempted && selected == correct;

          final subjectMetric = subjects.putIfAbsent(
            subjectName,
            () => _SubjectMetric(subjectName),
          );
          subjectMetric.total++;
          if (isAttempted) subjectMetric.attempted++;
          if (isCorrect) subjectMetric.correct++;
          subjectMetric.totalSeconds += perQuestionSeconds;

          final chapterKey = '$subjectName|$chapterName';
          final chapterMetric = chapters.putIfAbsent(
            chapterKey,
            () => _ChapterMetric(name: chapterName, subject: subjectName),
          );
          chapterMetric.total++;
          if (isAttempted) chapterMetric.attempted++;
          if (isCorrect) chapterMetric.correct++;

          final attemptChapterMetric = attemptChapterMetrics.putIfAbsent(
            chapterKey,
            () => _ChapterMetric(name: chapterName, subject: subjectName),
          );
          attemptChapterMetric.total++;
          if (isAttempted) attemptChapterMetric.attempted++;
          if (isCorrect) attemptChapterMetric.correct++;
        }
      } else {
        for (final qDoc in firestoreQuestions) {
          final question = qDoc.data();
          final subjectName = _subjectName(question, sectionNames);
          final chapterName = _chapterName(question, subjectName);
          final selected = _normalizeAnswerValue(answers[qDoc.id] ?? '');
          final correct = _optionLetter(question['correctOption']);
          final isAttempted = selected.isNotEmpty;
          final isCorrect = isAttempted && selected == correct;

          final subjectMetric = subjects.putIfAbsent(
            subjectName,
            () => _SubjectMetric(subjectName),
          );
          subjectMetric.total++;
          if (isAttempted) subjectMetric.attempted++;
          if (isCorrect) subjectMetric.correct++;
          subjectMetric.totalSeconds += perQuestionSeconds;

          final chapterKey = '$subjectName|$chapterName';
          final chapterMetric = chapters.putIfAbsent(
            chapterKey,
            () => _ChapterMetric(name: chapterName, subject: subjectName),
          );
          chapterMetric.total++;
          if (isAttempted) chapterMetric.attempted++;
          if (isCorrect) chapterMetric.correct++;

          final attemptChapterMetric = attemptChapterMetrics.putIfAbsent(
            chapterKey,
            () => _ChapterMetric(name: chapterName, subject: subjectName),
          );
          attemptChapterMetric.total++;
          if (isAttempted) attemptChapterMetric.attempted++;
          if (isCorrect) attemptChapterMetric.correct++;
        }
      }

      for (final metric in attemptChapterMetrics.values) {
        chapterAttempts.add(
          _ChapterAttemptMetric(
            label: label,
            date: attemptDate,
            subject: metric.subject,
            chapter: metric.name,
            accuracy: metric.accuracy,
            avgMinutesPerQuestion: perQuestionSeconds / 60.0,
            totalQuestions: metric.total,
            attempted: metric.attempted,
            correct: metric.correct,
            skipped: math.max(0, metric.total - metric.attempted),
          ),
        );
      }
    }

    return _QuestionDetailBundle(
      subjects: subjects,
      chapters: chapters,
      totalsByAttempt: totalsByAttempt,
      chapterAttempts: chapterAttempts,
    );
  }

  List<Map<String, dynamic>> _readEmbeddedQuestions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, String>> _loadSectionNames(
    String examId,
    String testId,
  ) async {
    return ExamMetadataCacheService.getSectionNames(examId, testId);
  }

  Future<List<_LeaderboardRow>> _loadExamLeaderboardRows(String examId) async {
    final summaryPage = await _loadLeaderboardSummaryPage(
      examId: examId,
      pageSize: 120,
      startAfter: null,
    );
    if (summaryPage != null && summaryPage.rows.isNotEmpty) {
      return summaryPage.rows;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: examId)
          .orderBy('createdAt', descending: true)
          .limit(120)
          .get();
      final entries = _aggregateLeaderboard(snap.docs);
      await _loadUserDisplayNames(entries.map((entry) => entry.userId));
      return _rowsFromEntries(entries);
    } catch (_) {
      return const <_LeaderboardRow>[];
    }
  }

  Future<_CompetitionVm> _loadCompetitionVm({
    required String userId,
    required String examId,
    required double avgScore,
    required List<_SubjectMetric> subjects,
  }) async {
    final leaderboardRows = await _leaderboardFutureCache.putIfAbsent(
      examId,
      () => _loadExamLeaderboardRows(examId),
    );
    final avgLeaderboardScore = leaderboardRows.isEmpty
        ? 0.0
        : leaderboardRows
                  .map((row) => row.entry.avgScore)
                  .reduce((a, b) => a + b) /
              leaderboardRows.length;
    final topLeaderboardScore = leaderboardRows.isEmpty
        ? avgScore
        : leaderboardRows.first.entry.avgScore;
    final myLeaderboardRow = leaderboardRows
        .cast<_LeaderboardRow?>()
        .firstWhere((row) => row?.entry.userId == userId, orElse: () => null);

    final comparisonRows = <_ComparisonRow>[
      _ComparisonRow(
        label: 'Overall Score',
        totalLabel: '/ 100',
        you: avgScore,
        average: avgLeaderboardScore,
        topper: topLeaderboardScore.clamp(0.0, 100.0),
      ),
      ...subjects
          .take(4)
          .map(
            (subject) => _ComparisonRow(
              label: subject.name,
              totalLabel: '/ 100',
              you: subject.accuracy,
              average: (subject.accuracy * 0.88).clamp(0.0, 100.0),
              topper: math.min(100.0, subject.accuracy + 12),
            ),
          ),
    ];

    final rankGapText = myLeaderboardRow == null
        ? 'Keep attempting tests to enter the live ranking pool.'
        : myLeaderboardRow.rank <= 3
        ? 'You are already in the top tier for this exam.'
        : 'You are ${myLeaderboardRow.rank - 3} places away from the Top 3.';

    return _CompetitionVm(
      platformAvg: avgLeaderboardScore,
      comparisonRows: comparisonRows,
      rankGapText: rankGapText,
    );
  }

  Future<_CompetitionVm> _competitionFutureFor(_DashboardVm vm) {
    final user = FirebaseAuth.instance.currentUser;
    final examId = selectedExamId;
    if (user == null || examId == null || examId.isEmpty) {
      return Future.value(const _CompetitionVm.empty());
    }
    return _competitionFutureCache.putIfAbsent(
      examId,
      () => _loadCompetitionVm(
        userId: user.uid,
        examId: examId,
        avgScore: vm.avgScore,
        subjects: vm.subjects,
      ),
    );
  }

  Map<String, String> _answersMap(dynamic raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      out[entry.key.toString()] = (entry.value ?? '').toString();
    }
    return out;
  }

  String _optionLetter(dynamic index) {
    switch (index?.toString()) {
      case '0':
        return 'A';
      case '1':
        return 'B';
      case '2':
        return 'C';
      case '3':
        return 'D';
      default:
        return (index ?? '').toString().trim().toUpperCase();
    }
  }

  String _normalizeAnswerValue(dynamic value) {
    final raw = (value ?? '').toString().trim().toUpperCase();
    switch (raw) {
      case '0':
      case 'A':
        return 'A';
      case '1':
      case 'B':
        return 'B';
      case '2':
      case 'C':
        return 'C';
      case '3':
      case 'D':
        return 'D';
      default:
        return raw;
    }
  }

  String _subjectName(
    Map<String, dynamic> question,
    Map<String, String> sectionNames,
  ) {
    final directName =
        (question['subject'] ?? question['sectionName'] ?? question['section'])
            ?.toString()
            .trim();
    if (directName != null && directName.isNotEmpty) {
      return directName;
    }

    final sectionId = question['sectionId']?.toString().trim();
    if (sectionId != null && sectionId.isNotEmpty) {
      final mappedName = sectionNames[sectionId]?.trim();
      if (mappedName != null && mappedName.isNotEmpty) {
        return mappedName;
      }
    }

    return 'General';
  }

  Future<Map<String, Map<String, dynamic>>> _loadTestConfigs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final configs = <String, Map<String, dynamic>>{};
    final lookups = <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
    for (final attemptDoc in attempts) {
      final attempt = attemptDoc.data();
      final examId = (attempt['examId'] ?? '').toString();
      final testId = (attempt['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;
      final key = '$examId|$testId';
      lookups.putIfAbsent(
        key,
        () async =>
            (await ExamMetadataCacheService.getTestDoc(examId, testId)) ??
            FirebaseFirestore.instance
                .collection('exams')
                .doc(examId)
                .collection('tests')
                .doc(testId)
                .get(),
      );
    }

    final entries = await Future.wait(
      lookups.entries.map((entry) async {
        try {
          final snap = await entry.value;
          return MapEntry(entry.key, snap.data() ?? const <String, dynamic>{});
        } catch (_) {
          return MapEntry(entry.key, const <String, dynamic>{});
        }
      }),
    );

    for (final entry in entries) {
      configs[entry.key] = entry.value;
    }
    return configs;
  }

  String _chapterName(Map<String, dynamic> question, String fallbackSubject) {
    return (question['chapter'] ??
            question['chapterName'] ??
            question['topic'] ??
            question['topicName'] ??
            fallbackSubject)
        .toString();
  }

  double _scorePct(Map<String, dynamic> attempt, Map<String, dynamic> result) {
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    final correct = normalizedCounts['correct'] ?? _toInt(result['score']) ?? 0;
    final incorrect = normalizedCounts['incorrect'] ?? 0;
    final unanswered = normalizedCounts['unanswered'] ?? 0;
    final total = (correct + incorrect + unanswered) > 0
        ? (correct + incorrect + unanswered)
        : 20;
    return (correct * 100.0 / total).clamp(0.0, 100.0);
  }

  double? _secondsPerQuestion(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
    int fallbackQuestions,
  ) {
    final mins = _attemptMinutes(attempt);
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    final totalQuestions =
        (normalizedCounts['correct'] ?? 0) +
        (normalizedCounts['incorrect'] ?? 0) +
        (normalizedCounts['unanswered'] ?? 0);
    final effectiveQuestions = totalQuestions > 0
        ? totalQuestions
        : fallbackQuestions;
    if (mins <= 0 || effectiveQuestions <= 0) return null;
    return (mins * 60.0) / effectiveQuestions;
  }

  int _attemptMinutes(Map<String, dynamic> attempt) {
    final timeTaken = _toInt(attempt['timeTaken']);
    if (timeTaken != null) return timeTaken;
    final started = _toDate(attempt['startedAt']);
    final submitted = _toDate(attempt['submittedAt']);
    if (started == null || submitted == null) return 0;
    return submitted.difference(started).inMinutes;
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _formatDashboardMetric(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  double _consistencyScore(List<_TrendPoint> points) {
    if (points.length <= 1) return 50;
    final values = points.map((e) => e.score).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) => math.pow(value - mean, 2))
            .reduce((a, b) => a + b) /
        values.length;
    final deviation = math.sqrt(variance);
    return (100 - deviation * 2.4).clamp(0.0, 100.0);
  }

  double _scoreBalance(List<_SubjectMetric> subjects) {
    if (subjects.isEmpty) return 0;
    final values = subjects.map((e) => e.accuracy).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final spread =
        values.map((value) => (value - mean).abs()).reduce((a, b) => a + b) /
        values.length;
    return (100 - spread * 1.6).clamp(0.0, 100.0);
  }

  double _coverageScore(List<_SubjectMetric> subjects) {
    if (subjects.isEmpty) return 0;
    return subjects.map((subject) => subject.coverage).reduce((a, b) => a + b) /
        subjects.length;
  }

  List<_TimeSlice> _timeSlicesForSubjects(List<_SubjectMetric> subjects) {
    const palette = <Color>[
      Color(0xFF4B72F1),
      Color(0xFF31B56A),
      Color(0xFFF2A126),
      Color(0xFFEB5757),
    ];
    final visibleSubjects = subjects.take(4).toList();
    final totalSeconds = visibleSubjects.fold<double>(
      0.0,
      (runningTotal, subject) => runningTotal + subject.totalSeconds,
    );
    return visibleSubjects.asMap().entries.map((entry) {
      final index = entry.key;
      final subject = entry.value;
      return _TimeSlice(
        label: subject.shortName,
        value: totalSeconds <= 0
            ? 0.0
            : (subject.totalSeconds * 100.0 / totalSeconds),
        color: palette[index % palette.length],
      );
    }).toList();
  }

  double _testFrequency(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) {
    if (attempts.length <= 1) return 45;
    final dates =
        attempts
            .map(
              (doc) =>
                  _toDate(doc.data()['submittedAt']) ??
                  _toDate(doc.data()['startedAt']),
            )
            .whereType<DateTime>()
            .toList()
          ..sort();
    if (dates.length <= 1) return 45;

    var totalGap = 0.0;
    for (int i = 1; i < dates.length; i++) {
      totalGap += dates[i].difference(dates[i - 1]).inDays.abs().toDouble();
    }
    final avgGap = totalGap / (dates.length - 1);
    return (100 - avgGap * 6).clamp(0.0, 100.0);
  }

  double _halfAverage(List<_TrendPoint> points, bool firstHalf) {
    if (points.isEmpty) return 0;
    final mid = points.length ~/ 2;
    final slice = firstHalf
        ? points.sublist(0, math.max(1, mid))
        : points.sublist(mid);
    if (slice.isEmpty) return 0;
    return slice.map((point) => point.score).reduce((a, b) => a + b) /
        slice.length;
  }

  String _relativeTime(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} mins ago';
    if (diff.inDays < 1) return '${diff.inHours} hrs ago';
    return '${diff.inDays} days ago';
  }

  List<_LeaderboardAgg> _aggregateLeaderboard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final byUser = <String, _LeaderboardAgg>{};

    for (final d in docs) {
      final data = d.data();
      final uid = (data['userId'] ?? '').toString();
      if (uid.isEmpty) continue;

      final score = (data['score'] as num?)?.toDouble() ?? 0.0;
      final percentile = _leaderboardPercentile(data, score);

      final agg = byUser.putIfAbsent(uid, () => _LeaderboardAgg(userId: uid));
      agg.testsTaken += 1;
      agg.totalScore += score;
      agg.totalPercentile += percentile;
      if (score > agg.bestScore) agg.bestScore = score;
    }

    final out = byUser.values.toList();
    for (final e in out) {
      final count = e.testsTaken == 0 ? 1 : e.testsTaken;
      e.avgScore = e.totalScore / count;
      e.avgPercentile = e.totalPercentile / count;
    }

    out.sort((a, b) {
      final byAvg = b.avgScore.compareTo(a.avgScore);
      if (byAvg != 0) return byAvg;
      final byBest = b.bestScore.compareTo(a.bestScore);
      if (byBest != 0) return byBest;
      return b.testsTaken.compareTo(a.testsTaken);
    });

    return out;
  }
}

enum _DashboardTrendMode { avg, max }

enum _SubjectViewMode { score, accuracy, time }

enum _RiskTone { red, orange, green }

class _QuestionDetailBundle {
  final Map<String, _SubjectMetric> subjects;
  final Map<String, _ChapterMetric> chapters;
  final Map<String, int> totalsByAttempt;
  final List<_ChapterAttemptMetric> chapterAttempts;

  const _QuestionDetailBundle({
    required this.subjects,
    required this.chapters,
    required this.totalsByAttempt,
    required this.chapterAttempts,
  });

  int totalQuestionsForAttempt(String attemptId) =>
      totalsByAttempt[attemptId] ?? 0;
}

class _LeaderboardAgg {
  final String userId;
  int testsTaken = 0;
  double totalScore = 0;
  double totalPercentile = 0;
  double bestScore = 0;
  double avgScore = 0;
  double avgPercentile = 0;

  _LeaderboardAgg({required this.userId});
}

class _LeaderboardRow {
  final _LeaderboardAgg entry;
  final int rank;
  final String displayName;

  const _LeaderboardRow({
    required this.entry,
    required this.rank,
    required this.displayName,
  });
}

class _DashboardVm {
  final String examName;
  final DateTime lastUpdated;
  final int testsTaken;
  final int totalQuestions;
  final int totalMinutes;
  final double avgScore;
  final double maxScore;
  final double avgPercentile;
  final int bestRank;
  final double readiness;
  final double delta;
  final String focusSubject;
  final int totalCorrect;
  final int totalIncorrect;
  final int totalSkipped;
  final double avgSecondsPerQuestion;
  final List<_TrendPoint> trendPoints;
  final List<_SubjectMetric> subjects;
  final List<_ChapterMetric> chapters;
  final List<_ChapterAttemptMetric> chapterAttempts;
  final List<_TimeSlice> timeSlices;
  final List<double> timeScoreTrend;
  final String timeInsight;
  final List<double> riskBars;
  final double marksLost;
  final bool hasNegativeMarking;
  final double riskAccuracy;
  final double safeAttempts;
  final double accuracyStability;
  final double scoreBalance;
  final double testFrequency;
  final double timeMgmt;
  final double speed;
  final String consistencyLabel;
  final List<_Recommendation> recommendations;
  final double gainPotential;

  double get avgMarksLostPerTest =>
      testsTaken <= 0 ? 0.0 : marksLost / testsTaken;

  bool get needsMoreDataForDeepAnalysis => testsTaken < 3;

  const _DashboardVm({
    required this.examName,
    required this.lastUpdated,
    required this.testsTaken,
    required this.totalQuestions,
    required this.totalMinutes,
    required this.avgScore,
    required this.maxScore,
    required this.avgPercentile,
    required this.bestRank,
    required this.readiness,
    required this.delta,
    required this.focusSubject,
    required this.totalCorrect,
    required this.totalIncorrect,
    required this.totalSkipped,
    required this.avgSecondsPerQuestion,
    required this.trendPoints,
    required this.subjects,
    required this.chapters,
    required this.chapterAttempts,
    required this.timeSlices,
    required this.timeScoreTrend,
    required this.timeInsight,
    required this.riskBars,
    required this.marksLost,
    required this.hasNegativeMarking,
    required this.riskAccuracy,
    required this.safeAttempts,
    required this.accuracyStability,
    required this.scoreBalance,
    required this.testFrequency,
    required this.timeMgmt,
    required this.speed,
    required this.consistencyLabel,
    required this.recommendations,
    required this.gainPotential,
  });

  _DashboardVm.empty({this.examName = 'Selected Exam'})
    : lastUpdated = DateTime.fromMillisecondsSinceEpoch(0),
      testsTaken = 0,
      totalQuestions = 0,
      totalMinutes = 0,
      avgScore = 0,
      maxScore = 0,
      avgPercentile = 0,
      bestRank = 0,
      readiness = 0,
      delta = 0,
      focusSubject = 'General',
      totalCorrect = 0,
      totalIncorrect = 0,
      totalSkipped = 0,
      avgSecondsPerQuestion = 0,
      trendPoints = const <_TrendPoint>[],
      subjects = const <_SubjectMetric>[],
      chapters = const <_ChapterMetric>[],
      chapterAttempts = const <_ChapterAttemptMetric>[],
      timeSlices = const <_TimeSlice>[],
      timeScoreTrend = const <double>[],
      timeInsight = 'Take at least 3 tests to unlock deeper analysis.',
      riskBars = const <double>[0, 0, 0, 0],
      marksLost = 0,
      hasNegativeMarking = false,
      riskAccuracy = 0,
      safeAttempts = 0,
      accuracyStability = 0,
      scoreBalance = 0,
      testFrequency = 0,
      timeMgmt = 0,
      speed = 0,
      consistencyLabel = 'Build your baseline',
      recommendations = const <_Recommendation>[],
      gainPotential = 0;
}

class _CompetitionVm {
  final double platformAvg;
  final List<_ComparisonRow> comparisonRows;
  final String rankGapText;

  const _CompetitionVm({
    required this.platformAvg,
    required this.comparisonRows,
    required this.rankGapText,
  });

  const _CompetitionVm.empty()
    : platformAvg = 0,
      comparisonRows = const <_ComparisonRow>[],
      rankGapText = 'Competition data is not available right now.';
}

class _LeaderboardPage {
  final List<_LeaderboardRow> rows;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;

  const _LeaderboardPage({required this.rows, required this.lastDoc});
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _DashboardSkeletonHero extends StatelessWidget {
  const _DashboardSkeletonHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFF7FAFF), Color(0xFFEAF1FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBlock(width: 110, height: 12),
          SizedBox(height: 14),
          _SkeletonBlock(width: 190, height: 26),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SkeletonBlock(
                  width: double.infinity,
                  height: 90,
                  radius: 18,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _SkeletonBlock(
                  width: double.infinity,
                  height: 90,
                  radius: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardSkeletonCard extends StatelessWidget {
  final double height;

  const _DashboardSkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBlock(width: 150, height: 18),
          SizedBox(height: 10),
          _SkeletonBlock(width: 220, height: 12),
          SizedBox(height: 18),
          Expanded(
            child: _SkeletonBlock(
              width: double.infinity,
              height: double.infinity,
              radius: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPoint {
  final String label;
  final double score;
  final DateTime date;
  final double extra;

  const _TrendPoint({
    required this.label,
    required this.score,
    required this.date,
    required this.extra,
  });
}

class _SubjectMetric {
  final String name;
  int total = 0;
  int attempted = 0;
  int correct = 0;
  double totalSeconds = 0;

  _SubjectMetric(this.name);

  double get accuracy => total == 0 ? 0 : (correct * 100.0 / total);
  double get coverage => total == 0 ? 0 : (attempted * 100.0 / total);
  double get score => accuracy;
  double get avgSeconds => total == 0 ? 0 : (totalSeconds / total);
  String get shortName =>
      name.length <= 10 ? name : '${name.substring(0, 9)}...';
}

class _ChapterMetric {
  final String name;
  final String subject;
  int total = 0;
  int attempted = 0;
  int correct = 0;

  _ChapterMetric({required this.name, required this.subject});

  double get accuracy => total == 0 ? 0 : (correct * 100.0 / total);
  double get proficiency => attempted == 0 ? 0 : (correct * 100.0 / attempted);
  Color get badgeColor {
    if (proficiency >= 75) return const Color(0xFF31B56A);
    if (proficiency >= 50) return const Color(0xFFF2A126);
    return const Color(0xFFEB5757);
  }

  String get shortName =>
      name.length <= 10 ? name : '${name.substring(0, 9)}...';
}

class _ChapterAttemptMetric {
  final String label;
  final DateTime date;
  final String subject;
  final String chapter;
  final double accuracy;
  final double avgMinutesPerQuestion;
  final int totalQuestions;
  final int attempted;
  final int correct;
  final int skipped;

  const _ChapterAttemptMetric({
    required this.label,
    required this.date,
    required this.subject,
    required this.chapter,
    required this.accuracy,
    required this.avgMinutesPerQuestion,
    required this.totalQuestions,
    required this.attempted,
    required this.correct,
    required this.skipped,
  });
}

class _SubjectAttemptMetric {
  final String label;
  final DateTime date;
  final String subject;
  final double score;
  final double accuracy;
  final int attempted;
  final int correct;
  final int total;

  const _SubjectAttemptMetric({
    required this.label,
    required this.date,
    required this.subject,
    required this.score,
    required this.accuracy,
    required this.attempted,
    required this.correct,
    required this.total,
  });
}

class _TimeSlice {
  final String label;
  final double value;
  final Color color;

  const _TimeSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _ComparisonRow {
  final String label;
  final String totalLabel;
  final double you;
  final double average;
  final double topper;

  const _ComparisonRow({
    required this.label,
    required this.totalLabel,
    required this.you,
    required this.average,
    required this.topper,
  });
}

class _Recommendation {
  final String title;
  final String subtitle;
  final IconData icon;

  const _Recommendation({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _DbRecommendationPayload {
  final int? testsTaken;
  final double? gainPotential;
  final List<_Recommendation> recommendations;
  final String signature;

  const _DbRecommendationPayload({
    required this.testsTaken,
    required this.gainPotential,
    required this.recommendations,
    required this.signature,
  });
}

class _ChapterExplorerScreen extends StatefulWidget {
  final _DashboardVm vm;

  const _ChapterExplorerScreen({required this.vm});

  @override
  State<_ChapterExplorerScreen> createState() => _ChapterExplorerScreenState();
}

class _ChapterExplorerScreenState extends State<_ChapterExplorerScreen> {
  String? _selectedSubject;
  String? _selectedChapter;
  int _testRange = 5;

  List<String> get _subjects {
    final names =
        widget.vm.chapterAttempts
            .map((item) => item.subject)
            .where((name) => name.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (names.isEmpty) {
      names.addAll(
        widget.vm.chapters.map((chapter) => chapter.subject).toSet().toList()
          ..sort(),
      );
    }
    return names;
  }

  List<String> get _chaptersForSubject {
    final subject = _selectedSubject;
    if (subject == null) return const [];
    final chapters =
        widget.vm.chapterAttempts
            .where((item) => item.subject == subject)
            .map((item) => item.chapter)
            .toSet()
            .toList()
          ..sort();
    if (chapters.isEmpty) {
      chapters.addAll(
        widget.vm.chapters
            .where((chapter) => chapter.subject == subject)
            .map((chapter) => chapter.name)
            .toSet()
            .toList()
          ..sort(),
      );
    }
    return chapters;
  }

  @override
  void initState() {
    super.initState();
    final weakest = widget.vm.chapters.isNotEmpty
        ? widget.vm.chapters.first
        : null;
    _selectedSubject =
        weakest?.subject ?? (_subjects.isNotEmpty ? _subjects.first : null);
    final initialChapters = _chaptersForSubject;
    _selectedChapter = weakest != null && weakest.subject == _selectedSubject
        ? weakest.name
        : (initialChapters.isNotEmpty ? initialChapters.first : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filteredAttempts = _filteredAttempts();
    final chapterAccuracy = filteredAttempts.isEmpty
        ? 0.0
        : filteredAttempts
                  .map((item) => item.accuracy)
                  .reduce((a, b) => a + b) /
              filteredAttempts.length;
    final avgTime = _weightedAverageChapterTime(filteredAttempts);
    final avgAttempted = filteredAttempts.isEmpty
        ? 0.0
        : filteredAttempts
                  .map((item) => item.attempted.toDouble())
                  .reduce((a, b) => a + b) /
              filteredAttempts.length;
    final avgCorrect = filteredAttempts.isEmpty
        ? 0.0
        : filteredAttempts
                  .map((item) => item.correct.toDouble())
                  .reduce((a, b) => a + b) /
              filteredAttempts.length;
    final avgSkipped = filteredAttempts.isEmpty
        ? 0.0
        : filteredAttempts
                  .map((item) => item.skipped.toDouble())
                  .reduce((a, b) => a + b) /
              filteredAttempts.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).maybePop(),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 34,
                            width: 34,
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Icon(
                              Icons.chevron_left_rounded,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chapter Explorer',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Filter and explore chapter-level trends from recent tests',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _explorerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filter & Explore',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _filterDropdown(
                                  label: 'Subject',
                                  value: _selectedSubject,
                                  items: _subjects,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedSubject = value;
                                      final chapters = _chaptersForSubject;
                                      _selectedChapter =
                                          chapters.contains(_selectedChapter)
                                          ? _selectedChapter
                                          : (chapters.isNotEmpty
                                                ? chapters.first
                                                : null);
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _filterDropdown(
                                  label: 'Chapter',
                                  value: _selectedChapter,
                                  items: _chaptersForSubject,
                                  onChanged: (value) {
                                    setState(() => _selectedChapter = value);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _rangePill(
                                  label: 'Last 5 Tests',
                                  selected: _testRange == 5,
                                  onTap: () => setState(() => _testRange = 5),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _rangePill(
                                  label: 'Last 10 Tests',
                                  selected: _testRange == 10,
                                  onTap: () => setState(() => _testRange = 10),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_selectedSubject ?? 'General'} - ${_selectedChapter ?? 'Overview'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        filteredAttempts.isEmpty
                                            ? 'No matching chapter data yet'
                                            : 'Showing last ${filteredAttempts.length} tests',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${chapterAccuracy.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    Text(
                                      'Avg Accuracy',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _explorerCard(
                      title: 'Chapter Accuracy Trend',
                      child: filteredAttempts.isEmpty
                          ? const _ExplorerEmptyState(
                              message: 'No chapter trend data available',
                            )
                          : _ExplorerLineChart(
                              points: filteredAttempts
                                  .map(
                                    (item) =>
                                        _ChartPoint(item.label, item.accuracy),
                                  )
                                  .toList(),
                              minY: 0,
                              maxY: 100,
                              suffix: '%',
                              lineColor: const Color(0xFF5A63F6),
                            ),
                    ),
                    const SizedBox(height: 12),
                    _explorerCard(
                      title: 'Avg. Time per Question (min)',
                      footer: const Text(
                        'Target: < 2.5 min',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF09E3E),
                        ),
                      ),
                      child: filteredAttempts.isEmpty
                          ? const _ExplorerEmptyState(
                              message: 'No timing data available',
                            )
                          : _ExplorerBarChart(
                              bars: filteredAttempts
                                  .map(
                                    (item) => _ChartPoint(
                                      item.label,
                                      item.avgMinutesPerQuestion,
                                    ),
                                  )
                                  .toList(),
                              maxY: math.max(
                                4.0,
                                filteredAttempts
                                        .map(
                                          (item) => item.avgMinutesPerQuestion,
                                        )
                                        .fold<double>(0.0, math.max) +
                                    0.5,
                              ),
                              barColor: const Color(0xFF7C7AF4),
                            ),
                    ),
                    const SizedBox(height: 12),
                    _explorerCard(
                      title: 'Attempt vs Correct vs Skipped',
                      child: filteredAttempts.isEmpty
                          ? const _ExplorerEmptyState(
                              message: 'No attempt breakdown available',
                            )
                          : _ExplorerGroupedBarChart(
                              series: [
                                _ChartSeries(
                                  label: 'Attempted',
                                  color: const Color(0xFF5B63F7),
                                  points: filteredAttempts
                                      .map(
                                        (item) => _ChartPoint(
                                          item.label,
                                          item.attempted.toDouble(),
                                        ),
                                      )
                                      .toList(),
                                ),
                                _ChartSeries(
                                  label: 'Correct',
                                  color: const Color(0xFF1FBF8F),
                                  points: filteredAttempts
                                      .map(
                                        (item) => _ChartPoint(
                                          item.label,
                                          item.correct.toDouble(),
                                        ),
                                      )
                                      .toList(),
                                ),
                                _ChartSeries(
                                  label: 'Skipped',
                                  color: const Color(0xFFD1D5E3),
                                  points: filteredAttempts
                                      .map(
                                        (item) => _ChartPoint(
                                          item.label,
                                          item.skipped.toDouble(),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _miniInsightCard(
                            label: 'Avg Attempted',
                            value: avgAttempted.toStringAsFixed(1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _miniInsightCard(
                            label: 'Avg Correct',
                            value: avgCorrect.toStringAsFixed(1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _miniInsightCard(
                            label: 'Avg Time',
                            value: '${avgTime.toStringAsFixed(1)}m',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Avg skipped ${avgSkipped.toStringAsFixed(1)} questions',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_ChapterAttemptMetric> _filteredAttempts() {
    final subject = _selectedSubject;
    final chapter = _selectedChapter;
    if (subject == null || chapter == null) return const [];
    final items =
        widget.vm.chapterAttempts
            .where((item) => item.subject == subject && item.chapter == chapter)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (items.length <= _testRange) return items;
    return items.sublist(items.length - _testRange);
  }

  double _weightedAverageChapterTime(List<_ChapterAttemptMetric> items) {
    if (items.isEmpty) return 0.0;
    double totalMinutes = 0.0;
    int totalQuestions = 0;
    for (final item in items) {
      totalMinutes += item.avgMinutesPerQuestion * item.totalQuestions;
      totalQuestions += item.totalQuestions;
    }
    if (totalQuestions <= 0) return 0.0;
    return totalMinutes / totalQuestions;
  }

  Widget _explorerCard({String? title, Widget? footer, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
          if (footer != null) ...[
            const SizedBox(height: 10),
            Center(child: footer),
          ],
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF6A72FF), width: 1.2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value)
                  ? value
                  : (items.isNotEmpty ? items.first : null),
              isExpanded: true,
              hint: const Text('Select'),
              selectedItemBuilder: (context) => items
                  .map(
                    (item) => Align(
                      alignment: Alignment.centerLeft,
                      child: _RollingDropdownLabel(
                        text: item,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              items: items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: _RollingDropdownLabel(
                        text: item,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: items.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _rangePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 34,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF625CF1) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF625CF1) : const Color(0xFFE2E6F3),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF6B7894),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniInsightCard({required String label, required String value}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectExplorerScreen extends StatefulWidget {
  final _DashboardVm vm;

  const _SubjectExplorerScreen({required this.vm});

  @override
  State<_SubjectExplorerScreen> createState() => _SubjectExplorerScreenState();
}

class _SubjectExplorerScreenState extends State<_SubjectExplorerScreen> {
  String? _selectedSubject;
  int _testRange = 5;

  List<String> get _subjects {
    final subjects = widget.vm.subjects.map((subject) => subject.name).toList();
    if (subjects.isNotEmpty) return subjects;
    return widget.vm.chapterAttempts
        .map((item) => item.subject)
        .where((item) => item.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  void initState() {
    super.initState();
    _selectedSubject = _subjects.isNotEmpty ? _subjects.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subject = _selectedSubject;
    final subjectAttempts = _subjectSeries();
    final chapterHeatmap =
        widget.vm.chapters
            .where((chapter) => chapter.subject == subject)
            .toList()
          ..sort((a, b) => b.proficiency.compareTo(a.proficiency));
    final chapterTimeBars = _chapterTimeSeries();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).maybePop(),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 34,
                            width: 34,
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Icon(
                              Icons.chevron_left_rounded,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Subject Explorer',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Subject-wise analytics from your actual exam subjects',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _subjects.map((item) {
                          final selected = item == _selectedSubject;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _selectedSubject = item),
                              borderRadius: BorderRadius.circular(999),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF625CF1)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFF625CF1)
                                        : const Color(0xFFE2E6F3),
                                  ),
                                ),
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF5B6783),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _rangeTogglePill(
                            label: 'Last 5 Tests',
                            selected: _testRange == 5,
                            onTap: () => setState(() => _testRange = 5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _rangeTogglePill(
                            label: 'Last 10 Tests',
                            selected: _testRange == 10,
                            onTap: () => setState(() => _testRange = 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _subjectCard(
                      title:
                          'Score Trend${subject == null ? '' : ' - $subject'}',
                      child: subjectAttempts.isEmpty
                          ? const _ExplorerEmptyState(
                              message: 'No subject trend data available',
                            )
                          : _ExplorerLineChart(
                              points: subjectAttempts
                                  .map(
                                    (item) =>
                                        _ChartPoint(item.label, item.score),
                                  )
                                  .toList(),
                              minY: 0,
                              maxY: 100,
                              suffix: '',
                              lineColor: const Color(0xFF5A63F6),
                            ),
                    ),
                    const SizedBox(height: 12),
                    _subjectCard(
                      title:
                          'Accuracy Trend${subject == null ? '' : ' - $subject'}',
                      child: subjectAttempts.isEmpty
                          ? const _ExplorerEmptyState(
                              message: 'No subject accuracy data available',
                            )
                          : _ExplorerLineChart(
                              points: subjectAttempts
                                  .map(
                                    (item) =>
                                        _ChartPoint(item.label, item.accuracy),
                                  )
                                  .toList(),
                              minY: 0,
                              maxY: 100,
                              suffix: '',
                              lineColor: const Color(0xFF7D8CFF),
                            ),
                    ),
                    const SizedBox(height: 12),
                    _subjectCard(
                      title: 'Chapter Performance Heatmap',
                      child: chapterHeatmap.isEmpty
                          ? const _ExplorerEmptyState(
                              message:
                                  'No chapter data available for this subject',
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  children: [
                                    _HeatmapLegend(
                                      label: 'High (>= 75%)',
                                      color: Color(0xFF16C784),
                                    ),
                                    _HeatmapLegend(
                                      label: 'Med (50-74%)',
                                      color: Color(0xFFF2A126),
                                    ),
                                    _HeatmapLegend(
                                      label: 'Low (< 50%)',
                                      color: Color(0xFFFF5B6B),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: chapterHeatmap.take(8).map((
                                    chapter,
                                  ) {
                                    return _HeatmapChip(chapter: chapter);
                                  }).toList(),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _subjectCard(
                      title: 'Avg. Time per Chapter (min/q)',
                      footer: const Text(
                        'Shorter bars = faster solving. Ideal: <2.5 min/question',
                        style: TextStyle(fontSize: 10),
                      ),
                      child: chapterTimeBars.isEmpty
                          ? const _ExplorerEmptyState(
                              message: 'No chapter timing data available',
                            )
                          : _ExplorerBarChart(
                              bars: chapterTimeBars,
                              maxY: math.max(
                                1.0,
                                chapterTimeBars
                                        .map((item) => item.value)
                                        .fold<double>(0.0, math.max) +
                                    0.5,
                              ),
                              barColor: const Color(0xFF6F74F7),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SubjectAttemptMetric> _subjectSeries() {
    final subject = _selectedSubject;
    if (subject == null) return const [];
    final grouped = <String, _SubjectAttemptAccumulator>{};
    for (final item
        in widget.vm.chapterAttempts
            .where((entry) => entry.subject == subject)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date))) {
      final group = grouped.putIfAbsent(
        item.label,
        () => _SubjectAttemptAccumulator(label: item.label, date: item.date),
      );
      group.correct += item.correct;
      group.attempted += item.attempted;
      group.total += item.attempted + item.skipped;
    }
    final items =
        grouped.values
            .map(
              (entry) => _SubjectAttemptMetric(
                label: entry.label,
                date: entry.date,
                subject: subject,
                score: entry.attempted == 0
                    ? 0.0
                    : (entry.correct * 100.0 / entry.attempted),
                accuracy: entry.total == 0
                    ? 0.0
                    : (entry.correct * 100.0 / entry.total),
                attempted: entry.attempted,
                correct: entry.correct,
                total: entry.total,
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (items.length <= _testRange) return items;
    return items.sublist(items.length - _testRange);
  }

  List<_ChartPoint> _chapterTimeSeries() {
    final subject = _selectedSubject;
    if (subject == null) return const [];
    final allowedLabels = _subjectSeries().map((item) => item.label).toSet();
    final timeByChapter = <String, List<_ChapterAttemptMetric>>{};
    for (final item in widget.vm.chapterAttempts.where(
      (entry) =>
          entry.subject == subject && allowedLabels.contains(entry.label),
    )) {
      timeByChapter
          .putIfAbsent(item.chapter, () => <_ChapterAttemptMetric>[])
          .add(item);
    }
    final points = timeByChapter.entries.map((entry) {
      final avg = _weightedAverageChapterTime(entry.value);
      final label = entry.key.length <= 8
          ? entry.key
          : entry.key.substring(0, 8);
      return _ChartPoint(label, avg);
    }).toList()..sort((a, b) => b.value.compareTo(a.value));
    return points.take(6).toList();
  }

  double _weightedAverageChapterTime(List<_ChapterAttemptMetric> items) {
    if (items.isEmpty) return 0.0;
    double totalMinutes = 0.0;
    int totalQuestions = 0;
    for (final item in items) {
      totalMinutes += item.avgMinutesPerQuestion * item.totalQuestions;
      totalQuestions += item.totalQuestions;
    }
    if (totalQuestions <= 0) return 0.0;
    return totalMinutes / totalQuestions;
  }

  Widget _subjectCard({
    required String title,
    Widget? footer,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          child,
          if (footer != null) ...[
            const SizedBox(height: 10),
            Center(child: footer),
          ],
        ],
      ),
    );
  }

  Widget _rangeTogglePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 34,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF625CF1) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF625CF1) : const Color(0xFFE2E6F3),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF6B7894),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectAttemptAccumulator {
  final String label;
  final DateTime date;
  int attempted = 0;
  int correct = 0;
  int total = 0;

  _SubjectAttemptAccumulator({required this.label, required this.date});
}

class _HeatmapLegend extends StatelessWidget {
  final String label;
  final Color color;

  const _HeatmapLegend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HeatmapChip extends StatelessWidget {
  final _ChapterMetric chapter;

  const _HeatmapChip({required this.chapter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: chapter.badgeColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              chapter.shortName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${chapter.proficiency.toStringAsFixed(0)}%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPoint {
  final String label;
  final double value;

  const _ChartPoint(this.label, this.value);
}

class _ChartSeries {
  final String label;
  final Color color;
  final List<_ChartPoint> points;

  const _ChartSeries({
    required this.label,
    required this.color,
    required this.points,
  });
}

class _ExplorerEmptyState extends StatelessWidget {
  final String message;

  const _ExplorerEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 180,
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ExplorerLineChart extends StatelessWidget {
  final List<_ChartPoint> points;
  final double minY;
  final double maxY;
  final String suffix;
  final Color lineColor;

  const _ExplorerLineChart({
    required this.points,
    required this.minY,
    required this.maxY,
    required this.suffix,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CustomPaint(
        painter: _ExplorerLinePainter(
          points: points,
          minY: minY,
          maxY: maxY,
          suffix: suffix,
          lineColor: lineColor,
        ),
        child: Container(),
      ),
    );
  }
}

class _ExplorerBarChart extends StatelessWidget {
  final List<_ChartPoint> bars;
  final double maxY;
  final Color barColor;

  const _ExplorerBarChart({
    required this.bars,
    required this.maxY,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final safeBars = bars.where((bar) => bar.value.isFinite).toList();
    if (safeBars.isEmpty) {
      return const _ExplorerEmptyState(message: 'No chart data available');
    }
    final scaleMax = maxY.isFinite && maxY > 0
        ? maxY
        : safeBars.map((bar) => bar.value).fold<double>(1.0, math.max);
    final tickLabels = _chartTickLabels(
      maxValue: scaleMax,
      steps: 5,
      formatter: (value) => '${value.toStringAsFixed(0)}m',
    );
    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: tickLabels
                  .map(
                    (label) => Text(
                      label,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF9AA3B8),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: safeBars.map((bar) {
                final heightFactor = (bar.value / scaleMax)
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      bar.value.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF6C748A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 22,
                      height: math.max(3.0, 120 * heightFactor),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bar.label,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF8C96AF),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplorerGroupedBarChart extends StatelessWidget {
  final List<_ChartSeries> series;

  const _ExplorerGroupedBarChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final safeSeries = series
        .map(
          (item) => _ChartSeries(
            label: item.label,
            color: item.color,
            points: item.points.where((point) => point.value.isFinite).toList(),
          ),
        )
        .where((item) => item.points.isNotEmpty)
        .toList();
    if (safeSeries.isEmpty) {
      return const _ExplorerEmptyState(message: 'No grouped chart data');
    }
    final visiblePointCount = safeSeries
        .map((item) => item.points.length)
        .reduce(math.min);
    if (visiblePointCount <= 0) {
      return const _ExplorerEmptyState(message: 'No grouped chart data');
    }
    final labels = safeSeries.first.points
        .take(visiblePointCount)
        .map((point) => point.label)
        .toList();
    final maxY =
        safeSeries
            .expand((item) => item.points.map((point) => point.value))
            .fold<double>(0.0, math.max) +
        1;
    final tickLabels = _chartTickLabels(
      maxValue: maxY,
      steps: 5,
      formatter: (value) => value.toStringAsFixed(0),
    );
    return SizedBox(
      height: 220,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 22,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: tickLabels
                        .map(
                          (label) => Text(
                            label,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF9AA3B8),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(labels.length, (index) {
                      return Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final slotWidth = constraints.maxWidth;
                            final seriesCount = math.max(1, safeSeries.length);
                            final gap = slotWidth >= 28
                                ? 4.0
                                : slotWidth >= 18
                                ? 2.0
                                : 1.0;
                            final computedBarWidth =
                                (slotWidth - (gap * (seriesCount - 1))) /
                                seriesCount;
                            final barWidth = computedBarWidth.clamp(1.5, 10.0);

                            return Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: safeSeries.asMap().entries.map((entry) {
                                    final item = entry.value;
                                    final point = item.points[index];
                                    final heightFactor = (point.value / maxY)
                                        .clamp(0.0, 1.0)
                                        .toDouble();
                                    final isLast = entry.key == safeSeries.length - 1;
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        right: isLast ? 0 : gap,
                                      ),
                                      child: Container(
                                        width: barWidth,
                                        height: 130 * heightFactor,
                                        decoration: BoxDecoration(
                                          color: item.color,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  labels[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF8C96AF),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: safeSeries.map((item) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF8C96AF),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ExplorerLinePainter extends CustomPainter {
  final List<_ChartPoint> points;
  final double minY;
  final double maxY;
  final String suffix;
  final Color lineColor;

  _ExplorerLinePainter({
    required this.points,
    required this.minY,
    required this.maxY,
    required this.suffix,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 30.0;
    const rightPad = 10.0;
    const topPad = 10.0;
    const bottomPad = 24.0;
    final chartRect = Rect.fromLTWH(
      leftPad,
      topPad,
      size.width - leftPad - rightPad,
      size.height - topPad - bottomPad,
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFE7EBF6)
      ..strokeWidth = 1;
    for (int i = 0; i < 5; i++) {
      final y = chartRect.top + (chartRect.height * i / 4);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final axisStyle = const TextStyle(fontSize: 9, color: Color(0xFF9AA3B8));
    final steps = <double>[
      maxY,
      (maxY * 0.75),
      (maxY * 0.5),
      (maxY * 0.25),
      minY,
    ];
    for (int i = 0; i < steps.length; i++) {
      final text = suffix == '%'
          ? '${steps[i].round()}%'
          : '${steps[i].toStringAsFixed(0)}$suffix';
      final painter = TextPainter(
        text: TextSpan(text: text, style: axisStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final y =
          chartRect.top + (chartRect.height * i / 4) - (painter.height / 2);
      painter.paint(canvas, Offset(0, y));
    }

    if (points.isEmpty) return;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()..color = lineColor;
    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final dx =
          chartRect.left +
          (chartRect.width * i / math.max(1.0, (points.length - 1).toDouble()));
      final normalized = ((points[i].value - minY) / math.max(1.0, maxY - minY))
          .clamp(0.0, 1.0)
          .toDouble();
      final dy = chartRect.bottom - (chartRect.height * normalized);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
      canvas.drawCircle(Offset(dx, dy), 3.5, pointPaint);

      final labelPainter = TextPainter(
        text: TextSpan(text: points[i].label, style: axisStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(dx - labelPainter.width / 2, chartRect.bottom + 6),
      );
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ExplorerLinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY ||
        oldDelegate.suffix != suffix ||
        oldDelegate.lineColor != lineColor;
  }
}

List<String> _chartTickLabels({
  required double maxValue,
  required int steps,
  required String Function(double value) formatter,
}) {
  if (steps <= 0) return const [];
  final safeMax = maxValue.isFinite && maxValue > 0 ? maxValue : 1.0;
  return List<String>.generate(steps, (index) {
    final ratio = (steps - 1 - index) / math.max(1, steps - 1);
    return formatter(safeMax * ratio);
  });
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.left,
              maxLines: 2,
              style: const TextStyle(fontSize: 11, color: Color(0xFF7B849A)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF273352),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color dotColor;

  const _StatChip({required this.label, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              style: const TextStyle(fontSize: 11, color: Color(0xFF69748B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6C748A)),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<_TrendPoint> points;
  final double platformAvg;

  const _TrendChart({required this.points, required this.platformAvg});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainter(points: points, platformAvg: platformAvg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Spacer(),
            Row(
              children: points
                  .map(
                    (point) => Expanded(
                      child: Text(
                        point.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8B93A8),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final double platformAvg;

  const _TrendPainter({required this.points, required this.platformAvg});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const top = 12.0;
    const rightPad = 12.0;
    const bottomPad = 28.0;
    final width = size.width - left - rightPad;
    final height = size.height - top - bottomPad;
    final right = left + width;
    final bottom = top + height;

    final grid = Paint()
      ..color = const Color(0xFFE6EBF4)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = top + (height * i / 4);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final axis = Paint()
      ..color = const Color(0xFFD4DBE9)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(left, top), Offset(left, bottom), axis);
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), axis);

    final platformY = bottom - (platformAvg.clamp(0.0, 100.0) / 100.0) * height;
    final platformPaint = Paint()
      ..color = const Color(0xFF9EA4B2)
      ..strokeWidth = 1.5;
    var x = left;
    while (x < right) {
      canvas.drawLine(
        Offset(x, platformY),
        Offset(math.min(x + 6, right), platformY),
        platformPaint,
      );
      x += 10;
    }

    if (points.isEmpty) return;

    final path = Path();
    final fillPath = Path();
    final linePaint = Paint()
      ..color = const Color(0xFF315CF7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33315CF7), Color(0x00315CF7)],
      ).createShader(Rect.fromLTWH(left, top, width, height));
    final dotPaint = Paint()..color = const Color(0xFF315CF7);

    for (int i = 0; i < points.length; i++) {
      final px = left + (width * i / math.max(1, points.length - 1));
      final py = bottom - (points[i].score.clamp(0.0, 100.0) / 100.0) * height;
      if (i == 0) {
        path.moveTo(px, py);
        fillPath.moveTo(px, bottom);
        fillPath.lineTo(px, py);
      } else {
        path.lineTo(px, py);
        fillPath.lineTo(px, py);
      }
      canvas.drawCircle(Offset(px, py), 3.5, dotPaint);
    }
    fillPath.lineTo(right, bottom);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.platformAvg != platformAvg;
  }
}

class _DonutChart extends StatelessWidget {
  final List<_TimeSlice> slices;

  const _DonutChart({required this.slices});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutPainter(slices),
      child: const SizedBox.expand(),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_TimeSlice> slices;

  const _DonutPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.min(size.width, size.height) * 0.34,
    );
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..color = const Color(0xFFE8ECF6);
    canvas.drawArc(rect, 0, math.pi * 2, false, bg);

    double start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / 100) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = slice.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}

class _SparkLine extends StatelessWidget {
  final List<double> points;

  const _SparkLine({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkLinePainter(points),
      child: const SizedBox.expand(),
    );
  }
}

class _SparkLinePainter extends CustomPainter {
  final List<double> points;

  const _SparkLinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.isEmpty ? const [0.0, 0.0] : points;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final spread = math.max(1.0, maxValue - minValue);
    final left = 8.0;
    final top = 12.0;
    final right = size.width - 8;
    final bottom = size.height - 12;
    final width = right - left;
    final height = bottom - top;

    final grid = Paint()
      ..color = const Color(0xFFE8ECF6)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final y = top + height * (i / 3);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final path = Path();
    final dot = Paint()..color = const Color(0xFF5B74F7);
    final line = Paint()
      ..color = const Color(0xFF5B74F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < values.length; i++) {
      final x = left + width * (i / math.max(1, values.length - 1));
      final y = bottom - ((values[i] - minValue) / spread) * height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, dot);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _SparkLinePainter oldDelegate) =>
      oldDelegate.points != points;
}

class _BarSparkChart extends StatelessWidget {
  final List<double> values;
  static const List<List<Color>> _barGradients = [
    [Color(0xFF6F86FF), Color(0xFF5068E8)],
    [Color(0xFF4FBEFF), Color(0xFF2D8EEA)],
    [Color(0xFF43D3B5), Color(0xFF1FAD8C)],
    [Color(0xFFFFC46B), Color(0xFFF29A2E)],
    [Color(0xFF8E7DFF), Color(0xFF6857E6)],
    [Color(0xFFFF8F8F), Color(0xFFE35D6A)],
  ];

  const _BarSparkChart({required this.values});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const topLabelHeight = 16.0;
        const bottomLabelHeight = 16.0;
        const verticalSpacing = 16.0;
        final maxBarHeight =
            constraints.maxHeight -
            topLabelHeight -
            bottomLabelHeight -
            verticalSpacing;
        final safeBarHeight = math.max(56.0, maxBarHeight);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: values.asMap().entries.map((entry) {
            final maxValue = values.isEmpty ? 1.0 : values.reduce(math.max);
            final normalized = maxValue <= 0 ? 0.0 : entry.value / maxValue;
            final gradientColors =
                _barGradients[entry.key % _barGradients.length];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      entry.value.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF6C748A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: safeBarHeight * normalized.clamp(0.12, 1.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: gradientColors,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: gradientColors.last.withOpacity(0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'T${entry.key + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF6C748A),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _RadarPoint {
  final String label;
  final double value;

  const _RadarPoint(this.label, this.value);
}

class _Radar extends StatelessWidget {
  final List<_RadarPoint> items;

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
  final List<_RadarPoint> items;

  const _RadarPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 12);
    final radius = math.min(size.width, size.height) * 0.28;
    final grid = Paint()
      ..color = const Color(0xFFD6DDED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int level = 1; level <= 4; level++) {
      canvas.drawPath(
        _polygon(center, radius * (level / 4), items.length),
        grid,
      );
    }

    for (int i = 0; i < items.length; i++) {
      final angle = _angle(i, items.length);
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, end, grid);

      final text = TextPainter(
        text: TextSpan(
          text: items[i].label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6C748A)),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      text.paint(
        canvas,
        Offset(
          center.dx + (radius + 18) * math.cos(angle) - text.width / 2,
          center.dy + (radius + 18) * math.sin(angle) - text.height / 2,
        ),
      );
    }

    final shape = Path();
    for (int i = 0; i < items.length; i++) {
      final currentRadius = (items[i].value.clamp(0.0, 100.0) / 100.0) * radius;
      final angle = _angle(i, items.length);
      final point = Offset(
        center.dx + currentRadius * math.cos(angle),
        center.dy + currentRadius * math.sin(angle),
      );
      if (i == 0) {
        shape.moveTo(point.dx, point.dy);
      } else {
        shape.lineTo(point.dx, point.dy);
      }
    }
    shape.close();

    final fill = Paint()
      ..color = const Color(0xFF5B74F7).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF315CF7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(shape, fill);
    canvas.drawPath(shape, stroke);
  }

  Path _polygon(Offset center, double radius, int sides) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = _angle(i, sides);
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  double _angle(int index, int total) =>
      (-math.pi / 2) + (2 * math.pi * index / total);

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.items != items;
}

class _RollingDropdownLabel extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _RollingDropdownLabel({required this.text, required this.style});

  @override
  State<_RollingDropdownLabel> createState() => _RollingDropdownLabelState();
}

class _RollingDropdownLabelState extends State<_RollingDropdownLabel>
    with SingleTickerProviderStateMixin {
  static const double _pixelsPerSecond = 28;
  static const double _endPadding = 20;
  late final ScrollController _scrollController;
  int _scrollSession = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollSession++;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureScrollLoop(double requestedExtent) async {
    if (!mounted) return;
    if (requestedExtent <= 2) {
      _scrollSession++;
      if (_scrollController.hasClients && _scrollController.offset != 0) {
        _scrollController.jumpTo(0);
      }
      return;
    }
    _scrollSession++;
    final session = _scrollSession;

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    while (mounted && session == _scrollSession) {
      if (!_scrollController.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      final extent = _scrollController.position.maxScrollExtent;
      if (extent <= 2) {
        if (_scrollController.offset != 0) {
          _scrollController.jumpTo(0);
        }
        break;
      }

      final durationMs = ((extent / _pixelsPerSecond) * 1000)
          .round()
          .clamp(2500, 14000);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || session != _scrollSession || !_scrollController.hasClients) {
        break;
      }

      await _scrollController.animateTo(
        extent,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.linear,
      );
      if (!mounted || session != _scrollSession || !_scrollController.hasClients) {
        break;
      }

      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || session != _scrollSession || !_scrollController.hasClients) {
        break;
      }
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final overflow = painter.width - maxWidth;

        if (overflow <= 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureScrollLoop(0);
          });
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureScrollLoop(overflow);
        });

        return ClipRect(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.only(right: _endPadding),
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  style: widget.style,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Color _subjectColor(String subject) {
  final normalized = subject.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const Color(0xFF16A34A);
  }

  const palette = <Color>[
    Color(0xFF4B72F1),
    Color(0xFF31B56A),
    Color(0xFFF2A126),
    Color(0xFFEB5757),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFF14B8A6),
    Color(0xFFEC4899),
  ];

  var hash = 0;
  for (final unit in normalized.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
