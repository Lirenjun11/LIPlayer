import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_quality.dart';
import '../models/lyric_line.dart';
import '../models/music_collection.dart';
import '../models/music_platform.dart';
import '../models/song.dart';

/// Thrown for any API-level failure (network, auth, business error).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// A page of results with an "end reached" flag.
class Paged<T> {
  final List<T> items;
  final bool isEnd;
  Paged(this.items, this.isEnd);
}

/// Backend client. Ports the request/auth logic of the Vue reference page:
/// the login endpoint issues an HttpOnly cookie (`musicplayer_auth`) that must
/// be attached to every subsequent request.
class ApiService {
  static const String baseUrl = 'https://m.lrj.ccwu.cc/';
  static const String _cookieName = 'musicplayer_auth';
  static const String _tokenKey = 'music_player_auth_token';

  final http.Client _client;
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  String _token = '';
  bool _authDisabled = false;

  /// Invoked when the session becomes invalid so the UI can return to login.
  void Function()? onUnauthorized;

  String get token => _token;
  bool get isAuthenticated => _token.isNotEmpty || _authDisabled;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey) ?? '';
  }

  Future<void> _saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token.isEmpty) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  Future<void> logout() async {
    _authDisabled = false;
    await _saveToken('');
  }

  /// Logs in and stores the issued cookie token.
  Future<void> login(String username, String password) async {
    final uri = Uri.parse('${baseUrl}api/auth/login');
    late final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ApiException('登录请求失败: $e');
    }

    final body = _decode(res.body);
    if (res.statusCode != 200) {
      throw ApiException(_message(body) ?? '登录失败(${res.statusCode})');
    }
    // Backend without auth enabled.
    if (body is Map && body['enabled'] == false) {
      _authDisabled = true;
      await _saveToken('');
      return;
    }
    final token = _extractCookie(res.headers['set-cookie']);
    if (token.isEmpty) {
      throw ApiException('登录响应未返回凭证');
    }
    _authDisabled = false;
    await _saveToken(token);
  }

  String _extractCookie(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final match = RegExp('$_cookieName=([^;\\s]+)').firstMatch(raw);
    if (match == null) return '';
    var value = match.group(1)!.trim();
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {}
    return value;
  }

  /// Performs an authenticated GET and unwraps `{ code: 0, data: ... }`.
  Future<dynamic> _get(String path, Map<String, dynamic> params,
      {bool retried = false}) async {
    if (!_authDisabled && _token.isEmpty) {
      throw ApiException('未登录');
    }
    final query = params.map((k, v) => MapEntry(k, '$v'));
    final uri = Uri.parse(baseUrl + path).replace(queryParameters: query);
    final headers = <String, String>{};
    if (_token.isNotEmpty) {
      headers['Cookie'] = '$_cookieName=$_token';
    }

    late final http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ApiException('网络请求失败: $e');
    }

    final body = _decode(res.body);
    final expired = res.statusCode == 401 || (body is Map && body['code'] == 401);
    if (expired) {
      if (!retried && _token.isNotEmpty) {
        // Token may have been rotated server-side; drop it and retry once.
        await _saveToken('');
        onUnauthorized?.call();
      }
      throw ApiException('登录已失效，请重新登录');
    }

    if (body is Map && body['code'] == 0) {
      return body['data'];
    }
    throw ApiException(_message(body) ?? '请求失败');
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String? _message(dynamic body) {
    if (body is Map) {
      final msg = body['message'] ?? body['msg'];
      if (msg != null && '$msg'.isNotEmpty) return '$msg';
    }
    return null;
  }

  List<dynamic> _asList(dynamic data, List<String> keys) {
    if (data is List) return data;
    if (data is Map) {
      for (final k in keys) {
        final v = data[k];
        if (v is List) return v;
      }
    }
    return const [];
  }

  bool _asEnd(dynamic data) {
    if (data is Map) return data['isEnd'] == true;
    return false;
  }

  // ---- Endpoints -----------------------------------------------------------

  Future<List<MusicPlatform>> fetchPlatforms() async {
    final data = await _get('api/external/plugins', {});
    return _asList(data, ['data'])
        .whereType<Map<String, dynamic>>()
        .map(MusicPlatform.fromJson)
        .toList();
  }

  /// Returns the toplist group titles for a platform.
  Future<List<String>> fetchToplistGroups(String platform) async {
    final data = await _get('api/external/toplist', {'platform': platform});
    return _asList(data, ['data', 'topList'])
        .map((e) => '${(e as Map)['title'] ?? ''}')
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Future<List<MusicCollection>> fetchToplistGroup(
      String platform, String group) async {
    final data = await _get('api/external/toplist-group', {
      'platform': platform,
      'group': group,
    });
    return _asList(data, ['data', 'topList'])
        .whereType<Map<String, dynamic>>()
        .map((e) => MusicCollection.fromJson(e, platform: platform))
        .toList();
  }

  Future<Paged<MusicCollection>> fetchSheets(
      String platform, int page) async {
    final data = await _get('api/external/sheets', {
      'platform': platform,
      'tag': '热门',
      'page': page,
    });
    final items = _asList(data, ['data', 'musicList'])
        .whereType<Map<String, dynamic>>()
        .map((e) => MusicCollection.fromJson(e, platform: platform))
        .toList();
    return Paged(items, _asEnd(data));
  }

  Future<Paged<Song>> search(
      String platform, String keyword, int page) async {
    final data = await _get('api/external/search', {
      'platform': platform,
      'keyword': keyword,
      'page': page,
      'type': 'music',
    });
    final items = _asList(data, ['data', 'musicList'])
        .whereType<Map<String, dynamic>>()
        .map((e) => Song.fromJson(e, platform: platform))
        .toList();
    return Paged(items, _asEnd(data));
  }

  /// Fetches a collection (sheet / toplist) detail.
  ///
  /// Multi-source plugins need the upstream `src` echoed back, and each track
  /// carries its own `source` which must be forwarded to `play-url`.
  Future<List<Song>> fetchCollectionDetail(
    String endpoint,
    String platform,
    String id, {
    String src = '',
  }) async {
    final data = await _get(endpoint, {
      'platform': platform,
      'id': id,
      'page': 1,
      if (src.isNotEmpty) 'src': src,
    });
    final responseSrc =
        (data is Map && data['src'] != null) ? '${data['src']}' : src;
    return _asList(data, ['data', 'musicList'])
        .whereType<Map<String, dynamic>>()
        .map((e) => Song.fromJson(e, platform: platform, source: responseSrc))
        .toList();
  }

  /// Resolves a stream URL. Plugins disagree on the accepted `quality`
  /// values, so each tier walks its fallback chain. For lossless tiers we
  /// keep looking while the plugin silently downgrades to MP3.
  Future<String> fetchPlayUrl(
    String platform,
    String id,
    String title,
    String artist, {
    AudioQuality quality = AudioQuality.standard,
    String source = '',
  }) async {
    String? downgraded;
    for (final value in quality.candidates) {
      String url;
      try {
        url =
            await _requestPlayUrl(platform, id, title, artist, value, source);
      } catch (_) {
        continue;
      }
      if (url.isEmpty) continue;
      if (quality == AudioQuality.lossless && !_isLossless(url)) {
        downgraded ??= url;
        continue;
      }
      return url;
    }
    return quality == AudioQuality.lossless ? (downgraded ?? '') : '';
  }

  Future<String> _requestPlayUrl(String platform, String id, String title,
      String artist, String quality, String source) async {
    final data = await _get('api/external/play-url', {
      'platform': platform,
      'id': id,
      'quality': quality,
      'title': title,
      'artist': artist,
      if (source.isNotEmpty) 'source': source,
    });
    if (data is Map && data['url'] != null) {
      // Keep the scheme returned by the backend: some CDNs serve HTTPS with
      // certificates iOS rejects (-1202), while plain HTTP works.
      return '${data['url']}'.trim();
    }
    return '';
  }

  bool _isLossless(String url) {
    final path = url.toLowerCase().split('?').first;
    return path.endsWith('.flac') ||
        path.endsWith('.wav') ||
        path.endsWith('.ape') ||
        path.endsWith('.alac');
  }

  Future<Map<String, dynamic>> fetchSongDetail(
      String platform, String id) async {
    final data = await _get('api/external/song-detail', {
      'platform': platform,
      'id': id,
    });
    if (data is Map) return data.cast<String, dynamic>();
    return const {};
  }

  /// Fetches lyrics and normalises every shape the backend may return:
  /// plain LRC text, `{ lrc: ... }`, `{ lyric: { lyric: ... } }`,
  /// JSON-in-string, or a list of `{ time, text }` objects.
  Future<List<LyricLine>> fetchLyricLines(
    String platform,
    String id, {
    String title = '',
    String artist = '',
    String source = '',
    int durationSeconds = 0,
  }) async {
    // The backend resolves lyrics by metadata; without `title` it answers
    // `no lyric found` even when the song does have lyrics.
    //
    // It also supports matching by title alone, so fall back progressively:
    // id+title -> title+artist -> cleaned title (brackets stripped).
    final cleaned = _cleanTitle(title);
    final duration =
        durationSeconds > 0 ? '$durationSeconds' : null;

    // Strategy 1 (best hit rate): platform + id + source + title + artist +
    // duration, exactly as the backend expects for tracks coming from a
    // playlist / toplist detail.
    final attempts = <Map<String, String>>[
      {
        'platform': platform,
        'id': id,
        if (source.isNotEmpty) 'source': source,
        if (title.isNotEmpty) 'title': title,
        if (artist.isNotEmpty) 'artist': artist,
        if (duration != null) 'duration': duration,
      },
      // Strategy 2: only the metadata, scraped by the backend.
      if (title.isNotEmpty)
        {
          'title': title,
          if (artist.isNotEmpty) 'artist': artist,
          if (duration != null) 'duration': duration,
        },
      // Strategy 3: cleaned title (brackets stripped).
      if (cleaned.isNotEmpty && cleaned != title)
        {
          'title': cleaned,
          if (artist.isNotEmpty) 'artist': artist,
          if (duration != null) 'duration': duration,
        },
      // Strategy 4: force a re-match, skipping the lyric cache/library.
      if (title.isNotEmpty)
        {
          'title': cleaned.isNotEmpty ? cleaned : title,
          if (artist.isNotEmpty) 'artist': artist,
          'force': '1',
        },
    ];

    for (final params in attempts) {
      try {
        final data = await _get('api/external/lyric', params);
        final lines = _extractLyrics(data);
        debugPrint(
          '[lyric] params=$params parsed=${lines.length} '
          'preview=${_preview(data)}',
        );
        if (lines.isNotEmpty) return lines;
      } catch (_) {
        // Try the next strategy.
      }
    }
    return const [];
  }

  /// Drops bracketed suffixes such as "(Live)" / "（《…》主题曲）".
  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'[\(（\[【].*?[\)）\]】]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _preview(dynamic data) {
    final text = '$data'.replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 300 ? '${text.substring(0, 300)}...' : text;
  }

  List<LyricLine> _extractLyrics(dynamic data, [int depth = 0]) {
    if (data == null || depth > 4) return const [];

    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return const [];
      final looksJson = (text.startsWith('{') && text.endsWith('}')) ||
          (text.startsWith('[') && text.endsWith(']'));
      if (looksJson) {
        try {
          final decoded = jsonDecode(text);
          final nested = _extractLyrics(decoded, depth + 1);
          if (nested.isNotEmpty) return nested;
        } catch (_) {}
      }
      final parsed = parseLrc(text);
      return parsed.isNotEmpty ? parsed : _staticLyrics(text);
    }

    if (data is List) {
      final lines = <LyricLine>[];
      for (final item in data) {
        if (item is Map) {
          final rawTime = item['time'] ??
              item['startTime'] ??
              item['start'] ??
              item['t'] ??
              item['timestamp'];
          final content = item['text'] ??
              item['lineLyric'] ??
              item['lyric'] ??
              item['content'] ??
              item['words'] ??
              item['lrc'];
          if (content != null) {
            lines.add(LyricLine(
              Duration(milliseconds: _asMs(rawTime)),
              '$content'.trim(),
            ));
          }
        }
      }
      if (lines.isNotEmpty) {
        lines.sort((a, b) => a.time.compareTo(b.time));
        return lines;
      }
      return _extractLyrics(
          data.map((e) => '$e').join('\n'), depth + 1);
    }

    if (data is Map) {
      const keys = [
        'rawLrc',
        'lrc',
        'lyric',
        'lyrics',
        'lyricText',
        'txt',
        'content',
        'text',
        'krc',
        'yrc',
        'lines',
        'data',
        'result',
      ];
      for (final key in keys) {
        if (data.containsKey(key)) {
          final parsed = _extractLyrics(data[key], depth + 1);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    }

    return const [];
  }

  /// Lyrics without timestamps still deserve to be shown.
  List<LyricLine> _staticLyrics(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => LyricLine(Duration.zero, line))
        .toList();
  }

  int _asMs(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) {
      final value = raw.toDouble();
      // Values below 1000 are almost always fractions of a second.
      return (value < 1000 ? value * 1000 : value).round();
    }
    final text = '$raw'.trim();
    final clock = RegExp(r'^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?$')
        .firstMatch(text);
    if (clock != null) {
      final min = int.tryParse(clock.group(1) ?? '0') ?? 0;
      final sec = int.tryParse(clock.group(2) ?? '0') ?? 0;
      final frac = (clock.group(3) ?? '0').padRight(3, '0').substring(0, 3);
      return min * 60000 + sec * 1000 + (int.tryParse(frac) ?? 0);
    }
    final value = double.tryParse(text);
    if (value == null) return 0;
    return (value < 1000 ? value * 1000 : value).round();
  }
}
