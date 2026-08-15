class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.minimumAppVersion,
    required this.packageUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      version: json['version'] as String,
      minimumAppVersion: json['minimum_app_version'] as String,
      packageUrl: Uri.parse(json['package_url'] as String),
      sha256: json['sha256'] as String,
      releaseNotes: json['release_notes'] as String? ?? '',
      publishedAt: DateTime.parse(json['published_at'] as String).toUtc(),
    );
  }

  final String version;
  final String minimumAppVersion;
  final Uri packageUrl;
  final String sha256;
  final String releaseNotes;
  final DateTime publishedAt;
}
