import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/widgets/resonance_canvas.dart';

/// 케이던스를 원의 크기로 옮기는 규칙 (2026-08-17 동심원 재설계).
///
/// 이 매핑이 틀리면 두 원이 영영 안 만나거나 처음부터 붙어 있다. 둘 다
/// 조용히 틀리는 종류라 — 화면은 멀쩡해 보이고 감각만 죽는다 — 여기서 잡는다.
void main() {
  double mine((double, double) t) => t.$1;
  double theirs((double, double) t) => t.$2;

  group('발구름 → 크기', () {
    test('느린 발구름은 작은 원, 빠른 발구름은 큰 원', () {
      expect(CadenceRadius.forCadence(140), CadenceRadius.radiusMin);
      expect(CadenceRadius.forCadence(200), CadenceRadius.radiusMax);
      expect(CadenceRadius.forCadence(170), closeTo(0.76, 0.001));
    });

    test('범위 밖은 잘라낸다 — 원이 화면을 벗어나면 안 된다', () {
      expect(CadenceRadius.forCadence(60), CadenceRadius.radiusMin);
      expect(CadenceRadius.forCadence(400), CadenceRadius.radiusMax);
    });
  });

  group('둘 다 알 때 — 각자의 실제 발구름', () {
    test('같은 케이던스면 두 원이 같아진다', () {
      final t = CadenceRadius.targets(
          myCadence: 175, partnerCadence: 175, hasCloseness: true, closeness: 1);
      expect(mine(t), theirs(t));
    });

    test('내가 더 빠르면 내 원이 더 크다', () {
      final t = CadenceRadius.targets(
          myCadence: 190,
          partnerCadence: 155,
          hasCloseness: true,
          closeness: 0.2);
      expect(mine(t), greaterThan(theirs(t)));
    });

    test('발맞춤 값이 아니라 실제 케이던스를 따른다', () {
      // closeness가 1이어도 케이던스가 다르면 원 크기는 달라야 한다.
      // 실데이터가 있을 때는 그게 가장 정직하다
      final t = CadenceRadius.targets(
          myCadence: 190, partnerCadence: 150, hasCloseness: true, closeness: 1);
      expect(mine(t), isNot(theirs(t)));
    });
  });

  group('발맞춤만 알 때 (데모) — 값이 곧 거리다', () {
    test('발이 맞을수록 두 원이 같아진다', () {
      final far = CadenceRadius.targets(
          myCadence: null,
          partnerCadence: null,
          hasCloseness: true,
          closeness: 0);
      final near = CadenceRadius.targets(
          myCadence: null,
          partnerCadence: null,
          hasCloseness: true,
          closeness: 1);
      expect((mine(far) - theirs(far)).abs(),
          greaterThan((mine(near) - theirs(near)).abs()));
      expect(mine(near), closeTo(theirs(near), 0.001));
    });

    test('내 원은 기준 크기에서 움직이지 않는다', () {
      // 내 발구름을 모르는데 내 원을 흔들면 없는 정보를 지어내는 것이다
      for (final c in [0.0, 0.5, 1.0]) {
        final t = CadenceRadius.targets(
            myCadence: null,
            partnerCadence: null,
            hasCloseness: true,
            closeness: c);
        expect(mine(t), CadenceRadius.radiusNominal);
      }
    });
  });

  group('아무것도 모를 때 — 숨만 쉬는 두 원', () {
    test('둘 다 기준 크기', () {
      final t = CadenceRadius.targets(
          myCadence: null,
          partnerCadence: null,
          hasCloseness: false,
          closeness: 0);
      expect(mine(t), CadenceRadius.radiusNominal);
      expect(theirs(t), CadenceRadius.radiusNominal);
    });

    test('한쪽 케이던스만 있어도 지어내지 않는다', () {
      // 내 발구름만 알고 상대를 모르면, 상대 원을 내 값으로 그리는 것은
      // 거짓말이다. 발맞춤도 없으면 둘 다 기준 크기로 둔다
      final t = CadenceRadius.targets(
          myCadence: 180,
          partnerCadence: null,
          hasCloseness: false,
          closeness: 0);
      expect(mine(t), CadenceRadius.radiusNominal);
      expect(theirs(t), CadenceRadius.radiusNominal);
    });
  });

  group('센서가 헛것을 볼 때 — NaN·무한대 (2026-09-11)', () {
    test('NaN은 clamp를 통과하므로 입구에서 기준 크기로 막는다', () {
      // NaN이 지수 평활의 누산기에 한 번 섞이면 러닝이 끝날 때까지
      // 고리가 다시 그려지지 않는다
      expect(CadenceRadius.forCadence(double.nan), CadenceRadius.radiusNominal);
      expect(CadenceRadius.forCadence(double.infinity),
          CadenceRadius.radiusNominal);
    });

    test('한쪽이 NaN이면 둘 다 아는 경로를 타지 않는다', () {
      final t = CadenceRadius.targets(
          myCadence: double.nan,
          partnerCadence: 170,
          hasCloseness: false,
          closeness: 0);
      expect(mine(t).isFinite, isTrue);
      expect(theirs(t).isFinite, isTrue);
    });

    test('발맞춤 값이 NaN이어도 반지름은 유한하다', () {
      final t = CadenceRadius.targets(
          myCadence: null,
          partnerCadence: null,
          hasCloseness: true,
          closeness: double.nan);
      expect(mine(t), CadenceRadius.radiusNominal);
      expect(theirs(t), CadenceRadius.radiusNominal);
    });
  });
}
