import 'song.dart';

/// A toplist entry or a song sheet (collection) shown on the discover page.
class MusicCollection {
  final String id;
  final String title;
  final String artwork;
  final String artist;
  final int playCount;
  final String platform;

  /// Upstream source id (`wy`, `kw`, ...) required by the detail endpoint.
  final String src;

  MusicCollection({
    required this.id,
    required this.title,
    this.artwork = '',
    this.artist = '',
    this.playCount = 0,
    required this.platform,
    this.src = '',
  });

  factory MusicCollection.fromJson(Map<String, dynamic> json, {String? platform}) {
    return MusicCollection(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      artwork: Song.normalizeUrl('${json['artwork'] ?? json['coverImg'] ?? ''}'),
      artist: '${json['artist'] ?? ''}',
      playCount: _asInt(json['playCount']),
      platform: platform ?? '${json['platform'] ?? ''}',
      src: '${json['src'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artwork': artwork,
        'artist': artist,
        'playCount': playCount,
        'platform': platform,
        'src': src,
      };

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

/// A named group of toplists (e.g. "飙升榜" category).
class ToplistGroup {
  final String title;
  final List<MusicCollection> items;

  ToplistGroup({required this.title, this.items = const []});
}
