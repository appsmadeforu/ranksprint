import 'package:flutter/material.dart';

class AppObscureOverlay extends StatelessWidget {
  const AppObscureOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            '',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
