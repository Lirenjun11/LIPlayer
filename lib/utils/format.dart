/// Formats a [Duration] as `mm:ss`.
String formatDuration(Duration d) {
  final total = d.inSeconds;
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Formats the API's raw duration (seconds or milliseconds) as `mm:ss`.
String formatRawDuration(int raw) {
  if (raw <= 0) return '--:--';
  final seconds = raw > 10000 ? raw ~/ 1000 : raw;
  return formatDuration(Duration(seconds: seconds));
}

/// Formats a play count with a Chinese 万 suffix.
String formatCount(int count) {
  if (count <= 0) return '0';
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
  return '$count';
}
