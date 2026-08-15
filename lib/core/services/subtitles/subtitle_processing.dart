import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class SubtitleZipExtractionRequest {
  const SubtitleZipExtractionRequest({
    required this.zipBytes,
    required this.expectedLanguageCode,
    required this.preferHi,
  });

  final Uint8List zipBytes;
  final String expectedLanguageCode;
  final bool preferHi;
}

class SubtitleZipExtractionResult {
  const SubtitleZipExtractionResult({
    required this.fileName,
    required this.srtText,
    required this.isHi,
  });

  final String fileName;
  final String srtText;
  final bool isHi;
}

class SrtToVttConverter {
  const SrtToVttConverter();

  Future<String> convertInBackground(String srtText) {
    return Isolate.run<String>(() => _convertSrtToVttSync(srtText));
  }
}

Future<SubtitleZipExtractionResult> extractBestSrtFromZipInBackground(
  SubtitleZipExtractionRequest request,
) {
  return Isolate.run<SubtitleZipExtractionResult>(
    () => _extractBestSrtFromZipSync(request),
  );
}

SubtitleZipExtractionResult _extractBestSrtFromZipSync(
  SubtitleZipExtractionRequest request,
) {
  final archive = ZipDecoder().decodeBytes(request.zipBytes, verify: true);
  final entries = <_RankedSubtitleEntry>[];
  final expectedLanguage = request.expectedLanguageCode.trim().toLowerCase();
  final hiPattern = RegExp(r'\b(hi|sdh|hearing[\s._-]?impaired)\b');
  final samplePattern = RegExp(r'sample', caseSensitive: false);

  for (final file in archive.files) {
    if (!file.isFile) {
      continue;
    }
    final rawName = file.name.trim();
    if (rawName.isEmpty) {
      continue;
    }
    final lowerName = rawName.toLowerCase();
    if (!lowerName.endsWith('.srt')) {
      continue;
    }
    if (samplePattern.hasMatch(lowerName)) {
      continue;
    }

    final fileData = file.content;
    if (fileData is! List<int> || fileData.isEmpty) {
      continue;
    }

    final languageScore = _languageMatchScore(lowerName, expectedLanguage);
    final isHi = hiPattern.hasMatch(lowerName);
    final hiScore = request.preferHi ? (isHi ? 3 : 1) : (isHi ? 0 : 3);
    final cleanlinessPenalty = rawName.length;
    entries.add(
      _RankedSubtitleEntry(
        fileName: rawName,
        bytes: Uint8List.fromList(fileData),
        languageScore: languageScore,
        hiScore: hiScore,
        cleanlinessPenalty: cleanlinessPenalty,
        isHi: isHi,
      ),
    );
  }

  if (entries.isEmpty) {
    throw const FormatException('No usable SRT files found in subtitle zip.');
  }

  entries.sort((left, right) {
    final languageCompare = right.languageScore.compareTo(left.languageScore);
    if (languageCompare != 0) {
      return languageCompare;
    }
    final hiCompare = right.hiScore.compareTo(left.hiScore);
    if (hiCompare != 0) {
      return hiCompare;
    }
    return left.cleanlinessPenalty.compareTo(right.cleanlinessPenalty);
  });

  final winner = entries.first;
  final decoded = _decodeSrtBytes(winner.bytes);
  if (decoded.trim().isEmpty) {
    throw const FormatException('Selected subtitle file was empty.');
  }

  return SubtitleZipExtractionResult(
    fileName: winner.fileName,
    srtText: decoded,
    isHi: winner.isHi,
  );
}

int _languageMatchScore(String lowerFileName, String expectedLanguageCode) {
  if (expectedLanguageCode.isEmpty) {
    return 0;
  }
  final iso2 = expectedLanguageCode.length >= 2
      ? expectedLanguageCode.substring(0, 2).toLowerCase()
      : expectedLanguageCode.toLowerCase();
  final boundaryPattern =
      RegExp('(^|[\\s._\\-\\[\\]\\(\\)])$iso2([\\s._\\-\\[\\]\\(\\)]|\$)');
  if (boundaryPattern.hasMatch(lowerFileName)) {
    return 3;
  }

  final aliases = switch (iso2) {
    'en' => const <String>['english', 'eng'],
    'fr' => const <String>['french', 'fra', 'fre'],
    'ar' => const <String>['arabic', 'ara'],
    _ => <String>[iso2],
  };
  for (final alias in aliases) {
    final aliasPattern =
        RegExp('(^|[\\s._\\-\\[\\]\\(\\)])$alias([\\s._\\-\\[\\]\\(\\)]|\$)');
    if (aliasPattern.hasMatch(lowerFileName)) {
      return 2;
    }
  }
  return 0;
}

String _decodeSrtBytes(Uint8List bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

String _convertSrtToVttSync(String srtText) {
  final normalized = srtText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final output = StringBuffer('WEBVTT\n\n');
  for (final line in lines) {
    if (line.contains('-->')) {
      output.writeln(
        line.replaceAll(',', '.').replaceAllMapped(
            RegExp(r'(\d{2}:\d{2}:\d{2}\.\d{1,2})(\s|$)'), (match) {
          final value = match.group(1)!;
          final parts = value.split('.');
          final fraction = parts.length > 1 ? parts[1].padRight(3, '0') : '000';
          return '${parts[0]}.$fraction${match.group(2)}';
        }),
      );
      continue;
    }
    output.writeln(line);
  }
  return output.toString();
}

class _RankedSubtitleEntry {
  const _RankedSubtitleEntry({
    required this.fileName,
    required this.bytes,
    required this.languageScore,
    required this.hiScore,
    required this.cleanlinessPenalty,
    required this.isHi,
  });

  final String fileName;
  final Uint8List bytes;
  final int languageScore;
  final int hiScore;
  final int cleanlinessPenalty;
  final bool isHi;
}
