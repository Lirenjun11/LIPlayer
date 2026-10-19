/// A music source / plugin advertised by the backend.
class MusicPlatform {
  final String platform;
  final List<String> supportedSearchType;

  MusicPlatform({required this.platform, this.supportedSearchType = const []});

  factory MusicPlatform.fromJson(Map<String, dynamic> json) {
    final rawTypes = json['supportedSearchType'];
    final types = <String>[];
    if (rawTypes is List) {
      for (final t in rawTypes) {
        types.add('$t');
      }
    }
    return MusicPlatform(
      platform: '${json['platform'] ?? ''}',
      supportedSearchType: types,
    );
  }
}
