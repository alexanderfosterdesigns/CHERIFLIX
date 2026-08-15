import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/services/subtitles/subtitle_processing.dart';

void main() {
  test('zip extraction skips sample and prefers language + non-HI', () async {
    final zipBytes = _buildZip(
      <String, String>{
        'movie.sample.en.srt': '1\n00:00:01,000 --> 00:00:02,000\nSAMPLE\n',
        'movie.fr.srt': '1\n00:00:01,000 --> 00:00:02,000\nBonjour\n',
        'movie.en.hi.srt': '1\n00:00:01,000 --> 00:00:02,000\n[Door]\n',
        'movie.en.srt': '1\n00:00:01,000 --> 00:00:02,000\nHello\n',
      },
    );

    final extracted = await extractBestSrtFromZipInBackground(
      SubtitleZipExtractionRequest(
        zipBytes: zipBytes,
        expectedLanguageCode: 'en',
        preferHi: false,
      ),
    );

    expect(extracted.fileName, 'movie.en.srt');
    expect(extracted.isHi, isFalse);
    expect(extracted.srtText, contains('Hello'));
  });

  test('zip extraction prefers HI variant when requested', () async {
    final zipBytes = _buildZip(
      <String, String>{
        'episode.en.srt': '1\n00:00:01,000 --> 00:00:02,000\nHello\n',
        'episode.en.sdh.srt': '1\n00:00:01,000 --> 00:00:02,000\n[Noise]\n',
      },
    );

    final extracted = await extractBestSrtFromZipInBackground(
      SubtitleZipExtractionRequest(
        zipBytes: zipBytes,
        expectedLanguageCode: 'en',
        preferHi: true,
      ),
    );

    expect(extracted.fileName, 'episode.en.sdh.srt');
    expect(extracted.isHi, isTrue);
  });

  test('SRT converter keeps cues and normalizes to VTT', () async {
    const converter = SrtToVttConverter();
    final result = await converter.convertInBackground(
      '1\r\n00:00:01,00 --> 00:00:02,50\r\nHello world\r\n',
    );

    expect(result, startsWith('WEBVTT'));
    expect(result, contains('00:00:01.000 --> 00:00:02.500'));
    expect(result, contains('Hello world'));
  });
}

Uint8List _buildZip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.addFile(ArchiveFile.string(name, content));
  });
  final encoded = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(encoded);
}
