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
    expect(find.text('Show me berries'), findsOneWidget);
    expect(find.text('What is on offer?'), findsOneWidget);
    expect(AssistantBrain.suggestions, [
      'Show me berries',
      'What is on offer?',
      'Add 2 cucumbers',
      'Find avocado',
      'Open my cart',
    ]);
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
}
