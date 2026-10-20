import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Network cover with a graceful placeholder/fallback.
class CoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;

  const CoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = 8,
    this.fit = BoxFit.cover,
  });

  /// Some CDNs (NetEase in particular) reject non-browser user agents with a
  /// 403, which is why covers used to stay on the placeholder.
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static Map<String, String> _headersFor(String url) {
    final headers = <String, String>{'User-Agent': _userAgent};
    if (url.contains('music.126.net')) {
      headers['Referer'] = 'https://music.163.com/';
    }
    return headers;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = url.replaceFirst(RegExp(r'^http:'), 'https:');
    // Decode at display size: full-resolution covers make long lists janky.
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final logical = width ?? height;
    final cacheWidth = (logical != null && logical.isFinite)
        ? (logical * dpr).clamp(96, 1024).round()
        : 480;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: resolved.isEmpty
          ? _fallback()
          : CachedNetworkImage(
              imageUrl: resolved,
              httpHeaders: _headersFor(resolved),
              width: width,
              height: height,
              fit: fit,
              memCacheWidth: cacheWidth,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => _fallback(),
              errorWidget: (_, __, ___) => _fallback(),
            ),
    );
  }

  Widget _fallback() {
    // `width` may be `double.infinity` (e.g. Expanded covers); an infinite
    // icon size breaks layout and makes the whole page unresponsive.
    final base = width ?? height;
    final iconSize = (base != null && base.isFinite)
        ? (base * 0.42).clamp(16.0, 64.0)
        : 20.0;
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.bgCard2, AppColors.bgCard],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note,
        color: AppColors.accent.withValues(alpha: 0.7),
        size: iconSize,
      ),
    );
  }
}
