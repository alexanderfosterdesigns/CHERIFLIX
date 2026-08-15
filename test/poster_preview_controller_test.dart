import 'dart:async';

import 'package:cheriflix/core/services/runtime_pressure.dart';
import 'package:cheriflix/core/widgets/poster_preview_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PosterPreviewController ignores stale preview loads after blur',
      () async {
    CheriflixRuntimePressureController.instance.resetForTesting();
    addTearDown(
      CheriflixRuntimePressureController.instance.resetForTesting,
    );

    final controller = PosterPreviewController(previewDelay: Duration.zero);
    final previewCompleter = Completer<Uri?>();
    addTearDown(controller.dispose);

    controller.focus(
      itemKey: 'movie-1',
      layerLink: LayerLink(),
      size: const Size(320, 180),
      loadPreview: () => previewCompleter.future,
    );
    controller.blur('movie-1');

    previewCompleter.complete(Uri.parse('https://example.com/trailer'));
    await previewCompleter.future;
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeKey, isNull);
    expect(controller.activePreviewUri, isNull);
  });

  test('PosterPreviewController does not start loads when previews suspended',
      () async {
    final pressureController = CheriflixRuntimePressureController.instance;
    pressureController.resetForTesting();
    addTearDown(pressureController.resetForTesting);
    pressureController.handleMemoryPressure();

    var loadCount = 0;
    final controller = PosterPreviewController(previewDelay: Duration.zero);
    addTearDown(controller.dispose);

    controller.focus(
      itemKey: 'movie-2',
      layerLink: LayerLink(),
      size: const Size(320, 180),
      loadPreview: () async {
        loadCount += 1;
        return Uri.parse('https://example.com/trailer');
      },
    );
    await Future<void>.delayed(Duration.zero);

    expect(loadCount, 0);
    expect(controller.activePreviewUri, isNull);
  });
}
