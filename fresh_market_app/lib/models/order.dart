import 'package:flutter/foundation.dart';

import 'money.dart';

/// A product variant id from any of the shapes the order server and
/// Shopify use: 44123, "44123" or "gid://shopify/ProductVariant/44123".
/// Null for anything else.
int? parseVariantId(Object? value) {
  if (value is int) return value > 0 ? value : null;
  if (value is! String) return null;
  final match = RegExp(r'^(?:gid://shopify/ProductVariant/)?([1-9]\d{0,18})$')
      .firstMatch(value.trim());
  return match == null ? null : int.tryParse(match[1]!);
}

int _fils(Object? value, String field) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  throw FormatException('$field is not a whole number of fils');
}

String _text(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field is missing');
}

/// What the order server found wrong with the basket.
enum QuoteProblemKind {
  soldOut('sold_out'),
  priceChanged('price_changed'),
  notExpress('not_express'),
  qtyReduced('qty_reduced'),

  /// A kind this version of the app does not know: its message is shown.
  other('');

  const QuoteProblemKind(this.code);

  final String code;

  static QuoteProblemKind fromCode(Object? code) {
    for (final kind in values) {
      if (kind != other && kind.code == code) return kind;
    }
    return other;
  }
}

/// One line of a quote, at the store's price now.
@immutable
class QuoteLine {
  const QuoteLine({
    required this.variantId,
    required this.title,
    required this.quantity,
    required this.unitPriceFils,
    required this.lineTotalFils,
    required this.available,
    this.variantTitle,
  });

  final int variantId;
  final String title;

  /// "500 GM", or null for a product without options.
  final String? variantTitle;

  /// What the store can sell now (lower than asked when stock is short).
  final int quantity;
  final int unitPriceFils;

  /// 0 for a line that is not available.
  final int lineTotalFils;
  final bool available;

  factory QuoteLine.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('a quote line');
    final id = parseVariantId(json['variantId']);
    if (id == null) throw const FormatException('quote line variantId');
    final variantTitle = json['variantTitle'];
    return QuoteLine(
      variantId: id,
      title: _text(json['title'], 'title'),
      variantTitle: variantTitle is String && variantTitle.isNotEmpty
          ? variantTitle
          : null,
      quantity: _fils(json['quantity'], 'quantity'),
      unitPriceFils: _fils(json['unitPriceFils'], 'unitPriceFils'),
      lineTotalFils: _fils(json['lineTotalFils'], 'lineTotalFils'),
      available: json['available'] != false,
    );
  }
}

/// Something that changed since the cart was filled.
@immutable
class QuoteProblem {
  const QuoteProblem({
    required this.kind,
    required this.message,
    this.variantId,
  });

  /// Null when the problem is about the whole basket (Express does not
  /// reach the area, or the total changed).
  final int? variantId;
  final QuoteProblemKind kind;

  /// The server's own sentence, used when the app has none of its own.
  final String message;

  factory QuoteProblem.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('a quote problem');
    final message = json['message'];
    return QuoteProblem(
      variantId: parseVariantId(json['variantId']),
      kind: QuoteProblemKind.fromCode(json['kind']),
      message: message is String ? message : '',
    );
  }

  static List<QuoteProblem> listFromJson(Object? json) => [
    if (json is List)
      for (final item in json) QuoteProblem.fromJson(item),
  ];
}

/// The order server's price for a basket: the store's prices, stock and
/// delivery fee now. The app shows it; it never works prices out itself.
@immutable
class Quote {
  const Quote({
    required this.lines,
    required this.subtotalFils,
    required this.deliveryFeeFils,
    required this.totalFils,
    required this.deliveryPromise,
    this.currency = 'AED',
    this.problems = const [],
    this.minOrderFils = 0,
  });

  final List<QuoteLine> lines;
  final int subtotalFils;
  final int deliveryFeeFils;
  final int totalFils;
  final String currency;

  /// "Tomorrow morning before 11 AM", "25–35 min".
  final String deliveryPromise;
  final List<QuoteProblem> problems;

  /// 0 when there is no minimum order.
  final int minOrderFils;

  List<QuoteLine> get availableLines =>
      lines.where((l) => l.available).toList(growable: false);

  /// Units that can be bought.
  int get itemCount =>
      availableLines.fold(0, (sum, line) => sum + line.quantity);

  bool get belowMinimum => minOrderFils > 0 && subtotalFils < minOrderFils;

  QuoteLine? lineOf(int variantId) {
    for (final line in lines) {
      if (line.variantId == variantId) return line;
    }
    return null;
  }

  factory Quote.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('a quote');
    final lines = json['lines'];
    final promise = json['deliveryPromise'];
    final currency = json['currency'];
    final min = json['minOrderFils'];
    return Quote(
      lines: [
        if (lines is List)
          for (final line in lines) QuoteLine.fromJson(line),
      ],
      subtotalFils: _fils(json['subtotalFils'], 'subtotalFils'),
      deliveryFeeFils: _fils(json['deliveryFeeFils'], 'deliveryFeeFils'),
      totalFils: _fils(json['totalFils'], 'totalFils'),
      currency: currency is String ? currency : 'AED',
      deliveryPromise: promise is String ? promise : '',
      problems: QuoteProblem.listFromJson(json['problems']),
      minOrderFils: min == null ? 0 : _fils(min, 'minOrderFils'),
    );
  }
}

/// The order the server created (201).
@immutable
class PlacedOrder {
  const PlacedOrder({
    required this.orderId,
    required this.orderName,
    required this.totalFils,
    required this.deliveryPromise,
    this.paymentMethod = 'Cash on Delivery',
  });

  /// "gid://shopify/Order/…".
  final String orderId;

  /// "#1001".
  final String orderName;
  final int totalFils;
  final String deliveryPromise;
  final String paymentMethod;

  factory PlacedOrder.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('an order');
    final promise = json['deliveryPromise'];
    final payment = json['paymentMethod'];
    return PlacedOrder(
      orderId: _text(json['orderId'], 'orderId'),
      orderName: _text(json['orderName'], 'orderName'),
      totalFils: _fils(json['totalFils'], 'totalFils'),
      deliveryPromise: promise is String ? promise : '',
      paymentMethod: payment is String && payment.isNotEmpty
          ? payment
          : 'Cash on Delivery',
    );
  }
}

/// Where an order is, as "My orders" says it.
enum OrderStatus {
  placed('Placed'),
  onTheWay('On the way'),
  delivered('Delivered'),
  cancelled('Cancelled'),
  refunded('Refunded');

  const OrderStatus(this.label);

  final String label;

  /// From the Customer Account API's order fields (2026-10), first match
  /// wins:
  ///
  /// 1. `cancelledAt` set, or `financialStatus` VOIDED: Cancelled.
  /// 2. `financialStatus` REFUNDED: Refunded.
  /// 3. The latest shipment event DELIVERED, or the order FULFILLED and
  ///    PAID (cash orders are marked paid when the driver hands them
  ///    over): Delivered.
  /// 4. `fulfillmentStatus` FULFILLED, PARTIALLY_FULFILLED or
  ///    IN_PROGRESS, a fulfillment with status SUCCESS, or a shipment
  ///    event on its way (IN_TRANSIT, OUT_FOR_DELIVERY, ...): On the way.
  /// 5. Anything else (UNFULFILLED, OPEN, SCHEDULED, ON_HOLD, ...):
  ///    Placed.
  static OrderStatus from({
    String? financialStatus,
    String? fulfillmentStatus,
    String? fulfillmentState,
    String? latestShipmentStatus,
    bool isCancelled = false,
  }) {
    if (isCancelled || financialStatus == 'VOIDED') return cancelled;
    if (financialStatus == 'REFUNDED') return refunded;
    if (latestShipmentStatus == 'DELIVERED' ||
        (fulfillmentStatus == 'FULFILLED' && financialStatus == 'PAID')) {
      return delivered;
    }
    const moving = {'FULFILLED', 'PARTIALLY_FULFILLED', 'IN_PROGRESS'};
    const shipping = {
      'CONFIRMED',
      'IN_TRANSIT',
      'OUT_FOR_DELIVERY',
      'ATTEMPTED_DELIVERY',
      'DELAYED',
      'CARRIER_PICKED_UP',
      'PICKED_UP',
      'READY_FOR_PICKUP',
    };
    if (moving.contains(fulfillmentStatus) ||
        fulfillmentState == 'SUCCESS' ||
        shipping.contains(latestShipmentStatus)) {
      return onTheWay;
    }
    return placed;
  }
}

/// One line of a past order.
@immutable
class OrderLine {
  const OrderLine({
    required this.title,
    required this.quantity,
    this.imageUrl,
    this.variantId,
  });

  final String title;
  final int quantity;
  final String? imageUrl;

  /// Null when the variant no longer exists in the store.
  final int? variantId;
}

/// A customer's order, from the Customer Account API.
@immutable
class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.name,
    required this.processedAt,
    required this.totalFils,
    required this.status,
    required this.lines,
    this.currencyCode = 'AED',
    this.moreLines = false,
    this.financialStatus,
  });

  final String id;

  /// "#1001".
  final String name;
  final DateTime processedAt;
  final int totalFils;
  final String currencyCode;
  final OrderStatus status;

  /// The first lines of the order (see [CustomerAccountApi.ordersQuery]).
  final List<OrderLine> lines;

  /// The order has more lines than [lines].
  final bool moreLines;

  /// Shopify's `financialStatus` (PENDING, PAID, ...).
  final String? financialStatus;

  /// How it is paid, for the order's summary line: "Cash on Delivery"
  /// while the cash is still to be collected (Shopify: PENDING), "Paid"
  /// once collected or paid; null for a refunded or cancelled order (the
  /// status pill says it).
  String? get paymentLabel => switch (financialStatus) {
    null || 'PENDING' => 'Cash on Delivery',
    'PAID' || 'AUTHORIZED' || 'PARTIALLY_REFUNDED' => 'Paid',
    'PARTIALLY_PAID' => 'Part paid',
    _ => null,
  };

  /// Units in [lines].
  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);

  /// Reads one `orders.nodes` entry of [CustomerAccountApi.ordersQuery].
  factory CustomerOrder.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('an order');
    final total = json['totalPrice'];
    if (total is! Map) throw const FormatException('totalPrice');
    final amount = parseMoney(total['amount']);
    if (amount == null) throw const FormatException('totalPrice.amount');
    final processed = DateTime.tryParse(_text(json['processedAt'], 'date'));
    if (processed == null) throw const FormatException('processedAt');
    final fulfillments = json['fulfillments'];
    final firstFulfillment =
        fulfillments is Map &&
            fulfillments['nodes'] is List &&
            (fulfillments['nodes'] as List).isNotEmpty
        ? (fulfillments['nodes'] as List).first
        : null;
    String? enumValue(Object? map, String key) {
      if (map is! Map) return null;
      final value = map[key];
      return value is String ? value : null;
    }

    final items = json['lineItems'];
    final nodes = items is Map && items['nodes'] is List
        ? items['nodes'] as List
        : const [];
    final pageInfo = items is Map ? items['pageInfo'] : null;
    final currency = total['currencyCode'];
    return CustomerOrder(
      id: _text(json['id'], 'id'),
      name: _text(json['name'], 'name'),
      processedAt: processed,
      totalFils: amount,
      currencyCode: currency is String ? currency : 'AED',
      status: OrderStatus.from(
        financialStatus: enumValue(json, 'financialStatus'),
        fulfillmentStatus: enumValue(json, 'fulfillmentStatus'),
        fulfillmentState: enumValue(firstFulfillment, 'status'),
        latestShipmentStatus: enumValue(
          firstFulfillment,
          'latestShipmentStatus',
        ),
        isCancelled: json['cancelledAt'] != null,
      ),
      lines: [
        for (final node in nodes)
          if (node is Map)
            OrderLine(
              title: node['title'] is String ? node['title'] as String : '',
              quantity: node['quantity'] is int ? node['quantity'] as int : 1,
              imageUrl: node['image'] is Map
                  ? (node['image'] as Map)['url'] as String?
                  : null,
              variantId: parseVariantId(node['variantId']),
            ),
      ],
      moreLines: pageInfo is Map && pageInfo['hasNextPage'] == true,
      financialStatus: enumValue(json, 'financialStatus'),
    );
  }
}
