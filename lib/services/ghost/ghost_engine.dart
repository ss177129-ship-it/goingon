// 고스트 재생기 — 시차 동행.
//
// **추월 게임이 아니다**(§3-1). 이 파일에는 승패·순위·앞서기·뒤처지기를
// 뜻하는 식별자가 하나도 없고, 앞으로도 없어야 한다. 쓸 수 있는 말은
// 가까워짐/나란함/멀어짐 셋뿐이며 그 판정은 이 파일이 아니라 공명 엔진이 한다.
// 여기가 하는 일은 "그날의 리듬을 시간축대로 흘려보내는 것"뿐이다.
//
// 내 페이스와 완전히 독립이다. 내가 빨라져도 고스트는 그날 그 사람이 달린
// 속도로 흐른다. 그래서 "따라잡는다"는 개념 자체가 성립하지 않는다.
import 'dart:async';

import '../cadence/partner_cadence.dart';
import 'ghost_run.dart';

/// 재생 중에 일어나는 일들
sealed class GhostEvent {
  const GhostEvent(this.elapsed);
  final Duration elapsed;
  String describe();
}

/// 상대가 느려진 지점에 닿았다 — 화자가 한 줄 할 자리.
/// **세션당 최대 2회**(§3-3). 관찰이지 평가가 아니다
class GhostSlowdown extends GhostEvent {
  const GhostSlowdown(super.elapsed);

  @override
  String describe() => 'slowdown ${elapsed.inSeconds}s';
}

/// 그날의 기록이 끝났다 — **작별 인사이지 이탈이 아니다**(§2-2).
/// "지수의 그날은 여기까지였어요" + 발소리 페이드. 내 세션은 계속된다
class GhostFarewell extends GhostEvent {
  const GhostFarewell(super.elapsed);

  @override
  String describe() => 'farewell — 그날은 여기까지';
}

/// 고스트 하나를 세션 시간축에 얹어 재생한다.
///
/// [PartnerCadenceSource]를 구현하므로 **공명 엔진에는 라이브와 똑같이
/// 꽂힌다**(P2). 시차 공명이 동시 공명과 다른 코드를 타지 않는 것이
/// 이 설계의 요점이다 — 다르면 "시차는 진짜 공명인가"에 코드가 아니라고
/// 답하게 된다.
class GhostEngine implements PartnerCadenceSource {
  GhostEngine(this.ghost) : _timeline = ghost.timeline;

  final GhostRun ghost;
  final GhostCadenceTimeline _timeline;

  final _events = StreamController<GhostEvent>.broadcast();
  Stream<GhostEvent> get events => _events.stream;

  /// 화자가 느려짐을 언급할 수 있는 횟수. 넘기면 조용히 지나간다 —
  /// 상한이 없으면 힘들었던 러닝일수록 잔소리가 많아진다
  static const kMaxSlowdownMentions = 2;

  int _mentioned = 0;
  int _nextMarker = 0;
  bool _saidFarewell = false;

  /// 상대 이름 — 작별 문구를 만드는 쪽(사운드·화자)이 쓴다
  Duration get duration => ghost.duration;

  @override
  double? spmAt({required Duration elapsed, required DateTime now}) =>
      _timeline.spmAt(elapsed: elapsed, now: now);

  @override
  bool isExhausted({required Duration elapsed}) =>
      _timeline.isExhausted(elapsed: elapsed);

  /// 세션의 1초 틱에서 부른다. 마커와 작별을 이 시각 기준으로 낸다
  void update(Duration elapsed) {
    while (_nextMarker < ghost.slowdownMarkers.length &&
        ghost.slowdownMarkers[_nextMarker] <= elapsed.inSeconds) {
      final at = ghost.slowdownMarkers[_nextMarker];
      _nextMarker++;
      if (_mentioned < kMaxSlowdownMentions) {
        _mentioned++;
        _emit(GhostSlowdown(Duration(seconds: at)));
      }
    }

    if (!_saidFarewell && isExhausted(elapsed: elapsed)) {
      _saidFarewell = true;
      _emit(GhostFarewell(elapsed));
    }
  }

  void _emit(GhostEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void dispose() => _events.close();
}

/// 함께 달린 뒤 상대에게 남기는 기록.
///
/// **발송은 서버만 한다**(CLAUDE.md) — 앱은 이 문서를 만들 뿐이고
/// Cloud Function이 그것을 보고 푸시를 보낸다. 클라이언트가 직접 보내면
/// 남의 기기로 가는 알림을 클라이언트가 만드는 셈이 된다.
class GhostCompanionship {
  const GhostCompanionship({
    required this.ghostRunId,
    required this.ghostOwnerUid,
    required this.companionUid,
    required this.resonanceSeconds,
    required this.at,
  });

  /// 누구의 그날과 달렸는가
  final String ghostRunId;
  final String ghostOwnerUid;

  /// 함께 달린 사람 (나)
  final String companionUid;

  /// 시차 공명 누적 초 — 북극성 지표의 원천이기도 하다
  final int resonanceSeconds;

  final DateTime at;

  /// 내 지난 러닝과 달린 것은 알릴 이유가 없다 — 나에게 "당신이 당신과
  /// 달렸어요"를 보내는 셈이다. 서비스가 이 값을 보고 문서를 만들지 결정한다
  bool get worthNotifying => ghostOwnerUid != companionUid;

  Map<String, Object?> toMap() => {
        'ghostRunId': ghostRunId,
        'ghostOwnerUid': ghostOwnerUid,
        'companionUid': companionUid,
        'resonanceSeconds': resonanceSeconds,
        'at': at.toUtc().toIso8601String(),
      };
}
