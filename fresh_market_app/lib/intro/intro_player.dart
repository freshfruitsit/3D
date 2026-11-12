import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// What the intro screen needs from a video player. The app uses
/// [VideoIntroPlayer]; tests supply a fake, because a real video cannot
/// play in a widget test.
///
/// Listeners are told whenever [isReady], [position], [duration] or
/// [isCompleted] change.
abstract class IntroPlayer implements Listenable {
  /// Loads the video. Throws if it cannot be played.
  Future<void> initialize();

  /// True once [initialize] has finished and the video can be shown.
  bool get isReady;

  /// Pixel size of the video; [Size.zero] until [isReady].
  Size get videoSize;

  Duration get position;
  Duration get duration;

  /// True once playback has reached the end.
  bool get isCompleted;

  Future<void> play();
  Future<void> pause();
  Future<void> setMuted(bool muted);

  /// The moving picture, sized by its parent. Only called when [isReady].
  Widget buildView(BuildContext context);

  void dispose();
}

/// Makes the player for one showing of the intro.
typedef IntroPlayerFactory = IntroPlayer Function();

/// Plays the bundled store reel with the video_player plugin.
class VideoIntroPlayer implements IntroPlayer {
  VideoIntroPlayer({this.asset = introVideoAsset});

  static const String introVideoAsset = 'assets/video/intro.mp4';

  final String asset;

  // Other apps' audio (music, a call) keeps playing: the intro starts
  // muted and must not take the audio away from them.
  late final VideoPlayerController _controller = VideoPlayerController.asset(
    asset,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );

  VideoPlayerValue get _value => _controller.value;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  bool get isReady => _value.isInitialized && !_value.hasError;

  @override
  Size get videoSize => _value.size;

  @override
  Duration get position => _value.position;

  @override
  Duration get duration => _value.duration;

  @override
  bool get isCompleted => _value.isCompleted;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> setMuted(bool muted) => _controller.setVolume(muted ? 0 : 1);

  @override
  Widget buildView(BuildContext context) => VideoPlayer(_controller);

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  void dispose() {
    _controller.dispose();
  }
}
