import 'package:flutter/foundation.dart';

import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import '../state/favourites_store.dart';
import 'assistant_brain.dart';

/// One bubble of the conversation.
@immutable
class AssistantMessage {
  const AssistantMessage.user(this.text)
      : fromUser = true,
        reply = null;

  AssistantMessage.assistant(AssistantReply this.reply)
      : fromUser = false,
        text = reply.text;

  final bool fromUser;
  final String text;

  /// Product rows and buttons of an assistant message.
  final AssistantReply? reply;
}

/// The conversation with the demo assistant. It lives outside the screen,
/// so leaving the assistant and coming back shows the same messages; it is
/// forgotten when the app closes.
class AssistantSession extends ChangeNotifier {
  AssistantSession({this.minReplyDelay = const Duration(milliseconds: 450)});

  /// The app's one conversation.
  static final AssistantSession shared = AssistantSession();

  /// A reply never appears sooner than this, so the typing indicator is
  /// seen even when the store answers at once.
  final Duration minReplyDelay;

  static AssistantMessage _greeting() => AssistantMessage.assistant(
        const AssistantReply(AssistantBrain.greeting, showOptions: true),
      );

  final List<AssistantMessage> _messages = [_greeting()];
  bool _busy = false;

  /// "Add all" and "empty my cart" buttons already carried out, with the
  /// message they belong to. Kept here, not in the screen, so leaving the
  /// assistant and coming back does not make them work again.
  final Set<(AssistantMessage, AssistantAction)> _done = {};

  /// Oldest first; starts with the greeting.
  List<AssistantMessage> get messages => List.unmodifiable(_messages);

  /// True while a reply is being prepared.
  bool get busy => _busy;

  /// Adds the shopper's message and then the assistant's answer. Ignored
  /// while [busy] or when [text] is blank. Completes when the answer is in
  /// [messages].
  Future<void> send(
    String text, {
    required ShopifyApi api,
    required CartStore cart,
    FavouritesStore? favourites,
  }) async {
    final message = text.trim();
    if (message.isEmpty || _busy) return;
    // What the message answers: an "Are you sure?" or a product chip.
    final previous = lastReply;
    _messages.add(AssistantMessage.user(message));
    _busy = true;
    notifyListeners();

    final brain = AssistantBrain(api: api, cart: cart, favourites: favourites);
    AssistantReply reply;
    try {
      final results = await Future.wait<Object?>([
        brain.reply(message, previous: previous),
        Future<void>.delayed(minReplyDelay),
      ]);
      reply = results.first! as AssistantReply;
    } catch (_) {
      // The brain turns store failures into replies; anything else must
      // not leave the assistant busy for good.
      reply = const AssistantReply(AssistantBrain.unexpectedError);
    } finally {
      _busy = false;
    }
    _messages.add(AssistantMessage.assistant(reply));
    notifyListeners();
  }

  /// The latest assistant reply, for the suggestion chips.
  AssistantReply? get lastReply =>
      _messages.lastWhere((m) => !m.fromUser).reply;

  /// Adds an assistant message without asking the store, for example
  /// after the screen carried out an [AddProductsAction]. Ignored while
  /// [busy].
  void note(AssistantReply reply) {
    if (_busy) return;
    _messages.add(AssistantMessage.assistant(reply));
    notifyListeners();
  }

  /// Shows the options grid again. Ignored while [busy].
  void showOptions() => note(AssistantBrain.optionsReply);

  /// True when [action] of [message] was already carried out.
  bool isDone(AssistantMessage message, AssistantAction action) =>
      _done.contains((message, action));

  /// Marks [action] of [message] as carried out. False when it already
  /// was, or while [busy] (the note saying what happened could not be
  /// added): then it must not be carried out.
  bool markDone(AssistantMessage message, AssistantAction action) {
    if (_busy || !_done.add((message, action))) return false;
    notifyListeners();
    return true;
  }

  /// Starts a new conversation: only the greeting is left. Ignored while
  /// [busy].
  void reset() {
    if (_busy) return;
    _messages
      ..clear()
      ..add(_greeting());
    _done.clear();
    notifyListeners();
  }
}
