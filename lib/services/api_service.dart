import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<List<Song>> fetchCollectionDetail(
      String endpoint, String platform, String id) async {
    final data = await _get(endpoint, {
      'platform': platform,
      'id': id,
      'page': 1,
    });
    return _asList(data, ['data', 'musicList'])
        .whereType<Map<String, dynamic>>()
        .map((e) => Song.fromJson(e, platform: platform))
        .toList();
  }

  Future<String> fetchPlayUrl(
      String platform, String id, String title, String artist) async {
    final data = await _get('api/external/play-url', {
      'platform': platform,
      'id': id,
      'quality': 'standard',
      'title': title,
      'artist': artist,
    });
    if (data is Map && data['url'] != null) {
      return Song.normalizeUrl('${data['url']}');
    }
    return '';
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

  Future<String> fetchLyric(String platform, String id) async {
    final data = await _get('api/external/lyric', {
      'platform': platform,
      'id': id,
    });
    if (data is Map) {
      final raw = data['rawLrc'] ?? data['lrc'] ?? data['lyric'];
      if (raw != null) return '$raw';
    }
    return '';
  }
}
