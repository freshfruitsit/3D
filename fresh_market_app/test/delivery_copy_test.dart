import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery_copy.dart';
import 'package:fresh_market_app/delivery/delivery_rules.dart';
import 'package:fresh_market_app/models/product.dart';

/// A UTC moment at UAE wall-clock [hour]:[minute] (UTC+4).
DateTime uae(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 13, hour - 4, minute);

DeliveryArea area(String name) => DeliveryConfig.areaNamed(name)!;

void main() {
  final mirdif = area('Mirdif');
  final jebelAli = area('Jebel Ali');
  const express = Product(
    id: 1,
    title: 'Kiwi',
    handle: 'kiwi',
    tags: ['1hr-delivery'],
  );
  const plain = Product(id: 2, title: 'Beef', handle: 'beef');

  group('header', () {
    test('mode subtitles', () {
      // (mode, area, now) -> text
      final table = <(DeliveryMode, DeliveryArea?, DateTime), String>{
        (DeliveryMode.market, null, uae(12)): 'Full range · same day',
        (DeliveryMode.market, mirdif, uae(10, 7)): 'Today by 4:15 PM',
        (DeliveryMode.market, mirdif, uae(18)): 'Tomorrow by 11 AM',
        (DeliveryMode.express, null, uae(12)): 'In about 60 min',
        (DeliveryMode.express, mirdif, uae(12)): '25–35 min',
        (DeliveryMode.express, mirdif, uae(7, 59)): 'Opens 8 AM',
        (DeliveryMode.express, mirdif, uae(22)): 'Opens 8 AM',
        (DeliveryMode.express, jebelAli, uae(12)): 'Not in your area',
      };
      table.forEach((input, want) {
        expect(
          DeliveryCopy.modeSubtitle(input.$1, input.$2, input.$3),
          want,
          reason: '$input',
        );
      });
    });

    test('chip and Express button state', () {
      expect(DeliveryCopy.chipLabel(null), 'Choose your area');
      expect(DeliveryCopy.chipLabel(mirdif), 'Mirdif');
      expect(DeliveryCopy.chipHint(null), '');
      expect(DeliveryCopy.chipHint(mirdif), 'Deliver to Mirdif, Dubai');
      expect(DeliveryCopy.expressOff(null), isFalse);
      expect(DeliveryCopy.expressOff(mirdif), isFalse);
      expect(DeliveryCopy.expressOff(jebelAli), isTrue);
      expect(DeliveryCopy.expressLive(mirdif, uae(12)), isTrue);
      expect(DeliveryCopy.expressLive(mirdif, uae(22)), isFalse);
      expect(DeliveryCopy.expressLive(jebelAli, uae(12)), isFalse);
      expect(
        DeliveryCopy.pickerTitle(hasArea: false),
        'Where should we deliver?',
      );
      expect(
        DeliveryCopy.pickerTitle(hasArea: true),
        'Change delivery location',
      );
    });
  });

  group('delivery bar', () {
    DeliveryBar bar(
      DeliveryArea? a,
      DeliveryMode m,
      DateTime now, [
      Product? product,
    ]) => DeliveryCopy.bar(area: a, mode: m, now: now, product: product);

    test('no location', () {
      final b = bar(null, DeliveryMode.market, uae(12));
      expect(b.kind, DeliveryBarKind.askLocation);
      expect(
        b.text,
        'Tell us where you are to see delivery times and Express '
        'availability.',
      );
      expect(
        b.message.first,
        const DeliveryTextPart('Tell us where you are', bold: true),
      );
      expect(b.actionLabel, 'Set location');
      expect(b.action, DeliveryBarAction.setLocation);
      expect(b.warn, isFalse);
    });

    test('Fresh Market before the cut-off', () {
      final b = bar(mirdif, DeliveryMode.market, uae(14, 40));
      expect(b.kind, DeliveryBarKind.marketToday);
      expect(b.text, 'Order now, get it today by 8:45 PM');
      expect(
        b.message.last,
        const DeliveryTextPart('today by 8:45 PM', bold: true),
      );
      expect(b.counterText, 'Same-day closes in 3h 20m');
      expect(b.actionLabel, 'Need it sooner? Express in 25–35 min');
      expect(b.action, DeliveryBarAction.express);

      final early = bar(mirdif, DeliveryMode.market, uae(6));
      expect(early.actionLabel, 'Express opens 8 AM');
      expect(early.action, DeliveryBarAction.express);

      final far = bar(jebelAli, DeliveryMode.market, uae(12));
      expect(far.actionLabel, isNull);
      expect(far.action, isNull);
      expect(far.counterText, 'Same-day closes in 6h 0m');
    });

    test('Fresh Market after the cut-off', () {
      final b = bar(mirdif, DeliveryMode.market, uae(19));
      expect(b.kind, DeliveryBarKind.marketTomorrow);
      expect(
        b.text,
        'Same-day orders closed at 6 PM. Order now, get it tomorrow '
        'morning before 11 AM',
      );
      expect(b.message.last.bold, isTrue);
      expect(b.counter, isEmpty);
      expect(b.actionLabel, 'Need it sooner? Express in 25–35 min');
      expect(
        bar(mirdif, DeliveryMode.market, uae(23)).actionLabel,
        'Express opens 8 AM',
      );
    });

    test('Express open, closed, and an item not on Express', () {
      final open = bar(mirdif, DeliveryMode.express, uae(12));
      expect(open.kind, DeliveryBarKind.express);
      expect(
        open.text,
        'Express: items marked 25–35 min reach you in under an hour',
      );
      expect(open.counterText, 'Open until 10 PM');
      expect(open.actionLabel, 'Full range: Today by 6 PM');
      expect(open.action, DeliveryBarAction.market);
      expect(open.warn, isFalse);
      // An Express item on its product page changes nothing.
      expect(
        bar(mirdif, DeliveryMode.express, uae(12), express).kind,
        DeliveryBarKind.express,
      );

      final closed = bar(mirdif, DeliveryMode.express, uae(22, 30));
      expect(closed.kind, DeliveryBarKind.expressClosed);
      expect(
        closed.text,
        'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
        'delivers tomorrow morning before 11 am.',
      );
      expect(closed.text, DeliveryRules.expressClosed(mirdif, uae(22, 30)));
      expect(closed.actionLabel, 'Switch to Fresh Market');
      expect(closed.warn, isTrue);

      final notOn = bar(mirdif, DeliveryMode.express, uae(12), plain);
      expect(notOn.kind, DeliveryBarKind.notOnExpress);
      expect(
        notOn.text,
        "This item isn't on Express. Fresh Market delivers it today "
        'within 6 hours.',
      );
      expect(notOn.action, DeliveryBarAction.market);
      expect(notOn.warn, isTrue);
    });
  });

  group('product page lines', () {
    test('Express line', () {
      expect(
        DeliveryCopy.productExpressLine(mirdif, uae(12)),
        'Get it in 25–35 min to Mirdif',
      );
      expect(
        DeliveryCopy.productExpressLine(mirdif, uae(23)),
        'Express opens 8 AM',
      );
      expect(
        DeliveryCopy.productExpressLine(jebelAli, uae(12)),
        "Express isn't available in Jebel Ali yet",
      );
    });

    test('Fresh Market line', () {
      expect(
        DeliveryCopy.productMarketLine(mirdif, uae(10)),
        'Today within 6 hours to Mirdif · by 4 PM',
      );
      expect(
        DeliveryCopy.productMarketLine(mirdif, uae(18)),
        'Tomorrow morning before 11 AM to Mirdif',
      );
    });
  });

  group('location picker summary', () {
    test('nothing picked', () {
      final s = DeliveryCopy.pickSummary(null, uae(12));
      expect(s.heading, 'What you get here');
      expect(s.placeLabel, isNull);
      expect(s.options.single.title, 'Pick an area first');
      expect(
        s.options.single.detail,
        'Search above, tap the map, or use your current location.',
      );
      expect(s.options.single.available, isFalse);
      expect(s.buttonLabel, 'Deliver here');
      expect(s.canConfirm, isFalse);
      expect(s.note, 'Pick an area to see delivery options.');
      expect(
        DeliveryCopy.pickSummary(
          null,
          uae(12),
          hasMap: false,
        ).options.single.detail,
        'Search above, or use your current location.',
      );
    });

    test('a spot we do not deliver to', () {
      final s = DeliveryCopy.pickSummary(
        DeliveryRules.placeFromPoint(24.0, 52.0),
        uae(12),
      );
      expect(s.heading, 'What you get in');
      expect(s.placeLabel, 'This spot');
      expect(s.options.single.title, "We don't deliver here yet");
      expect(
        s.options.single.detail,
        'We deliver across the seven emirates of the UAE. Move the pin or '
        'search another area.',
      );
      expect(s.canConfirm, isFalse);
      expect(s.buttonLabel, 'Deliver here');
      expect(s.note, 'This spot is outside our delivery area.');
    });

    test('an area in the Express zone, open and closed', () {
      final pick = DeliveryPlace.fromArea(mirdif);
      final s = DeliveryCopy.pickSummary(pick, uae(10, 7));
      expect(s.placeLabel, 'Mirdif, Dubai');
      expect(s.canConfirm, isTrue);
      expect(s.buttonLabel, 'Deliver to Mirdif');
      expect(s.note, 'You can change this any time from the header.');
      final market = s.options[0];
      expect(market.title, 'Fresh Market · full range');
      expect(
        market.detail,
        'Order now and it arrives by 4:15 PM · same-day cut-off 6 PM',
      );
      expect(market.when, 'Today within 6 hours');
      expect(market.available, isTrue);
      final ex = s.options[1];
      expect(ex.title, 'Express · selected items');
      expect(ex.detail, '7 km from our Ras Al Khor hub · open until 10 PM');
      expect(ex.when, '25–35 min');
      expect(ex.available, isTrue);

      final closed = DeliveryCopy.pickSummary(pick, uae(22)).options[1];
      expect(closed.detail, 'Closed now · runs 8 AM to 10 PM');
      expect(closed.when, 'From 8 AM');
      expect(closed.available, isTrue);
    });

    test('an area outside the Express zone', () {
      final s = DeliveryCopy.pickSummary(
        DeliveryPlace.fromArea(jebelAli),
        uae(19),
      );
      expect(s.options[0].when, 'Tomorrow morning before 11 AM');
      expect(
        s.options[0].detail,
        'Ordered after 6 PM, so it comes tomorrow morning',
      );
      expect(
        s.options[1].detail,
        'Outside the 20 km Express zone (38 km from the hub)',
      );
      expect(s.options[1].when, 'Not available');
      expect(s.options[1].available, isFalse);
      expect(s.canConfirm, isTrue);
    });
  });

  test('search status texts', () {
    expect(DeliveryCopy.searching(' marina '), 'Searching for “marina”…');
    expect(
      DeliveryCopy.nothingFound('zzz'),
      'Nothing found for “zzz”. Try a nearby landmark, street or '
      'area, or tap the map to drop the pin.',
    );
    expect(
      DeliveryCopy.nothingFound('zzz', hasMap: false),
      'Nothing found for “zzz”. Try a nearby landmark, street or '
      'area.',
    );
  });
}
