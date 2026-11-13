import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/assistant/assistant_session.dart';
import 'package:fresh_market_app/screens/assistant_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/product_detail_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/screens/search_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:fresh_market_app/widgets/ask_button.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

const delay = Duration(milliseconds: 100);

AssistantSession newSession() => AssistantSession(minReplyDelay: delay);

/// Lets the reply arrive and the list settle.
Future<void> settleReply(WidgetTester tester) async {
  await tester.pump(delay);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('opens with the header, greeting, chips and input',
      (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, AssistantScreen(session: newSession()), api: api);

    expect(find.text('Fresh Market Assistant'), findsOneWidget);
    expect(find.text('Demo assistant: scripted replies, not AI yet'),
        findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(
      find.text('Hi, I am your Fresh Market assistant. Ask me to find a '
          'product, open a category, add something to your cart or show '
          "today's offers."),
      findsOneWidget,
    );
    // The default chips, the first ones on screen.
    expect(find.text(AssistantBrain.defaultSuggestions[0]), findsOneWidget);
    expect(find.text(AssistantBrain.defaultSuggestions[1]), findsOneWidget);
    expect(find.text('Show me berries'), findsOneWidget);
    expect(find.text('What is on offer?'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(find.byTooltip('Show options'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Ask for a product or a category',
    );
    expect(api.calls, isEmpty);
  });

  testWidgets('a chip sends: bubble, typing indicator, then the category '
      'reply with rows and an action', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, AssistantScreen(session: newSession()), api: api);

    await tester.ensureVisible(find.text('Show me berries'));
    await tester.pump();
    await tester.tap(find.text('Show me berries'));
    await tester.pump();
    // The chip and the new user bubble.
    expect(find.text('Show me berries'), findsNWidgets(2));
    expect(find.bySemanticsLabel('The assistant is typing'), findsOneWidget);
    expect(find.text('Here is Berries.'), findsNothing);

    await settleReply(tester);
    expect(find.bySemanticsLabel('The assistant is typing'), findsNothing);
    expect(find.text('Here is Berries.'), findsOneWidget);
    expect(find.text('Zespri Kiwi Sungold 500 GM'), findsOneWidget);
    expect(find.text('Dhs. 19.95'), findsOneWidget);
    expect(find.text('Australian Beef Cubes'), findsOneWidget);
    // Struck old price of the sale product.
    expect(find.text('Dhs. 62.50'), findsOneWidget);
    expect(find.text('115.00'), findsOneWidget);
    expect(find.text('Cucumber 500 GM'), findsOneWidget);
    expect(find.byType(AddControl), findsNWidgets(3));
    expect(find.text('Open Berries'), findsOneWidget);

    await tapVisible(tester, find.text('Open Berries'));
    expect(find.byType(ProductListScreen), findsOneWidget);

    // Back returns to the conversation.
    await tapVisible(tester, find.byTooltip('Back').last);
    expect(find.byType(ProductListScreen), findsNothing);
    expect(find.text('Here is Berries.'), findsOneWidget);
  });

  testWidgets('Enter sends; add puts the product in the cart and the row '
      'shows the stepper', (tester) async {
    final cart = CartStore();
    await pumpScreen(tester, AssistantScreen(session: newSession()),
        cart: cart);

    await ask(tester, 'Add 2 cucumbers');
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
    await settleReply(tester);

    expect(find.text('Done. I added 2 × Cucumber (500 GM) to your cart.'),
        findsOneWidget);
    expect(cart.quantityOf(2004), 2);
    expect(find.byType(QuantityStepper), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('the send button sends and is ignored while a reply loads',
      (tester) async {
    final api = FakeShopifyApi.sample();
    final session = newSession();
    await pumpScreen(tester, AssistantScreen(session: session), api: api);

    await tester.enterText(find.byType(TextField), 'kiwi');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(session.busy, isTrue);

    await tester.enterText(find.byType(TextField), 'beef');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await settleReply(tester);

    expect(api.calls, ['search(kiwi)']);
    expect(session.messages, hasLength(3));
    expect(find.text('I found this for "kiwi".'), findsOneWidget);
    expect(find.text('See all results'), findsOneWidget);
    // What was typed meanwhile is still there.
    expect(find.text('beef'), findsOneWidget);
  });

  testWidgets('See all results opens Search with the query', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, AssistantScreen(session: newSession()), api: api);

    await ask(tester, 'Find kiwi');
    await settleReply(tester);
    await tapVisible(tester, find.text('See all results'));

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(api.calls.last, 'search(kiwi)');
    await tester.pump(SearchScreen.debounce);
  });

  testWidgets('tapping a product row opens product detail', (tester) async {
    await pumpScreen(tester, AssistantScreen(session: newSession()));

    await ask(tester, 'Find kiwi');
    await settleReply(tester);
    await tapVisible(tester, find.text('Zespri Kiwi Sungold 500 GM'));

    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  testWidgets('offers reply and its collection button', (tester) async {
    await pumpScreen(tester, AssistantScreen(session: newSession()));

    await tapVisible(tester, find.text('What is on offer?'));
    await settleReply(tester);

    expect(
      find.text('These are on sale today. The biggest saving is 46% on '
          'Australian Beef Cubes.'),
      findsOneWidget,
    );
    expect(find.text('Strawberry 1 KG'), findsOneWidget);
    expect(find.text('82.95'), findsOneWidget);

    await tapVisible(tester, find.text("See all Today's Top Deals"));
    expect(find.byType(ProductListScreen), findsOneWidget);
    expect(find.text("Today's Top Deals"), findsWidgets);
    expect(find.text('Australian Beef Cubes'), findsWidgets);
  });

  testWidgets('Open cart shows the Cart tab', (tester) async {
    final shell = ShellController();
    final cart = CartStore();
    final kiwi = sampleProducts().first;
    cart.add(kiwi, kiwi.variants.first);
    await pumpScreen(tester, AssistantScreen(session: newSession()),
        cart: cart, shell: shell);

    await ask(tester, 'Open my cart');
    await settleReply(tester);
    expect(find.text('Your cart has 1 item, subtotal Dhs. 19.95.'),
        findsOneWidget);

    await tapVisible(tester, find.text('Open cart'));
    expect(shell.tab, AppTab.cart);
  });

  testWidgets('checkout offers both actions; empty cart says so',
      (tester) async {
    final cart = CartStore();
    await pumpScreen(tester, AssistantScreen(session: newSession()),
        cart: cart);

    await ask(tester, 'checkout');
    await settleReply(tester);
    expect(find.textContaining('Your cart is empty'), findsOneWidget);
    expect(find.text('Go to checkout'), findsNothing);

    final kiwi = sampleProducts().first;
    cart.add(kiwi, kiwi.variants.first);
    await ask(tester, 'checkout');
    await settleReply(tester);
    expect(find.text('Go to checkout'), findsOneWidget);
    expect(find.text('Review cart'), findsOneWidget);
  });

  testWidgets('Go to checkout opens checkout once, shows progress and '
      'blocks the list meanwhile; an emptied cart says so', (tester) async {
    final api = FakeShopifyApi.sample();
    final cart = CartStore();
    final kiwi = sampleProducts().first;
    cart.add(kiwi, kiwi.variants.first);
    await pumpScreen(tester, AssistantScreen(session: newSession()),
        api: api, cart: cart);
    await ask(tester, 'checkout');
    await settleReply(tester);

    // The cart check takes a second.
    api.delay = const Duration(seconds: 1);
    final button = find.text('Go to checkout');
    await tester.tap(button);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(button, warnIfMissed: false);
    await tester.tap(find.text('Review cart'), warnIfMissed: false);
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('product(')), hasLength(1));

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CheckoutScreen), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CheckoutScreen), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // An old button after the cart was emptied.
    api.delay = Duration.zero;
    cart.clear();
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Your cart is empty.'), findsOneWidget);
    expect(find.byType(CheckoutScreen), findsNothing);
  });

  testWidgets('a network error is said plainly', (tester) async {
    final api = FakeShopifyApi.sample()
      ..error = const NetworkException('offline');
    await pumpScreen(tester, AssistantScreen(session: newSession()), api: api);

    await ask(tester, 'Find avocado');
    await settleReply(tester);
    expect(
      find.text(
          'I could not reach the store. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.byType(AddControl), findsNothing);
  });

  testWidgets('the conversation is kept when the screen is reopened',
      (tester) async {
    final session = newSession();
    await pumpScreen(tester, AssistantScreen(session: session));
    await ask(tester, 'Find avocado');
    await settleReply(tester);

    await pumpScreen(tester, const SizedBox());
    await pumpScreen(tester, AssistantScreen(session: session));
    expect(find.text('Find avocado'), findsWidgets);
    expect(find.textContaining('could not find anything for "avocado"'),
        findsOneWidget);
  });

  testWidgets('AskButton is a 48px pill that opens the assistant',
      (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(body: Center(child: AskButton())),
    );

    expect(find.text('Ask'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(tester.getSize(find.byType(AskButton)).height, 48);

    await tapVisible(tester, find.byType(AskButton));
    expect(find.byType(AssistantScreen), findsOneWidget);
    expect(find.text('Fresh Market Assistant'), findsOneWidget);

    await tapVisible(tester, find.byTooltip('Back'));
    expect(find.byType(AssistantScreen), findsNothing);
  });

  group('options grid', () {
    testWidgets('the greeting shows the 8 options as tiles across the full '
        'width; a tile sends its message', (tester) async {
      final session = newSession();
      await pumpScreen(tester, AssistantScreen(session: session));

      expect(session.messages.single.reply!.showOptions, isTrue);
      for (final option in AssistantBrain.quickOptions) {
        expect(find.text(option.label), findsOneWidget);
        expect(find.bySemanticsLabel(option.label), findsOneWidget);
      }
      expect(AssistantBrain.quickOptions, hasLength(8));
      for (final icon in [
        Icons.local_offer_outlined,
        Icons.grid_view_rounded,
        Icons.restaurant_menu,
        Icons.place_outlined,
        Icons.card_giftcard,
        Icons.trending_up,
        Icons.shopping_bag_outlined,
        Icons.support_agent,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }

      // 4 columns x 2 rows, at least 84 high, wider than the bubble.
      final first = tileRect(tester, AssistantBrain.quickOptions[0].label);
      final fourth = tileRect(tester, AssistantBrain.quickOptions[3].label);
      final fifth = tileRect(tester, AssistantBrain.quickOptions[4].label);
      expect(first.height, greaterThanOrEqualTo(84));
      expect(fourth.top, first.top);
      expect(fifth.left, first.left);
      expect(fifth.top, greaterThan(first.bottom));
      expect(fourth.right, closeTo(390 - 12, 0.5));
      final bubble = tester.getRect(find
          .ancestor(
            of: find.text(AssistantBrain.greeting),
            matching: find.byType(Container),
          )
          .first);
      expect(fourth.right, greaterThan(bubble.right));
      expect(tester.widget<Material>(tileMaterial(tester, "Today's offers"))
          .color, AppColors.tile);

      final offers = AssistantBrain.quickOptions.first;
      await tester.tap(find.text(offers.label));
      await tester.pump();
      expect(session.messages[1].fromUser, isTrue);
      expect(session.messages[1].text, offers.message);
      expect(session.busy, isTrue);

      // Greyed and not tappable while the reply loads.
      expect(tester.widget<Material>(tileMaterial(tester, 'Categories')).color,
          AppColors.disabledFill);
      await tester.tap(find.text('Categories'));
      await tester.pump();
      expect(session.messages, hasLength(2));

      await settleReply(tester);
      expect(session.busy, isFalse);
      expect(session.messages, hasLength(3));
      expect(tester.widget<Material>(tileMaterial(tester, 'Categories')).color,
          AppColors.tile);
    });
  });

  group('suggestion chips', () {
    testWidgets('follow the latest reply, go back to the start when they '
        'change and wait while a reply loads', (tester) async {
      final session = newSession();
      await pumpScreen(tester, AssistantScreen(session: session));

      expect(find.text(AssistantBrain.defaultSuggestions.first),
          findsOneWidget);
      await tester.drag(chipRow, const Offset(-500, 0));
      await tester.pump();
      expect(chipPosition(tester).pixels, greaterThan(0));

      const ownChips = [
        'Chip 1',
        'Chip 2',
        'Chip 3',
        'Chip 4',
        'Chip 5',
        'Chip 6',
        'Chip 7',
        'Chip 8',
      ];
      session.note(const AssistantReply('Pick one', suggestions: ownChips));
      await tester.pump();
      await tester.pump();
      expect(find.text(ownChips.first), findsOneWidget);
      expect(find.text('What is on offer?'), findsNothing);
      expect(chipPosition(tester).pixels, 0);

      // A reply from the store: its own chips, or the defaults.
      await tester.tap(find.text(ownChips.first));
      await tester.pump();
      expect(session.messages[session.messages.length - 1].text,
          ownChips.first);
      // Disabled while busy.
      await tester.tap(find.text(ownChips[1]));
      await tester.pump();
      expect(session.messages.where((m) => m.fromUser), hasLength(1));

      await settleReply(tester);
      final latest = session.lastReply!;
      final expected = latest.suggestions.isEmpty
          ? AssistantBrain.defaultSuggestions
          : latest.suggestions;
      expect(find.text(expected.first), findsWidgets);
      expect(find.text(ownChips[1]), findsNothing);
    });
  });

  testWidgets('New chat leaves only the greeting; waits while a reply '
      'loads', (tester) async {
    final session = newSession();
    await pumpScreen(tester, AssistantScreen(session: session));

    await ask(tester, 'Find kiwi');
    await tester.tap(find.byTooltip('New chat'));
    await tester.pump();
    expect(session.messages, hasLength(2));
    await settleReply(tester);
    expect(session.messages, hasLength(3));

    await tester.tap(find.byTooltip('New chat'));
    await tester.pump();
    expect(session.messages, hasLength(1));
    expect(find.text('Find kiwi'), findsNothing);
    expect(find.text(AssistantBrain.greeting), findsOneWidget);
    expect(find.text("Today's offers"), findsOneWidget);
    expect(find.text(AssistantBrain.defaultSuggestions.first), findsOneWidget);
    expect(tester.getSize(find.byTooltip('New chat')).height,
        greaterThanOrEqualTo(44));
  });

  testWidgets('the options button shows the grid at the bottom, once',
      (tester) async {
    final session = newSession();
    await pumpScreen(tester, AssistantScreen(session: session));
    expect(tester.getSize(find.byTooltip('Show options')),
        const Size(44, 44));

    // The greeting already shows it.
    await tester.tap(find.byTooltip('Show options'));
    await tester.pump();
    expect(session.messages, hasLength(1));

    final products = sampleProducts();
    session.note(AssistantReply('Many rows', products: products.sublist(0, 4)));
    session.note(AssistantReply('More rows', products: products.sublist(2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final list = find.byType(ListView).first;
    await tester.drag(list, const Offset(0, 400));
    await tester.pump();
    final chat = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first);
    expect(chat.position.pixels, greaterThan(0));

    await tester.tap(find.byTooltip('Show options'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.messages, hasLength(4));
    expect(session.messages.last.reply, same(AssistantBrain.optionsReply));
    expect(chat.position.pixels, 0);
    expect(find.text(AssistantBrain.optionsReply.text), findsOneWidget);
    expect(find.text('Customer care'), findsWidgets);

    // Again: already at the bottom, nothing added.
    await tester.tap(find.byTooltip('Show options'));
    await tester.pump();
    expect(session.messages, hasLength(4));

    // Waits while a reply loads.
    await ask(tester, 'Find kiwi');
    await tester.tap(find.byTooltip('Show options'));
    await tester.pump();
    expect(session.messages, hasLength(5));
    await settleReply(tester);
  });

  group('actions', () {
    testWidgets('Add all adds the first variant in stock of each product, '
        'skips sold-out ones and works once', (tester) async {
      final cart = CartStore();
      final session = newSession();
      final products = sampleProducts();
      // Kiwi (500 GM in stock), Blueberry (sold out), Strawberry (250 GM
      // sold out, 1 KG in stock).
      final picked = [products[0], products[3], products[5]];
      session.note(AssistantReply(
        'A fruit salad',
        products: picked,
        actions: [AddProductsAction('Add all to cart', products: picked)],
      ));
      await pumpScreen(tester, AssistantScreen(session: session), cart: cart);

      final pill = pillMaterial(tester, 'Add all to cart');
      expect(tester.widget<Material>(pill).color, AppColors.brand);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.text('Add all to cart'))
            .style
            ?.color,
        Colors.white,
      );

      await tapVisible(tester, find.text('Add all to cart'));
      expect(cart.quantityOf(2001), 1);
      expect(cart.quantityOf(2009), 1);
      expect(cart.quantityOf(2008), 0);
      expect(cart.quantityOf(2006), 0);
      expect(cart.itemCount, 2);
      expect(
        find.text('Added 2 products to your cart: Zespri Kiwi Sungold '
            '(500 GM) and Strawberry (1 KG). Blueberry is sold out.'),
        findsOneWidget,
      );
      expect(find.text('Open cart'), findsOneWidget);
      expect(find.text('Ideas for a smoothie'), findsOneWidget);
      expect(find.text('Checkout'), findsOneWidget);
      expect(session.messages, hasLength(3));

      // A second tap does nothing.
      await tapVisible(tester, find.text('Add all to cart'));
      expect(cart.itemCount, 2);
      expect(session.messages, hasLength(3));
      expect(tester.widget<Material>(pillMaterial(tester, 'Add all to cart'))
          .color, AppColors.disabledFill);
    });

    testWidgets('Add all with only sold-out products adds nothing',
        (tester) async {
      final cart = CartStore();
      final session = newSession();
      final blueberry = sampleProducts()[3];
      session.note(AssistantReply(
        'Berries',
        actions: [AddProductsAction('Add all to cart', products: [blueberry])],
      ));
      await pumpScreen(tester, AssistantScreen(session: session), cart: cart);

      await tapVisible(tester, find.text('Add all to cart'));
      expect(cart.isEmpty, isTrue);
      expect(find.text('Nothing was added. Blueberry is sold out.'),
          findsOneWidget);
    });

    testWidgets('Empty my cart is red, clears the cart once per message and '
        'says when it is already empty', (tester) async {
      final kiwi = sampleProducts().first;
      final cart = CartStore()..add(kiwi, kiwi.variants.first);
      final session = newSession();
      // The same reply twice: each message's button is its own.
      const reply = AssistantReply(
        'Empty your cart?',
        actions: [ClearCartAction()],
      );
      session
        ..note(reply)
        ..note(reply);
      await pumpScreen(tester, AssistantScreen(session: session), cart: cart);

      final buttons = find.text('Yes, empty my cart');
      expect(buttons, findsNWidgets(2));
      final shape = tester.widget<Material>(pillMaterial(tester,
          'Yes, empty my cart')).shape! as StadiumBorder;
      expect(shape.side.color, AppColors.red);
      expect(tester.widget<Text>(buttons.first).style?.color, AppColors.red);

      // The newest message comes first in the reversed list.
      await tapVisible(tester, buttons.first);
      expect(cart.isEmpty, isTrue);
      expect(find.text('Done. Your cart is empty now.'), findsOneWidget);
      expect(session.lastReply!.suggestions, [
        'What is on offer?',
        'Show me berries',
        'Ideas for a fruit salad',
      ]);
      expect(find.text('What is on offer?'), findsOneWidget);
      expect(find.text('Cheapest avocado'), findsNothing);
      expect(session.messages, hasLength(4));

      cart.add(kiwi, kiwi.variants.first);
      await tapVisible(tester, buttons.first);
      expect(cart.itemCount, 1);
      expect(session.messages, hasLength(4));

      cart.clear();
      await tapVisible(tester, buttons.last);
      expect(find.text('Your cart is already empty.'), findsOneWidget);
      expect(session.messages, hasLength(5));
    });

    testWidgets('links open outside the app; a failure is said',
        (tester) async {
      final launched = <Uri>[];
      Future<bool> launcher(Uri uri) async {
        launched.add(uri);
        if (uri.scheme == 'https') throw StateError('no browser');
        return uri.scheme == 'mailto';
      }

      final session = newSession();
      session.note(const AssistantReply(
        'Customer care',
        actions: [
          OpenLinkAction('Call us', uri: 'tel:+971000000000'),
          OpenLinkAction('Email us', uri: 'mailto:care@example.com'),
          OpenLinkAction('Visit the store', uri: 'https://example.com/pages'),
          OpenLinkAction('Other', uri: 'file:///data/secret.txt'),
        ],
      ));
      await pumpScreen(
        tester,
        AssistantScreen(session: session, launcher: launcher),
      );
      expect(find.byIcon(Icons.phone), findsOneWidget);
      expect(find.byIcon(Icons.mail), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));

      await tapVisible(tester, find.text('Call us'));
      expect(launched.single, Uri.parse('tel:+971000000000'));
      expect(
        find.text("Couldn't open the phone app. Call +971000000000 instead."),
        findsOneWidget,
      );

      await tapVisible(tester, find.text('Email us'));
      expect(launched.last.scheme, 'mailto');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining("Couldn't open the email app"), findsNothing);

      await tapVisible(tester, find.text('Visit the store'));
      expect(launched, hasLength(3));
      expect(find.text("Couldn't open the store page."), findsOneWidget);

      // Only phone, email and https links are ever launched.
      await tapVisible(tester, find.text('Other'));
      expect(launched, hasLength(3));
      expect(find.text("Couldn't open that link."), findsOneWidget);
      expect(session.messages, hasLength(2));
    });

    testWidgets('categories, favourites and a ready-made question',
        (tester) async {
      final shell = ShellController();
      final session = newSession();
      const reply = AssistantReply(
        'Where next?',
        actions: [
          OpenCategoriesAction(),
          OpenFavouritesAction(),
          SendMessageAction('Ask about smoothies',
              message: 'Ideas for a smoothie'),
        ],
      );
      session.note(reply);
      await pumpScreen(tester, AssistantScreen(session: session),
          shell: shell);

      await tapVisible(tester, find.text('Open favourites'));
      expect(find.byType(ProductListScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ProductListScreen), findsNothing);

      await tapVisible(tester, find.text('Ask about smoothies'));
      expect(session.messages.where((m) => m.fromUser).single.text,
          'Ideas for a smoothie');
      await settleReply(tester);
      expect(session.busy, isFalse);

      await tapVisible(tester, find.text('All categories'));
      expect(shell.tab, AppTab.categories);
    });
  });

  testWidgets('nothing overflows on a 360dp phone with text scale 1.3',
      (tester) async {
    final products = sampleProducts();
    final kiwi = products.first;
    final cart = CartStore()..add(kiwi, kiwi.variants.first, quantity: 12);
    final session = newSession();
    session
      ..note(AssistantReply(
        'Here are ideas for a fruit salad, with everything you need from '
        'the store and a sentence long enough to wrap.',
        products: [products[0], products[2], products[3], products[5]],
        actions: [
          AddProductsAction('Add all 4 to cart', products: products),
          const ClearCartAction(),
          const OpenLinkAction('Call customer care', uri: 'tel:+971000000000'),
          const OpenLinkAction('Email customer care',
              uri: 'mailto:care@example.com'),
          const OpenLinkAction('Open the store website',
              uri: 'https://example.com'),
          const OpenCategoriesAction(),
          const OpenFavouritesAction(),
          const SendMessageAction('Ideas for a smoothie',
              message: 'Ideas for a smoothie'),
          const OpenSearchAction('kiwi'),
        ],
        suggestions: const [
          'A rather long follow-up question for the chips',
          'Another one',
        ],
      ))
      ..showOptions();
    await pumpScreen(tester, AssistantScreen(session: session), cart: cart);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Through the whole conversation, up to the greeting.
    final list = find.byType(ListView).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, 250));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(find.text(AssistantBrain.greeting), findsOneWidget);

    // With a reply loading (greyed grid and buttons, typing dots).
    await ask(tester, 'Find kiwi');
    expect(tester.takeException(), isNull);
    await settleReply(tester);
    expect(tester.takeException(), isNull);
    for (final option in AssistantBrain.quickOptions) {
      expect(find.text(option.label), findsWidgets);
    }
  });
}

/// The horizontal list of suggestion chips.
final Finder chipRow = find.byWidgetPredicate(
  (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
);

ScrollPosition chipPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
        find.descendant(of: chipRow, matching: find.byType(Scrollable)).first)
    .position;

/// The options tile labelled [label] (the newest one when several).
Rect tileRect(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);

Finder tileMaterial(WidgetTester tester, String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Material)).first;

/// The pill button labelled [label] (the newest one when several).
Finder pillMaterial(WidgetTester tester, String label) => find
    .ancestor(of: find.text(label).first, matching: find.byType(Material))
    .first;
