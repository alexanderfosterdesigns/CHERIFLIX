part of 'player_screen.dart';

const String _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 Edg/133.0.0.0';

const Set<String> _trustedPlaybackHostSuffixes = <String>{
  'vidking.net',
  'vidapi.ru',
  'vaplayer.ru',
  'vidnest.fun',
  'vidapi.xyz',
  'vidsrc.xyz',
  '111movies.com',
  'vixsrc.to',
  'autoembed.cc',
  'vidsrc.cc',
  'vidsrc.to',
  'embed.su',
  'vsembed.ru',
  'vsrc.su',
  'vidsrc.me',
  'vidlink.pro',
  'vidsrc-embed.ru',
  'vidembed.cc',
  'vidzee.wtf',
  'maplestage.com',
  'primewire.tf',
  'multiembed.mov',
  'autoembed.co',
};

String _buildSiteHardeningBootstrapScript(
  Set<String> allowedHostSuffixes,
  String loadToken,
  List<CaptionTrack> captionTracks,
  String? selectedCaptionTrackId,
) {
  final allowedHostsJson = jsonEncode(
    allowedHostSuffixes.map((host) => host.toLowerCase()).toList()..sort(),
  );
  final loadTokenJson = jsonEncode(loadToken);
  final captionTracksJson =
      jsonEncode(captionTracks.map((track) => track.toJson()).toList());
  final selectedCaptionTrackIdJson = jsonEncode(selectedCaptionTrackId);

  return '''
(() => {
  const allowedHosts = $allowedHostsJson;
  const loadToken = $loadTokenJson;
  const captionTracks = $captionTracksJson;
  const selectedCaptionTrackId = $selectedCaptionTrackIdJson;
  window.__cheriflixPlayerLoadToken = loadToken;
  window.__cheriflixCaptionConfig = {
    tracks: captionTracks,
    selectedTrackId: selectedCaptionTrackId,
  };
  const styleId = '__cheriflix_site_lock_style__';
  const selectorList = [
    '.popup',
    '.popunder',
    '.overlay-ad',
    '.adsbox',
    '.ad-container',
    '.banner-ad',
    '.social-bar',
    '[id*="ad-"]',
    '[id^="ad_"]',
    '[class*=" ad-"]',
    '[class^="ad-"]',
    '[class*="ads"]',
    '[aria-label*="advert"]',
    '[aria-label*="sponsor"]',
    '[contenteditable="true"]',
    '[contenteditable="plaintext-only"]'
  ];
  const suspiciousTextPattern =
      /(start blocking ads|start blocking ads now|remove all ads|remove ads|say goodbye to online ads|block banners, pop-ups & more|disable ad blocker|disable adblock|turn off adblock|adblock|ads?|download|install|extension|allow notifications|subscribe)/i;
  const closeTextPattern = /^(x|\\u00d7|close|dismiss)\$/i;
  const blockedScriptPattern =
      /(acscdn\\.com|aclib|doubleclick|googlesyndication|adservice|adsterra|popunder|fuseplatform)/i;

  const normalizeHost = (value) => String(value || '').trim().toLowerCase();
  const normalizeText = (value) =>
      String(value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
  const postFrameMessage = (payload) => {
    try {
      if (!window.flutter_inappwebview ||
          typeof window.flutter_inappwebview.callHandler !== 'function') {
        return;
      }

      window.flutter_inappwebview.callHandler('cheriflixPlayerMessage', {
        channel: 'cheriflix-frame',
        token: loadToken,
        isTopFrame: window.top === window,
        host: normalizeHost(window.location && window.location.hostname),
        ...payload,
      });
    } catch (_) {}
  };
  const isAllowedHost = (host) => {
    const normalizedHost = normalizeHost(host);
    if (!normalizedHost || allowedHosts.length === 0) {
      return true;
    }

    return allowedHosts.some((allowedHost) =>
      normalizedHost === allowedHost || normalizedHost.endsWith('.' + allowedHost));
  };

  const toUrl = (rawValue) => {
    if (!rawValue) {
      return null;
    }

    try {
      return new URL(String(rawValue), window.location.href);
    } catch (_) {
      return null;
    }
  };

  const isBlockedTopLevelUrl = (rawValue) => {
    const url = toUrl(rawValue);
    if (!url) {
      return false;
    }

    const protocol = String(url.protocol || '').toLowerCase();
    if (protocol === 'about:' ||
        protocol === 'blob:' ||
        protocol === 'data:' ||
        protocol === 'javascript:') {
      return false;
    }

    if (protocol !== 'http:' && protocol !== 'https:') {
      return true;
    }

    return !isAllowedHost(url.hostname);
  };

  const getRect = (element) => {
    try {
      return element.getBoundingClientRect();
    } catch (_) {
      return null;
    }
  };

  const isFixedLike = (element) => {
    if (!(element instanceof HTMLElement)) {
      return false;
    }

    const style = window.getComputedStyle(element);
    const zIndex = Number.parseInt(style.zIndex || '0', 10);
    return style.position === 'fixed' ||
        style.position === 'sticky' ||
        (style.position === 'absolute' && zIndex >= 50);
  };

  const isFloatingPanelShape = (rect) => {
    if (!rect) {
      return false;
    }

    const nearTopRight =
        rect.top <= window.innerHeight * 0.48 &&
        rect.left >= window.innerWidth * 0.48;
    const pillSized =
        rect.width >= 120 &&
        rect.width <= Math.max(460, window.innerWidth * 0.45) &&
        rect.height >= 40 &&
        rect.height <= window.innerHeight * 0.28;
    return nearTopRight && pillSized;
  };

  const isSmallTopRightWidget = (element) => {
    if (!(element instanceof HTMLElement) || !isFixedLike(element)) {
      return false;
    }

    const rect = getRect(element);
    if (!rect) {
      return false;
    }

    const nearTopRight =
        rect.top <= window.innerHeight * 0.48 &&
        rect.left >= window.innerWidth * 0.55;
    const smallWidget = rect.width >= 20 &&
        rect.width <= 140 &&
        rect.height >= 20 &&
        rect.height <= 140;
    return nearTopRight && smallWidget;
  };

  const findFloatingContainer = (element) => {
    let current = element;
    let best = element instanceof HTMLElement ? element : null;
    for (let depth = 0; depth < 6 && current && current !== document.body; depth += 1) {
      if (current instanceof HTMLElement && isFixedLike(current)) {
        best = current;
      }
      current = current.parentElement;
    }
    return best;
  };

  const installAdLibraryStubs = () => {
    const noop = () => {};
    const aclibFacade = Object.freeze({
      runInPagePush: noop,
      runPop: noop,
      runBanner: noop,
      runAutoTag: noop,
      runInterstitial: noop
    });

    try {
      Object.defineProperty(window, 'aclib', {
        configurable: false,
        enumerable: false,
        get: () => aclibFacade,
        set: () => true
      });
    } catch (_) {
      try {
        window.aclib = aclibFacade;
      } catch (_) {}
    }
  };

  const installStyle = () => {
    const root = document.head || document.documentElement || document.body;
    if (!root || document.getElementById(styleId)) {
      return;
    }

    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = selectorList
      .map((selector) => selector + '{display:none !important;visibility:hidden !important;pointer-events:none !important;}')
      .join('\\n');
    root.appendChild(style);
  };

  const stripBlockedScripts = () => {
    document.querySelectorAll('script[src]').forEach((node) => {
      const src = node.getAttribute('src') || node.src || '';
      if (blockedScriptPattern.test(String(src).toLowerCase())) {
        node.remove();
      }
    });
  };

  const hasSuspiciousAction = (element) => {
    const candidates = element.querySelectorAll('a[href],button');
    return Array.from(candidates).some((node) => {
      const href = node.getAttribute && node.getAttribute('href');
      const text = String(node.innerText || node.textContent || '').trim();
      return (href && isBlockedTopLevelUrl(href)) ||
          suspiciousTextPattern.test(text) ||
          (node.hasAttribute && node.hasAttribute('download'));
    });
  };

  const shouldRemoveOverlay = (element) => {
    if (!(element instanceof HTMLElement)) {
      return false;
    }

    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    const text = String(element.innerText || element.textContent || '')
        .trim()
        .slice(0, 600);
    const zIndex = Number.parseInt(style.zIndex || '0', 10);
    const coversLargeArea =
        rect.width >= window.innerWidth * 0.25 &&
        rect.height >= window.innerHeight * 0.18;
    const anchoredOnTop =
        style.position === 'fixed' ||
        style.position === 'sticky' ||
        (style.position === 'absolute' && zIndex >= 1000);

    return anchoredOnTop &&
        coversLargeArea &&
        (suspiciousTextPattern.test(text) || hasSuspiciousAction(element));
  };

  const stripSuspiciousFloatingWidgets = () => {
    const suspiciousRects = [];

    document.querySelectorAll('body *').forEach((node) => {
      if (!(node instanceof HTMLElement) || !isFixedLike(node)) {
        return;
      }

      const text = normalizeText(node.innerText || node.textContent || '');
      const rect = getRect(node);
      if (!text || !rect || !isFloatingPanelShape(rect)) {
        return;
      }

      if (!suspiciousTextPattern.test(text)) {
        return;
      }

      const container = findFloatingContainer(node);
      const containerRect = getRect(container);
      if (container && containerRect) {
        suspiciousRects.push(containerRect);
        container.remove();
      }
    });

    if (suspiciousRects.length === 0) {
      return;
    }

    document.querySelectorAll('body *').forEach((node) => {
      if (!(node instanceof HTMLElement) || !isSmallTopRightWidget(node)) {
        return;
      }

      const rect = getRect(node);
      if (!rect) {
        return;
      }

      const text = normalizeText(node.innerText || node.textContent || '');
      const hasGraphicChild = node.querySelector('svg,img,canvas,path') != null;
      const nearSuspiciousPanel = suspiciousRects.some((panelRect) => {
        return rect.top <= panelRect.bottom + 80 &&
            rect.bottom >= panelRect.top - 40 &&
            rect.left >= panelRect.left - 120;
      });

      if (!nearSuspiciousPanel) {
        return;
      }

      if (closeTextPattern.test(text) ||
          text === '!' ||
          text === 'i' ||
          text == 'â†“' ||
          hasGraphicChild) {
        const container = findFloatingContainer(node);
        if (container) {
          container.remove();
        } else {
          node.remove();
        }
      }
    });
  };

  const hasPlayableSurface = () =>
      document.querySelector(
        'video, iframe, [id*="player"], [class*="player"], [class*="jw"], [class*="vjs"], [class*="plyr"], [data-player], .jw-display-icon-container, .jw-icon-display, .vjs-big-play-button, .plyr__control--overlaid, .shaka-play-button, .shaka-play-button-container button'
      ) != null;

  const fatalGracePeriodMs = 30000;
  const protectionStartedAt = Date.now();

  const hasSuspiciousOverlay = () => {
    for (const node of document.querySelectorAll('body *')) {
      if (!(node instanceof HTMLElement)) {
        continue;
      }

      const text = normalizeText(node.innerText || node.textContent || '');
      if (!text) {
        continue;
      }

      if (shouldRemoveOverlay(node)) {
        return true;
      }

      const rect = getRect(node);
      if (rect && isFloatingPanelShape(rect) && suspiciousTextPattern.test(text)) {
        return true;
      }
    }

    return false;
  };

  const reportFatalState = () => {
    if (window.top !== window) {
      return;
    }

    if (Date.now() - protectionStartedAt < fatalGracePeriodMs) {
      return;
    }

    if (hasPlayableSurface()) {
      return;
    }

    const title = normalizeText(document.title || '');
    const text = normalizeText(
      document.body ? document.body.innerText || document.body.textContent || '' : ''
    ).slice(0, 1000);
    const combined = (title + ' ' + text).trim();
    let reason = '';

    if (/(404[^a-z0-9]{0,6}page not found|page not found|return to the home page|go to home)/i.test(combined)) {
      reason = 'This source returned a 404 page instead of the video.';
    } else if (/(application error|client-side exception has occurred|a client-side exception has occurred)/i.test(combined)) {
      reason = 'This source crashed before the player loaded.';
    } else if (/(please disable sandbox|disable sandbox|sandbox must be disabled)/i.test(combined)) {
      reason = 'This source refused the protected player shell.';
    } else if (/(video|media|file|content)\\s+(?:is\\s+)?not\\s+found|video not found|media not found|file not found|content not found/i.test(combined)) {
      reason = 'This source says the video is unavailable.';
    }

    if (!reason) {
      return;
    }

    const signature = [reason, title, text.slice(0, 160)].join('|');
    if (window.__cheriflixLastFatalSignature === signature) {
      return;
    }

    window.__cheriflixLastFatalSignature = signature;
    postFrameMessage({
      type: 'frame-health',
      fatal: true,
      reason,
      title: document.title || '',
      sample: text.slice(0, 220)
    });
  };

  const stripDownloadsAndEditors = () => {
    document.querySelectorAll('a[download]').forEach((node) => {
      node.removeAttribute('download');
    });
    document.querySelectorAll('input[type="file"]').forEach((node) => {
      node.setAttribute('disabled', 'disabled');
      node.setAttribute('tabindex', '-1');
      node.style.display = 'none';
    });
    document
        .querySelectorAll('[contenteditable="true"],[contenteditable="plaintext-only"]')
        .forEach((node) => node.setAttribute('contenteditable', 'false'));
    try {
      document.designMode = 'off';
    } catch (_) {}
  };

  const sanitizeAnchors = () => {
    document.querySelectorAll('a[href], area[href]').forEach((node) => {
      const href = node.getAttribute('href') || node.href || '';
      const rel = String(node.getAttribute('rel') || '').toLowerCase();
      const target = String(node.getAttribute('target') || '').toLowerCase();
      const opensNewWindow =
          target === '_blank' ||
          rel.includes('noopener') ||
          rel.includes('noreferrer') ||
          rel.includes('external');

      if (node.hasAttribute('download') ||
          opensNewWindow ||
          isBlockedTopLevelUrl(href)) {
        node.removeAttribute('download');
      }

      node.removeAttribute('target');
      if (opensNewWindow || isBlockedTopLevelUrl(href)) {
        node.setAttribute('rel', 'nofollow noopener noreferrer');
      }
    });
  };

  const normalizeIframePermissions = () => {
    document.querySelectorAll('iframe').forEach((node) => {
      if (!(node instanceof HTMLIFrameElement)) {
        return;
      }

      try {
        const allowTokens = new Set(
          String(node.getAttribute('allow') || '')
              .split(';')
              .map((token) => token.trim())
              .filter(Boolean)
        );
        allowTokens.add('autoplay');
        allowTokens.add('fullscreen');
        allowTokens.add('encrypted-media');
        allowTokens.add('picture-in-picture');
        node.setAttribute('allow', Array.from(allowTokens).join('; '));
        node.setAttribute('allowfullscreen', '');
      } catch (_) {}
    });
  };

  const stripSuspiciousOverlays = () => {
    selectorList.forEach((selector) => {
      document.querySelectorAll(selector).forEach((node) => {
        if (!node || !(node instanceof HTMLElement)) {
          node.remove();
          return;
        }

        if (shouldRemoveOverlay(node) || node.matches(selector)) {
          node.remove();
        }
      });
    });

    document.querySelectorAll('body *').forEach((node) => {
      if (node instanceof HTMLElement && shouldRemoveOverlay(node)) {
        node.remove();
      }
    });
  };

  const blockInteraction = (event) => {
    const target = event.target && event.target.closest
        ? event.target.closest('a[href],area[href],input[type="file"],[contenteditable="true"],[contenteditable="plaintext-only"]')
        : null;
    if (!target) {
      return;
    }

    const urlValue =
        target.getAttribute('href') ||
        target.getAttribute('src') ||
        target.getAttribute('data') ||
        '';
    const shouldBlock =
        target.matches('input[type="file"],[contenteditable="true"],[contenteditable="plaintext-only"]') ||
        target.hasAttribute('download') ||
        (urlValue && isBlockedTopLevelUrl(urlValue));

    if (!shouldBlock) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  };

  const installNavigationGuards = () => {
    const blockError = () => new Error('Blocked by CHERIFLIX site lock');

    const createBlockedPopupWindow = () => {
      const popupLocation = {
        href: 'about:blank',
        assign: () => {},
        replace: () => {},
        reload: () => {},
        toString: () => 'about:blank',
      };
      const popupDocument = {
        body: {
          innerHTML: '',
          appendChild: () => {},
          removeChild: () => {},
        },
        documentElement: null,
        open: () => popupDocument,
        close: () => {},
        write: () => {},
        writeln: () => {},
      };
      const popupWindow = {
        closed: false,
        name: '',
        opener: window,
        parent: window,
        top: window,
        self: null,
        frames: null,
        length: 0,
        location: popupLocation,
        document: popupDocument,
        close() {
          this.closed = true;
        },
        focus: () => {},
        blur: () => {},
        postMessage: () => {},
        moveTo: () => {},
        moveBy: () => {},
        resizeTo: () => {},
        resizeBy: () => {},
        addEventListener: () => {},
        removeEventListener: () => {},
        dispatchEvent: () => false,
      };
      popupWindow.self = popupWindow;
      popupWindow.frames = popupWindow;
      return popupWindow;
    };

    try {
      window.open = () => createBlockedPopupWindow();
      window.alert = () => {};
      window.confirm = () => false;
      window.prompt = () => null;
      window.print = () => {};
    } catch (_) {}

    try {
      Object.defineProperty(window, 'onbeforeunload', {
        configurable: true,
        enumerable: false,
        get: () => null,
        set: () => true,
      });
    } catch (_) {
      try {
        window.onbeforeunload = null;
      } catch (_) {}
    }

    try {
      const originalAddEventListener = window.addEventListener.bind(window);
      window.addEventListener = function(type, listener, options) {
        if (String(type || '').toLowerCase() === 'beforeunload') {
          return;
        }
        return originalAddEventListener(type, listener, options);
      };
    } catch (_) {}

    try {
      if (window.Notification && typeof window.Notification.requestPermission === 'function') {
        window.Notification.requestPermission = async () => 'denied';
      }
    } catch (_) {}

    try {
      window.showOpenFilePicker = async () => { throw blockError(); };
      window.showSaveFilePicker = async () => { throw blockError(); };
      window.showDirectoryPicker = async () => { throw blockError(); };
    } catch (_) {}

    try {
      const originalFormSubmit = HTMLFormElement.prototype.submit;
      HTMLFormElement.prototype.submit = function() {
        const action = this.getAttribute('action') || window.location.href;
        if (isBlockedTopLevelUrl(action)) {
          return;
        }
        return originalFormSubmit.apply(this, arguments);
      };
    } catch (_) {}

    try {
      const originalAnchorClick = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function() {
        const href = this.getAttribute('href') || this.href || '';
        const blocked =
            this.hasAttribute('download') ||
            isBlockedTopLevelUrl(href);
        if (blocked) {
          return;
        }
        return originalAnchorClick.apply(this, arguments);
      };
    } catch (_) {}

    try {
      const originalInputClick = HTMLInputElement.prototype.click;
      HTMLInputElement.prototype.click = function() {
        if (String(this.type || '').toLowerCase() === 'file') {
          return;
        }
        return originalInputClick.apply(this, arguments);
      };
    } catch (_) {}
  };

  const scrub = () => {
    installAdLibraryStubs();
    installStyle();
    stripDownloadsAndEditors();
    sanitizeAnchors();
    normalizeIframePermissions();
    stripSuspiciousOverlays();
    stripSuspiciousFloatingWidgets();
    reportFatalState();
  };

  let scrubQueued = false;
  const scheduleScrub = () => {
    if (scrubQueued) {
      return;
    }
    scrubQueued = true;
    window.setTimeout(() => {
      scrubQueued = false;
      scrub();
    }, 0);
  };

  installAdLibraryStubs();
  installNavigationGuards();
  document.addEventListener('click', blockInteraction, true);
  document.addEventListener('auxclick', blockInteraction, true);
  document.addEventListener('submit', (event) => {
    const form = event.target instanceof HTMLFormElement ? event.target : null;
    if (!form) {
      return;
    }

    const action = form.getAttribute('action') || window.location.href;
    if (!isBlockedTopLevelUrl(action)) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }, true);
  document.addEventListener('dragenter', (event) => event.preventDefault(), true);
  document.addEventListener('dragover', (event) => event.preventDefault(), true);
  document.addEventListener('drop', (event) => {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }, true);
  const observer = new MutationObserver(() => scheduleScrub());
  const observeRoot = () => {
    const root = document.documentElement || document.body;
    if (root) {
      observer.observe(root, { childList: true, subtree: true });
    }
  };

  window.__cheriflixProtector = { scrub };
  scrub();
  let intervalTicks = 0;
  const scrubInterval = window.setInterval(() => {
    scrub();
    intervalTicks += 1;
    if (intervalTicks >= 40) {
      window.clearInterval(scrubInterval);
    }
  }, 1500);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      scrub();
      observeRoot();
    }, { once: true });
  } else {
    observeRoot();
  }
})();
$_playerBridgeInstallScript''';
}

const String _playerBridgeInstallScript = r'''
(() => {
  const frameId = window.__cheriflixFrameId ||
      `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  window.__cheriflixFrameId = frameId;
  const playerState = {
    zoomScale: 1,
    defaultVolume: 1.0,
    defaultAudioRestored: false,
    userVolumeAdjusted: false,
    qualityOptions: ['Auto'],
    selectedQualityLabel: 'Auto',
    hlsQualityIndex: -1,
    pendingSeekSeconds: null,
    autoplayRequested: true,
    userPausedPlayback: false,
    selectedCaptionTrackId:
        window.__cheriflixCaptionConfig &&
            window.__cheriflixCaptionConfig.selectedTrackId
        ? window.__cheriflixCaptionConfig.selectedTrackId
        : null,
    detectedSource: null,
  };

  const postMessage = (payload) => {
    try {
      if (!window.flutter_inappwebview ||
          typeof window.flutter_inappwebview.callHandler !== 'function') {
        return;
      }

      window.flutter_inappwebview.callHandler('cheriflixPlayerMessage', {
        channel: 'cheriflix-player',
        token: String(window.__cheriflixPlayerLoadToken || ''),
        type: 'state',
        frameId,
        sourceUrl: String(window.location && window.location.href || ''),
        ...payload,
      });
    } catch (_) {}
  };

  const toAbsoluteHttpUrl = (rawValue) => {
    if (!rawValue) {
      return null;
    }

    try {
      const resolved = new URL(String(rawValue), window.location.href);
      const protocol = String(resolved.protocol || '').toLowerCase();
      if (protocol !== 'http:' && protocol !== 'https:') {
        return null;
      }
      return resolved.toString();
    } catch (_) {
      return null;
    }
  };

  const normalizeHeaderMap = (value) => {
    if (!value) {
      return {};
    }

    try {
      if (typeof Headers !== 'undefined' && value instanceof Headers) {
        const normalized = {};
        value.forEach((headerValue, headerName) => {
          normalized[String(headerName)] = String(headerValue);
        });
        return normalized;
      }
    } catch (_) {}

    if (Array.isArray(value)) {
      const normalized = {};
      value.forEach((entry) => {
        if (!Array.isArray(entry) || entry.length < 2) {
          return;
        }
        normalized[String(entry[0])] = String(entry[1]);
      });
      return normalized;
    }

    if (typeof value === 'object') {
      const normalized = {};
      Object.entries(value).forEach(([headerName, headerValue]) => {
        normalized[String(headerName)] = String(headerValue);
      });
      return normalized;
    }

    return {};
  };

  const inferDirectSourceKind = (rawUrl, contentType = '') => {
    const resolved = toAbsoluteHttpUrl(rawUrl);
    if (!resolved) {
      return null;
    }

    const parsed = new URL(resolved);
    const path = String(parsed.pathname || '').toLowerCase();
    const search = String(parsed.search || '').toLowerCase();
    const normalizedContentType = String(contentType || '').toLowerCase();

    if (path.endsWith('.m3u8') ||
        search.includes('.m3u8') ||
        normalizedContentType.includes('application/vnd.apple.mpegurl') ||
        normalizedContentType.includes('application/x-mpegurl')) {
      return 'hls';
    }

    if (path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.m4v') ||
        path.endsWith('.webm') ||
        path.endsWith('.mov') ||
        normalizedContentType.startsWith('video/') ||
        normalizedContentType.includes('matroska')) {
      return 'file';
    }

    return null;
  };

  const parseProxyHeaders = (resolvedUrl) => {
    try {
      const parsed = new URL(String(resolvedUrl));
      const rawHeaders = parsed.searchParams.get('headers');
      if (!rawHeaders) {
        return {};
      }

      try {
        return normalizeHeaderMap(JSON.parse(rawHeaders));
      } catch (_) {
        return normalizeHeaderMap(JSON.parse(decodeURIComponent(rawHeaders)));
      }
    } catch (_) {
      return {};
    }
  };

  const currentPageHeaders = () => {
    const headers = {};
    const pageUrl = String(window.location && window.location.href || '').trim();
    const origin = String(window.location && window.location.origin || '').trim();
    if (pageUrl) {
      headers.Referer = pageUrl;
    }
    if (/^https?:/i.test(origin)) {
      headers.Origin = origin;
    }
    return headers;
  };

  const captureDirectSource = (
    rawUrl,
    {
      headers = null,
      pageUrl = null,
      contentType = '',
      sourceKind = null,
      confidence = 1,
    } = {}
  ) => {
    const resolvedUrl = toAbsoluteHttpUrl(rawUrl);
    if (!resolvedUrl) {
      return false;
    }

    const parsed = new URL(resolvedUrl);
    const path = String(parsed.pathname || '').toLowerCase();
    if (path.endsWith('.ts') ||
        path.endsWith('.m4s') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif') ||
        path.endsWith('.svg') ||
        path.endsWith('.css') ||
        path.endsWith('.js') ||
        path.endsWith('.ico') ||
        path.endsWith('.html') ||
        path.endsWith('.htm')) {
      return false;
    }

    const normalizedSourceKind =
        sourceKind || inferDirectSourceKind(resolvedUrl, contentType);
    if (normalizedSourceKind !== 'hls' && normalizedSourceKind !== 'file') {
      return false;
    }

    const mergedHeaders = {
      ...currentPageHeaders(),
      ...parseProxyHeaders(resolvedUrl),
      ...normalizeHeaderMap(headers),
    };
    const normalizedPageUrl =
        toAbsoluteHttpUrl(pageUrl) || String(window.location && window.location.href || '');
    const current = playerState.detectedSource;
    if (current &&
        current.url === resolvedUrl &&
        current.sourceKind === normalizedSourceKind &&
        current.confidence >= confidence) {
      return false;
    }

    if (current &&
        current.url !== resolvedUrl &&
        current.confidence > confidence) {
      return false;
    }

    playerState.detectedSource = {
      url: resolvedUrl,
      sourceKind: normalizedSourceKind,
      headers: mergedHeaders,
      pageUrl: normalizedPageUrl,
      confidence,
    };
    return true;
  };

  const getVideo = () => {
    const videos = getVideos();
    if (videos.length === 0) {
      return null;
    }

    return videos.sort((left, right) => {
      const leftArea = (left.videoWidth || left.clientWidth || 0) *
          (left.videoHeight || left.clientHeight || 0);
      const rightArea = (right.videoWidth || right.clientWidth || 0) *
          (right.videoHeight || right.clientHeight || 0);
      return rightArea - leftArea;
    })[0];
  };

  const getVideos = () => collectElementsAcrossOpenShadowRoots('video');

  const collectElementsAcrossOpenShadowRoots = (selector) => {
    const results = [];
    const seenNodes = new Set();
    const seenRoots = new Set();
    const queue = [document];

    while (queue.length > 0) {
      const root = queue.shift();
      if (!root || seenRoots.has(root)) {
        continue;
      }

      seenRoots.add(root);

      let matches = [];
      try {
        matches = Array.from(root.querySelectorAll(selector));
      } catch (_) {
        matches = [];
      }

      for (const match of matches) {
        if (!match || seenNodes.has(match)) {
          continue;
        }
        seenNodes.add(match);
        results.push(match);
      }

      let descendants = [];
      try {
        descendants = Array.from(root.querySelectorAll('*'));
      } catch (_) {
        descendants = [];
      }

      for (const descendant of descendants) {
        if (!(descendant instanceof HTMLElement) || !descendant.shadowRoot) {
          continue;
        }

        queue.push(descendant.shadowRoot);
      }
    }

    return results;
  };

  const isVisibleElement = (element) => {
    if (!(element instanceof HTMLElement)) {
      return false;
    }

    const rect = element.getBoundingClientRect();
    if (rect.width < 28 || rect.height < 28) {
      return false;
    }

    const style = window.getComputedStyle(element);
    if (style.display === 'none' ||
        style.visibility === 'hidden' ||
        Number(style.opacity || '1') <= 0.02) {
      return false;
    }

    return rect.bottom > 0 &&
        rect.right > 0 &&
        rect.top < window.innerHeight &&
        rect.left < window.innerWidth;
  };

  const isLikelyPlayActivator = (element) => {
    if (!(element instanceof HTMLElement) || !isVisibleElement(element)) {
      return false;
    }

    if (element.hasAttribute('disabled') ||
        element.getAttribute('aria-disabled') === 'true') {
      return false;
    }

    const descriptor = [
      element.getAttribute('aria-label') || '',
      element.getAttribute('title') || '',
      element.id || '',
      element.className || '',
      element.innerText || element.textContent || ''
    ].join(' ').replace(/\s+/g, ' ').trim().toLowerCase();

    const matchesExplicitSelector = element.matches(
      '.jw-display-icon-container,.jw-icon-display,.vjs-big-play-button,.plyr__control--overlaid,.shaka-play-button,.shaka-play-button-container button,[aria-label*="play"],[title*="play"]'
    );
    const hasPlayIntent =
        /\b(play|watch|resume|start|continue)\b/i.test(descriptor) ||
        /\bplay\b/i.test(descriptor.replace(/[_-]+/g, ' '));
    const hasNegativeIntent =
        /\b(trailer|download|install|advert|adblock|subscribe|close|dismiss|cancel|next|previous)\b/i
            .test(descriptor);
    if ((!matchesExplicitSelector && !hasPlayIntent) || hasNegativeIntent) {
      return false;
    }

    if (element instanceof HTMLAnchorElement) {
      const href = element.getAttribute('href') || element.href || '';
      if (href && !/^#/.test(href) && /^https?:/i.test(href)) {
        return false;
      }
    }

    return true;
  };

  const findPlayActivator = () => {
    const rawCandidates = collectElementsAcrossOpenShadowRoots(
      'button,[role="button"],[aria-label],[title],[class*="play"],[class*="Play"],[id*="play"],[id*="Play"],.jw-display-icon-container,.jw-icon-display,.vjs-big-play-button,.plyr__control--overlaid,.shaka-play-button,.shaka-play-button-container button'
    );
    const candidates = Array.from(new Set(Array.from(rawCandidates)))
        .filter(isLikelyPlayActivator);

    if (candidates.length === 0) {
      return null;
    }

    const viewportCenterX = window.innerWidth / 2;
    const viewportCenterY = window.innerHeight / 2;
    candidates.sort((left, right) => {
      const leftRect = left.getBoundingClientRect();
      const rightRect = right.getBoundingClientRect();
      const leftCenterDistance = Math.hypot(
        leftRect.left + leftRect.width / 2 - viewportCenterX,
        leftRect.top + leftRect.height / 2 - viewportCenterY
      );
      const rightCenterDistance = Math.hypot(
        rightRect.left + rightRect.width / 2 - viewportCenterX,
        rightRect.top + rightRect.height / 2 - viewportCenterY
      );
      if (Math.abs(leftCenterDistance - rightCenterDistance) > 1) {
        return leftCenterDistance - rightCenterDistance;
      }
      return (rightRect.width * rightRect.height) -
          (leftRect.width * leftRect.height);
    });

    return candidates[0];
  };

  const findCenterPlayActivator = () => {
    const centerPoints = [
      [window.innerWidth / 2, window.innerHeight / 2],
      [window.innerWidth / 2, Math.max(0, window.innerHeight / 2 - 16)],
      [window.innerWidth / 2, Math.min(window.innerHeight - 1, window.innerHeight / 2 + 16)],
      [Math.max(0, window.innerWidth / 2 - 16), window.innerHeight / 2],
      [Math.min(window.innerWidth - 1, window.innerWidth / 2 + 16), window.innerHeight / 2],
    ];
    const selector =
        'button,[role="button"],a,video,.jw-display-icon-container,.jw-icon-display,.vjs-big-play-button,.plyr__control--overlaid,.shaka-play-button,.shaka-play-button-container button';

    for (const [x, y] of centerPoints) {
      let hit = null;
      try {
        hit = document.elementFromPoint(x, y);
      } catch (_) {
        hit = null;
      }

      if (!(hit instanceof HTMLElement)) {
        continue;
      }

      const activator = hit.closest(selector) || hit;
      if (activator instanceof HTMLElement && isVisibleElement(activator)) {
        return activator;
      }
    }

    return null;
  };

  const tryInvokePlay = (player) => {
    if (!player || typeof player.play !== 'function') {
      return false;
    }

    try {
      const result = player.play();
      if (result && typeof result.catch === 'function') {
        result.catch(() => {});
      }
      return true;
    } catch (_) {
      return false;
    }
  };

  const playKnownPlayerLibraries = () => {
    let played = false;

    try {
      if (typeof window.jwplayer === 'function') {
        const jwCandidates = [];
        try {
          if (window.jwplayer.players && typeof window.jwplayer.players === 'object') {
            jwCandidates.push(...Object.keys(window.jwplayer.players));
          }
        } catch (_) {}
        try {
          const hintedIds = Array.from(
            collectElementsAcrossOpenShadowRoots('[id]')
          )
              .map((element) => element.id || '')
              .filter((id) => /jw|player/i.test(id));
          jwCandidates.push(...hintedIds);
        } catch (_) {}
        try {
          const defaultPlayer = window.jwplayer();
          played = tryInvokePlay(defaultPlayer) || played;
        } catch (_) {}
        for (const candidateId of Array.from(new Set(jwCandidates))) {
          try {
            const player = window.jwplayer(candidateId);
            played = tryInvokePlay(player) || played;
          } catch (_) {}
        }
      }
    } catch (_) {}

    try {
      if (typeof window.videojs === 'function') {
        const players = [];
        try {
          if (typeof window.videojs.getPlayers === 'function') {
            const allPlayers = window.videojs.getPlayers();
            players.push(...Object.values(allPlayers || {}));
          }
        } catch (_) {}
        try {
          if (typeof window.videojs.getAllPlayers === 'function') {
            players.push(...window.videojs.getAllPlayers());
          }
        } catch (_) {}
        try {
          const hintedIds = Array.from(
            collectElementsAcrossOpenShadowRoots('[id]')
          )
              .map((element) => element.id || '')
              .filter((id) => /videojs|player|vjs/i.test(id));
          for (const candidateId of hintedIds) {
            try {
              players.push(window.videojs(candidateId));
            } catch (_) {}
          }
        } catch (_) {}
        for (const player of players) {
          played = tryInvokePlay(player) || played;
        }
      }
    } catch (_) {}

    try {
      const elements = collectElementsAcrossOpenShadowRoots(
        '.plyr,.video-js,.jwplayer,.jw-wrapper,[data-player],[data-plyr],[id*="player"],[class*="player"]'
      );
      for (const element of elements) {
        if (!(element instanceof HTMLElement)) {
          continue;
        }

        const candidates = [
          element.plyr,
          element.player,
          element.jwplayer,
          element.videojs,
          element._player,
          element.__player,
        ];
        for (const candidate of candidates) {
          played = tryInvokePlay(candidate) || played;
        }
      }
    } catch (_) {}

    return played;
  };

  const clickPlayActivator = () => {
    const activator = findPlayActivator() || findCenterPlayActivator();
    if (!activator) {
      return false;
    }

    try {
      activator.focus({ preventScroll: true });
    } catch (_) {}

    const eventTypes = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'];
    for (const eventType of eventTypes) {
      try {
        if (eventType.startsWith('pointer') && typeof PointerEvent === 'function') {
          activator.dispatchEvent(new PointerEvent(eventType, {
            bubbles: true,
            cancelable: true,
            composed: true,
            view: window,
            pointerId: 1,
            pointerType: 'mouse',
            isPrimary: true,
            buttons: 1,
          }));
        } else {
          activator.dispatchEvent(new MouseEvent(eventType, {
            bubbles: true,
            cancelable: true,
            composed: true,
            view: window,
            buttons: 1,
          }));
        }
      } catch (_) {}
    }

    try {
      if (typeof activator.click === 'function') {
        activator.click();
      }
    } catch (_) {}

    try {
      activator.dispatchEvent(new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        composed: true,
        key: 'Enter',
      }));
      activator.dispatchEvent(new KeyboardEvent('keyup', {
        bubbles: true,
        cancelable: true,
        composed: true,
        key: 'Enter',
      }));
      activator.dispatchEvent(new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        composed: true,
        key: ' ',
      }));
      activator.dispatchEvent(new KeyboardEvent('keyup', {
        bubbles: true,
        cancelable: true,
        composed: true,
        key: ' ',
      }));
    } catch (_) {}

    return true;
  };

  const getHlsInstance = () => {
    try {
      if (window.hls &&
          Array.isArray(window.hls.levels) &&
          typeof window.hls.currentLevel === 'number') {
        return window.hls;
      }
    } catch (_) {}
    return null;
  };

  const captureVideoSource = (video) => {
    if (!video) {
      return;
    }

    captureDirectSource(video.currentSrc || video.src, {
      confidence: 3,
    });
    Array.from(video.querySelectorAll('source[src]')).forEach((element) => {
      captureDirectSource(element.getAttribute('src') || element.src, {
        confidence: 3,
      });
    });

    const hls = getHlsInstance();
    if (hls) {
      captureDirectSource(hls.url || hls._url || hls.src, {
        sourceKind: 'hls',
        confidence: 3,
      });
    }
  };

  const installHlsHook = () => {
    try {
      if (typeof window.Hls !== 'function' ||
          !window.Hls.prototype ||
          window.Hls.prototype.__cheriflixPatched) {
        return;
      }

      const originalLoadSource = window.Hls.prototype.loadSource;
      if (typeof originalLoadSource !== 'function') {
        return;
      }

      window.Hls.prototype.loadSource = function(...args) {
        if (args.length > 0) {
          captureDirectSource(args[0], {
            sourceKind: 'hls',
            confidence: 3,
          });
        }
        return originalLoadSource.apply(this, args);
      };
      window.Hls.prototype.__cheriflixPatched = true;
    } catch (_) {}
  };

  const installNetworkHooks = () => {
    try {
      if (window.__cheriflixNetworkHooksInstalled) {
        return;
      }
      window.__cheriflixNetworkHooksInstalled = true;

      if (typeof window.fetch === 'function') {
        const originalFetch = window.fetch.bind(window);
        window.fetch = function(...args) {
          const input = args[0];
          const init = args[1];
          const requestUrl =
              typeof input === 'string' || input instanceof URL
              ? String(input)
              : input && input.url
              ? String(input.url)
              : '';
          const requestHeaders = normalizeHeaderMap(
            init && init.headers ? init.headers : input && input.headers
          );
          return originalFetch(...args).then((response) => {
            const responseUrl =
                response && response.url ? response.url : requestUrl;
            const contentType = response && response.headers
                ? response.headers.get('content-type') || ''
                : '';
            captureDirectSource(responseUrl || requestUrl, {
              headers: requestHeaders,
              contentType,
              confidence: contentType ? 2 : 1,
            });
            return response;
          });
        };
      }

      if (typeof XMLHttpRequest !== 'undefined') {
        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;
        const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;

        XMLHttpRequest.prototype.open = function(method, url, ...rest) {
          this.__cheriflixRequestUrl = url;
          this.__cheriflixRequestHeaders = {};
          return originalOpen.call(this, method, url, ...rest);
        };

        XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
          try {
            const headerName = String(name);
            this.__cheriflixRequestHeaders =
                this.__cheriflixRequestHeaders || {};
            this.__cheriflixRequestHeaders[headerName] = String(value);
          } catch (_) {}
          return originalSetRequestHeader.call(this, name, value);
        };

        XMLHttpRequest.prototype.send = function(...args) {
          this.addEventListener('load', () => {
            try {
              const responseUrl = this.responseURL || this.__cheriflixRequestUrl;
              const contentType =
                  this.getResponseHeader('content-type') || '';
              captureDirectSource(responseUrl, {
                headers: this.__cheriflixRequestHeaders,
                contentType,
                confidence: contentType ? 2 : 1,
              });
            } catch (_) {}
          }, { once: true });
          return originalSend.apply(this, args);
        };
      }
    } catch (_) {}
  };

  const scanPerformanceResources = () => {
    try {
      if (!window.performance ||
          typeof window.performance.getEntriesByType !== 'function') {
        return;
      }

      const entries = window.performance.getEntriesByType('resource') || [];
      const recentEntries = entries.slice(Math.max(0, entries.length - 40));
      recentEntries.forEach((entry) => {
        captureDirectSource(entry && entry.name ? entry.name : '', {
          confidence: 1,
        });
      });
    } catch (_) {}
  };

  const syncQualityState = () => {
    const hls = getHlsInstance();
    if (!hls) {
      playerState.qualityOptions = ['Auto'];
      playerState.selectedQualityLabel = 'Auto';
      playerState.hlsQualityIndex = -1;
      return;
    }

    const levels = Array.isArray(hls.levels) ? hls.levels : [];
    const options = ['Auto'];
    for (const level of levels) {
      const label = level && (level.height || level.width)
          ? `${level.height || level.width}p`
          : 'Auto';
      options.push(label);
    }

    playerState.qualityOptions = options;
    playerState.hlsQualityIndex =
        typeof hls.currentLevel === 'number' ? hls.currentLevel : -1;
    playerState.selectedQualityLabel =
        playerState.hlsQualityIndex >= 0 &&
            playerState.hlsQualityIndex + 1 < options.length
        ? options[playerState.hlsQualityIndex + 1]
        : 'Auto';
  };

  const getConfiguredCaptionTracks = () => {
    const config = window.__cheriflixCaptionConfig || {};
    return Array.isArray(config.tracks) ? config.tracks : [];
  };

  const syncCaptionElements = (video) => {
    if (!video) {
      return;
    }

    const configuredTracks = getConfiguredCaptionTracks();
    const existingElements = Array.from(
      video.querySelectorAll('track[data-cheriflix-caption="true"]')
    );
    const byId = new Map(
      existingElements.map((element) => [element.getAttribute('data-track-id'), element])
    );

    for (const configuredTrack of configuredTracks) {
      if (!configuredTrack || !configuredTrack.id || !configuredTrack.url) {
        continue;
      }

      let element = byId.get(configuredTrack.id);
      if (!element) {
        element = document.createElement('track');
        element.setAttribute('data-cheriflix-caption', 'true');
        element.setAttribute('data-track-id', configuredTrack.id);
        video.appendChild(element);
      }

      try {
        element.kind = 'subtitles';
        element.label = configuredTrack.label || configuredTrack.id;
        element.srclang = configuredTrack.languageCode || 'en';
        element.src = configuredTrack.url;
        element.default = configuredTrack.id === playerState.selectedCaptionTrackId;
      } catch (_) {}
    }

    existingElements.forEach((element) => {
      const trackId = element.getAttribute('data-track-id');
      const stillConfigured = configuredTracks.some((track) => track.id === trackId);
      if (!stillConfigured) {
        element.remove();
      }
    });
  };

  const syncCaptionTrackModes = (video) => {
    if (!video) {
      return;
    }

    const configuredTracks = getConfiguredCaptionTracks();
    const tracks = getCaptionTracks(video);
    for (let index = 0; index < tracks.length; index += 1) {
      const configuredTrack = configuredTracks[index];
      const track = tracks[index];
      try {
        track.mode =
            configuredTrack && configuredTrack.id === playerState.selectedCaptionTrackId
            ? 'showing'
            : 'disabled';
      } catch (_) {}
      try {
        if (!track.__cheriflixCueHooked && typeof track.addEventListener === 'function') {
          track.__cheriflixCueHooked = true;
          track.addEventListener('cuechange', () => postState());
        }
      } catch (_) {}
    }
  };

  const getSerializedCaptionTracks = () => {
    return getConfiguredCaptionTracks().map((track) => ({
      id: track.id,
      label: track.label,
      languageCode: track.languageCode || 'en',
      kind: track.kind || 'auto',
      format: track.format || 'vtt',
      url: track.url,
      isDefault: track.id === playerState.selectedCaptionTrackId,
    }));
  };

  const resolveSelectedCaptionLabel = () => {
    const selectedTrack = getConfiguredCaptionTracks().find(
      (track) => track.id === playerState.selectedCaptionTrackId
    );
    return selectedTrack && selectedTrack.label ? selectedTrack.label : 'Off';
  };

  const getCaptionTracks = (video) => {
    try {
      return Array.from(video.textTracks || []).filter((track) => {
        const kind = String(track.kind || '').toLowerCase();
        return kind === 'captions' || kind === 'subtitles';
      });
    } catch (_) {
      return [];
    }
  };

  const getActiveSubtitleLines = (video) => {
    if (!video) {
      return [];
    }
    try {
      const tracks = getCaptionTracks(video);
      const selectedTrack = tracks.find((track) => track.mode === 'showing');
      if (!selectedTrack || !selectedTrack.activeCues) {
        return [];
      }
      return Array.from(selectedTrack.activeCues)
          .map((cue) => String(cue && cue.text ? cue.text : '').trim())
          .filter((line) => line.length > 0);
    } catch (_) {
      return [];
    }
  };

  const applyPresentation = (video) => {
    if (!video) {
      return;
    }

    try {
      prepareVideoForAutoplay(video);
      video.autoplay = true;
      video.playsInline = true;
      video.setAttribute('autoplay', 'autoplay');
      video.setAttribute('playsinline', 'true');
      video.controls = false;
      video.removeAttribute('controls');
      video.setAttribute('controlslist', 'nodownload noplaybackrate');
      video.style.transformOrigin = 'center center';
      video.style.transform = `scale(${playerState.zoomScale})`;
      video.style.objectFit = playerState.zoomScale > 1 ? 'cover' : 'contain';
      video.style.backgroundColor = 'black';
    } catch (_) {}

    syncCaptionElements(video);
    syncCaptionTrackModes(video);
    applyPendingSeek(video);

    document.querySelectorAll(
      '.jw-controls,.jw-controlbar,.jw-display-icon-container,.vjs-control-bar,.plyr__controls,.shaka-controls-container'
    ).forEach((node) => {
      try {
        node.style.display = 'none';
        node.style.visibility = 'hidden';
        node.style.opacity = '0';
      } catch (_) {}
    });
  };

  const prepareVideoForAutoplay = (video) => {
    if (!video) {
      return;
    }

    try {
      video.autoplay = true;
      video.playsInline = true;
      video.preload = 'auto';
      video.setAttribute('autoplay', 'autoplay');
      video.setAttribute('playsinline', 'true');
      video.setAttribute('preload', 'auto');
      if (!playerState.userVolumeAdjusted && !playerState.defaultAudioRestored) {
        video.defaultMuted = true;
        video.muted = true;
        video.volume = 0;
        video.setAttribute('muted', 'true');
      }
    } catch (_) {}
  };

  const restoreDefaultAudioIfAllowed = (video) => {
    if (
      !video ||
      video.paused ||
      playerState.userVolumeAdjusted ||
      playerState.defaultAudioRestored
    ) {
      return;
    }

    try {
      video.defaultMuted = false;
      video.muted = false;
      video.volume = playerState.defaultVolume;
      video.removeAttribute('muted');
      playerState.defaultAudioRestored = true;
    } catch (_) {}
  };

  const playVideo = (video) => {
    if (!video) {
      return false;
    }

    try {
      if (typeof video.play === 'function') {
        const playResult = video.play();
        if (playResult && typeof playResult.catch === 'function') {
          playResult.catch(() => {});
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  };

  const playAllVideos = () => {
    const videos = getVideos();
    let played = false;
    for (const candidate of videos) {
      prepareVideoForAutoplay(candidate);
      played = playVideo(candidate) || played;
    }
    return played;
  };

  const kickAutoplayPlayback = (video) => {
    if (video) {
      prepareVideoForAutoplay(video);
    }

    playAllVideos();
    playKnownPlayerLibraries();
    clickPlayActivator();
    playVideo(video);
  };

  const enableMutedAutoplay = (video) => {
    if (!video) {
      return;
    }

    prepareVideoForAutoplay(video);
  };

  const applyPendingSeek = (video) => {
    if (!video || playerState.pendingSeekSeconds == null) {
      return;
    }

    const requested = Number(playerState.pendingSeekSeconds);
    if (!Number.isFinite(requested)) {
      playerState.pendingSeekSeconds = null;
      return;
    }

    try {
      const duration = Number.isFinite(video.duration) ? video.duration : requested;
      video.currentTime = Math.max(0, Math.min(duration, requested));
      playerState.pendingSeekSeconds = null;
    } catch (_) {}
  };

  const attemptAutoplay = (video, force = false) => {
    if (!video) {
      if (!force && (!playerState.autoplayRequested || playerState.userPausedPlayback)) {
        return;
      }
      playKnownPlayerLibraries();
      clickPlayActivator();
      return;
    }

    if (!force && (!playerState.autoplayRequested || playerState.userPausedPlayback)) {
      return;
    }

    if (!video.paused) {
      playerState.autoplayRequested = false;
      return;
    }

    kickAutoplayPlayback(video);

    window.setTimeout(() => {
      if (!video.paused) {
        playerState.autoplayRequested = false;
        return;
      }

      if (playerState.autoplayRequested && !playerState.userPausedPlayback) {
        kickAutoplayPlayback(video);
      }
    }, 180);

    window.setTimeout(() => {
      if (!video.paused) {
        playerState.autoplayRequested = false;
        return;
      }

      if (playerState.autoplayRequested && !playerState.userPausedPlayback) {
        kickAutoplayPlayback(video);
      }
    }, 700);
  };

  const postState = () => {
    const video = getVideo();
    if (!video) {
      const detectedSource = playerState.detectedSource;
      postMessage({
        bridgeAvailable: false,
        currentSeconds: 0,
        durationSeconds: 0,
        paused: true,
        muted: false,
        playbackRate: 1,
        zoomScale: playerState.zoomScale,
        captionsAvailable: getConfiguredCaptionTracks().length > 0,
        captionsEnabled: playerState.selectedCaptionTrackId != null,
        captionTracks: getSerializedCaptionTracks(),
        selectedCaptionTrackId: playerState.selectedCaptionTrackId,
        selectedCaptionLabel: resolveSelectedCaptionLabel(),
        subtitleLines: [],
        qualityOptions: playerState.qualityOptions,
        selectedQualityLabel: playerState.selectedQualityLabel,
        detectedSourceUrl: detectedSource ? detectedSource.url : null,
        detectedSourceKind: detectedSource ? detectedSource.sourceKind : null,
        detectedSourceConfidence: detectedSource ? detectedSource.confidence : null,
        detectedSourceHeaders: detectedSource ? detectedSource.headers : null,
        detectedSourcePageUrl: detectedSource ? detectedSource.pageUrl : null,
      });
      return;
    }

    applyPresentation(video);
    restoreDefaultAudioIfAllowed(video);
    captureVideoSource(video);
    syncQualityState();
    const captionTracks = getCaptionTracks(video);
    const detectedSource = playerState.detectedSource;
    postMessage({
      bridgeAvailable: true,
      currentSeconds:
          Number.isFinite(video.currentTime) ? video.currentTime : 0,
      durationSeconds: Number.isFinite(video.duration) ? video.duration : 0,
      paused: video.paused,
      muted: video.muted || video.volume === 0,
      playbackRate:
          Number.isFinite(video.playbackRate) ? video.playbackRate : 1,
      zoomScale: playerState.zoomScale,
      captionsAvailable:
          captionTracks.length > 0 || getConfiguredCaptionTracks().length > 0,
      captionsEnabled:
          captionTracks.some((track) => track.mode === 'showing') ||
          playerState.selectedCaptionTrackId != null,
      captionTracks: getSerializedCaptionTracks(),
      selectedCaptionTrackId: playerState.selectedCaptionTrackId,
      selectedCaptionLabel: resolveSelectedCaptionLabel(),
      subtitleLines: getActiveSubtitleLines(video),
      qualityOptions: playerState.qualityOptions,
      selectedQualityLabel: playerState.selectedQualityLabel,
      videoWidth: Number(video.videoWidth || 0),
      videoHeight: Number(video.videoHeight || 0),
      hasRenderedFrame:
          Number(video.readyState || 0) >= 2 &&
          Number(video.videoWidth || 0) > 0 &&
          Number(video.videoHeight || 0) > 0,
      detectedSourceUrl: detectedSource ? detectedSource.url : null,
      detectedSourceKind: detectedSource ? detectedSource.sourceKind : null,
      detectedSourceConfidence: detectedSource ? detectedSource.confidence : null,
      detectedSourceHeaders: detectedSource ? detectedSource.headers : null,
      detectedSourcePageUrl: detectedSource ? detectedSource.pageUrl : null,
    });
    if (!video.paused) {
      playerState.autoplayRequested = false;
    }
  };

  const hookVideo = () => {
    const video = getVideo();
    if (!video || video.__cheriflixHooked) {
      if (video) {
        applyPresentation(video);
      }
      return;
    }

    video.__cheriflixHooked = true;
    const forwardState = () => postState();
    [
      'play',
      'pause',
      'timeupdate',
      'durationchange',
      'loadedmetadata',
      'seeked',
      'volumechange',
      'ratechange'
    ].forEach((eventName) => {
      try {
        video.addEventListener(eventName, forwardState, { passive: true });
      } catch (_) {}
    });
    try {
      video.addEventListener('play', () => {
        playerState.autoplayRequested = false;
      }, { passive: true });
    } catch (_) {}
    try {
      video.addEventListener('loadedmetadata', () => {
        applyPendingSeek(video);
        postState();
      }, {
        passive: true
      });
    } catch (_) {}
    try {
      video.addEventListener('canplay', () => {
        postState();
      }, {
        passive: true
      });
    } catch (_) {}
    try {
      video.addEventListener('canplaythrough', () => {
        postState();
      }, {
        passive: true
      });
    } catch (_) {}

    applyPresentation(video);
    postState();
  };

  const cyclePlaybackRate = () => {
    const video = getVideo();
    if (!video) {
      postState();
      return;
    }

    const rates = [0.75, 1, 1.25, 1.5, 1.75, 2];
    const current = Number.isFinite(video.playbackRate) ? video.playbackRate : 1;
    const currentIndex = rates.findIndex((rate) => Math.abs(rate - current) < 0.01);
    const nextRate = rates[(currentIndex + 1 + rates.length) % rates.length];
    try {
      video.playbackRate = nextRate;
    } catch (_) {}
    postState();
  };

  const stepPlaybackRate = (direction) => {
    const video = getVideo();
    if (!video) {
      postState();
      return;
    }

    const rates = [0.75, 1, 1.25, 1.5, 1.75, 2];
    const current = Number.isFinite(video.playbackRate) ? video.playbackRate : 1;
    const currentIndex = rates.findIndex((rate) => Math.abs(rate - current) < 0.01);
    const normalizedIndex = currentIndex < 0 ? 1 : currentIndex;
    const nextIndex = Math.max(
      0,
      Math.min(rates.length - 1, normalizedIndex + (direction < 0 ? -1 : 1))
    );
    try {
      video.playbackRate = rates[nextIndex];
    } catch (_) {}
    postState();
  };

  const bridge = {
    refresh() {
      installHlsHook();
      scanPerformanceResources();
      hookVideo();
      postState();
    },
    requestState() {
      installHlsHook();
      scanPerformanceResources();
      hookVideo();
      postState();
    },
    play() {
      hookVideo();
      const video = getVideo();
      playerState.userPausedPlayback = false;
      playerState.autoplayRequested = true;
      if (!video) {
        playKnownPlayerLibraries();
        clickPlayActivator();
        postState();
        return;
      }
      kickAutoplayPlayback(video);
      window.setTimeout(() => {
        if (playerState.autoplayRequested && !playerState.userPausedPlayback) {
          kickAutoplayPlayback(video);
        }
      }, 180);
      window.setTimeout(() => {
        if (playerState.autoplayRequested && !playerState.userPausedPlayback) {
          kickAutoplayPlayback(video);
        }
      }, 700);
      postState();
    },
    pause() {
      hookVideo();
      playerState.userPausedPlayback = true;
      playerState.autoplayRequested = false;
      const video = getVideo();
      if (video && typeof video.pause === 'function') {
        try {
          video.pause();
        } catch (_) {}
      }
      postState();
    },
    togglePlayPause() {
      hookVideo();
      const video = getVideo();
      if (!video) {
        playerState.userPausedPlayback = false;
        playerState.autoplayRequested = true;
        playKnownPlayerLibraries();
        clickPlayActivator();
        postState();
        return;
      }
      try {
        if (video.paused) {
          playerState.userPausedPlayback = false;
          playerState.autoplayRequested = true;
          kickAutoplayPlayback(video);
          window.setTimeout(() => {
            if (!video.paused) {
              playerState.autoplayRequested = false;
              return;
            }

            if (playerState.autoplayRequested && !playerState.userPausedPlayback) {
              kickAutoplayPlayback(video);
            }
          }, 180);

          window.setTimeout(() => {
            if (!video.paused) {
              playerState.autoplayRequested = false;
              return;
            }

            if (playerState.autoplayRequested && !playerState.userPausedPlayback) {
              kickAutoplayPlayback(video);
            }
          }, 700);
        } else if (typeof video.pause === 'function') {
          playerState.userPausedPlayback = true;
          playerState.autoplayRequested = false;
          video.pause();
        }
      } catch (_) {}
      postState();
    },
    attemptAutoplay() {
      hookVideo();
      const video = getVideo();
      playerState.userPausedPlayback = false;
      playerState.autoplayRequested = true;
      attemptAutoplay(video, true);
      postState();
    },
    seekBy(seconds) {
      hookVideo();
      const video = getVideo();
      if (!video) {
        postState();
        return;
      }
      const amount = Number(seconds || 0);
      if (!Number.isFinite(amount)) {
        postState();
        return;
      }
      try {
        const duration = Number.isFinite(video.duration) ? video.duration : Infinity;
        const nextTime = Math.max(0, Math.min(duration, (video.currentTime || 0) + amount));
        video.currentTime = nextTime;
      } catch (_) {}
      postState();
    },
    seekTo(seconds) {
      hookVideo();
      const requested = Number(seconds || 0);
      if (!Number.isFinite(requested)) {
        postState();
        return;
      }

      playerState.pendingSeekSeconds = Math.max(0, requested);
      const video = getVideo();
      if (video) {
        applyPendingSeek(video);
      }
      postState();
    },
    toggleMute() {
      hookVideo();
      const video = getVideo();
      if (!video) {
        postState();
        return;
      }
      try {
        playerState.userVolumeAdjusted = true;
        playerState.defaultAudioRestored = true;
        const shouldUnmute = video.muted || video.volume === 0;
        video.muted = !shouldUnmute;
        if (shouldUnmute) {
          video.defaultMuted = false;
          video.volume = playerState.defaultVolume;
          video.removeAttribute('muted');
        } else {
          video.volume = 0;
          video.setAttribute('muted', 'true');
        }
      } catch (_) {}
      postState();
    },
    cyclePlaybackRate() {
      hookVideo();
      cyclePlaybackRate();
    },
    stepPlaybackRate(direction) {
      hookVideo();
      stepPlaybackRate(Number(direction) || 0);
    },
    toggleCaptions() {
      const configuredTracks = getConfiguredCaptionTracks();
      if (configuredTracks.length === 0) {
        playerState.selectedCaptionTrackId = null;
        postState();
        return;
      }

      playerState.selectedCaptionTrackId =
          playerState.selectedCaptionTrackId == null ? configuredTracks[0].id : null;
      const video = getVideo();
      if (video) {
        syncCaptionElements(video);
        syncCaptionTrackModes(video);
      }
      postState();
    },
    selectCaptionTrack(trackId) {
      const nextTrackId = trackId ? String(trackId) : null;
      playerState.selectedCaptionTrackId = nextTrackId;
      const video = getVideo();
      if (video) {
        syncCaptionElements(video);
        syncCaptionTrackModes(video);
      }
      postState();
    },
    setCaptionTracks(argument) {
      const payload = argument && typeof argument === 'object' ? argument : {};
      const tracks = Array.isArray(payload.tracks) ? payload.tracks : [];
      const selectedTrackId = payload.selectedTrackId == null
          ? null
          : String(payload.selectedTrackId);
      window.__cheriflixCaptionConfig = {
        tracks: tracks,
        selectedTrackId: selectedTrackId,
      };
      playerState.selectedCaptionTrackId = selectedTrackId;
      const video = getVideo();
      if (video) {
        syncCaptionElements(video);
        syncCaptionTrackModes(video);
      }
      postState();
    },
    cycleQuality() {
      hookVideo();
      const hls = getHlsInstance();
      syncQualityState();
      if (!hls || playerState.qualityOptions.length <= 1) {
        postState();
        return;
      }

      const currentDisplayIndex =
          playerState.hlsQualityIndex < 0 ? 0 : playerState.hlsQualityIndex + 1;
      const nextDisplayIndex =
          (currentDisplayIndex + 1) % playerState.qualityOptions.length;
      try {
        hls.currentLevel = nextDisplayIndex == 0 ? -1 : nextDisplayIndex - 1;
      } catch (_) {}
      syncQualityState();
      postState();
    },
    adjustZoom(delta) {
      const amount = Number(delta || 0);
      if (!Number.isFinite(amount)) {
        postState();
        return;
      }

      playerState.zoomScale = Math.max(
        0.5,
        Math.min(3, playerState.zoomScale + amount)
      );
      const video = getVideo();
      if (video) {
        applyPresentation(video);
      }
      postState();
    },
  };

  const invokeBridgeCommand = (payload) => {
    if (!payload || payload.type !== 'cheriflix-command') {
      return;
    }

    const targetFrameId = payload.targetFrameId ? String(payload.targetFrameId) : null;
    if (targetFrameId && targetFrameId !== frameId) {
      return;
    }

    const command = payload.command ? String(payload.command) : '';
    if (!command || typeof bridge[command] !== 'function') {
      return;
    }

    try {
      bridge[command](payload.argument);
    } catch (_) {}
  };

  window.__cheriflixDispatchPlayerCommand = (payload) => {
    invokeBridgeCommand(payload);
    for (let index = 0; index < window.frames.length; index += 1) {
      try {
        window.frames[index].postMessage(payload, '*');
      } catch (_) {}
    }
  };

  window.addEventListener('message', (event) => {
    const payload = event && event.data;
    if (!payload || payload.type !== 'cheriflix-command') {
      return;
    }
    invokeBridgeCommand(payload);
    for (let index = 0; index < window.frames.length; index += 1) {
      try {
        window.frames[index].postMessage(payload, '*');
      } catch (_) {}
    }
  });

  window.__cheriflixPlayerBridge = bridge;
  installNetworkHooks();
  installHlsHook();
  scanPerformanceResources();
  hookVideo();
  bridge.refresh();
  postState();

  let scanTicks = 0;
  const scanInterval = window.setInterval(() => {
    installHlsHook();
    scanPerformanceResources();
    hookVideo();
    postState();
    scanTicks += 1;
    if (scanTicks >= 180) {
      window.clearInterval(scanInterval);
    }
  }, 1000);
})();
''';

const String _siteHardeningFollowUpScript = r'''
(() => {
  try {
    if (window.__cheriflixProtector &&
        typeof window.__cheriflixProtector.scrub === 'function') {
      window.__cheriflixProtector.scrub();
    }
    if (window.__cheriflixPlayerBridge &&
        typeof window.__cheriflixPlayerBridge.refresh === 'function') {
      window.__cheriflixPlayerBridge.refresh();
    }
  } catch (_) {}
})();
''';
