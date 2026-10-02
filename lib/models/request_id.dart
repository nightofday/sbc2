import 'dart:math';

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
