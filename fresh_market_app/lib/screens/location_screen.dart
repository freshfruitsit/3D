import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../delivery/delivery.dart';
import '../services/device_location.dart';
import '../services/location_services.dart';
import '../theme/app_theme.dart';

/// The delivery location picker, as on the website: the phone's location,
/// a search for an area, street or building, an optional map with the
/// Express zone, and "What you get" for the place picked. "Deliver to …"
/// saves it in the [DeliveryStore].
///
/// Opened from the Home header (with a close button) through
/// `AppNav.openLocationPicker`, which it closes with the website's message
/// ("Delivering to Mirdif"). On the first launch the delivery gate shows
/// it with [firstLaunch] (no close button) and gets the message through
/// [onPicked].
class LocationScreen extends StatefulWidget {
  const LocationScreen({
    super.key,
    this.firstLaunch = false,
    this.reason,
    this.onPicked,
    this.pickOnly = false,
    this.initialArea,
  });

  /// The first choice of area: it must be made, so there is no close
  /// button.
  final bool firstLaunch;

  /// Why the picker opened, shown at the top ("Set your location to check
  /// Express").
  final String? reason;

  /// Receives the message after a place was saved. When null the screen
  /// closes its route with the message as the result.
  final ValueChanged<String>? onPicked;

  /// Picks the area of a saved address: the chosen [DeliveryArea] closes
  /// the route as its result and the delivery location is not changed.
  final bool pickOnly;

  /// Where a [pickOnly] picker starts; the delivery area when null.
  final DeliveryArea? initialArea;

  /// The [pickOnly] title, subtitle and note under the button.
  static const String addressTitle = 'Where is this address?';
  static const String addressSubtitle =
      'Choose the area this address is in. Your delivery location stays '
      'the same.';
  static const String addressNote =
      'The emirate comes from the area you choose.';

  static const String subtitle =
      "We'll show delivery times and what's available for your area.";
  static const String searchHint = 'Search area, street or building';
  static const String useMyLocation = 'Use my current location';
  static const String locating = 'Finding your location…';

  // Phone location problems.
  static const String serviceOffMessage =
      'Location is turned off on your phone. Turn it on, or search for your '
      'area.';
  static const String deniedForeverMessage =
      'Location access is off for Fresh Market. Allow it in Settings, or '
      'search for your area.';
  static const String timeoutMessage =
      "We couldn't find your location in time. Try again, or search for "
      'your area.';
  static const String failedMessage =
      "We couldn't read your location. Search for your area instead.";

  /// OpenStreetMap tiles, as the website's map uses.
  static const String tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'ae.freshmarket.fresh_market_app';
  static const String attribution = '© OpenStreetMap contributors';
  static const String mapHint = 'Tap the map or drag it to move the pin.';
  /// The Express zone's fill on the map: the accent at 10%.
  static const Color zoneFill = Color(0x1A0E7C3A);

  static const String tilesFailed =
      "The map couldn't load. Search for your area instead.";

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

/// What to say after "Use my current location" failed, and the button
/// that helps.
class _GpsNotice {
  const _GpsNotice(this.text, {this.actionLabel, this.action});

  final String text;
  final String? actionLabel;
  final VoidCallback? action;
}

class _LocationScreenState extends State<LocationScreen> {
  late final LocationServices _services;
  late final PlaceSearchController _search;
  final TextEditingController _text = TextEditingController();
  final MapController _map = MapController();

  /// The "What you get" panel, scrolled into view after a pick from the
  /// list or the phone's location.
  final GlobalKey _panelKey = GlobalKey();

  /// The place the "What you get" panel and the button are for.
  DeliveryPlace? _pick;

  /// Counts picks, so a slow reverse lookup of an older pin is ignored.
  int _pickSeq = 0;

  /// A reverse lookup of the pin is running ("Finding this spot…").
  bool _resolving = false;

  bool _locating = false;
  _GpsNotice? _gpsNotice;

  bool _mapReady = false;

  /// A finger is on the map: the page must not scroll under it.
  bool _mapTouched = false;
  bool _tilesFailed = false;

  @override
  void initState() {
    super.initState();
    _services = context.read<LocationServices?>() ?? const LocationServices();
    _search = PlaceSearchController(search: _services.search);
    // Opened to change the area: start from the current one.
    final area = widget.initialArea ?? context.read<DeliveryStore>().area;
    if (area != null) _pick = DeliveryPlace.fromArea(area);
  }

  @override
  void dispose() {
    _search.dispose();
    _text.dispose();
    _map.dispose();
    super.dispose();
  }

  // ---- picking ------------------------------------------------------------

  void _pickPlace(DeliveryPlace place) {
    FocusManager.instance.primaryFocus?.unfocus();
    _pickSeq++;
    setState(() {
      _pick = place;
      _resolving = false;
    });
    _moveMap(place.lat, place.lng);
    _showPanel();
  }

  void _showPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panel = _panelKey.currentContext;
      if (!mounted || panel == null) return;
      Scrollable.ensureVisible(
        panel,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// A phone fix or a pin: named at once from the website's areas, then
  /// (with the remote search) by the geocoder, like the website.
  Future<void> _pickPoint(
    double lat,
    double lng, {
    bool moveMap = false,
  }) async {
    final seq = ++_pickSeq;
    final search = _services.search;
    setState(() {
      _pick = DeliveryRules.placeFromPoint(lat, lng);
      _resolving = search != null;
    });
    if (moveMap) _moveMap(lat, lng);
    if (search == null) return;
    final resolved = await search.resolvePoint(lat, lng);
    if (!mounted || seq != _pickSeq) return;
    setState(() {
      _pick = resolved;
      _resolving = false;
    });
  }

  void _moveMap(double lat, double lng) {
    if (!_mapReady) return;
    try {
      _map.move(
        LatLng(lat, lng),
        _map.camera.zoom < 12 ? 13 : _map.camera.zoom,
      );
    } catch (_) {
      // The map is not laid out yet; the pick still counts.
    }
  }

  void _confirm() {
    final pick = _pick;
    if (pick == null) return;
    if (widget.pickOnly) {
      final area = pick.toArea();
      if (area != null) Navigator.of(context).pop(area);
      return;
    }
    final message = context.read<DeliveryStore>().setPlace(pick);
    if (message == null) return; // not a place we deliver to
    final onPicked = widget.onPicked;
    if (onPicked != null) {
      onPicked(message);
    } else {
      Navigator.of(context).pop(message);
    }
  }

  // ---- phone location ------------------------------------------------------

  Future<void> _useMyLocation() async {
    if (_locating) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _locating = true;
      _gpsNotice = null;
    });
    final outcome = await _services.device.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    switch (outcome) {
      case LocationFix(:final lat, :final lng):
        unawaited(_pickPoint(lat, lng, moveMap: true));
        _showPanel();
      case LocationFailure(:final problem):
        setState(() => _gpsNotice = _noticeFor(problem));
    }
  }

  _GpsNotice _noticeFor(LocationProblem problem) {
    final device = _services.device;
    return switch (problem) {
      LocationProblem.serviceOff => _GpsNotice(
        LocationScreen.serviceOffMessage,
        actionLabel: 'Turn on location',
        action: () => device.openLocationSettings(),
      ),
      LocationProblem.denied => _GpsNotice(
        _services.showMap
            ? DeliveryCopy.locationNotShared
            : 'Location wasn’t shared. Search for your area.',
        actionLabel: 'Try again',
        action: _useMyLocation,
      ),
      LocationProblem.deniedForever => _GpsNotice(
        LocationScreen.deniedForeverMessage,
        actionLabel: 'Open settings',
        action: () => device.openAppSettings(),
      ),
      LocationProblem.timeout => _GpsNotice(
        LocationScreen.timeoutMessage,
        actionLabel: 'Try again',
        action: _useMyLocation,
      ),
      LocationProblem.failed => const _GpsNotice(LocationScreen.failedMessage),
    };
  }

  // ---- map -----------------------------------------------------------------

  void _onMapEvent(MapEvent event) {
    if (event.source == MapEventSource.mapController) return;
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd) {
      final c = event.camera.center;
      unawaited(_pickPoint(c.latitude, c.longitude));
    }
  }

  void _onMapTap(LatLng point) {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_pickPoint(point.latitude, point.longitude, moveMap: true));
  }

  void _onTileError() {
    if (_tilesFailed || !mounted) return;
    // Called while tiles load, possibly during a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tilesFailed = true);
    });
  }

  void _setMapTouched(bool touched) {
    if (_mapTouched != touched) setState(() => _mapTouched = touched);
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    var summary = DeliveryCopy.pickSummary(
      _pick,
      store.now(),
      hasMap: _services.showMap,
    );
    final pickedArea = _pick?.toArea();
    if (widget.pickOnly) {
      summary = PickSummary(
        heading: summary.heading,
        placeLabel: summary.placeLabel,
        options: summary.options,
        buttonLabel: summary.canConfirm && pickedArea != null
            ? 'Use ${pickedArea.name}'
            : summary.buttonLabel,
        canConfirm: summary.canConfirm,
        note: summary.canConfirm ? LocationScreen.addressNote : summary.note,
      );
    }
    final reason = widget.reason;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: widget.pickOnly
                  ? LocationScreen.addressTitle
                  : DeliveryCopy.pickerTitle(hasArea: store.hasArea),
              subtitle: widget.pickOnly
                  ? LocationScreen.addressSubtitle
                  : LocationScreen.subtitle,
              onClose: widget.firstLaunch
                  ? null
                  : () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('location-list'),
                physics: _mapTouched
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppDims.gutter,
                  4,
                  AppDims.gutter,
                  24,
                ),
                children: [
                  if (reason != null) ...[
                    _Banner(text: reason),
                    const SizedBox(height: 12),
                  ],
                  _SearchField(
                    controller: _text,
                    onChanged: (value) {
                      _search.setTerm(value);
                      setState(() {}); // the clear button
                    },
                    onClear: () {
                      _text.clear();
                      _search.clear();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  _GpsButton(locating: _locating, onTap: _useMyLocation),
                  if (_gpsNotice != null) ...[
                    const SizedBox(height: 12),
                    _NoticeBox(notice: _gpsNotice!),
                  ],
                  const SizedBox(height: 24),
                  ListenableBuilder(
                    listenable: _search,
                    builder: (context, _) => _Suggestions(
                      term: _search.term,
                      rows: _search.suggestions,
                      status: _search.statusText(hasMap: _services.showMap),
                      searching: _search.searching,
                      selected: _pick,
                      onPick: _pickPlace,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _WhatYouGet(
                    key: _panelKey,
                    summary: summary,
                    resolving: _resolving,
                    pickedNothing: _pick == null,
                  ),
                  if (_services.showMap) ...[
                    const SizedBox(height: 20),
                    _mapBox(),
                  ],
                ],
              ),
            ),
            _ConfirmBar(summary: summary, onConfirm: _confirm),
          ],
        ),
      ),
    );
  }

  Widget _mapBox() {
    final pick = _pick;
    const hub = DeliveryConfig.hub;
    final start = pick == null
        ? const LatLng(25.18, 55.36)
        : LatLng(pick.lat, pick.lng);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Map. ${LocationScreen.mapHint}',
          child: ClipRRect(
            borderRadius: AppDims.bannerBorderRadius,
            child: SizedBox(
              height: 220,
              child: Listener(
                onPointerDown: (_) => _setMapTouched(true),
                onPointerUp: (_) => _setMapTouched(false),
                onPointerCancel: (_) => _setMapTouched(false),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: start,
                          initialZoom: pick == null ? 10 : 13,
                          minZoom: 6,
                          maxZoom: 18,
                          backgroundColor: AppColors.subtle,
                          interactionOptions: const InteractionOptions(
                            flags:
                                InteractiveFlag.all & ~InteractiveFlag.rotate,
                          ),
                          onMapReady: () => _mapReady = true,
                          onTap: (_, point) => _onMapTap(point),
                          onMapEvent: _onMapEvent,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: LocationScreen.tileUrl,
                            userAgentPackageName:
                                LocationScreen.userAgentPackageName,
                            errorTileCallback: (_, _, _) => _onTileError(),
                          ),
                          // A hint of the Express zone under the streets;
                          // with no streets (tiles failed) it would be a
                          // mint slab, so the calm placeholder stays.
                          if (!_tilesFailed)
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: LatLng(hub.lat, hub.lng),
                                  radius: DeliveryConfig.expressKm * 1000,
                                  useRadiusInMeter: true,
                                  color: LocationScreen.zoneFill,
                                  borderColor: AppColors.green,
                                  borderStrokeWidth: 1.5,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(hub.lat, hub.lng),
                                width: 28,
                                height: 28,
                                child: const _HubMarker(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // The pin sits at the centre: dragging the map moves
                    // the spot under it, a tap brings that spot here.
                    if (pick != null)
                      const IgnorePointer(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 36),
                            child: Icon(
                              Icons.location_on,
                              size: 40,
                              color: AppColors.ink,
                              shadows: [
                                Shadow(color: Color(0x66FFFFFF), blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          color: const Color(0xD9FFFFFF),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            LocationScreen.attribution,
                            style: AppText.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_tilesFailed)
                      Positioned(
                        left: 8,
                        right: 8,
                        top: 8,
                        child: IgnorePointer(
                          child: _MapNote(text: LocationScreen.tilesFailed),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: LocationScreen.zoneFill,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.green, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Express zone: ${DeliveryConfig.expressKm.round()} km around '
                'our ${DeliveryConfig.hubName}. ${LocationScreen.mapHint}',
                style: AppText.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Title (24/800), subtitle and, when it may be closed, the close button.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDims.gutter,
        8,
        onClose == null ? AppDims.gutter : 4,
        16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The 48px close button's centre lines up with the
                // title's.
                const SizedBox(height: 8),
                Semantics(
                  header: true,
                  child: Text(title, style: AppText.title),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppText.bodySmall.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              tooltip: 'Close',
              icon: const Icon(Icons.close, color: AppColors.ink),
            ),
        ],
      ),
    );
  }
}

/// Off-white info card with an info icon: why the picker opened.
class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppDecor.info,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The off-white, borderless search input (the theme's input style).
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: AppText.body,
      decoration: InputDecoration(
        hintText: LocationScreen.searchHint,
        prefixIcon: const Icon(Icons.search, color: AppColors.ink, size: 22),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, color: AppColors.secondary),
              ),
      ),
    );
  }
}

/// "Use my current location": a white row with a hairline, the green
/// target icon and a chevron; a spinner and "Finding your location…"
/// while it looks.
class _GpsButton extends StatelessWidget {
  const _GpsButton({required this.locating, required this.onTap});

  final bool locating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label =
        locating ? LocationScreen.locating : LocationScreen.useMyLocation;
    return Semantics(
      button: true,
      enabled: !locating,
      label: label,
      onTap: locating ? null : onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: AppDims.cardBorderRadius,
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: AppColors.surface,
          shape: AppDecor.cardShape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: locating ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: locating
                          ? const Padding(
                              padding: EdgeInsets.all(2),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(
                              Icons.my_location,
                              size: 22,
                              color: AppColors.green,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: locating
                              ? AppColors.secondary
                              : AppColors.ink,
                        ),
                      ),
                    ),
                    if (!locating)
                      const Icon(
                        Icons.chevron_right,
                        size: 22,
                        color: AppColors.tertiary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A problem with the phone's location and the button that helps: an
/// off-white info card in ink (no alarm colours).
class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.notice});

  final _GpsNotice notice;

  @override
  Widget build(BuildContext context) {
    final label = notice.actionLabel;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 12, 4, label == null ? 12 : 2),
        decoration: AppDecor.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_disabled,
                    size: 20,
                    color: AppColors.ink,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(notice.text, style: AppText.bodySmall),
                  ),
                ],
              ),
            ),
            if (label != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: notice.action, child: Text(label)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The rows under the search field: the store row, the website's areas
/// and (with the remote search) addresses, in a white card with hairline
/// separators; or a status line.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.term,
    required this.rows,
    required this.status,
    required this.searching,
    required this.selected,
    required this.onPick,
  });

  final String term;
  final List<DeliveryPlace> rows;
  final String? status;
  final bool searching;
  final DeliveryPlace? selected;
  final ValueChanged<DeliveryPlace> onPick;

  @override
  Widget build(BuildContext context) {
    final heading = term.trim().isEmpty ? 'Suggested areas' : 'Places found';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(heading, style: AppText.cardHeading),
              ),
            ),
            if (searching && rows.isNotEmpty)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isNotEmpty)
          Container(
            decoration: AppDecor.card,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 50,
                      color: AppColors.hairline,
                    ),
                  _PlaceRow(
                    place: rows[i],
                    selected: _same(rows[i], selected),
                    onTap: () => onPick(rows[i]),
                  ),
                ],
              ],
            ),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                status!,
                style: AppText.bodySmall.copyWith(color: AppColors.secondary),
              ),
            ),
          ),
      ],
    );
  }

  static bool _same(DeliveryPlace a, DeliveryPlace? b) =>
      b != null && a.name == b.name && a.lat == b.lat && a.lng == b.lng;
}

/// One suggestion: pin, name, emirate or address, an "Express" tag inside
/// the Express zone and an ink check when it is the current pick.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  final DeliveryPlace place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final covered = place.deliverable && DeliveryRules.isCovered(place);
    final subtitle = place.subtitle;
    return Semantics(
      button: true,
      selected: selected,
      label: [
        place.name,
        if (subtitle.isNotEmpty) subtitle,
        if (covered) 'Express available',
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                children: [
                  Icon(
                    place.isStore
                        ? Icons.storefront_outlined
                        : Icons.location_on_outlined,
                    size: 22,
                    color: selected ? AppColors.ink : AppColors.secondary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.productName.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (covered) ...[
                    const SizedBox(width: 8),
                    const ExpressTag(),
                  ],
                  if (selected) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.check_circle,
                      size: 22,
                      color: AppColors.ink,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small green-soft "Express" pill with a green bolt.
class ExpressTag extends StatelessWidget {
  const ExpressTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 3, 8, 3),
      decoration: const BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: AppDims.pillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, size: 14, color: AppColors.green),
          const SizedBox(width: 2),
          Text(
            'Express',
            style: AppText.tag.copyWith(color: AppColors.green),
          ),
        ],
      ),
    );
  }
}

/// The hub on the map: an ink disc with a white storefront.
class _HubMarker extends StatelessWidget {
  const _HubMarker();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ink,
        shape: BoxShape.circle,
        boxShadow: AppShadows.raised,
      ),
      child: Center(
        child: Icon(Icons.storefront, size: 16, color: AppColors.onDark),
      ),
    );
  }
}

class _MapNote extends StatelessWidget {
  const _MapNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDims.controlBorderRadius,
        boxShadow: AppShadows.raised,
      ),
      child: Text(text, style: AppText.caption.copyWith(color: AppColors.ink)),
    );
  }
}

/// "What you get in …" as an off-white card (radius 14): the Fresh Market
/// and Express rows exactly as the website words them, or why nothing can
/// be delivered.
class _WhatYouGet extends StatelessWidget {
  const _WhatYouGet({
    super.key,
    required this.summary,
    required this.resolving,
    required this.pickedNothing,
  });

  final PickSummary summary;
  final bool resolving;
  final bool pickedNothing;

  @override
  Widget build(BuildContext context) {
    final place = summary.placeLabel;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.subtle,
        borderRadius: AppDims.cardBorderRadius,
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: summary.heading),
                  if (place != null) ...[
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: place,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
              style: AppText.cardHeading,
            ),
          ),
          if (resolving)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(DeliveryCopy.findingSpot, style: AppText.caption),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < summary.options.length; i++)
            _OptionRow(
              option: summary.options[i],
              icon: !summary.canConfirm
                  ? (pickedNothing
                        ? Icons.place_outlined
                        : Icons.location_off_outlined)
                  : (i == 0 ? Icons.storefront : Icons.bolt),
              express: summary.canConfirm && i == 1,
              divider: i > 0,
            ),
        ],
      ),
    );
  }
}

/// One option: a white disc with its icon (Express: a green bolt), then
/// the title, the time (Express: in green) and the detail, stacked so
/// nothing wraps mid-phrase on a narrow phone. Unavailable options are
/// drawn in grey.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.icon,
    required this.express,
    required this.divider,
  });

  final PickOption option;
  final IconData icon;

  /// The Express row of a place we deliver to.
  final bool express;
  final bool divider;

  /// Keeps a number with its unit ("6 hours", "10 PM", "7 km") on one
  /// line when the text wraps, and a hyphenated word ("same-day",
  /// "cut-off") whole: its hyphen becomes Inter's non-breaking hyphen,
  /// which looks the same.
  static String _keepUnits(String text) => text
      .replaceAllMapped(RegExp(r'(\d) (?=\S)'), (m) => '${m[1]}\u00A0')
      .replaceAllMapped(RegExp(r'(\w)-(?=\w)'), (m) => '${m[1]}\u2011');

  @override
  Widget build(BuildContext context) {
    final available = option.available;
    final Color iconColor = !available
        ? AppColors.tertiary
        : (express ? AppColors.green : AppColors.ink);
    final Color whenColor = !available
        ? AppColors.secondary
        : (express ? AppColors.green : AppColors.ink);
    return Container(
      decoration: divider
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.hairline)),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.title,
                  style: AppText.productName.copyWith(
                    fontWeight: FontWeight.w700,
                    color: available ? AppColors.ink : AppColors.secondary,
                  ),
                ),
                if (option.when.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _keepUnits(option.when),
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w800,
                      color: whenColor,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(_keepUnits(option.detail), style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sticky white bar with the green "Deliver to …" button and the
/// website's note under it.
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.summary, required this.onConfirm});

  final PickSummary summary;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
        boxShadow: AppShadows.sticky,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDims.gutter,
            12,
            AppDims.gutter,
            10,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: summary.canConfirm ? onConfirm : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(summary.buttonLabel, maxLines: 1),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                summary.note,
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
