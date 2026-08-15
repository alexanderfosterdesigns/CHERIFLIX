import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

void main() {
  group('VideoControllerConfiguration.shouldAttachSurfaceAfterVideoParameters',
      () {
    test('defaults to true for gpu output', () {
      const configuration = VideoControllerConfiguration(
        vo: 'gpu',
      );

      expect(configuration.shouldAttachSurfaceAfterVideoParameters, isTrue);
    });

    test('defaults to false for non-gpu outputs', () {
      const configuration = VideoControllerConfiguration(
        vo: 'mediacodec_embed',
      );

      expect(configuration.shouldAttachSurfaceAfterVideoParameters, isFalse);
    });

    test('uses explicit true override', () {
      const configuration = VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        androidAttachSurfaceAfterVideoParameters: true,
      );

      expect(configuration.shouldAttachSurfaceAfterVideoParameters, isTrue);
    });

    test('uses explicit false override', () {
      const configuration = VideoControllerConfiguration(
        vo: 'gpu',
        androidAttachSurfaceAfterVideoParameters: false,
      );

      expect(configuration.shouldAttachSurfaceAfterVideoParameters, isFalse);
    });

    test('copyWith keeps explicit false override after output change', () {
      const configuration = VideoControllerConfiguration(
        vo: 'gpu',
        androidAttachSurfaceAfterVideoParameters: false,
      );

      final updated = configuration.copyWith(
        vo: 'mediacodec_embed',
      );

      expect(updated.shouldAttachSurfaceAfterVideoParameters, isFalse);
    });

    test('copyWith keeps explicit true override after output change', () {
      const configuration = VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        androidAttachSurfaceAfterVideoParameters: true,
      );

      final updated = configuration.copyWith(
        vo: 'gpu',
      );

      expect(updated.shouldAttachSurfaceAfterVideoParameters, isTrue);
    });
  });

  group('Android deferred attachment wiring', () {
    test('deferred attach skips the placeholder 1x1 prime', () {
      expect(
        shouldPrimeInitialAndroidSurfaceSize(
          attachSurfaceAfterVideoParameters: true,
        ),
        isFalse,
      );
    });

    test('attach-early mode still primes the placeholder 1x1 surface', () {
      expect(
        shouldPrimeInitialAndroidSurfaceSize(
          attachSurfaceAfterVideoParameters: false,
        ),
        isTrue,
      );
    });

    test('create arguments carry the deferred attach flag to native code', () {
      expect(
        buildAndroidVideoOutputManagerCreateArguments(
          handle: 42,
          forceSurfaceTexture: true,
          attachSurfaceAfterVideoParameters: true,
        ),
        <String, Object>{
          'handle': '42',
          'forceSurfaceTexture': true,
          'attachSurfaceAfterVideoParameters': true,
        },
      );
    });

    test('first non-zero wid with real dimensions triggers a bind', () {
      expect(
        shouldBindAndroidSurfaceFromTextureUpdate(
          previousWid: 0,
          nextWid: 15310,
          width: 1920,
          height: 1080,
          previousWidth: 0,
          previousHeight: 0,
        ),
        isTrue,
      );
    });

    test('zero wid never triggers a bind', () {
      expect(
        shouldBindAndroidSurfaceFromTextureUpdate(
          previousWid: 0,
          nextWid: 0,
          width: 1920,
          height: 1080,
          previousWidth: 0,
          previousHeight: 0,
        ),
        isFalse,
      );
    });

    test('identical wid and size do not trigger redundant binds', () {
      expect(
        shouldBindAndroidSurfaceFromTextureUpdate(
          previousWid: 15310,
          nextWid: 15310,
          width: 1920,
          height: 1080,
          previousWidth: 1920,
          previousHeight: 1080,
        ),
        isFalse,
      );
    });

    test('size changes with the same wid still trigger a rebind', () {
      expect(
        shouldBindAndroidSurfaceFromTextureUpdate(
          previousWid: 15310,
          nextWid: 15310,
          width: 1280,
          height: 720,
          previousWidth: 1920,
          previousHeight: 1080,
        ),
        isTrue,
      );
    });

    test('first deferred real-surface bind refreshes the video pipeline', () {
      expect(
        shouldRefreshAndroidVideoAfterSurfaceBind(
          videoOutputName: 'gpu',
          attachSurfaceAfterVideoParameters: true,
          previousBoundWid: 0,
          nextWid: 15310,
        ),
        isTrue,
      );
    });

    test('attach-early gpu mode does not refresh after a surface bind', () {
      expect(
        shouldRefreshAndroidVideoAfterSurfaceBind(
          videoOutputName: 'gpu',
          attachSurfaceAfterVideoParameters: false,
          previousBoundWid: 0,
          nextWid: 15310,
        ),
        isFalse,
      );
    });

    test('attach-early mediacodec_embed refreshes after first surface bind', () {
      expect(
        shouldRefreshAndroidVideoAfterSurfaceBind(
          videoOutputName: 'mediacodec_embed',
          attachSurfaceAfterVideoParameters: false,
          previousBoundWid: 0,
          nextWid: 15310,
        ),
        isTrue,
      );
    });

    test('subsequent deferred binds do not trigger another refresh', () {
      expect(
        shouldRefreshAndroidVideoAfterSurfaceBind(
          videoOutputName: 'mediacodec_embed',
          attachSurfaceAfterVideoParameters: true,
          previousBoundWid: 15310,
          nextWid: 15310,
        ),
        isFalse,
      );
    });

    test('producer-backed deferred binds still request the one-time refresh',
        () {
      expect(
        shouldRefreshAndroidVideoAfterSurfaceBind(
          videoOutputName: 'gpu',
          attachSurfaceAfterVideoParameters: true,
          previousBoundWid: 0,
          nextWid: 15310,
        ),
        isTrue,
      );
    });
  });
}
