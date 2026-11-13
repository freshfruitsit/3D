import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery_rules.dart';
import 'package:fresh_market_app/models/product.dart';

/// A UTC moment at UAE wall-clock [hour]:[minute] on 13 Nov 2026 (UAE is
/// UTC+4, so 02:00 UAE is 22:00 UTC the day before).
DateTime uae(int hour, [int minute = 0, int day = 13]) =>
    DateTime.utc(2026, 11, day, hour - 4, minute);

DeliveryArea area(String name) => DeliveryConfig.areaNamed(name)!;

Product product({List<String> tags = const []}) =>
    Product(id: 1, title: 'Item', handle: 'item', tags: tags);

void main() {
  final marina = area('Dubai Marina');
  final downtown = area('Downtown Dubai');
  final mirdif = area('Mirdif');
  final jebelAli = area('Jebel Ali');
  final nahyan = area('Al Nahyan');

  group('config', () {
    test('has the website\'s 20 areas in its order', () {
      expect(DeliveryConfig.areas, hasLength(20));
      expect(DeliveryConfig.areas.first.name, 'Dubai Marina');
      expect(DeliveryConfig.areas.last.name, 'Al Faseel');
      expect(area('Al Jimi (Al Ain)').emirate, Emirate.abuDhabi);
      expect(area('Business Bay').lat, 25.185);
      expect(area('Business Bay').lng, 55.265);
      expect(area('Al Majaz').lng, 55.385);
      final counts = <Emirate, int>{};
      for (final a in DeliveryConfig.areas) {
        counts[a.emirate] = (counts[a.emirate] ?? 0) + 1;
      }
      expect(counts, {
        Emirate.dubai: 9,
        Emirate.abuDhabi: 5,
        Emirate.sharjah: 2,
        Emirate.ajman: 1,
        Emirate.ummAlQuwain: 1,
        Emirate.rasAlKhaimah: 1,
        Emirate.fujairah: 1,
      });
    });

    test('emirate codes and names', () {
      final table = {
        'dubai': 'Dubai',
        'auh': 'Abu Dhabi',
        'shj': 'Sharjah',
        'ajm': 'Ajman',
        'uaq': 'Umm Al Quwain',
        'rak': 'Ras Al Khaimah',
        'fuj': 'Fujairah',
      };
      for (final entry in table.entries) {
        expect(Emirate.fromCode(entry.key)!.label, entry.value);
      }
      expect(Emirate.fromCode('xx'), isNull);
      expect(Emirate.fromCode(null), isNull);
      expect(DeliveryConfig.cut.values.toSet(), {18});
      expect(DeliveryConfig.cut.keys.toSet(), Emirate.values.toSet());
    });

    test('emirate from address text', () {
      final table = <String?, Emirate?>{
        'Dubai': Emirate.dubai,
        'Abu Dhabi Emirate': Emirate.abuDhabi,
        'Al Ain Region': Emirate.abuDhabi,
        'Sharjah Emirate': Emirate.sharjah,
        'Ajman': Emirate.ajman,
        'Umm Al Quwain': Emirate.ummAlQuwain,
        'Ras Al Khaimah': Emirate.rasAlKhaimah,
        'FUJAIRAH': Emirate.fujairah,
        'Muscat': null,
        '': null,
        null: null,
      };
      table.forEach((text, want) {
        expect(Emirate.fromText(text), want, reason: '$text');
      });
    });

    test('placeLabel adds the emirate unless the name has it', () {
      expect(placeLabel('Dubai Marina', Emirate.dubai), 'Dubai Marina');
      expect(placeLabel('Downtown Dubai', Emirate.dubai), 'Downtown Dubai');
      expect(placeLabel('Mirdif', Emirate.dubai), 'Mirdif, Dubai');
      expect(placeLabel('Al Nahyan', Emirate.abuDhabi), 'Al Nahyan, Abu Dhabi');
      expect(
        placeLabel('Near Al Majaz', Emirate.sharjah),
        'Near Al Majaz, Sharjah',
      );
      expect(
        placeLabel('The Fresh Market', Emirate.dubai),
        'The Fresh Market, Dubai',
      );
      expect(placeLabel('This spot', null), 'This spot');
      expect(mirdif.label, 'Mirdif, Dubai');
      expect(area('Al Faseel').label, 'Al Faseel, Fujairah');
    });

    test('area JSON round trip and invalid input', () {
      expect(DeliveryArea.fromJson(mirdif.toJson()), mirdif);
      expect(mirdif.toJson(), {
        'name': 'Mirdif',
        'em': 'dubai',
        'lat': 25.22,
        'lng': 55.42,
      });
      expect(
        DeliveryArea.fromJson({
          'name': 'X',
          'em': 'dubai',
          'lat': 25,
          'lng': 55,
        }),
        const DeliveryArea(name: 'X', emirate: Emirate.dubai, lat: 25, lng: 55),
      );
      for (final bad in <Object?>[
        null,
        'Mirdif',
        {'name': 'X', 'em': 'nope', 'lat': 25.0, 'lng': 55.0},
        {'name': '', 'em': 'dubai', 'lat': 25.0, 'lng': 55.0},
        {'name': 'X', 'em': 'dubai', 'lat': '25', 'lng': 55.0},
        {'name': 'X', 'em': 'dubai', 'lat': 25.0},
        {'em': 'dubai', 'lat': 25.0, 'lng': 55.0},
      ]) {
        expect(DeliveryArea.fromJson(bad), isNull, reason: '$bad');
      }
    });
  });

  group('time', () {
    test('UAE hours are UTC+4 with no daylight saving', () {
      final table = <DateTime, double>{
        DateTime.utc(2026, 11, 13, 0, 0): 4,
        DateTime.utc(2026, 11, 13, 13, 59): 17 + 59 / 60,
        DateTime.utc(2026, 11, 13, 14, 0): 18,
        DateTime.utc(2026, 11, 13, 19, 59): 23 + 59 / 60,
        DateTime.utc(2026, 11, 13, 20, 0): 0,
        DateTime.utc(2026, 11, 12, 20, 30): 0.5,
        DateTime.utc(2026, 12, 31, 21, 15): 1.25,
        DateTime.utc(2026, 6, 21, 6, 7): 10 + 7 / 60,
        DateTime.utc(2026, 3, 29, 1, 30, 59): 5.5, // seconds are ignored
      };
      table.forEach((now, want) {
        expect(
          DeliveryRules.uaeHours(now),
          closeTo(want, 1e-9),
          reason: '$now',
        );
      });
      // A local DateTime is read as the same instant.
      final instant = DateTime.utc(2026, 11, 13, 6, 0);
      expect(DeliveryRules.uaeHours(instant.toLocal()), 10);
      // The test helper crosses midnight correctly.
      expect(uae(0, 30), DateTime.utc(2026, 11, 12, 20, 30));
      expect(DeliveryRules.uaeHours(uae(0, 30)), 0.5);
    });

    test('formatHour', () {
      final table = <num, String>{
        0: '12 AM',
        0.5: '12:30 AM',
        6.5: '6:30 AM',
        8: '8 AM',
        11: '11 AM',
        12: '12 PM',
        12.75: '12:45 PM',
        16.25: '4:15 PM',
        18: '6 PM',
        22: '10 PM',
        23.75: '11:45 PM',
        24: '12 AM',
        24.25: '12:15 AM',
        16 + 5 / 60: '4:05 PM',
      };
      table.forEach((h, want) {
        expect(DeliveryRules.formatHour(h), want, reason: '$h');
      });
    });

    test('formatLeft', () {
      final table = <num, String>{
        0: '0m',
        -1: '0m',
        1 / 60: '1m',
        0.75: '45m',
        1: '1h 0m',
        10: '10h 0m',
        3 + 20 / 60: '3h 20m',
        17.5: '17h 30m',
        18 - (7 + 59 / 60): '10h 1m',
      };
      table.forEach((h, want) {
        expect(DeliveryRules.formatLeft(h), want, reason: '$h');
      });
    });
  });

  group('distance and Express', () {
    test('km and ETA per area (values from the website\'s own maths)', () {
      final table = <String, (double, bool, int, String)>{
        'Dubai Marina': (24.782042, false, 55, '50–60 min'),
        'Downtown Dubai': (9.324910, true, 35, '30–40 min'),
        'Business Bay': (9.575684, true, 35, '30–40 min'),
        'Jumeirah': (12.526305, true, 40, '35–45 min'),
        'Al Barsha': (17.887507, true, 45, '40–50 min'),
        'Deira': (10.786138, true, 35, '30–40 min'),
        'Mirdif': (7.498334, true, 30, '25–35 min'),
        'Dubai Silicon Oasis': (6.968785, true, 30, '25–35 min'),
        'Jebel Ali': (38.230866, false, 75, '70–80 min'),
        'Al Nahyan': (126.546857, false, 210, '205–215 min'),
        'Al Majaz': (16.867663, true, 45, '40–50 min'),
        'Muwaileh': (16.124109, true, 45, '40–50 min'),
        'Al Nuaimiya': (25.042886, false, 60, '55–65 min'),
        'Al Faseel': (97.861320, false, 165, '160–170 min'),
      };
      final noon = uae(12);
      table.forEach((name, want) {
        final ex = DeliveryRules.express(area(name), noon);
        expect(ex.km, closeTo(want.$1, 1e-5), reason: name);
        expect(ex.covered, want.$2, reason: name);
        expect(ex.etaMinutes, want.$3, reason: name);
        expect(ex.range, want.$4, reason: name);
        expect(DeliveryRules.km(area(name)), ex.km);
        expect(DeliveryRules.isCovered(area(name)), want.$2, reason: name);
      });
      expect(DeliveryRules.km(marina, marina), 0);
      expect(
        DeliveryRules.km(marina, mirdif),
        DeliveryRules.km(mirdif, marina),
      );
    });

    test('ETA near the hub (never below the 15 minute floor)', () {
      final atHub = DeliveryRules.express(DeliveryConfig.hub, uae(12));
      expect(atHub.km, 0);
      expect(atHub.etaMinutes, 20);
      expect(atHub.range, '15–25 min');
      const near = GeoPoint(25.18 + 1 / 111.19492664, 55.36); // 1 km north
      expect(DeliveryRules.express(near, uae(12)).etaMinutes, 20);
    });

    test('covered at the 20 km edge', () {
      // Due north of the hub the distance is R * dLat exactly.
      GeoPoint north(double km) =>
          GeoPoint(25.18 + km / 6371 * 180 / 3.141592653589793, 55.36);
      final inside = north(19.99);
      final outside = north(20.01);
      expect(DeliveryRules.km(inside), closeTo(19.99, 1e-6));
      expect(DeliveryRules.km(outside), closeTo(20.01, 1e-6));
      expect(DeliveryRules.express(inside, uae(12)).covered, isTrue);
      expect(DeliveryRules.express(outside, uae(12)).covered, isFalse);
      // round((20 + 19.99 * 1.5) / 5) * 5 = 50
      expect(DeliveryRules.express(inside, uae(12)).etaMinutes, 50);
    });

    test('open from 8 AM until before 10 PM, UAE time', () {
      final table = <DateTime, bool>{
        uae(0, 30): false,
        uae(7, 59): false,
        uae(8, 0): true,
        uae(8, 1): true,
        uae(12): true,
        uae(21, 59): true,
        uae(22, 0): false,
        uae(22, 1): false,
        uae(23, 59): false,
      };
      table.forEach((now, open) {
        expect(DeliveryRules.express(mirdif, now).open, open, reason: '$now');
        expect(DeliveryRules.isExpressOpen(now), open, reason: '$now');
        expect(DeliveryRules.express(mirdif, now).available, open);
      });
      // Not covered is never available, even when open.
      expect(DeliveryRules.express(jebelAli, uae(12)).available, isFalse);
    });
  });

  group('Fresh Market promise', () {
    test('around the 6 PM cut-off and midnight', () {
      // (UAE time, today, slot, left)
      final table = <DateTime, (bool, String, String?)>{
        uae(0, 0): (true, 'Today by 6 AM', '18h 0m'),
        uae(0, 30): (true, 'Today by 6:30 AM', '17h 30m'),
        uae(3, 59): (true, 'Today by 10 AM', '14h 1m'),
        uae(7, 59): (true, 'Today by 2 PM', '10h 1m'),
        uae(8, 0): (true, 'Today by 2 PM', '10h 0m'),
        uae(10, 0): (true, 'Today by 4 PM', '8h 0m'),
        uae(10, 7): (true, 'Today by 4:15 PM', '7h 53m'),
        uae(13, 45): (true, 'Today by 7:45 PM', '4h 15m'),
        uae(15, 44): (true, 'Today by 9:45 PM', '2h 16m'),
        uae(16, 16): (true, 'Today by 10:30 PM', '1h 44m'),
        uae(17, 50): (true, 'Today by 12 AM', '10m'),
        uae(17, 59): (true, 'Today by 12 AM', '1m'),
        uae(18, 0): (false, 'Tomorrow by 11 AM', null),
        uae(18, 1): (false, 'Tomorrow by 11 AM', null),
        uae(21, 59): (false, 'Tomorrow by 11 AM', null),
        uae(22, 0): (false, 'Tomorrow by 11 AM', null),
        uae(23, 59): (false, 'Tomorrow by 11 AM', null),
        // 01:15 UAE on 1 Jan 2027 is 21:15 UTC on 31 Dec 2026.
        DateTime.utc(2026, 12, 31, 21, 15): (
          true,
          'Today by 7:15 AM',
          '16h 45m',
        ),
      };
      table.forEach((now, want) {
        final mk = DeliveryRules.market(marina, now);
        expect(mk.today, want.$1, reason: '$now');
        expect(mk.slot, want.$2, reason: '$now');
        expect(mk.left, want.$3, reason: '$now');
        expect(mk.cutHour, 18);
      });
    });

    test('today texts', () {
      final mk = DeliveryRules.market(mirdif, uae(10, 7));
      expect(mk.line, 'Today within 6 hours');
      expect(mk.short, 'Within 6 hrs');
      expect(mk.by, '4:15 PM');
      expect(mk.slot, 'Today by 4:15 PM');
      expect(
        mk.sub,
        'Order now and it arrives by 4:15 PM · same-day cut-off 6 PM',
      );
    });

    test('after the cut-off texts', () {
      final mk = DeliveryRules.market(nahyan, uae(18));
      expect(mk.today, isFalse);
      expect(mk.line, 'Tomorrow morning before 11 AM');
      expect(mk.slot, 'Tomorrow by 11 AM');
      expect(mk.short, 'Tomorrow by 11 AM');
      expect(mk.by, isNull);
      expect(mk.left, isNull);
      expect(mk.sub, 'Ordered after 6 PM, so it comes tomorrow morning');
    });

    test('every emirate uses its own cut-off (18 everywhere)', () {
      for (final e in Emirate.values) {
        expect(DeliveryRules.cutHour(e), 18);
        expect(DeliveryRules.marketFor(e, uae(17, 59)).today, isTrue);
        expect(DeliveryRules.marketFor(e, uae(18)).today, isFalse);
      }
    });
  });

  group('places from points', () {
    test('nearest area', () {
      final table = <(double, double), (String, double)>{
        (25.18, 55.36): ('Dubai Silicon Oasis', 6.9688),
        (25.08, 55.14): ('Dubai Marina', 0),
        (25.09, 55.15): ('Dubai Marina', 1.5002),
        (25.10, 55.16): ('Dubai Marina', 3.0004),
        (24.0, 52.0): ('Al Nahyan', 246.9110),
        (26.5, 56.0): ('Al Nakheel', 79.1060),
        (23.6, 58.4): ('Al Faseel', 269.3100),
      };
      table.forEach((point, want) {
        final n = DeliveryRules.nearestArea(point.$1, point.$2);
        expect(n.area.name, want.$1, reason: '$point');
        expect(n.km, closeTo(want.$2, 1e-4), reason: '$point');
      });
    });

    test('name, "Near …" and "This spot"', () {
      final table = <(double, double), (String, Emirate?)>{
        (25.08, 55.14): ('Dubai Marina', Emirate.dubai),
        (25.081, 55.141): ('Dubai Marina', Emirate.dubai),
        (25.09, 55.15): ('Dubai Marina', Emirate.dubai), // 1.5 km
        (25.10, 55.16): ('Near Dubai Marina', Emirate.dubai), // 3.0004 km
        (25.18, 55.36): ('Near Dubai Silicon Oasis', Emirate.dubai),
        (24.47, 54.38): ('Al Nahyan', Emirate.abuDhabi),
        (25.33, 55.385): ('Al Majaz', Emirate.sharjah),
        (26.5, 56.0): ('This spot', null), // 79 km from Al Nakheel
        (24.0, 52.0): ('This spot', null),
      };
      table.forEach((point, want) {
        final place = DeliveryRules.placeFromPoint(point.$1, point.$2);
        expect(place.name, want.$1, reason: '$point');
        expect(place.emirate, want.$2, reason: '$point');
        expect(place.deliverable, want.$2 != null);
        // The place keeps the exact point, not the area's.
        expect(place.lat, point.$1);
        expect(place.lng, point.$2);
      });
      final spot = DeliveryRules.placeFromPoint(24.0, 52.0);
      expect(spot.toArea(), isNull);
      expect(spot.label, 'This spot');
      expect(
        DeliveryRules.notDeliverableMessage,
        "We don't deliver here yet. We deliver across the seven emirates "
        'of the UAE.',
      );
      final near = DeliveryRules.placeFromPoint(25.10, 55.16).toArea()!;
      expect(near.label, 'Near Dubai Marina');
      expect(near.emirate, Emirate.dubai);
    });

    test('60 km limit', () {
      // Due north of Al Nakheel (25.79, 55.95).
      double north(double km) => 25.79 + km / 6371 * 180 / 3.141592653589793;
      expect(
        DeliveryRules.placeFromPoint(north(59.9), 55.95).name,
        'Near Al Nakheel',
      );
      expect(
        DeliveryRules.placeFromPoint(north(60.1), 55.95).name,
        'This spot',
      );
    });
  });

  group('products', () {
    test('Express eligibility is the 1hr-delivery tag, any case', () {
      final table = <List<String>, bool>{
        ['1hr-delivery']: true,
        ['AIR', '1HR-Delivery']: true,
        [' 1hr-delivery ']: true,
        ['1hr delivery']: false,
        ['express']: false,
        []: false,
      };
      table.forEach((tags, want) {
        expect(
          DeliveryRules.isExpressEligible(product(tags: tags)),
          want,
          reason: '$tags',
        );
      });
    });

    test('card line in Fresh Market mode', () {
      final fast = product(tags: ['1hr-delivery']);
      final slow = product();
      ProductPromise? p(Product item, DeliveryArea? a, DateTime now) =>
          DeliveryRules.productPromise(
            item,
            area: a,
            mode: DeliveryMode.market,
            now: now,
          );

      expect(p(fast, null, uae(12)), isNull);
      // Covered and open: the Express ETA is offered too.
      expect(
        p(fast, mirdif, uae(12)),
        const ProductPromise(
          kind: ProductPromiseKind.market,
          text: 'Within 6 hrs · or 30 min',
          highlight: 'or 30 min',
        ),
      );
      expect(
        p(fast, mirdif, uae(18, 30))!.text,
        'Tomorrow by 11 AM · or 30 min',
      );
      // Closed, not covered, or not an Express item: the market line only.
      expect(p(fast, mirdif, uae(7, 59))!.text, 'Within 6 hrs');
      expect(p(fast, mirdif, uae(22))!.text, 'Tomorrow by 11 AM');
      expect(p(fast, marina, uae(12))!.text, 'Within 6 hrs');
      expect(p(slow, mirdif, uae(12))!.text, 'Within 6 hrs');
      expect(p(slow, mirdif, uae(12))!.highlight, isNull);
      expect(p(fast, mirdif, uae(12))!.isExpress, isFalse);
    });

    test('card line in Express mode', () {
      final fast = product(tags: ['1hr-delivery']);
      final slow = product();
      ProductPromise? p(Product item, DeliveryArea? a, DateTime now) =>
          DeliveryRules.productPromise(
            item,
            area: a,
            mode: DeliveryMode.express,
            now: now,
          );

      expect(p(fast, null, uae(12)), isNull);
      expect(
        p(fast, downtown, uae(12)),
        const ProductPromise(
          kind: ProductPromiseKind.express,
          text: '30–40 min',
        ),
      );
      expect(p(fast, downtown, uae(12))!.isExpress, isTrue);
      expect(p(fast, downtown, uae(22))!.text, 'From 8 AM');
      expect(p(fast, downtown, uae(7, 59))!.text, 'From 8 AM');
      expect(
        p(slow, downtown, uae(12)),
        const ProductPromise(
          kind: ProductPromiseKind.marketOnly,
          text: 'Fresh Market · Within 6 hrs',
        ),
      );
      expect(
        p(slow, downtown, uae(19))!.text,
        'Fresh Market · Tomorrow by 11 AM',
      );
      expect(p(slow, downtown, uae(12))!.isExpress, isFalse);
    });
  });

  group('cart attributes', () {
    test('Fresh Market', () {
      expect(
        DeliveryRules.cartAttributes(mirdif, DeliveryMode.market, uae(10)),
        {
          'Delivery mode': 'Fresh Market',
          'Delivery area': 'Mirdif, Dubai',
          'Delivery promise': 'Today within 6 hours',
          'Delivery pin': '25.22000,55.42000',
        },
      );
      expect(
        DeliveryRules.cartAttributes(
          downtown,
          DeliveryMode.market,
          uae(18, 1),
        )['Delivery promise'],
        'Tomorrow morning before 11 AM',
      );
    });

    test('Express', () {
      expect(
        DeliveryRules.cartAttributes(downtown, DeliveryMode.express, uae(9)),
        {
          'Delivery mode': 'Express',
          'Delivery area': 'Downtown Dubai',
          'Delivery promise': '30–40 min',
          'Delivery pin': '25.20000,55.27000',
        },
      );
    });

    test('a picked point keeps 5 decimals', () {
      const pin = DeliveryArea(
        name: 'Near Mirdif',
        emirate: Emirate.dubai,
        lat: 25.2312345678,
        lng: 55.4,
      );
      final attrs = DeliveryRules.cartAttributes(
        pin,
        DeliveryMode.market,
        uae(12),
      );
      expect(attrs['Delivery pin'], '25.23123,55.40000');
      expect(attrs['Delivery area'], 'Near Mirdif, Dubai');
      expect(attrs.keys.toList(), [
        'Delivery mode',
        'Delivery area',
        'Delivery promise',
        'Delivery pin',
      ]);
    });
  });

  group('messages', () {
    test('match the website', () {
      expect(DeliveryRules.deliveringTo(mirdif), 'Delivering to Mirdif');
      expect(
        DeliveryRules.switchedToMarket(jebelAli),
        "Express isn't available in Jebel Ali. Switched to Fresh Market.",
      );
      expect(
        DeliveryRules.setLocationForExpress,
        'Set your location to check Express',
      );
      expect(
        DeliveryRules.expressNotCovered(jebelAli, uae(12)),
        "Express isn't available in Jebel Ali yet. Fresh Market delivers "
        'today within 6 hours.',
      );
      expect(
        DeliveryRules.expressClosed(mirdif, uae(7)),
        'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
        'delivers today within 6 hours.',
      );
      expect(
        DeliveryRules.expressClosed(mirdif, uae(22, 30)),
        'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
        'delivers tomorrow morning before 11 am.',
      );
    });

    test('modes', () {
      expect(DeliveryMode.fromCode('market'), DeliveryMode.market);
      expect(DeliveryMode.fromCode('express'), DeliveryMode.express);
      expect(DeliveryMode.fromCode('x'), isNull);
      expect(DeliveryMode.market.label, 'Fresh Market');
      expect(DeliveryMode.express.label, 'Express');
    });
  });
}
