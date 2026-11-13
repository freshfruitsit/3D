import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'delivery_copy.dart';
import 'delivery_rules.dart';

/// Finds delivery places: the website's areas (local, instant) and, like the
/// website, any address through the Photon geocoder (photon.komoot.io).
/// Remote failures never throw; they give no results.
class PlaceSearch {
  PlaceSearch({http.Client? client, this.timeout = const Duration(seconds: 8)})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// Remote search starts at this many characters.
  static const int minRemoteChars = 3;

  /// The website waits this long after typing before searching remotely.
  static const Duration debounce = Duration(milliseconds: 320);

  /// The most rows [suggestions] gives.
  static const int maxSuggestions = 8;

  // ---- local --------------------------------------------------------------

  /// The website's areas whose "name + emirate" contains every word of
  /// [term] (any case): the first 5, or the first 4 for an empty term.
  static List<DeliveryArea> localMatches(String term) {
    final t = term.trim().toLowerCase();
    final words = _words(t);
    return DeliveryConfig.areas
        .where((a) {
          final hay = '${a.name} ${a.emirate.label}'.toLowerCase();
          return words.every(hay.contains);
        })
        .take(t.isEmpty ? 4 : 5)
        .toList();
  }

  /// The store's own row: "The Fresh Market", "Our market · Ras Al Khor
  /// hub", at the hub.
  static DeliveryPlace get storePlace {
    const hub = DeliveryConfig.hub;
    return DeliveryPlace(
      name: DeliveryConfig.storeName,
      sub: 'Our market · ${DeliveryConfig.hubName}',
      emirate: DeliveryRules.nearestArea(hub.lat, hub.lng).area.emirate,
      lat: hub.lat,
      lng: hub.lng,
      isStore: true,
    );
  }

  /// The picker's rows for [term], in the website's order: the store row
  /// (3+ characters naming it), the local areas, then [remote] results (3+
  /// characters) whose name is not already listed; at most 8.
  static List<DeliveryPlace> suggestions(
    String term, {
    List<DeliveryPlace> remote = const [],
  }) {
    final t = term.trim().toLowerCase();
    final words = _words(t);
    final local = [
      for (final a in localMatches(term)) DeliveryPlace.fromArea(a),
    ];
    final seen = {for (final p in local) p.name.toLowerCase()};
    final storeHay = '${DeliveryConfig.storeName} ${DeliveryConfig.hubName}'
        .toLowerCase();
    final long = t.length >= minRemoteChars;
    return [
      if (long && words.every(storeHay.contains)) storePlace,
      ...local,
      if (long)
        for (final r in remote)
          if (!seen.contains(r.name.toLowerCase())) r,
    ].take(maxSuggestions).toList();
  }

  // ---- remote -------------------------------------------------------------

  /// Photon search near the hub, inside the UAE's box.
  static Uri searchUri(String term) => Uri.parse(
    'https://photon.komoot.io/api/?q=${Uri.encodeComponent(term)}'
    '&limit=7&lang=en&lat=${DeliveryConfig.hub.lat}'
    '&lon=${DeliveryConfig.hub.lng}&bbox=51.4,22.6,56.5,26.2',
  );

  /// Photon reverse lookup of one point.
  static Uri reverseUri(double lat, double lng) => Uri.parse(
    'https://photon.komoot.io/reverse?lat=$lat&lon=$lng&lang=en&limit=1',
  );

  /// Delivery places for [term] from the geocoder, like the website: only
  /// for 3+ characters, only places in an emirate, without repeats. Any
  /// error gives an empty list.
  Future<List<DeliveryPlace>> search(String term) async {
    final t = term.trim();
    if (t.length < minRemoteChars) return const [];
    final features = await _features(searchUri(t));
    final out = <DeliveryPlace>[];
    final seen = <String>{};
    for (final f in features) {
      final place = placeFromFeature(f);
      if (place == null || !place.deliverable) continue;
      final key = '${place.name.toLowerCase()}|${place.sub.toLowerCase()}';
      if (seen.add(key)) out.add(place);
    }
    return out;
  }

  /// The geocoder's place at a point (named for an area), at exactly
  /// [lat],[lng]; it may be outside the UAE ([DeliveryPlace.foreign]) or
  /// have no emirate. Null when nothing was found or on any error.
  Future<DeliveryPlace?> reverse(double lat, double lng) async {
    final features = await _features(reverseUri(lat, lng));
    if (features.isEmpty) return null;
    return placeFromFeature(features.first, forArea: true)?.at(lat, lng);
  }

  /// A GPS point or map pin as a place, like the website: the local
  /// [DeliveryRules.placeFromPoint] answer, replaced by the geocoder's when
  /// that one has an emirate, is abroad, or the local one has no emirate.
  Future<DeliveryPlace> resolvePoint(double lat, double lng) async {
    final local = DeliveryRules.placeFromPoint(lat, lng);
    final remote = await reverse(lat, lng);
    if (remote != null &&
        (remote.deliverable || remote.foreign || !local.deliverable)) {
      return remote;
    }
    return local;
  }

  void close() => _client.close();

  Future<List<Object?>> _features(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final features = json is Map ? json['features'] : null;
      return features is List ? features : const [];
    } catch (_) {
      return const [];
    }
  }

  /// A Photon GeoJSON feature as a place, exactly as the website maps it.
  /// With [forArea] the name prefers the district or locality (reverse
  /// lookups); otherwise the place's own name. Null without coordinates
  /// or a name.
  static DeliveryPlace? placeFromFeature(
    Object? feature, {
    bool forArea = false,
  }) {
    if (feature is! Map) return null;
    final props = feature['properties'];
    final p = props is Map ? props : const {};
    final geometry = feature['geometry'];
    final coords = geometry is Map ? geometry['coordinates'] : null;
    if (coords is! List || coords.length < 2) return null;
    final lng = _number(coords[0]);
    final lat = _number(coords[1]);
    if (lat == null || lng == null) return null;

    String? s(String key) {
      final v = p[key];
      if (v is String) return v.isEmpty ? null : v;
      if (v is num) return '$v';
      return null;
    }

    final country = s('countrycode');
    if (country != null && country.toUpperCase() != 'AE') {
      return DeliveryPlace(
        name: s('name') ?? s('city') ?? 'This spot',
        sub: s('country') ?? '',
        emirate: null,
        foreign: true,
        lat: lat,
        lng: lng,
      );
    }

    final nearest = DeliveryRules.nearestArea(lat, lng);
    final emirate =
        Emirate.fromText(s('state')) ??
        Emirate.fromText(s('county')) ??
        Emirate.fromText(s('city')) ??
        (nearest.km <= DeliveryConfig.maxAreaKm ? nearest.area.emirate : null);
    final areaName =
        s('district') ?? s('locality') ?? s('suburb') ?? s('city') ?? s('name');
    final name = forArea
        ? (areaName ?? s('name'))
        : (s('name') ?? s('street') ?? areaName);
    if (name == null) return null;

    final street = s('street');
    final house = s('housenumber');
    final parts = <String>[];
    for (final x in [
      house != null && street != null ? '$house $street' : street,
      s('district') ?? s('locality'),
      s('city'),
      emirate?.label,
    ]) {
      if (x == null || x.isEmpty || x == name || parts.contains(x)) continue;
      parts.add(x);
    }
    return DeliveryPlace(
      name: name.length > 48 ? name.substring(0, 48) : name,
      sub: parts.take(3).join(', '),
      emirate: emirate,
      lat: lat,
      lng: lng,
    );
  }

  static List<String> _words(String lowerTerm) =>
      lowerTerm.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  static double? _number(Object? v) {
    final d = v is num
        ? v.toDouble()
        : (v is String ? double.tryParse(v) : null);
    return d != null && d.isFinite ? d : null;
  }
}

/// The location picker's search box state: local rows at once, remote rows
/// after a 320 ms pause, the latest request winning, like the website.
class PlaceSearchController extends ChangeNotifier {
  PlaceSearchController({this._search, this.debounce = PlaceSearch.debounce});

  /// The remote search; null for local areas only.
  final PlaceSearch? _search;
  final Duration debounce;

  String _term = '';
  List<DeliveryPlace> _remote = const [];
  String _remoteFor = '';
  bool _searching = false;
  int _seq = 0;
  Timer? _timer;
  bool _disposed = false;

  /// The text typed, as given.
  String get term => _term;

  /// A remote search is waiting or running.
  bool get searching => _searching;

  /// The latest remote results (deliverable places).
  List<DeliveryPlace> get remote => _remote;

  /// The rows to show for [term].
  List<DeliveryPlace> get suggestions =>
      PlaceSearch.suggestions(_term, remote: _remote);

  /// The status line under the rows, or null: "Searching for …" while
  /// searching with nothing to show, or "Nothing found for …".
  String? statusText({bool hasMap = true}) {
    final rows = suggestions;
    if (_searching && rows.isEmpty) return DeliveryCopy.searching(_term);
    if (_searching || rows.isNotEmpty) return null;
    return DeliveryCopy.nothingFound(_term, hasMap: hasMap);
  }

  /// Call on every change of the search text.
  void setTerm(String raw) {
    _term = raw;
    final t = raw.trim();
    _timer?.cancel();
    final seq = ++_seq;
    final search = _search;
    if (search == null || t.length < PlaceSearch.minRemoteChars) {
      _remote = const [];
      _remoteFor = '';
      _searching = false;
      notifyListeners();
      return;
    }
    // Keep earlier results while the text only grows.
    if (!t.toLowerCase().startsWith(_remoteFor)) {
      _remote = const [];
      _remoteFor = '';
    }
    _searching = true;
    notifyListeners();
    _timer = Timer(debounce, () async {
      final found = await search.search(t);
      if (_disposed || seq != _seq) return; // a newer request won
      _remote = found;
      _remoteFor = t.toLowerCase();
      _searching = false;
      notifyListeners();
    });
  }

  /// Empties the box (the picker opening again).
  void clear() => setTerm('');

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
