import 'package:flutter/foundation.dart';

import '../models/product.dart';
import 'delivery_rules.dart';

/// A run of text, bold where the website uses `<b>`.
@immutable
class DeliveryTextPart {
  const DeliveryTextPart(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  bool operator ==(Object other) =>
      other is DeliveryTextPart && other.text == text && other.bold == bold;

  @override
  int get hashCode => Object.hash(text, bold);

  @override
  String toString() => bold ? '<b>$text</b>' : text;
}

/// What the delivery bar's button does.
enum DeliveryBarAction {
  /// Open the location picker.
  setLocation,

  /// Switch to Fresh Market.
  market,

  /// Switch to Express.
  express,
}

/// Which delivery bar the website shows.
enum DeliveryBarKind {
  /// No location yet.
  askLocation,

  /// Express mode on a product page of an item that is not on Express.
  notOnExpress,

  /// Express mode while Express is closed.
  expressClosed,

  /// Express mode, open.
  express,

  /// Fresh Market before the same-day cut-off.
  marketToday,

  /// Fresh Market after the cut-off.
  marketTomorrow,
}

/// The website's delivery bar (under the header) as text parts.
@immutable
class DeliveryBar {
  const DeliveryBar({
    required this.kind,
    required this.message,
    this.counter = const [],
    this.actionLabel,
    this.action,
    this.warn = false,
  });

  final DeliveryBarKind kind;

  /// The main sentence.
  final List<DeliveryTextPart> message;

  /// The side counter ("Same-day closes in 3h 20m", "Open until 10 PM");
  /// empty when there is none.
  final List<DeliveryTextPart> counter;

  /// Button text ("Set location", "Switch to Fresh Market", ...), or null
  /// for no button.
  final String? actionLabel;
  final DeliveryBarAction? action;

  /// Shown in the warning style.
  final bool warn;

  /// [message] as plain text.
  String get text => message.map((p) => p.text).join();

  /// [counter] as plain text ('' when none).
  String get counterText => counter.map((p) => p.text).join();

  @override
  String toString() =>
      'DeliveryBar($kind, $text | $counterText | $actionLabel)';
}

/// One delivery option row of the location picker.
@immutable
class PickOption {
  const PickOption({
    required this.title,
    required this.detail,
    required this.when,
    required this.available,
  });

  /// "Fresh Market · full range" / "Express · selected items".
  final String title;

  /// Small text under the title.
  final String detail;

  /// Right-hand text ("Today within 6 hours", "25–35 min", "Not
  /// available").
  final String when;

  /// False draws the row as unavailable.
  final bool available;

  @override
  String toString() => 'PickOption($title | $detail | $when | $available)';
}

/// The "What you get" box of the location picker for the current pick.
@immutable
class PickSummary {
  const PickSummary({
    required this.heading,
    this.placeLabel,
    required this.options,
    required this.buttonLabel,
    required this.canConfirm,
    required this.note,
  });

  /// "What you get here" / "What you get in".
  final String heading;

  /// The place after [heading] ("Dubai Marina, Dubai"); null with no pick.
  final String? placeLabel;
  final List<PickOption> options;

  /// "Deliver here" / "Deliver to Dubai Marina".
  final String buttonLabel;
  final bool canConfirm;

  /// Line under the button.
  final String note;
}

/// The website's other delivery texts: header, delivery bar, product page
/// lines and the location picker.
abstract final class DeliveryCopy {
  static const String chooseArea = 'Choose your area';
  static const String panelTitle = 'Where should we deliver?';
  static const String panelTitleChange = 'Change delivery location';
  static const String locationNotShared =
      'Location wasn’t shared. Search for your area or tap the map.';
  static const String findingSpot = 'Finding this spot…';

  /// Title of the location picker.
  static String pickerTitle({required bool hasArea}) =>
      hasArea ? panelTitleChange : panelTitle;

  /// The location chip: area name, or "Choose your area".
  static String chipLabel(DeliveryArea? area) => area?.name ?? chooseArea;

  /// The chip's hint: "Deliver to Dubai Marina, Dubai" ('' with no area).
  static String chipHint(DeliveryArea? area) =>
      area == null ? '' : 'Deliver to ${area.label}';

  /// Second line of a mode button in the header.
  static String modeSubtitle(
    DeliveryMode mode,
    DeliveryArea? area,
    DateTime now,
  ) {
    switch (mode) {
      case DeliveryMode.market:
        return area == null
            ? 'Full range · same day'
            : DeliveryRules.market(area, now).slot;
      case DeliveryMode.express:
        if (area == null) return 'In about 60 min';
        final ex = DeliveryRules.express(area, now);
        if (!ex.covered) return 'Not in your area';
        return ex.open
            ? ex.range
            : 'Opens ${DeliveryRules.formatHour(DeliveryConfig.expressOpen)}';
    }
  }

  /// The Express mode button is shown as off (area outside the zone).
  static bool expressOff(DeliveryArea? area) =>
      area != null && !DeliveryRules.isCovered(area);

  /// The Express mode button is shown as live (covered and open).
  static bool expressLive(DeliveryArea? area, DateTime now) =>
      area != null && DeliveryRules.express(area, now).available;

  /// The delivery bar. Pass [product] on a product page so Express mode
  /// can say when that item is not on Express.
  static DeliveryBar bar({
    required DeliveryArea? area,
    required DeliveryMode mode,
    required DateTime now,
    Product? product,
  }) {
    const b = DeliveryTextPart.new;
    if (area == null) {
      return const DeliveryBar(
        kind: DeliveryBarKind.askLocation,
        message: [
          DeliveryTextPart('Tell us where you are', bold: true),
          DeliveryTextPart(' to see delivery times and Express availability.'),
        ],
        actionLabel: 'Set location',
        action: DeliveryBarAction.setLocation,
      );
    }
    final mk = DeliveryRules.market(area, now);
    final ex = DeliveryRules.express(area, now);
    final open = DeliveryRules.formatHour(DeliveryConfig.expressOpen);
    final close = DeliveryRules.formatHour(DeliveryConfig.expressClose);
    if (mode == DeliveryMode.express) {
      if (product != null && !DeliveryRules.isExpressEligible(product)) {
        return DeliveryBar(
          kind: DeliveryBarKind.notOnExpress,
          message: [
            b("This item isn't on Express.", bold: true),
            b(' Fresh Market delivers it ${mk.line.toLowerCase()}.'),
          ],
          actionLabel: 'Switch to Fresh Market',
          action: DeliveryBarAction.market,
          warn: true,
        );
      }
      if (!ex.open) {
        return DeliveryBar(
          kind: DeliveryBarKind.expressClosed,
          message: [
            b('Express is closed right now.', bold: true),
            b(' It runs $open to $close. Fresh Market delivers '),
            b(mk.line.toLowerCase(), bold: true),
            b('.'),
          ],
          actionLabel: 'Switch to Fresh Market',
          action: DeliveryBarAction.market,
          warn: true,
        );
      }
      return DeliveryBar(
        kind: DeliveryBarKind.express,
        message: [
          b('Express: items marked '),
          b(ex.range, bold: true),
          b(' reach you in under an hour'),
        ],
        counter: [b('Open until '), b(close, bold: true)],
        actionLabel: 'Full range: ${mk.slot}',
        action: DeliveryBarAction.market,
      );
    }
    final expressLabel = !ex.covered
        ? null
        : ex.open
        ? 'Need it sooner? Express in ${ex.range}'
        : 'Express opens $open';
    final expressAction = ex.covered ? DeliveryBarAction.express : null;
    if (mk.today) {
      return DeliveryBar(
        kind: DeliveryBarKind.marketToday,
        message: [b('Order now, get it '), b('today by ${mk.by}', bold: true)],
        counter: [b('Same-day closes in '), b(mk.left!, bold: true)],
        actionLabel: expressLabel,
        action: expressAction,
      );
    }
    final line = mk.line[0].toLowerCase() + mk.line.substring(1);
    return DeliveryBar(
      kind: DeliveryBarKind.marketTomorrow,
      message: [
        b(
          'Same-day orders closed at ${DeliveryRules.formatHour(mk.cutHour)}. '
          'Order now, get it ',
        ),
        b(line, bold: true),
      ],
      actionLabel: expressLabel,
      action: expressAction,
    );
  }

  /// The product page's Express line ("Get it in 25–35 min to Mirdif").
  static String productExpressLine(DeliveryArea area, DateTime now) {
    final ex = DeliveryRules.express(area, now);
    if (!ex.covered) return "Express isn't available in ${area.name} yet";
    return ex.open
        ? 'Get it in ${ex.range} to ${area.name}'
        : 'Express opens '
              '${DeliveryRules.formatHour(DeliveryConfig.expressOpen)}';
  }

  /// [productExpressLine] as the second row of the product page in Fresh
  /// Market mode: labelled "Express: Get it in 25–35 min to Mirdif" while
  /// Express can deliver; otherwise the website's own text as is ("Express
  /// opens 8 AM", "Express isn't available in Jebel Ali yet"), which
  /// already names Express.
  static String productExpressLabelled(DeliveryArea area, DateTime now) {
    final line = productExpressLine(area, now);
    return DeliveryRules.express(area, now).available ? 'Express: $line' : line;
  }

  /// The Fresh Market part of the assistant's delivery answer, with the
  /// same-day cut-off in the delivery bar's words: "Today within 6 hours,
  /// by 4 PM. Same-day closes in 8h 0m (cut-off 6 PM)" before it,
  /// "Tomorrow morning before 11 AM. Same-day orders closed at 6 PM"
  /// after it.
  static String marketAnswer(DeliveryArea area, DateTime now) {
    final mk = DeliveryRules.market(area, now);
    final cut = DeliveryRules.formatHour(mk.cutHour);
    return mk.today
        ? '${mk.line}, by ${mk.by}. Same-day closes in ${mk.left} '
              '(cut-off $cut)'
        : '${mk.line}. Same-day orders closed at $cut';
  }

  /// The product page's Fresh Market line
  /// ("Today within 6 hours to Mirdif · by 4 PM").
  static String productMarketLine(DeliveryArea area, DateTime now) {
    final mk = DeliveryRules.market(area, now);
    return mk.today
        ? '${mk.line} to ${area.name} · by ${mk.by}'
        : '${mk.line} to ${area.name}';
  }

  /// The "What you get" box of the location picker for [pick].
  static PickSummary pickSummary(
    DeliveryPlace? pick,
    DateTime now, {
    bool hasMap = true,
  }) {
    if (pick == null) {
      return PickSummary(
        heading: 'What you get here',
        options: [
          PickOption(
            title: 'Pick an area first',
            detail:
                'Search above, ${hasMap ? 'tap the map, ' : ''}'
                'or use your current location.',
            when: '',
            available: false,
          ),
        ],
        buttonLabel: 'Deliver here',
        canConfirm: false,
        note: 'Pick an area to see delivery options.',
      );
    }
    final area = pick.toArea();
    if (area == null) {
      return PickSummary(
        heading: 'What you get in',
        placeLabel: pick.name,
        options: const [
          PickOption(
            title: DeliveryRules.notDeliverableTitle,
            detail:
                '${DeliveryRules.notDeliverableText} '
                'Move the pin or search another area.',
            when: '',
            available: false,
          ),
        ],
        buttonLabel: 'Deliver here',
        canConfirm: false,
        note: 'This spot is outside our delivery area.',
      );
    }
    final mk = DeliveryRules.market(area, now);
    final ex = DeliveryRules.express(area, now);
    final open = DeliveryRules.formatHour(DeliveryConfig.expressOpen);
    final close = DeliveryRules.formatHour(DeliveryConfig.expressClose);
    final km = ex.km.round();
    return PickSummary(
      heading: 'What you get in',
      placeLabel: area.label,
      options: [
        PickOption(
          title: 'Fresh Market · full range',
          detail: mk.sub,
          when: mk.line,
          available: true,
        ),
        PickOption(
          title: 'Express · selected items',
          detail: !ex.covered
              ? 'Outside the ${DeliveryConfig.expressKm.round()} km Express '
                    'zone ($km km from the hub)'
              : ex.open
              ? '$km km from our ${DeliveryConfig.hubName} '
                    '· open until $close'
              : 'Closed now · runs $open to $close',
          when: !ex.covered
              ? 'Not available'
              : ex.open
              ? ex.range
              : 'From $open',
          available: ex.covered,
        ),
      ],
      buttonLabel: 'Deliver to ${area.name}',
      canConfirm: true,
      note: 'You can change this any time from the header.',
    );
  }

  /// Search status line: "Searching for “marina”…".
  static String searching(String term) => 'Searching for “${term.trim()}”…';

  /// Shown when a search finds nothing.
  static String nothingFound(String term, {bool hasMap = true}) =>
      'Nothing found for “${term.trim()}”. Try a nearby landmark, '
      'street or area${hasMap ? ', or tap the map to drop the pin' : ''}.';
}
