import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/live_share.dart';

/// 라이브 동기화의 세 판단 — 언제 쓰는가, 얼마나 가까운가, 언제 입을 다무는가.
///
/// 셋 다 화면 없이 틀릴 수 있는 것들이다. 쓰기가 잦으면 청구서가 오르고,
/// 발맞춤이 틀리면 있지도 않은 순간에 소리와 진동이 터지고, 낡은 값을
/// 그냥 쓰면 앱이 거짓말을 한다.
void main() {
  final t0 = DateTime.utc(2026, 8, 17, 7);

  LiveState state(
          {double km = 1.0,
          double? cadence = 170,
          int? instantPace,
          int seconds = 0}) =>
      LiveState(
        paceSecPerKm: 330,
        instantPaceSecPerKm: instantPace,
        cadenceSpm: cadence,
        km: km,
        at: t0.add(Duration(seconds: seconds)),
      );

  group('쓰기 판단 — 아껴 쓴다', () {
    test('첫 값은 무조건 쓴다', () {
      // 상대가 나를 볼 수 있어야 세션이 시작된다
      expect(LiveWriteGate().shouldWrite(state()), isTrue);
    });

    test('3초가 안 지났으면 아무리 변해도 안 쓴다', () {
      final gate = LiveWriteGate();
      gate.shouldWrite(state(seconds: 0));
      expect(gate.shouldWrite(state(km: 5.0, cadence: 200, seconds: 2)),
          isFalse);
    });

    test('3초가 지나도 변한 게 없으면 하트비트 전까지는 안 쓴다', () {
      // 신호등에 서 있는 동안 초당 한 번씩 쓰지 않기 위해
      final gate = LiveWriteGate();
      gate.shouldWrite(state(seconds: 0));
      expect(gate.shouldWrite(state(seconds: 4)), isFalse);
      expect(gate.shouldWrite(state(seconds: 9)), isFalse);
    });

    test('변한 게 없어도 10초마다 한 번은 쓴다 (2026-09-11 하트비트)', () {
      // 쓰기가 통째로 멎으면 상대 화면이 "신호 약함"으로 떨어진다.
      // 멀쩡히 연결돼 있는데 화면이 네트워크를 의심하면 안 된다
      final gate = LiveWriteGate();
      gate.shouldWrite(state(seconds: 0));
      expect(gate.shouldWrite(state(seconds: 10)), isTrue);
      expect(gate.shouldWrite(state(seconds: 15)), isFalse,
          reason: '하트비트는 마지막 쓰기부터 다시 센다');
      expect(gate.shouldWrite(state(seconds: 20)), isTrue);
    });

    test('1분 정지 동안의 쓰기는 하트비트 횟수(6)를 넘지 않는다', () {
      final gate = LiveWriteGate();
      gate.shouldWrite(state(seconds: 0));
      var writes = 0;
      for (var i = 1; i <= 60; i++) {
        if (gate.shouldWrite(state(seconds: i))) writes++;
      }
      expect(writes, 6);
    });

    test('지금 페이스가 8초 넘게 바뀌면 쓴다', () {
      // 보폭만 늘려 빨라지면 케이던스가 거의 안 변한다 — 여기서 못 잡으면
      // 상대 화면에 끝내 도착하지 않는다
      final gate = LiveWriteGate();
      gate.shouldWrite(state(instantPace: 330, seconds: 0));
      expect(gate.shouldWrite(state(instantPace: 325, seconds: 4)), isFalse);
      expect(gate.shouldWrite(state(instantPace: 320, seconds: 5)), isTrue);
    });

    test('지금 페이스가 생긴 것도 소식이다', () {
      final gate = LiveWriteGate();
      gate.shouldWrite(state(instantPace: null, seconds: 0));
      expect(gate.shouldWrite(state(instantPace: 330, seconds: 4)), isTrue);
    });

    test('10m를 움직였으면 쓴다', () {
      final gate = LiveWriteGate();
      gate.shouldWrite(state(km: 1.0, seconds: 0));
      expect(gate.shouldWrite(state(km: 1.01, seconds: 4)), isTrue);
    });

    test('케이던스가 2spm 넘게 바뀌면 쓴다', () {
      final gate = LiveWriteGate();
      gate.shouldWrite(state(cadence: 170, seconds: 0));
      expect(gate.shouldWrite(state(cadence: 171, seconds: 4)), isFalse);
      expect(gate.shouldWrite(state(cadence: 173, seconds: 4)), isTrue);
    });

    test('케이던스가 사라진 것도 소식이다', () {
      // 권한이 꺼졌거나 폰을 손에 들었을 때. 상대 화면에서 발맞춤이
      // 옛 값으로 굳어 있으면 안 된다
      final gate = LiveWriteGate();
      gate.shouldWrite(state(cadence: 170, seconds: 0));
      expect(gate.shouldWrite(state(cadence: null, seconds: 4)), isTrue);
    });

    test('30분 러닝에서 쓰기가 수백 회를 넘지 않는다', () {
      // 1초마다 값이 들어와도 게이트가 걸러낸다
      final gate = LiveWriteGate();
      var writes = 0;
      for (var i = 0; i < 1800; i++) {
        // 실제 러닝처럼 조금씩 늘어나는 거리
        if (gate.shouldWrite(state(km: i * 0.003, seconds: i))) writes++;
      }
      expect(writes, lessThanOrEqualTo(601)); // 3초에 한 번이 상한
      expect(writes, greaterThan(100), reason: '너무 안 쓰면 상대가 멈춰 보인다');
    });
  });

  group('발맞춤 — 케이던스 차이', () {
    test('같으면 1.0', () {
      expect(CadenceCloseness.of(170, 170), 1.0);
    });

    test('30spm 이상 벌어지면 0', () {
      expect(CadenceCloseness.of(150, 180), 0.0);
      expect(CadenceCloseness.of(155, 60), 0.0,
          reason: '어느 정수비로도 이어지지 않는 짝이어야 0이 된다');
    });

    test('정수비로 이어지면 0이 아니다 (2026-08-22 P2)', () {
      // 120(걷기) 대 190(러닝)은 2:3에 가깝다 — §1-3이 폴리리듬 공명으로
      // 인정하는 관계라 "완전히 남남"이라고 말하지 않는다. 규칙의 주인은
      // CadenceMatch이고 자세한 검증은 cadence_resonance_test.dart에 있다
      expect(CadenceCloseness.of(120, 190), greaterThan(0.7));
    });

    test('사이는 선형', () {
      expect(CadenceCloseness.of(170, 185), closeTo(0.5, 0.001));
      expect(CadenceCloseness.of(170, 176), closeTo(0.8, 0.001));
    });

    test('방향은 상관없다', () {
      expect(CadenceCloseness.of(160, 175), CadenceCloseness.of(175, 160));
    });

    test('한쪽이라도 모르면 null — 0이 아니다', () {
      // 0으로 두면 "아주 멀다"가 되어 화면이 멀어졌다고 말한다.
      // 모르는 것과 먼 것은 다르다
      expect(CadenceCloseness.of(null, 170), isNull);
      expect(CadenceCloseness.of(170, null), isNull);
      expect(CadenceCloseness.of(null, null), isNull);
    });
  });

  group('신선도 — 낡은 값으로 말하지 않는다', () {
    test('6초까지는 쓴다', () {
      expect(CadenceCloseness.isFresh(t0, t0.add(const Duration(seconds: 5))),
          isTrue);
      expect(CadenceCloseness.isFresh(t0, t0.add(const Duration(seconds: 6))),
          isTrue);
    });

    test('6초를 넘으면 버린다', () {
      expect(CadenceCloseness.isFresh(t0, t0.add(const Duration(seconds: 7))),
          isFalse);
      expect(CadenceCloseness.isFresh(t0, t0.add(const Duration(minutes: 1))),
          isFalse);
    });
  });

  group('직렬화', () {
    test('없는 값은 아예 안 실어 보낸다', () {
      final m = LiveState(
              paceSecPerKm: null, cadenceSpm: null, km: 2.5, at: t0)
          .toMap();
      expect(m.containsKey('paceSecPerKm'), isFalse);
      expect(m.containsKey('cadenceSpm'), isFalse);
      expect(m['km'], 2.5);
    });

    test('보낸 그대로 돌아온다', () {
      final before = state(km: 3.2, cadence: 178);
      final after = LiveState.fromMap(before.toMap())!;
      expect(after.km, 3.2);
      expect(after.cadenceSpm, 178);
      expect(after.at.millisecondsSinceEpoch, before.at.millisecondsSinceEpoch);
    });

    test('지금 페이스도 보낸 그대로 돌아온다', () {
      final after =
          LiveState.fromMap(state(instantPace: 312).toMap())!;
      expect(after.instantPaceSecPerKm, 312);
      expect(after.displayPaceSecPerKm, 312);
    });

    test('구버전 앱은 지금 페이스를 안 보낸다 — 화면은 평균으로 떨어진다', () {
      final old = LiveState.fromMap({
        'paceSecPerKm': 330,
        'km': 1.0,
        'at': t0.millisecondsSinceEpoch,
      })!;
      expect(old.instantPaceSecPerKm, isNull);
      expect(old.displayPaceSecPerKm, 330);
    });

    test('시각이 없는 조각은 버린다 — 신선도를 판정할 수 없다', () {
      expect(LiveState.fromMap({'km': 1.0}), isNull);
      expect(LiveState.fromMap(null), isNull);
    });
  });
}
