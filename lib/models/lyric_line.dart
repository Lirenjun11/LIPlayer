/// A single parsed lyric line with its timing.
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);
}

/// Parser for the LRC format, ported from the Vue reference implementation.
List<LyricLine> parseLrc(String lrcText) {
  if (lrcText.isEmpty) return const [];
  final lines = lrcText.split('\n');
  final timeRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final offsetRegex = RegExp(r'\[offset:([+-]?\d+)\]', caseSensitive: false);
  final metaRegex = RegExp(r'\[[a-z]+:[^\]]*\]', caseSensitive: false);

  double offset = 0;
  for (final line in lines) {
    final m = offsetRegex.firstMatch(line);
    if (m != null) {
      offset = (int.tryParse(m.group(1) ?? '0') ?? 0) / 1000;
    }
  }

  final result = <LyricLine>[];
  for (final line in lines) {
    final times = <double>[];
    for (final m in timeRegex.allMatches(line)) {
      final min = int.tryParse(m.group(1) ?? '0') ?? 0;
      final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
      final fraction = (m.group(3) ?? '0').padRight(3, '0').substring(0, 3);
      final ms = int.tryParse(fraction) ?? 0;
      final t = min * 60 + sec + ms / 1000 + offset;
      times.add(t < 0 ? 0 : t);
    }
    final text = line.replaceAll(timeRegex, '').replaceAll(metaRegex, '').trim();
    if (text.isNotEmpty && times.isNotEmpty) {
      for (final t in times) {
        result.add(LyricLine(Duration(milliseconds: (t * 1000).round()), text));
      }
    }
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}
