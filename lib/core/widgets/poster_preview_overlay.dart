import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/runtime_pressure.dart';

const bool _enableAndroidTrailerPreviews = bool.fromEnvironment(
  'CHERIFLIX_ANDROID_TRAILER_PREVIEWS',
  defaultValue: false,
);

class PosterPreviewController extends ChangeNotifier {
  PosterPreviewController({
    this.previewDelay = const Duration(milliseconds: 1800),
  });

  final Duration previewDelay;
  final Map<String, Uri?> _previewCache = <String, Uri?>{};

  Timer? _loadTimer;
  int _requestId = 0;
  String? _activeKey;
  LayerLink? _activeLayerLink;
  Size? _activeSize;
  Uri? _activePreviewUri;

  String? get activeKey => _activeKey;
  LayerLink? get activeLayerLink => _activeLayerLink;
  Size? get activeSize => _activeSize;
  Uri? get activePreviewUri => _activePreviewUri;

  void focus({
    required String itemKey,
    required LayerLink layerLink,
    required Size size,
    required Future<Uri?> Function() loadPreview,
  }) {
    final hasCachedValue = _previewCache.containsKey(itemKey);
    final cachedUri = hasCachedValue ? _previewCache[itemKey] : null;
    _requestId += 1;
    _loadTimer?.cancel();
    _activeKey = itemKey;
    _activeLayerLink = layerLink;
    _activeSize = size;
    _activePreviewUri =
        CheriflixRuntimePressureController.instance.previewSuspendedForSession
            ? null
            : cachedUri;
    notifyListeners();

    if (hasCachedValue ||
        !cheriflixTrailerPreviewsSupported ||
        CheriflixRuntimePressureController
            .instance.previewSuspendedForSession) {
      return;
    }

    final requestId = _requestId;
    Future<void> loadRequestedPreview() async {
      Uri? uri;
      try {
        uri = await loadPreview();
      } catch (_) {
        CheriflixRuntimePressureController.instance.recordPreviewFailure();
        return;
      }
      _previewCache[itemKey] = uri;
      if (_requestId != requestId || _activeKey != itemKey) {
        return;
      }
      _activePreviewUri = uri;
      notifyListeners();
    }

    if (previewDelay <= Duration.zero) {
      unawaited(loadRequestedPreview());
      return;
    }

    _loadTimer = Timer(previewDelay, () {
      unawaited(loadRequestedPreview());
    });
  }

  void blur(String itemKey) {
    if (_activeKey != itemKey) {
      return;
    }
    _requestId += 1;
    _loadTimer?.cancel();
    _activeKey = null;
    _activeLayerLink = null;
    _activeSize = null;
    _activePreviewUri = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }
}

class PosterPreviewOverlay extends StatefulWidget {
  const PosterPreviewOverlay({
    super.key,
    required this.controller,
    this.borderRadius = 16,
    this.mode = TrailerPreviewMode.card,
    this.showBadge = true,
  });

  final PosterPreviewController controller;
  final double borderRadius;
  final TrailerPreviewMode mode;
  final bool showBadge;

  @override
  State<PosterPreviewOverlay> createState() => _PosterPreviewOverlayState();
}

enum TrailerPreviewMode {
  card,
  backdrop,
  hero,
}

class _PosterPreviewOverlayState extends State<PosterPreviewOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant PosterPreviewOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
    _handleControllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPreviewPlatformSupported ||
        CheriflixRuntimePressureController
            .instance.previewSuspendedForSession) {
      return const SizedBox.shrink();
    }

    final layerLink = widget.controller.activeLayerLink;
    final size = widget.controller.activeSize;
    final previewUri = widget.controller.activePreviewUri;
    if (layerLink == null || size == null || previewUri == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: CompositedTransformFollower(
        link: layerLink,
        showWhenUnlinked: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  BackdropTrailerPreview(
                    previewUri: previewUri,
                    mode: widget.mode,
                    borderRadius: widget.borderRadius,
                  ),
                  if (widget.showBadge)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC111111),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x30FFFFFF)),
                        ),
                        child: const Text(
                          'TRAILER PREVIEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class BackdropTrailerPreview extends StatefulWidget {
  const BackdropTrailerPreview({
    super.key,
    required this.previewUri,
    this.mode = TrailerPreviewMode.backdrop,
    this.borderRadius = 0,
    this.onReady,
    this.onPlaybackStarted,
    this.onPlaybackStopped,
  });

  final Uri? previewUri;
  final TrailerPreviewMode mode;
  final double borderRadius;
  final VoidCallback? onReady;
  final VoidCallback? onPlaybackStarted;
  final VoidCallback? onPlaybackStopped;

  @override
  State<BackdropTrailerPreview> createState() => _BackdropTrailerPreviewState();
}

class _BackdropTrailerPreviewState extends State<BackdropTrailerPreview>
    with WidgetsBindingObserver {
  final Object _previewOwner = Object();
  URLRequest? _initialUrlRequest;
  InAppWebViewController? _controller;
  Key? _webViewKey;
  bool _ready = false;
  bool _playbackStarted = false;
  String? _loadedPreviewUri;
  String? _messageToken;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CheriflixRuntimePressureController.instance.addListener(
      _handleRuntimePressureChanged,
    );
    _syncPreview();
  }

  @override
  void didUpdateWidget(covariant BackdropTrailerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewUri != widget.previewUri ||
        oldWidget.mode != widget.mode) {
      _syncPreview();
    }
  }

  @override
  void dispose() {
    CheriflixRuntimePressureController.instance.removeListener(
      _handleRuntimePressureChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    CheriflixRuntimePressureController.instance.releasePreviewSurface(
      _previewOwner,
    );
    _emitPlaybackStopped();
    unawaited(_stopAndBlankPreview());
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    CheriflixRuntimePressureController.instance.handleMemoryPressure();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return;
    }
    CheriflixRuntimePressureController.instance.releasePreviewSurface(
      _previewOwner,
    );
    _collapsePreview(clearLoadedPreview: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPreviewPlatformSupported ||
        CheriflixRuntimePressureController
            .instance.previewSuspendedForSession ||
        !CheriflixRuntimePressureController.instance.ownsPreviewSurface(
          _previewOwner,
        ) ||
        widget.previewUri == null ||
        !_ready ||
        _initialUrlRequest == null ||
        _webViewKey == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: ExcludeFocus(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InAppWebView(
            key: _webViewKey,
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              cacheEnabled: false,
              disableContextMenu: true,
              allowsInlineMediaPlayback: true,
              iframeAllow:
                  'autoplay; fullscreen; encrypted-media; picture-in-picture',
              iframeAllowFullscreen: true,
              supportZoom: false,
              mediaPlaybackRequiresUserGesture: false,
              javaScriptCanOpenWindowsAutomatically: false,
              supportMultipleWindows: false,
            ),
            initialUrlRequest: _initialUrlRequest,
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'cheriflixPreviewMessage',
                callback: (arguments) {
                  if (arguments.isEmpty || arguments.first is! Map) {
                    return null;
                  }
                  _handleWebMessage(
                    Map<dynamic, dynamic>.from(arguments.first as Map),
                  );
                  return null;
                },
              );
            },
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame != true ||
                  !_isFatalWebResourceError(error) ||
                  _isIgnoredWebResourceError(error)) {
                return;
              }
              CheriflixRuntimePressureController.instance
                  .recordPreviewFailure();
              _collapsePreview(clearLoadedPreview: true);
            },
            onReceivedHttpError: (controller, request, response) {
              if (request.isForMainFrame != true) {
                return;
              }
              final statusCode = response.statusCode;
              if (statusCode == null || statusCode < 400) {
                return;
              }
              CheriflixRuntimePressureController.instance
                  .recordPreviewFailure();
              _collapsePreview(clearLoadedPreview: true);
            },
            onWebContentProcessDidTerminate: (controller) {
              CheriflixRuntimePressureController.instance
                  .recordPreviewFailure();
              _collapsePreview(clearLoadedPreview: true);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _syncPreview() async {
    final runtimePressure = CheriflixRuntimePressureController.instance;
    if (!_isPreviewPlatformSupported ||
        runtimePressure.previewSuspendedForSession) {
      runtimePressure.releasePreviewSurface(_previewOwner);
      _collapsePreview(clearLoadedPreview: true);
      return;
    }

    final previewUri = widget.previewUri?.toString();
    if (previewUri == null || previewUri.isEmpty) {
      runtimePressure.releasePreviewSurface(_previewOwner);
      _emitPlaybackStopped();
      unawaited(_stopAndBlankPreview());
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = false;
        _loadedPreviewUri = null;
        _messageToken = null;
        _webViewKey = null;
        _initialUrlRequest = null;
      });
      return;
    }

    if (_loadedPreviewUri == previewUri &&
        _ready &&
        _initialUrlRequest != null &&
        _webViewKey != null) {
      runtimePressure.claimPreviewSurface(_previewOwner);
      return;
    }

    final preservedFocus = _capturePrimaryFocus();
    final requestId = ++_requestId;
    final messageToken = 'cheriflix-preview-$requestId';
    _emitPlaybackStopped();
    Uri shellUrl;
    try {
      shellUrl = await _buildHostedPreviewShellUrl(
        previewUri,
        mode: widget.mode,
        borderRadius: widget.borderRadius,
        messageToken: messageToken,
      );
    } catch (_) {
      runtimePressure.recordPreviewFailure();
      if (!mounted || requestId != _requestId) {
        return;
      }
      _collapsePreview(clearLoadedPreview: false);
      return;
    }
    if (!mounted || requestId != _requestId) {
      return;
    }

    runtimePressure.claimPreviewSurface(_previewOwner);
    setState(() {
      _loadedPreviewUri = previewUri;
      _ready = true;
      _messageToken = messageToken;
      _webViewKey = ValueKey<String>(
        'trailer_preview_${widget.mode.name}_$requestId',
      );
      _initialUrlRequest = URLRequest(url: WebUri(shellUrl.toString()));
    });
    _restorePrimaryFocus(preservedFocus);
    widget.onReady?.call();
  }

  void _handleWebMessage(dynamic message) {
    if (message is! Map) {
      return;
    }

    final channel = '${message['channel'] ?? ''}'.trim();
    final type = '${message['type'] ?? ''}'.trim();
    final token = '${message['token'] ?? ''}'.trim();
    if (channel != 'cheriflix-preview' ||
        token.isEmpty ||
        token != _messageToken) {
      return;
    }

    if (type == 'playing') {
      if (_playbackStarted) {
        return;
      }
      _playbackStarted = true;
      widget.onPlaybackStarted?.call();
      return;
    }

    if (type == 'stopped') {
      _emitPlaybackStopped();
    }
  }

  void _emitPlaybackStopped() {
    if (!_playbackStarted) {
      return;
    }
    _playbackStarted = false;
    widget.onPlaybackStopped?.call();
  }

  void _collapsePreview({
    bool clearLoadedPreview = false,
  }) {
    _emitPlaybackStopped();
    unawaited(_stopAndBlankPreview());
    if (!mounted) {
      return;
    }
    setState(() {
      _ready = false;
      if (clearLoadedPreview) {
        _loadedPreviewUri = null;
      }
      _messageToken = null;
      _webViewKey = null;
      _initialUrlRequest = null;
    });
  }

  Future<void> _stopAndBlankPreview() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      await controller.evaluateJavascript(
        source: '''
          document.querySelectorAll('video, audio').forEach((node) => {
            try {
              node.pause();
              node.removeAttribute('src');
              node.load();
            } catch (_) {}
          });
        ''',
      );
    } catch (_) {}
    try {
      await controller.stopLoading();
    } catch (_) {}
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    } catch (_) {}
  }

  void _handleRuntimePressureChanged() {
    final runtimePressure = CheriflixRuntimePressureController.instance;
    if (!runtimePressure.previewSuspendedForSession &&
        runtimePressure.ownsPreviewSurface(_previewOwner)) {
      return;
    }
    _collapsePreview(clearLoadedPreview: true);
  }

  FocusNode? _capturePrimaryFocus() {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null || !focusNode.canRequestFocus) {
      return null;
    }
    return focusNode;
  }

  void _restorePrimaryFocus(FocusNode? focusNode) {
    if (focusNode == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || focusNode.context == null || !focusNode.canRequestFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }
}

bool _isIgnoredWebResourceError(WebResourceError error) {
  final description = error.description.trim().toLowerCase();
  return error.type == WebResourceErrorType.CANCELLED ||
      description.contains('err_aborted') ||
      description.contains('net::err_aborted') ||
      description.contains('blocked by client');
}

bool _isFatalWebResourceError(WebResourceError error) {
  return error.type == WebResourceErrorType.BAD_URL ||
      error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
      error.type == WebResourceErrorType.FILE_NOT_FOUND ||
      error.type == WebResourceErrorType.HOST_LOOKUP ||
      error.type == WebResourceErrorType.FAILED_SSL_HANDSHAKE ||
      error.type == WebResourceErrorType.TOO_MANY_REDIRECTS ||
      error.type == WebResourceErrorType.TIMEOUT ||
      error.type == WebResourceErrorType.UNSAFE_RESOURCE;
}

bool get cheriflixTrailerPreviewsSupported =>
    !kIsWeb &&
    (Platform.environment.containsKey('FLUTTER_TEST') ||
        defaultTargetPlatform == TargetPlatform.windows ||
        (defaultTargetPlatform == TargetPlatform.android &&
            _enableAndroidTrailerPreviews));

bool get _isPreviewPlatformSupported =>
    !kIsWeb &&
    !Platform.environment.containsKey('FLUTTER_TEST') &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        (defaultTargetPlatform == TargetPlatform.android &&
            _enableAndroidTrailerPreviews));

const String _previewShellFileName = 'preview_shell.html';

Future<_PreviewShellServer>? _previewShellServerFuture;

Future<_PreviewShellServer> _ensurePreviewShellServer() {
  return _previewShellServerFuture ??= _createPreviewShellServer();
}

Future<_PreviewShellServer> _createPreviewShellServer() async {
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
    shared: true,
  );
  unawaited(
    server.forEach((request) async {
      if (request.method == 'GET' &&
          (request.uri.path == '/' ||
              request.uri.path == '/$_previewShellFileName')) {
        request.response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        request.response.headers
            .set(HttpHeaders.cacheControlHeader, 'no-store');
        request.response.headers.set(
          'Referrer-Policy',
          'strict-origin-when-cross-origin',
        );
        request.response.write(_previewHostHtml);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    }),
  );
  return _PreviewShellServer(
    server: server,
    baseUri: Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    ),
  );
}

class _PreviewShellServer {
  const _PreviewShellServer({
    required this.server,
    required this.baseUri,
  });

  final HttpServer server;
  final Uri baseUri;
}

Future<Uri> _buildHostedPreviewShellUrl(
  String previewUri, {
  required TrailerPreviewMode mode,
  required double borderRadius,
  required String messageToken,
}) async {
  final server = await _ensurePreviewShellServer();
  return server.baseUri.replace(
    path: '/$_previewShellFileName',
    queryParameters: <String, String>{
      'mode': mode.name,
      'src': _decoratePreviewSource(
        previewUri,
        previewOrigin: server.baseUri.origin,
      ),
      'token': messageToken,
      'radius': borderRadius.toStringAsFixed(2),
    },
  );
}

String _decoratePreviewSource(
  String rawPreviewUri, {
  String previewOrigin = '',
}) {
  final uri = Uri.tryParse(rawPreviewUri);
  if (uri == null) {
    return rawPreviewUri;
  }

  if (uri.scheme == 'cheriflix-preview') {
    final queryParameters = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      if (entry.key == 'src' || entry.key.startsWith('src')) {
        queryParameters[entry.key] = _decoratePreviewSource(
          entry.value,
          previewOrigin: previewOrigin,
        );
      } else {
        queryParameters[entry.key] = entry.value;
      }
    }
    return uri.replace(queryParameters: queryParameters).toString();
  }

  final normalizedHost = uri.host.toLowerCase();
  final isYouTube = normalizedHost.contains('youtube.com') ||
      normalizedHost.contains('youtube-nocookie.com') ||
      normalizedHost.contains('youtu.be');
  if (!isYouTube) {
    return rawPreviewUri;
  }

  final normalizedUri = normalizedHost.contains('youtube.com') &&
          !normalizedHost.contains('youtube-nocookie.com')
      ? uri.replace(
          scheme: 'https',
          host: 'www.youtube-nocookie.com',
        )
      : uri;
  final queryParameters = <String, String>{
    ...normalizedUri.queryParameters,
    'origin': previewOrigin,
    'widget_referrer': previewOrigin,
  };
  return normalizedUri.replace(queryParameters: queryParameters).toString();
}

const String _previewHostConfigScript = '''
      const params = new URLSearchParams(window.location.search);
      const requestedMode = params.get('mode');
      const mode =
        requestedMode === 'backdrop' || requestedMode === 'hero'
          ? requestedMode
          : 'card';
      const src = params.get('src');
      const token = params.get('token') || '';
      const radius = Math.max(0, Number(params.get('radius') || '0'));
      const resolvedRadius = Number.isFinite(radius) ? radius : 0;
      document.documentElement.style.setProperty(
        '--preview-border-radius',
        `\${resolvedRadius}px`
      );
''';

const String _previewHostHtml = '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="referrer" content="strict-origin-when-cross-origin" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
    />
    <style>
      html, body {
        margin: 0;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: transparent;
      }
      body {
        position: relative;
        border-radius: var(--preview-border-radius, 0px);
      }
      body.card,
      body.hero {
        overflow: hidden;
      }
      .surface,
      .surface iframe,
      .surface #player {
        position: absolute;
        border: 0;
        background: #000;
        pointer-events: none;
        opacity: 0;
        overflow: hidden;
        transition: opacity 180ms ease;
      }
      body.ready .surface,
      body.ready .surface iframe,
      body.ready .surface #player,
      body.playing .surface,
      body.playing .surface iframe,
      body.playing .surface #player {
        opacity: 1;
      }
      body.card .surface,
      body.card iframe,
      body.card #player {
        position: absolute;
        left: -16%;
        top: -11%;
        width: 132%;
        height: 122%;
      }
      body.backdrop .surface,
      body.backdrop iframe,
      body.backdrop #player {
        position: absolute;
        left: -24%;
        top: -21%;
        width: 148%;
        height: 140%;
        opacity: 1;
      }
      body.hero .surface,
      body.hero iframe,
      body.hero #player {
        position: absolute;
        left: -32%;
        top: -22%;
        width: 164%;
        height: 144%;
        opacity: 1;
      }
      .conceal {
        position: absolute;
        inset: 0;
        z-index: 20;
        pointer-events: none;
        opacity: 1;
        transition: opacity 280ms ease;
      }
      .chrome-mask {
        position: absolute;
        z-index: 30;
        pointer-events: none;
        display: none;
      }
      body.card .conceal {
        background: linear-gradient(
          to top,
          rgba(0, 0, 0, 0.42) 0,
          rgba(0, 0, 0, 0.22) 24%,
          rgba(0, 0, 0, 0.06) 58%,
          rgba(0, 0, 0, 0) 100%
        );
      }
      body.backdrop .conceal,
      body.hero .conceal {
        display: none;
      }
      body.ready .conceal,
      body.playing .conceal {
        opacity: 0;
      }
      body.backdrop::after,
      body.hero::after {
        content: '';
        position: absolute;
        inset: 0;
        pointer-events: none;
        background: linear-gradient(
          to bottom,
          rgba(20, 20, 20, 0.22) 0,
          rgba(20, 20, 20, 0.15) 8%,
          rgba(20, 20, 20, 0.09) 18%,
          rgba(20, 20, 20, 0.04) 32%,
          rgba(20, 20, 20, 0.01) 46%,
          rgba(20, 20, 20, 0) 62%
        );
      }
      body.card::after {
        content: '';
        position: absolute;
        inset: 0;
        pointer-events: none;
        background: linear-gradient(
          to top,
          rgba(0, 0, 0, 0.24) 0,
          rgba(0, 0, 0, 0.1) 32%,
          rgba(0, 0, 0, 0.02) 64%,
          rgba(0, 0, 0, 0) 100%
        );
      }
    </style>
  </head>
  <body class="card">
    <div class="conceal"></div>
    <div class="chrome-mask top-left"></div>
    <div class="chrome-mask top-right"></div>
    <div class="chrome-mask bottom-right"></div>
    <script>
$_previewHostConfigScript

      document.body.className = mode;

      let playbackStarted = false;
      let currentSourceIndex = -1;

      const postMessage = (type) => {
        try {
          if (
            window.flutter_inappwebview &&
            typeof window.flutter_inappwebview.callHandler === 'function'
          ) {
            window.flutter_inappwebview.callHandler(
              'cheriflixPreviewMessage',
              {
                channel: 'cheriflix-preview',
                token,
                type,
              }
            );
            return;
          }
          if (
            !window.chrome ||
            !window.chrome.webview ||
            typeof window.chrome.webview.postMessage !== 'function'
          ) {
            return;
          }
          window.chrome.webview.postMessage({
            channel: 'cheriflix-preview',
            token,
            type,
          });
        } catch (_) {}
      };

      const markPlaying = () => {
        revealPlayback();
        if (playbackStarted) {
          return;
        }
        playbackStarted = true;
        document.body.classList.add('playing');
        postMessage('playing');
      };

      const markStopped = () => {
        if (!playbackStarted) {
          return;
        }
        playbackStarted = false;
        document.body.classList.remove('playing');
        postMessage('stopped');
      };

      const revealPlayback = () => {
        document.body.classList.add('ready');
      };

      const concealPlayback = () => {
        document.body.classList.remove('ready');
      };

      const isYouTubeSource = (value) =>
        value.includes('youtube.com/embed/') ||
        value.includes('youtube-nocookie.com/embed/');

      const resolvePreviewSources = (value) => {
        if (!value) {
          return [];
        }
        try {
          const parsedUrl = new URL(value);
          if (parsedUrl.protocol === 'cheriflix-preview:') {
            const sources = [];
            const primary = parsedUrl.searchParams.get('src');
            if (primary) {
              sources.push(primary);
            }
            Array.from(parsedUrl.searchParams.keys())
              .filter(
                (key) =>
                  key.startsWith('src') &&
                  key !== 'src' &&
                  /^[0-9]+/.test(key.slice(3))
              )
              .sort((left, right) => Number(left.slice(3)) - Number(right.slice(3)))
              .forEach((key) => {
                const candidate = parsedUrl.searchParams.get(key);
                if (candidate) {
                  sources.push(candidate);
                }
              });
            return sources;
          }
        } catch (_) {}
        return [value];
      };

      window.addEventListener('beforeunload', () => {
        markStopped();
      });

      function clearPreviewSurface() {
        concealPlayback();
        document.querySelectorAll('.surface').forEach((node) => {
          try {
            node.remove();
          } catch (_) {}
        });
      }

      let youtubeIframeApiPromise = null;

      function extractYouTubeVideoId(parsedUrl) {
        const host = (parsedUrl.hostname || '').toLowerCase();
        const segments = parsedUrl.pathname.split('/').filter(Boolean);
        const queryVideoId =
          parsedUrl.searchParams.get('v') || parsedUrl.searchParams.get('vi');
        if (queryVideoId) {
          return queryVideoId;
        }
        if (host === 'youtu.be' && segments.length > 0) {
          return segments[0];
        }
        const knownPrefix = ['embed', 'shorts', 'live'].find((prefix) =>
          segments.includes(prefix)
        );
        if (knownPrefix) {
          const prefixIndex = segments.indexOf(knownPrefix);
          if (prefixIndex >= 0 && prefixIndex + 1 < segments.length) {
            return segments[prefixIndex + 1];
          }
        }
        return segments.length > 0 ? segments[segments.length - 1] : '';
      }

      function createYouTubeEmbedUrl(parsedUrl, videoId, muted) {
        const embedUrl = new URL(parsedUrl.toString());
        embedUrl.protocol = 'https:';
        embedUrl.hostname = 'www.youtube-nocookie.com';
        embedUrl.port = '';
        embedUrl.pathname = '/embed/' + videoId;
        embedUrl.searchParams.set('autoplay', '1');
        embedUrl.searchParams.set('mute', muted ? '1' : '0');
        embedUrl.searchParams.set('controls', '0');
        embedUrl.searchParams.set('modestbranding', '1');
        embedUrl.searchParams.set('rel', '0');
        embedUrl.searchParams.set('playsinline', '1');
        embedUrl.searchParams.set('loop', '1');
        embedUrl.searchParams.set(
          'playlist',
          embedUrl.searchParams.get('playlist') || videoId
        );
        embedUrl.searchParams.set('iv_load_policy', '3');
        embedUrl.searchParams.set('fs', '0');
        embedUrl.searchParams.set('disablekb', '1');
        embedUrl.searchParams.set('cc_load_policy', '0');
        embedUrl.searchParams.set('enablejsapi', '1');
        return embedUrl.toString();
      }

      function loadYouTubeIframeApi() {
        if (window.YT && typeof window.YT.Player === 'function') {
          return Promise.resolve(window.YT);
        }
        if (youtubeIframeApiPromise) {
          return youtubeIframeApiPromise;
        }

        youtubeIframeApiPromise = new Promise((resolve, reject) => {
          let settled = false;
          const settle = (callback, value) => {
            if (settled) {
              return;
            }
            settled = true;
            window.clearTimeout(timeoutId);
            callback(value);
          };

          const handleReady = () => {
            if (window.YT && typeof window.YT.Player === 'function') {
              settle(resolve, window.YT);
            }
          };

          const timeoutId = window.setTimeout(() => {
            settle(reject, new Error('YouTube iframe API timed out.'));
          }, 8000);

          const previousReadyHandler = window.onYouTubeIframeAPIReady;
          window.onYouTubeIframeAPIReady = () => {
            try {
              if (typeof previousReadyHandler === 'function') {
                previousReadyHandler();
              }
            } catch (_) {}
            handleReady();
          };

          let script = document.querySelector(
            'script[data-cheriflix-youtube-api="true"]'
          );
          if (!script) {
            script = document.createElement('script');
            script.src = 'https://www.youtube.com/iframe_api';
            script.async = true;
            script.defer = true;
            script.setAttribute('data-cheriflix-youtube-api', 'true');
            script.addEventListener('error', () => {
              settle(reject, new Error('YouTube iframe API failed to load.'));
            });
            document.head.appendChild(script);
          }
          script.addEventListener('load', handleReady);

          handleReady();
        }).catch((error) => {
          youtubeIframeApiPromise = null;
          throw error;
        });

        return youtubeIframeApiPromise;
      }

      function createYouTubePlayer(url, onFatalError) {
        let parsedUrl;
        try {
          parsedUrl = new URL(url);
        } catch (_) {
          if (typeof onFatalError === 'function') {
            onFatalError();
          }
          return;
        }

        const videoId = extractYouTubeVideoId(parsedUrl);
        if (!videoId) {
          if (typeof onFatalError === 'function') {
            onFatalError();
          }
          return;
        }

        const vars = {};
        parsedUrl.searchParams.forEach((value, key) => {
          vars[key] = value;
        });
        const wantsAudio = Number(vars.mute || vars.muted || '0') !== 1;
        // Bootstrap in a muted state so autoplay is never coupled to
        // the audio preference. We restore audio only after playback starts.
        const autoplayBootstrapUrl = createYouTubeEmbedUrl(
          parsedUrl,
          videoId,
          true
        );
        const youtubeHostOrigin = 'https://www.youtube-nocookie.com';

        const shell = document.createElement('iframe');
        shell.id = 'player';
        shell.className = 'surface';

        let audioAttempted = false;
        let audioReasserted = false;
        let audioRecoveredToMuted = false;
        let lastPlayingAt = 0;
        let autoplayKickTimer = null;
        let autoplayKickCount = 0;
        let loadFailureTimer = null;
        let playerInstance = null;

        const configureIframe = (frame) => {
          if (!frame) {
            return;
          }
          try {
            frame.allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture';
            frame.allowFullscreen = true;
            frame.referrerPolicy = 'strict-origin-when-cross-origin';
            frame.tabIndex = -1;
          } catch (_) {}
        };

        const configurePlayerFrame = (player) => {
          try {
            configureIframe(player.getIframe());
          } catch (_) {}
        };

        const stopAutoplayKick = () => {
          if (autoplayKickTimer == null) {
            return;
          }
          window.clearInterval(autoplayKickTimer);
          autoplayKickTimer = null;
        };

        const stopLoadFailureTimer = () => {
          if (loadFailureTimer == null) {
            return;
          }
          window.clearTimeout(loadFailureTimer);
          loadFailureTimer = null;
        };

        const scheduleLoadFailureTimer = () => {
          stopLoadFailureTimer();
          loadFailureTimer = window.setTimeout(() => {
            if (!playbackStarted) {
              advanceFromFatalError(0);
            }
          }, 8000);
        };

        const disposePlayerSurface = () => {
          stopAutoplayKick();
          stopLoadFailureTimer();
          try {
            if (playerInstance && typeof playerInstance.destroy === 'function') {
              playerInstance.destroy();
            }
          } catch (_) {}
          playerInstance = null;
          try {
            shell.remove();
          } catch (_) {}
        };

        const advanceFromFatalError = (errorCode) => {
          markStopped();
          disposePlayerSurface();
          if (typeof onFatalError === 'function') {
            onFatalError(errorCode);
            return;
          }
          clearPreviewSurface();
          markStopped();
        };

        const syncAudio = (player) => {
          if (!wantsAudio || audioReasserted) {
            return;
          }
          audioAttempted = true;
          audioReasserted = true;
          window.setTimeout(() => {
            try {
              player.unMute();
              player.setVolume(100);
            } catch (_) {}
          }, 1600);
        };

        const startPlayback = (player) => {
          configurePlayerFrame(player);
          try {
            player.mute();
            player.setVolume(0);
            player.playVideo();
            window.setTimeout(() => {
              try {
                player.playVideo();
              } catch (_) {}
            }, 220);
            window.setTimeout(() => {
              try {
                player.playVideo();
              } catch (_) {}
            }, 650);
            window.setTimeout(() => {
              try {
                player.playVideo();
              } catch (_) {}
            }, 1200);
          } catch (_) {}
        };

        const scheduleAutoplayKick = (player) => {
          stopAutoplayKick();
          autoplayKickCount = 0;
          autoplayKickTimer = window.setInterval(() => {
            if (playbackStarted || autoplayKickCount >= 8) {
              stopAutoplayKick();
              return;
            }
            autoplayKickCount += 1;
            startPlayback(player);
          }, 360);
        };

        const bootstrapPlayer = () => {
          configureIframe(shell);
          shell.src = autoplayBootstrapUrl;
          document.body.appendChild(shell);
          scheduleLoadFailureTimer();
          playerInstance = new YT.Player(shell, {
            host: youtubeHostOrigin,
            events: {
              onReady: (event) => {
                configurePlayerFrame(event.target);
                startPlayback(event.target);
                scheduleAutoplayKick(event.target);
              },
              onAutoplayBlocked: (event) => {
                configurePlayerFrame(event.target);
                startPlayback(event.target);
                scheduleAutoplayKick(event.target);
              },
              onStateChange: (event) => {
                if (!window.YT) {
                  return;
                }
                if (event.data === window.YT.PlayerState.PLAYING) {
                  stopAutoplayKick();
                  stopLoadFailureTimer();
                  lastPlayingAt = Date.now();
                  markPlaying();
                  syncAudio(event.target);
                  return;
                }

                if (event.data === window.YT.PlayerState.BUFFERING) {
                  configurePlayerFrame(event.target);
                  return;
                }

                const droppedAfterAudioAttempt =
                  wantsAudio &&
                  audioAttempted &&
                  !audioRecoveredToMuted &&
                  lastPlayingAt > 0 &&
                  Date.now() - lastPlayingAt < 2400;

                if (droppedAfterAudioAttempt) {
                  audioRecoveredToMuted = true;
                  try {
                    event.target.mute();
                    event.target.playVideo();
                  } catch (_) {}
                  return;
                }

                if (
                  event.data === window.YT.PlayerState.UNSTARTED ||
                  event.data === window.YT.PlayerState.PAUSED ||
                  event.data === window.YT.PlayerState.CUED ||
                  event.data === window.YT.PlayerState.ENDED
                ) {
                  markStopped();
                  startPlayback(event.target);
                  scheduleAutoplayKick(event.target);
                }
              },
              onError: (event) => {
                const errorCode = Number(event && event.data ? event.data : 0);
                advanceFromFatalError(errorCode);
              }
            }
          });
        };

        loadYouTubeIframeApi()
          .then(() => {
            bootstrapPlayer();
          })
          .catch(() => {
            advanceFromFatalError(0);
          });
      }

      const previewSources = resolvePreviewSources(src);

      function loadPreviewSource(index) {
        if (index < 0 || index >= previewSources.length) {
          clearPreviewSurface();
          markStopped();
          return;
        }

        currentSourceIndex = index;
        clearPreviewSurface();
        const nextSource = previewSources[index];
        if (isYouTubeSource(nextSource)) {
          createYouTubePlayer(nextSource, () => loadPreviewSource(index + 1));
          return;
        }
        loadPreviewSource(index + 1);
      }

      if (previewSources.length > 0) {
        loadPreviewSource(0);
      }
    </script>
  </body>
</html>
''';
