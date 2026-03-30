import 'dart:async';

import 'package:flutter/material.dart';

class AnimatedLoadingLabel extends StatefulWidget {
  const AnimatedLoadingLabel({
    super.key,
    this.label = 'Loading',
    this.textStyle,
    this.dotColor,
    this.showPulse = true,
  });

  final String label;
  final TextStyle? textStyle;
  final Color? dotColor;
  final bool showPulse;

  @override
  State<AnimatedLoadingLabel> createState() => _AnimatedLoadingLabelState();
}

class _AnimatedLoadingLabelState extends State<AnimatedLoadingLabel> {
  Timer? _timer;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() {
        _dotCount = _dotCount % 3 + 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        widget.textStyle ??
        const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
        );
    final dotColor =
        widget.dotColor ?? baseStyle.color ?? const Color(0xFF64748B);
    final hasLabel = widget.label.trim().isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showPulse) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (hasLabel) Text(widget.label, style: baseStyle),
        if (hasLabel) const SizedBox(width: 3),
        Text('.' * _dotCount, style: baseStyle.copyWith(letterSpacing: 1.2)),
      ],
    );
  }
}
