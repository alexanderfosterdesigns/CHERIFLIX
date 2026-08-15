import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/features/player/widgets/player_scrub_bar.dart';

const String _inlineThumbnailBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7ZzE0AAAAASUVORK5CYII=';

String _thumbnailUrlFor(int seconds) =>
    'data:image/png;base64,$_inlineThumbnailBase64';

final List<int> _localThumbnailPng = base64Decode(
  _inlineThumbnailBase64,
);

void main() {
  testWidgets(
      'PlayerScrubBar stays hidden on load and reveals thumbnails only while scrubbing',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarTest');
    final frameCache = <int, String>{};
    final requestedFrames = <Duration>[];
    final seekRequests = <Duration>[];
    const stripKey = ValueKey<String>('player_scrub_thumbnail_strip');

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      focusNode.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1920,
              child: PlayerScrubBar(
                position: const Duration(seconds: 32),
                totalDuration: const Duration(minutes: 10),
                focusNode: focusNode,
                frameCache: frameCache,
                stripHideDelay: const Duration(seconds: 2),
                onSeekRequested: (position) async => seekRequests.add(position),
                onFrameRequested: (position) async {
                  requestedFrames.add(position);
                  frameCache[position.inSeconds] =
                      _thumbnailUrlFor(position.inSeconds);
                  return _thumbnailUrlFor(position.inSeconds);
                },
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(tester.getSize(find.byKey(stripKey)).height, 0);
    expect(requestedFrames, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    final placeholderFrameSize = tester.getSize(
      find.byKey(const ValueKey<String>('player_scrub_thumbnail_frame_25')),
    );
    expect(
      placeholderFrameSize.width / placeholderFrameSize.height,
      closeTo(PlayerScrubBar.defaultThumbnailAspectRatio, 0.02),
    );
    expect(find.byType(Image), findsNothing);

    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.getSize(find.byKey(stripKey)).width, closeTo(1920, 0.1));
    expect(tester.getSize(find.byKey(stripKey)).height, greaterThan(190));
    expect(requestedFrames, isNotEmpty);
    expect(requestedFrames.first, const Duration(seconds: 35));
    expect(
      requestedFrames.map((duration) => duration.inSeconds),
      containsAll(<int>[25, 30, 35, 40, 45]),
    );
    expect(find.text('00:25'), findsOneWidget);
    expect(find.text('00:35'), findsOneWidget);
    expect(find.text('00:45'), findsOneWidget);
    final firstFrameSize = tester.getSize(
      find.byKey(const ValueKey<String>('player_scrub_thumbnail_frame_25')),
    );
    expect(
      firstFrameSize.width / firstFrameSize.height,
      closeTo(PlayerScrubBar.defaultThumbnailAspectRatio, 0.02),
    );
    expect(firstFrameSize, equals(placeholderFrameSize));
    expect(find.byType(Image), findsWidgets);
    expect(
      tester.widget<Text>(find.text('00:35')).style?.fontSize ?? 0,
      greaterThanOrEqualTo(14),
    );
    expect(seekRequests, isEmpty);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(seekRequests, isEmpty);
    expect(tester.getSize(find.byKey(stripKey)).height, greaterThan(0));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(find.byKey(stripKey)).height, 0);
    expect(seekRequests, isEmpty);
    expect(requestedFrames.map((duration) => duration.inSeconds), isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      seekRequests,
      <Duration>[const Duration(seconds: 25)],
    );
  });

  testWidgets(
      'PlayerScrubBar requests the exact first and last thumbnail timestamps',
      (tester) async {
    final frameCache = <int, String>{};
    final requestedFrames = <Duration>[];
    final startFocusNode = FocusNode(debugLabel: 'ScrubBarStartEdge');
    final endFocusNode = FocusNode(debugLabel: 'ScrubBarEndEdge');

    addTearDown(() {
      startFocusNode.dispose();
      endFocusNode.dispose();
    });

    Future<void> pumpBar(Duration position, FocusNode focusNode) async {
      requestedFrames.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 960,
                child: PlayerScrubBar(
                  position: position,
                  totalDuration: const Duration(minutes: 10),
                  focusNode: focusNode,
                  frameCache: frameCache,
                  onSeekRequested: (position) async {},
                  onFrameRequested: (position) async {
                    requestedFrames.add(position);
                    frameCache[position.inSeconds] =
                        _thumbnailUrlFor(position.inSeconds);
                    return _thumbnailUrlFor(position.inSeconds);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      await tester.pump();
    }

    await pumpBar(const Duration(seconds: 2), startFocusNode);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(requestedFrames.first, Duration.zero);
    expect(requestedFrames.map((position) => position.inSeconds), contains(0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    await pumpBar(const Duration(seconds: 598), endFocusNode);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(requestedFrames.first, const Duration(minutes: 10));
    expect(
      requestedFrames.map((position) => position.inSeconds),
      contains(600),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
  });

  testWidgets(
      'PlayerScrubBar previews while a direction key is held and seeks only on enter',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarHoldTest');
    final frameCache = <int, String>{};
    final seekRequests = <Duration>[];

    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              child: PlayerScrubBar(
                position: const Duration(seconds: 30),
                totalDuration: const Duration(minutes: 10),
                focusNode: focusNode,
                frameCache: frameCache,
                onSeekRequested: (position) async => seekRequests.add(position),
                onFrameRequested: (position) async {
                  frameCache[position.inSeconds] =
                      _thumbnailUrlFor(position.inSeconds);
                  return _thumbnailUrlFor(position.inSeconds);
                },
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(seekRequests, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(seekRequests, hasLength(1));
    expect(
      seekRequests.single,
      greaterThan(const Duration(seconds: 35)),
    );
    expect(
      seekRequests.single,
      lessThanOrEqualTo(const Duration(minutes: 10)),
    );
  });

  testWidgets('PlayerScrubBar enter selects the centered thumbnail timestamp',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarEnterTest');
    final frameCache = <int, String>{};
    final seekRequests = <Duration>[];

    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              child: PlayerScrubBar(
                position: const Duration(seconds: 32),
                totalDuration: const Duration(minutes: 10),
                focusNode: focusNode,
                frameCache: frameCache,
                onSeekRequested: (position) async => seekRequests.add(position),
                onFrameRequested: (position) async {
                  frameCache[position.inSeconds] =
                      _thumbnailUrlFor(position.inSeconds);
                  return _thumbnailUrlFor(position.inSeconds);
                },
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('00:35'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(seekRequests, <Duration>[const Duration(seconds: 35)]);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      0,
    );

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(seekRequests, <Duration>[const Duration(seconds: 35)]);
  });

  testWidgets(
      'PlayerScrubBar enter on the focused progress bar does not issue a no-op seek',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarNoOpEnter');
    final frameCache = <int, String>{};
    final seekRequests = <Duration>[];
    const stripKey = ValueKey<String>('player_scrub_thumbnail_strip');

    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              child: PlayerScrubBar(
                position: const Duration(seconds: 30),
                totalDuration: const Duration(minutes: 10),
                focusNode: focusNode,
                frameCache: frameCache,
                onSeekRequested: (position) async => seekRequests.add(position),
                onFrameRequested: (position) async {
                  frameCache[position.inSeconds] =
                      _thumbnailUrlFor(position.inSeconds);
                  return _thumbnailUrlFor(position.inSeconds);
                },
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(seekRequests, isEmpty);
    expect(tester.getSize(find.byKey(stripKey)).height, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(seekRequests, isEmpty);
    expect(tester.getSize(find.byKey(stripKey)).height, 0);
  });

  testWidgets('PlayerScrubBar shows a loading indicator while a frame loads',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarLoadingTest');
    final frameCache = <int, String>{};
    final frameCompleters = <int, Completer<String?>>{};

    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              child: PlayerScrubBar(
                position: const Duration(seconds: 32),
                totalDuration: const Duration(minutes: 10),
                focusNode: focusNode,
                frameCache: frameCache,
                onSeekRequested: (position) async {},
                onFrameRequested: (position) {
                  return frameCompleters
                      .putIfAbsent(
                        position.inSeconds,
                        () => Completer<String?>(),
                      )
                      .future;
                },
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('thumbnail_loading_indicator_35')),
      findsOneWidget,
    );

    frameCache[35] = _thumbnailUrlFor(35);
    frameCompleters[35]!.complete(_thumbnailUrlFor(35));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    expect(
      find.byKey(const ValueKey<String>('thumbnail_loading_indicator_35')),
      findsNothing,
    );
  });

  testWidgets('PlayerScrubBar renders local file thumbnail refs',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarFileThumbnailTest');
    final frameCache = <int, String>{};
    final cacheDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('scrub-file-test'),
    ))!;
    final file = File('${cacheDir.path}${Platform.pathSeparator}thumb.png');
    await tester
        .runAsync(() => file.writeAsBytes(_localThumbnailPng, flush: true));
    final fileUri = file.uri.toString();
    frameCache.addAll(<int, String>{
      25: fileUri,
      30: fileUri,
      35: fileUri,
      40: fileUri,
      45: fileUri,
    });

    addTearDown(() async {
      focusNode.dispose();
      await tester.runAsync(() async {
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              child: PlayerScrubBar(
                position: const Duration(seconds: 32),
                totalDuration: const Duration(minutes: 10),
                focusNode: focusNode,
                frameCache: frameCache,
                onSeekRequested: (position) async {},
                onFrameRequested: (position) async =>
                    frameCache[position.inSeconds],
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(Image), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('thumbnail_loading_indicator_35')),
      findsNothing,
    );
  });

  testWidgets('PlayerScrubBar drag seeks to the visible thumbnail timestamp',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarDragAlignmentTest');
    final frameCache = <int, String>{};
    final seekRequests = <Duration>[];

    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              child: PlayerScrubBar(
                position: const Duration(seconds: 32),
                totalDuration: const Duration(minutes: 10),
                focusNode: focusNode,
                frameCache: frameCache,
                onSeekRequested: (position) async => seekRequests.add(position),
                onFrameRequested: (position) async {
                  frameCache[position.inSeconds] =
                      _thumbnailUrlFor(position.inSeconds);
                  return _thumbnailUrlFor(position.inSeconds);
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final barRect =
        tester.getRect(find.byKey(const ValueKey<String>('player_scrub_bar')));
    final targetDx = barRect.left +
        (barRect.width * (const Duration(seconds: 39).inSeconds / 600));
    final gesture = await tester.startGesture(
      Offset(targetDx, barRect.bottom - 8),
    );
    await tester.pump();
    await gesture.moveTo(Offset(targetDx, barRect.bottom - 8));
    await tester.pump();

    expect(find.text('00:35'), findsOneWidget);

    await gesture.up();
    await tester.pump();

    expect(seekRequests, <Duration>[const Duration(seconds: 35)]);
  });

  testWidgets('PlayerScrubBar exits scrub mode and transfers focus',
      (tester) async {
    final focusNode = FocusNode(debugLabel: 'ScrubBarExitTest');
    final exitFocusNode = FocusNode(debugLabel: 'ScrubBarExitTarget');
    final frameCache = <int, String>{};
    var exitCalls = 0;

    addTearDown(() {
      focusNode.dispose();
      exitFocusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              SizedBox(
                width: 960,
                child: PlayerScrubBar(
                  position: const Duration(seconds: 30),
                  totalDuration: const Duration(minutes: 10),
                  focusNode: focusNode,
                  frameCache: frameCache,
                  onSeekRequested: (position) async {},
                  onFrameRequested: (position) async {
                    frameCache[position.inSeconds] =
                        _thumbnailUrlFor(position.inSeconds);
                    return _thumbnailUrlFor(position.inSeconds);
                  },
                  onExitRequested: () {
                    exitCalls += 1;
                    exitFocusNode.requestFocus();
                  },
                ),
              ),
              Focus(
                focusNode: exitFocusNode,
                child: const SizedBox(width: 20, height: 20),
              ),
            ],
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(exitCalls, 1);
    expect(exitFocusNode.hasFocus, isTrue);
  });
}
