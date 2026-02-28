import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TopHeader extends StatelessWidget {
  final String? selectedExamId;
  final List<String> userExamIds;
  final Function(String) onExamChanged;

  const TopHeader({
    super.key,
    required this.selectedExamId,
    required this.userExamIds,
    required this.onExamChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE5E7EB), // light grey
            width: 1, // thin line
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('exams')
                  .where('isActive', isEqualTo: true)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox();
                }

                final exams = snapshot.data!.docs;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    // color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedExamId,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      items: exams.map((exam) {
                        final isUnlocked = userExamIds.contains(exam.id);

                        return DropdownMenuItem<String>(
                          value: exam.id,
                          enabled: isUnlocked,
                          child: Row(
                            children: [
                              Text(
                                exam['name'] ?? exam.id,
                                style: TextStyle(
                                  color: isUnlocked
                                      ? Colors.black
                                      : Colors.grey,
                                ),
                              ),
                              if (!isUnlocked)
                                const Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null && userExamIds.contains(value)) {
                          onExamChanged(value);
                        }
                      },
                    ),
                  ),
                );
              },
            ),

            // Bell Icon
            Stack(
              children: [
                const Icon(Icons.notifications_none, size: 28),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
