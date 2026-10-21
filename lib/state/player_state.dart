import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_quality.dart';
import '../models/lyric_line.dart';
import '../models/music_platform.dart';
import '../models/song.dart';
import '../services/api_service.dart';

enum PlayMode { order, random, single }

extension PlayModeLabel on PlayMode {
  String get label => switch (this) {
        PlayMode.order => '顺序',
        PlayMode.random => '随机',
        PlayMode.single => '单曲',
      };
}

/// Playback engine: wraps just_audio and mirrors the behaviour of the Vue page
/// (queue management, play modes, lyrics sync, session persistence).
class PlayerState extends ChangeNotifier {
  static const String _stateKey = 'music_player_state';
  static const String _qualityKey = 'music_player_quality';
  static const String _recentKey = 'music_player_recent';
  static const int recentLimit = 100;

  final ApiService api;
  final AudioPlayer _player = AudioPlayer();

  PlayerState(this.api) {
    _wireStreams();
    // Coming back from the background: the engine may have skipped tracks via
    // the lock screen while Dart was paused, so re-read the live index.
    _lifecycle = AppLifecycleListener(onResume: _reconcileIndex);
  }

  late final AppLifecycleListener _lifecycle;

  void _reconcileIndex() {
    final liveIndex = _player.currentIndex;
    if (liveIndex != null && liveIndex != _windowCurrent) {
      _onPlayerIndexChanged(liveIndex);
    }
  }

  // ---- Observable state ----------------------------------------------------
  List<Song> playlist = [];
  int currentIndex = -1;
  Song? currentSong;
  bool isPlaying = false;
  bool isLoadingUrl = false;
  PlayMode playMode = PlayMode.order;
  AudioQuality quality = AudioQuality.standard;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  List<LyricLine> lyrics = const [];
  int currentLyricIndex = -1;
  bool lyricsLoading = false;

  /// Most recent tracks, newest first, capped at [recentLimit].
  List<Song> recentPlays = [];

  /// Notifies the UI about transient errors (shown as a snackbar).
  void Function(String message)? onError;

  /// Called when playback had to switch to another music source because the
  /// current one disappeared, so the home page can follow along.
  void Function(String platform)? onPlatformChanged;

  int _playToken = 0;
  int _lyricToken = 0;
  bool _handlingCompletion = false;
  bool _hasSource = false;

  /// Position to seek to once the restored track gets an audio source.
  Duration? _pendingSeek;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Resolved stream URLs keyed by `song.uniqueKey`. Kept so the transition to
  /// the next track (including from the iOS lock screen) needs no network.
  final Map<String, String> _urlCache = {};

  /// Decoded lengths reported by the audio engine, keyed by `song.uniqueKey`.
  final Map<String, Duration> _actualDurations = {};

  /// Playlist indices currently loaded into the engine (prev..next window),
  /// and the position of the playing track inside that window.
  List<int> _windowIndexes = [];
  int _windowCurrent = 0;
  bool _rebuilding = false;

  /// Songs that already failed to resolve in this session; used to stop the
  /// auto-skip loop once the whole queue has been tried.
  final Set<String> _failedKeys = {};
  int _consecutiveFailures = 0;
  bool _disposed = false;

  /// Cached platform list used to detect a dead music source.
  List<MusicPlatform>? _platformsSnapshot;
  DateTime _platformsFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _wireStreams() {
    _player.playerStateStream.listen((state) {
      final wasPlaying = isPlaying;
      isPlaying = state.playing && state.processingState != ProcessingState.completed;
      // Flush the queue and position when playback pauses or stops.
      if (wasPlaying && !isPlaying) _saveState();
      if (state.processingState == ProcessingState.completed &&
          !_handlingCompletion &&
          !_rebuilding) {
        _handlingCompletion = true;
        autoNext();
        Future.delayed(const Duration(milliseconds: 300), () {
          _handlingCompletion = false;
        });
      }
      notifyListeners();
    });

    // Native transitions (auto-advance, lock-screen / headset skip).
    _player.currentIndexStream.listen(_onPlayerIndexChanged);

    _player.positionStream.listen((p) {
      position = p;
      // Safety net: the lock-screen skip on iOS can advance the engine without
      // the currentIndex event reaching Dart (app suspended / resumed), so the
      // UI would keep showing the previous track. Reconcile on every tick.
      final liveIndex = _player.currentIndex;
      if (liveIndex != null && liveIndex != _windowCurrent) {
        _onPlayerIndexChanged(liveIndex);
      }
      _updateLyricIndex();
      // Persist progress at most every 5 seconds so a restart resumes near
      // the same spot without hammering prefs on every tick.
      if (isPlaying &&
          DateTime.now().difference(_lastSavedAt).inSeconds >= 5) {
        _lastSavedAt = DateTime.now();
        _saveState();
      }
      notifyListeners();
    });

    _player.durationStream.listen((d) {
      duration = d ?? Duration.zero;
      // Remember the real decoded length: the metadata duration from the API
      // is often rounded or plainly wrong.
      final key = currentSong?.uniqueKey;
      if (key != null && duration > Duration.zero) {
        _actualDurations[key] = duration;
      }
      notifyListeners();
    });
  }

  /// Real duration once the track has been decoded, metadata before that.
  Duration durationOf(Song song) =>
      _actualDurations[song.uniqueKey] ?? song.durationValue;

  bool get hasCurrent => currentSong != null;

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    final value = position.inMilliseconds / total * 100;
    return value.clamp(0, 100).toDouble();
  }

  // ---- Queue ---------------------------------------------------------------

  void addToPlaylist(Song song) {
    final exists = playlist.any((s) => s.uniqueKey == song.uniqueKey);
    if (exists) {
      onError?.call('已在播放队列');
      return;
    }
    playlist.add(song);
    if (playlist.length == 1) {
      playAt(0);
    } else {
      _saveState();
      notifyListeners();
    }
  }

  void removeFromPlaylist(int index) {
    if (index < 0 || index >= playlist.length) return;
    final wasCurrent = index == currentIndex;
    playlist.removeAt(index);
    if (playlist.isEmpty) {
      currentIndex = -1;
      currentSong = null;
      _hasSource = false;
      _player.stop();
      _saveState();
      notifyListeners();
      return;
    }
    if (wasCurrent) {
      final next = index >= playlist.length ? playlist.length - 1 : index;
      playAt(next);
    } else {
      if (index < currentIndex) currentIndex--;
      _saveState();
      notifyListeners();
      // The removed track may sit inside the engine's window.
      unawaited(_refreshWindow());
    }
  }

  void clearPlaylist() {
    playlist = [];
    currentIndex = -1;
    currentSong = null;
    lyrics = const [];
    _windowIndexes = [];
    _windowCurrent = 0;
    _hasSource = false;
    _player.stop();
    SharedPreferences.getInstance().then((p) => p.remove(_stateKey));
    notifyListeners();
  }

  void replacePlaylist(List<Song> songs) {
    playlist = List<Song>.from(songs);
    notifyListeners();
  }

  /// Plays [song] by inserting it right after the current track, without
  /// clearing the rest of the queue. If it is already queued, jumps to it.
  Future<void> playNextAndPlay(Song song) async {
    final existing =
        playlist.indexWhere((s) => s.uniqueKey == song.uniqueKey);
    if (existing >= 0) {
      await playAt(existing);
      return;
    }
    final insertAt = currentIndex < 0 ? playlist.length : currentIndex + 1;
    playlist.insert(insertAt, song);
    await playAt(insertAt);
  }

  /// Appends the songs that are not queued yet. Returns how many were added.
  int appendAll(List<Song> songs) {
    final keys = playlist.map((s) => s.uniqueKey).toSet();
    final added = <Song>[];
    for (final song in songs) {
      if (keys.add(song.uniqueKey)) added.add(song);
    }
    if (added.isEmpty) return 0;
    playlist.addAll(added);
    _saveState();
    notifyListeners();
    // Fill the window when the queue was previously exhausted.
    unawaited(_maybeExtendWindow());
    return added.length;
  }

  /// Appends [songs] to the queue (keeping the current one) and plays the
  /// first newly added track.
  Future<void> appendAllAndPlay(List<Song> songs) async {
    final startIndex = playlist.length;
    appendAll(songs);
    if (playlist.length > startIndex) {
      await playAt(startIndex);
    } else if (songs.isNotEmpty && playlist.isNotEmpty) {
      final index =
          playlist.indexWhere((s) => s.uniqueKey == songs.first.uniqueKey);
      if (index >= 0) await playAt(index);
    }
  }

  // ---- Recently played -----------------------------------------------------

  void _recordRecent(Song song) {
    recentPlays.removeWhere((s) => s.uniqueKey == song.uniqueKey);
    recentPlays.insert(0, song);
    if (recentPlays.length > recentLimit) {
      recentPlays = recentPlays.sublist(0, recentLimit);
    }
    _saveRecent();
    notifyListeners();
  }

  void clearRecent() {
    recentPlays = [];
    SharedPreferences.getInstance()
        .then((prefs) => prefs.remove(_recentKey));
    notifyListeners();
  }

  Future<void> _saveRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _recentKey,
        jsonEncode(recentPlays.map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ---- Playback ------------------------------------------------------------

  MediaItem _mediaItem(Song song) => MediaItem(
        id: song.uniqueKey,
        title: song.title.isEmpty ? '未知歌曲' : song.title,
        artist: song.artist,
        album: song.album.isEmpty ? null : song.album,
        artUri: song.artwork.isNotEmpty ? Uri.parse(song.artwork) : null,
      );

  /// Resolves a stream URL (cached when possible). `strict` walks the quality
  /// ladder down so the current track still plays when its tier is unavailable.
  Future<String?> _resolveUrl(Song song, int token,
      {bool strict = false}) async {
    final cached = _urlCache[song.uniqueKey];
    if (cached != null && cached.isNotEmpty) return cached;

    final tiers = <AudioQuality>[quality];
    if (strict) {
      for (var i = quality.index - 1; i >= 0; i--) {
        tiers.add(AudioQuality.values[i]);
      }
    }

    for (final tier in tiers) {
      if (token != _playToken) return null;
      try {
        final url = await api.fetchPlayUrl(
          song.platform,
          song.id,
          song.title,
          song.artist,
          quality: tier,
          source: song.source,
        );
        if (url.isEmpty) continue;
        _urlCache[song.uniqueKey] = url;
        if (strict && tier != quality) {
          onError?.call('${quality.label}音源不可用，已自动降级为${tier.label}');
        }
        return url;
      } catch (_) {}
    }
    return null;
  }

  /// Hands a (prev..next) window to the audio engine as a native playlist.
  /// Neighbours in the playlist are what make the iOS lock-screen skip buttons
  /// appear and let playback continue while the app is suspended.
  Future<bool> _loadWindow(int index, int token,
      {Duration initialPosition = Duration.zero}) async {
    const radius = 2;
    final start = (index - radius).clamp(0, playlist.length - 1);
    final end = (index + radius).clamp(0, playlist.length - 1);

    final sources = <AudioSource>[];
    final indexes = <int>[];
    var currentPos = -1;

    for (var i = start; i <= end; i++) {
      final song = playlist[i];
      final isCurrent = i == index;
      final url = await _resolveUrl(song, token, strict: isCurrent);
      if (token != _playToken) return false;
      if (url == null || url.isEmpty) {
        if (isCurrent) return false;
        continue;
      }
      if (isCurrent) currentPos = sources.length;
      sources.add(AudioSource.uri(Uri.parse(url), tag: _mediaItem(song)));
      indexes.add(i);
    }

    if (currentPos < 0 || sources.isEmpty) return false;

    try {
      await _player.setAudioSources(
        sources,
        initialIndex: currentPos,
        initialPosition: initialPosition,
      );
    } catch (e) {
      debugPrint('[player] window load failed: $e');
      return false;
    }
    _windowIndexes = indexes;
    _windowCurrent = currentPos;
    _hasSource = true;
    return true;
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= playlist.length) return;
    // Only the restored track resumes from the saved position.
    final restoreSeek = index == currentIndex ? _pendingSeek : null;
    _pendingSeek = null;
    final token = ++_playToken;

    currentIndex = index;
    currentSong = playlist[index];
    lyrics = const [];
    lyricsLoading = true;
    currentLyricIndex = -1;
    position = restoreSeek ?? Duration.zero;
    duration =
        _actualDurations[currentSong!.uniqueKey] ?? currentSong!.durationValue;
    isLoadingUrl = true;
    notifyListeners();

    try {
      final ok = await _loadWindow(index, token,
          initialPosition: restoreSeek ?? Duration.zero);
      if (token != _playToken) return;
      if (!ok) {
        _hasSource = false;
        _handlePlayFailure(currentSong!, token);
        return;
      }
      _failedKeys.clear();
      _consecutiveFailures = 0;
      unawaited(_player.play());
      _recordRecent(currentSong!);
      _fetchLyric(currentSong!, token);
      unawaited(_fetchSongDetail(currentSong!, token));
      _saveState();
    } catch (e) {
      if (token == _playToken) onError?.call('播放失败: $e');
    } finally {
      if (token == _playToken) {
        isLoadingUrl = false;
        notifyListeners();
      }
    }
  }

  /// A track could not be resolved (dead source, removed song, network...).
  /// Skip to the next one, but stop once every song has been tried so a dead
  /// music source cannot put the app in an endless retry loop.
  Future<void> _handlePlayFailure(Song song, int token) async {
    _failedKeys.add(song.uniqueKey);
    _consecutiveFailures++;
    final total = playlist.length;

    // A couple of failures in a row may mean the whole source disappeared.
    if (_consecutiveFailures >= 2 && _consecutiveFailures <= 4) {
      final healed = await _tryPlatformHeal(song, token);
      if (_disposed || token != _playToken) return;
      if (healed) return;
    }

    if (total <= 1 || _failedKeys.length >= total) {
      _failedKeys.clear();
      _consecutiveFailures = 0;
      onError?.call('播放失败：当前音乐源可能已失效，请切换音源');
      notifyListeners();
      return;
    }

    if (playMode == PlayMode.single) {
      onError?.call('《${song.title}》播放失败');
      notifyListeners();
      return;
    }

    onError?.call('《${song.title}》播放失败，已自动跳过');
    final nextIndex = (currentIndex + 1) % total;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_disposed || token != _playToken) return;
      playAt(nextIndex);
    });
  }

  /// Detects a dead music source and moves the current track to a working one.
  /// Returns true when playback was restarted with a substituted song.
  Future<bool> _tryPlatformHeal(Song song, int token) async {
    final platforms = await _availablePlatforms();
    if (platforms.isEmpty) return false;
    // Still advertised by the backend → treat as a per-track problem.
    if (platforms.any((p) => p.platform == song.platform)) return false;

    final target = platforms.first;
    final replacement = await _remapSong(song);
    if (_disposed || token != _playToken) return false;

    if (replacement == null) {
      onError?.call('「${target.platform}」可用，但未找到《${song.title}》');
      return false;
    }

    final index = playlist.indexWhere((s) => s.uniqueKey == song.uniqueKey);
    if (index < 0) return false;

    playlist[index] = replacement;
    _failedKeys.clear();
    _consecutiveFailures = 0;
    _saveState();
    onPlatformChanged?.call(target.platform);
    onError?.call('音乐源已失效，已切换到「${target.platform}」');
    await playAt(index);
    return true;
  }

  Future<List<MusicPlatform>> _availablePlatforms() async {
    final fresh =
        DateTime.now().difference(_platformsFetchedAt).inMinutes < 5;
    if (fresh && _platformsSnapshot != null) return _platformsSnapshot!;
    try {
      final list = await api.fetchPlatforms();
      _platformsSnapshot = list;
      _platformsFetchedAt = DateTime.now();
      return list;
    } catch (_) {
      return _platformsSnapshot ?? const [];
    }
  }

  /// Finds the same track on another platform, rejecting covers/live versions
  /// by comparing title, artist and length.
  Future<Song?> _remapSong(Song song) async {
    final platforms = await _availablePlatforms();
    final others =
        platforms.where((p) => p.platform != song.platform).toList();
    if (others.isEmpty || song.title.trim().isEmpty) return null;

    final query = '${song.title} ${song.artist}'.trim();
    final wanted = song.durationValue.inMilliseconds;

    for (final platform in others) {
      try {
        final result = await api.search(platform.platform, query, 1);
        for (final candidate in result.items.take(12)) {
          if (!_titleMatches(candidate.title, song.title)) continue;
          if (!_artistMatches(candidate.artist, song.artist)) continue;
          final length = candidate.durationValue.inMilliseconds;
          if (wanted > 0 && length > 0 && (length - wanted).abs() > 15000) {
            continue;
          }
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_()（）\[\]【】·,，.。]'), '');

  static bool _titleMatches(String a, String b) {
    final x = _normalize(a);
    final y = _normalize(b);
    if (x.isEmpty || y.isEmpty) return false;
    return x.contains(y) || y.contains(x);
  }

  static bool _artistMatches(String a, String b) {
    final split = RegExp(r'[、,，&/]');
    final left = a
        .split(split)
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    final right = b
        .split(split)
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    for (final x in left) {
      for (final y in right) {
        if (x.contains(y) || y.contains(x)) return true;
      }
    }
    return false;
  }

  /// Keeps Dart state in sync when the engine advances by itself: automatic
  /// track transitions and the lock-screen / headset skip buttons.
  void _onPlayerIndexChanged(int? playerIndex) {
    if (playerIndex == null) return;
    if (playerIndex < 0 || playerIndex >= _windowIndexes.length) return;

    final songIndex = _windowIndexes[playerIndex];
    if (songIndex < 0 || songIndex >= playlist.length) return;
    // Compare against the playlist index, not the cached window position: the
    // cache can be stale after a native skip while the app was suspended.
    if (songIndex == currentIndex) {
      _windowCurrent = playerIndex;
      return;
    }
    _windowCurrent = playerIndex;

    currentIndex = songIndex;
    currentSong = playlist[songIndex];
    position = Duration.zero;
    duration =
        _actualDurations[currentSong!.uniqueKey] ?? currentSong!.durationValue;
    lyrics = const [];
    lyricsLoading = true;
    currentLyricIndex = -1;
    notifyListeners();

    _recordRecent(currentSong!);
    _fetchLyric(currentSong!, _playToken);
    unawaited(_fetchSongDetail(currentSong!, _playToken));
    _saveState();
    unawaited(_maybeExtendWindow());
  }

  /// Rebuilds the window once the current track reaches its edge, resuming at
  /// the same position so the re-load is inaudible.
  Future<void> _maybeExtendWindow() async {
    if (!_hasSource || _rebuilding) return;
    final pos = _windowIndexes.indexOf(currentIndex);
    if (pos < 0) return;
    if (pos > 0 && pos < _windowIndexes.length - 1) return;

    _rebuilding = true;
    try {
      final token = _playToken;
      final resume = position;
      final ok = await _loadWindow(currentIndex, token, initialPosition: resume);
      if (!ok || token != _playToken) return;
      await _player.play();
    } finally {
      _rebuilding = false;
    }
  }

  /// Rebuilds the window in place after the queue was edited.
  Future<void> _refreshWindow() async {
    if (!_hasSource || currentSong == null || _rebuilding) return;
    _rebuilding = true;
    try {
      final token = _playToken;
      final resume = position;
      final ok = await _loadWindow(currentIndex, token, initialPosition: resume);
      if (!ok || token != _playToken) return;
      await _player.play();
    } finally {
      _rebuilding = false;
    }
  }

  void togglePlay() {
    if (currentSong == null) return;
    if (_player.playing) {
      _player.pause();
    } else if (!_hasSource) {
      playAt(currentIndex);
    } else {
      _player.play();
    }
  }

  Future<void> prev() async {
    if (playlist.isEmpty) return;
    final pos = _windowIndexes.indexOf(currentIndex);
    if (pos > 0) {
      await _player.seekToPrevious();
      return;
    }
    final target = currentIndex - 1 < 0 ? playlist.length - 1 : currentIndex - 1;
    await playAt(target);
  }

  Future<void> next() async {
    if (playlist.isEmpty) return;
    if (playMode == PlayMode.single) {
      await playAt(currentIndex);
      return;
    }
    if (playMode == PlayMode.random) {
      autoNext();
      return;
    }
    final pos = _windowIndexes.indexOf(currentIndex);
    if (pos >= 0 && pos < _windowIndexes.length - 1) {
      await _player.seekToNext();
      return;
    }
    final target = currentIndex + 1 >= playlist.length ? 0 : currentIndex + 1;
    await playAt(target);
  }

  void autoNext() {
    if (playlist.isEmpty) return;
    if (playMode == PlayMode.single) {
      playAt(currentIndex);
      return;
    }
    int idx;
    if (playMode == PlayMode.random) {
      idx = (DateTime.now().microsecondsSinceEpoch % playlist.length);
    } else {
      idx = currentIndex + 1;
      if (idx >= playlist.length) idx = 0;
    }
    playAt(idx);
  }

  /// Switches playback quality and reloads the current track in place.
  Future<void> setQuality(AudioQuality next) async {
    if (quality == next) return;
    quality = next;
    // Cached URLs belong to the previous quality tier.
    _urlCache.clear();
    _saveState();
    // Stored separately so clearing the queue does not drop the preference.
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_qualityKey, next.name));
    notifyListeners();
    onError?.call('音质已切换为「${next.label}」');
    if (currentSong != null && _hasSource) {
      _pendingSeek = position;
      await playAt(currentIndex);
    }
  }

  void togglePlayMode() {
    final modes = PlayMode.values;
    playMode = modes[(playMode.index + 1) % modes.length];
    onError?.call(playMode.label == '顺序'
        ? '顺序播放'
        : playMode.label == '随机'
            ? '随机播放'
            : '单曲循环');
    _saveState();
    notifyListeners();
  }

  Future<void> seek(Duration to) async {
    final clamped = to < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && to > duration ? duration : to);
    position = clamped;
    _updateLyricIndex();
    notifyListeners();
    try {
      await _player.seek(clamped);
    } catch (_) {}
  }

  void seekToLyric(int index) {
    if (index < 0 || index >= lyrics.length) return;
    seek(lyrics[index].time);
  }

  // ---- Lyrics --------------------------------------------------------------

  Future<void> _fetchLyric(Song song, int token) async {
    final lyricToken = ++_lyricToken;
    lyricsLoading = true;
    lyrics = const [];
    currentLyricIndex = -1;
    notifyListeners();
    try {
      final lines = await api.fetchLyricLines(
        song.platform,
        song.id,
        title: song.title,
        artist: song.artist,
      );
      if (lyricToken != _lyricToken || token != _playToken) return;
      lyrics = lines;
    } catch (_) {
      if (lyricToken == _lyricToken) lyrics = const [];
    } finally {
      if (lyricToken == _lyricToken) {
        lyricsLoading = false;
        _updateLyricIndex();
        notifyListeners();
      }
    }
  }

  void _updateLyricIndex() {
    if (lyrics.isEmpty) return;
    // Unsynchronised lyrics have no timestamps; keep them unhighlighted.
    if (lyrics.every((line) => line.time == Duration.zero)) return;
    final ms = position.inMilliseconds;
    var idx = -1;
    for (var i = 0; i < lyrics.length; i++) {
      if (ms >= lyrics[i].time.inMilliseconds - 50) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != currentLyricIndex) {
      currentLyricIndex = idx;
    }
  }

  Future<void> _fetchSongDetail(Song song, int token) async {
    try {
      final detail = await api.fetchSongDetail(song.platform, song.id);
      if (token != _playToken) return;
      final artwork = detail['artwork'];
      if (artwork != null && '${artwork}'.isNotEmpty && song.artwork.isEmpty) {
        song.artwork = Song.normalizeUrl('$artwork');
        notifyListeners();
      }
      final dur = detail['duration'];
      if (dur != null && duration <= Duration.zero) {
        duration = Song(
          id: song.id,
          title: song.title,
          artist: song.artist,
          platform: song.platform,
          duration: dur is int ? dur : int.tryParse('$dur') ?? 0,
        ).durationValue;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ---- Persistence ---------------------------------------------------------

  Future<void> saveState() async {
    await _saveState();
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (playlist.isEmpty) {
        await prefs.remove(_stateKey);
        return;
      }
      await prefs.setString(
        _stateKey,
        jsonEncode({
          'playlist': playlist.map((s) => s.toJson()).toList(),
          'currentIndex': currentIndex,
          'playMode': playMode.name,
          'quality': quality.name,
          'positionMs': position.inMilliseconds,
          'durationMs': duration.inMilliseconds,
        }),
      );
    } catch (_) {}
  }

  Future<void> restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Quality is restored even when there is no saved queue.
      final savedQuality = prefs.getString(_qualityKey);
      if (savedQuality != null && savedQuality.isNotEmpty) {
        quality = AudioQuality.values.firstWhere(
          (q) => q.name == savedQuality,
          orElse: () => AudioQuality.standard,
        );
      }

      // Recently played list is independent from the queue as well.
      final recentRaw = prefs.getString(_recentKey);
      if (recentRaw != null && recentRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(recentRaw);
          if (decoded is List) {
            recentPlays = decoded
                .whereType<Map<String, dynamic>>()
                .map(Song.fromJson)
                .take(recentLimit)
                .toList();
          }
        } catch (_) {}
      }

      final raw = prefs.getString(_stateKey);
      if (raw == null || raw.isEmpty) {
        notifyListeners();
        return;
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['playlist'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList();
      if (list.isEmpty) return;
      playlist = list;
      currentIndex = (data['currentIndex'] as num?)?.toInt() ?? -1;
      playMode = PlayMode.values.firstWhere(
        (m) => m.name == data['playMode'],
        orElse: () => PlayMode.order,
      );
      // Backward compatibility with the older combined payload.
      if (savedQuality == null || savedQuality.isEmpty) {
        quality = AudioQuality.values.firstWhere(
          (q) => q.name == data['quality'],
          orElse: () => AudioQuality.standard,
        );
      }
      if (currentIndex < 0 || currentIndex >= playlist.length) {
        currentIndex = -1;
      } else {
        currentSong = playlist[currentIndex];
      }
      final savedMs = (data['positionMs'] as num?)?.toInt() ?? 0;
      final savedDuration = (data['durationMs'] as num?)?.toInt() ?? 0;
      if (savedDuration > 0) {
        duration = Duration(milliseconds: savedDuration);
      }
      if (currentSong != null && savedMs > 0) {
        position = Duration(milliseconds: savedMs);
        _pendingSeek = position;
      }
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    _saveState();
    _player.dispose();
    super.dispose();
  }
}
