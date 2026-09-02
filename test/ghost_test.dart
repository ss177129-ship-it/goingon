// 고스트런 — 시차 동행.
//
// 여기서 지켜야 하는 것 셋:
//   1. 남긴 것과 되살린 것이 같은가 (delta 압축 왕복)
//   2. 재생이 **내 페이스와 독립인가** — 이것이 깨지면 추월 게임이 된다
//   3. 시차 공명이 **동시 공명과 같은 판정**을 타는가
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/cadence/partner_cadence.dart';
import 'package:goingon/services/ghost/ghost_engine.dart';
import 'package:goingon/services/ghost/ghost_run.dart';
import 'package:goingon/services/resonance.dart';

Duration _s(int n) => Duration(seconds: n);

GhostRun _ghost(List<double?> cadence,
        {List<int> slowdowns = const [],
        GhostVisibility visibility = GhostVisibility.pacemates}) =>
    GhostRun(
      id: 'g1',
      uid: 'jisoo',
      startedAt: DateTime.utc(2026, 8, 20, 19),
      duration: _s(cadence.length),
      km: 1.4,
      cadence: cadence,
      slowdownMarkers: slowdowns,
      visibility: visibility,
    );

void main() {
  group('저장 — 모든 러닝이 고스트가 된다', () {
    test('delta 압축 왕복에서 값이 살아남는다', () {
      final run = _ghost([158, 161, 160, null, 173, 174]);
      final back = GhostRun.fromMap('g1', run.toMap().cast<String, dynamic>());
      expect(back!.cadence, run.cadence);
      expect(back.km, run.km);
      expect(back.duration, run.duration);
      expect(back.visibility, GhostVisibility.pacemates);
    });

    test('GPS 경로는 담기지 않는다', () {
      final m = _ghost([160, 161]).toMap();
      expect(m.containsKey('route'), isFalse,
          reason: '경로는 재생에 필요 없고, 담지 않으면 규제 부담도 사라진다');
      expect(m.containsKey('latlng'), isFalse);
    });

    test('공개 범위 기본은 페이스메이트만', () {
      expect(GhostVisibility.fromWire(null), GhostVisibility.pacemates);
      expect(GhostVisibility.fromWire('알수없는값'), GhostVisibility.pacemates,
          reason: '모르는 값을 만나면 더 넓게가 아니라 더 좁게 간다');
      expect(GhostVisibility.fromWire('everyone'), GhostVisibility.everyone);
    });

    test('2분 미만은 고스트로 쓰지 않는다', () {
      expect(_ghost(List.filled(100, 165.0)).isUsable, isFalse);
      expect(_ghost(List.filled(130, 165.0)).isUsable, isTrue);
    });
  });

  group('기록기', () {
    test('모르는 초는 0이 아니라 null로 남는다', () {
      final r = GhostRecorder()..start();
      r.sample(165);
      r.sample(null);
      r.sample(167);
      expect(r.cadence, [165, null, 167],
          reason: '0으로 채우면 "멈춰 서 있었다"는 없는 사실이 기록된다');
    });

    test('느려진 지점을 남기되 한 구간에 하나만', () {
      final r = GhostRecorder()..start();
      for (var i = 0; i < 5; i++) {
        r.sample(170);
      }
      for (var i = 0; i < 15; i++) {
        r.sample(150); // 20spm 하락이 계속 이어짐
      }
      expect(r.slowdownMarkers, hasLength(1),
          reason: '한 번 느려진 구간에 마커가 열 개면 화자가 열 번 말한다');
    });
  });

  group('재생 — 내 페이스와 독립', () {
    test('벽시계가 달라도 같은 값을 준다', () {
      final e = GhostEngine(_ghost([160, 165, 170, null, 172]));
      for (final now in [
        DateTime.utc(2026, 8, 23),
        DateTime.utc(2027, 1, 1),
      ]) {
        expect(e.spmAt(elapsed: _s(2), now: now), 170,
            reason: '장소도 시각도 독립이어야 "멀리 있어도"가 성립한다');
        expect(e.spmAt(elapsed: _s(3), now: now), isNull);
      }
      e.dispose();
    });

    test('그날의 기록이 끝나면 작별 — 한 번만', () async {
      final e = GhostEngine(_ghost([160, 161, 162]));
      final events = <GhostEvent>[];
      e.events.listen(events.add);
      e.update(_s(2));
      e.update(_s(3));
      e.update(_s(4));
      await pumpEventQueue();
      expect(events.whereType<GhostFarewell>(), hasLength(1),
          reason: '작별은 이탈이 아니라 인사다 — 두 번 하면 인사가 아니다');
      e.dispose();
    });

    test('느려짐 언급은 세션당 2회까지', () async {
      final e = GhostEngine(
          _ghost(List.filled(300, 160.0), slowdowns: [30, 90, 150, 210]));
      final events = <GhostEvent>[];
      e.events.listen(events.add);
      for (var t = 0; t < 250; t++) {
        e.update(_s(t));
      }
      await pumpEventQueue();
      expect(events.whereType<GhostSlowdown>(), hasLength(2),
          reason: '상한이 없으면 힘들었던 러닝일수록 잔소리가 많아진다');
      e.dispose();
    });
  });

  group('시차 공명 — 동시 공명과 같은 판정', () {
    test('고스트도 8초를 채우면 공명한다', () {
      final e = GhostEngine(_ghost(List.filled(60, 171.0)));
      final r = ResonanceEngine();
      final t0 = DateTime.utc(2026, 8, 23, 6);
      for (var t = 0; t < 30; t++) {
        r.addCadences(
          mine: 170,
          theirs: e.spmAt(elapsed: _s(t), now: t0.add(_s(t))),
          at: t0.add(_s(t)),
        );
      }
      expect(r.state, SyncState.resonant);
      r.dispose();
      e.dispose();
    });

    test('고스트는 라이브와 똑같은 문으로 들어간다', () {
      // 타입이 같아야 공명 엔진이 둘을 구분할 수 없다 —
      // 구분할 수 있으면 언젠가 다르게 대하게 된다
      final PartnerCadenceSource ghost = GhostEngine(_ghost([170, 170]));
      final PartnerCadenceSource live = LivePartnerCadence();
      expect(ghost, isA<PartnerCadenceSource>());
      expect(live, isA<PartnerCadenceSource>());
    });
  });

  group('함께 달림 기록', () {
    test('내 과거와 달린 것은 알림 대상이 아니다', () {
      final mine = GhostCompanionship(
        ghostRunId: 'g1',
        ghostOwnerUid: 'me',
        companionUid: 'me',
        resonanceSeconds: 14,
        at: DateTime.utc(2026, 8, 23),
      );
      expect(mine.worthNotifying, isFalse,
          reason: '"당신이 당신과 달렸어요"를 보낼 이유가 없다');
    });

    test('공명 초가 실려 간다 — 북극성 지표의 원천', () {
      final c = GhostCompanionship(
        ghostRunId: 'g1',
        ghostOwnerUid: 'jisoo',
        companionUid: 'chanwoong',
        resonanceSeconds: 14,
        at: DateTime.utc(2026, 8, 23, 7),
      );
      expect(c.toMap()['resonanceSeconds'], 14);
      expect(c.toMap()['ghostOwnerUid'], 'jisoo');
    });
  });
}
