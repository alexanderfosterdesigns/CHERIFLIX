import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cheriflix_theme.dart';
import '../../core/widgets/bounded_asset_image.dart';
import '../../core/widgets/cheriflix_chrome.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.onFinished,
    this.loadingOnly = false,
  });

  final VoidCallback? onFinished;
  final bool loadingOnly;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _finishDelay = Duration(milliseconds: 1600);
  static const Duration _assetReadyFallbackDelay = Duration(milliseconds: 600);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  Timer? _timer;
  Timer? _assetReadyFallbackTimer;
  bool _precacheStarted = false;
  bool _assetsReady = false;

  @override
  void initState() {
    super.initState();
    _configureFinishTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheSplashAssets();
  }

  @override
  void didUpdateWidget(covariant SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadingOnly != widget.loadingOnly ||
        oldWidget.onFinished != widget.onFinished) {
      _configureFinishTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _assetReadyFallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _configureFinishTimer() {
    _timer?.cancel();
    _timer = null;

    if (!widget.loadingOnly && widget.onFinished != null && _assetsReady) {
      _timer = Timer(_finishDelay, widget.onFinished!);
    }
  }

  Future<void> _precacheSplashAssets() async {
    if (_precacheStarted) {
      return;
    }
    _precacheStarted = true;
    _assetReadyFallbackTimer = Timer(
      _assetReadyFallbackDelay,
      _markAssetsReady,
    );
    try {
      await Future.wait(<Future<void>>[
        precacheImage(
          boundedAssetImageProvider(
            context,
            CheriflixAssets.icon,
            logicalWidth: 132,
            logicalHeight: 132,
            maxDecodeWidth: 512,
            maxDecodeHeight: 512,
          ),
          context,
        ),
        precacheImage(
          boundedAssetImageProvider(
            context,
            CheriflixAssets.logo,
            logicalWidth: 220,
            logicalHeight: 46,
            maxDecodeWidth: 1024,
            maxDecodeHeight: 256,
          ),
          context,
        ),
      ]);
    } catch (_) {
      // Asset failures still surface through Image.asset below, but the splash
      // should not get stuck if the bundle reports late.
    }
    _markAssetsReady();
  }

  void _markAssetsReady() {
    _assetReadyFallbackTimer?.cancel();
    _assetReadyFallbackTimer = null;
    if (!mounted || _assetsReady) {
      return;
    }
    setState(() {
      _assetsReady = true;
    });
    _configureFinishTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CheriflixBackdrop(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOutCubic,
              ).value;
              final scale =
                  Tween<double>(begin: 0.92, end: 1.04).transform(value);
              return Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 132,
                      height: 132,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xDD111111),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(color: const Color(0x18FFFFFF)),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x66E50914),
                            blurRadius: 28,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: _assetsReady
                          ? Image(
                              image: boundedAssetImageProvider(
                                context,
                                CheriflixAssets.icon,
                                logicalWidth: 84,
                                logicalHeight: 84,
                                maxDecodeWidth: 512,
                                maxDecodeHeight: 512,
                              ),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            )
                          : const Center(
                              child: CircularProgressIndicator(),
                            ),
                    ),
                    const SizedBox(height: 28),
                    const CheriflixLogo(height: 46),
                    const SizedBox(height: 14),
                    Text(
                      widget.loadingOnly
                          ? 'Bootstrapping app services...'
                          : 'Cherry picked, for you.',
                      style: const TextStyle(
                        color: CheriflixColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
