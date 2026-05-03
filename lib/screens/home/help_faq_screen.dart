import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/static_top_header.dart';

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<QuerySnapshot> _faqFuture;

  String _searchQuery = '';
  String _selectedCategory = 'All';

  String htmlToPlainText(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<li>', caseSensitive: false), '- ')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    _faqFuture = _loadFaqs();
  }

  Future<QuerySnapshot> _loadFaqs() {
    return FirebaseFirestore.instance
        .collection('helpFaqs')
        .get()
        .timeout(const Duration(seconds: 12));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: const StaticTopHeader(title: 'Help & FAQ'),
      body: SafeArea(
        top: false,
        child: FutureBuilder<QuerySnapshot>(
          future: _faqFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not load FAQs right now.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _faqFuture = _loadFaqs();
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
              );
            }

            final docsList = snapshot.data?.docs ?? [];
            if (docsList.isEmpty) {
              return Center(
                child: Text(
                  'No FAQs available',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }

            final faqs = docsList
                .map(
                  (doc) => _FaqItem.fromMap(doc.data() as Map<String, dynamic>),
                )
                .toList()
              ..sort((a, b) => a.priority.compareTo(b.priority));

            final categories = _buildCategories(faqs);
            final filteredFaqs = _filterFaqs(faqs);
            final groupedFaqs = _groupFaqs(filteredFaqs, categories);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 14),
                  _buildCategoryChips(categories),
                  const SizedBox(height: 22),
                  Text(
                    'Frequently Asked Questions',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (filteredFaqs.isEmpty)
                    _buildEmptyState()
                  else
                    ...groupedFaqs.entries.map(
                      (entry) => _FaqSection(
                        title: entry.key,
                        items: entry.value,
                        htmlToPlainText: htmlToPlainText,
                      ),
                    ),
                  const SizedBox(height: 18),
                  _buildHelpFooter(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<String> _buildCategories(List<_FaqItem> faqs) {
    final discovered = <String>{};
    for (final faq in faqs) {
      final category = faq.category;
      if (category.isNotEmpty) {
        discovered.add(category);
      }
    }
    final categories = discovered.toList()..sort();
    return ['All', ...categories];
  }

  List<_FaqItem> _filterFaqs(List<_FaqItem> faqs) {
    return faqs.where((faq) {
      final matchesCategory =
          _selectedCategory == 'All' || faq.category == _selectedCategory;
      final query = _searchQuery.trim().toLowerCase();
      final matchesQuery =
          query.isEmpty ||
          faq.question.toLowerCase().contains(query) ||
          htmlToPlainText(faq.answer).toLowerCase().contains(query) ||
          faq.category.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  Map<String, List<_FaqItem>> _groupFaqs(
    List<_FaqItem> faqs,
    List<String> categories,
  ) {
    final grouped = <String, List<_FaqItem>>{};
    for (final category in categories.where((item) => item != 'All')) {
      final items = faqs.where((faq) => faq.category == category).toList();
      if (items.isNotEmpty) {
        grouped[category] = items;
      }
    }

    final uncategorized = faqs.where((faq) => faq.category.isEmpty).toList();
    if (uncategorized.isNotEmpty) {
      grouped['General'] = uncategorized;
    }
    return grouped;
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search help...',
          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : TextButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(List<String> categories) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = _selectedCategory == category;
          return InkWell(
            onTap: () => setState(() => _selectedCategory = category),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
              ),
              child: Text(
                category,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        'No FAQs matched your search. Try another keyword or category.',
        style: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildHelpFooter() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Still need help?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reach out to the RankSprint support team from the app if your answer is not listed here.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  const _FaqSection({
    required this.title,
    required this.items,
    required this.htmlToPlainText,
  });

  final String title;
  final List<_FaqItem> items;
  final String Function(String) htmlToPlainText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: colorScheme.onSurfaceVariant,
          collapsedIconColor: colorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          children: items
              .map(
                (item) => _FaqTile(
                  question: item.question,
                  answer: htmlToPlainText(item.answer),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: colorScheme.onSurfaceVariant,
          collapsedIconColor: colorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info,
                  size: 17,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  question,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 27),
              child: Text(
                answer,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem {
  const _FaqItem({
    required this.question,
    required this.answer,
    required this.priority,
    required this.category,
  });

  final String question;
  final String answer;
  final int priority;
  final String category;

  factory _FaqItem.fromMap(Map<String, dynamic> data) {
    return _FaqItem(
      question: (data['question'] ?? '').toString(),
      answer: (data['answer'] ?? '').toString(),
      priority: ((data['priority'] ?? 0) as num).toInt(),
      category: _normalizeCategory(
        (data['category'] ?? data['section'] ?? data['group'] ?? '').toString(),
      ),
    );
  }

  static String _normalizeCategory(String raw) {
    return raw.trim();
  }
}
