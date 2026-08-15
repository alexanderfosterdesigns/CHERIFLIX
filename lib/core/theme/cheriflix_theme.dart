import 'package:flutter/material.dart';

class CheriflixColors {
  static const Color background = Color(0xFF141414);
  static const Color nav = Color(0xFF000000);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color elevatedSurface = Color(0xFF232323);
  static const Color accentRed = Color(0xFFE50914);
  static const Color accentRedMuted = Color(0xFFB20710);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF999999);
  static const Color outline = Color(0x40FFFFFF);
  static const Color focus = Color(0xFFFFFFFF);
  static const Color shadow = Color(0xB3000000);
}

class CheriflixAssets {
  static const String logo = 'assets/branding/CHERIFLIX typography logo.png';
  static const String icon = 'assets/branding/icon HQ.png';
}

class CheriflixTypography {
  static const String sansFamily = 'Netflix Sans';
  static const String subtitleFamily = 'Consolas';
  static const String heroEyebrowFamily = 'DomusExtrabold';
  static const String heroDisplayFamily = 'BebasNeueRegular';
  static const String heroSupportFamily = 'BFSoloSansBold';

  static const TextStyle heroTitle = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 0.98,
  );

  static const TextStyle heroBannerEyebrow = TextStyle(
    fontFamily: heroEyebrowFamily,
    fontSize: 12,
    letterSpacing: 4.1,
    height: 1,
    shadows: <Shadow>[
      Shadow(
        color: Color(0xAA000000),
        offset: Offset(0, 1),
        blurRadius: 6,
      ),
    ],
  );

  static const TextStyle heroBannerTitle = TextStyle(
    fontFamily: heroDisplayFamily,
    fontSize: 82,
    letterSpacing: -0.8,
    height: 0.82,
    shadows: <Shadow>[
      Shadow(
        color: Color(0xB0000000),
        offset: Offset(0, 3),
        blurRadius: 14,
      ),
    ],
  );

  static const TextStyle heroBannerMeta = TextStyle(
    fontFamily: heroSupportFamily,
    fontSize: 12,
    letterSpacing: 0,
    height: 1.1,
    shadows: <Shadow>[
      Shadow(
        color: Color(0x80000000),
        offset: Offset(0, 1),
        blurRadius: 4,
      ),
    ],
  );

  static const TextStyle heroBannerSynopsis = TextStyle(
    fontFamily: heroSupportFamily,
    fontSize: 12.8,
    height: 1.42,
    shadows: <Shadow>[
      Shadow(
        color: Color(0xB0000000),
        offset: Offset(0, 1),
        blurRadius: 5,
      ),
    ],
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.08,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.16,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w300,
    height: 1.52,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.48,
  );

  static const TextStyle metadata = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.32,
    color: CheriflixColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    height: 1.1,
    color: CheriflixColors.textSecondary,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: subtitleFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.18,
    color: Color(0xF2FFFFFF),
    shadows: <Shadow>[
      Shadow(
        color: Color(0xF0000000),
        offset: Offset(0, 2),
        blurRadius: 10,
      ),
      Shadow(
        color: Color(0xB3000000),
        offset: Offset(0, 0),
        blurRadius: 3,
      ),
    ],
  );

  static TextTheme textTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: heroTitle,
      displayMedium: heroTitle.copyWith(fontSize: 34),
      displaySmall: heroTitle.copyWith(fontSize: 28),
      headlineLarge: sectionTitle.copyWith(fontSize: 22),
      headlineMedium: sectionTitle.copyWith(fontSize: 20),
      headlineSmall: sectionTitle.copyWith(fontSize: 18),
      titleLarge: cardTitle.copyWith(fontSize: 17),
      titleMedium: cardTitle,
      titleSmall: metadata.copyWith(color: CheriflixColors.textPrimary),
      bodyLarge: body.copyWith(fontSize: 16),
      bodyMedium: body,
      bodySmall: metadata.copyWith(fontSize: 12),
      labelLarge: button,
      labelMedium: metadata,
      labelSmall: metadata.copyWith(fontSize: 12),
    );
  }
}

ThemeData buildCheriflixTheme() {
  const colorScheme = ColorScheme.dark(
    primary: CheriflixColors.accentRed,
    secondary: CheriflixColors.accentRed,
    surface: CheriflixColors.surface,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: CheriflixColors.textPrimary,
  );

  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: CheriflixTypography.sansFamily,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: CheriflixColors.background,
    focusColor: Colors.transparent,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: CheriflixColors.textPrimary,
      selectionColor: Color(0x66E50914),
      selectionHandleColor: CheriflixColors.accentRed,
    ),
    dividerColor: Colors.white10,
  );

  return base.copyWith(
    textTheme: CheriflixTypography.textTheme(base.textTheme).apply(
      bodyColor: CheriflixColors.textPrimary,
      displayColor: CheriflixColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF101010),
      labelStyle: CheriflixTypography.button.copyWith(
        color: CheriflixColors.textSecondary,
        letterSpacing: 0.6,
      ),
      hintStyle: const TextStyle(
        color: Color(0x80FFFFFF),
        fontSize: 16,
        fontWeight: FontWeight.w300,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: CheriflixColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: CheriflixColors.focus,
          width: 3,
        ),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: CheriflixColors.outline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: CheriflixColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentTextStyle: CheriflixTypography.bodyMedium.copyWith(
        color: CheriflixColors.textPrimary,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CheriflixColors.accentRed,
      linearTrackColor: Color(0x33111111),
      circularTrackColor: Color(0x33111111),
    ),
    iconTheme: const IconThemeData(color: CheriflixColors.textPrimary),
  );
}
