import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/services/profile_avatar_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads curated categories and falls back to uncategorized drift row',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_avatar_catalog_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final root = await _seedAvatarRoot(tempDirectory);
    await _writeImage(root, 'Show A - One - id1.png');
    await _writeImage(root, 'Show A - Two - id2.png');
    await _writeImage(root, 'Show B - One - id3.png');
    await _writeImage(root, 'Default${Platform.pathSeparator}blue.png');

    await _writeManifest(
      root,
      <String, Object?>{
        'version': 1,
        'categories': <Object?>[
          <String, Object?>{
            'id': 'show-a',
            'title': 'Show A',
            'items': <Object?>[
              <String, Object?>{
                'key': 'Show A - One - id1.png',
                'sort': 10,
                'label': 'One',
              },
              <String, Object?>{
                'key': 'Show A - Two - id2.png',
                'sort': 20,
                'label': 'Two',
              },
            ],
          },
        ],
      },
    );

    final service = ProfileAvatarCatalogService(
      searchRoots: <Directory>[tempDirectory],
    );
    final catalog = await service.loadCatalog();

    expect(catalog.defaultOptions.length, 1);
    expect(catalog.categories.length, 2);
    expect(catalog.categories.first.title, 'Show A');
    expect(catalog.categories.last.title, 'Uncategorized');
    expect(
        catalog.categories.last.options.single.key, 'Show B - One - id3.png');
  });

  test('reports manifest validation issues for duplicate and unknown keys',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_avatar_catalog_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final root = await _seedAvatarRoot(tempDirectory);
    await _writeImage(root, 'Known - One - id1.png');
    await _writeImage(root, 'Known - Two - id2.png');

    await _writeManifest(
      root,
      <String, Object?>{
        'version': 1,
        'categories': <Object?>[
          <String, Object?>{
            'id': 'known-a',
            'title': 'Known A',
            'items': <Object?>[
              <String, Object?>{'key': 'Known - One - id1.png', 'sort': 10},
              <String, Object?>{'key': 'Ghost - Missing - idX.png', 'sort': 20},
            ],
          },
          <String, Object?>{
            'id': 'known-b',
            'title': 'Known B',
            'items': <Object?>[
              <String, Object?>{'key': 'Known - One - id1.png', 'sort': 30},
            ],
          },
        ],
      },
    );

    final service = ProfileAvatarCatalogService(
      searchRoots: <Directory>[tempDirectory],
    );
    final catalog = await service.loadCatalog();

    expect(
      catalog.validationIssues.any(
        (issue) => issue.contains('Manifest key not found on disk'),
      ),
      isTrue,
    );
    expect(
      catalog.validationIssues.any(
        (issue) => issue.contains('Duplicate avatar key across categories'),
      ),
      isTrue,
    );
    expect(
      catalog.categories.any((row) => row.title == 'Uncategorized'),
      isTrue,
    );
  });
}

Future<Directory> _seedAvatarRoot(Directory tempDirectory) async {
  final root = Directory(
    '${tempDirectory.path}${Platform.pathSeparator}profile-pictures',
  );
  await root.create(recursive: true);
  return root;
}

Future<void> _writeImage(Directory root, String relativePath) async {
  final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
  final file = File('${root.path}${Platform.pathSeparator}$normalized');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(const <int>[137, 80, 78, 71], flush: true);
}

Future<void> _writeManifest(
  Directory root,
  Map<String, Object?> manifest,
) async {
  final file = File('${root.path}${Platform.pathSeparator}avatar_catalog.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
}
