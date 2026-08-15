import 'caption_track.dart';
import 'playback_target.dart';

enum PlaybackRendererProfile {
  standard,
  androidAttachEarlyFallback,
  androidProducerStandardFallback,
  androidProducerAttachEarlyFallback,
  androidMediacodecEmbedFallback,
  androidSoftwareFallback,
}

class PlaybackLoadRequest {
  const PlaybackLoadRequest({
    required this.uri,
    required this.sourceKind,
    this.httpHeaders = const <String, String>{},
    required this.allowedHostSuffixes,
    this.captionTracks = const <CaptionTrack>[],
    this.selectedCaptionTrackId,
    this.preferredAudioLanguage = 'en',
    this.providerKey,
    this.originalLanguageCode,
    this.rendererProfile = PlaybackRendererProfile.standard,
  });

  final Uri uri;
  final PlaybackSourceKind sourceKind;
  final Map<String, String> httpHeaders;
  final Set<String> allowedHostSuffixes;
  final List<CaptionTrack> captionTracks;
  final String? selectedCaptionTrackId;
  final String preferredAudioLanguage;
  final String? providerKey;
  final String? originalLanguageCode;
  final PlaybackRendererProfile rendererProfile;
}
