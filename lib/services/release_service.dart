import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A downloadable IPA attached to the latest GitHub release.
class ReleaseAsset {
  final String name;
  final String url;
  final int size;
  final String proxy;
  final String tag;

  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.proxy,
    required this.tag,
  });

  double get sizeMb => size / (1024 * 1024);
}

/// Reads the newest GitHub release and downloads its IPA.
///
/// GitHub is unreachable on some networks, so a mirror prefix is tried first
/// and a direct connection is kept as a fallback.
class ReleaseService {
  static const String repo = 'Lirenjun11/LIPlayer';
  static const List<String> _proxies = [
    'https://gh-proxy.com/',
    'https://ghfast.top/',
    '',
  ];

  Future<ReleaseAsset?> fetchLatest() async {
    for (final proxy in _proxies) {
      try {
        final uri = Uri.parse(
          '${proxy}https://api.github.com/repos/$repo/releases/latest',
        );
        final response = await http.get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'LIPlayer',
          },
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) continue;

        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final assets =
            (json['assets'] as List? ?? const []).whereType<Map<String, dynamic>>();
        for (final asset in assets) {
          final name = '${asset['name'] ?? ''}';
          if (!name.toLowerCase().endsWith('.ipa')) continue;
          return ReleaseAsset(
            name: name,
            url: '${asset['browser_download_url'] ?? ''}',
            size: (asset['size'] as num?)?.toInt() ?? 0,
            proxy: proxy,
            tag: '${json['tag_name'] ?? ''}',
          );
        }
      } catch (_) {
        // Try the next mirror.
      }
    }
    return null;
  }

  /// Downloads [asset] into the app's documents directory.
  Future<File> download(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${asset.name}');
    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse('${asset.proxy}${asset.url}'));
      request.headers['User-Agent'] = 'LIPlayer';
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('下载失败（HTTP ${response.statusCode}）');
      }

      final total = response.contentLength ?? asset.size;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }
}
