import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class ProfileAvatarCatalogService {
  ProfileAvatarCatalogService({List<Directory>? searchRoots})
      : _searchRoots = searchRoots;

  static final ProfileAvatarCatalogService instance =
      ProfileAvatarCatalogService();

  static const String _manifestFileName = 'avatar_catalog.json';
  static const Set<String> _supportedExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
  };
  static const List<String> _androidBuiltInAvatarAssets = <String>[
    'assets/avatars/avatar_01.png',
    'assets/avatars/avatar_02.png',
    'assets/avatars/avatar_03.png',
    'assets/avatars/avatar_04.png',
  ];
  static const List<String> _generatedAvatarPlaceholderKeys = <String>[
    'generated/avatar_a.png',
    'generated/avatar_b.png',
    'generated/avatar_c.png',
    'generated/avatar_d.png',
  ];
  static const String _bundledProfilePicturesRoot = 'profile-pictures/';
  static const List<String> _bundledDefaultProfilePictureKeys = <String>[
    'Default/blue-cherry-bg.png',
    'Default/gray-cherry-bg.png',
    'Default/green-cherry-bg.png',
    'Default/pink-cherry-bg.png',
    'Default/purple-cherry-bg.png',
    'Default/red-cherry-bg.png',
    'Default/yellow-cherry-2-bg.png',
  ];

  final List<Directory>? _searchRoots;
  Future<ProfileAvatarCatalog>? _catalogFuture;
  final Map<String, Future<ProfileAvatarOption?>> _resolveCache =
      <String, Future<ProfileAvatarOption?>>{};

  Future<ProfileAvatarCatalog> loadCatalog({bool refresh = false}) {
    if (refresh) {
      _catalogFuture = null;
      _resolveCache.clear();
    }
    return _catalogFuture ??= _scanCatalog();
  }

  Future<ProfileAvatarOption?> resolveAvatarOption(String avatarLabel) {
    final normalizedKey = normalizeAvatarKey(avatarLabel);
    if (normalizedKey == null) {
      return Future<ProfileAvatarOption?>.value(null);
    }
    final cacheKey = normalizedKey.toLowerCase();
    return _resolveCache.putIfAbsent(cacheKey, () async {
      final catalog = await loadCatalog();
      return catalog.byKeyLower[cacheKey];
    });
  }

  Future<File?> resolveAvatarFile(String avatarLabel) async {
    final option = await resolveAvatarOption(avatarLabel);
    return option?.file;
  }

  Future<String?> pickRandomDefaultAvatarKey({
    required Set<String> usedAvatarLabels,
  }) async {
    final catalog = await loadCatalog();
    if (catalog.defaultOptions.isEmpty) {
      return null;
    }

    final defaultLowerKeys =
        catalog.defaultKeys.map((key) => key.toLowerCase());
    final usedDefaultKeys = usedAvatarLabels
        .map(normalizeAvatarKey)
        .whereType<String>()
        .map((key) => key.toLowerCase())
        .where(defaultLowerKeys.contains)
        .toSet();
    final available = catalog.defaultOptions
        .where((option) => !usedDefaultKeys.contains(option.key.toLowerCase()))
        .toList(growable: false);
    final pool = available.isNotEmpty ? available : catalog.defaultOptions;
    return pool.first.key;
  }

  String? normalizeAvatarKey(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized =
        trimmed.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (normalized.isEmpty) {
      return null;
    }
    final extensionIndex = normalized.lastIndexOf('.');
    if (extensionIndex < 0) {
      return null;
    }
    final extension = normalized.substring(extensionIndex).toLowerCase();
    if (!_supportedExtensions.contains(extension)) {
      return null;
    }
    return normalized;
  }

  Future<ProfileAvatarCatalog> _scanCatalog() async {
    final root = await _findProfilePicturesRoot();
    if (root == null) {
      final bundledCatalog = await _scanBundledAssetCatalog();
      if (bundledCatalog != null) {
        return bundledCatalog;
      }
      if (!Platform.isAndroid) {
        return const ProfileAvatarCatalog.empty();
      }
      return _androidFallbackCatalog(
        issues: const <String>[
          'Profile picture directory was not found. Using bundled Android TV avatars.',
        ],
      );
    }

    final issues = <String>[];
    final defaultOptions = await _readImmediateImageFiles(
      Directory('${root.path}${Platform.pathSeparator}Default'),
      keyPrefix: 'Default/',
      isDefault: true,
    );
    final otherOptions = await _readImmediateImageFiles(
      root,
      keyPrefix: '',
      isDefault: false,
      excludedDirectories: const <String>{'Default'},
    );

    final optionsByLowerKey = <String, ProfileAvatarOption>{
      for (final option in otherOptions) option.key.toLowerCase(): option,
    };

    var categoryRows = <ProfileAvatarCategory>[];
    final manifestFile =
        File('${root.path}${Platform.pathSeparator}$_manifestFileName');
    if (await manifestFile.exists()) {
      final manifestResult = await _loadCategoriesFromManifest(
        manifestFile,
        optionsByLowerKey: optionsByLowerKey,
      );
      categoryRows = manifestResult.categories;
      issues.addAll(manifestResult.issues);
    } else {
      issues.add('Avatar manifest is missing: ${manifestFile.path}');
      categoryRows = _autoCategorizeRows(otherOptions);
    }

    final assignedKeys = <String>{
      for (final row in categoryRows)
        for (final option in row.options) option.key.toLowerCase(),
    };
    final uncategorized = otherOptions
        .where((option) => !assignedKeys.contains(option.key.toLowerCase()))
        .toList(growable: false);
    if (uncategorized.isNotEmpty) {
      issues.add(
        'Found ${uncategorized.length} uncategorized avatar file(s). Added fallback row.',
      );
      categoryRows = <ProfileAvatarCategory>[
        ...categoryRows,
        ProfileAvatarCategory(
          id: 'uncategorized',
          title: 'Uncategorized',
          options: uncategorized,
          fallback: true,
        ),
      ];
    }

    categoryRows.sort(
      (left, right) => left.title.toLowerCase().compareTo(
            right.title.toLowerCase(),
          ),
    );

    final fileSystemCatalog = ProfileAvatarCatalog(
      defaultOptions: defaultOptions,
      otherOptions: otherOptions,
      categories: categoryRows,
      validationIssues: issues,
    );
    if (fileSystemCatalog.allOptions.isNotEmpty || !Platform.isAndroid) {
      return fileSystemCatalog;
    }

    return _androidFallbackCatalog(
      issues: <String>[
        ...issues,
        'No usable file-based avatars were found. Using bundled Android TV avatars.',
      ],
    );
  }

  Future<ProfileAvatarCatalog?> _scanBundledAssetCatalog() async {
    final directManifestCatalog = await _scanBundledManifestCatalog();
    if (directManifestCatalog != null) {
      return directManifestCatalog;
    }

    final bundledAssets = await _loadBundledAssetPaths();
    if (bundledAssets.isEmpty) {
      return null;
    }

    final profilePictureAssets = bundledAssets
        .where((asset) => asset.startsWith(_bundledProfilePicturesRoot))
        .toSet();
    if (profilePictureAssets.isEmpty) {
      return null;
    }

    final issues = <String>[];
    final defaultOptions = _readBundledImmediateImageAssets(
      profilePictureAssets,
      folder: 'Default',
      isDefault: true,
    );
    final otherOptions = _readBundledImmediateImageAssets(
      profilePictureAssets,
      isDefault: false,
    );

    final optionsByLowerKey = <String, ProfileAvatarOption>{
      for (final option in otherOptions) option.key.toLowerCase(): option,
    };

    var categoryRows = <ProfileAvatarCategory>[];
    final manifestAssetPath = '$_bundledProfilePicturesRoot$_manifestFileName';
    if (profilePictureAssets.contains(manifestAssetPath)) {
      try {
        final rawManifest = await rootBundle.loadString(manifestAssetPath);
        final manifestResult = _loadCategoriesFromManifestString(
          rawManifest,
          optionsByLowerKey: optionsByLowerKey,
        );
        categoryRows = manifestResult.categories;
        issues.addAll(manifestResult.issues);
      } catch (error) {
        issues.add('Could not parse avatar manifest asset: $error');
        categoryRows = _autoCategorizeRows(otherOptions);
      }
    } else {
      issues.add('Avatar manifest asset is missing: $manifestAssetPath');
      categoryRows = _autoCategorizeRows(otherOptions);
    }

    final assignedKeys = <String>{
      for (final row in categoryRows)
        for (final option in row.options) option.key.toLowerCase(),
    };
    final uncategorized = otherOptions
        .where((option) => !assignedKeys.contains(option.key.toLowerCase()))
        .toList(growable: false);
    if (uncategorized.isNotEmpty) {
      issues.add(
        'Found ${uncategorized.length} uncategorized avatar asset(s). Added fallback row.',
      );
      categoryRows = <ProfileAvatarCategory>[
        ...categoryRows,
        ProfileAvatarCategory(
          id: 'uncategorized',
          title: 'Uncategorized',
          options: uncategorized,
          fallback: true,
        ),
      ];
    }

    categoryRows.sort(
      (left, right) => left.title.toLowerCase().compareTo(
            right.title.toLowerCase(),
          ),
    );

    return ProfileAvatarCatalog(
      defaultOptions: defaultOptions,
      otherOptions: otherOptions,
      categories: categoryRows,
      validationIssues: issues,
    );
  }

  Future<ProfileAvatarCatalog?> _scanBundledManifestCatalog() async {
    final manifestAssetPath = '$_bundledProfilePicturesRoot$_manifestFileName';
    String rawManifest;
    try {
      rawManifest = await rootBundle.loadString(manifestAssetPath);
    } catch (_) {
      return null;
    }

    final issues = <String>[];
    final defaultOptions = _bundledDefaultProfilePictureKeys
        .map(
          (key) => ProfileAvatarOption(
            key: key,
            displayName: _displayNameForFilename(key),
            isDefault: true,
            assetPath: '$_bundledProfilePicturesRoot$key',
          ),
        )
        .toList(growable: false);
    final manifestResult =
        _loadBundledCategoriesFromManifestString(rawManifest);
    issues.addAll(manifestResult.issues);
    final categories = manifestResult.categories;
    final otherOptions = <ProfileAvatarOption>[
      for (final category in categories) ...category.options,
    ];
    if (categories.isEmpty && otherOptions.isEmpty) {
      return null;
    }
    return ProfileAvatarCatalog(
      defaultOptions: defaultOptions,
      otherOptions: otherOptions,
      categories: categories,
      validationIssues: issues,
    );
  }

  ProfileAvatarCatalog _androidFallbackCatalog({
    required List<String> issues,
  }) {
    final builtInDefaultOptions = _androidBuiltInAvatarAssets
        .map(
          (path) => ProfileAvatarOption(
            key: path,
            displayName: _displayNameForFilename(path),
            isDefault: true,
            assetPath: path,
          ),
        )
        .toList(growable: false);

    final generatedOptions = _generatedAvatarPlaceholderKeys
        .map(
          (key) => ProfileAvatarOption(
            key: key,
            displayName: _displayNameForFilename(key),
            isDefault: false,
          ),
        )
        .toList(growable: false);

    final categories = <ProfileAvatarCategory>[
      if (builtInDefaultOptions.isNotEmpty)
        ProfileAvatarCategory(
          id: 'builtin',
          title: 'Built-in',
          options: builtInDefaultOptions,
          fallback: true,
        ),
      ProfileAvatarCategory(
        id: 'generated',
        title: 'Generated',
        options: generatedOptions,
        fallback: true,
      ),
    ];

    return ProfileAvatarCatalog(
      defaultOptions: builtInDefaultOptions,
      otherOptions: generatedOptions,
      categories: categories,
      validationIssues: issues,
    );
  }

  Future<_ManifestLoadResult> _loadCategoriesFromManifest(
    File manifestFile, {
    required Map<String, ProfileAvatarOption> optionsByLowerKey,
  }) async {
    try {
      final raw = await manifestFile.readAsString();
      return _loadCategoriesFromManifestString(
        raw,
        optionsByLowerKey: optionsByLowerKey,
      );
    } catch (error) {
      return _ManifestLoadResult(
        categories: const <ProfileAvatarCategory>[],
        issues: <String>['Could not parse avatar manifest: $error'],
      );
    }
  }

  _ManifestLoadResult _loadCategoriesFromManifestString(
    String rawManifest, {
    required Map<String, ProfileAvatarOption> optionsByLowerKey,
  }) {
    final issues = <String>[];
    final rows = <ProfileAvatarCategory>[];
    final assigned = <String>{};

    Map<String, dynamic> manifest;
    final decoded = jsonDecode(rawManifest);
    if (decoded is! Map<String, dynamic>) {
      return _ManifestLoadResult(
        categories: const <ProfileAvatarCategory>[],
        issues: <String>['Avatar manifest root must be a JSON object.'],
      );
    }
    manifest = decoded;

    final categories = manifest['categories'];
    if (categories is! List) {
      return _ManifestLoadResult(
        categories: const <ProfileAvatarCategory>[],
        issues: <String>['Avatar manifest must include a "categories" list.'],
      );
    }

    final rowIds = <String>{};
    for (final rawCategory in categories) {
      if (rawCategory is! Map) {
        issues.add('Skipped malformed category entry in manifest.');
        continue;
      }
      final id = (rawCategory['id']?.toString() ?? '').trim();
      final title = (rawCategory['title']?.toString() ?? '').trim();
      final rawItems = rawCategory['items'];
      if (id.isEmpty || title.isEmpty || rawItems is! List) {
        issues.add('Skipped malformed category: id/title/items required.');
        continue;
      }
      final lowerId = id.toLowerCase();
      if (rowIds.contains(lowerId)) {
        issues.add('Duplicate category id "$id" in manifest.');
        continue;
      }
      rowIds.add(lowerId);

      final resolvedItems = <_ResolvedManifestItem>[];
      for (final rawItem in rawItems) {
        if (rawItem is! Map) {
          issues.add('Skipped malformed item in category "$title".');
          continue;
        }
        final key = normalizeAvatarKey(rawItem['key']?.toString() ?? '');
        if (key == null) {
          issues.add('Skipped invalid key in category "$title".');
          continue;
        }
        final lowerKey = key.toLowerCase();
        if (lowerKey.startsWith('default/')) {
          issues.add(
              'Default key "$key" must not appear in manifest categories.');
          continue;
        }
        final option = optionsByLowerKey[lowerKey];
        if (option == null) {
          issues.add('Manifest key not found on disk: "$key".');
          continue;
        }
        if (!assigned.add(lowerKey)) {
          issues.add('Duplicate avatar key across categories: "$key".');
          continue;
        }
        final sort = _parseManifestSort(rawItem['sort']);
        final label = (rawItem['label']?.toString() ?? '').trim();
        resolvedItems.add(
          _ResolvedManifestItem(
            option: option,
            sort: sort,
            label: label,
          ),
        );
      }

      if (resolvedItems.isEmpty) {
        continue;
      }
      resolvedItems.sort((left, right) {
        final sortCmp = left.sort.compareTo(right.sort);
        if (sortCmp != 0) {
          return sortCmp;
        }
        final leftLabel =
            left.label.isEmpty ? left.option.displayName : left.label;
        final rightLabel =
            right.label.isEmpty ? right.option.displayName : right.label;
        return leftLabel.toLowerCase().compareTo(rightLabel.toLowerCase());
      });
      rows.add(
        ProfileAvatarCategory(
          id: id,
          title: title,
          options: resolvedItems
              .map((entry) => entry.option)
              .toList(growable: false),
        ),
      );
    }

    return _ManifestLoadResult(
      categories: rows,
      issues: issues,
    );
  }

  _ManifestLoadResult _loadBundledCategoriesFromManifestString(
    String rawManifest,
  ) {
    final issues = <String>[];
    final rows = <ProfileAvatarCategory>[];
    final assigned = <String>{};

    final decoded = jsonDecode(rawManifest);
    if (decoded is! Map<String, dynamic>) {
      return _ManifestLoadResult(
        categories: const <ProfileAvatarCategory>[],
        issues: <String>['Avatar manifest root must be a JSON object.'],
      );
    }

    final categories = decoded['categories'];
    if (categories is! List) {
      return _ManifestLoadResult(
        categories: const <ProfileAvatarCategory>[],
        issues: <String>['Avatar manifest must include a "categories" list.'],
      );
    }

    final rowIds = <String>{};
    for (final rawCategory in categories) {
      if (rawCategory is! Map) {
        issues.add('Skipped malformed category entry in manifest.');
        continue;
      }
      final id = (rawCategory['id']?.toString() ?? '').trim();
      final title = (rawCategory['title']?.toString() ?? '').trim();
      final rawItems = rawCategory['items'];
      if (id.isEmpty || title.isEmpty || rawItems is! List) {
        issues.add('Skipped malformed category: id/title/items required.');
        continue;
      }
      final lowerId = id.toLowerCase();
      if (rowIds.contains(lowerId)) {
        issues.add('Duplicate category id "$id" in manifest.');
        continue;
      }
      rowIds.add(lowerId);

      final resolvedItems = <_ResolvedManifestItem>[];
      for (final rawItem in rawItems) {
        if (rawItem is! Map) {
          issues.add('Skipped malformed item in category "$title".');
          continue;
        }
        final key = normalizeAvatarKey(rawItem['key']?.toString() ?? '');
        if (key == null || key.toLowerCase().startsWith('default/')) {
          issues.add('Skipped invalid key in category "$title".');
          continue;
        }
        final lowerKey = key.toLowerCase();
        if (!assigned.add(lowerKey)) {
          issues.add('Duplicate avatar key across categories: "$key".');
          continue;
        }
        final label = (rawItem['label']?.toString() ?? '').trim();
        final option = ProfileAvatarOption(
          key: key,
          displayName: label.isEmpty ? _displayNameForFilename(key) : label,
          isDefault: false,
          assetPath: '$_bundledProfilePicturesRoot$key',
        );
        resolvedItems.add(
          _ResolvedManifestItem(
            option: option,
            sort: _parseManifestSort(rawItem['sort']),
            label: label,
          ),
        );
      }

      if (resolvedItems.isEmpty) {
        continue;
      }
      resolvedItems.sort((left, right) {
        final sortCmp = left.sort.compareTo(right.sort);
        if (sortCmp != 0) {
          return sortCmp;
        }
        return left.option.displayName
            .toLowerCase()
            .compareTo(right.option.displayName.toLowerCase());
      });
      rows.add(
        ProfileAvatarCategory(
          id: id,
          title: title,
          options: resolvedItems
              .map((entry) => entry.option)
              .toList(growable: false),
        ),
      );
    }

    rows.sort(
      (left, right) => left.title.toLowerCase().compareTo(
            right.title.toLowerCase(),
          ),
    );
    return _ManifestLoadResult(categories: rows, issues: issues);
  }

  Future<Set<String>> _loadBundledAssetPaths() async {
    try {
      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final listedAssets = assetManifest.listAssets();
      if (listedAssets.isNotEmpty) {
        return listedAssets.toSet();
      }
    } catch (_) {
      // Fallback to legacy manifest JSON below.
    }

    try {
      final rawManifest = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(rawManifest);
      if (decoded is! Map) {
        return <String>{};
      }
      return decoded.keys.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  List<ProfileAvatarOption> _readBundledImmediateImageAssets(
    Set<String> allAssets, {
    String? folder,
    required bool isDefault,
  }) {
    final options = <ProfileAvatarOption>[];
    for (final assetPath in allAssets) {
      final normalizedAssetPath = assetPath.replaceAll('\\', '/');
      if (!normalizedAssetPath.startsWith(_bundledProfilePicturesRoot)) {
        continue;
      }
      final relativePath =
          normalizedAssetPath.substring(_bundledProfilePicturesRoot.length);
      if (relativePath.isEmpty) {
        continue;
      }
      if (!_isSupportedImagePath(relativePath)) {
        continue;
      }

      String key;
      String filename;
      if (folder == null) {
        if (relativePath.contains('/')) {
          continue;
        }
        key = relativePath;
        filename = relativePath;
      } else {
        final folderPrefix = '$folder/';
        if (!relativePath.startsWith(folderPrefix)) {
          continue;
        }
        final filePortion = relativePath.substring(folderPrefix.length);
        if (filePortion.isEmpty || filePortion.contains('/')) {
          continue;
        }
        key = '$folder/$filePortion';
        filename = filePortion;
      }

      options.add(
        ProfileAvatarOption(
          key: key,
          displayName: _displayNameForFilename(filename),
          isDefault: isDefault,
          assetPath: normalizedAssetPath,
        ),
      );
    }

    options.sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
            right.displayName.toLowerCase(),
          ),
    );
    return options;
  }

  int _parseManifestSort(Object? rawSort) {
    if (rawSort is int) {
      return rawSort;
    }
    if (rawSort is num) {
      return rawSort.toInt();
    }
    if (rawSort is String) {
      return int.tryParse(rawSort) ?? 9999;
    }
    return 9999;
  }

  List<ProfileAvatarCategory> _autoCategorizeRows(
    List<ProfileAvatarOption> options,
  ) {
    final bySeries = <String, List<ProfileAvatarOption>>{};
    for (final option in options) {
      final series = _seriesForKey(option.key);
      bySeries.putIfAbsent(series, () => <ProfileAvatarOption>[]).add(option);
    }

    final rows = <ProfileAvatarCategory>[];
    for (final title in bySeries.keys) {
      final rowOptions = bySeries[title]!
        ..sort((left, right) {
          return left.displayName.toLowerCase().compareTo(
                right.displayName.toLowerCase(),
              );
        });
      rows.add(
        ProfileAvatarCategory(
          id: _slugify(title),
          title: title,
          options: rowOptions,
        ),
      );
    }
    rows.sort(
      (left, right) => left.title.toLowerCase().compareTo(
            right.title.toLowerCase(),
          ),
    );
    return rows;
  }

  String _seriesForKey(String key) {
    final name = _basenameWithoutExtension(key);
    final parts = name.split(' - ');
    if (parts.length < 2) {
      return 'Misc';
    }
    return _cleanCatalogText(parts.first);
  }

  String _cleanCatalogText(String value) {
    var cleaned = value.trim().replaceAll('_', ': ');
    cleaned = _fixMojibake(cleaned);
    return cleaned.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _fixMojibake(String value) {
    if (!value.contains('Ã') && !value.contains('Â')) {
      return value;
    }
    try {
      return utf8.decode(latin1.encode(value));
    } catch (_) {
      return value;
    }
  }

  String _slugify(String value) {
    final cleaned = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'misc' : cleaned;
  }

  Future<Directory?> _findProfilePicturesRoot() async {
    final explicitRoots = _searchRoots;
    final candidates = <Directory>[
      if (explicitRoots != null) ...explicitRoots else ..._defaultSearchRoots(),
    ];
    for (final root in candidates) {
      final resolved = await _searchAncestorsForProfileDirectory(root);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  Iterable<Directory> _defaultSearchRoots() sync* {
    yield Directory.current.absolute;
    yield File(Platform.resolvedExecutable).parent.absolute;
  }

  Future<Directory?> _searchAncestorsForProfileDirectory(
    Directory start,
  ) async {
    var current = start.absolute;
    while (true) {
      final candidate = Directory(
        '${current.path}${Platform.pathSeparator}profile-pictures',
      );
      if (await candidate.exists()) {
        return candidate;
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        return null;
      }
      current = parent;
    }
  }

  Future<List<ProfileAvatarOption>> _readImmediateImageFiles(
    Directory directory, {
    required String keyPrefix,
    required bool isDefault,
    Set<String> excludedDirectories = const <String>{},
  }) async {
    if (!await directory.exists()) {
      return const <ProfileAvatarOption>[];
    }

    final excludedLower =
        excludedDirectories.map((entry) => entry.toLowerCase()).toSet();
    final options = <ProfileAvatarOption>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        final normalizedDirName = _lowerBasename(entity.path);
        if (excludedLower.contains(normalizedDirName)) {
          continue;
        }
        continue;
      }
      if (entity is! File) {
        continue;
      }
      if (!_isSupportedImagePath(entity.path)) {
        continue;
      }
      final filename = _basename(entity.path);
      final key = '$keyPrefix$filename'.replaceAll('\\', '/');
      options.add(
        ProfileAvatarOption(
          key: key,
          file: entity,
          displayName: _displayNameForFilename(filename),
          isDefault: isDefault,
        ),
      );
    }

    options.sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
            right.displayName.toLowerCase(),
          ),
    );
    return options;
  }

  bool _isSupportedImagePath(String path) {
    final extension = _extension(path).toLowerCase();
    return _supportedExtensions.contains(extension);
  }
}

class ProfileAvatarCatalog {
  const ProfileAvatarCatalog({
    required this.defaultOptions,
    required this.otherOptions,
    required this.categories,
    required this.validationIssues,
  });

  const ProfileAvatarCatalog.empty()
      : defaultOptions = const <ProfileAvatarOption>[],
        otherOptions = const <ProfileAvatarOption>[],
        categories = const <ProfileAvatarCategory>[],
        validationIssues = const <String>[];

  final List<ProfileAvatarOption> defaultOptions;
  final List<ProfileAvatarOption> otherOptions;
  final List<ProfileAvatarCategory> categories;
  final List<String> validationIssues;

  List<ProfileAvatarOption> get allOptions =>
      <ProfileAvatarOption>[...defaultOptions, ...otherOptions];

  Set<String> get defaultKeys =>
      defaultOptions.map((option) => option.key).toSet();

  Map<String, ProfileAvatarOption> get byKeyLower =>
      <String, ProfileAvatarOption>{
        for (final option in allOptions) option.key.toLowerCase(): option,
      };
}

class ProfileAvatarCategory {
  const ProfileAvatarCategory({
    required this.id,
    required this.title,
    required this.options,
    this.fallback = false,
  });

  final String id;
  final String title;
  final List<ProfileAvatarOption> options;
  final bool fallback;
}

class ProfileAvatarOption {
  const ProfileAvatarOption({
    required this.key,
    required this.displayName,
    required this.isDefault,
    this.file,
    this.assetPath,
  });

  final String key;
  final File? file;
  final String? assetPath;
  final String displayName;
  final bool isDefault;
}

class _ManifestLoadResult {
  const _ManifestLoadResult({
    required this.categories,
    required this.issues,
  });

  final List<ProfileAvatarCategory> categories;
  final List<String> issues;
}

class _ResolvedManifestItem {
  const _ResolvedManifestItem({
    required this.option,
    required this.sort,
    required this.label,
  });

  final ProfileAvatarOption option;
  final int sort;
  final String label;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slashIndex = normalized.lastIndexOf('/');
  return slashIndex < 0 ? normalized : normalized.substring(slashIndex + 1);
}

String _basenameWithoutExtension(String path) {
  final basename = _basename(path);
  final dotIndex = basename.lastIndexOf('.');
  return dotIndex < 0 ? basename : basename.substring(0, dotIndex);
}

String _lowerBasename(String path) => _basename(path).toLowerCase();

String _extension(String path) {
  final basename = _basename(path);
  final dotIndex = basename.lastIndexOf('.');
  return dotIndex < 0 ? '' : basename.substring(dotIndex);
}

String _displayNameForFilename(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  final rawName = dotIndex < 0 ? filename : filename.substring(0, dotIndex);
  return rawName.replaceAll('_', ' ').trim();
}
