import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  /// Convert HTML → Plain Text
  String htmlToPlainText(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2F6FEB),
        centerTitle: true,
        title: const Text(
          "Terms & Conditions",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('policies')
            .where('type', isEqualTo: 'terms')
            .where('isActive', isEqualTo: true)
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("Terms & Conditions not available"),
            );
          }

          final doc = snapshot.data!.docs.first;
          final html = doc['content'] ?? doc['body'] ?? doc['text'] ?? "";

          String text = htmlToPlainText(html);

          // Change email
          text = text.replaceAll(
            RegExp(r'Email\s*:\s*.*', caseSensitive: false),
            'Email: support@ranksprintai.com',
          );

          // Change phone line
          text = text.replaceAll(
            RegExp(r'Phone\s*:\s*.*', caseSensitive: false),
            'For more info visit ranksprintai.com',
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.8,
                      color: Colors.black87,
                    ),
                    children: [
                      TextSpan(
                        text: text
                            .replaceAll("Email: support@ranksprintai.com", "")
                            .replaceAll(
                              "For more info visit ranksprintai.com",
                              "",
                            ),
                      ),

                      const TextSpan(text: "\n\nEmail: "),

                      TextSpan(
                        text: "support@ranksprintai.com",
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final Uri email = Uri.parse(
                              "mailto:support@ranksprintai.com",
                            );
                            if (await canLaunchUrl(email)) {
                              await launchUrl(email);
                            }
                          },
                      ),

                      const TextSpan(text: "\n\nFor more info visit "),

                      TextSpan(
                        text: "ranksprintai.com",
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final Uri url = Uri.parse(
                              "https://ranksprintai.com",
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
