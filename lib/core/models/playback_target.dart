enum PlaybackSourceKind {
  embed,
  hls,
  file;

  static PlaybackSourceKind? tryParse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'embed' || 'page' || 'webview' => PlaybackSourceKind.embed,
      'hls' => PlaybackSourceKind.hls,
      'file' || 'mp4' || 'mkv' => PlaybackSourceKind.file,
      _ => null,
    };
  }
}

class PlaybackTarget {
  const PlaybackTarget({
    required this.uri,
    required this.providerKey,
    required this.providerLabel,
    required this.providerIndex,
    required this.sourceKind,
    this.httpHeaders = const <String, String>{},
    this.pageUri,
    this.expiresAtEpochMs,
    this.fallbackUris = const <Uri>[],
    this.diagnosticSessionId,
    this.offlineStorageAllowed = false,
    this.qualityLabel,
    this.bitrateBitsPerSecond,
  });

  final Uri uri;
  final String providerKey;
  final String providerLabel;
  final int providerIndex;
  final PlaybackSourceKind sourceKind;
  final Map<String, String> httpHeaders;
  final Uri? pageUri;
  final int? expiresAtEpochMs;
  final List<Uri> fallbackUris;
  final String? diagnosticSessionId;
  final bool offlineStorageAllowed;
  final String? qualityLabel;
  final int? bitrateBitsPerSecond;

  bool get isDirectPlayable =>
      uri.hasScheme &&
      (sourceKind == PlaybackSourceKind.hls ||
          sourceKind == PlaybackSourceKind.file);

  factory PlaybackTarget.fromJson(Map<String, dynamic> json) {
    final uriValue = json['uri'] ?? json['url'];
    final rawSourceKind =
        json['sourceKind'] ?? json['source_kind'] ?? _inferSourceKind(uriValue);
    final pageUriValue = json['pageUri'] ?? json['page_uri'];
    return PlaybackTarget(
      uri: Uri.parse(uriValue.toString()),
      providerKey:
          (json['providerKey'] ?? json['provider_key'] ?? '').toString(),
      providerLabel:
          (json['providerLabel'] ?? json['provider_label'] ?? '').toString(),
      providerIndex: _readInt(
            json['providerIndex'] ?? json['provider_index'],
          ) ??
          0,
      sourceKind:
          PlaybackSourceKind.tryParse(rawSourceKind) ?? PlaybackSourceKind.file,
      httpHeaders: _readStringMap(
        json['httpHeaders'] ?? json['http_headers'],
      ),
      pageUri: pageUriValue == null || '$pageUriValue'.trim().isEmpty
          ? null
          : Uri.parse(pageUriValue.toString()),
      expiresAtEpochMs: _readInt(
        json['expiresAtEpochMs'] ?? json['expires_at_epoch_ms'],
      ),
      fallbackUris: _readUriList(
        json['fallbackUris'] ?? json['fallback_uris'],
      ),
      diagnosticSessionId:
          (json['diagnosticSessionId'] ?? json['diagnostic_session_id'])
              ?.toString(),
      offlineStorageAllowed: _readBool(
        json['offlineStorageAllowed'] ?? json['offline_storage_allowed'],
      ),
      qualityLabel: (json['qualityLabel'] ?? json['quality_label'])?.toString(),
      bitrateBitsPerSecond: _readInt(
        json['bitrateBitsPerSecond'] ?? json['bitrate_bits_per_second'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'uri': uri.toString(),
      'providerKey': providerKey,
      'providerLabel': providerLabel,
      'providerIndex': providerIndex,
      'sourceKind': sourceKind.name,
      'httpHeaders': httpHeaders,
      if (pageUri != null) 'pageUri': pageUri.toString(),
      if (expiresAtEpochMs != null) 'expiresAtEpochMs': expiresAtEpochMs,
      if (fallbackUris.isNotEmpty)
        'fallbackUris': fallbackUris.map((uri) => uri.toString()).toList(),
      if (diagnosticSessionId != null)
        'diagnosticSessionId': diagnosticSessionId,
      'offlineStorageAllowed': offlineStorageAllowed,
      if (qualityLabel != null) 'qualityLabel': qualityLabel,
      if (bitrateBitsPerSecond != null)
        'bitrateBitsPerSecond': bitrateBitsPerSecond,
    };
  }

  static List<Uri> _readUriList(Object? value) {
    if (value is! List) {
      return const <Uri>[];
    }
    return value
        .map((item) => Uri.tryParse(item.toString()))
        .whereType<Uri>()
        .where((uri) => uri.hasScheme && uri.host.isNotEmpty)
        .toList(growable: false);
  }

  static PlaybackSourceKind _inferSourceKind(Object? value) {
    final uri = Uri.tryParse(value?.toString() ?? '');
    final path = uri?.path.toLowerCase() ?? '';
    if (path.endsWith('.m3u8')) {
      return PlaybackSourceKind.hls;
    }
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isNotEmpty &&
        !path.endsWith('.mp4') &&
        !path.endsWith('.mkv') &&
        !path.endsWith('.webm')) {
      return PlaybackSourceKind.embed;
    }
    return PlaybackSourceKind.file;
  }

  static Map<String, String> _readStringMap(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    return <String, String>{
      for (final entry in value.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    return switch (value?.toString().trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      _ => false,
    };
  }
}
