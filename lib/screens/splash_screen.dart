import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'auth_wrapper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoFuture;
  bool _showApp = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/splash_screen.mp4');
    _initializeVideoFuture = _initializeVideo();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_handlePlaybackState);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    try {
      await _videoController!.initialize();
      _videoController!
        ..setLooping(false)
        ..addListener(_handlePlaybackState);
      await _videoController!.play();
    } catch (_) {
      _showMainApp();
    }
  }

  void _handlePlaybackState() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;

    final position = controller.value.position;
    final duration = controller.value.duration;

    if (duration != Duration.zero &&
        position >= duration - const Duration(milliseconds: 150)) {
      _showMainApp();
    }
  }

  void _showMainApp() {
    if (!mounted || _showApp) return;
    setState(() {
      _showApp = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showApp) {
      return const AuthWrapper();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<void>(
        future: _initializeVideoFuture,
        builder: (context, snapshot) {
          if (_showApp) {
            return const SizedBox.shrink();
          }

          if (snapshot.hasError ||
              _videoController == null ||
              !_videoController!.value.isInitialized) {
            return const SizedBox.expand();
          }

          final controller = _videoController!;
          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          );
        },
      ),
    );
  }
}
