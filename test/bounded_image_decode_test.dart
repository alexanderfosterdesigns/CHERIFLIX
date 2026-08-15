import 'package:cheriflix/core/theme/cheriflix_theme.dart';
import 'package:cheriflix/core/widgets/cheriflix_chrome.dart';
import 'package:cheriflix/core/widgets/profile_avatar.dart';
import 'package:cheriflix/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile avatars request bounded asset decode sizes',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: CheriflixProfileAvatar(
            avatarLabel: 'Cheri',
            width: 96,
            height: 64,
            resolvedAssetPath: CheriflixAssets.icon,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final resizeProvider = image.image as ResizeImage;

    expect(resizeProvider.width, 192);
    expect(resizeProvider.height, 128);
  });

  testWidgets('brand logo renders through a bounded resize provider',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: CheriflixLogo(height: 46),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final resizeProvider = image.image as ResizeImage;

    expect(resizeProvider.width, lessThanOrEqualTo(1024));
    expect(resizeProvider.height, 92);
    expect((resizeProvider.imageProvider as AssetImage).assetName,
        CheriflixAssets.logo);
  });

  testWidgets('splash icon renders through a bounded resize provider',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(loadingOnly: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 601));
    await tester.pump();

    final iconProvider = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<ResizeImage>()
        .firstWhere(
          (provider) =>
              provider.imageProvider is AssetImage &&
              (provider.imageProvider as AssetImage).assetName ==
                  CheriflixAssets.icon,
        );

    expect(iconProvider.width, 84);
    expect(iconProvider.height, 84);
  });
}
