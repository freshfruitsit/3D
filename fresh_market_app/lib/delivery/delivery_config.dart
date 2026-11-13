import 'package:flutter/foundation.dart';

/// The seven emirates the store delivers to. [code] is the short code the
/// website uses ("dubai", "auh", ...) and saves; [label] is the display name.
enum Emirate {
  dubai('dubai', 'Dubai'),
  abuDhabi('auh', 'Abu Dhabi'),
  sharjah('shj', 'Sharjah'),
  ajman('ajm', 'Ajman'),
  ummAlQuwain('uaq', 'Umm Al Quwain'),
  rasAlKhaimah('rak', 'Ras Al Khaimah'),
  fujairah('fuj', 'Fujairah');

  const Emirate(this.code, this.label);

  /// The website's code: dubai, auh, shj, ajm, uaq, rak or fuj.
  final String code;

  /// "Abu Dhabi".
  final String label;

  /// The emirate with this website [code], or null for an unknown code.
  static Emirate? fromCode(String? code) {
    for (final e in values) {
      if (e.code == code) return e;
    }
    return null;
  }

  /// The emirate named in an address text (a geocoder's state, county or
  /// city), as the website reads it; null when none is named.
  static Emirate? fromText(String? text) {
    final v = (text ?? '').toLowerCase();
    if (v.contains('dubai')) return dubai;
    if (v.contains('abu dhabi') || v.contains('al ain')) return abuDhabi;
    if (v.contains('sharjah')) return sharjah;
    if (v.contains('ajman')) return ajman;
    if (v.contains('umm al')) return ummAlQuwain;
    if (v.contains('ras al')) return rasAlKhaimah;
    if (v.contains('fujairah')) return fujairah;
    return null;
  }
}

/// A point on the map in degrees.
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// "25.08000,55.14000": the website's "Delivery pin" format.
  String get pin => '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.runtimeType == runtimeType &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

/// "Dubai Marina, Dubai", or just the name when it already contains the
/// emirate ("Downtown Dubai") or there is no emirate.
String placeLabel(String name, Emirate? emirate) {
  if (emirate == null) return name;
  return name.toLowerCase().contains(emirate.label.toLowerCase())
      ? name
      : '$name, ${emirate.label}';
}

/// A place the store delivers to: one of the website's areas, or a point the
/// shopper chose (GPS, map pin or search) with the emirate it is in.
@immutable
class DeliveryArea extends GeoPoint {
  const DeliveryArea({
    required this.name,
    required this.emirate,
    required double lat,
    required double lng,
  }) : super(lat, lng);

  /// "Dubai Marina", "Near Mirdif", "Al Wasl Road".
  final String name;
  final Emirate emirate;

  /// "Dubai Marina, Dubai" (see [placeLabel]).
  String get label => placeLabel(name, emirate);

  /// The website's saved shape: `{name, em, lat, lng}`.
  Map<String, dynamic> toJson() => {
        'name': name,
        'em': emirate.code,
        'lat': lat,
        'lng': lng,
      };

  /// Reads [toJson]'s shape; null when anything is missing or invalid.
  static DeliveryArea? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final emirate = Emirate.fromCode(json['em'] as String?);
    final lat = json['lat'];
    final lng = json['lng'];
    if (name is! String || name.isEmpty || emirate == null) return null;
    if (lat is! num || lng is! num) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    return DeliveryArea(
      name: name,
      emirate: emirate,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryArea &&
      other.name == name &&
      other.emirate == emirate &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(name, emirate, lat, lng);

  @override
  String toString() => 'DeliveryArea($name, ${emirate.code}, $lat, $lng)';
}

/// The website's delivery settings (its `data-tfm-delivery-config` block on
/// https://testtfm.myshopify.com). Keep these in step with the website.
abstract final class DeliveryConfig {
  /// The hub Express rides from.
  static const GeoPoint hub = GeoPoint(25.18, 55.36);
  static const String hubName = 'Ras Al Khor hub';
  static const String storeName = 'The Fresh Market';

  /// Express covers places up to this far from [hub].
  static const double expressKm = 20;

  /// Express runs from this hour (UAE time)...
  static const int expressOpen = 8;

  /// ...until this hour (exclusive).
  static const int expressClose = 22;

  /// Express ETA in minutes before the distance part.
  static const int etaBase = 20;

  /// Same-day cut-off hour (UAE time) per emirate.
  static const Map<Emirate, int> cut = {
    Emirate.dubai: 18,
    Emirate.abuDhabi: 18,
    Emirate.sharjah: 18,
    Emirate.ajman: 18,
    Emirate.ummAlQuwain: 18,
    Emirate.rasAlKhaimah: 18,
    Emirate.fujairah: 18,
  };

  /// Cut-off used for an emirate missing from [cut].
  static const int defaultCut = 18;

  /// Same-day orders arrive within this many hours.
  static const int sameDayHours = 6;
  static const String todayText = 'Today within 6 hours';
  static const String tomorrowShort = 'Tomorrow by 11 AM';
  static const String tomorrowText = 'Tomorrow morning before 11 AM';

  /// The product tag the website marks as Express.
  static const String expressTag = '1hr-delivery';

  /// A map point within this distance of an area takes the area's name;
  /// farther away it is "Near <area>".
  static const double nearKm = 3;

  /// A map point farther than this from every area is not delivered to.
  static const double maxAreaKm = 60;

  /// UAE time is UTC+4 all year.
  static const int uaeOffsetMinutes = 240;

  /// The website refreshes its promises this often.
  static const Duration refreshInterval = Duration(seconds: 30);

  /// Where the website (and this app) saves the shopper's choice.
  static const String prefsKey = 'tfm-delivery-v1';

  /// The website's delivery areas, in its order.
  static const List<DeliveryArea> areas = [
    DeliveryArea(
        name: 'Dubai Marina', emirate: Emirate.dubai, lat: 25.08, lng: 55.14),
    DeliveryArea(
        name: 'Downtown Dubai', emirate: Emirate.dubai, lat: 25.20, lng: 55.27),
    DeliveryArea(
        name: 'Business Bay',
        emirate: Emirate.dubai,
        lat: 25.185,
        lng: 55.265),
    DeliveryArea(
        name: 'Jumeirah', emirate: Emirate.dubai, lat: 25.21, lng: 55.24),
    DeliveryArea(
        name: 'Al Barsha', emirate: Emirate.dubai, lat: 25.11, lng: 55.20),
    DeliveryArea(name: 'Deira', emirate: Emirate.dubai, lat: 25.27, lng: 55.32),
    DeliveryArea(
        name: 'Mirdif', emirate: Emirate.dubai, lat: 25.22, lng: 55.42),
    DeliveryArea(
        name: 'Dubai Silicon Oasis',
        emirate: Emirate.dubai,
        lat: 25.12,
        lng: 55.38),
    DeliveryArea(
        name: 'Jebel Ali', emirate: Emirate.dubai, lat: 25.01, lng: 55.03),
    DeliveryArea(
        name: 'Al Nahyan', emirate: Emirate.abuDhabi, lat: 24.47, lng: 54.38),
    DeliveryArea(
        name: 'Al Reem Island',
        emirate: Emirate.abuDhabi,
        lat: 24.50,
        lng: 54.40),
    DeliveryArea(
        name: 'Khalifa City',
        emirate: Emirate.abuDhabi,
        lat: 24.42,
        lng: 54.57),
    DeliveryArea(
        name: 'Yas Island', emirate: Emirate.abuDhabi, lat: 24.49, lng: 54.60),
    DeliveryArea(
        name: 'Al Jimi (Al Ain)',
        emirate: Emirate.abuDhabi,
        lat: 24.24,
        lng: 55.74),
    DeliveryArea(
        name: 'Al Majaz', emirate: Emirate.sharjah, lat: 25.33, lng: 55.385),
    DeliveryArea(
        name: 'Muwaileh', emirate: Emirate.sharjah, lat: 25.30, lng: 55.45),
    DeliveryArea(
        name: 'Al Nuaimiya', emirate: Emirate.ajman, lat: 25.39, lng: 55.45),
    DeliveryArea(
        name: 'Al Salamah',
        emirate: Emirate.ummAlQuwain,
        lat: 25.56,
        lng: 55.55),
    DeliveryArea(
        name: 'Al Nakheel',
        emirate: Emirate.rasAlKhaimah,
        lat: 25.79,
        lng: 55.95),
    DeliveryArea(
        name: 'Al Faseel', emirate: Emirate.fujairah, lat: 25.12, lng: 56.33),
  ];

  /// The area called [name] (exact), or null.
  static DeliveryArea? areaNamed(String name) {
    for (final a in areas) {
      if (a.name == name) return a;
    }
    return null;
  }
}
