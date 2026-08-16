import 'package:flutter/material.dart';

class CheriflixColors {
  static const Color background = Color(0xFF0D0D0D);
  static const Color nav = Color(0xFF080808);
  static const Color surface = Color(0xFF161616);
  static const Color elevatedSurface = Color(0xFF1E1E1E);
  static const Color accentRed = Color(0xFFE50914);
  static const Color accentRedMuted = Color(0xFFB20710);
  static const Color textPrimary = Color(0xFFF0F0F0);
  static const Color textSecondary = Color(0xFF7A7A7A);
  // Dedicated ink for white/light controls. This is intentionally not
  // inherited from the dark theme, so labels and icons always remain legible.
  static const Color inkOnLight = Color(0xFF080808);
  static const Color outline = Color(0x30FFFFFF);
  static const Color focus = Color(0xFFE8E8E8);
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
    height: 1.02,
    letterSpacing: -0.3,
  );

  static const TextStyle heroBannerEyebrow = TextStyle(
    fontFamily: heroEyebrowFamily,
    fontSize: 11,
    letterSpacing: 4.5,
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
    height: 1.12,
    letterSpacing: -0.15,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.1,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w300,
    height: 1.55,
    letterSpacing: 0.05,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.48,
    letterSpacing: 0.02,
  );

  static const TextStyle metadata = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.32,
    color: CheriflixColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: 0.1,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
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
    dividerColor: const Color(0x12FFFFFF),
  );

  return base.copyWith(
    textTheme: CheriflixTypography.textTheme(base.textTheme).apply(
      bodyColor: CheriflixColors.textPrimary,
      displayColor: CheriflixColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0C0C0C),
      labelStyle: CheriflixTypography.button.copyWith(
        color: CheriflixColors.textSecondary,
        letterSpacing: 0.6,
      ),
      hintStyle: const TextStyle(
        color: Color(0x66FFFFFF),
        fontSize: 15,
        fontWeight: FontWeight.w300,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xAAFFFFFF),
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: CheriflixColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: CheriflixTypography.bodyMedium.copyWith(
        color: CheriflixColors.textPrimary,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CheriflixColors.accentRed,
      linearTrackColor: Color(0x22FFFFFF),
      circularTrackColor: Color(0x22FFFFFF),
    ),
    iconTheme: const IconThemeData(color: CheriflixColors.textPrimary),
  );
}
