import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/utils/format.dart';

void main() {
  test('formatDuration pads minutes and seconds', () {
    expect(formatDuration(const Duration(seconds: 75)), '01:15');
  });

  test('formatRawDuration handles seconds and milliseconds', () {
    expect(formatRawDuration(65), '01:05');
    expect(formatRawDuration(65000), '01:05');
    expect(formatRawDuration(0), '--:--');
  });

  test('formatCount uses the 万 suffix', () {
    expect(formatCount(999), '999');
    expect(formatCount(23456), '2.3万');
  });
}
