import 'package:flutter/foundation.dart';

import '../services/shopify_api.dart';
import '../state/cart_store.dart';
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

  final List<AssistantMessage> _messages = [
    AssistantMessage.assistant(const AssistantReply(AssistantBrain.greeting)),
  ];
  bool _busy = false;

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
  }) async {
    final message = text.trim();
    if (message.isEmpty || _busy) return;
    _messages.add(AssistantMessage.user(message));
    _busy = true;
    notifyListeners();

    final brain = AssistantBrain(api: api, cart: cart);
    final results = await Future.wait<Object?>([
      brain.reply(message),
      Future<void>.delayed(minReplyDelay),
    ]);
    _messages.add(AssistantMessage.assistant(results.first! as AssistantReply));
    _busy = false;
    notifyListeners();
  }
}
