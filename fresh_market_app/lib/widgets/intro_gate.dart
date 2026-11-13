import 'package:material_ui/material_ui.dart';

import '../intro/intro_player.dart';
import '../screens/intro_screen.dart';

/// Shows the intro video every time the app starts, then [child].
///
/// [child] is built straight away, hidden under the intro, so the shop
/// loads its products while the video plays and is ready the moment the
/// shopper taps Skip or Start shopping. While hidden it is not painted,
/// cannot be tapped, is left out of accessibility and its animations are
/// paused.
class IntroGate extends StatefulWidget {
  const IntroGate({
    super.key,
    required this.child,
    this.playerFactory,
    this.enabled = true,
  });

  final Widget child;

  /// Passed to [IntroScreen]; leave null in the app.
  final IntroPlayerFactory? playerFactory;

  /// False shows [child] straight away (tests).
  final bool enabled;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  late bool _done = !widget.enabled;

  void _onIntroDone() {
    if (_done) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    // The child keeps the same place in the tree before and after the
    // intro, so it is not rebuilt from scratch when the intro ends.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: !_done,
          child: TickerMode(enabled: _done, child: widget.child),
        ),
        if (!_done)
          IntroScreen(
            onDone: _onIntroDone,
            playerFactory: widget.playerFactory,
          ),
      ],
    );
  }
}
