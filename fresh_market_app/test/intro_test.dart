import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/intro/intro_player.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/intro_screen.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/intro_gate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_app.dart';

/// A player the test drives by hand.
class FakeIntroPlayer extends ChangeNotifier implements IntroPlayer {
  FakeIntroPlayer({this.failInitialize = false});

  final bool failInitialize;

  bool ready = false;
  bool playing = false;
  bool disposed = false;
  bool? muted;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 34);
  @override
  bool isCompleted = false;

  @override
  bool get isReady => ready;

  @override
  Size get videoSize => ready ? const Size(720, 1280) : Size.zero;

  @override
  Future<void> initialize() async {
    if (failInitialize) throw PlatformException(code: 'no-video');
    ready = true;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> setMuted(bool value) async => muted = value;

  @override
  Widget buildView(BuildContext context) =>
      const ColoredBox(color: Color(0xFF123456));

  void seek(Duration to, {bool completed = false}) {
    position = to;
    isCompleted = completed;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Future<void> pumpIntro(
  WidgetTester tester, {
  required FakeIntroPlayer player,
  required VoidCallback onDone,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) async {
  usePhoneSize(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          padding: viewPadding,
          viewPadding: viewPadding,
        ),
        child: IntroScreen(onDone: onDone, playerFactory: () => player),
      ),
    ),
  );
  await tester.pump();
}

double progressOf(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byKey(IntroScreen.progressKey))
    .value!;

void main() {
  tearDown(() => IntroScreen.debugDefaultPlayerFactory = null);

  group('IntroScreen', () {
    testWidgets('plays muted and shows the poster until the first frame',
        (tester) async {
      final player = FakeIntroPlayer();
      await pumpIntro(tester, player: player, onDone: () {});

      expect(player.muted, isTrue);
      expect(player.playing, isTrue);
      expect(find.byKey(IntroScreen.posterKey), findsOneWidget);
      expect(find.byKey(IntroScreen.videoKey), findsNothing);
      expect(progressOf(tester), 0);

      expect(find.text('@freshmarket.ae'), findsOneWidget);
      expect(find.text('Welcome to Fresh Market'), findsOneWidget);
      expect(
        find.text('Fresh from Ras Al Khor to your door, every morning.'),
        findsOneWidget,
      );
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Start shopping'), findsOneWidget);

      player.seek(const Duration(seconds: 17));
      await tester.pump();

      final video = find.byKey(IntroScreen.videoKey);
      expect(video, findsOneWidget);
      expect(tester.widget<FittedBox>(video).fit, BoxFit.cover);
      expect(tester.getSize(video), const Size(390, 844));
      expect(progressOf(tester), closeTo(0.5, 0.001));
    });

    testWidgets('the mute button turns the sound on and off', (tester) async {
      final player = FakeIntroPlayer();
      await pumpIntro(tester, player: player, onDone: () {});

      final semantics = tester.ensureSemantics();
      expect(find.byTooltip('Unmute'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Unmute')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      await tester.tap(find.byKey(IntroScreen.muteKey));
      await tester.pump();
      expect(player.muted, isFalse);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Mute')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      semantics.dispose();

      await tester.tap(find.byKey(IntroScreen.muteKey));
      await tester.pump();
      expect(player.muted, isTrue);
    });

    testWidgets('the top controls are 44px touch targets', (tester) async {
      await pumpIntro(tester, player: FakeIntroPlayer(), onDone: () {});

      expect(tester.getSize(find.byKey(IntroScreen.muteKey)),
          const Size(44, 44));
      final skip = tester.getSize(find.byKey(IntroScreen.skipKey));
      expect(skip.height, 44);
      expect(skip.width, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(IntroScreen.startKey)).width, 390 - 32);
    });

    testWidgets('Skip finishes once, even when tapped twice', (tester) async {
      var done = 0;
      final player = FakeIntroPlayer();
      await pumpIntro(tester, player: player, onDone: () => done++);

      await tester.tap(find.byKey(IntroScreen.skipKey));
      await tester.tap(find.byKey(IntroScreen.skipKey));
      await tester.tap(find.byKey(IntroScreen.startKey));
      player.seek(const Duration(seconds: 34), completed: true);
      await tester.pump();

      expect(done, 1);
      expect(player.playing, isFalse);
    });

    testWidgets('Start shopping finishes', (tester) async {
      var done = 0;
      await pumpIntro(tester, player: FakeIntroPlayer(), onDone: () => done++);

      await tester.tap(find.byKey(IntroScreen.startKey));
      expect(done, 1);
    });

    testWidgets('the Android back button finishes', (tester) async {
      var done = 0;
      await pumpIntro(tester, player: FakeIntroPlayer(), onDone: () => done++);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(done, 1);
      expect(find.byType(IntroScreen), findsOneWidget);
    });

    testWidgets('the video ending finishes', (tester) async {
      var done = 0;
      final player = FakeIntroPlayer();
      await pumpIntro(tester, player: player, onDone: () => done++);

      player.seek(const Duration(seconds: 33));
      await tester.pump();
      expect(done, 0);

      player.seek(const Duration(seconds: 34), completed: true);
      player.seek(const Duration(seconds: 34), completed: true);
      await tester.pump();
      expect(done, 1);
    });

    testWidgets('keeps the poster and working controls when the video fails',
        (tester) async {
      var done = 0;
      final player = FakeIntroPlayer(failInitialize: true);
      await pumpIntro(tester, player: player, onDone: () => done++);

      expect(find.byKey(IntroScreen.posterKey), findsOneWidget);
      expect(find.byKey(IntroScreen.videoKey), findsNothing);
      expect(player.playCalls, 0);
      expect(progressOf(tester), 0);

      await tester.tap(find.byKey(IntroScreen.muteKey));
      await tester.pump();
      expect(find.byTooltip('Mute'), findsOneWidget);

      await tester.tap(find.byKey(IntroScreen.startKey));
      expect(done, 1);
    });

    testWidgets('falls back to the poster with the real player in tests',
        (tester) async {
      var done = 0;
      usePhoneSize(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: IntroScreen(onDone: () => done++),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(IntroScreen.posterKey), findsOneWidget);
      expect(find.byKey(IntroScreen.videoKey), findsNothing);
      await tester.tap(find.byKey(IntroScreen.skipKey));
      expect(done, 1);
    });

    testWidgets('pauses in the background and resumes on return',
        (tester) async {
      final player = FakeIntroPlayer();
      await pumpIntro(tester, player: player, onDone: () {});
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      expect(player.playing, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(player.playing, isFalse);
      expect(player.pauseCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(player.playing, isTrue);
      expect(player.playCalls, 2);
    });

    testWidgets('does not resume after it has finished', (tester) async {
      final player = FakeIntroPlayer();
      await pumpIntro(tester, player: player, onDone: () {});
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));

      await tester.tap(find.byKey(IntroScreen.skipKey));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(player.playing, isFalse);
    });

    testWidgets('disposes the player', (tester) async {
      final player = FakeIntroPlayer();
      await pumpIntro(tester, player: player, onDone: () {});
      expect(player.disposed, isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(player.disposed, isTrue);
    });

    testWidgets('keeps clear of the status bar and the gesture bar',
        (tester) async {
      await pumpIntro(
        tester,
        player: FakeIntroPlayer(),
        onDone: () {},
        viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
      );

      expect(
        tester.getTopLeft(find.byKey(IntroScreen.progressKey)).dy,
        greaterThanOrEqualTo(47),
      );
      expect(
        tester.getBottomLeft(find.byKey(IntroScreen.startKey)).dy,
        lessThanOrEqualTo(844 - 34),
      );
      // The picture itself still fills the whole screen.
      expect(tester.getSize(find.byKey(IntroScreen.posterKey)),
          const Size(390, 844));
    });

    testWidgets('fits a small phone with large text', (tester) async {
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: IntroScreen(onDone: () {}, playerFactory: FakeIntroPlayer.new),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('IntroGate', () {
    Future<void> pumpGate(WidgetTester tester, FakeIntroPlayer player) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: IntroGate(
            playerFactory: () => player,
            child: const Text('the shop'),
          ),
        ),
      );
    }

    testWidgets('first launch: intro, then the app, and the flag is stored',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpGate(tester, FakeIntroPlayer());

      // While the flag loads: neither the intro nor the app.
      expect(find.byType(IntroScreen), findsNothing);
      expect(find.text('the shop'), findsNothing);
      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox).last).color,
        AppColors.page,
      );

      await tester.pumpAndSettle();
      expect(find.byType(IntroScreen), findsOneWidget);
      expect(find.text('the shop'), findsNothing);

      await tester.tap(find.byKey(IntroScreen.startKey));
      await tester.pumpAndSettle();
      expect(find.byType(IntroScreen), findsNothing);
      expect(find.text('the shop'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(IntroGate.seenKey), isTrue);
    });

    testWidgets('the video ending also opens the app', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final player = FakeIntroPlayer();
      await pumpGate(tester, player);
      await tester.pumpAndSettle();

      player.seek(const Duration(seconds: 34), completed: true);
      await tester.pumpAndSettle();
      expect(find.text('the shop'), findsOneWidget);
      expect(player.disposed, isTrue);
    });

    testWidgets('later launches go straight to the app', (tester) async {
      SharedPreferences.setMockInitialValues({IntroGate.seenKey: true});
      final player = FakeIntroPlayer();
      await pumpGate(tester, player);
      expect(find.byType(IntroScreen), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(IntroScreen), findsNothing);
      expect(find.text('the shop'), findsOneWidget);
      expect(player.playCalls, 0);
    });
  });

  group('AccountScreen intro row', () {
    testWidgets('"Watch the intro again" plays the intro and comes back',
        (tester) async {
      final player = FakeIntroPlayer();
      IntroScreen.debugDefaultPlayerFactory = () => player;
      await pumpScreen(tester, const AccountScreen());

      final row = find.text('Watch the intro again');
      expect(row, findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(tester.getTopLeft(find.text('Favourites')).dy),
      );

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(IntroScreen), findsOneWidget);
      expect(player.playing, isTrue);

      await tester.tap(find.byKey(IntroScreen.skipKey));
      await tester.pumpAndSettle();
      expect(find.byType(IntroScreen), findsNothing);
      expect(find.text('Account'), findsOneWidget);
      expect(player.disposed, isTrue);
    });

    testWidgets('back closes the replayed intro', (tester) async {
      IntroScreen.debugDefaultPlayerFactory = FakeIntroPlayer.new;
      await pumpScreen(tester, const AccountScreen());

      await tester.tap(find.text('Watch the intro again'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(IntroScreen), findsNothing);
      expect(find.text('Account'), findsOneWidget);
    });
  });
}
