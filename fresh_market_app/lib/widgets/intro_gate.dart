import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../intro/intro_player.dart';
import '../screens/intro_screen.dart';
import '../theme/app_theme.dart';

/// Shows the intro video on the very first launch, then [child].
///
/// On later launches [child] shows straight away. While the saved flag is
/// being read only the plain page background is shown, so the intro never
/// flashes. [child] is not built until the intro has finished.
///
/// If device storage cannot be read the intro is skipped, so a shopper is
/// never made to watch it on every launch.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child, this.playerFactory});

  final Widget child;

  /// Passed to [IntroScreen]; leave null in the app.
  final IntroPlayerFactory? playerFactory;

  /// shared_preferences key; true once the intro has been finished.
  static const String seenKey = 'intro_seen_v1';

  @override
  State<IntroGate> createState() => _IntroGateState();
}

enum _GateState { loading, intro, done }

class _IntroGateState extends State<IntroGate> {
  _GateState _state = _GateState.loading;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var seen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      seen = prefs.getBool(IntroGate.seenKey) ?? false;
    } catch (_) {
      seen = true;
    }
    if (!mounted) return;
    setState(() => _state = seen ? _GateState.done : _GateState.intro);
  }

  void _onIntroDone() {
    if (_state == _GateState.done) return;
    setState(() => _state = _GateState.done);
    final prefs = _prefs;
    if (prefs != null) {
      unawaited(
        prefs
            .setBool(IntroGate.seenKey, true)
            .then<void>((_) {})
            .catchError((Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _GateState.loading => const ColoredBox(
          color: AppColors.page,
          child: SizedBox.expand(),
        ),
      _GateState.intro => IntroScreen(
          onDone: _onIntroDone,
          playerFactory: widget.playerFactory,
        ),
      _GateState.done => widget.child,
    };
  }
}
