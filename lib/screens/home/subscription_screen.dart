import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String selectedPlanId = '';
  final TextEditingController _couponController = TextEditingController();

  List<Map<String, dynamic>> subscriptionPlans = [];
  String? selectedExamId;
  bool isLoadingPlans = false;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionPlans();
  }

  /// LOAD PLANS FROM FIRESTORE
  Future<void> _loadSubscriptionPlans() async {
    setState(() => isLoadingPlans = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptionPlans')
          .where('isActive', isEqualTo: true)
          .get();

      final plans = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final examsIncluded =
            Map<String, dynamic>.from(data['examsIncluded'] ?? {});

        plans.add({
          'id': doc.id,
          'name': data['name'] ?? 'Plan',
          'durationDays': data['durationDays'] ?? 30,
          'duration': _getDurationString(data['durationDays'] ?? 30),
          'price': (data['price'] ?? 0).toInt(),
          'discount': data['discountPercentage'] ?? 0,
          'originalPrice': _calculateOriginalPrice(
              (data['price'] ?? 0).toInt(),
              (data['discountPercentage'] ?? 0).toInt()),
          'examsIncluded': examsIncluded,
        });
      }

      plans.sort((a, b) => (a['price'] as int).compareTo(b['price'] as int));

      setState(() {
        subscriptionPlans = plans;
        if (plans.isNotEmpty) selectedPlanId = plans.first['id'];
        isLoadingPlans = false;
      });
    } catch (e) {
      debugPrint("Plan load error: $e");
      setState(() => isLoadingPlans = false);
    }
  }

  /// GET TESTS/PYQS FOR SELECTED PLAN + EXAM
  Map<String, List<String>> _getContentForSelected() {
    if (selectedPlanId.isEmpty || selectedExamId == null) {
      return {'tests': [], 'pyqs': []};
    }

    final plan =
        subscriptionPlans.firstWhere((p) => p['id'] == selectedPlanId);

    final examsMap =
        Map<String, dynamic>.from(plan['examsIncluded'] ?? {});

    if (!examsMap.containsKey(selectedExamId)) {
      return {'tests': [], 'pyqs': []};
    }

    final examData = Map<String, dynamic>.from(examsMap[selectedExamId]);

    return {
      'tests': List<String>.from(examData['tests'] ?? []),
      'pyqs': List<String>.from(examData['pyqs'] ?? []),
    };
  }

  String _getDurationString(int days) {
    if (days == 30) return '1 Month';
    if (days == 90) return '3 Months';
    if (days == 180) return '6 Months';
    if (days == 365) return '12 Months';
    return '$days Days';
  }

  int _calculateOriginalPrice(int price, int discount) {
    if (discount == 0) return price;
    return (price / (1 - discount / 100)).toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingPlans) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selectedPlan =
        subscriptionPlans.firstWhere((p) => p['id'] == selectedPlanId);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          /// HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
            color: const Color(0xFF2F3E8F),
            child: Column(
              children: const [
                Icon(Icons.workspace_premium,
                    color: Colors.orange, size: 40),
                SizedBox(height: 8),
                Text("Unlock Premium",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Get unlimited access to all features",
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),

          /// CONTENT
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  /// PLAN CARDS
                  ...subscriptionPlans.map((plan) {
                    final isSelected =
                        plan['id'] == selectedPlanId;
                    final isPopular =
                        plan['durationDays'] == 180;

                    return GestureDetector(
                      onTap: () =>
                          setState(() => selectedPlanId = plan['id']),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF2F3E8F)
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? const Color(0xFF2F3E8F)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 12),

                            /// TEXT
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(plan['name'],
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w600)),
                                      if (isPopular) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius:
                                                BorderRadius.circular(
                                                    4),
                                          ),
                                          child: const Text(
                                            "Most Popular",
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white),
                                          ),
                                        )
                                      ]
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(plan['duration'],
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600])),
                                ],
                              ),
                            ),

                            /// PRICE
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "₹${plan['originalPrice']}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    decoration: TextDecoration
                                        .lineThrough,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text("₹${plan['price']}",
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.bold)),
                                    const SizedBox(width: 4),
                                    Text(
                                        "${plan['discount']}% OFF",
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.green,
                                            fontWeight:
                                                FontWeight.bold)),
                                  ],
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  }),

                  /// INCLUDED
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: const [
                        Text("What's Included",
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 10),
                        _Feature("Access to all mock tests"),
                        _Feature("Unlimited test attempts"),
                        _Feature("Previous year questions"),
                        _Feature("Detailed analytics"),
                        _Feature("National rank comparison"),
                        _Feature("Live doubt solving"),
                        _Feature("Study materials"),
                        _Feature("Ad-free experience"),
                      ],
                    ),
                  ),

                  /// COUPON
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text("Have a Coupon Code?",
                            style: TextStyle(
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _couponController,
                                decoration: InputDecoration(
                                  hintText: "Enter coupon code",
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                                onPressed: () {},
                                child: const Text("Apply"))
                          ],
                        )
                      ],
                    ),
                  ),

                  /// SECURE
                  _sectionCard(
                    color: const Color(0xFFEAF4FF),
                    child: Row(
                      children: const [
                        Icon(Icons.verified,
                            color: Colors.green),
                        SizedBox(width: 8),
                        Text("100% Secure Payment"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),

      /// BOTTOM BAR
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Text(
                "₹${selectedPlan['price']}",
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                debugPrint("Selected plan: $selectedPlanId");
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Subscribe Now"),
            )
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child, Color? color}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }
}

/// FEATURE ROW (OUTSIDE MAIN CLASS)
class _Feature extends StatelessWidget {
  final String text;
  const _Feature(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}