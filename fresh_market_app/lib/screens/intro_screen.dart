import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../intro/intro_player.dart';
import '../theme/app_theme.dart';

/// The first-launch intro: the store reel playing full screen, muted,
/// with Skip and "Start shopping" over it. Once the sound is turned on,
/// the speaker's words show as captions over the dark bottom of the
/// picture (when the reel's caption file is bundled).
///
/// [onDone] is called exactly once: on Skip, "Start shopping", the system
/// back button, or when the video reaches its end. The poster image shows
/// until the video's first frame, and stays if the video cannot be played;
/// the controls work either way.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone, this.playerFactory});

  final VoidCallback onDone;

  /// Makes the video player. Leave null in the app; tests pass a fake.
  final IntroPlayerFactory? playerFactory;

  /// Replaces the real video player everywhere a [playerFactory] is not
  /// passed. For tests of screens that open the intro themselves; reset
  /// it to null when the test ends.
  @visibleForTesting
  static IntroPlayerFactory? debugDefaultPlayerFactory;

  static const String posterAsset = 'assets/video/intro_poster.jpg';

  /// The black FRESH® MARKET wordmark (transparent background), shown on
  /// a white rounded rectangle over the video.
  static const String logoAsset = 'assets/images/logo_wide.png';

  static const String handle = '@freshmarket.ae';
  static const String welcome = 'Welcome to Fresh Market';
  static const String headline =
      'Fresh from Ras Al Khor to your door, every morning.';

  static const Key posterKey = ValueKey('intro-poster');
  static const Key videoKey = ValueKey('intro-video');
  static const Key progressKey = ValueKey('intro-progress');
  static const Key muteKey = ValueKey('intro-mute');
  static const Key skipKey = ValueKey('intro-skip');
  static const Key startKey = ValueKey('intro-start');
  static const Key captionKey = ValueKey('intro-caption');

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with WidgetsBindingObserver {
  late final IntroPlayer _player;

  bool _muted = true;
  bool _failed = false;
  bool _finished = false;
  bool _disposed = false;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _inForeground = state == null || state == AppLifecycleState.resumed;
    final factory =
        widget.playerFactory ??
        IntroScreen.debugDefaultPlayerFactory ??
        VideoIntroPlayer.new;
    _player = factory()..addListener(_onPlayerChanged);
    unawaited(_start());
  }

  /// The system's "remove animations" setting: the poster stays and the
  /// video does not play by itself (Skip and Start shopping still work).
  bool get _reduceMotion =>
      context
          .getInheritedWidgetOfExactType<MediaQuery>()
          ?.data
          .disableAnimations ??
      false;

  Future<void> _start() async {
    try {
      await _player.initialize();
      if (_disposed || _finished) return;
      await _player.setMuted(_muted);
      if (_disposed || _finished) return;
      if (_inForeground && !_reduceMotion) await _player.play();
    } catch (_) {
      // No video on this device: the poster stays and the buttons work.
      if (!_disposed) setState(() => _failed = true);
    }
  }

  void _onPlayerChanged() {
    if (_disposed || _finished) return;
    if (_player.isReady && _player.isCompleted) {
      _finish();
      return;
    }
    setState(() {});
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _run(_player.pause);
    widget.onDone();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _run(() => _player.setMuted(_muted));
  }

  /// Player calls that may fail (no video on this device) without it
  /// mattering to the shopper.
  void _run(Future<void> Function() call) {
    try {
      unawaited(call().catchError((Object _) {}));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _inForeground) return;
    _inForeground = foreground;
    if (_finished || _failed || !_player.isReady) return;
    if (foreground && _reduceMotion) return;
    _run(foreground ? _player.play : _player.pause);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_onPlayerChanged);
    try {
      _player.dispose();
    } catch (_) {}
    super.dispose();
  }

  bool get _showVideo =>
      !_failed &&
      _player.isReady &&
      !_player.videoSize.isEmpty &&
      _player.position > Duration.zero;

  /// The caption to show: only while the sound is on, as captions are the
  /// words of the speech.
  String get _caption {
    if (_muted || _failed || !_player.isReady) return '';
    return _player.caption.trim();
  }

  double get _progress {
    if (_failed || !_player.isReady) return 0;
    final total = _player.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_player.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _introOverlayStyle,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _finish();
        },
        child: Material(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: Image.asset(
                  IntroScreen.posterAsset,
                  key: IntroScreen.posterKey,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                ),
              ),
              if (_showVideo)
                ExcludeSemantics(
                  child: FittedBox(
                    key: IntroScreen.videoKey,
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _player.videoSize.width,
                      height: _player.videoSize.height,
                      child: _player.buildView(context),
                    ),
                  ),
                ),
              const IgnorePointer(child: _Scrims()),
              SafeArea(
                minimum: const EdgeInsets.only(top: 12, bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDims.gutter,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProgressLine(value: _progress),
                      const SizedBox(height: 12),
                      _Header(
                        muted: _muted,
                        onToggleMute: _toggleMute,
                        onSkip: _finish,
                      ),
                      const Spacer(),
                      // Kept inside the dark part of the scrim.
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_caption.isNotEmpty) ...[
                              _CaptionLine(text: _caption),
                              const SizedBox(height: 16),
                            ],
                            const _Welcome(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: IntroScreen.startKey,
                        onPressed: _finish,
                        child: const Text('Start shopping'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Light status bar icons over the dark video.
const SystemUiOverlayStyle _introOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarIconBrightness: Brightness.light,
);

/// Translucent ink fill of the mute button and the Skip pill.
const Color _controlFill = Color(0x99111111);

/// Darkens the top and the bottom of the picture so the white text and
/// the controls stay readable on any frame.
class _Scrims extends StatelessWidget {
  const _Scrims();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x8C000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0x99000000),
            Color(0xE6000000),
          ],
          // The bottom one starts a little higher: it holds the welcome
          // line, the headline and the handle.
          stops: [0, 0.22, 0.5, 0.76, 1],
        ),
      ),
    );
  }
}

/// The thin line at the top that fills as the video plays.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        child: LinearProgressIndicator(
          key: IntroScreen.progressKey,
          value: value,
          minHeight: 3,
          backgroundColor: const Color(0x59FFFFFF),
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.onDark),
        ),
      ),
    );
  }
}

/// Soft shadow that keeps white text readable on bright frames.
const List<Shadow> _textShadow = [
  Shadow(color: Color(0x80000000), blurRadius: 6),
];

/// One caption of the speech: white 15/600 on a dark plate, readable on
/// any frame (white on the plate over white is 8:1 or more).
class _CaptionLine extends StatelessWidget {
  const _CaptionLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        key: IntroScreen.captionKey,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: const BoxDecoration(
          color: _captionPlate,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppText.family,
            fontFamilyFallback: AppText.fallback,
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// The dark plate behind a caption.
const Color _captionPlate = Color(0xB3000000);

/// "Welcome to Fresh Market", the headline and the store's handle, above
/// "Start shopping".
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          IntroScreen.welcome,
          style: TextStyle(
            fontFamily: AppText.family,
            fontFamilyFallback: AppText.fallback,
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: _textShadow,
          ),
        ),
        SizedBox(height: 6),
        Text(
          IntroScreen.headline,
          style: TextStyle(
            fontFamily: AppText.family,
            fontFamilyFallback: AppText.fallback,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
            shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
          ),
        ),
        SizedBox(height: 10),
        Text(
          IntroScreen.handle,
          style: TextStyle(
            fontFamily: AppText.family,
            fontFamilyFallback: AppText.fallback,
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: Color(0xE6FFFFFF),
            shadows: _textShadow,
          ),
        ),
      ],
    );
  }
}

/// The wordmark on a white rounded rectangle (left), then Mute and Skip.
class _Header extends StatelessWidget {
  const _Header({
    required this.muted,
    required this.onToggleMute,
    required this.onSkip,
  });

  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onSkip;

  /// Height of the wordmark inside its white rectangle.
  static const double logoHeight = 22;

  @override
  Widget build(BuildContext context) {
    final muteLabel = muted ? 'Unmute' : 'Mute';
    return Row(
      children: [
        // Brand only: the welcome line below says the name to screen
        // readers.
        ExcludeSemantics(
          child: Container(
            height: AppDims.touch,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: AppDims.buttonBorderRadius,
              boxShadow: AppShadows.raised,
            ),
            child: Image.asset(
              IntroScreen.logoAsset,
              height: logoHeight,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: muteLabel,
          child: Tooltip(
            message: muteLabel,
            child: Material(
              color: _controlFill,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: IntroScreen.muteKey,
                onTap: onToggleMute,
                child: SizedBox(
                  width: AppDims.touch,
                  height: AppDims.touch,
                  child: Icon(
                    muted
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          child: Material(
            color: _controlFill,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: IntroScreen.skipKey,
              onTap: onSkip,
              child: SizedBox(
                height: AppDims.touch,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Skip',
                        // The pill keeps its 44px height at any text size.
                        textScaler: MediaQuery.textScalerOf(context)
                            .clamp(maxScaleFactor: 1.3),
                        style: const TextStyle(
                          fontFamily: AppText.family,
                          fontFamilyFallback: AppText.fallback,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
