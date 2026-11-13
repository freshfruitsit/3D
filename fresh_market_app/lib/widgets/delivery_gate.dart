import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../delivery/delivery.dart';
import '../screens/location_screen.dart';

/// Shows the delivery location picker until a delivery area is saved,
/// then [child] (the shop).
///
/// On the first launch the picker must be completed before shopping: it
/// has no close button and system back does not skip it. Once an area is
/// saved, later launches go straight to [child]; the area can be changed
/// any time from the Home header.
///
/// [child] is built straight away underneath, so the shop loads while the
/// shopper picks an area. It also tells the delivery store to refresh its
/// promises when the app comes back to the foreground.
class DeliveryGate extends StatefulWidget {
  const DeliveryGate({super.key, required this.child});

  final Widget child;

  @override
  State<DeliveryGate> createState() => _DeliveryGateState();
}

class _DeliveryGateState extends State<DeliveryGate> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () {
      if (mounted) context.read<DeliveryStore>().refresh();
    },
  );

  @override
  void initState() {
    super.initState();
    // Created now so it hears the first resume.
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onPicked(String message) {
    if (!mounted) return;
    AppNav.showNotice(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final open = context.select<DeliveryStore, bool>((s) => s.hasArea);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: !open,
          child: TickerMode(enabled: open, child: widget.child),
        ),
        if (!open)
          PopScope(
            // Back must not skip the first choice of area.
            canPop: false,
            child: LocationScreen(firstLaunch: true, onPicked: _onPicked),
          ),
      ],
    );
  }
}
