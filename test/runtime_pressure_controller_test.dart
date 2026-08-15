import 'package:cheriflix/core/services/runtime_pressure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime pressure suspends autoplay previews for the session', () {
    final controller = CheriflixRuntimePressureController.instance;
    controller.resetForTesting();
    addTearDown(controller.resetForTesting);

    expect(controller.previewSuspendedForSession, isFalse);

    controller.handleMemoryPressure();

    expect(controller.previewSuspendedForSession, isTrue);
    expect(controller.memoryPressureCount, 1);
  });

  test('preview ownership allows only one active surface at a time', () {
    final controller = CheriflixRuntimePressureController.instance;
    controller.resetForTesting();
    addTearDown(controller.resetForTesting);

    final firstOwner = Object();
    final secondOwner = Object();

    controller.claimPreviewSurface(firstOwner);
    expect(controller.ownsPreviewSurface(firstOwner), isTrue);
    expect(controller.ownsPreviewSurface(secondOwner), isFalse);

    controller.claimPreviewSurface(secondOwner);
    expect(controller.ownsPreviewSurface(firstOwner), isFalse);
    expect(controller.ownsPreviewSurface(secondOwner), isTrue);
  });

  test('repeated preview failures suspend previews', () {
    final controller = CheriflixRuntimePressureController.instance;
    controller.resetForTesting();
    addTearDown(controller.resetForTesting);

    controller.recordPreviewFailure();
    controller.recordPreviewFailure();
    expect(controller.previewSuspendedForSession, isFalse);

    controller.recordPreviewFailure();
    expect(controller.previewSuspendedForSession, isTrue);
  });

  test('successful preview clears transient failure streak', () {
    final controller = CheriflixRuntimePressureController.instance;
    controller.resetForTesting();
    addTearDown(controller.resetForTesting);

    controller.recordPreviewFailure();
    controller.recordPreviewFailure();
    controller.recordPreviewSuccess();
    controller.recordPreviewFailure();

    expect(controller.previewFailureCount, 1);
    expect(controller.previewSuspendedForSession, isFalse);
  });
}
