/// Formats an amount held in minor units (fils) the way the store shows it:
/// `Dhs. 12.50`, `Dhs. 1,250.00`.
String formatMoney(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}Dhs. $grouped.$fraction';
}

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
