import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Colour tokens of the approved design. Every colour comes from THE
/// FRESH MARKET logo: a black wordmark on a lime half-circle, on white.
abstract final class AppColors {
  /// Page background on every screen: a mild tint of the logo's lime.
  static const Color page = Color(0xFFEFF5DA);

  /// Deeper lime tint used by category tiles and quiet controls.
  static const Color tile = Color(0xFFDDEBB0);

  /// 1px border of cards, tiles and the bottom bar.
  static const Color border = Color(0xFFCCDD98);

  /// Cards, inputs and the bottom bar.
  static const Color surface = Color(0xFFFFFFFF);

  /// The logo's black: text, black heading tags, sale pills, the Ask
  /// button. Also the text and icons on [lime].
  static const Color ink = Color(0xFF111111);
  static const Color secondary = Color(0xFF4E5641);
  static const Color body = Color(0xFF33392A);

  /// The logo's lime: primary buttons, add buttons, the active tab, lime
  /// heading tags and the cart badge. Never put white on it: text and
  /// icons on lime are [ink].
  static const Color lime = Color(0xFFB8D432);

  /// Dark olive (the store website's own pin colour) for green text and
  /// small accent icons on white or light backgrounds: links, "View all",
  /// sale prices. Lime itself is too light for text.
  static const Color olive = Color(0xFF4F6B00);

  /// Category tile label.
  static const Color tileLabel = Color(0xFF2E3B00);

  /// Disabled fills and text.
  static const Color disabledFill = Color(0xFFE8EBE0);
  static const Color disabledText = Color(0xFF8A9080);
}

/// Spacing, radii and sizes shared by every screen.
abstract final class AppDims {
  /// The one page gutter.
  static const double gutter = 16;

  static const double cardRadius = 12;
  static const double controlRadius = 10;

  /// Minimum touch target.
  static const double touch = 44;

  /// Space the floating bottom bar needs below scrollable content, before
  /// the device's own bottom inset.
  static const double navBarClearance = 100;

  /// Bottom padding for scrollable content on screens shown with the
  /// floating bottom bar (tab screens, lists, search).
  static double bottomBarSpace(BuildContext context) =>
      navBarClearance + MediaQuery.viewPaddingOf(context).bottom;

  /// Height of the floating Ask button plus the gap between it and the
  /// bottom bar (AskButton.height + AskButton.gapAboveNavBar).
  static const double askButtonClearance = 60;

  /// Bottom padding for scrollable content on screens that also show the
  /// Ask button above the bottom bar, so the last row can scroll clear of
  /// it.
  static double floatingSpace(BuildContext context) =>
      bottomBarSpace(context) + askButtonClearance;

  static const BorderRadius cardBorderRadius =
      BorderRadius.all(Radius.circular(cardRadius));
  static const BorderRadius controlBorderRadius =
      BorderRadius.all(Radius.circular(controlRadius));
}

/// Type scale. All styles use the bundled Inter family.
abstract final class AppText {
  static const String family = 'Inter';

  /// 24/800: screen titles and the product title.
  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: -0.3,
  );

  /// 20/800: section headings and list titles.
  static const TextStyle heading = TextStyle(
    fontFamily: family,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: -0.2,
  );

  /// 16/700: card headings.
  static const TextStyle cardHeading = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// 14/400: body text.
  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.body,
  );

  /// 14/500: product names.
  static const TextStyle productName = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
  );

  /// 12/500: captions and size lines.
  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: AppColors.secondary,
  );

  /// 16/800: prices on cards and rows.
  static const TextStyle price = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );

  /// 12px struck-through old price.
  static const TextStyle oldPrice = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: AppColors.secondary,
    decoration: TextDecoration.lineThrough,
    decorationColor: AppColors.secondary,
  );

  /// 16/700 label of primary buttons.
  static const TextStyle button = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );

  /// 14/700 olive text link ("View all").
  static const TextStyle link = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.olive,
  );

  /// 11/700 uppercase category tile label.
  static const TextStyle tileLabel = TextStyle(
    fontFamily: family,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.tileLabel,
    letterSpacing: 0.4,
  );
}

/// Ready-made decorations.
abstract final class AppDecor {
  /// White card: radius 12, 1px border.
  static const BoxDecoration card = BoxDecoration(
    color: AppColors.surface,
    borderRadius: AppDims.cardBorderRadius,
    border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
  );

  /// Soft shadow under floating white surfaces (bottom bar, cart summary).
  static const List<BoxShadow> floatShadow = [
    BoxShadow(color: Color(0x1F2E3B00), blurRadius: 20, offset: Offset(0, 6)),
  ];
}

/// Status bar style for the light lime page background.
const SystemUiOverlayStyle appOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarIconBrightness: Brightness.dark,
);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.lime,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.lime,
    onPrimary: AppColors.ink,
    primaryContainer: AppColors.tile,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.olive,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.tile,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.ink,
    onTertiary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.secondary,
    // No red anywhere: errors are said in ink.
    error: AppColors.ink,
    onError: Colors.white,
    errorContainer: AppColors.tile,
    onErrorContainer: AppColors.ink,
    outline: AppColors.border,
  );
  const buttonShape = RoundedRectangleBorder(
    borderRadius: AppDims.controlBorderRadius,
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: AppDims.controlBorderRadius,
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppText.family,
    scaffoldBackgroundColor: AppColors.page,
    canvasColor: AppColors.page,
    dividerColor: AppColors.border,
    splashFactory: InkRipple.splashFactory,
    textTheme: const TextTheme(
      headlineSmall: AppText.title,
      titleLarge: AppText.heading,
      titleMedium: AppText.cardHeading,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.caption,
      labelLarge: AppText.button,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.page,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.heading,
      systemOverlayStyle: appOverlayStyle,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.lime,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.disabledFill,
        disabledForegroundColor: AppColors.disabledText,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: buttonShape,
        textStyle: AppText.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: const BorderSide(color: AppColors.border),
        shape: buttonShape,
        textStyle: AppText.button.copyWith(fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.olive,
        minimumSize: const Size(AppDims.touch, AppDims.touch),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: buttonShape,
        textStyle: AppText.link,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(AppDims.touch, AppDims.touch),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: AppText.body.copyWith(color: AppColors.secondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder(AppColors.border),
      enabledBorder: inputBorder(AppColors.border),
      focusedBorder: inputBorder(AppColors.olive, 1.5),
    ),
    // The default cursor would be lime (primary), too faint on white and
    // the page; the selection is a translucent lime under ink text.
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.olive,
      selectionColor: Color(0x80B8D432),
      selectionHandleColor: AppColors.olive,
    ),
    // Olive, not lime: a spinner must stand out on white and the page.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.olive,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: AppText.body.copyWith(color: Colors.white),
      actionTextColor: AppColors.lime,
      behavior: SnackBarBehavior.floating,
      shape: buttonShape,
    ),
  );
}
