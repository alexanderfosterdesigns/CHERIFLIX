import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/update_manifest.dart';
import 'package:cheriflix/core/services/update_service.dart';

void main() {
  group('UpdateService', () {
    final service = UpdateService(
        manifestUrl: Uri.parse('https://updates.example.com/manifest.json'));

    test('identifies a newer semantic version', () {
      expect(
        service.isNewerVersion(
          currentVersion: '1.0.0',
          candidateVersion: '1.0.1',
        ),
        isTrue,
      );
    });

    test('rejects an older semantic version', () {
      expect(
        service.isNewerVersion(
          currentVersion: '1.2.0',
          candidateVersion: '1.1.9',
        ),
        isFalse,
      );
    });

    test('treats equal versions as not newer', () {
      expect(
        service.isNewerVersion(
          currentVersion: '2.0.0',
          candidateVersion: '2.0.0',
        ),
        isFalse,
      );
    });

    test('accepts a valid HTTPS manifest', () {
      expect(
        () => service.validateManifest(_validManifest()),
        returnsNormally,
      );
    });

    test('rejects an insecure package URL', () {
      expect(
        () => service.validateManifest(
          _validManifest(
            packageUrl: Uri.parse('http://updates.example.com/package.zip'),
          ),
        ),
        throwsA(isA<UpdateValidationException>()),
      );
    });

    test('rejects an invalid SHA-256 checksum', () {
      expect(
        () => service.validateManifest(_validManifest(sha256: 'not-a-sha')),
        throwsA(isA<UpdateValidationException>()),
      );
    });
  });
}

UpdateManifest _validManifest({
  Uri? packageUrl,
  String? sha256,
}) {
  return UpdateManifest(
    version: '1.0.1',
    minimumAppVersion: '1.0.0',
    packageUrl: packageUrl ??
        Uri.parse('https://updates.example.com/cheriflix/package.zip'),
    sha256: sha256 ??
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    releaseNotes: 'Notes',
    publishedAt: DateTime.now().toUtc(),
  );
}
