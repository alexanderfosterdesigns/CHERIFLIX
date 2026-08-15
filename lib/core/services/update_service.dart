import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../models/update_manifest.dart';

enum UpdateCheckStatus {
  upToDate,
  updateAvailable,
  invalidManifest,
  checkFailed,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    this.manifest,
    required this.message,
  });

  final UpdateCheckStatus status;
  final UpdateManifest? manifest;
  final String message;
}

class UpdatePackageStageResult {
  const UpdatePackageStageResult({
    required this.stagingDirectory,
    required this.manifest,
  });

  final Directory stagingDirectory;
  final UpdateManifest manifest;
}

class UpdateValidationException implements Exception {
  const UpdateValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateService {
  UpdateService({
    required this.manifestUrl,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Uri manifestUrl;
  final HttpClient _client;

  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxAttempts = 3;
  static final RegExp _semverPattern =
      RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$');
  static final RegExp _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

  Future<UpdateManifest> fetchManifest() async {
    _validateHttpsUri(manifestUrl, label: 'manifest URL');
    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final request = await _client.getUrl(manifestUrl).timeout(
              _requestTimeout,
            );
        final response = await request.close().timeout(_requestTimeout);
        final payload = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final manifest = UpdateManifest.fromJson(
            jsonDecode(payload) as Map<String, dynamic>,
          );
          validateManifest(manifest);
          return manifest;
        }
        if (!_isRetriableStatus(response.statusCode) ||
            attempt >= _maxAttempts) {
          throw HttpException(
            'Update manifest request failed: ${response.statusCode}',
            uri: manifestUrl,
          );
        }
      } on TimeoutException {
        if (attempt >= _maxAttempts) {
          rethrow;
        }
      } on SocketException {
        if (attempt >= _maxAttempts) {
          rethrow;
        }
      }
      await _retryDelay(attempt);
    }
    throw HttpException('Update manifest request failed.', uri: manifestUrl);
  }

  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async {
    try {
      final manifest = await fetchManifest();
      final hasUpdate = isNewerVersion(
        currentVersion: currentVersion,
        candidateVersion: manifest.version,
      );
      if (!hasUpdate) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          message: 'CHERIFLIX is up to date.',
        );
      }
      return UpdateCheckResult(
        status: UpdateCheckStatus.updateAvailable,
        manifest: manifest,
        message: 'Update ${manifest.version} is available.',
      );
    } on UpdateValidationException catch (error) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.invalidManifest,
        message: error.message,
      );
    } catch (_) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.checkFailed,
        message: 'Could not check for updates.',
      );
    }
  }

  Future<UpdatePackageStageResult> downloadAndStagePackage(
    UpdateManifest manifest, {
    Directory? stagingDirectory,
  }) async {
    validateManifest(manifest);
    final stageRoot = stagingDirectory ??
        await Directory.systemTemp.createTemp('cheriflix_update_');
    await stageRoot.create(recursive: true);

    final packageBytes = await _downloadBytes(manifest.packageUrl);
    final digest = sha256.convert(packageBytes).toString().toLowerCase();
    if (digest != manifest.sha256.toLowerCase()) {
      throw const UpdateValidationException(
        'Downloaded update package checksum did not match the manifest.',
      );
    }

    final archive = ZipDecoder().decodeBytes(packageBytes);
    await _extractArchiveSafely(archive, stageRoot);
    return UpdatePackageStageResult(
      stagingDirectory: stageRoot,
      manifest: manifest,
    );
  }

  bool isNewerVersion({
    required String currentVersion,
    required String candidateVersion,
  }) {
    final currentParts = _parseComparableVersion(currentVersion);
    final candidateParts = _parseComparableVersion(candidateVersion);
    for (var index = 0; index < 3; index += 1) {
      if (candidateParts[index] > currentParts[index]) {
        return true;
      }
      if (candidateParts[index] < currentParts[index]) {
        return false;
      }
    }
    return false;
  }

  void validateManifest(UpdateManifest manifest) {
    if (!_semverPattern.hasMatch(manifest.version)) {
      throw const UpdateValidationException(
        'Update manifest has an invalid version.',
      );
    }
    if (!_semverPattern.hasMatch(manifest.minimumAppVersion)) {
      throw const UpdateValidationException(
        'Update manifest has an invalid minimum app version.',
      );
    }
    _validateHttpsUri(manifest.packageUrl, label: 'package URL');
    if (!_sha256Pattern.hasMatch(manifest.sha256)) {
      throw const UpdateValidationException(
        'Update manifest has an invalid SHA-256 checksum.',
      );
    }
    final now = DateTime.now().toUtc();
    if (manifest.publishedAt.isBefore(DateTime.utc(2020)) ||
        manifest.publishedAt.isAfter(now.add(const Duration(days: 1)))) {
      throw const UpdateValidationException(
        'Update manifest has an invalid publish date.',
      );
    }
  }

  Future<List<int>> _downloadBytes(Uri uri) async {
    _validateHttpsUri(uri, label: 'package URL');
    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final request = await _client.getUrl(uri).timeout(_requestTimeout);
        final response = await request.close().timeout(_requestTimeout);
        final bytes = await response.expand((chunk) => chunk).toList().timeout(
              _requestTimeout,
            );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return bytes;
        }
        if (!_isRetriableStatus(response.statusCode) ||
            attempt >= _maxAttempts) {
          throw HttpException(
            'Update package request failed: ${response.statusCode}',
            uri: uri,
          );
        }
      } on TimeoutException {
        if (attempt >= _maxAttempts) {
          rethrow;
        }
      } on SocketException {
        if (attempt >= _maxAttempts) {
          rethrow;
        }
      }
      await _retryDelay(attempt);
    }
    throw HttpException('Update package request failed.', uri: uri);
  }

  Future<void> _extractArchiveSafely(Archive archive, Directory target) async {
    final targetRoot = target.absolute.path;
    for (final entry in archive) {
      final relativeName = entry.name.replaceAll('\\', '/');
      if (_isUnsafeArchivePath(relativeName)) {
        throw const UpdateValidationException(
          'Update package contains an unsafe file path.',
        );
      }
      final destination = File(
        '$targetRoot${Platform.pathSeparator}'
        '${relativeName.replaceAll('/', Platform.pathSeparator)}',
      ).absolute;
      if (!_isWithinDirectory(targetRoot, destination.path)) {
        throw const UpdateValidationException(
          'Update package contains an unsafe file path.',
        );
      }
      if (entry.isFile) {
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(entry.content as List<int>, flush: true);
      } else {
        await Directory(destination.path).create(recursive: true);
      }
    }
  }

  bool _isUnsafeArchivePath(String relativeName) {
    final normalized = relativeName.replaceAll(RegExp(r'/+$'), '');
    if (normalized.trim().isEmpty ||
        normalized.startsWith('/') ||
        normalized.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      return true;
    }
    return normalized.split('/').any((segment) {
      return segment.isEmpty || segment == '.' || segment == '..';
    });
  }

  bool _isWithinDirectory(String parentPath, String childPath) {
    final parent = PathCanonicalizer.canonicalDirectory(parentPath);
    final child = PathCanonicalizer.canonicalPath(childPath);
    return child == parent ||
        child.startsWith('$parent${Platform.pathSeparator}');
  }

  void _validateHttpsUri(Uri uri, {required String label}) {
    if (uri.scheme.toLowerCase() != 'https' || uri.host.trim().isEmpty) {
      throw UpdateValidationException('Update $label must use HTTPS.');
    }
  }

  bool _isRetriableStatus(int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }

  Future<void> _retryDelay(int attempt) {
    return Future<void>.delayed(Duration(milliseconds: 240 * attempt));
  }

  List<int> _parseComparableVersion(String version) {
    return version
        .split(RegExp(r'[-+]'))
        .first
        .split('.')
        .map((segment) => int.tryParse(segment) ?? 0)
        .followedBy(<int>[0, 0, 0])
        .take(3)
        .toList();
  }
}

class PathCanonicalizer {
  const PathCanonicalizer._();

  static String canonicalDirectory(String path) {
    return canonicalPath(path).replaceAll(RegExp(r'[\\/]+$'), '');
  }

  static String canonicalPath(String path) {
    return File(path)
        .absolute
        .path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
  }
}
