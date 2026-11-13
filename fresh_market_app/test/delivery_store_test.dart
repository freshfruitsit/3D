import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery_rules.dart';
import 'package:fresh_market_app/delivery/delivery_store.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A UTC moment at UAE wall-clock [hour]:[minute] (UTC+4).
DateTime uae(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 13, hour - 4, minute);

DeliveryArea area(String name) => DeliveryConfig.areaNamed(name)!;

Future<SharedPreferences> prefsWith([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Map<String, dynamic> saved(SharedPreferences prefs) =>
    jsonDecode(prefs.getString(DeliveryStore.prefsKey)!)
        as Map<String, dynamic>;

void main() {
  final mirdif = area('Mirdif');
  final downtown = area('Downtown Dubai');
  final jebelAli = area('Jebel Ali');
  const fast = Product(
    id: 1,
    title: 'Kiwi',
    handle: 'kiwi',
    tags: ['1hr-delivery'],
  );
  const slow = Product(id: 2, title: 'Beef', handle: 'beef');

  group('choosing', () {
    test('starts with no area in Fresh Market mode', () {
      final store = DeliveryStore(now: () => uae(12), refreshEvery: null);
      expect(store.area, isNull);
      expect(store.hasArea, isFalse);
      expect(store.mode, DeliveryMode.market);
      expect(store.isExpress, isFalse);
      expect(store.market, isNull);
      expect(store.express, isNull);
      expect(store.expressCovered, isFalse);
      expect(store.promiseFor(fast), isNull);
      expect(store.cartAttributes, isNull);
      expect(store.expressClosedNotice, isNull);
      expect(store.shouldAskForLocation, isTrue);
      store.markAskedForLocation();
      expect(store.shouldAskForLocation, isFalse);
    });

    test('Express needs a location, then an area in the zone', () {
      final store = DeliveryStore(now: () => uae(12), refreshEvery: null);
      var notified = 0;
      store.addListener(() => notified++);

      expect(
        store.setMode(DeliveryMode.express),
        'Set your location to check Express',
      );
      expect(store.mode, DeliveryMode.market);
      expect(notified, 0);

      expect(store.setArea(jebelAli), 'Delivering to Jebel Ali');
      expect(notified, 1);
      expect(
        store.setMode(DeliveryMode.express),
        "Express isn't available in Jebel Ali yet. Fresh Market delivers "
        'today within 6 hours.',
      );
      expect(store.mode, DeliveryMode.market);
      expect(notified, 1);

      expect(store.setArea(mirdif), 'Delivering to Mirdif');
      expect(store.expressCovered, isTrue);
      expect(store.setMode(DeliveryMode.express), isNull);
      expect(store.mode, DeliveryMode.express);
      expect(notified, 3);
      // Choosing the same mode again changes nothing.
      expect(store.setMode(DeliveryMode.express), isNull);
      expect(notified, 3);
      expect(store.setMode(DeliveryMode.market), isNull);
      expect(store.mode, DeliveryMode.market);
      expect(notified, 4);
      store.dispose();
    });

    test('moving out of the zone switches back to Fresh Market', () {
      final store = DeliveryStore(now: () => uae(12), refreshEvery: null);
      store.setArea(downtown);
      store.setMode(DeliveryMode.express);
      expect(store.setArea(mirdif), 'Delivering to Mirdif');
      expect(store.mode, DeliveryMode.express);
      expect(
        store.setArea(jebelAli),
        "Express isn't available in Jebel Ali. Switched to Fresh Market.",
      );
      expect(store.mode, DeliveryMode.market);
      expect(store.area, jebelAli);
    });

    test('Express can be chosen while closed and says so', () {
      var now = uae(21, 59);
      final store = DeliveryStore(now: () => now, refreshEvery: null);
      store.setArea(mirdif);
      expect(store.setMode(DeliveryMode.express), isNull);
      expect(store.expressClosedNotice, isNull);
      now = uae(22);
      expect(
        store.expressClosedNotice,
        'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
        'delivers tomorrow morning before 11 am.',
      );
      now = uae(7, 30);
      expect(
        store.expressClosedNotice,
        'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
        'delivers today within 6 hours.',
      );
      expect(store.setMode(DeliveryMode.market), isNull);
      expect(store.expressClosedNotice, isNull);
    });

    test('setPlace accepts only places we deliver to', () {
      final store = DeliveryStore(now: () => uae(12), refreshEvery: null);
      expect(store.setPlace(DeliveryRules.placeFromPoint(24.0, 52.0)), isNull);
      expect(store.area, isNull);
      final near = DeliveryRules.placeFromPoint(25.18, 55.36);
      expect(store.setPlace(near), 'Delivering to Near Dubai Silicon Oasis');
      expect(
        store.area,
        const DeliveryArea(
          name: 'Near Dubai Silicon Oasis',
          emirate: Emirate.dubai,
          lat: 25.18,
          lng: 55.36,
        ),
      );
      expect(store.shouldAskForLocation, isFalse);
    });
  });

  group('promises follow the clock', () {
    test('market and express getters', () {
      var now = uae(10, 7);
      final store = DeliveryStore(now: () => now, refreshEvery: null);
      store.setArea(mirdif);
      expect(store.market!.slot, 'Today by 4:15 PM');
      expect(store.market!.left, '7h 53m');
      expect(store.express!.range, '25–35 min');
      expect(store.express!.open, isTrue);
      now = uae(18);
      expect(store.market!.slot, 'Tomorrow by 11 AM');
      now = uae(22);
      expect(store.express!.open, isFalse);
    });

    test('promiseFor in Fresh Market mode', () {
      var now = uae(12);
      final store = DeliveryStore(now: () => now, refreshEvery: null);
      store.setArea(mirdif);
      expect(store.promiseFor(fast)!.text, 'Within 6 hrs · or 30 min');
      expect(store.promiseFor(fast)!.highlight, 'or 30 min');
      expect(store.promiseFor(fast)!.isExpress, isFalse);
      expect(store.promiseFor(slow)!.text, 'Within 6 hrs');
      now = uae(23);
      expect(store.promiseFor(fast)!.text, 'Tomorrow by 11 AM');
      store.setArea(jebelAli);
      now = uae(12);
      expect(store.promiseFor(fast)!.text, 'Within 6 hrs');
      expect(store.isExpressEligible(fast), isTrue);
      expect(store.isExpressEligible(slow), isFalse);
    });

    test('promiseFor in Express mode', () {
      var now = uae(12);
      final store = DeliveryStore(now: () => now, refreshEvery: null);
      store.setArea(downtown);
      store.setMode(DeliveryMode.express);
      expect(store.promiseFor(fast)!.text, '30–40 min');
      expect(store.promiseFor(fast)!.isExpress, isTrue);
      expect(store.promiseFor(slow)!.text, 'Fresh Market · Within 6 hrs');
      expect(store.promiseFor(slow)!.kind, ProductPromiseKind.marketOnly);
      now = uae(22, 30);
      expect(store.promiseFor(fast)!.text, 'From 8 AM');
      expect(store.promiseFor(slow)!.text, 'Fresh Market · Tomorrow by 11 AM');
    });

    test('cart attributes', () {
      final store = DeliveryStore(now: () => uae(9), refreshEvery: null);
      store.setArea(mirdif);
      expect(store.cartAttributes, {
        'Delivery mode': 'Fresh Market',
        'Delivery area': 'Mirdif, Dubai',
        'Delivery promise': 'Today within 6 hours',
        'Delivery pin': '25.22000,55.42000',
      });
      store.setMode(DeliveryMode.express);
      expect(store.cartAttributes, {
        'Delivery mode': 'Express',
        'Delivery area': 'Mirdif, Dubai',
        'Delivery promise': '25–35 min',
        'Delivery pin': '25.22000,55.42000',
      });
    });
  });

  group('saved on the device', () {
    test('saves the website\'s shape under tfm-delivery-v1', () async {
      final prefs = await prefsWith();
      final store = DeliveryStore(
        prefs: prefs,
        now: () => uae(12),
        refreshEvery: null,
      );
      expect(DeliveryStore.prefsKey, 'tfm-delivery-v1');
      expect(prefs.getString(DeliveryStore.prefsKey), isNull);

      store.setArea(mirdif);
      expect(saved(prefs), {
        'mode': 'market',
        'area': {'name': 'Mirdif', 'em': 'dubai', 'lat': 25.22, 'lng': 55.42},
      });
      store.setMode(DeliveryMode.express);
      expect(saved(prefs)['mode'], 'express');
      // A refused change writes nothing new.
      store.setMode(DeliveryMode.express);
      expect(saved(prefs)['mode'], 'express');
    });

    test('restores area and mode', () async {
      final prefs = await prefsWith();
      DeliveryStore(prefs: prefs, refreshEvery: null)
        ..setArea(downtown)
        ..setMode(DeliveryMode.express);

      final again = DeliveryStore(prefs: prefs, refreshEvery: null);
      expect(again.area, downtown);
      expect(again.mode, DeliveryMode.express);
    });

    test(
      'reads what the website saved, and falls back to Fresh Market',
      () async {
        // (saved JSON) -> (area name or null, mode)
        final table = <String, (String?, DeliveryMode)>{
          '{"mode":"express","area":{"name":"Mirdif","em":"dubai",'
              '"lat":25.22,"lng":55.42}}': (
            'Mirdif',
            DeliveryMode.express,
          ),
          // Express outside the zone is not kept.
          '{"mode":"express","area":{"name":"Jebel Ali","em":"dubai",'
              '"lat":25.01,"lng":55.03}}': (
            'Jebel Ali',
            DeliveryMode.market,
          ),
          // Express without an area is not kept.
          '{"mode":"express","area":null}': (null, DeliveryMode.market),
          '{"mode":"market","area":{"name":"Al Nahyan","em":"auh",'
              '"lat":24.47,"lng":54.38}}': (
            'Al Nahyan',
            DeliveryMode.market,
          ),
          // An unknown emirate drops the area (and so Express).
          '{"mode":"express","area":{"name":"X","em":"zz","lat":25.2,'
              '"lng":55.3}}': (
            null,
            DeliveryMode.market,
          ),
          '{"mode":"bogus"}': (null, DeliveryMode.market),
          'not json': (null, DeliveryMode.market),
          '[1,2]': (null, DeliveryMode.market),
          '': (null, DeliveryMode.market),
        };
        for (final entry in table.entries) {
          final prefs = await prefsWith({DeliveryStore.prefsKey: entry.key});
          final store = DeliveryStore(prefs: prefs, refreshEvery: null);
          expect(store.area?.name, entry.value.$1, reason: entry.key);
          expect(store.mode, entry.value.$2, reason: entry.key);
        }
      },
    );

    test('without prefs it lives in memory', () {
      final store = DeliveryStore(refreshEvery: null)..setArea(mirdif);
      expect(store.area, mirdif);
      expect(DeliveryStore(refreshEvery: null).area, isNull);
    });
  });

  group('30 second refresh', () {
    testWidgets('ticks while listened to and stops after', (tester) async {
      final store = DeliveryStore(now: () => uae(12));
      expect(store.refreshEvery, const Duration(seconds: 30));
      expect(store.isTicking, isFalse);

      var ticks = 0;
      void listener() => ticks++;
      store.addListener(listener);
      expect(store.isTicking, isTrue);

      await tester.pump(const Duration(seconds: 29));
      expect(ticks, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, 1);
      await tester.pump(const Duration(seconds: 60));
      expect(ticks, 3);

      store.removeListener(listener);
      expect(store.isTicking, isFalse);
      await tester.pump(const Duration(seconds: 60));
      expect(ticks, 3);

      store.addListener(listener);
      expect(store.isTicking, isTrue);
      store.dispose();
      expect(store.isTicking, isFalse);
      await tester.pump(const Duration(seconds: 60));
      expect(ticks, 3);
    });

    testWidgets('promises change as time passes', (tester) async {
      var now = uae(17, 59);
      final store = DeliveryStore(now: () => now)..setArea(mirdif);
      final seen = <String>[];
      store.addListener(() => seen.add(store.market!.slot));
      now = uae(18);
      await tester.pump(const Duration(seconds: 30));
      expect(seen, ['Tomorrow by 11 AM']);
      store.dispose();
    });

    testWidgets('can be turned off', (tester) async {
      final store = DeliveryStore(now: () => uae(12), refreshEvery: null);
      var ticks = 0;
      store.addListener(() => ticks++);
      expect(store.isTicking, isFalse);
      await tester.pump(const Duration(minutes: 5));
      expect(ticks, 0);
      store.refresh();
      expect(ticks, 1);
      store.dispose();
    });
  });
}
