import 'package:flutter/material.dart';
import 'widgets/app_obscure_overlay.dart';
import 'screens/auth_wrapper.dart';

class AppLifecycleManager extends StatefulWidget {
  const AppLifecycleManager({super.key});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  AppLifecycleState? _lastState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _lastState = state;
    });
  }

  bool get _shouldObscure =>
      _lastState == AppLifecycleState.inactive ||
      _lastState == AppLifecycleState.paused ||
      _lastState == AppLifecycleState.detached;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const AuthWrapper(),
        if (_shouldObscure) const AppObscureOverlay(),
      ],
    );
  }
}
