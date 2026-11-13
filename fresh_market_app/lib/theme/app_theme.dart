import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Colour tokens. A calm white canvas, black (ink) type and ONE accent,
/// green, used with discipline.
///
/// Green is only for: add (+) buttons and quantity steppers, the buying
/// calls to action (Add to cart, Checkout, Deliver to <area>, Start
/// shopping, Add all to cart), Express (bolt icon, ETA text),
/// delivery-promise highlights, success notices, the cart badge and the
/// active-tab indicator. Everything else is ink, grey or white.
///
/// Contrast (WCAG): ink on canvas 18.9:1; [secondary] on canvas 6.4:1 and
/// on [subtle] 5.9:1; white on [green] 5.3:1; [green] text on canvas 5.3:1,
/// on [subtle] 4.9:1 and on [greenSoft] 4.7:1; white on [saving] 5.2:1 and
/// [saving] text on canvas 5.2:1; [navInactive] on ink 8.3:1. [tertiary]
/// (3.3:1) is for icons, decoration and large text only.
abstract final class AppColors {
  /// The page background on every screen.
  static const Color canvas = Color(0xFFFFFFFF);

  /// White surfaces on the canvas: cards, sheets, inputs that sit on
  /// [subtle], round buttons. The same white as [canvas].
  static const Color surface = Color(0xFFFFFFFF);

  /// Warm off-white: image wells, category tiles, the search field,
  /// segmented-control track, info cards, assistant bubbles.
  static const Color subtle = Color(0xFFF5F6F2);

  /// 1px card borders and dividers.
  static const Color hairline = Color(0xFFE8E9E4);

  /// Text, the brand, heading tags, selected states, the bottom bar.
  static const Color ink = Color(0xFF111111);

  /// Secondary text (size lines, captions, hints). 6.4:1 on canvas.
  static const Color secondary = Color(0xFF5C6159);

  /// Icons, decoration and large text only (3.3:1 on canvas).
  static const Color tertiary = Color(0xFF8A8F86);

  /// THE accent. White text on it is 5.3:1. See the class comment for the
  /// only places it may be used.
  static const Color green = Color(0xFF0E7C3A);

  /// Pressed / hover state of [green] fills.
  static const Color greenPressed = Color(0xFF0A6830);

  /// Behind small green text (an "Express" tag).
  static const Color greenSoft = Color(0xFFE8F4EC);

  /// Deep orange for the discount badge and the sale price (not red).
  /// White text on it is 5.2:1.
  static const Color saving = Color(0xFFC2410C);

  /// Text and icons on [ink], [green] and [saving] fills.
  static const Color onDark = Color(0xFFFFFFFF);

  /// Inactive icons and labels on the ink bottom bar (8.3:1 on ink).
  static const Color navInactive = Color(0xFFA9ADA4);

  /// Disabled fills (buttons, tiles) and their text / icons.
  static const Color disabledFill = Color(0xFFEDEEE9);
  static const Color disabledText = Color(0xFF8A8F86);

  /// Loading skeleton blocks.
  static const Color skeleton = Color(0xFFEDEEE9);
}

/// Spacing, radii and sizes shared by every screen (8pt grid).
abstract final class AppDims {
  /// The one page gutter.
  static const double gutter = 16;

  /// Vertical space between Home sections.
  static const double sectionGap = 28;

  /// Space between a section heading and its content.
  static const double headingGap = 12;

  /// Radii: cards 14, image wells 12, buttons and inputs 12, banners and
  /// the map 16, chips and pills fully round.
  static const double cardRadius = 14;
  static const double wellRadius = 12;
  static const double buttonRadius = 12;
  static const double controlRadius = 12;
  static const double bannerRadius = 16;

  /// Minimum touch target.
  static const double touch = 44;

  /// Touch target of the controls shoppers hit most on cards and lines:
  /// the add (+) circle, the stepper's buttons and the favourite heart
  /// (Android's 48dp; the visible circles stay 36 and 32).
  static const double controlTarget = 48;

  /// Height of primary buttons and of the search field.
  static const double buttonHeight = 52;
  static const double fieldHeight = 48;

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
  static const BorderRadius wellBorderRadius =
      BorderRadius.all(Radius.circular(wellRadius));
  static const BorderRadius buttonBorderRadius =
      BorderRadius.all(Radius.circular(buttonRadius));
  static const BorderRadius controlBorderRadius =
      BorderRadius.all(Radius.circular(controlRadius));
  static const BorderRadius bannerBorderRadius =
      BorderRadius.all(Radius.circular(bannerRadius));
  static const BorderRadius pillBorderRadius =
      BorderRadius.all(Radius.circular(999));
}

/// Shadows. Cards get a barely-there lift; floating things a soft one.
abstract final class AppShadows {
  /// Cards: 0 1 3 rgba(0,0,0,.05).
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  /// Small raised controls on a tinted track (the selected segment of the
  /// mode switch, round white buttons on an image).
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Floating surfaces: the bottom bar and the Ask pill.
  static const List<BoxShadow> float = [
    BoxShadow(color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Sticky bottom bars (product detail, location picker): a soft shadow
  /// cast upwards.
  static const List<BoxShadow> sticky = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -2)),
  ];
}

/// Type scale. Every style uses the bundled Inter family with the bundled
/// "Dirham" family as fallback, so the UAE Dirham sign (U+20C3) renders
/// anywhere.
abstract final class AppText {
  static const String family = 'Inter';

  /// The family that has the Dirham sign.
  static const String dirhamFamily = 'Dirham';
  static const List<String> fallback = [dirhamFamily];

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// 24/800 -0.3: screen titles and the product title.
  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: -0.3,
  );

  /// 18/800: section heading text, app bar titles, empty-state titles.
  static const TextStyle heading = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: -0.2,
  );

  /// 16/700: headings inside cards (summary card, info cards).
  static const TextStyle cardHeading = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 15/400: body text.
  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 14/400: dense body text (rows, info cards, notes).
  static const TextStyle bodySmall = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 14/500: card titles (product names), two lines at most.
  static const TextStyle productName = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// Same as [productName]: the spec's "card title 14/500".
  static const TextStyle cardTitle = productName;

  /// 12/500: captions and size lines, in [AppColors.secondary].
  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: AppColors.secondary,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 13/600: chip and pill labels, small buttons.
  static const TextStyle label = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 13,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 16/800, tabular figures: prices on cards and rows.
  static const TextStyle price = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    fontFeatures: _tabular,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 24/800, tabular figures: the price on product detail.
  static const TextStyle priceLarge = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: -0.3,
    fontFeatures: _tabular,
  );

  /// 12/500 struck-through old price. Secondary rather than tertiary so the
  /// text keeps 4.5:1.
  static const TextStyle oldPrice = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: AppColors.secondary,
    decoration: TextDecoration.lineThrough,
    decorationColor: AppColors.secondary,
    fontFeatures: _tabular,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 16/700 label of primary buttons (colour from the button).
  static const TextStyle button = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w700,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 14/600 label of secondary and small buttons (colour from the button).
  static const TextStyle buttonSmall = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 14,
    height: 1.25,
    fontWeight: FontWeight.w600,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 14/600 ink text link ("See all", "Change").
  static const TextStyle link = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 12/600 ink label under category and brand tiles (sentence case, two
  /// lines at most).
  static const TextStyle tileLabel = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 11/700 bottom bar label (colour from the bar).
  static const TextStyle navLabel = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );

  /// 11/700 small tags and badges ("Express", "−46%"; colour from the tag).
  static const TextStyle tag = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    // Explicit 0: otherwise Material 3 typography adds 0.1-0.5 of
    // tracking through the inherited text style.
    letterSpacing: 0,
  );
}

/// Ready-made decorations.
abstract final class AppDecor {
  /// White card: radius 14, 1px hairline, very soft shadow.
  static const BoxDecoration card = BoxDecoration(
    color: AppColors.surface,
    borderRadius: AppDims.cardBorderRadius,
    border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
    boxShadow: AppShadows.card,
  );

  /// Subtle info card (delivery summaries, notes): off-white, radius 12,
  /// no border.
  static const BoxDecoration info = BoxDecoration(
    color: AppColors.subtle,
    borderRadius: AppDims.wellBorderRadius,
  );

  /// Subtle image well: off-white, radius 12.
  static const BoxDecoration well = BoxDecoration(
    color: AppColors.subtle,
    borderRadius: AppDims.wellBorderRadius,
  );

  /// White sticky bottom bar with a hairline on top.
  static const BoxDecoration stickyBar = BoxDecoration(
    color: AppColors.surface,
    border: Border(top: BorderSide(color: AppColors.hairline)),
  );

  /// The shape of cards (for `Material(shape: ...)`).
  static const RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: AppDims.cardBorderRadius,
    side: BorderSide(color: AppColors.hairline),
  );

  /// Soft shadow under floating white surfaces (bottom bar, cart summary).
  static const List<BoxShadow> floatShadow = AppShadows.float;
}

/// Button styles beyond the theme defaults. The theme's [FilledButton] is
/// the green buying CTA, [OutlinedButton] the ink outline, [TextButton] an
/// ink text link.
abstract final class AppButtons {
  /// Green filled, white label: the buying CTAs (theme default for
  /// FilledButton).
  ///
  /// Pressed, hovered and focused fills are the [AppColors.greenPressed]
  /// token rather than a white overlay (which would make an off-palette
  /// green).
  static ButtonStyle get primary => FilledButton.styleFrom(
        foregroundColor: AppColors.onDark,
        disabledForegroundColor: AppColors.disabledText,
        minimumSize: const Size(64, AppDims.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.buttonBorderRadius,
        ),
        textStyle: AppText.button,
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.disabledFill;
          }
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return AppColors.greenPressed;
          }
          return AppColors.green;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      );

  /// Ink filled, white label: strong actions that are not buying (send).
  static ButtonStyle get dark => FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.onDark,
        disabledBackgroundColor: AppColors.disabledFill,
        disabledForegroundColor: AppColors.disabledText,
        minimumSize: const Size(64, AppDims.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.buttonBorderRadius,
        ),
        textStyle: AppText.button,
      );

  /// Ink outline on white (theme default for OutlinedButton): "Start
  /// shopping" on empty states, "Discover now", destructive confirms.
  static ButtonStyle get outline => OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        disabledForegroundColor: AppColors.disabledText,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: const BorderSide(color: AppColors.ink, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.buttonBorderRadius,
        ),
        textStyle: AppText.buttonSmall,
      );

  /// Fully round ink outline pill (assistant action pills).
  static ButtonStyle get outlinePill => outline.copyWith(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        minimumSize: const WidgetStatePropertyAll(Size(64, AppDims.touch)),
      );

  /// White pill with a hairline (sort pill, chips).
  static ButtonStyle get chip => OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        minimumSize: const Size(44, AppDims.touch),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: const BorderSide(color: AppColors.hairline),
        shape: const StadiumBorder(),
        textStyle: AppText.label,
      );
}

/// Status bar style for the white canvas.
const SystemUiOverlayStyle appOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarIconBrightness: Brightness.dark,
);

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    // Ink, not green: default Material widgets (switches, checkboxes,
    // focus rings, spinners) stay neutral. The green buying button is set
    // explicitly below.
    primary: AppColors.ink,
    onPrimary: AppColors.onDark,
    primaryContainer: AppColors.subtle,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.ink,
    onSecondary: AppColors.onDark,
    secondaryContainer: AppColors.subtle,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.green,
    onTertiary: AppColors.onDark,
    tertiaryContainer: AppColors.greenSoft,
    onTertiaryContainer: AppColors.green,
    // No red anywhere: errors are said in ink.
    error: AppColors.ink,
    onError: AppColors.onDark,
    errorContainer: AppColors.subtle,
    onErrorContainer: AppColors.ink,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.secondary,
    surfaceDim: AppColors.subtle,
    surfaceBright: AppColors.surface,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.subtle,
    surfaceContainerHigh: AppColors.subtle,
    surfaceContainerHighest: AppColors.subtle,
    surfaceTint: Color(0x00000000),
    outline: AppColors.hairline,
    outlineVariant: AppColors.hairline,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.onDark,
    inversePrimary: AppColors.navInactive,
  );
  final outlinedBorder = OutlineInputBorder(
    borderRadius: AppDims.controlBorderRadius,
    borderSide: BorderSide.none,
  );
  const textTheme = TextTheme(
    headlineSmall: AppText.title,
    titleLarge: AppText.heading,
    titleMedium: AppText.cardHeading,
    titleSmall: AppText.productName,
    bodyLarge: AppText.body,
    bodyMedium: AppText.body,
    bodySmall: AppText.caption,
    labelLarge: AppText.button,
    labelMedium: AppText.label,
    labelSmall: AppText.tag,
  );

  return ThemeData(
    useMaterial3: true,
    // Standard on every platform: Flutter web on desktop would otherwise
    // pick compact density and draw every button 8pt shorter than on the
    // phone.
    visualDensity: VisualDensity.standard,
    colorScheme: scheme,
    fontFamily: AppText.family,
    // Applied to every text theme, so plain Text widgets (and the
    // assistant's sentences) render the Dirham sign too.
    fontFamilyFallback: AppText.fallback,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    dividerColor: AppColors.hairline,
    splashFactory: InkRipple.splashFactory,
    textTheme: textTheme.apply(fontFamilyFallback: AppText.fallback),
    primaryTextTheme: textTheme.apply(fontFamilyFallback: AppText.fallback),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.heading,
      systemOverlayStyle: appOverlayStyle,
    ),
    filledButtonTheme: FilledButtonThemeData(style: AppButtons.primary),
    outlinedButtonTheme: OutlinedButtonThemeData(style: AppButtons.outline),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(AppDims.touch, AppDims.touch),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.buttonBorderRadius,
        ),
        textStyle: AppText.link,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(AppDims.touch, AppDims.touch),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.surface,
      disabledColor: AppColors.disabledFill,
      side: BorderSide(color: AppColors.hairline),
      shape: StadiumBorder(),
      labelStyle: AppText.label,
      checkmarkColor: AppColors.ink,
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.subtle,
      hintStyle: AppText.body.copyWith(color: AppColors.secondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: outlinedBorder,
      enabledBorder: outlinedBorder,
      focusedBorder: const OutlineInputBorder(
        borderRadius: AppDims.controlBorderRadius,
        borderSide: BorderSide(color: AppColors.ink, width: 1.5),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.ink,
      selectionColor: Color(0x33111111),
      selectionHandleColor: AppColors.ink,
    ),
    // Ink: a spinner is not an accent.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
      linearTrackColor: AppColors.hairline,
      circularTrackColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.surface,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: AppText.bodySmall.copyWith(color: AppColors.onDark),
      // Green on ink would be under 4.5:1; the action is white and bold.
      actionTextColor: AppColors.onDark,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDims.buttonBorderRadius,
      ),
    ),
  );
}
