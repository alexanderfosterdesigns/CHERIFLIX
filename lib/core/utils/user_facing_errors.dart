String userFacingErrorMessage(
  Object error, {
  required String fallback,
}) {
  final raw = error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Error:\s*'), '')
      .trim();
  if (raw.isEmpty) {
    return fallback;
  }

  final lower = raw.toLowerCase();
  if (lower.contains('127.0.0.1') ||
      lower.contains('preview_shell') ||
      lower.contains('webpage not available') ||
      lower.contains('youtube') ||
      lower.contains('iframe') ||
      lower.contains('trailer')) {
    return 'Trailer preview unavailable right now.';
  }
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('handshake') ||
      lower.contains('connection')) {
    return 'CHERIFLIX could not reach the service right now. Please try again.';
  }
  if (lower.contains('401') ||
      lower.contains('403') ||
      lower.contains('unauthorized') ||
      lower.contains('forbidden')) {
    return 'This service needs a fresh sign-in before it can continue.';
  }
  if (lower.contains('tmdb') || lower.contains('catalog')) {
    return 'Live catalog data is unavailable right now.';
  }
  if (lower.contains('trakt')) {
    return 'Trakt is unavailable right now. Please try again.';
  }

  final sanitized = raw
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final isHumanReadable = sanitized.isNotEmpty &&
      sanitized.length <= 90 &&
      !sanitized.contains('{') &&
      !sanitized.contains('Stack') &&
      !sanitized.contains(' at ') &&
      RegExp(r"^[A-Za-z0-9 ,.!?'()\-:/]+$").hasMatch(sanitized);
  if (isHumanReadable) {
    return sanitized;
  }

  return fallback;
}
