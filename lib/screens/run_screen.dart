import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode, ValueListenable;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/demo_resonance.dart';
import '../services/location_service.dart';
import '../services/resonance.dart';
import '../services/run_recovery.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import '../widgets/pressable.dart';
import '../widgets/resonance_canvas.dart';
import 'finish_screen.dart';

/// 강제 종료 대비 스냅샷을 남기는 최소 간격.
/// 예전에도 5초 주기였고 그대로 유지한다. 달라진 것은 이제 타이머뿐 아니라
/// 위치 콜백에서도 저장을 부르며, 어느 쪽에서 불리든 이 간격이 지켜진다는 점
const _kSnapshotInterval = Duration(seconds: 5);

/// 멈춤 버튼 지름. 러닝 중 주요 조작의 최소 터치 타겟(72pt)보다 크게 잡는다
const _kStopButtonSize = 76.0;

/// 러닝 화면 — 각자 GPS로 기록, 끝나면 합산 (MVP: 라이브 동기화 없음)
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

  @override
  void initState() {
    super.initState();
    ActiveRunGuard.active = true;
    if (kDebugMode) _resonanceLog = ResonanceEventLog.attach(_resonance);
    // 실제 세션에는 발맞춤을 알 방법이 아직 없다(러닝 중 실시간 동기화 없음).
    // 그래서 연속값을 흘려 넣는 곳은 데모의 가상 파트너뿐이고, 실제 세션에서는
    // 신호·마일스톤 이벤트만 흐른다
    if (widget.demo) _demoResonance = DemoResonanceDriver(_resonance)..start();
    _stateSub = _resonance.events.listen((e) {
      if (e is! ResonanceStateChanged || !mounted) return;
      setState(() => _syncState = e.to);
    });
    _stopHoldController =
        AnimationController(vsync: this, duration: kLongPressTimeout)
          ..addListener(() => _stopHold.value = _stopHoldController.value);
    WakelockPlus.enable();
    if (!widget.demo) _listenPartnerGesture();
    _start();
  }

  /// 상대가 보낸 제스처 신호 감지 — 위치/페이스는 안 보내고 이 필드 하나만 봄
  void _listenPartnerGesture() {
    _sessionSub = RunService().sessionStream(widget.sessionId).listen((doc) {
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

  Future<void> _start() async {
    // 경과 시간은 틱 카운트가 아니라 시작 시각과의 차이로 계산 —
    // 폰이 잠겨 있는 동안 Timer 틱이 밀려도(백그라운드에서는 흔함)
    // 화면에 다시 나타났을 때 표시되는 시간이 실제와 어긋나지 않음
    _startedAt = DateTime.now();
    if (widget.demo) {
      // 미리보기: GPS 없이 가상 거리 증가 (시뮬레이터는 실제 GPS가 없어요)
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _seconds = DateTime.now().difference(_startedAt!).inSeconds;
          _km = _seconds * 0.003; // 약 5'30"/km 페이스
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
        setState(() => _km = km);
        // 위치가 갱신될 때도 스냅샷을 남긴다 — 아래 _saveSnapshot 주석 참조
        _saveSnapshot();
      },
      onError: _handleGpsError,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds = _elapsedSeconds);
      _saveSnapshot();
      _reportProgress();
    });
  }

  /// 1km 통과·10분 경과 같은 지점을 공명 레이어에 알린다. 엔진이 중복을
  /// 걸러주므로 매 틱 불러도 된다
  void _reportProgress() => _resonance.updateProgress(
        km: _km,
        elapsed: Duration(seconds: _elapsedSeconds),
        at: DateTime.now(),
      );

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
    _location.stop();
    WakelockPlus.disable();
    final kcal = LocationService.estimateKcal(_seconds);
    if (!widget.demo) {
      try {
        await RunService().submitResult(widget.sessionId, AuthService().uid,
            seconds: _seconds, km: _km, kcal: kcal, mood: mood);
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
        mySeconds: _seconds,
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
    if (confirmed != true) return;
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
      backgroundColor: GoColors.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('오늘 러닝, 어땠어요?', style: GoTheme.serif(20)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: moods
                    .map((m) => Pressable(
                          onTap: () => Navigator.pop(ctx, m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: GoColors.line, width: 1.5),
                            ),
                            child: Text(m,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: GoColors.ink)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('건너뛰기',
                      style: TextStyle(color: GoColors.dim, fontSize: 13)),
                ),
              ),
            ]),
      ),
    );
  }

  String get _timeText {
    final m = _seconds ~/ 60, s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_gpsOk) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('위치 권한이 필요해요', style: GoTheme.serif(24)),
              const SizedBox(height: 10),
              const Text('설정 > GoingOn > 위치에서 허용해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
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


  /// 캡션 라벨 — 이 화면에서 34px 미만이 허용되는 **유일한** 글자.
  /// 달리는 사람은 3초 이상 화면을 못 본다는 전제에서, 값은 크게 두고
  /// 값이 무엇인지 알려주는 꼬리표만 작게 남긴다
  Widget _caption(String text, {Color color = GoColors.dim}) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: color,
        ),
      );

  /// 상태어 — 이 화면의 두 번째 주인공.
  ///
  /// 발맞춤 값이 없는 실제 세션에서는 상태를 아는 척하지 않고 '함께'만 쓴다
  /// ([ResonanceEngine.hasCloseness] 주석 참조)
  String get _stateWord {
    if (!_resonance.hasCloseness) return '함께';
    return switch (_syncState) {
      SyncState.drifting => '각자의 리듬',
      SyncState.approaching => '가까워져요',
      SyncState.aligned => '나란히',
      SyncState.resonant => '공명',
    };
  }

  /// 공명일 때만 골드. 그 외에는 상대의 색(coral) — 색 배정은 섞지 않는다
  Color get _stateColor =>
      _resonance.hasCloseness && _syncState == SyncState.resonant
          ? GoColors.resonance
          : GoColors.coralDark;

  Widget _runBody() {
    return Scaffold(
      backgroundColor: GoColors.canvas,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 8),
          // ── 내 페이스 — 곁눈으로 0.5초 안에 읽혀야 하는 단 하나의 숫자 ──
          _caption('나 · 페이스',
              color: GoColors.limeDark.withValues(alpha: .6)),
          Text(LocationService.pace(_km, _seconds),
              style: GoTheme.serif(68, color: GoColors.limeDark)
                  .copyWith(height: 1.1)),
          _caption('km당'),
          const SizedBox(height: 14),
          // ── 상대 상태어 ──
          _caption('${widget.partnerName} · 상태',
              color: GoColors.coralDark.withValues(alpha: .6)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(_stateWord,
                key: ValueKey(_stateWord),
                style: GoTheme.serif(44, color: _stateColor)
                    .copyWith(height: 1.2)),
          ),
          // ── 겹치는 두 원 (탭·스와이프·길게 누르기로 신호) ──
          // 신호에는 글자가 붙지 않는다 — 보낸 것은 잔상으로, 받은 것은
          // 상대 원의 맥동과 햅틱으로만 온다
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onGesturePointerDown,
              onPointerUp: _onGesturePointerUp,
              onPointerCancel: _onGesturePointerCancel,
              child: ResonanceCanvas(engine: _resonance),
            ),
          ),
          // ── 함께 달린 것 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: GoColors.line),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .05),
                      blurRadius: 6, offset: const Offset(0, 1)),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                _togetherCell(_timeText, '시간'),
                _togetherDivider(),
                _togetherCell(_km.toStringAsFixed(1), 'km'),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          _stopButton(),
          const SizedBox(height: 5),
          _caption('길게 누르면 종료'),
          // 위치를 "항상 허용"으로 못 받은 경우에만 — 화면이 꺼지면 거리가
          // 멈추므로, 사용자가 이유를 모른 채 기록을 잃지 않도록 알려줌
          if (_screenMustStayOn) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _caption('화면을 끄면 거리가 멈춰요 — 위치를 "항상 허용"으로 바꾸면 꺼도 기록돼요',
                  color: GoColors.amber.withValues(alpha: .9)),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  /// 멈춤 — 러닝 중 유일한 주요 조작이라 터치 타겟을 76pt로 잡았다
  /// (권장 최소 72pt). 달리면서 흔들리는 손으로 누르는 버튼이다.
  ///
  /// 길게 누르는 동안 테두리를 따라 진행 링이 찬다. 링이 없을 때는 얼마나
  /// 눌러야 하는지 알 수 없어서, 사람들이 중간에 손을 떼고 "왜 안 되지"
  /// 하다가 결국 짧게 여러 번 누른다
  Widget _stopButton() {
    return GestureDetector(
      onTapDown: _finishing ? null : (_) => _beginStopHold(),
      onTapUp: (_) => _cancelStopHold(),
      onTapCancel: _cancelStopHold,
      onLongPress: _finishing
          ? null
          : () {
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
              color: GoColors.ink.withValues(alpha: .07),
              border: Border.all(color: GoColors.ink.withValues(alpha: .1)),
            ),
          ),
          // 링은 누르는 동안에만 그린다. 색은 ink 계열 — lime(나)도
          // coral(상대)도 gold(공명)도 아닌, 이 앱에서 색 뜻이 없는 자리
          RepaintBoundary(
            child: CustomPaint(
              size: const Size.square(_kStopButtonSize),
              painter: _StopHoldPainter(_stopHold),
            ),
          ),
          const Text('멈춤',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GoColors.mid)),
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

  Widget _togetherCell(String value, String label) => Expanded(
        child: Column(children: [
          Text(value,
              style: GoTheme.serif(40, color: GoColors.ink)
                  .copyWith(height: 1.1)),
          _caption(label),
        ]),
      );

  Widget _togetherDivider() =>
      Container(width: 1, height: 44, color: GoColors.line);
}

/// 멈춤 버튼 테두리를 따라 차오르는 진행 링.
///
/// 위젯 트리를 다시 만들지 않고 [ValueNotifier] 하나로만 다시 그린다 —
/// 러닝 화면은 원 애니메이션이 이미 매 프레임 돌고 있어서, 여기까지
/// setState로 그리면 화면 전체가 초당 60번 리빌드된다
class _StopHoldPainter extends CustomPainter {
  _StopHoldPainter(this.progress) : super(repaint: progress);

  final ValueListenable<double> progress;

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
        ..color = GoColors.ink.withValues(alpha: .45),
    );
  }

  @override
  bool shouldRepaint(covariant _StopHoldPainter old) => false;
}
