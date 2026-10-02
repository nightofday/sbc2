import 'request_id.dart';

class PosCheckoutItem {
  final String menuVariantId;
  final int quantity;
  final List<String> modifierIds;
  final String specialInstructions;

  const PosCheckoutItem({
    required this.menuVariantId,
    required this.quantity,
    this.modifierIds = const [],
    this.specialInstructions = '',
  });

  factory PosCheckoutItem.fromJson(Map<String, dynamic> json) {
    return PosCheckoutItem(
      menuVariantId: json['menu_variant_id']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      modifierIds: ((json['modifier_ids'] as List?) ?? const [])
          .map((id) => id.toString())
          .toList(),
      specialInstructions: json['special_instructions']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'menu_variant_id': menuVariantId,
    'quantity': quantity,
    'modifier_ids': modifierIds,
    'special_instructions': specialInstructions.trim().isEmpty
        ? null
        : specialInstructions.trim(),
  };
}

class PosPaymentInput {
  final String paymentMethodId;
  final double amount;
  final double? amountTendered;
  final double changeAmount;
  final String? externalReference;

  const PosPaymentInput({
    required this.paymentMethodId,
    required this.amount,
    this.amountTendered,
    this.changeAmount = 0,
    this.externalReference,
  });

  factory PosPaymentInput.fromJson(Map<String, dynamic> json) {
    return PosPaymentInput(
      paymentMethodId: json['payment_method_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      amountTendered: (json['amount_tendered'] as num?)?.toDouble(),
      changeAmount: (json['change_amount'] as num?)?.toDouble() ?? 0,
      externalReference: json['external_reference']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'payment_method_id': paymentMethodId,
    'amount': amount,
    'amount_tendered': amountTendered,
    'change_amount': changeAmount,
    'external_reference': externalReference,
  };
}

/// Thrown when the sale was committed but its receipt could not be loaded
/// afterwards. The caller must treat the sale as saved, not as failed.
class CheckoutSavedException implements Exception {
  final String orderNumber;

  const CheckoutSavedException(this.orderNumber);

  @override
  String toString() =>
      'Order #$orderNumber was saved, but its receipt could not be loaded.';
}

/// Keeps one request ID for a sale until its outcome is known, so that
/// submitting the same sale again after a lost response cannot charge twice.
class CheckoutAttempt {
  final String Function() _createId;
  String? _requestId;
  String? _fingerprint;

  CheckoutAttempt({String Function()? createId})
    : _createId = createId ?? newRequestId;

  /// The request ID whose outcome is still unknown, if any.
  String? get unresolvedRequestId => _requestId;

  bool get hasUnresolved => _requestId != null;

  /// Whether [fingerprint] describes a different sale from the unresolved one.
  bool conflictsWith(String fingerprint) {
    return _requestId != null && _fingerprint != fingerprint;
  }

  /// Returns the ID to send for [fingerprint], reusing the unresolved one.
  String requestIdFor(String fingerprint) {
    if (_requestId == null) {
      _requestId = _createId();
      _fingerprint = fingerprint;
    }

    return _requestId!;
  }

  /// Call once the outcome is known: saved, or definitely rejected.
  void resolve() {
    _requestId = null;
    _fingerprint = null;
  }
}

/// The amounts offered as one-tap choices when a customer pays [total] in
/// cash: the exact amount, then the next round figures and notes above it.
List<double> quickCashAmounts(double total) {
  if (total <= 0) return const [];

  const steps = [50.0, 100.0, 500.0, 1000.0];
  final amounts = <double>{total};

  for (final step in steps) {
    final rounded = (total / step).ceil() * step;
    if (rounded > total) amounts.add(rounded);
    if (amounts.length == 5) break;
  }

  return amounts.toList()..sort();
}
