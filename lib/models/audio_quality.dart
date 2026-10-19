/// Playback quality tiers exposed to the user.
///
/// The backend forwards `quality` to each music plugin and they do not agree
/// on the accepted values, so every tier carries a fallback chain.
enum AudioQuality { standard, high, lossless }

extension AudioQualityX on AudioQuality {
  String get label => switch (this) {
        AudioQuality.standard => '标准',
        AudioQuality.high => '高品质',
        AudioQuality.lossless => '无损',
      };

  String get description => switch (this) {
        AudioQuality.standard => '省流量，约 128kbps',
        AudioQuality.high => '约 320kbps / 部分音源为 FLAC',
        AudioQuality.lossless => 'FLAC 等无损格式，文件较大',
      };

  /// Values tried in order until a usable URL comes back.
  List<String> get candidates => switch (this) {
        AudioQuality.standard => const ['standard'],
        AudioQuality.high => const ['high', 'standard'],
        AudioQuality.lossless => const [
            'lossless',
            'master',
            'hires',
            'high',
            'standard',
          ],
      };
}
