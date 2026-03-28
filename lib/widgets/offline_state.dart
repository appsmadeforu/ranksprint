import 'package:flutter/material.dart';

class OfflineState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const OfflineState({
    super.key,
    this.title = 'No Internet',
    this.message =
        'Please check your connection and try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/nointernet.png',
                height: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF8A8A8A),
                  height: 1.4,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B86C8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Try Again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
