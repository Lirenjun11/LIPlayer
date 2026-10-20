import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_quality.dart';
import '../models/lyric_line.dart';
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

  void _wireStreams() {
    _player.playerStateStream.listen((state) {
      final wasPlaying = isPlaying;
      isPlaying = state.playing && state.processingState != ProcessingState.completed;
      // Flush the queue and position when playback pauses or stops.
      if (wasPlaying && !isPlaying) _saveState();
      if (state.processingState == ProcessingState.completed &&
          !_handlingCompletion) {
        _handlingCompletion = true;
        autoNext();
        Future.delayed(const Duration(milliseconds: 300), () {
          _handlingCompletion = false;
        });
      }
      notifyListeners();
    });

    _player.positionStream.listen((p) {
      position = p;
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
      notifyListeners();
    });
  }

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
    }
  }

  void clearPlaylist() {
    playlist = [];
    currentIndex = -1;
    currentSong = null;
    lyrics = const [];
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
    isLoadingUrl = true;
    notifyListeners();

    final song = currentSong!;
    try {
      final mediaItem = MediaItem(
        id: song.uniqueKey,
        title: song.title.isEmpty ? '未知歌曲' : song.title,
        artist: song.artist,
        album: song.album.isEmpty ? null : song.album,
        artUri: song.artwork.isNotEmpty ? Uri.parse(song.artwork) : null,
      );
      final usedUrl = await _loadBestSource(song, mediaItem, token);
      if (token != _playToken) return;
      if (usedUrl == null) throw ApiException('获取播放地址失败');
      song.playUrl = usedUrl;
      if (restoreSeek != null && restoreSeek > Duration.zero) {
        try {
          await _player.seek(restoreSeek);
          position = restoreSeek;
        } catch (_) {}
      }
      _hasSource = true;
      unawaited(_player.play());
      _recordRecent(song);
      _fetchLyric(song, token);
      unawaited(_fetchSongDetail(song, token));
      _prefetchNext();
      _saveState();
    } on ApiException catch (e) {
      if (token == _playToken) onError?.call(e.message);
    } catch (e) {
      if (token == _playToken) onError?.call('播放失败: $e');
    } finally {
      if (token == _playToken) {
        isLoadingUrl = false;
        notifyListeners();
      }
    }
  }

  /// Resolves a playable source, stepping down one quality tier at a time
  /// (lossless -> high -> standard) when the current tier cannot be played.
  /// The user's chosen quality is left untouched.
  Future<String?> _loadBestSource(Song song, MediaItem tag, int token) async {
    // Prefetched URL first: instant track changes, and it keeps working when
    // iOS suspends the app right after the previous track ends.
    final cached = _urlCache[song.uniqueKey];
    if (cached != null && cached.isNotEmpty) {
      try {
        return await _loadSourceWithFallback(cached, tag);
      } catch (_) {
        _urlCache.remove(song.uniqueKey);
      }
    }

    final ladder = <AudioQuality>[];
    for (var i = quality.index; i >= 0; i--) {
      ladder.add(AudioQuality.values[i]);
    }

    for (final tier in ladder) {
      if (token != _playToken) return null;
      String url;
      try {
        url = await api.fetchPlayUrl(
          song.platform,
          song.id,
          song.title,
          song.artist,
          quality: tier,
          source: song.source,
        );
      } catch (_) {
        continue;
      }
      if (url.isEmpty) continue;

      try {
        final used = await _loadSourceWithFallback(url, tag);
        if (token != _playToken) return null;
        if (tier != quality) {
          onError?.call('${quality.label}音源不可用，已自动降级为${tier.label}');
        }
        return used;
      } catch (e) {
        debugPrint('[player] ${tier.name} source failed: $e');
      }
    }
    return null;
  }

  /// Loads [url] into the player. Some music CDNs serve HTTPS with
  /// certificates iOS refuses to trust (error -1202), while plain HTTP from
  /// the same host works, so fall back to the other scheme before giving up.
  Future<String> _loadSourceWithFallback(String url, MediaItem tag) async {
    final candidates = <String>[url];
    if (url.startsWith('https://')) {
      candidates.add(url.replaceFirst('https://', 'http://'));
    } else if (url.startsWith('http://')) {
      candidates.add(url.replaceFirst('http://', 'https://'));
    }

    Object? lastError;
    for (final candidate in candidates) {
      try {
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(candidate), tag: tag),
        );
        return candidate;
      } catch (e) {
        lastError = e;
        debugPrint('[player] source failed: $candidate ($e)');
      }
    }
    if (lastError != null) throw lastError;
    throw ApiException('播放地址不可用');
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

  void prev() {
    if (playlist.isEmpty) return;
    var idx = currentIndex - 1;
    if (idx < 0) idx = playlist.length - 1;
    playAt(idx);
  }

  void next() => autoNext();

  /// Warms the URL of the upcoming track so the next transition does not
  /// depend on a network round trip (important on the iOS lock screen).
  void _prefetchNext() {
    if (playlist.length < 2) return;
    final nextIndex = (currentIndex + 1) % playlist.length;
    if (nextIndex == currentIndex) return;
    final next = playlist[nextIndex];
    if (_urlCache.containsKey(next.uniqueKey)) return;
    unawaited(() async {
      try {
        final url = await api.fetchPlayUrl(
          next.platform,
          next.id,
          next.title,
          next.artist,
          quality: quality,
          source: next.source,
        );
        if (url.isNotEmpty) _urlCache[next.uniqueKey] = url;
      } catch (_) {}
    }());
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
    _saveState();
    _player.dispose();
    super.dispose();
  }
}
