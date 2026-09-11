import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode, ValueListenable;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/cadence_service.dart';
import '../services/demo_resonance.dart';
import '../services/cadence/partner_cadence.dart';
import '../services/live_share.dart';
import '../services/location_service.dart';
import '../services/resonance.dart';
import '../services/run_recovery.dart';
import '../services/run_service.dart';
import '../services/sound/resonance_sound.dart';
import '../services/sound/audio_session_controller.dart';
import '../services/sound/run_briefing.dart';
import '../services/sound/soloud_sound_engine.dart';
import '../services/sound_settings.dart';
import '../theme.dart';
import '../widgets/go_button.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import '../widgets/resonance_canvas.dart';
import '../widgets/run_stat_block.dart';
import '../widgets/world/run_world.dart';
import '../widgets/world/world_palette.dart';
import 'finish_screen.dart';

/// 강제 종료 대비 스냅샷을 남기는 최소 간격.
/// 예전에도 5초 주기였고 그대로 유지한다. 달라진 것은 이제 타이머뿐 아니라
/// 위치 콜백에서도 저장을 부르며, 어느 쪽에서 불리든 이 간격이 지켜진다는 점
const _kSnapshotInterval = Duration(seconds: 5);

/// 멈춤 버튼 지름. 러닝 중 주요 조작의 최소 터치 타겟(72pt)보다 크게 잡는다
const _kStopButtonSize = 76.0;

/// 평균과 비교하기 전에 지나야 하는 거리(km).
/// 200m 전의 평균은 GPS 오차가 그대로 들어가 있어 기준이 못 된다
const _kMinDistanceForDelta = 0.2;

/// 이 미만의 차이는 GPS 노이즈다. 화면에 띄우면 숫자가 계속 깜빡인다
const _kMinDeltaSeconds = 4;

/// **화면에서** 상대를 낡았다고 보기까지의 시간.
///
/// 공명 판정의 [CadenceCloseness.staleAfter](6초)보다 길다. 둘은 목적이
/// 다르다 — 판정은 모르는 것을 아는 척하면 안 되니 엄격해야 하고, 화면은
/// 쓰기 게이트(3초 간격 + 10초 하트비트)가 한 번 건너뛰었다고 상대를
/// 지워버리면 안 된다. 하트비트의 두 배 남짓으로 잡는다
const _kPartnerStaleAfter = Duration(seconds: 22);

/// 세계가 기준 속도로 흐르는 페이스(km당 초). 5'30"이다
const double _kWorldBasePace = 330;

/// 러닝 화면 — 각자 GPS로 기록하고, 케이던스·페이스·거리를 실시간으로
/// 주고받아 공명을 만든다. 합산은 여전히 완료 후에 한다
class RunScreen extends StatefulWidget {
  final String sessionId;
  final String partnerName;
  final bool demo;
  const RunScreen(
      {super.key,
      required this.sessionId,
      required this.partnerName,
      this.demo = false});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen>
    with SingleTickerProviderStateMixin {
  final _location = LocationService();
  Timer? _timer;
  DateTime? _startedAt;
  int _seconds = 0;
  double _km = 0;
  bool _gpsOk = true;
  bool _finishing = false;

  /// **최근 30초 구간의 페이스(km당 초).** 화면의 큰 숫자가 이 값이다.
  ///
  /// 계산은 [RunAccumulator]가 이미 하고 있었다(`paceSmoothingWindow: 30s`가
  /// `RunFilterConfig.current`에 켜져 있다). 여기까지 배선이 없었을 뿐이다.
  ///
  /// 왜 평균이 아니라 이것인가: 25분에 4.6km를 뛴 뒤 전력 질주를 해도
  /// 누적 평균은 5초쯤밖에 안 움직인다. 분모가 이미 커져 있기 때문이다.
  /// 내 행동이 화면을 즉시 바꾸지 않으면 그 숫자는 내 것으로 느껴지지 않는다
  double? _instantSecPerKm;

  /// 마지막으로 받은 상대의 실시간 상태. 화면에 그대로 그린다
  LiveState? _partnerLive;

  /// **그 값을 내가 받은 시각.**
  ///
  /// 신선도를 `live.at`(상대 폰의 시계)으로 재면 안 된다. 두 기기의 시계는
  /// 늘 몇 초씩 어긋나 있고, 8초 느린 폰과 달리면 데이터가 3초마다 멀쩡히
  /// 도착하는데도 화면은 러닝 내내 '신호 약함'으로 남는다. 반대로 빨리 가는
  /// 폰이면 영영 낡지 않는다. 내 시계 하나로만 재면 그 문제가 사라진다
  DateTime? _partnerLiveAt;

  /// 마지막으로 스냅샷을 남긴 시각 — 타이머와 위치 콜백이 서로 겹쳐 부를 때
  /// 저장이 몰리지 않도록 여기서 간격을 맞춘다
  DateTime? _lastSnapshotAt;

  /// Always 권한을 못 받아 화면을 끄면 기록이 멈추는 상태. 이때만 화면을
  /// 강제로 켜두고, 왜 그런지 사용자에게도 알려줌
  bool _screenMustStayOn = false;

  // ── 제스처 상호작용(탭/스와이프/롱프레스로 상대에게 신호 보내기) ──
  // 연출은 전부 캔버스가 이벤트를 받아서 한다. 여기 남는 것은 손가락을
  // 읽는 일과, 같은 신호를 연달아 보내지 못하게 막는 일뿐
  StreamSubscription? _sessionSub;
  DateTime? _lastPartnerGestureAt;
  Offset? _gestureStart;
  Timer? _holdTimer;
  final _cooldown = SignalCooldown();

  // ── 라이브 동기화 ──
  // 내 케이던스를 읽어 세션 문서에 쓰고, 상대 것을 같은 구독에서 받아
  // 공명 엔진에 흘려 넣는다. 데모는 DemoResonanceDriver가 대신 흘린다
  StreamSubscription<double>? _cadenceSub;
  double? _myCadence;

  /// 상대 케이던스의 출처. 지금은 라이브 하나뿐이지만, 고스트(P4)가 붙으면
  /// 여기만 바뀌고 아래 발맞춤 경로는 그대로다 — 시차 공명이 라이브 공명과
  /// 같은 판정을 타게 하는 것이 P2의 목적이었다
  final PartnerCadenceSource _partnerCadence = LivePartnerCadence();
  final _liveGate = LiveWriteGate();

  // ── 멈춤 길게 누르기 진행 링 ──
  // 링이 차는 시간은 [kLongPressTimeout]과 같아야 한다 — 링이 다 찬 순간과
  // onLongPress가 뜨는 순간이 어긋나면 "다 찼는데 왜 안 되지"가 된다
  late final AnimationController _stopHoldController;
  final _stopHold = ValueNotifier<double>(0);

  // ── 공명 이벤트 레이어 ──
  // 화면·소리·햅틱이 각자 "지금 바뀌었나"를 판정하지 않도록, 판정은 엔진
  // 한 곳에서만 하고 나머지는 이벤트만 받는다. 아직 구독자는 디버그 로그
  // 하나뿐이며, broadcast 스트림이라 아무도 안 들으면 이벤트는 그냥 버려진다
  final _resonance = ResonanceEngine();
  DemoResonanceDriver? _demoResonance;
  ResonanceEventLog? _resonanceLog;
  StreamSubscription<ResonanceEvent>? _stateSub;

  /// 상태어에 쓰는 값. 원 그림은 매 프레임 엔진을 직접 읽지만, 텍스트는
  /// 전이가 있을 때만 바뀌면 되므로 여기 담아두고 그때만 리빌드한다
  SyncState _syncState = SyncState.drifting;

  /// 공명 사운드. **꺼져 있으면 아예 만들지 않는다** — 오디오 세션을 잡는
  /// 것 자체가 다른 앱의 재생에 영향을 주기 때문
  ResonanceSound? _sound;

  /// 1km 브리핑. 사운드와 독립된 설정이라 따로 켠다
  RunBriefing? _briefing;

  @override
  void initState() {
    super.initState();
    ActiveRunGuard.active = true;
    // 시간대는 시작할 때 한 번만 정한다. 매 프레임 `DateTime.now()`로 고르면
    // 19시를 넘기는 러닝에서 달리는 도중에 노을이 밤으로 뒤집히고, 그 순간
    // 층 일곱 개의 [ui.Picture]가 프레임 안에서 통째로 다시 구워진다
    _worldTime = WorldPalette.timeFor(DateTime.now());
    if (kDebugMode) _resonanceLog = ResonanceEventLog.attach(_resonance);
    // 데모는 가상 파트너가, 실세션은 상대의 live 데이터가 발맞춤을 만든다.
    // 둘 다 결국 engine.addSample로 들어가는 같은 경로다
    if (widget.demo) {
      _demoResonance = DemoResonanceDriver(_resonance)..start();
    } else {
      // 케이던스는 없을 수 있다(시뮬레이터·권한 거부). 그때는 그냥 값이
      // 안 오고, 공명은 '함께' 고정으로 남는다 — 기능 저하이지 실패가 아니다
      _cadenceSub = CadenceService().stream().listen((spm) => _myCadence = spm);
    }
    _stateSub = _resonance.events.listen((e) {
      if (e is! ResonanceStateChanged || !mounted) return;
      setState(() => _syncState = e.to);
    });
    _stopHoldController =
        AnimationController(vsync: this, duration: kLongPressTimeout)
          ..addListener(() => _stopHold.value = _stopHoldController.value);
    WakelockPlus.enable();
    _startSoundIfEnabled();
    if (!widget.demo) _listenPartnerGesture();
    _start();
  }

  /// 설정을 읽고 켜져 있을 때만 사운드를 올린다. 화면이 먼저 떠 있어도
  /// 상관없다 — 패드는 어차피 나란히(0.70) 이상에서만 들린다
  Future<void> _startSoundIfEnabled() async {
    if (!await SoundSettings.load()) return;
    if (!mounted) return;
    final session = AudioSessionController(
      onAudibleChanged: (audible) => _sound?.setAudible(audible),
    );
    final sound = ResonanceSound(
      engine: _resonance,
      sound: SoLoudSoundEngine(),
      session: session,
    );
    _sound = sound;
    await sound.start();

    if (!await SoundSettings.loadBriefing()) return;
    if (!mounted) {
      await sound.stop();
      return;
    }
    // 오디오 세션은 사운드 쪽이 이미 잡았다. 브리핑은 그 위에서 잠깐
    // 덕킹만 걸었다 푼다
    final briefing = RunBriefing(
      engine: _resonance,
      partnerName: widget.partnerName,
      session: session,
      onSpeaking: sound.setSpeaking,
    );
    _briefing = briefing;
    await briefing.start();
  }

  /// 세션 문서 하나를 구독해 **제스처와 상대 live를 함께** 받는다
  void _listenPartnerGesture() {
    _sessionSub = RunService().sessionStream(widget.sessionId).listen((doc) {
      _readPartnerLive(doc.data());
      final g = doc.data()?['gesture'] as Map<String, dynamic>?;
      if (g == null || g['uid'] == AuthService().uid) return;
      final at = (g['at'] as Timestamp?)?.toDate();
      if (at == null) return;
      if (_lastPartnerGestureAt != null && !at.isAfter(_lastPartnerGestureAt!)) {
        return;
      }
      _lastPartnerGestureAt = at;
      _resonance.signalReceived(
          SignalKind.fromGestureType(g['type'] as String), at: at);
    });
  }

  /// 상대의 실시간 상태 — **제스처와 같은 구독을 쓴다.** 구독을 하나 더
  /// 만들면 같은 문서를 두 번 듣게 되고 읽기 비용이 두 배가 된다
  void _readPartnerLive(Map<String, dynamic>? data) {
    final live = data?['live'] as Map<String, dynamic>?;
    if (live == null) return;
    final myUid = AuthService().uid;
    LiveState? next;
    for (final entry in live.entries) {
      if (entry.key == myUid) continue;
      // 구버전이 스칼라를 써 넣었을 수도 있다. 캐스트가 던지면 스트림 구독이
      // 통째로 죽어 러닝 내내 상대가 안 보인다
      final raw = entry.value;
      if (raw is! Map) continue;
      final state = LiveState.fromMap(Map<String, dynamic>.from(raw));
      if (state == null) continue;
      (_partnerCadence as LivePartnerCadence)
          .update(spm: state.cadenceSpm, at: state.at);
      next = state;
    }
    // 화면에도 그린다 — 예전에는 케이던스만 꺼내 쓰고 페이스·거리를 버렸다.
    // setState는 루프 밖에서 한 번만 부른다
    if (next != null && mounted) {
      setState(() {
        _partnerLive = next;
        _partnerLiveAt = DateTime.now();
      });
    }
  }

  Future<void> _start() async {
    // 경과 시간은 틱 카운트가 아니라 시작 시각과의 차이로 계산 —
    // 폰이 잠겨 있는 동안 Timer 틱이 밀려도(백그라운드에서는 흔함)
    // 화면에 다시 나타났을 때 표시되는 시간이 실제와 어긋나지 않음
    _startedAt = DateTime.now();
    if (widget.demo) {
      // 미리보기: GPS 없이 가상 거리 증가 (시뮬레이터는 실제 GPS가 없어요)
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final t = DateTime.now().difference(_startedAt!).inSeconds;
        // 미리보기는 첫인상이다. 상대 칸이 비어 있으면 고장난 화면으로 읽힌다 —
        // 두 사람이 실제로 달리는 것처럼 값을 만들어 넣는다
        _myCadence = 176 + 4 * math.sin(t / 11);
        setState(() {
          _seconds = t;
          _km = t * 0.003; // 약 5'30"/km 페이스
          _instantSecPerKm = 325 + 15 * math.sin(t / 14);
          _partnerLive = LiveState(
            paceSecPerKm: 330,
            instantPaceSecPerKm: (318 + 14 * math.sin(t / 17)).round(),
            cadenceSpm: 174 + 5 * math.sin(t / 13 + 1.2),
            km: t * 0.0031,
            at: DateTime.now(),
          );
          _partnerLiveAt = DateTime.now();
        });
        _reportProgress();
      });
      return;
    }
    final ok = await _location.requestPermission(
      onBeforeAlwaysUpgrade: () {
        if (!mounted) return Future.value();
        return GoDialog.notice(
          context,
          title: '위치 접근 허용',
          body: '화면을 꺼도 러닝 기록이 끊기지 않으려면,\n다음 화면에서 "항상 허용"을 선택해 주세요.',
        );
      },
    );
    if (!ok) {
      setState(() => _gpsOk = false);
      return;
    }
    // Always 권한을 받았으면 폰을 잠가도 GPS가 계속 돌므로 화면을 켜둘 이유가
    // 없음 — 30~60분 화면을 켜두는 건 러닝 중 최대 배터리 소비원임.
    // When In Use만 받았으면 화면이 꺼지는 순간 거리가 멈추므로 그대로 켜둠
    if (_location.tracksInBackground) {
      WakelockPlus.disable();
    } else if (mounted) {
      setState(() => _screenMustStayOn = true);
    }
    _location.start(
      (km) {
        setState(() {
          _km = km;
          _instantSecPerKm = _location.stats?.instantSecPerKm;
        });
        // 위치가 갱신될 때도 스냅샷을 남긴다 — 아래 _saveSnapshot 주석 참조
        _saveSnapshot();
        // **배경에서는 이쪽이 유일한 경로다.** 화면이 꺼지면 1초 타이머가
        // 멈추므로(실측 35초까지) 여기서도 부르지 않으면 상대 화면에서
        // 내가 통째로 사라진다
        _reportProgress();
      },
      onError: _handleGpsError,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _seconds = _elapsedSeconds;
        // 멈춰 서 있으면 위치 콜백이 아예 안 온다(distanceFilter 5m).
        // 그때도 현재 페이스는 늘어져야 하므로 타이머에서도 읽는다
        _instantSecPerKm = _location.stats?.instantSecPerKm;
      });
      _saveSnapshot();
      _reportProgress();
    });
  }

  /// 1km 통과·10분 경과 같은 지점을 공명 레이어에 알린다. 엔진이 중복을
  /// 걸러주므로 매 틱 불러도 된다
  void _reportProgress() {
    final now = DateTime.now();
    _resonance.updateProgress(
      km: _km,
      elapsed: Duration(seconds: _elapsedSeconds),
      at: now,
    );
    if (!widget.demo) {
      _pushLiveIfChanged(now);
      _feedCloseness(now);
    }
  }

  /// 내 상태를 상대에게. [LiveWriteGate]가 3초 간격과 변화량을 함께 보고
  /// 정한다 — 신호등에 서 있는 동안 초당 한 번씩 쓰지 않기 위해.
  /// 변화가 없어도 하트비트(10초)마다는 쓴다
  void _pushLiveIfChanged(DateTime now) {
    final secPerKm = _km < 0.02 ? null : (_elapsedSeconds / _km).round();
    final state = LiveState(
      paceSecPerKm: secPerKm,
      instantPaceSecPerKm: _finiteRound(_instantSecPerKm),
      cadenceSpm: _myCadence,
      km: _km,
      at: now,
    );
    if (!_liveGate.shouldWrite(state)) return;
    RunService()
        .pushLive(widget.sessionId, AuthService().uid, state)
        // 부가 정보라 실패해도 러닝을 멈추지 않는다. 3초 뒤 또 시도한다
        .catchError((_) {});
  }

  /// 세계가 흐르는 속도. 빨라지면 도시가 빨리 흐른다.
  ///
  /// **숫자보다 이쪽이 훨씬 직관적이다.** 페이스는 역수 단위라 머리로 한 번
  /// 뒤집어야 하지만, 도시가 빨리 흐르는 것은 몸으로 바로 읽힌다.
  ///
  /// 상·하한을 두는 이유: 신호등에 서면 0으로 수렴해 세계가 얼어붙고,
  /// GPS가 튀면 배경이 순간이동한다. 부드럽게 따라가는 것은 [RunWorld]가 한다
  double get _worldSpeed {
    final p = _instantSecPerKm;
    // 멈춰 서면 30초 창의 거리가 0이 되어 페이스가 무한대다. 이것은 '모름'이
    // 아니라 '가장 느림'이다 — 1.0으로 돌리면 걷다가 서는 순간 도시가 오히려
    // 빨라진다(걷기 0.5 → 정지 1.0)
    if (p != null && p.isInfinite) return 0.5;
    // 창이 아직 안 찼거나 값이 헛것이면 기준 속도
    if (p == null || p.isNaN || p <= 0) return 1;
    return (_kWorldBasePace / p).clamp(0.5, 2.0);
  }

  /// 유한한 값만 반올림한다. `double.infinity.round()`는 던진다 —
  /// 30초 창에 거리가 0이면 즉시 페이스가 무한대가 될 수 있다
  static int? _finiteRound(double? v) =>
      (v == null || !v.isFinite) ? null : v.round();

  /// 지금 믿을 수 있는 상대 케이던스. 낡았으면 null
  double? _freshPartnerCadence() => _partnerCadence.spmAt(
      elapsed: Duration(seconds: _elapsedSeconds), now: DateTime.now());

  /// 상대와 내 케이던스로 발맞춤을 만들어 공명 엔진에 넣는다.
  ///
  /// **낡은 값으로는 아무 말도 하지 않는다.** 상대 데이터가 6초 이상
  /// 지났으면 흘려 넣지 않고, 그러면 엔진의 hasCloseness가 false로 남아
  /// 상태어가 '함께'로 돌아간다 — 모르는 것을 아는 척하지 않는다
  void _feedCloseness(DateTime now) {
    final theirs = _partnerCadence.spmAt(
        elapsed: Duration(seconds: _elapsedSeconds), now: now);
    _resonance.addCadences(mine: _myCadence, theirs: theirs, at: now);
  }

  /// 시작 시각과의 차이로 구한 경과 시간(초).
  ///
  /// 배경에서는 Timer가 멈춰 `_seconds`가 낡은 값으로 남으므로, 스냅샷을
  /// 저장할 때는 이 값을 직접 계산해 써야 한다 — 안 그러면 배경에서 저장한
  /// 기록의 시간이 실제보다 짧게 남는다
  int get _elapsedSeconds => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inSeconds;

  /// 강제 종료 대비 스냅샷. **타이머와 위치 콜백 양쪽에서 부른다.**
  ///
  /// 예전에는 1초 타이머 안에서만 저장했는데, 실기기에서 재보니 앱이 배경으로
  /// 내려가면 **타이머가 35초까지 멈췄다**(2026-08-16 측정). 그 구간에 앱이
  /// 정리되면 그만큼의 기록이 사라진다.
  ///
  /// 그렇다고 위치 콜백만 믿을 수도 없다. `distanceFilter`가 5m라 멈춰 서
  /// 있으면 콜백 자체가 오지 않고, 같은 측정에서 위치 콜백의 공백은 84초로
  /// 오히려 더 컸다.
  ///
  /// 그래서 양쪽 모두에서 부르고, 여기서 간격만 조절한다. 어느 한쪽이 멈춰도
  /// 다른 쪽이 기록을 남기고, 둘 다 멈추면 어차피 손쓸 방법이 없다.
  /// 중복 저장은 같은 키를 덮어쓸 뿐이라 해가 없다.
  void _saveSnapshot() {
    final now = DateTime.now();
    final last = _lastSnapshotAt;
    if (last != null && now.difference(last) < _kSnapshotInterval) return;
    _lastSnapshotAt = now;
    RunRecovery.save(
      sessionId: widget.sessionId,
      partnerName: widget.partnerName,
      km: _km,
      seconds: _elapsedSeconds,
    );
  }

  /// 러닝 도중 위치 서비스가 꺼지거나 권한이 취소되는 등
  /// GPS를 더 이상 쓸 수 없게 됐을 때 — 크래시 대신 안내 화면으로 전환
  void _handleGpsError() {
    if (!mounted) return;
    _timer?.cancel();
    _location.stop();
    setState(() => _gpsOk = false);
  }

  // ── 제스처 상호작용 ──
  // 탭 = "여기 있어", 스와이프 = "힘내", 길게 누르기(550ms) = "천천히 가자".
  // 셋뿐인 이유는 달리면서 넷째를 기억 못 하기 때문이고, 방향을 나누지
  // 않는(위/아래 구분 없는) 이유도 같다 — 팔에 차고 뛰면서 위로 그었는지
  // 아래로 그었는지까지 신경 쓰게 하면 아예 안 쓴다

  void _onGesturePointerDown(PointerDownEvent e) {
    // 두 번째 손가락이 내려오면 첫 타이머는 버린다 — 안 그러면 첫 손가락이
    // 이미 떨어진 뒤에 '천천히 가자'가 혼자 나간다
    _holdTimer?.cancel();
    _gestureStart = e.localPosition;
    _holdTimer = Timer(const Duration(milliseconds: 550), () {
      _sendSignal(SignalKind.slow);
      _gestureStart = null; // 롱프레스로 이미 처리됨 — pointerUp에서 또 판정하지 않음
    });
  }

  void _onGesturePointerUp(PointerUpEvent e) {
    _holdTimer?.cancel();
    final start = _gestureStart;
    if (start == null) return;
    _gestureStart = null;
    final dist = (e.localPosition - start).distance;
    _sendSignal(dist < 14 ? SignalKind.here : SignalKind.cheer);
  }

  void _onGesturePointerCancel(PointerCancelEvent e) {
    _holdTimer?.cancel();
    _gestureStart = null;
  }

  /// 신호를 보낸다. 같은 신호를 연달아 누르면 **조용히 무시된다**
  /// ([SignalCooldown] 참조 — 러닝 중 에러 UI는 죄책감 장치다)
  Future<void> _sendSignal(SignalKind kind) async {
    if (!mounted) return;
    final now = DateTime.now();
    if (!_cooldown.allow(kind, now)) return;
    // 잔상·햅틱은 이벤트를 구독하는 캔버스가 낸다. 여기서 직접 그리면
    // 보낸 신호와 받은 신호의 연출이 두 곳으로 갈라진다
    _resonance.signalSent(kind, at: now);
    if (widget.demo) return;
    try {
      await RunService()
          .sendGesture(widget.sessionId, AuthService().uid, kind.gestureType);
    } catch (e, stack) {
      // 잔상은 이미 보여줬으니 실패해도 조용히 무시 — 재시도 강요 안 함
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  Future<void> _finish(String? mood) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    _timer?.cancel();
    _demoResonance?.stop();
    await _briefing?.stop();
    await _sound?.stop();
    _location.stop();
    WakelockPlus.disable();
    // **_seconds가 아니라 _elapsedSeconds다.** _seconds는 1초 타이머가 올리는
    // 값이라 화면이 꺼져 있던 동안(실측 35초까지) 밀린다. 화면을 끄고 달리는
    // 것은 Always 권한을 받았을 때의 정상 경로이므로, 그 차이가 그대로
    // 제출되는 기록·칼로리·마무리 화면의 오차가 된다
    final finalSeconds = _elapsedSeconds > _seconds ? _elapsedSeconds : _seconds;
    final kcal = LocationService.estimateKcal(finalSeconds);
    if (!widget.demo) {
      try {
        await RunService().submitResult(widget.sessionId, AuthService().uid,
            seconds: finalSeconds, km: _km, kcal: kcal, mood: mood);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
        if (!mounted) return;
        setState(() => _finishing = false);
        GoToast.error(context, '결과 저장에 실패했어요. 다시 시도해 주세요.');
        return;
      }
      // 결과가 서버에 안전히 올라갔으니 로컬 복구 스냅샷은 폐기
      await RunRecovery.clear();
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => FinishScreen(
        sessionId: widget.sessionId,
        partnerName: widget.partnerName,
        mySeconds: finalSeconds,
        myKm: _km,
        myKcal: kcal,
        myMood: mood,
        demo: widget.demo,
      ),
    ));
  }

  @override
  void dispose() {
    _demoResonance?.stop();
    _cadenceSub?.cancel();
    _briefing?.stop();
    _sound?.stop();
    _stopHoldController.dispose();
    _stopHold.dispose();
    _stateSub?.cancel();
    _resonanceLog?.cancel();
    _resonance.dispose();
    _sessionSub?.cancel();
    _holdTimer?.cancel();
    _timer?.cancel();
    _location.stop();
    WakelockPlus.disable();
    ActiveRunGuard.active = false;
    super.dispose();
  }

  /// 실수 종료 방지 — 마치기 전 한 번 확인
  Future<void> _confirmFinish() async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '오늘 러닝을 마칠까요?',
      confirmLabel: '마치기',
      cancelLabel: '계속 달리기',
    );
    if (confirmed != true) {
      // 롱프레스가 이기면 onTapUp이 오지 않아 _cancelStopHold가 불리지 않는다.
      // 여기서 안 풀면 링이 가득 찬 채로 남는다
      _cancelStopHold();
      return;
    }
    if (!mounted) return;
    final mood = await _pickMood();
    if (!mounted) return;
    _finish(mood);
  }

  /// 결과 제출 직전 — 오늘 러닝이 어땠는지 한 탭으로 남김 (건너뛰기 가능)
  Future<String?> _pickMood() async {
    const moods = ['상쾌했어요', '죽을 뻔했어요', '네 생각 났어요', '또 하고 싶어요'];
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: GoRoles.of(context).surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            GoSpace.sheet, GoSpace.xl, GoSpace.sheet, GoSpace.sheetBottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('오늘 러닝, 어땠어요?', style: GoText.heading),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: moods
                    .map((m) => GoButton(m,
                        kind: GoButtonKind.secondary,
                        size: GoButtonSize.md,
                        onTap: () => Navigator.pop(ctx, m)))
                    .toList(),
              ),
              const SizedBox(height: GoSpace.m),
              Center(
                child: GoButton('건너뛰기',
                    kind: GoButtonKind.text,
                    size: GoButtonSize.md,
                    onTap: () => Navigator.pop(ctx, null)),
              ),
            ]),
      ),
    );
  }

  String get _timeText {
    final m = _seconds ~/ 60, s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── 화면에 쓸 값들 ──

  /// 큰 숫자 — 지금 페이스. 창(30초)이 아직 안 찼으면 평균으로 대신한다.
  /// 빈 칸을 보여주면 "고장났다"로 읽힌다
  String get _currentPaceText {
    final inst = _instantSecPerKm;
    if (inst == null) return LocationService.pace(_km, _seconds);
    return LocationService.formatPace(inst);
  }

  String get _averagePaceText => LocationService.pace(_km, _seconds);

  /// 평균 대비 지금. (차이 초, 지금이 더 빠른가). 비교할 게 없으면 null
  (int, bool)? get _paceDelta {
    final inst = _instantSecPerKm;
    if (inst == null ||
        !inst.isFinite ||
        _km < _kMinDistanceForDelta ||
        _seconds <= 0) {
      return null;
    }
    final avg = _seconds / _km;
    if (!avg.isFinite) return null;
    // 20분/km를 넘으면 페이스 자체를 `--'--"`로 감추므로(formatPace),
    // 그 옆에 "41초 빠름"을 붙이면 보여주지도 않은 숫자와의 차이를 말하게 된다
    if (avg > 1200 || inst > 1200) return null;
    final diff = (avg - inst).round(); // 양수 = 지금이 더 빠르다
    if (diff.abs() < _kMinDeltaSeconds) return null;
    return (diff.abs(), diff > 0);
  }

  /// 상대의 신호가 낡았는가. 낡으면 **값은 남기고 채도만 뺀다** —
  /// 사라지면 상대가 없어지고, 흐려지면 상대가 멀어진다
  bool get _partnerStale {
    final at = _partnerLiveAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > _kPartnerStaleAfter;
  }

  String? get _partnerStaleNote {
    final at = _partnerLiveAt;
    if (at == null) return null;
    final gap = math.max(0, DateTime.now().difference(at).inSeconds);
    return gap < 60 ? '$gap초 전' : '${gap ~/ 60}분 전';
  }

  String get _partnerPaceText {
    final sec = _partnerLive?.displayPaceSecPerKm;
    if (sec == null) return "--'--\"";
    return LocationService.formatPace(sec.toDouble());
  }

  String get _partnerKmText =>
      (_partnerLive?.km ?? 0).toStringAsFixed(2);

  /// 상태어 — 이 화면의 두 번째 주인공.
  ///
  /// 발맞춤 값이 없는 실제 세션에서는 상태를 아는 척하지 않고 '함께'만 쓴다
  String get _stateWord {
    if (!_resonance.hasCloseness) return '함께';
    return switch (_syncState) {
      SyncState.drifting => '각자의 리듬',
      SyncState.approaching => '가까워져요',
      SyncState.aligned => '나란히',
      SyncState.resonant => '공명',
    };
  }

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    if (!_gpsOk) {
      // 경로를 글로만 알려주면(설정 > GoingOn > 위치) 사람들은 앱을 나가
      // 헤매다 돌아오지 않는다. 여기서 바로 앱 설정을 열어주고, 돌아올
      // 곳도 남긴다 — 막다른 화면을 만들지 않는다
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('위치 권한이 필요해요', style: GoText.heading),
              const SizedBox(height: 10),
              Text('달린 거리를 재려면 위치 접근이 필요해요.\n좌표는 기기 밖으로 나가지 않아요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 1.5, color: roles.textSecondary)),
              const SizedBox(height: GoSpace.section),
              GoButton('설정 열기',
                  icon: Icons.settings_outlined,
                  onTap: () => ph.openAppSettings()),
              const SizedBox(height: GoSpace.s),
              GoButton('돌아가기',
                  kind: GoButtonKind.text,
                  size: GoButtonSize.md,
                  onTap: () => Navigator.maybePop(context)),
            ]),
          ),
        ),
      );
    }

    // 달리는 중에는 화면을 벗어날 수 없게 막음. iOS는 화면 왼쪽에서
    // 스와이프하면 뒤로 가는데, 주머니에 넣거나 팔에 차고 달리다 그 제스처가
    // 들어가면 러닝이 통째로 버려짐(기록 미제출 + 화면 이탈). 마치려면
    // 반드시 '길게 눌러 종료'를 거치게 함
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_finishing) _confirmFinish();
      },
      child: _runBody(),
    );
  }

  /// 배경 위에서도 숫자가 읽히게 하는 그림자. 스크림만으로는 모자란다 —
  /// 도시의 불빛과 숫자가 같은 밝기로 겹치는 자리가 반드시 생긴다
  List<Shadow> get _numShadow => GoRoles.of(context).runDark.numShadow;

  /// 캡션 라벨 — 이 화면에서 34px 미만이 허용되는 **유일한** 글자.
  /// 달리는 사람은 3초 이상 화면을 못 본다는 전제에서, 값은 크게 두고
  /// 값이 무엇인지 알려주는 꼬리표만 작게 남긴다
  Widget _caption(String text, {Color? color}) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: color ?? _tone.secondary,
          shadows: _numShadow,
        ),
      );

  Widget _runBody() {
    // 러닝 화면만 앱에서 떼어낸다. 로비까지는 종이, 달리기 시작하면 잉크로
    // 내려앉는다 — 그 전환 자체가 "시작했다"는 신호가 되고, 야간 러닝의
    // 눈부심과 OLED 배터리까지 같이 해결된다.
    //
    // 그리고 밝은 종이 위에서는 어떤 색도 빛날 수 없다. 라임이 형광으로
    // 살아나려면 어둠이 필요하다
    final time = _worldTime;
    return Scaffold(
      backgroundColor: GoRoles.of(context).runDark.bg,
      body: Stack(children: [
        Positioned.fill(
          child: RunWorld(speed: _worldSpeed, time: time, enabled: !_finishing),
        ),
        _scrims(time),
        Positioned.fill(
          child: SafeArea(
            child: LayoutBuilder(builder: (context, c) => _runColumn(time, c)),
          ),
        ),
      ]),
    );
  }

  /// 배경 위에서 숫자가 이기게 하는 장치.
  ///
  /// 처음에는 배경이 숫자를 그대로 삼켰고, 스크림을 세게 넣으니 이번엔
  /// 배경이 죽었다. 지금은 **좁고 옅게** 깔고 숫자 자체에 그림자를 준다.
  /// 이 균형은 실기에서 다시 잡아야 한다 — 한여름 대낮 야외는 또 다르다
  Widget _scrims(WorldTime time) {
    final v = WorldPalette.veil(time);
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, c) {
          // 고정 높이(200 + 252)는 세로 452pt 아래에서 Column을 넘긴다.
          // 화면이 작아지면 스크림도 같이 줄어야 한다
          final h = c.maxHeight.isFinite ? c.maxHeight : 844.0;
          final top = math.min(200.0, h * .26);
          final bottom = math.min(252.0, h * .32);
          return Column(children: [
            Container(
              height: top,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    v.withValues(alpha: .84),
                    v.withValues(alpha: .48),
                    v.withValues(alpha: 0),
                  ],
                  stops: const [0, .56, 1],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: bottom,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    v.withValues(alpha: .90),
                    v.withValues(alpha: .54),
                    v.withValues(alpha: 0),
                  ],
                  stops: const [0, .46, 1],
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  /// 시작할 때 정한 시간대. 러닝 중에는 바뀌지 않는다
  late final WorldTime _worldTime;

  /// SE(세로 약 600pt)에서도 캔버스가 남도록 하는 문턱
  static const _kTightHeight = 700.0;

  /// 어둠 위의 글자 세 색
  RunTextTone get _tone {
    final dark = GoRoles.of(context).runDark;
    return RunTextTone(
      primary: dark.text,
      secondary: dark.textSecondary,
      disabled: dark.textDisabled,
      shadows: dark.numShadow,
    );
  }

  Widget _runColumn(WorldTime time, BoxConstraints c) {
    final delta = _paceDelta;
    const gutter = EdgeInsets.symmetric(horizontal: 26);
    final tight = c.maxHeight < _kTightHeight;
    final myPaceSize = tight ? 52.0 : 64.0;
    final myKmSize = tight ? 40.0 : 48.0;
    final partnerPaceSize = tight ? 38.0 : 46.0;
    final partnerKmSize = tight ? 30.0 : 36.0;
    final gap = tight ? 10.0 : 16.0;
    final dark = GoRoles.of(context).runDark;
    final night = time == WorldTime.night;
    final me = dark.self(night: night);
    final you = dark.partner(night: night);

    return Column(children: [
      const SizedBox(height: 10),
      Padding(
        padding: gutter,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_timeText,
                    style: GoTheme.serif(26, color: dark.text)
                        .copyWith(shadows: _numShadow)),
                const SizedBox(width: 8),
                _caption('함께'),
              ],
            ),
            Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _partnerStale ? dark.textDisabled : dark.online,
                ),
              ),
              const SizedBox(width: 6),
              _caption(_partnerStale ? '신호 약함' : '연결됨'),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // 위가 상대, 아래가 나. 이 순서는 화면 전체에서 한 번도 뒤집히지 않는다
      Padding(
        padding: gutter,
        child: RunStatBlock(
          name: widget.partnerName,
          color: you,
          pace: _partnerPaceText,
          km: _partnerKmText,
          paceLabel: '페이스',
          paceSize: partnerPaceSize,
          kmSize: partnerKmSize,
          stale: _partnerStale,
          staleNote: _partnerStaleNote,
          tone: _tone,
        ),
      ),

      Expanded(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onGesturePointerDown,
          onPointerUp: _onGesturePointerUp,
          onPointerCancel: _onGesturePointerCancel,
          child: ResonanceCanvas(
            engine: _resonance,
            myCadence: () => _myCadence,
            partnerCadence: _freshPartnerCadence,
            selfColor: me,
            partnerColor: you,
            resonanceColor: dark.resonance,
            haloColor: dark.halo,
          ),
        ),
      ),

      AnimatedSwitcher(
        duration: GoMotion.update,
        child: Text(_stateWord,
            key: ValueKey(_stateWord),
            style: TextStyle(
              fontSize: tight ? 22 : 26,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -.3,
              color: _resonance.hasCloseness && _syncState == SyncState.resonant
                  ? dark.resonance
                  : dark.text,
              shadows: _numShadow,
            )),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _caption(
            '${widget.partnerName} ${_finiteRound(_partnerLive?.cadenceSpm) ?? '—'}',
            color: _partnerStale ? _tone.disabled : you),
        const SizedBox(width: 22),
        _caption('나 ${_finiteRound(_myCadence) ?? '—'}', color: me),
      ]),
      SizedBox(height: gap),

      // 큰 숫자는 '지금' 페이스, 아래 한 줄이 기준점
      Padding(
        padding: gutter,
        child: RunStatBlock(
          name: '나',
          color: me,
          pace: _currentPaceText,
          km: _km.toStringAsFixed(2),
          paceLabel: '지금 페이스',
          paceSize: myPaceSize,
          kmSize: myKmSize,
          tone: _tone,
          footnote: PaceFootnote(
            averagePace: _averagePaceText,
            deltaSeconds: delta?.$1,
            fasterThanAverage: delta?.$2 ?? false,
            fastColor: me,
            tone: _tone,
          ),
        ),
      ),

      SizedBox(height: gap + 2),
      _stopButton(),
      const SizedBox(height: 5),
      _caption('길게 누르면 종료'),
      // 위치를 "항상 허용"으로 못 받은 경우에만 — 화면이 꺼지면 거리가
      // 멈추므로, 사용자가 이유를 모른 채 기록을 잃지 않도록 알려줌
      if (_screenMustStayOn) ...[
        const SizedBox(height: 10),
        Padding(
          padding: gutter,
          child: _caption('화면을 끄면 거리가 멈춰요 — 위치를 "항상 허용"으로 바꾸면 꺼도 기록돼요',
              color: dark.warning),
        ),
      ],
      SizedBox(height: tight ? GoSpace.m : GoSpace.section),
    ]);
  }

  /// 멈춤 — 러닝 중 유일한 주요 조작이라 터치 타겟을 76pt로 잡았다
  /// (권장 최소 72pt). 달리면서 흔들리는 손으로 누르는 버튼이다.
  ///
  /// 길게 누르는 동안 테두리를 따라 진행 링이 찬다. 링이 없을 때는 얼마나
  /// 눌러야 하는지 알 수 없어서, 사람들이 중간에 손을 떼고 "왜 안 되지"
  /// 하다가 결국 짧게 여러 번 누른다
  Widget _stopButton() {
    final dark = GoRoles.of(context).runDark;
    return GestureDetector(
      onTapDown: _finishing ? null : (_) => _beginStopHold(),
      onTapUp: (_) => _cancelStopHold(),
      onTapCancel: _cancelStopHold,
      onLongPress: _finishing
          ? null
          : () {
              // 컨트롤러를 세우지 않으면 다음 프레임에 리스너가 _stopHold를
              // 진행 중이던 값(~0.8)으로 되돌려, 링이 가득 찼다가 다시 줄었다
              // 차오른다
              _stopHoldController.stop();
              // 링이 다 찼다는 것을 손으로도 알려준다 — 여기서부터는
              // 손을 떼도 확인 다이얼로그가 뜬다
              HapticFeedback.mediumImpact();
              _stopHold.value = 1;
              _confirmFinish();
            },
      child: SizedBox(
        width: _kStopButtonSize,
        height: _kStopButtonSize,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // 러닝 화면에서 유일하게 눌러야 하는 것 — 곁눈으로도 "누르는 것"으로
              // 읽혀야 한다. 어둠 위에서는 그림자가 안 보이므로 옅은 테두리로 띄운다
              border: Border.all(color: dark.text.withValues(alpha: .30), width: 1.5),
            ),
          ),
          // 링은 누르는 동안에만 그린다. 색은 ink 계열 — lime(나)도
          // coral(상대)도 gold(공명)도 아닌, 이 앱에서 색 뜻이 없는 자리
          RepaintBoundary(
            child: CustomPaint(
              size: const Size.square(_kStopButtonSize),
              painter: _StopHoldPainter(
                  _stopHold, dark.text.withValues(alpha: .55)),
            ),
          ),
          Text('멈춤',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _tone.secondary)),
        ]),
      ),
    );
  }

  void _beginStopHold() {
    HapticFeedback.selectionClick();
    _stopHoldController.forward(from: 0);
  }

  void _cancelStopHold() {
    if (_stopHoldController.isAnimating || _stopHold.value > 0) {
      _stopHoldController.stop();
      _stopHold.value = 0;
    }
  }
}

/// 멈춤 버튼 테두리를 따라 차오르는 진행 링.
///
/// 위젯 트리를 다시 만들지 않고 [ValueNotifier] 하나로만 다시 그린다 —
/// 러닝 화면은 원 애니메이션이 이미 매 프레임 돌고 있어서, 여기까지
/// setState로 그리면 화면 전체가 초당 60번 리빌드된다
class _StopHoldPainter extends CustomPainter {
  _StopHoldPainter(this.progress, this.color) : super(repaint: progress);

  final ValueListenable<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(1.5),
      -math.pi / 2, // 12시에서 시작 — 시계처럼 읽힌다
      2 * math.pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _StopHoldPainter old) => false;
}
