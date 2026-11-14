/// The official UAE Dirham sign (U+20C3). It is drawn by the bundled
/// "Dirham" font, which every app text style lists as its fallback.
const String dirhamSign = '\u20C3';

/// The amount alone, grouped with commas: `12.50`, `1,250.00` (`-5.00`
/// below zero).
String formatAmount(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$grouped.$fraction';
}

/// Formats an amount held in minor units (fils) with the Dirham sign:
/// `\u20C3 12.50`, `\u20C3 1,250.00` (sign, space, amount). The space is a
/// no-break space ([moneySpace]), so a line never wraps between the sign
/// and its amount (at large text sizes too).
String formatMoney(int cents) =>
    '${cents < 0 ? '-' : ''}$dirhamSign$moneySpace${formatAmount(cents.abs())}';

/// The no-break space between the Dirham sign and the amount.
const String moneySpace = '\u00A0';

/// What a screen reader says for an amount: `AED 12.50`. Use it as the
/// `semanticsLabel` of any Text that shows [formatMoney].
String moneySemantics(int cents) =>
    '${cents < 0 ? '-' : ''}AED ${formatAmount(cents.abs())}';

/// Parses a price from any storefront shape into minor units.
///
/// `products.json` sends decimal strings (`"24.00"`), `/products/x.js` sends
/// integers already in minor units (`2400`). Empty or missing values give
/// null.
int? parseMoney(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    final text = value.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return null;
    return (parsed * 100).round();
  }
  return null;
}

/// Minor units as the decimal string `products.json` uses (`"24.00"`).
String moneyToDecimalString(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
