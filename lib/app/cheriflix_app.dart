import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/focus_navigation_sound.dart';
import '../core/services/runtime_pressure.dart';
import '../core/theme/cheriflix_theme.dart';
import 'app_bootstrap.dart';

class _CheriflixScrollBehavior extends MaterialScrollBehavior {
  const _CheriflixScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class CheriflixApp extends StatelessWidget {
  const CheriflixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cheriflix Beta',
      theme: buildCheriflixTheme(),
      scrollBehavior: const _CheriflixScrollBehavior(),
      debugShowCheckedModeBanner: false,
      home: const _FocusNavigationSoundScope(
        child: AppBootstrap(),
      ),
    );
  }
}

class _FocusNavigationSoundScope extends StatefulWidget {
  const _FocusNavigationSoundScope({
    required this.child,
  });

  final Widget child;

  @override
  State<_FocusNavigationSoundScope> createState() =>
      _FocusNavigationSoundScopeState();
}

class _FocusNavigationSoundScopeState extends State<_FocusNavigationSoundScope>
    with WidgetsBindingObserver {
  late final FocusNavigationSoundInputGate _inputGate =
      FocusNavigationSoundInputGate();
  FocusNode? _lastPrimaryFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    FocusManager.instance.addListener(_handlePrimaryFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handlePrimaryFocusChanged);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    CheriflixRuntimePressureController.instance.handleMemoryPressure();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _inputGate.markUserInput(),
      child: widget.child,
    );
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _inputGate.markDirectionalKey(event.logicalKey);
    }
    return false;
  }

  void _handlePrimaryFocusChanged() {
    final nextFocus = FocusManager.instance.primaryFocus;
    if (identical(nextFocus, _lastPrimaryFocus)) {
      return;
    }

    final previousFocus = _lastPrimaryFocus;
    _lastPrimaryFocus = nextFocus;
    if (previousFocus == null || !_isPlayableFocus(nextFocus)) {
      return;
    }
    if (!_inputGate.hasRecentUserInput) {
      return;
    }

    unawaited(FocusNavigationSound.playFocusMove());
  }

  bool _isPlayableFocus(FocusNode? focusNode) {
    return focusNode != null &&
        focusNode.canRequestFocus &&
        focusNode.context != null;
  }
}

class FocusNavigationSoundInputGate {
  FocusNavigationSoundInputGate({
    DateTime Function()? clock,
    this.inputWindow = const Duration(milliseconds: 350),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration inputWindow;
  DateTime? _lastUserInputAt;

  bool get hasRecentUserInput {
    final lastInput = _lastUserInputAt;
    if (lastInput == null) {
      return false;
    }
    return _clock().difference(lastInput) <= inputWindow;
  }

  void markUserInput() {
    _lastUserInputAt = _clock();
  }

  void markDirectionalKey(LogicalKeyboardKey key) {
    if (!_isDirectionalKey(key)) {
      return;
    }
    markUserInput();
  }

  bool _isDirectionalKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.tab;
  }
}
