import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery_rules.dart';
import 'package:fresh_market_app/delivery/place_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A Photon GeoJSON feature.
Map<String, dynamic> feature(
  double lat,
  double lng, [
  Map<String, dynamic> props = const {},
]) => {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [lng, lat],
  },
  'properties': props,
};

http.Response collection(List<Object?> features) => http.Response(
  jsonEncode({'type': 'FeatureCollection', 'features': features}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

List<String> names(List<DeliveryPlace> places) => [
  for (final p in places) p.name,
];

void main() {
  group('local areas', () {
    test('every word must appear in name + emirate', () {
      final table = <String, List<String>>{
        '': ['Dubai Marina', 'Downtown Dubai', 'Business Bay', 'Jumeirah'],
        '   ': ['Dubai Marina', 'Downtown Dubai', 'Business Bay', 'Jumeirah'],
        'dubai': [
          'Dubai Marina',
          'Downtown Dubai',
          'Business Bay',
          'Jumeirah',
          'Al Barsha',
        ],
        'MARINA': ['Dubai Marina'],
        'marina dubai': ['Dubai Marina'],
        'abu dhabi': [
          'Al Nahyan',
          'Al Reem Island',
          'Khalifa City',
          'Yas Island',
          'Al Jimi (Al Ain)',
        ],
        // "Umm Al Quwain" has "al" and "ain" too.
        'al ain': ['Al Jimi (Al Ain)', 'Al Salamah'],
        'island': ['Al Reem Island', 'Yas Island'],
        'sharjah': ['Al Majaz', 'Muwaileh'],
        'fuj': ['Al Faseel'],
        'ras': ['Al Nakheel'],
        'al quwain': ['Al Salamah'],
        'mir': ['Mirdif'],
        'zzz': [],
        'marina abu': [],
      };
      table.forEach((term, want) {
        expect(
          names([
            for (final a in PlaceSearch.localMatches(term))
              DeliveryPlace.fromArea(a),
          ]),
          want,
          reason: '"$term"',
        );
      });
    });

    test('suggestions add the store row and remote rows like the website', () {
      // Under 3 characters: local only, even with remote results.
      final remote = [
        const DeliveryPlace(
          name: 'Marina Walk',
          emirate: Emirate.dubai,
          lat: 25.07,
          lng: 55.13,
        ),
        const DeliveryPlace(
          name: 'dubai marina',
          emirate: Emirate.dubai,
          lat: 25.0,
          lng: 55.1,
        ),
      ];
      expect(names(PlaceSearch.suggestions('ma', remote: remote)), [
        'Dubai Marina',
        'Al Majaz',
        'Al Nuaimiya', // Ajman
        'Al Salamah',
        'Al Nakheel', // Ras Al Khaimah
      ]);
      // Remote rows follow, without names already listed (any case).
      final rows = PlaceSearch.suggestions('marina', remote: remote);
      expect(names(rows), ['Dubai Marina', 'Marina Walk']);
      expect(rows.first.subtitle, 'Dubai');
      expect(rows.first.emirate, Emirate.dubai);

      // The store row, for 3+ characters that name it.
      final store = PlaceSearch.suggestions('fresh');
      expect(store.first.name, 'The Fresh Market');
      expect(store.first.isStore, isTrue);
      expect(store.first.subtitle, 'Our market · Ras Al Khor hub');
      expect(store.first.emirate, Emirate.dubai);
      expect(store.first.lat, 25.18);
      expect(store.first.lng, 55.36);
      expect(names(PlaceSearch.suggestions('ras al khor')), [
        'The Fresh Market',
      ]);
      expect(names(PlaceSearch.suggestions('ras')), [
        'The Fresh Market',
        'Al Nakheel',
      ]);
      expect(names(PlaceSearch.suggestions('fr')), isEmpty);

      // At most 8 rows.
      final many = [
        for (var i = 0; i < 10; i++)
          DeliveryPlace(
            name: 'Dubai Place $i',
            emirate: Emirate.dubai,
            lat: 25.1,
            lng: 55.2,
          ),
      ];
      final capped = PlaceSearch.suggestions('dubai', remote: many);
      expect(capped, hasLength(8));
      expect(names(capped).take(5), [
        'Dubai Marina',
        'Downtown Dubai',
        'Business Bay',
        'Jumeirah',
        'Al Barsha',
      ]);
    });
  });

  group('Photon features', () {
    test('a Dubai address', () {
      final place = PlaceSearch.placeFromFeature(
        feature(25.0763, 55.1345, {
          'name': 'Marina Walk',
          'street': 'King Salman Street',
          'housenumber': '12',
          'district': 'Dubai Marina',
          'city': 'Dubai',
          'state': 'Dubai',
          'countrycode': 'AE',
        }),
      )!;
      expect(place.name, 'Marina Walk');
      expect(place.sub, '12 King Salman Street, Dubai Marina, Dubai');
      expect(place.emirate, Emirate.dubai);
      expect(place.lat, 25.0763);
      expect(place.lng, 55.1345);
      expect(place.deliverable, isTrue);
      expect(place.foreign, isFalse);
      expect(place.label, 'Marina Walk, Dubai');
    });

    test('emirate from state, county, city, else the nearest area', () {
      final table = <Map<String, dynamic>, Emirate?>{
        {'name': 'A', 'state': 'Abu Dhabi Emirate'}: Emirate.abuDhabi,
        {'name': 'A', 'county': 'Al Ain Region'}: Emirate.abuDhabi,
        {'name': 'A', 'city': 'Sharjah'}: Emirate.sharjah,
        {'name': 'A', 'state': 'Ajman', 'city': 'Dubai'}: Emirate.ajman,
        // No hint: the nearest area within 60 km (Mirdif here).
        {'name': 'A'}: Emirate.dubai,
      };
      table.forEach((props, want) {
        expect(
          PlaceSearch.placeFromFeature(feature(25.22, 55.42, props))!.emirate,
          want,
          reason: '$props',
        );
      });
      // No hint and far from every area: not deliverable.
      final far = PlaceSearch.placeFromFeature(
        feature(23.0, 53.0, {'name': 'Desert', 'countrycode': 'AE'}),
      )!;
      expect(far.emirate, isNull);
      expect(far.deliverable, isFalse);
      expect(far.foreign, isFalse);
    });

    test('another country is not deliverable', () {
      final place = PlaceSearch.placeFromFeature(
        feature(23.6, 58.4, {
          'name': 'Muttrah',
          'city': 'Muscat',
          'country': 'Oman',
          'countrycode': 'om',
        }),
      )!;
      expect(place.foreign, isTrue);
      expect(place.deliverable, isFalse);
      expect(place.name, 'Muttrah');
      expect(place.sub, 'Oman');
      final unnamed = PlaceSearch.placeFromFeature(
        feature(23.6, 58.4, {'countrycode': 'OM'}),
      )!;
      expect(unnamed.name, 'This spot');
      expect(unnamed.sub, '');
      final city = PlaceSearch.placeFromFeature(
        feature(23.6, 58.4, {'city': 'Muscat', 'countrycode': 'OM'}),
      )!;
      expect(city.name, 'Muscat');
    });

    test('names for search and for an area (reverse lookup)', () {
      final props = {
        'street': 'Al Wasl Road',
        'district': 'Jumeirah 1',
        'city': 'Dubai',
        'state': 'Dubai',
      };
      final forSearch = PlaceSearch.placeFromFeature(
        feature(25.21, 55.24, props),
      )!;
      expect(forSearch.name, 'Al Wasl Road');
      expect(forSearch.sub, 'Jumeirah 1, Dubai');
      final forArea = PlaceSearch.placeFromFeature(
        feature(25.21, 55.24, props),
        forArea: true,
      )!;
      expect(forArea.name, 'Jumeirah 1');
      expect(forArea.sub, 'Al Wasl Road, Dubai');

      final locality = PlaceSearch.placeFromFeature(
        feature(25.21, 55.24, {'locality': 'Al Safa', 'suburb': 'S'}),
        forArea: true,
      )!;
      expect(locality.name, 'Al Safa');
      final suburb = PlaceSearch.placeFromFeature(
        feature(25.21, 55.24, {'suburb': 'Al Quoz', 'name': 'Mall'}),
        forArea: true,
      )!;
      expect(suburb.name, 'Al Quoz');
      final onlyName = PlaceSearch.placeFromFeature(
        feature(25.21, 55.24, {'name': 'Mall'}),
        forArea: true,
      )!;
      expect(onlyName.name, 'Mall');
    });

    test('long names are cut to 48 characters; bad features are dropped', () {
      final long = 'X' * 60;
      expect(
        PlaceSearch.placeFromFeature(feature(25.2, 55.3, {'name': long}))!.name,
        'X' * 48,
      );
      for (final bad in <Object?>[
        null,
        'feature',
        {
          'properties': {'name': 'A'},
        },
        {
          'geometry': {
            'coordinates': [55.3],
          },
          'properties': {'name': 'A'},
        },
        {
          'geometry': {
            'coordinates': ['x', 'y'],
          },
          'properties': {'name': 'A'},
        },
        feature(25.2, 55.3, {}), // no name at all
        feature(25.2, 55.3, {'name': ''}),
      ]) {
        expect(PlaceSearch.placeFromFeature(bad), isNull, reason: '$bad');
      }
    });

    test('the sub line skips repeats and the name, at most 3 parts', () {
      final place = PlaceSearch.placeFromFeature(
        feature(25.33, 55.385, {
          'name': 'Al Majaz',
          'street': 'Corniche Street',
          'district': 'Al Majaz',
          'city': 'Sharjah',
          'state': 'Sharjah',
        }),
      )!;
      expect(place.sub, 'Corniche Street, Sharjah');
      final dubai = PlaceSearch.placeFromFeature(
        feature(25.2, 55.27, {
          'name': 'Tower',
          'street': 'Sheikh Zayed Road',
          'locality': 'Trade Centre',
          'city': 'Dubai',
          'state': 'Dubai',
        }),
      )!;
      // City and emirate are both "Dubai": listed once.
      expect(dubai.sub, 'Sheikh Zayed Road, Trade Centre, Dubai');
    });
  });

  group('remote search', () {
    test('asks Photon near the hub inside the UAE box', () async {
      final asked = <Uri>[];
      final search = PlaceSearch(
        client: MockClient((request) async {
          asked.add(request.url);
          return collection([]);
        }),
      );
      await search.search('  al wasl ');
      expect(
        asked.single.toString(),
        'https://photon.komoot.io/api/?q=al%20wasl&limit=7&lang=en'
        '&lat=25.18&lon=55.36&bbox=51.4,22.6,56.5,26.2',
      );
      await search.reverse(25.2048, 55.2708);
      expect(
        asked.last.toString(),
        'https://photon.komoot.io/reverse?lat=25.2048&lon=55.2708'
        '&lang=en&limit=1',
      );
    });

    test('needs 3 characters', () async {
      var calls = 0;
      final search = PlaceSearch(
        client: MockClient((_) async {
          calls++;
          return collection([]);
        }),
      );
      expect(await search.search('ab'), isEmpty);
      expect(await search.search('  ab  '), isEmpty);
      expect(calls, 0);
      await search.search('abc');
      expect(calls, 1);
    });

    test('keeps deliverable places once each', () async {
      final search = PlaceSearch(
        client: MockClient(
          (_) async => collection([
            feature(25.0763, 55.1345, {
              'name': 'Marina Walk',
              'city': 'Dubai',
              'countrycode': 'AE',
            }),
            feature(25.0764, 55.1346, {
              'name': 'marina walk',
              'city': 'Dubai',
              'countrycode': 'AE',
            }),
            feature(23.6, 58.4, {'name': 'Marina', 'countrycode': 'OM'}),
            feature(23.0, 53.0, {'name': 'Marina Desert'}),
            feature(25.33, 55.385, {
              'name': 'Marina Walk',
              'city': 'Sharjah',
              'countrycode': 'AE',
            }),
            {'bad': true},
          ]),
        ),
      );
      final found = await search.search('marina walk');
      expect(names(found), ['Marina Walk', 'Marina Walk']);
      expect(found[0].emirate, Emirate.dubai);
      expect(found[0].sub, 'Dubai');
      expect(found[1].emirate, Emirate.sharjah);
    });

    test('errors give no results', () async {
      final failures = <Future<http.Response> Function()>[
        () async => http.Response('oops', 500),
        () async => http.Response('not json', 200),
        () async => http.Response('{"features": "x"}', 200),
        () async => http.Response('[]', 200),
        () async => throw http.ClientException('offline'),
      ];
      for (final fail in failures) {
        final search = PlaceSearch(client: MockClient((_) => fail()));
        expect(await search.search('dubai marina'), isEmpty);
        expect(await search.reverse(25.08, 55.14), isNull);
      }
    });

    test('times out after 8 seconds by default', () async {
      expect(PlaceSearch().timeout, const Duration(seconds: 8));
      final never = Completer<http.Response>();
      final search = PlaceSearch(
        client: MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 20),
      );
      expect(await search.search('dubai marina'), isEmpty);
    });

    test('reverse keeps the pin and names the area', () async {
      final search = PlaceSearch(
        client: MockClient(
          (_) async => collection([
            feature(25.2101, 55.2402, {
              'name': 'Some Villa',
              'street': 'Al Wasl Road',
              'district': 'Jumeirah 1',
              'city': 'Dubai',
              'state': 'Dubai',
              'countrycode': 'AE',
            }),
          ]),
        ),
      );
      final place = (await search.reverse(25.21, 55.24))!;
      expect(place.name, 'Jumeirah 1');
      expect(place.lat, 25.21);
      expect(place.lng, 55.24);
      expect(place.emirate, Emirate.dubai);
    });

    test('resolvePoint combines the local and remote answers', () async {
      PlaceSearch answering(List<Object?> features) =>
          PlaceSearch(client: MockClient((_) async => collection(features)));

      // Remote with an emirate wins.
      final named = await answering([
        feature(25.21, 55.24, {'district': 'Jumeirah 1', 'state': 'Dubai'}),
      ]).resolvePoint(25.10, 55.16);
      expect(named.name, 'Jumeirah 1');
      expect(named.lat, 25.10);

      // Remote without an emirate loses to a deliverable local answer.
      final local = await answering([
        feature(23.0, 53.0, {'name': 'Somewhere', 'countrycode': ''}),
      ]).resolvePoint(25.10, 55.16);
      expect(local.name, 'Near Dubai Marina');

      // Abroad always wins (not deliverable).
      final abroad = await answering([
        feature(24.9, 56.2, {'name': 'Madha', 'countrycode': 'OM'}),
      ]).resolvePoint(25.12, 56.30);
      expect(abroad.name, 'Madha');
      expect(abroad.foreign, isTrue);
      expect(abroad.deliverable, isFalse);
      expect(abroad.lat, 25.12);

      // Nothing remote: the local answer.
      final offline = await PlaceSearch(
        client: MockClient((_) async => throw http.ClientException('x')),
      ).resolvePoint(24.0, 52.0);
      expect(offline.name, 'This spot');
      expect(offline.deliverable, isFalse);
    });
  });

  group('search box controller', () {
    test('local rows at once; remote after the pause; latest wins', () async {
      final requests = <String, Completer<http.Response>>{};
      final search = PlaceSearch(
        client: MockClient((request) {
          final c = Completer<http.Response>();
          requests[request.url.queryParameters['q']!] = c;
          return c.future;
        }),
      );
      final box = PlaceSearchController(
        search: search,
        debounce: const Duration(milliseconds: 10),
      );
      var changes = 0;
      box.addListener(() => changes++);

      box.setTerm('ma');
      expect(box.searching, isFalse);
      expect(names(box.suggestions), hasLength(5));

      box.setTerm('mar');
      expect(box.searching, isTrue);
      // "mar" is in "The Fresh Market" too.
      expect(names(box.suggestions), ['The Fresh Market', 'Dubai Marina']);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(requests.keys, ['mar']);

      box.setTerm('mari');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(requests.keys, ['mar', 'mari']);

      // The newer answer arrives first, then the stale one: it is ignored.
      requests['mari']!.complete(
        collection([
          feature(25.07, 55.13, {'name': 'Marina Mall', 'state': 'Dubai'}),
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(box.searching, isFalse);
      expect(names(box.remote), ['Marina Mall']);
      requests['mar']!.complete(
        collection([
          feature(25.07, 55.13, {'name': 'Stale', 'state': 'Dubai'}),
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(names(box.remote), ['Marina Mall']);
      expect(names(box.suggestions), ['Dubai Marina', 'Marina Mall']);
      expect(box.statusText(), isNull);

      // Typing on keeps the earlier results until the new ones arrive.
      box.setTerm('marin');
      expect(names(box.remote), ['Marina Mall']);
      expect(box.searching, isTrue);
      // Changing the start drops them.
      box.setTerm('deira');
      expect(box.remote, isEmpty);
      // Back under 3 characters: no remote, not searching.
      box.setTerm('de');
      expect(box.searching, isFalse);
      expect(box.remote, isEmpty);
      expect(changes, greaterThan(0));
      box.dispose();
    });

    test('status texts', () async {
      final search = PlaceSearch(
        client: MockClient((_) async => collection([])),
      );
      final box = PlaceSearchController(
        search: search,
        debounce: const Duration(milliseconds: 5),
      );
      box.setTerm('zzz');
      expect(box.statusText(), 'Searching for “zzz”…');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(box.searching, isFalse);
      expect(
        box.statusText(),
        'Nothing found for “zzz”. Try a nearby landmark, street '
        'or area, or tap the map to drop the pin.',
      );
      box.setTerm('marina');
      // Rows to show: no status line even while searching.
      expect(box.statusText(), isNull);
      box.clear();
      expect(box.term, '');
      expect(names(box.suggestions), [
        'Dubai Marina',
        'Downtown Dubai',
        'Business Bay',
        'Jumeirah',
      ]);
      box.dispose();
    });

    test('local only without a remote search', () {
      final box = PlaceSearchController();
      box.setTerm('sharjah');
      expect(box.searching, isFalse);
      expect(names(box.suggestions), ['Al Majaz', 'Muwaileh']);
      box.dispose();
    });

    test('a disposed controller ignores late answers', () async {
      final c = Completer<http.Response>();
      final box = PlaceSearchController(
        search: PlaceSearch(client: MockClient((_) => c.future)),
        debounce: Duration.zero,
      );
      box.setTerm('marina');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      box.dispose();
      c.complete(
        collection([
          feature(25.07, 55.13, {'name': 'Late', 'state': 'Dubai'}),
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(box.remote, isEmpty);
    });
  });
}
