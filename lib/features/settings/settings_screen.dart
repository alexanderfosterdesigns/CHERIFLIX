import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/maturity_tier.dart';
import '../../core/models/profile.dart';
import '../../core/models/profile_playback_settings.dart';
import '../../core/services/offline_download_manager.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';
import '../../core/utils/user_facing_errors.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/tv_text_editor_dialog.dart';
import '../../core/widgets/tv_shortcuts.dart';
import '../profile/profile_avatar_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.activeProfile,
    required this.playbackSettings,
    required this.hideSpoilers,
    required this.onHideSpoilersChanged,
    required this.onBack,
    required this.onSaveProfile,
    required this.onSavePlaybackSettings,
    this.onClearRememberedAudioLanguages,
    this.traktAuthorizationUri,
    this.onConnectTrakt,
    this.onDisconnectTrakt,
    required this.onCheckForUpdates,
    this.onBrowseHome,
    this.onBrowseTvShows,
    this.onBrowseMovies,
    this.onBrowseNewPopular,
    this.onBrowseMyList,
    this.onOpenSearch,
    this.onSwitchProfile,
    this.downloadManager,
    this.downloadLocation = '',
    this.onDownloadLocationChanged,
  });

  final Profile activeProfile;
  final ProfilePlaybackSettings playbackSettings;
  final bool hideSpoilers;
  final ValueChanged<bool> onHideSpoilersChanged;
  final VoidCallback onBack;
  final ValueChanged<Profile> onSaveProfile;
  final ValueChanged<ProfilePlaybackSettings> onSavePlaybackSettings;
  final Future<void> Function()? onClearRememberedAudioLanguages;
  final Uri? traktAuthorizationUri;
  final Future<void> Function(String code)? onConnectTrakt;
  final Future<void> Function()? onDisconnectTrakt;
  final Future<void> Function()? onCheckForUpdates;
  final VoidCallback? onBrowseHome;
  final VoidCallback? onBrowseTvShows;
  final VoidCallback? onBrowseMovies;
  final VoidCallback? onBrowseNewPopular;
  final VoidCallback? onBrowseMyList;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onSwitchProfile;
  final OfflineDownloadManager? downloadManager;
  final String downloadLocation;
  final Future<void> Function(String path)? onDownloadLocationChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Map<String, String> _languages = <String, String>{
    'en': 'English',
    'fr': 'French',
    'es': 'Spanish',
    'ar': 'Arabic',
    'de': 'German',
    'hi': 'Hindi',
    'it': 'Italian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'zh': 'Chinese',
  };
  static const bool _showTraktSettings = false;
  static const bool _showCheckForUpdates = false;

  late final TextEditingController _nameController =
      TextEditingController(text: widget.activeProfile.name);
  late final TextEditingController _subtitleController =
      TextEditingController(text: widget.playbackSettings.subtitleUrl ?? '');
  late final FocusNode _backButtonFocusNode =
      FocusNode(debugLabel: 'SettingsBack');
  late final FocusNode _nameFocusNode = FocusNode(debugLabel: 'SettingsName');
  late String _avatarLabel = widget.activeProfile.avatarLabel;
  late String _languageCode = widget.playbackSettings.languageCode;
  late String _preferredAudioLanguageCode =
      widget.playbackSettings.preferredAudioLanguageCode;
  late MaturityTier _maturityTier = widget.activeProfile.maturityTier;
  late bool _autoplayNextEpisode = widget.playbackSettings.autoplayNextEpisode;
  late bool _autoplayPreviews = widget.playbackSettings.autoplayPreviews;
  late bool _muteAutoplayTrailers =
      widget.playbackSettings.muteAutoplayTrailers;
  late String _downloadLocation = widget.downloadLocation;

  @override
  void dispose() {
    _nameController.dispose();
    _subtitleController.dispose();
    _backButtonFocusNode.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    final languageOptions = <DropdownMenuItem<String>>[
      for (final entry in _languages.entries)
        DropdownMenuItem<String>(
          value: entry.key,
          child: Text(entry.value),
        ),
      if (!_languages.containsKey(_languageCode))
        DropdownMenuItem<String>(
          value: _languageCode,
          child: Text(_languageCode.toUpperCase()),
        ),
    ];

    return TvShortcutScope(
      onBack: widget.onBack,
      child: CheriflixScaffold(
        topBar: CheriflixTopBar(
          profile: widget.activeProfile.copyWith(avatarLabel: _avatarLabel),
          downFallbackNodes: <FocusNode>[_backButtonFocusNode],
          onHome: widget.onBrowseHome,
          onTvShows: widget.onBrowseTvShows,
          onMovies: widget.onBrowseMovies,
          onNewPopular: widget.onBrowseNewPopular,
          onMyList: widget.onBrowseMyList,
          onSearch: widget.onOpenSearch,
          onProfiles: widget.onSwitchProfile,
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding.left,
            layout.value(compact: 10, standard: 12, wide: 14),
            layout.pagePadding.right,
            layout.pagePadding.bottom,
          ),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: TvActionButton(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                onPressed: widget.onBack,
                autofocus: true,
                focusNode: _backButtonFocusNode,
                variant: TvButtonVariant.ghost,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: layout.settingsContentMaxWidth,
                ),
                child: CheriflixPanel(
                  padding: EdgeInsets.all(layout.settingsPanelPaddingValue),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 860;
                          return compact
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    _buildAvatarBlock(layout),
                                    const SizedBox(height: 28),
                                    _buildIdentityForm(languageOptions),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    _buildAvatarBlock(layout),
                                    SizedBox(
                                      width: layout.value(
                                        compact: 20,
                                        standard: 24,
                                        wide: 32,
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildIdentityForm(
                                        languageOptions,
                                      ),
                                    ),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Color(0x16FFFFFF)),
                      const SizedBox(height: 28),
                      Text(
                        'Maturity Settings',
                        style: TextStyle(
                          fontSize: layout.settingsSectionTitleSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _MaturityButton(
                            label: 'KIDS',
                            active: _maturityTier == MaturityTier.kids,
                            onPressed: () => setState(
                              () => _maturityTier = MaturityTier.kids,
                            ),
                          ),
                          _MaturityButton(
                            label: 'TV-PG, PG',
                            active: _maturityTier == MaturityTier.teen,
                            onPressed: () => setState(
                              () => _maturityTier = MaturityTier.teen,
                            ),
                          ),
                          _MaturityButton(
                            label: 'MATURE',
                            active: _maturityTier == MaturityTier.mature,
                            onPressed: () => setState(
                              () => _maturityTier = MaturityTier.mature,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _maturityDescription(_maturityTier),
                        style: const TextStyle(
                          color: CheriflixColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Divider(color: Color(0x16FFFFFF)),
                      const SizedBox(height: 28),
                      Text(
                        'Audio language',
                        style: TextStyle(
                          fontSize: layout.settingsSectionTitleSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        key: const ValueKey<String>(
                          'preferred_audio_language_setting',
                        ),
                        initialValue: _preferredAudioLanguageCode,
                        dropdownColor: CheriflixColors.surface,
                        decoration: const InputDecoration(
                          labelText: 'PREFERRED AUDIO LANGUAGE',
                          helperText:
                              'Used only when this title has no remembered choice.',
                        ),
                        items: languageOptions,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _preferredAudioLanguageCode = value);
                        },
                      ),
                      if (widget.onClearRememberedAudioLanguages != null) ...[
                        const SizedBox(height: 14),
                        TvActionButton(
                          label: 'Reset remembered title languages',
                          icon: Icons.restart_alt_rounded,
                          onPressed: _clearRememberedAudioLanguages,
                          variant: TvButtonVariant.dark,
                        ),
                      ],
                      const SizedBox(height: 28),
                      const Divider(color: Color(0x16FFFFFF)),
                      const SizedBox(height: 28),
                      Text(
                        'Autoplay controls',
                        style: TextStyle(
                          fontSize: layout.settingsSectionTitleSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          TvActionButton(
                            label: _autoplayNextEpisode
                                ? 'Next Episode: ON'
                                : 'Next Episode: OFF',
                            onPressed: () => setState(() {
                              _autoplayNextEpisode = !_autoplayNextEpisode;
                            }),
                            variant: _autoplayNextEpisode
                                ? TvButtonVariant.danger
                                : TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: _autoplayPreviews
                                ? 'Hide trailers: OFF'
                                : 'Hide trailers: ON',
                            onPressed: _toggleAutoplayPreviews,
                            variant: !_autoplayPreviews
                                ? TvButtonVariant.danger
                                : TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: widget.hideSpoilers
                                ? 'Hide Spoilers: ON'
                                : 'Hide Spoilers: OFF',
                            onPressed: () {
                              widget.onHideSpoilersChanged(
                                !widget.hideSpoilers,
                              );
                            },
                            variant: widget.hideSpoilers
                                ? TvButtonVariant.danger
                                : TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: _muteAutoplayTrailers
                                ? 'Auto-mute trailers: ON'
                                : 'Auto-mute trailers: OFF',
                            onPressed: () => setState(() {
                              _muteAutoplayTrailers = !_muteAutoplayTrailers;
                            }),
                            variant: _muteAutoplayTrailers
                                ? TvButtonVariant.danger
                                : TvButtonVariant.dark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _subtitleController,
                        decoration: const InputDecoration(
                          labelText: 'SUBTITLE URL OVERRIDE',
                          hintText: 'Optional subtitle source override',
                        ),
                      ),
                      if (widget.downloadManager != null) ...<Widget>[
                        const SizedBox(height: 28),
                        const Divider(color: Color(0x16FFFFFF)),
                        const SizedBox(height: 28),
                        Text(
                          'Offline Downloads',
                          style: TextStyle(
                            fontSize: layout.settingsSectionTitleSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedBuilder(
                          animation: widget.downloadManager!,
                          builder: (context, child) {
                            final manager = widget.downloadManager!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Storage used: ${_formatBytes(manager.completedBytes)}\n'
                                  'Location: $_downloadLocation',
                                  style: const TextStyle(
                                    color: CheriflixColors.textSecondary,
                                    fontSize: 16,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: <Widget>[
                                    TvActionButton(
                                      label:
                                          'Quality: ${manager.defaultQuality.label}',
                                      icon: Icons.high_quality_rounded,
                                      onPressed: _cycleDownloadQuality,
                                      variant: TvButtonVariant.dark,
                                    ),
                                    TvActionButton(
                                      label: Platform.isAndroid
                                          ? 'App-managed storage'
                                          : 'Change download location',
                                      icon: Icons.folder_rounded,
                                      onPressed: Platform.isAndroid
                                          ? null
                                          : _editDownloadLocation,
                                      variant: TvButtonVariant.dark,
                                    ),
                                  ],
                                ),
                                if (manager.records.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 18),
                                  for (final record in manager.records)
                                    _buildDownloadRecord(record),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                      if (_showTraktSettings) ...<Widget>[
                        const SizedBox(height: 28),
                        const Divider(color: Color(0x16FFFFFF)),
                        const SizedBox(height: 28),
                        Text(
                          'Trakt',
                          style: TextStyle(
                            fontSize: layout.settingsSectionTitleSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.activeProfile.traktAccount == null
                              ? 'Connect this profile to sync watched titles and unlock personalized recommendations on the home screen.'
                              : 'Connected as @${widget.activeProfile.traktAccount!.username}. This profile now uses Trakt-backed recommendations and watch syncing.',
                          style: const TextStyle(
                            color: CheriflixColors.textSecondary,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            TvActionButton(
                              label: widget.activeProfile.traktAccount == null
                                  ? 'Connect Trakt'
                                  : 'Reconnect Trakt',
                              icon: Icons.login_rounded,
                              onPressed: widget.traktAuthorizationUri == null ||
                                      widget.onConnectTrakt == null
                                  ? null
                                  : _connectTrakt,
                              variant: TvButtonVariant.dark,
                            ),
                            TvActionButton(
                              label: 'Disconnect Trakt',
                              icon: Icons.link_off_rounded,
                              onPressed:
                                  widget.activeProfile.traktAccount == null
                                      ? null
                                      : _disconnectTrakt,
                              variant: TvButtonVariant.dark,
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                      ],
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          TvActionButton(
                            label: 'Save profile',
                            icon: Icons.save_rounded,
                            onPressed: _saveAll,
                            variant: TvButtonVariant.light,
                          ),
                          if (_showCheckForUpdates)
                            TvActionButton(
                              label: 'Check for updates',
                              icon: Icons.system_update_alt_rounded,
                              onPressed: widget.onCheckForUpdates == null
                                  ? null
                                  : () async {
                                      await widget.onCheckForUpdates!();
                                    },
                              variant: TvButtonVariant.dark,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadRecord(OfflineDownloadRecord record) {
    final status = switch (record.status) {
      OfflineDownloadStatus.downloading =>
        '${(record.progress * 100).round()}%',
      OfflineDownloadStatus.completed =>
        'Completed · ${_formatBytes(record.bytesDownloaded)}',
      OfflineDownloadStatus.failed => record.error ?? 'Failed',
      _ => record.status.name,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '$status · ${record.quality.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CheriflixColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                if (record.status == OfflineDownloadStatus.downloading)
                  LinearProgressIndicator(value: record.progress),
              ],
            ),
          ),
          if (record.status == OfflineDownloadStatus.downloading)
            IconButton(
              tooltip: 'Pause',
              onPressed: () => widget.downloadManager!.pause(record.key),
              icon: const Icon(Icons.pause_rounded),
            ),
          if (record.status == OfflineDownloadStatus.paused)
            IconButton(
              tooltip: 'Resume',
              onPressed: () => widget.downloadManager!.resume(record.key),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (record.status == OfflineDownloadStatus.downloading ||
              record.status == OfflineDownloadStatus.paused)
            IconButton(
              tooltip: 'Cancel',
              onPressed: () => widget.downloadManager!.cancel(record.key),
              icon: const Icon(Icons.close_rounded),
            ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => widget.downloadManager!.delete(record.key),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  void _cycleDownloadQuality() {
    final current = widget.downloadManager!.defaultQuality.index;
    widget.downloadManager!.defaultQuality = OfflineDownloadQuality
        .values[(current + 1) % OfflineDownloadQuality.values.length];
    setState(() {});
  }

  Future<void> _editDownloadLocation() async {
    final path = await showTvTextEditorDialog(
      context,
      title: 'Download Location',
      initialValue: _downloadLocation,
    );
    if (!mounted || path == null || path.trim().isEmpty) {
      return;
    }
    try {
      await widget.onDownloadLocationChanged?.call(path.trim());
      if (mounted) {
        setState(() => _downloadLocation = path.trim());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingErrorMessage(
                error,
                fallback: 'The download location could not be changed.',
              ),
            ),
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildAvatarBlock(CheriflixTvLayout layout) {
    return SizedBox(
      width: layout.settingsAvatarBlockWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          CheriflixProfileArtwork(
            size: layout.settingsArtworkSize,
            avatarLabel: _avatarLabel,
          ),
          const SizedBox(height: 12),
          TvIconButton(
            icon: Icons.edit_rounded,
            label: 'Change profile picture',
            onPressed: _openAvatarPicker,
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityForm(List<DropdownMenuItem<String>> languageOptions) {
    final dropdownTheme = Theme.of(context).copyWith(
      focusColor: CheriflixColors.focus.withValues(alpha: 0.22),
      hoverColor: CheriflixColors.focus.withValues(alpha: 0.18),
      highlightColor: CheriflixColors.focus.withValues(alpha: 0.2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TvActionButton(
          key: const ValueKey<String>('settings_profile_name'),
          label: 'NAME  ·  ${_nameController.text}',
          icon: Icons.keyboard_rounded,
          focusNode: _nameFocusNode,
          onPressed: _editProfileName,
          variant: TvButtonVariant.dark,
        ),
        const SizedBox(height: 18),
        Theme(
          data: dropdownTheme,
          child: DropdownButtonFormField<String>(
            initialValue: _languageCode,
            dropdownColor: CheriflixColors.surface,
            decoration: const InputDecoration(
              labelText: 'APP LANGUAGE',
            ),
            items: languageOptions,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _languageCode = value);
            },
          ),
        ),
        const SizedBox(height: 18),
        TvActionButton(
          label: widget.activeProfile.isLocked
              ? 'Remove Profile PIN'
              : 'Add Profile PIN',
          icon: widget.activeProfile.isLocked
              ? Icons.lock_open_rounded
              : Icons.lock_rounded,
          onPressed: _editProfilePin,
          variant: TvButtonVariant.dark,
        ),
      ],
    );
  }

  void _saveAll() {
    final trimmedName = _nameController.text.trim();
    final updatedProfile = widget.activeProfile.copyWith(
      name: trimmedName.isEmpty ? widget.activeProfile.name : trimmedName,
      avatarLabel: _avatarLabel,
      languageCode: _languageCode,
      maturityTier: _maturityTier,
    );
    final playbackSettings = ProfilePlaybackSettings(
      languageCode: _languageCode,
      preferredAudioLanguageCode: _preferredAudioLanguageCode,
      subtitleUrl: _subtitleController.text.trim().isEmpty
          ? null
          : _subtitleController.text.trim(),
      autoplayNextEpisode: _autoplayNextEpisode,
      autoplayPreviews: _autoplayPreviews,
      muteAutoplayTrailers: _muteAutoplayTrailers,
      preferredAndroidRendererProfile:
          widget.playbackSettings.preferredAndroidRendererProfile,
    );

    widget.onSaveProfile(updatedProfile);
    widget.onSavePlaybackSettings(playbackSettings);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile and playback settings saved.')),
    );
  }

  Future<void> _clearRememberedAudioLanguages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset remembered languages?'),
        content: const Text(
          'Shows and movies will use the global preferred audio language again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onClearRememberedAudioLanguages?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remembered audio languages cleared.')),
    );
  }

  Future<void> _editProfileName() async {
    final updatedName = await showTvTextEditorDialog(
      context,
      title: 'Edit Profile Name',
      initialValue: _nameController.text,
    );
    if (!mounted || updatedName == null) return;
    setState(() => _nameController.text = updatedName);
    _nameFocusNode.requestFocus();
  }

  Future<void> _editProfilePin() async {
    if (widget.activeProfile.isLocked) {
      widget.onSaveProfile(widget.activeProfile.copyWith(pinHash: null));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile PIN removed.')),
      );
      return;
    }
    final pin = await showTvTextEditorDialog(
      context,
      title: 'Create a 4-digit Profile PIN',
      initialValue: '',
      maxLength: 4,
      numericOnly: true,
    );
    if (!mounted || pin == null) return;
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN must contain exactly 4 numbers.')),
      );
      return;
    }
    widget.onSaveProfile(
      widget.activeProfile.copyWith(
        pinHash: sha256.convert(utf8.encode(pin)).toString(),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile PIN enabled.')),
    );
  }

  void _toggleAutoplayPreviews() {
    final nextValue = !_autoplayPreviews;
    setState(() {
      _autoplayPreviews = nextValue;
    });
    widget.onSavePlaybackSettings(
      widget.playbackSettings.copyWith(
        autoplayPreviews: nextValue,
      ),
    );
  }

  void _openAvatarPicker() async {
    final selectedAvatarKey = await showProfileAvatarPickerDialog(
      context,
      selectedAvatarLabel: _avatarLabel,
    );
    if (!mounted ||
        selectedAvatarKey == null ||
        selectedAvatarKey == _avatarLabel) {
      return;
    }

    setState(() => _avatarLabel = selectedAvatarKey);
    widget.onSaveProfile(
      widget.activeProfile.copyWith(
        avatarLabel: selectedAvatarKey,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile picture updated.')),
    );
  }

  Future<void> _connectTrakt() async {
    final authorizationUri = widget.traktAuthorizationUri;
    final onConnectTrakt = widget.onConnectTrakt;
    if (authorizationUri == null || onConnectTrakt == null) {
      return;
    }

    final authorizationCode = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return _TraktConnectDialog(
          authorizationUri: authorizationUri,
        );
      },
    );
    if (!mounted || authorizationCode == null) {
      return;
    }

    try {
      await onConnectTrakt(authorizationCode.trim());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trakt profile connected.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingErrorMessage(
              error,
              fallback: 'Trakt sign-in could not be completed.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _disconnectTrakt() async {
    final onDisconnectTrakt = widget.onDisconnectTrakt;
    if (onDisconnectTrakt == null) {
      return;
    }

    try {
      await onDisconnectTrakt();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trakt profile disconnected.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingErrorMessage(
              error,
              fallback: 'Trakt could not be disconnected right now.',
            ),
          ),
        ),
      );
    }
  }
}

class _MaturityButton extends StatelessWidget {
  const _MaturityButton({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvActionButton(
      label: label,
      onPressed: onPressed,
      variant: active ? TvButtonVariant.danger : TvButtonVariant.dark,
    );
  }
}

class _TraktConnectDialog extends StatefulWidget {
  const _TraktConnectDialog({
    required this.authorizationUri,
  });

  final Uri authorizationUri;

  @override
  State<_TraktConnectDialog> createState() => _TraktConnectDialogState();
}

class _TraktConnectDialogState extends State<_TraktConnectDialog> {
  late final TextEditingController _codeController = TextEditingController();
  String? _openError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CheriflixColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      title: const Text(
        'Connect Trakt',
        style: TextStyle(
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: CheriflixTvLayout.of(context).value(
          compact: 420,
          standard: 500,
          wide: 560,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Each Cheriflix profile can connect to its own Trakt account. Open the Trakt login page, approve access, then paste the authorization code shown by Trakt into the field below.',
              style: TextStyle(
                color: CheriflixColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            TvActionButton(
              label: 'Open Trakt Login',
              icon: Icons.open_in_browser_rounded,
              onPressed: () async {
                try {
                  await _openExternalUri(widget.authorizationUri);
                  if (!mounted) {
                    return;
                  }
                  setState(() => _openError = null);
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _openError = userFacingErrorMessage(
                      error,
                      fallback: 'The Trakt sign-in page could not be opened.',
                    );
                  });
                }
              },
              variant: TvButtonVariant.light,
            ),
            const SizedBox(height: 14),
            SelectableText(
              widget.authorizationUri.toString(),
              style: const TextStyle(
                color: CheriflixColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (_openError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _openError!,
                style: const TextStyle(
                  color: CheriflixColors.accentRed,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _codeController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'AUTHORIZATION CODE',
                hintText: 'Paste the code from Trakt',
              ),
              onSubmitted: (value) {
                final code = value.trim();
                if (code.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(code);
              },
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                TvActionButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  variant: TvButtonVariant.dark,
                ),
                TvActionButton(
                  label: 'Connect',
                  onPressed: () {
                    final code = _codeController.text.trim();
                    if (code.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop(code);
                  },
                  variant: TvButtonVariant.light,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _maturityDescription(MaturityTier tier) {
  switch (tier) {
    case MaturityTier.kids:
      return 'Only show titles suitable for younger viewers on this profile.';
    case MaturityTier.teen:
      return 'Show titles rated TV-PG, PG and below for this profile.';
    case MaturityTier.mature:
      return 'Show the full CHERIFLIX catalog, including mature titles.';
  }
}

Future<void> _openExternalUri(Uri uri) async {
  final openedExternally = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (openedExternally) {
    return;
  }

  final openedByPlatform = await launchUrl(
    uri,
    mode: LaunchMode.platformDefault,
  );
  if (openedByPlatform) {
    return;
  }

  throw UnsupportedError('Could not open the link on this device.');
}
