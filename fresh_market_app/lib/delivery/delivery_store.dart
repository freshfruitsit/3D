import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import 'delivery_rules.dart';

/// The shopper's delivery choice (area and mode), kept on the device the way
/// the website keeps it, with promises that refresh every 30 seconds.
///
/// While anything listens, a [Timer.periodic] calls [notifyListeners] every
/// [refreshEvery] so "Today by …" and "closes in …" stay current; it stops
/// when the last listener goes and in [dispose].
class DeliveryStore extends ChangeNotifier {
  /// Reads the saved choice from [prefs]. With no [prefs] it lives in
  /// memory only (tests). [now] is the clock (UTC or local, any zone);
  /// [refreshEvery] null turns the refresh ticker off.
  DeliveryStore({
    this._prefs,
    DateTime Function()? now,
    this.refreshEvery = DeliveryConfig.refreshInterval,
  }) : now = now ?? DateTime.now {
    _restore();
  }

  /// Same key and JSON shape as the website: `{"mode", "area"}`.
  static const String prefsKey = DeliveryConfig.prefsKey;

  final SharedPreferences? _prefs;

  /// The clock. Replace it in tests.
  DateTime Function() now;

  /// How often listeners are told to refresh; null for never.
  final Duration? refreshEvery;

  DeliveryArea? _area;
  DeliveryMode _mode = DeliveryMode.market;
  Timer? _ticker;
  bool _disposed = false;
  bool _askedForLocation = false;

  /// Where to deliver; null until the shopper chooses.
  DeliveryArea? get area => _area;
  bool get hasArea => _area != null;

  /// Fresh Market or Express. Express only for an area in the Express zone.
  DeliveryMode get mode => _mode;
  bool get isExpress => _mode == DeliveryMode.express;

  /// The Fresh Market promise now, or null without an area.
  MarketPromise? get market {
    final a = _area;
    return a == null ? null : DeliveryRules.market(a, now());
  }

  /// The Express promise now, or null without an area.
  ExpressPromise? get express {
    final a = _area;
    return a == null ? null : DeliveryRules.express(a, now());
  }

  /// True when Express could be chosen (an area in the Express zone).
  bool get expressCovered {
    final a = _area;
    return a != null && DeliveryRules.isCovered(a);
  }

  /// The website's closed-Express notice while Express is chosen but
  /// closed; null otherwise.
  String? get expressClosedNotice {
    final a = _area;
    if (a == null || !isExpress) return null;
    final ex = DeliveryRules.express(a, now());
    return ex.open ? null : DeliveryRules.expressClosed(a, now());
  }

  /// The card line for [product]; null without an area.
  ProductPromise? promiseFor(Product product) => DeliveryRules.productPromise(
    product,
    area: _area,
    mode: _mode,
    now: now(),
  );

  /// True when [product] can come by Express.
  bool isExpressEligible(Product product) =>
      DeliveryRules.isExpressEligible(product);

  /// True once per app run while no area is set: the website opens the
  /// location picker by itself once per session. Call [markAskedForLocation]
  /// after asking.
  bool get shouldAskForLocation => _area == null && !_askedForLocation;

  void markAskedForLocation() => _askedForLocation = true;

  /// Delivers to [area]. Returns the website's toast: "Delivering to
  /// Mirdif", or, when Express was chosen and [area] is outside the Express
  /// zone, "Express isn't available in Jebel Ali. Switched to Fresh
  /// Market." (the mode becomes Fresh Market).
  String setArea(DeliveryArea area) {
    _area = area;
    var message = DeliveryRules.deliveringTo(area);
    if (isExpress && !DeliveryRules.isCovered(area)) {
      _mode = DeliveryMode.market;
      message = DeliveryRules.switchedToMarket(area);
    }
    _save();
    notifyListeners();
    return message;
  }

  /// [setArea] for a picked place; returns null and changes nothing when the
  /// store does not deliver there.
  String? setPlace(DeliveryPlace place) {
    final area = place.toArea();
    return area == null ? null : setArea(area);
  }

  /// Switches mode. Returns null when done, or the website's message when
  /// Express is refused: no area yet ([DeliveryRules.setLocationForExpress];
  /// the UI should open the location picker) or the area is outside the
  /// Express zone. Choosing Express while it is closed is allowed (see
  /// [expressClosedNotice]).
  String? setMode(DeliveryMode mode) {
    final a = _area;
    if (mode == DeliveryMode.express) {
      if (a == null) return DeliveryRules.setLocationForExpress;
      if (!DeliveryRules.isCovered(a)) {
        return DeliveryRules.expressNotCovered(a, now());
      }
    }
    if (mode != _mode) {
      _mode = mode;
      _save();
      notifyListeners();
    }
    return null;
  }

  /// Tells listeners to redraw now (e.g. when the app comes back to the
  /// foreground).
  void refresh() {
    if (!_disposed) notifyListeners();
  }

  /// True while the refresh ticker runs.
  bool get isTicking => _ticker != null;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _syncTicker();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _syncTicker();
  }

  void _syncTicker() {
    final every = refreshEvery;
    if (!_disposed && every != null && hasListeners) {
      _ticker ??= Timer.periodic(every, (_) => refresh());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  void _save() {
    _prefs?.setString(
      prefsKey,
      jsonEncode({'mode': _mode.code, 'area': _area?.toJson()}),
    );
  }

  void _restore() {
    final raw = _prefs?.getString(prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final saved = jsonDecode(raw);
        if (saved is Map) {
          _area = DeliveryArea.fromJson(saved['area']);
          if (saved['mode'] == DeliveryMode.express.code) {
            _mode = DeliveryMode.express;
          }
        }
      } catch (_) {
        // A saved choice we cannot read is dropped.
        _area = null;
        _mode = DeliveryMode.market;
      }
    }
    // Like the website: Express needs an area in the Express zone.
    final a = _area;
    if (isExpress && (a == null || !DeliveryRules.isCovered(a))) {
      _mode = DeliveryMode.market;
    }
  }
}
