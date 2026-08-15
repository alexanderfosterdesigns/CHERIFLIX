import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class CheriflixRuntimePressureController extends ChangeNotifier {
  CheriflixRuntimePressureController._();

  static final CheriflixRuntimePressureController instance =
      CheriflixRuntimePressureController._();

  bool _previewSuspendedForSession = false;
  int _memoryPressureCount = 0;
  int _previewFailureCount = 0;
  DateTime? _lastPreviewFailureAt;
  Object? _activePreviewOwner;

  bool get previewSuspendedForSession => _previewSuspendedForSession;
  int get memoryPressureCount => _memoryPressureCount;
  int get previewFailureCount => _previewFailureCount;

  bool ownsPreviewSurface(Object owner) =>
      _activePreviewOwner == null || identical(_activePreviewOwner, owner);

  void claimPreviewSurface(Object owner) {
    if (identical(_activePreviewOwner, owner)) {
      return;
    }
    _activePreviewOwner = owner;
    notifyListeners();
  }

  void releasePreviewSurface(Object owner) {
    if (!identical(_activePreviewOwner, owner)) {
      return;
    }
    _activePreviewOwner = null;
    notifyListeners();
  }

  void handleMemoryPressure() {
    _memoryPressureCount += 1;
    _previewSuspendedForSession = true;
    _activePreviewOwner = null;
    trimImageCache();
    notifyListeners();
  }

  void recordPreviewFailure() {
    final now = DateTime.now();
    if (_lastPreviewFailureAt == null ||
        now.difference(_lastPreviewFailureAt!) > const Duration(minutes: 2)) {
      _previewFailureCount = 0;
    }
    _lastPreviewFailureAt = now;
    _previewFailureCount += 1;
    if (_previewFailureCount >= 3) {
      _previewSuspendedForSession = true;
      _activePreviewOwner = null;
    }
    notifyListeners();
  }

  void suspendPreviewsForSession() {
    if (_previewSuspendedForSession) {
      return;
    }
    _previewSuspendedForSession = true;
    notifyListeners();
  }

  void recordPreviewSuccess() {
    if (_previewFailureCount == 0) {
      return;
    }
    _previewFailureCount = 0;
    _lastPreviewFailureAt = null;
    notifyListeners();
  }

  void trimImageCache() {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  @visibleForTesting
  void resetForTesting() {
    _previewSuspendedForSession = false;
    _memoryPressureCount = 0;
    _previewFailureCount = 0;
    _lastPreviewFailureAt = null;
    _activePreviewOwner = null;
    notifyListeners();
  }
}
