import 'dart:math';

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

/// Returns a random version 4 UUID for use as a checkout request ID.
String newRequestId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// Whether an error code means the server answered and rejected the request,
/// so nothing was saved. PostgreSQL reports a five-character SQLSTATE and
/// the Data API a `PGRST` code. Anything else, such as a gateway timeout or
/// a dropped connection, leaves the outcome unknown.
bool isServerRejectionCode(String? code) {
  if (code == null) return false;

  return RegExp(r'^[0-9A-Z]{5}$').hasMatch(code) || code.startsWith('PGRST');
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
