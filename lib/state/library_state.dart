import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// A user-created playlist.
class SongPlaylist {
  SongPlaylist({
    required this.id,
    required this.name,
    List<Song>? songs,
    DateTime? createdAt,
  })  : songs = songs ?? [],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final List<Song> songs;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory SongPlaylist.fromJson(Map<String, dynamic> json) {
    return SongPlaylist(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? '未命名歌单'}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      songs: (json['songs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList(),
    );
  }
}

/// Favourites and user playlists, persisted locally.
class LibraryState extends ChangeNotifier {
  static const String _favoritesKey = 'library_favorites';
  static const String _playlistsKey = 'library_playlists';

  List<Song> favorites = [];
  List<SongPlaylist> playlists = [];

  bool isFavorite(Song song) =>
      favorites.any((s) => s.uniqueKey == song.uniqueKey);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawFavorites = prefs.getString(_favoritesKey);
    if (rawFavorites != null && rawFavorites.isNotEmpty) {
      try {
        favorites = (jsonDecode(rawFavorites) as List)
            .whereType<Map<String, dynamic>>()
            .map(Song.fromJson)
            .toList();
      } catch (_) {}
    }
    final rawPlaylists = prefs.getString(_playlistsKey);
    if (rawPlaylists != null && rawPlaylists.isNotEmpty) {
      try {
        playlists = (jsonDecode(rawPlaylists) as List)
            .whereType<Map<String, dynamic>>()
            .map(SongPlaylist.fromJson)
            .toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(Song song) async {
    final index = favorites.indexWhere((s) => s.uniqueKey == song.uniqueKey);
    if (index >= 0) {
      favorites.removeAt(index);
    } else {
      favorites.insert(0, song);
    }
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> removeFavorite(Song song) async {
    favorites.removeWhere((s) => s.uniqueKey == song.uniqueKey);
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> clearFavorites() async {
    favorites = [];
    notifyListeners();
    await _saveFavorites();
  }

  Future<SongPlaylist> createPlaylist(String name) async {
    final playlist = SongPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? '未命名歌单' : name.trim(),
    );
    playlists.insert(0, playlist);
    notifyListeners();
    await _savePlaylists();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final playlist = playlists.firstWhere((p) => p.id == id,
        orElse: () => SongPlaylist(id: '', name: ''));
    if (playlist.id.isEmpty) return;
    playlist.name = name.trim().isEmpty ? playlist.name : name.trim();
    notifyListeners();
    await _savePlaylists();
  }

  /// Moves a playlist; used by the drag-to-reorder list.
  Future<void> reorderPlaylists(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= playlists.length) return;
    final target = newIndex.clamp(0, playlists.length - 1);
    final playlist = playlists.removeAt(oldIndex);
    playlists.insert(target, playlist);
    notifyListeners();
    await _savePlaylists();
  }

  Future<void> deletePlaylist(String id) async {
    playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _savePlaylists();
  }

  /// Returns false when the song is already in the playlist.
  Future<bool> addToPlaylist(String playlistId, Song song) async {
    final playlist =
        playlists.firstWhere((p) => p.id == playlistId, orElse: () => SongPlaylist(id: '', name: ''));
    if (playlist.id.isEmpty) return false;
    if (playlist.songs.any((s) => s.uniqueKey == song.uniqueKey)) {
      return false;
    }
    playlist.songs.add(song);
    notifyListeners();
    await _savePlaylists();
    return true;
  }

  Future<void> removeFromPlaylist(String playlistId, Song song) async {
    final playlist =
        playlists.firstWhere((p) => p.id == playlistId, orElse: () => SongPlaylist(id: '', name: ''));
    if (playlist.id.isEmpty) return;
    playlist.songs.removeWhere((s) => s.uniqueKey == song.uniqueKey);
    notifyListeners();
    await _savePlaylists();
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _favoritesKey,
        jsonEncode(favorites.map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _playlistsKey,
        jsonEncode(playlists.map((p) => p.toJson()).toList()),
      );
    } catch (_) {}
  }
}
