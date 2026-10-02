import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/request_id.dart';

const noConnectionMessage =
    'No connection to the server. Check the internet and try again.';

/// The message to show a person for [error]: the server's own wording when
/// it answered, a plain sentence when it could not be reached, and never a
/// class name or stack detail.
String errorText(Object? error) {
  if (error == null) return 'Something went wrong. Please try again.';

  if (error is PostgrestException) {
    return isServerRejectionCode(error.code)
        ? error.message
        : noConnectionMessage;
  }

  if (error is TimeoutException) return noConnectionMessage;

  final text = error.toString();
  const connectionHints = [
    'SocketException',
    'ClientException',
    'Failed to fetch',
    'Failed host lookup',
    'AuthRetryableFetchException',
    'Connection closed',
    'Connection refused',
    'Network is unreachable',
    'XMLHttpRequest',
  ];
  if (connectionHints.any(text.contains)) return noConnectionMessage;

  return text
      .replaceFirst(RegExp(r'^(Exception|FormatException|Bad state): '), '')
      .trim();
}
