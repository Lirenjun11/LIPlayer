/// A playable track, mirroring the song shape used by the Vue reference page.
class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  String artwork;
  final String platform;

  /// Raw duration as returned by the API (usually milliseconds).
  final int duration;

  /// Upstream source id (`wy`, `kw`, ...). Multi-source plugins need it echoed
  /// back to `play-url`, otherwise the track cannot be resolved.
  final String source;

  /// Resolved stream URL, populated lazily via the play-url endpoint.
  String? playUrl;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.artwork = '',
    required this.platform,
    this.duration = 0,
    this.source = '',
    this.playUrl,
  });

  String get uniqueKey => '${platform}_$id';

  Duration get durationValue {
    if (duration <= 0) return Duration.zero;
    // The API mixes seconds and milliseconds; >10000 is treated as ms.
    final ms = duration > 10000 ? duration : duration * 1000;
    return Duration(milliseconds: ms);
  }

  factory Song.fromJson(
    Map<String, dynamic> json, {
    String? platform,
    String? source,
  }) {
    final rawSource = '${json['source'] ?? ''}';
    return Song(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      artist: '${json['artist'] ?? ''}',
      album: '${json['album'] ?? ''}',
      artwork: normalizeUrl('${json['artwork'] ?? json['coverImg'] ?? ''}'),
      platform: platform ?? '${json['platform'] ?? ''}',
      duration: _asInt(json['duration']),
      source: rawSource.isNotEmpty ? rawSource : (source ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'artwork': artwork,
        'platform': platform,
        'duration': duration,
        'source': source,
      };

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  /// Upgrades plain http resource links to https to avoid cleartext blocks.
  static String normalizeUrl(String url) {
    if (url.isEmpty) return '';
    return url.replaceFirst(RegExp(r'^http:'), 'https:');
  }
}
