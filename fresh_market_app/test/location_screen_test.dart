import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/screens/location_screen.dart';
import 'package:fresh_market_app/services/device_location.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

/// Types [term] into the picker's search and taps the row named [name].
Future<void> _searchAndPick(
  WidgetTester tester,
  String term,
  String name,
) async {
  await tester.enterText(find.byType(TextField), term);
  await tester.pump();
  final row = find.descendant(
    of: find.byType(LocationScreen),
    matching: find.text(name),
  );
  // The list builds lazily: on a small phone with large text the rows may
  // start below the screen.
  await tester.scrollUntilVisible(row, 200, scrollable: _list);
  await tester.pump();
  await tester.tap(row.first);
  await tester.pump();
}

Finder get _list => find
    .descendant(
      of: find.byKey(const ValueKey('location-list')),
      matching: find.byType(Scrollable),
    )
    .first;

/// The time line of an option ("6 hours" keeps its number and unit).
Finder _when(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(' ', ' ') == text,
  description: 'option time "$text"',
);

void main() {
  testWidgets('the white picker: title, subtle search, the location row with '
      'a green target, white result rows', (tester) async {
    await pumpScreen(
      tester,
      LocationScreen(firstLaunch: true, onPicked: (_) {}),
      delivery: testDelivery(area: null),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.canvas);
    final title = tester.widget<Text>(find.text('Where should we deliver?'));
    expect(title.style!.fontSize, 24);
    expect(title.style!.fontWeight, FontWeight.w800);

    // The search field takes the theme's subtle, borderless input.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.filled, isNull); // from the theme
    final theme = Theme.of(tester.element(find.byType(TextField)));
    expect(theme.inputDecorationTheme.fillColor, AppColors.subtle);

    // "Use my current location": a white row with a green target icon.
    final target = tester.widget<Icon>(find.byIcon(Icons.my_location));
    expect(target.color, AppColors.green);
    final gps = find.ancestor(
      of: find.text(LocationScreen.useMyLocation),
      matching: find.byType(Material),
    );
    final gpsMaterial = tester.widget<Material>(gps.first);
    expect(gpsMaterial.color, AppColors.surface);
    expect(gpsMaterial.shape, AppDecor.cardShape);
    expect(
      tester.getSize(gps.first).height,
      greaterThanOrEqualTo(AppDims.touch),
    );
    // Only one filled (green) button: the confirm button.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    // The result rows sit in a white card with a hairline.
    final rows = tester.widget<Container>(
      find
          .ancestor(of: find.text('Business Bay'), matching: find.byType(Container))
          .first,
    );
    expect(rows.decoration, AppDecor.card);
    expect(tester.takeException(), isNull);
  });

  testWidgets('What you get: an off-white card (radius 14); Express time in '
      'green, Fresh Market time in ink; the sticky bar is white with the '
      'green Deliver to button', (tester) async {
    await pumpScreen(
      tester,
      LocationScreen(firstLaunch: true, onPicked: (_) {}),
      delivery: testDelivery(area: null),
    );
    await _searchAndPick(tester, 'mirdif', 'Mirdif');

    final heading = find.text('What you get in Mirdif, Dubai');
    final card = tester.widget<Container>(
      find.ancestor(of: heading, matching: find.byType(Container)).first,
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.subtle);
    expect(decoration.borderRadius, BorderRadius.circular(14));
    expect(decoration.border, isNull);

    final market = tester.widget<Text>(_when('Today within 6 hours'));
    expect(market.style!.color, AppColors.ink);
    final express = tester.widget<Text>(_when('25–35 min'));
    expect(express.style!.color, AppColors.green);
    // Stacked: the time sits under the option's title, not beside it.
    expect(
      tester.getRect(_when('25–35 min')).top,
      greaterThan(tester.getRect(find.text('Express · selected items')).bottom -
          0.5),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Deliver to Mirdif'),
      ),
      findsOneWidget,
    );
    final buttonColor = button.style ??
        Theme.of(tester.element(find.byType(FilledButton)))
            .filledButtonTheme
            .style!;
    expect(
      buttonColor.backgroundColor!.resolve(<WidgetState>{}),
      AppColors.green,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an area outside the Express zone at night: Express in grey',
      (tester) async {
    await pumpScreen(
      tester,
      LocationScreen(firstLaunch: true, onPicked: (_) {}),
      delivery: testDelivery(area: null, at: uaeTime(23)),
    );
    await _searchAndPick(tester, 'marina', 'Dubai Marina');
    final notAvailable = tester.widget<Text>(_when('Not available'));
    expect(notAvailable.style!.color, AppColors.secondary);
    final bolt = tester.widget<Icon>(
      find.descendant(
        of: find.byType(LocationScreen),
        matching: find.byIcon(Icons.bolt),
      ).last,
    );
    expect(bolt.color, AppColors.tertiary);
  });

  testWidgets('the close button lines up with the title', (tester) async {
    await pumpScreen(
      tester,
      const LocationScreen(),
      delivery: testDelivery(),
    );
    final title = tester.getRect(find.text('Change delivery location'));
    final close = tester.getRect(find.byTooltip('Close'));
    // Centred on the title's first line (a long title may wrap).
    final firstLine = title.top + 24 * 1.2 / 2;
    expect(close.center.dy, moreOrLessEquals(firstLine, epsilon: 3));
    expect(close.height, greaterThanOrEqualTo(AppDims.touch));
  });

  testWidgets('a location problem shows an off-white note with its button',
      (tester) async {
    await pumpScreen(
      tester,
      LocationScreen(firstLaunch: true, onPicked: (_) {}),
      delivery: testDelivery(area: null),
      locationServices: testLocationServices(
        FakeDeviceLocation(const LocationFailure(LocationProblem.timeout)),
      ),
    );
    await tester.tap(find.text(LocationScreen.useMyLocation));
    await tester.pump();
    await tester.pump();
    final note = tester.widget<Container>(
      find
          .ancestor(
            of: find.text(LocationScreen.timeoutMessage),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(note.decoration, AppDecor.info);
    expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
  });

  testWidgets('no overflow at 360dp with text scale 1.3', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final cases = <(String, DateTime, String?)>[
      ('mirdif', uaeTime(10), 'Mirdif'),
      ('marina', uaeTime(23), 'Dubai Marina'),
      ('jebel', uaeTime(18, 30), 'Jebel Ali'),
      ('', uaeTime(10), null),
    ];
    for (final (term, at, name) in cases) {
      await pumpScreen(
        tester,
        // With the close button: the longer title.
        LocationScreen(
          key: ValueKey('$term $at'),
          reason: 'Set your location to check Express',
        ),
        delivery: testDelivery(at: at),
        locationServices: testLocationServices(
          FakeDeviceLocation(const LocationFailure(LocationProblem.denied)),
        ),
      );
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      await tester.tap(find.text(LocationScreen.useMyLocation));
      await tester.pump();
      await tester.pump();
      if (name != null) await _searchAndPick(tester, term, name);
      for (var i = 0; i < 8; i++) {
        await tester.drag(_list, const Offset(0, -300));
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: '$term $at');
    }
  });
}
