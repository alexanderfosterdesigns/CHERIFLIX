import 'dart:async';

import 'package:cheriflix/core/services/runtime_pressure.dart';
import 'package:cheriflix/core/widgets/poster_preview_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/widgets/tv_shortcuts.dart';

void main() {
  testWidgets('TvShortcutScope moves focus with arrow keys', (tester) async {
    final leftNode = FocusNode();
    final rightNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcutScope(
          child: Row(
            children: <Widget>[
              TextButton(
                focusNode: leftNode,
                autofocus: true,
                onPressed: () {},
                child: const Text('Left'),
              ),
              TextButton(
                focusNode: rightNode,
                onPressed: () {},
                child: const Text('Right'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(leftNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(rightNode.hasFocus, isTrue);
  });

  testWidgets(
      'TvShortcutScope restores last focused node when scope temporarily owns focus',
      (tester) async {
    final leftNode = FocusNode();
    final rightNode = FocusNode();
    addTearDown(leftNode.dispose);
    addTearDown(rightNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcutScope(
          child: Row(
            children: <Widget>[
              TextButton(
                focusNode: leftNode,
                autofocus: true,
                onPressed: () {},
                child: const Text('Left'),
              ),
              TextButton(
                focusNode: rightNode,
                onPressed: () {},
                child: const Text('Right'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(rightNode.hasFocus, isTrue);

    FocusManager.instance.primaryFocus?.nearestScope?.requestScopeFocus();
    await tester.pump();
    expect(rightNode.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(leftNode.hasFocus, isTrue);
  });

  testWidgets(
      'TvShortcutScope falls back to first traversable descendant when last focused node is unavailable',
      (tester) async {
    const scopeKey = ValueKey<String>('tv_scope');
    final leftNode = FocusNode();
    final rightNode = FocusNode();
    final replacementNode = FocusNode();
    addTearDown(leftNode.dispose);
    addTearDown(rightNode.dispose);
    addTearDown(replacementNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcutScope(
          key: scopeKey,
          child: Row(
            children: <Widget>[
              TextButton(
                focusNode: leftNode,
                autofocus: true,
                onPressed: () {},
                child: const Text('Left'),
              ),
              TextButton(
                focusNode: rightNode,
                onPressed: () {},
                child: const Text('Right'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(rightNode.hasFocus, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcutScope(
          key: scopeKey,
          child: Row(
            children: <Widget>[
              TextButton(
                focusNode: replacementNode,
                onPressed: () {},
                child: const Text('Replacement'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    FocusManager.instance.primaryFocus?.nearestScope?.requestScopeFocus();
    await tester.pump();
    expect(replacementNode.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(replacementNode.hasFocus, isTrue);
  });

  testWidgets(
      'TvIconButton skips an unavailable directional fallback and lands on the next focusable node',
      (tester) async {
    final settingsNode = FocusNode(debugLabel: 'SettingsNode');
    final scrubNode = FocusNode(debugLabel: 'ScrubNode');
    final playNode = FocusNode(debugLabel: 'PlayNode');

    scrubNode.canRequestFocus = false;

    addTearDown(settingsNode.dispose);
    addTearDown(scrubNode.dispose);
    addTearDown(playNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              TvIconButton(
                label: 'Settings',
                icon: Icons.settings_rounded,
                onPressed: () {},
                autofocus: true,
                focusNode: settingsNode,
                downFallbackNodes: <FocusNode>[scrubNode, playNode],
              ),
              const SizedBox(width: 16),
              Focus(
                focusNode: scrubNode,
                canRequestFocus: false,
                child: const SizedBox(width: 48, height: 48),
              ),
              const SizedBox(width: 16),
              TvIconButton(
                label: 'Play',
                icon: Icons.play_arrow_rounded,
                onPressed: () {},
                focusNode: playNode,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(settingsNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(playNode.hasFocus, isTrue);
    expect(scrubNode.hasFocus, isFalse);
  });

  testWidgets('TvShortcutScope invokes back callback on backspace',
      (tester) async {
    var backInvoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcutScope(
          onBack: () => backInvoked = true,
          child: Focus(
            autofocus: true,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(backInvoked, isTrue);
  });

  testWidgets('TvShortcutScope invokes back callback on gamepad back',
      (tester) async {
    var backInvoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcutScope(
          onBack: () => backInvoked = true,
          child: Focus(
            autofocus: true,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();

    expect(backInvoked, isTrue);
  });

  testWidgets('TvActionButton activates on enter', (tester) async {
    var activated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvActionButton(
            label: 'Play',
            onPressed: () => activated = true,
            autofocus: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activated, isTrue);
  });

  testWidgets('TvActionButton activates on TV OK/select keys', (tester) async {
    var activated = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvActionButton(
            label: 'Subtitles',
            onPressed: () => activated += 1,
            autofocus: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(
      LogicalKeyboardKey.gameButtonSelect,
      physicalKey: PhysicalKeyboardKey.select,
    );
    await tester.pump();

    expect(activated, 2);
  });

  testWidgets('TvShortcutScope falls back to the focused activate action',
      (tester) async {
    var activated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcutScope(
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  activated = true;
                  return null;
                },
              ),
            },
            child: const Focus(
              autofocus: true,
              child: SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(activated, isTrue);
  });

  testWidgets(
      'TvActionButton media variant keeps its size stable when focus changes',
      (tester) async {
    final playNode = FocusNode();
    final infoNode = FocusNode();
    addTearDown(playNode.dispose);
    addTearDown(infoNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              TvActionButton(
                key: const ValueKey<String>('media_play_button'),
                label: 'Play',
                onPressed: () {},
                autofocus: true,
                focusNode: playNode,
                variant: TvButtonVariant.media,
              ),
              const SizedBox(width: 16),
              TvActionButton(
                key: const ValueKey<String>('media_info_button'),
                label: 'Info',
                onPressed: () {},
                focusNode: infoNode,
                variant: TvButtonVariant.media,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final focusedSize =
        tester.getSize(find.byKey(const ValueKey<String>('media_play_button')));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('media_play_button'))),
      equals(focusedSize),
    );
  });

  testWidgets('TvPosterButton activates on numpad enter', (tester) async {
    var activated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvPosterButton(
            title: 'Dune',
            subtitle: 'Movie',
            onPressed: () => activated = true,
            autofocus: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(activated, isTrue);
  });

  testWidgets(
      'TvPosterButton keeps expanded artwork full-bleed without image zoom transforms',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 724,
            height: 500,
            child: TvPosterButton(
              title: 'Dune',
              subtitle: 'Movie',
              imageUrl: 'https://example.com/poster.jpg',
              expandedImageUrl: 'https://example.com/backdrop.jpg',
              onPressed: () {},
              autofocus: true,
              width: 210,
              posterHeight: 280,
              expandedWidth: 724,
              expandedPosterHeight: 408,
              expandOnFocus: true,
              overlayExpandedDetails: true,
              autoplayPreviewEnabled: true,
              previewLoader: () async => null,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final posterFinder = find.byType(TvPosterButton);
    final imageWidget = tester.widget<Image>(
      find.descendant(of: posterFinder, matching: find.byType(Image)).first,
    );
    final imageProvider = imageWidget.image;
    final resizedImage = imageProvider as ResizeImage;

    expect(imageWidget.fit, BoxFit.cover);
    expect(imageProvider, isA<ResizeImage>());
    expect(resizedImage.width, 724);
    expect(resizedImage.height, isNull);
    expect(
      find.descendant(of: posterFinder, matching: find.byType(AnimatedScale)),
      findsNothing,
    );
  });

  testWidgets(
      'TvPosterButton decodes portrait poster slots by height to avoid blurry crops',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 210,
            height: 360,
            child: TvPosterButton(
              title: 'The Rookie',
              subtitle: 'S1:E1',
              imageUrl: 'https://example.com/still.jpg',
              onPressed: () {},
              width: 210,
              posterHeight: 280,
              expandOnFocus: false,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final imageWidget = tester.widget<Image>(
      find
          .descendant(
            of: find.byType(TvPosterButton),
            matching: find.byType(Image),
          )
          .first,
    );
    final imageProvider = imageWidget.image as ResizeImage;

    expect(imageProvider.width, isNull);
    expect(imageProvider.height, 280);
  });

  testWidgets('TvPosterButton ignores stale preview loads after blur',
      (tester) async {
    CheriflixRuntimePressureController.instance.resetForTesting();
    addTearDown(
      CheriflixRuntimePressureController.instance.resetForTesting,
    );

    final posterNode = FocusNode(debugLabel: 'Poster');
    final nextNode = FocusNode(debugLabel: 'Next');
    final previewCompleter = Completer<Uri?>();
    addTearDown(posterNode.dispose);
    addTearDown(nextNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              SizedBox(
                width: 360,
                height: 420,
                child: TvPosterButton(
                  title: 'Preview Stress',
                  subtitle: 'Movie',
                  onPressed: () {},
                  autofocus: true,
                  focusNode: posterNode,
                  expandOnFocus: true,
                  autoplayPreviewEnabled: true,
                  previewLoadDelay: Duration.zero,
                  previewLoader: () => previewCompleter.future,
                ),
              ),
              TextButton(
                focusNode: nextNode,
                onPressed: () {},
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    nextNode.requestFocus();
    await tester.pump();
    previewCompleter.complete(Uri.parse('https://example.com/trailer'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(BackdropTrailerPreview), findsNothing);
  });

  testWidgets(
      'TvPosterButton top-aligns overlay-style expanded cards within the rail slot',
      (tester) async {
    const slotKey = ValueKey<String>('poster_slot');
    const surfaceKey = ValueKey<String>('poster_surface');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: slotKey,
            width: 724,
            height: 522,
            child: TvPosterButton(
              title: 'Grey\'s Anatomy',
              subtitle: 'TV Show',
              onPressed: () {},
              autofocus: true,
              width: 308,
              posterHeight: 440,
              expandedWidth: 724,
              expandedPosterHeight: 408,
              expandOnFocus: true,
              reserveExpandedSpace: true,
              overlayExpandedDetails: true,
              posterSurfaceKey: surfaceKey,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final slotTop = tester.getTopLeft(find.byKey(slotKey)).dy;
    final surfaceTop = tester.getTopLeft(find.byKey(surfaceKey)).dy;

    expect(surfaceTop, moreOrLessEquals(slotTop, epsilon: 0.1));
  });

  testWidgets('TvActionButton activates on gamepad confirm', (tester) async {
    var activated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvActionButton(
            label: 'Play',
            onPressed: () => activated = true,
            autofocus: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();

    expect(activated, isTrue);
  });
}
