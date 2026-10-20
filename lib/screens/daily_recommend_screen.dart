import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../services/api_service.dart';
import '../state/player_state.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

/// "每日推荐": a deterministic 30-track mix built once per day from the
/// listener's favourite artists plus today's top lists. Cached per day so the
/// list does not change while the day is running.
class DailyRecommendScreen extends StatefulWidget {
  /// Default number of tracks generated each day.
  static const int defaultLimit = 30;

  /// Presets offered in the settings sheet.
  static const List<int> limitOptions = [10, 20, 30, 50, 80, 100];

  static const String _limitKey = 'daily_recommend_limit';

  static Future<int> loadLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_limitKey) ?? defaultLimit;
    return value.clamp(1, 100);
  }

  static Future<void> saveLimit(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_limitKey, value.clamp(1, 100));
  }

  final ApiService api;
  final String platform;
  final List<Song> recentPlays;

  const DailyRecommendScreen({
    super.key,
    required this.api,
    required this.platform,
    this.recentPlays = const [],
  });

  @override
  State<DailyRecommendScreen> createState() => _DailyRecommendScreenState();
}

class _DailyRecommendScreenState extends State<DailyRecommendScreen> {
  static const String _keyPrefix = 'daily_recommend';

  final List<Song> _songs = [];
  int _limit = DailyRecommendScreen.defaultLimit;
  bool _loading = true;
  String? _error;

  DateTime get _today => DateTime.now();

  String get _dateKey =>
      '${_today.year}-${_today.month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';

  String get _cacheKey =>
      '${_keyPrefix}_${widget.platform}_${_dateKey}_$_limit';

  int get _seed =>
      _today.year * 10000 + _today.month * 100 + _today.day;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (widget.platform.isEmpty) {
      setState(() {
        _loading = false;
        _error = '请先选择音源';
      });
      return;
    }

    _limit = await DailyRecommendScreen.loadLimit();
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!refresh) {
      final cached = prefs.getString(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final list = (jsonDecode(cached) as List)
              .whereType<Map<String, dynamic>>()
              .map(Song.fromJson)
              .toList();
          if (list.isNotEmpty && mounted) {
            setState(() {
              _songs
                ..clear()
                ..addAll(list);
              _loading = false;
            });
            return;
          }
        } catch (_) {}
      }
    }

    try {
      final songs = await _build();
      if (!mounted) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(songs);
        _loading = false;
        _error = songs.isEmpty ? '今天没能生成推荐，稍后再试试' : null;
      });
      if (songs.isNotEmpty) {
        await prefs.setString(
          _cacheKey,
          jsonEncode(songs.map((s) => s.toJson()).toList()),
        );
        // Drop previous days so prefs do not grow forever. The limit setting
        // also starts with the same prefix, so it must be skipped explicitly.
        for (final key in prefs.getKeys().toList()) {
          if (key == DailyRecommendScreen._limitKey) continue;
          if (key.startsWith(_keyPrefix) && key != _cacheKey) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '生成失败：$e';
        });
      }
    }
  }

  /// Favourite artists = most frequent artists in recent plays.
  List<String> _favouriteArtists() {
    final counts = <String, int>{};
    for (final song in widget.recentPlays) {
      final artist = song.artist.trim();
      if (artist.isEmpty) continue;
      counts[artist] = (counts[artist] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  bool _artistMatches(String songArtist, String query) {
    final a = songArtist.toLowerCase().replaceAll(' ', '');
    final q = query.toLowerCase().replaceAll(' ', '');
    if (a.isEmpty || q.isEmpty) return false;
    return a.contains(q) || q.contains(a);
  }

  Future<List<Song>> _build() async {
    final rng = Random(_seed);
    final picked = <Song>[];
    final seen = <String>{};

    void add(Song song) {
      if (picked.length >= _limit) return;
      if (song.id.isEmpty) return;
      if (seen.add(song.uniqueKey)) picked.add(song);
    }

    // 1. Songs from artists the listener plays most. Search results are
    //    filtered by artist name, otherwise unrelated tracks sneak in.
    final artists = _favouriteArtists().take(4).toList();
    final perArtist = (_limit / 4).ceil().clamp(6, 20);
    for (final artist in artists) {
      if (picked.length >= _limit) break;
      try {
        final result = await widget.api.search(widget.platform, artist, 1);
        final songs = result.items
            .where((s) => _artistMatches(s.artist, artist))
            .toList()
          ..shuffle(rng);
        for (final song in songs.take(perArtist)) {
          add(song);
        }
      } catch (_) {}
    }

    // 2. Keep walking top lists until the target count is reached (a 100-track
    //    list needs far more sources than a 30-track one). The collection count
    //    is capped so the request fan-out stays reasonable.
    try {
      final groups = await widget.api.fetchToplistGroups(widget.platform);
      final shuffled = [...groups]..shuffle(rng);
      var fetched = 0;
      const maxCollections = 12;
      outer:
      for (final group in shuffled) {
        if (picked.length >= _limit || fetched >= maxCollections) break;
        try {
          final collections =
              await widget.api.fetchToplistGroup(widget.platform, group);
          final picks = [...collections]..shuffle(rng);
          for (final collection in picks) {
            if (picked.length >= _limit || fetched >= maxCollections) {
              break outer;
            }
            fetched++;
            try {
              final songs = await widget.api.fetchCollectionDetail(
                'api/external/toplist-detail',
                collection.platform.isEmpty
                    ? widget.platform
                    : collection.platform,
                collection.id,
                src: collection.src,
              );
              for (final song in ([...songs]..shuffle(rng))) {
                add(song);
                if (picked.length >= _limit) break;
              }
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (_) {}

    // 3. Still short? Reuse tracks the listener already knows.
    if (picked.length < _limit) {
      for (final song in ([...widget.recentPlays]..shuffle(rng))) {
        add(song);
        if (picked.length >= _limit) break;
      }
    }

    picked.shuffle(rng);
    return picked.take(_limit).toList();
  }

  void _playAll() {
    if (_songs.isEmpty) return;
    context.read<PlayerState>().appendAllAndPlay(_songs);
    AppToast.show(context, '已加入队列并开始播放（${_songs.length} 首）');
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the palette (light/dark) changes.
    context.watch<AppSettings>();
    final player = context.watch<PlayerState>();
    final currentKey = player.currentSong?.uniqueKey;

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          '每日推荐',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: '重新生成',
            icon: Icon(Icons.refresh_rounded,
                size: 20, color: AppColors.text2),
            onPressed: _loading ? null : () => _load(refresh: true),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header()),
          // Keep the current list visible while a refresh is running.
          if (_loading && _songs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
              ),
            ),
          if (_songs.isEmpty && _loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                      SizedBox(height: 14),
                      Text(
                        '正在根据你的口味生成…',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.text2),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Text(
                    _error ?? '暂无推荐',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: _songs.length,
              itemBuilder: (context, index) {
                final song = _songs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SongTile(
                    song: song,
                    playing: song.uniqueKey == currentKey,
                    onTap: () => player.playNextAndPlay(song),
                    trailing: IconButton(
                      icon: Icon(Icons.add_circle_outline,
                          size: 20, color: AppColors.accent),
                      onPressed: () {
                        final added = player.appendAll([song]);
                        AppToast.show(
                            context, added == 0 ? '已在播放队列' : '已添加到队列');
                      },
                    ),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _header() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[_today.weekday - 1];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1830), Color(0xFF141A2A)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: kAccentGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${_today.day}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_today.month} 月 ${_today.day} 日 · 周$weekday',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _songs.isEmpty
                            ? '每天 ${_limit} 首，按你的口味生成'
                            : '根据收听口味精选 ${_songs.length} 首',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.text2),
                      ),
                    ],
                  ),
                ),
                if (_songs.isNotEmpty)
                  GestureDetector(
                    onTap: _playAll,
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: kAccentGradient,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              size: 18, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            '播放',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
