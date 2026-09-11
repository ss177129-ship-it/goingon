import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/world/world_palette.dart';

/// 러닝 배경의 시간대와 어둠 위의 관계색 (2026-09-11 2단계).
///
/// 시간대는 러닝을 시작할 때 한 번만 정한다. 그 경계가 흔들리면 같은 시각에
/// 시작한 두 사람의 화면이 다르고, 경계에서 매 프레임 고르면 달리는 도중에
/// 노을이 밤으로 뒤집히며 배경 일곱 층이 통째로 다시 구워진다.
void main() {
  WorldTime at(int hour, [int minute = 0]) =>
      WorldPalette.timeFor(DateTime(2026, 9, 11, hour, minute));

  group('시간대 — 해 진 뒤는 밤', () {
    test('18시 59분까지는 노을', () {
      expect(at(18, 59), WorldTime.dusk);
      expect(at(12), WorldTime.dusk);
    });

    test('19시부터 밤', () {
      expect(at(19), WorldTime.night);
      expect(at(23, 59), WorldTime.night);
      expect(at(0), WorldTime.night);
    });

    test('새벽 5시에 다시 노을로', () {
      expect(at(4, 59), WorldTime.night);
      expect(at(5), WorldTime.dusk);
    });

    test('시간대마다 그림 팔레트가 한 벌씩', () {
      expect(WorldPalette.of(WorldTime.night).night, isTrue);
      expect(WorldPalette.of(WorldTime.dusk).night, isFalse);
    });
  });

  group('어둠 위의 관계색 — theme.dart가 유일한 출처', () {
    const dark = GoRoles.light;

    test('밤에는 원색, 노을에는 한 톤 밝은 색', () {
      final d = dark.runDark;
      expect(d.self(night: true), GoColors.lime);
      expect(d.self(night: false), isNot(d.self(night: true)));
      expect(d.partner(night: false), isNot(d.partner(night: true)));
    });

    test('나와 상대의 색은 어느 시간대에도 섞이지 않는다', () {
      final d = dark.runDark;
      for (final night in [true, false]) {
        expect(d.self(night: night), isNot(d.partner(night: night)));
      }
    });

    test('숫자 그림자가 비어 있지 않다 — 배경이 숫자를 삼키지 않도록', () {
      expect(dark.runDark.numShadow, isNotEmpty);
    });
  });
}
