class ProviderConfig {
  const ProviderConfig({
    required this.providerPriority,
    required this.providerTimeoutSeconds,
    required this.disabledProviders,
  });

  factory ProviderConfig.defaults() {
    return const ProviderConfig(
      providerPriority: <String>[
        'vidking',
        'vixsrc',
        'vidsrc',
        'vsembed',
        'embedsu',
        'vsrcsu',
        'vidsrcme',
        'vidsrc_embed',
        'videasy',
        'vidapi',
        'vidnest',
        'vidapi_xyz',
        'vidsrc_xyz',
        '111movies_com',
        'autoembed_cc',
        'vidsrc_cc',
        'vidlink',
        'vidzee',
        'mapple',
        'primesrc',
        'multiembed',
        'autoembed',
        '2embed',
        '111movies',
        'hdrezka',
      ],
      providerTimeoutSeconds: 8,
      disabledProviders: <String>{},
    );
  }

  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    return ProviderConfig(
      providerPriority: _readStringList(
        json['provider_priority'] ?? json['providerPriority'],
      ),
      providerTimeoutSeconds: _readInt(json['provider_timeout_seconds'] ??
              json['providerTimeoutSeconds']) ??
          8,
      disabledProviders: _readStringSet(
        json['disabled_providers'] ?? json['disabledProviders'],
      ),
    );
  }

  final List<String> providerPriority;
  final int providerTimeoutSeconds;
  final Set<String> disabledProviders;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'provider_priority': providerPriority,
      'provider_timeout_seconds': providerTimeoutSeconds,
      'disabled_providers': disabledProviders.toList(growable: false),
    };
  }

  static List<String> _readStringList(Object? value) {
    return (value as List<dynamic>? ?? const <dynamic>[])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Set<String> _readStringSet(Object? value) {
    return (value as List<dynamic>? ?? const <dynamic>[])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toSet();
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
}
