import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/product.dart';
import 'delivery_config.dart';

export 'delivery_config.dart';

/// How the shopper wants the order delivered.
enum DeliveryMode {
  /// Full range with the same-day / next-morning promise.
  market('market', 'Fresh Market'),

  /// Only Express items, in under an hour, inside the Express zone.
  express('express', 'Express');

  const DeliveryMode(this.code, this.label);

  /// Saved value: "market" or "express".
  final String code;

  /// "Fresh Market" or "Express" (also the cart's "Delivery mode").
  final String label;

  static DeliveryMode? fromCode(String? code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return null;
  }
}

/// The Fresh Market (full range) promise for an area at one moment.
@immutable
class MarketPromise {
  const MarketPromise({
    required this.today,
    required this.line,
    required this.slot,
    required this.short,
    required this.sub,
    required this.cutHour,
    this.by,
    this.left,
  });

  /// True before the same-day cut-off.
  final bool today;

  /// "Today within 6 hours" / "Tomorrow morning before 11 AM".
  final String line;

  /// "Today by 4:15 PM" / "Tomorrow by 11 AM".
  final String slot;

  /// "Within 6 hrs" / "Tomorrow by 11 AM" (product cards).
  final String short;

  /// "4:15 PM"; only when [today].
  final String? by;

  /// Time left to order for today, "3h 20m" / "45m"; only when [today].
  final String? left;

  /// "Order now and it arrives by 4:15 PM · same-day cut-off 6 PM" /
  /// "Ordered after 6 PM, so it comes tomorrow morning".
  final String sub;

  /// Same-day cut-off hour, UAE time (18).
  final int cutHour;

  @override
  String toString() => 'MarketPromise($slot, left: $left)';
}

/// The Express promise for a place at one moment.
@immutable
class ExpressPromise {
  const ExpressPromise({
    required this.covered,
    required this.open,
    required this.etaMinutes,
    required this.range,
    required this.km,
  });

  /// Within the Express zone (20 km of the hub).
  final bool covered;

  /// Express is running now (8 AM to 10 PM UAE time).
  final bool open;

  /// Rounded ETA, at least 15.
  final int etaMinutes;

  /// "25–35 min" (en dash).
  final String range;

  /// Distance from the hub.
  final double km;

  /// Covered and open: Express can deliver right now.
  bool get available => covered && open;

  @override
  String toString() => 'ExpressPromise($range, covered: $covered, open: $open)';
}

/// A candidate delivery place: a search result, a GPS point or a map pin.
/// [emirate] is null where the store does not deliver.
@immutable
class DeliveryPlace extends GeoPoint {
  const DeliveryPlace({
    required this.name,
    required this.emirate,
    required double lat,
    required double lng,
    this.sub = '',
    this.foreign = false,
    this.isStore = false,
  }) : super(lat, lng);

  /// From one of the website's areas.
  DeliveryPlace.fromArea(DeliveryArea area)
    : this(
        name: area.name,
        emirate: area.emirate,
        lat: area.lat,
        lng: area.lng,
        sub: area.emirate.label,
      );

  final String name;
  final Emirate? emirate;

  /// Second line ("Al Wasl Road, Jumeirah, Dubai"); may be empty.
  final String sub;

  /// Outside the UAE (a geocoder result with another country code).
  final bool foreign;

  /// The store's own row ("The Fresh Market", at the hub).
  final bool isStore;

  bool get deliverable => emirate != null;

  /// "Dubai Marina, Dubai" (see [placeLabel]).
  String get label => placeLabel(name, emirate);

  /// The second line to show: [sub], else the emirate name.
  String get subtitle => sub.isNotEmpty ? sub : (emirate?.label ?? '');

  /// The area to deliver to, or null when not [deliverable].
  DeliveryArea? toArea() {
    final e = emirate;
    if (e == null) return null;
    return DeliveryArea(name: name, emirate: e, lat: lat, lng: lng);
  }

  /// A copy at another point (the website keeps the pin, not the
  /// geocoder's point, after a reverse lookup).
  DeliveryPlace at(double lat, double lng) => DeliveryPlace(
    name: name,
    emirate: emirate,
    lat: lat,
    lng: lng,
    sub: sub,
    foreign: foreign,
    isStore: isStore,
  );

  @override
  bool operator ==(Object other) =>
      other is DeliveryPlace &&
      other.name == name &&
      other.emirate == emirate &&
      other.lat == lat &&
      other.lng == lng &&
      other.sub == sub &&
      other.foreign == foreign &&
      other.isStore == isStore;

  @override
  int get hashCode =>
      Object.hash(name, emirate, lat, lng, sub, foreign, isStore);

  @override
  String toString() =>
      'DeliveryPlace($name, ${emirate?.code}, $lat, $lng, sub: $sub)';
}

/// How a product card shows delivery.
enum ProductPromiseKind {
  /// Fresh Market mode: "Within 6 hrs" (maybe "· or 25 min").
  market,

  /// Express mode, Express item: "25–35 min" or "From 8 AM".
  express,

  /// Express mode, item not on Express: "Fresh Market · Within 6 hrs".
  marketOnly,
}

/// The short delivery line of a product card.
@immutable
class ProductPromise {
  const ProductPromise({
    required this.kind,
    required this.text,
    this.highlight,
  });

  final ProductPromiseKind kind;

  /// The whole line, e.g. "Within 6 hrs · or 25 min".
  final String text;

  /// The part of [text] the website shows in bold ("or 25 min"), if any.
  final String? highlight;

  /// Shown with the Express bolt (an Express item in Express mode).
  bool get isExpress => kind == ProductPromiseKind.express;

  @override
  bool operator ==(Object other) =>
      other is ProductPromise &&
      other.kind == kind &&
      other.text == text &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(kind, text, highlight);

  @override
  String toString() => 'ProductPromise($kind, $text)';
}

/// The website's delivery rules (tfm-delivery.js), as pure functions of a
/// place and a UTC moment [now]. Every result matches the website's text.
abstract final class DeliveryRules {
  /// UAE wall-clock time of [now] in fractional hours (0 <= h < 24).
  static double uaeHours(DateTime now) {
    final utc = now.toUtc();
    return ((utc.hour * 60 + utc.minute + DeliveryConfig.uaeOffsetMinutes) %
            1440) /
        60;
  }

  /// 12-hour label: "8 AM", "6 PM", "4:15 PM", "12 AM" (24 wraps to
  /// midnight).
  static String formatHour(num h) {
    final m = (h * 60).round() % 1440;
    final hour = m ~/ 60;
    final minute = m % 60;
    final ap = hour < 12 ? 'AM' : 'PM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final mm = minute == 0 ? '' : ':${minute.toString().padLeft(2, '0')}';
    return '$h12$mm $ap';
  }

  /// Time left as the website writes it: "3h 20m", "10h 0m", "45m".
  static String formatLeft(num h) {
    final m = math.max(0, (h * 60).round());
    return '${m >= 60 ? '${m ~/ 60}h ' : ''}${m % 60}m';
  }

  /// Great-circle distance in km (haversine, R = 6371); [b] defaults to
  /// the hub.
  static double km(GeoPoint a, [GeoPoint b = DeliveryConfig.hub]) {
    double r(double x) => x * math.pi / 180;
    final dLat = r(a.lat - b.lat);
    final dLng = r(a.lng - b.lng);
    final s =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(r(a.lat)) *
            math.cos(r(b.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * 6371 * math.asin(math.sqrt(s));
  }

  /// Same-day cut-off hour for [emirate].
  static int cutHour(Emirate emirate) =>
      DeliveryConfig.cut[emirate] ?? DeliveryConfig.defaultCut;

  /// The Fresh Market promise for [area] at [now].
  static MarketPromise market(DeliveryArea area, DateTime now) =>
      marketFor(area.emirate, now);

  /// The Fresh Market promise for any place in [emirate] at [now].
  static MarketPromise marketFor(Emirate emirate, DateTime now) {
    final cut = cutHour(emirate);
    final h = uaeHours(now);
    const hrs = DeliveryConfig.sameDayHours;
    if (h < cut) {
      // Rounded up to the next quarter hour, like the website.
      final by = formatHour((((h + hrs) * 4).ceil()) / 4);
      return MarketPromise(
        today: true,
        line: DeliveryConfig.todayText,
        slot: 'Today by $by',
        short: 'Within $hrs hrs',
        by: by,
        left: formatLeft(cut - h),
        sub:
            'Order now and it arrives by $by · same-day cut-off '
            '${formatHour(cut)}',
        cutHour: cut,
      );
    }
    return MarketPromise(
      today: false,
      line: DeliveryConfig.tomorrowText,
      slot: DeliveryConfig.tomorrowShort,
      short: DeliveryConfig.tomorrowShort,
      sub: 'Ordered after ${formatHour(cut)}, so it comes tomorrow morning',
      cutHour: cut,
    );
  }

  /// True when [point] is inside the Express zone (time does not matter).
  static bool isCovered(GeoPoint point) =>
      km(point) <= DeliveryConfig.expressKm;

  /// True while Express runs (8 AM to 10 PM UAE time).
  static bool isExpressOpen(DateTime now) {
    final h = uaeHours(now);
    return h >= DeliveryConfig.expressOpen && h < DeliveryConfig.expressClose;
  }

  /// The Express promise for [point] at [now].
  static ExpressPromise express(GeoPoint point, DateTime now) {
    final d = km(point);
    final eta = math.max(
      15,
      ((DeliveryConfig.etaBase + d * 1.5) / 5).round() * 5,
    );
    return ExpressPromise(
      covered: d <= DeliveryConfig.expressKm,
      open: isExpressOpen(now),
      etaMinutes: eta,
      range: '${eta - 5}–${eta + 5} min',
      km: d,
    );
  }

  /// The nearest of the website's areas to a point, with its distance.
  static ({DeliveryArea area, double km}) nearestArea(double lat, double lng) {
    final point = GeoPoint(lat, lng);
    var best = DeliveryConfig.areas.first;
    var bestKm = double.infinity;
    for (final a in DeliveryConfig.areas) {
      final d = km(point, a);
      if (d < bestKm) {
        bestKm = d;
        best = a;
      }
    }
    return (area: best, km: bestKm);
  }

  /// A GPS point or map pin as a place: the nearest area's name within
  /// 3 km, "Near <area>" up to 60 km (in that area's emirate), otherwise
  /// "This spot" with no emirate (not delivered to).
  static DeliveryPlace placeFromPoint(double lat, double lng) {
    final n = nearestArea(lat, lng);
    if (n.km <= DeliveryConfig.maxAreaKm) {
      return DeliveryPlace(
        name: n.km > DeliveryConfig.nearKm
            ? 'Near ${n.area.name}'
            : n.area.name,
        emirate: n.area.emirate,
        lat: lat,
        lng: lng,
      );
    }
    return DeliveryPlace(name: 'This spot', emirate: null, lat: lat, lng: lng);
  }

  /// The website marks exactly the products tagged "1hr-delivery" (any
  /// case) as Express.
  static bool isExpressEligible(Product product) {
    const wanted = DeliveryConfig.expressTag;
    return product.tags.any((t) => t.trim().toLowerCase() == wanted);
  }

  /// The card line for [product]; null without an [area] (the website
  /// hides it until a location is set).
  static ProductPromise? productPromise(
    Product product, {
    required DeliveryArea? area,
    required DeliveryMode mode,
    required DateTime now,
  }) {
    if (area == null) return null;
    final eligible = isExpressEligible(product);
    final mk = market(area, now);
    final ex = express(area, now);
    if (mode == DeliveryMode.express) {
      if (eligible) {
        return ProductPromise(
          kind: ProductPromiseKind.express,
          text: ex.open
              ? ex.range
              : 'From ${formatHour(DeliveryConfig.expressOpen)}',
        );
      }
      return ProductPromise(
        kind: ProductPromiseKind.marketOnly,
        text: 'Fresh Market · ${mk.short}',
      );
    }
    if (eligible && ex.covered && ex.open) {
      final fast = 'or ${ex.etaMinutes} min';
      return ProductPromise(
        kind: ProductPromiseKind.market,
        text: '${mk.short} · $fast',
        highlight: fast,
      );
    }
    return ProductPromise(kind: ProductPromiseKind.market, text: mk.short);
  }

  // ---- messages (the website's toasts) -----------------------------------

  /// After choosing an area.
  static String deliveringTo(DeliveryArea area) => 'Delivering to ${area.name}';

  /// After choosing an area outside the Express zone while in Express.
  static String switchedToMarket(DeliveryArea area) =>
      "Express isn't available in ${area.name}. Switched to Fresh Market.";

  /// Choosing Express before setting a location.
  static const String setLocationForExpress =
      'Set your location to check Express';

  /// Choosing Express for an area outside the Express zone.
  static String expressNotCovered(DeliveryArea area, DateTime now) =>
      "Express isn't available in ${area.name} yet. Fresh Market delivers "
      '${market(area, now).line.toLowerCase()}.';

  /// Shown while Express is chosen but closed (it can still be chosen).
  static String expressClosed(DeliveryArea area, DateTime now) =>
      'Express is closed right now. It runs '
      '${formatHour(DeliveryConfig.expressOpen)} to '
      '${formatHour(DeliveryConfig.expressClose)}. Fresh Market delivers '
      '${market(area, now).line.toLowerCase()}.';

  /// A place where the store does not deliver.
  static const String notDeliverableTitle = "We don't deliver here yet";
  static const String notDeliverableText =
      'We deliver across the seven emirates of the UAE.';
  static const String notDeliverableMessage =
      '$notDeliverableTitle. $notDeliverableText';
}
