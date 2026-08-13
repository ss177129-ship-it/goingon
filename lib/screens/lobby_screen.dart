import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import 'run_screen.dart';

/// 로비 — 프로토타입 s-lobby 충실 구현
/// 준비 단계: 집에서 출발 → 준비운동 → 도착 → 준비완료
/// demo: true면 Firestore 없이 가상 파트너로 진행
class LobbyScreen extends StatefulWidget {
  final String sessionId;
  final String partnerName;
  final bool demo;
  const LobbyScreen(
      {super.key,
      required this.sessionId,
      required this.partnerName,
      this.demo = false});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _Step {
  final IconData icon;
  final String text;
  const _Step(this.icon, this.text);
}

const _steps = [
  _Step(Icons.home_rounded, '집에서 출발'),
  _Step(Icons.self_improvement, '준비운동'),
  _Step(Icons.place_outlined, '도착'),
  _Step(Icons.check_circle_outline, '준비완료'),
];

class _LobbyScreenState extends State<LobbyScreen> {
  final _runs = RunService();
  final _uid = AuthService().uid;
  StreamSubscription? _sub;
  int _step = 0;
  bool _isLate = false;
  bool _partnerReady = false;
  bool _partnerLate = false;
  bool _partnerJoined = false;
  bool _showTimeoutHelp = false;
  int? _countdown;
  Timer? _timeoutTimer;
  Timer? _countdownTimer;

  bool get _meReady => _step == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    // 로비/러닝이 떠 있는 동안엔 새 GO? 요청 시트가 홈 화면에 겹쳐 뜨지 않게 함
    ActiveRunGuard.active = true;
    if (widget.demo) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _partnerJoined = true);
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        setState(() => _partnerLate = true);
      });
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (!mounted) return;
        setState(() {
          _partnerLate = false;
          _partnerReady = true;
        });
        _maybeCountdown();
      });
      return;
    }
    _timeoutTimer = Timer(const Duration(minutes: 3), () {
      if (mounted && !_partnerReady) setState(() => _showTimeoutHelp = true);
    });
    _subscribeToSession();
    // 내가 로비에 들어왔다는 걸 상대에게 알림 — 실패해도 진행에는 지장이
    // 없는 부가 정보라 조용히 넘어감
    _runs.enterLobby(widget.sessionId, _uid).catchError((_) {});
  }

  void _subscribeToSession() {
    _sub = _runs.sessionStream(widget.sessionId).listen((doc) {
      final data = doc.data();
      if (data == null) return;
      if (data['status'] == 'cancelled') {
        final declineMessage = data['declineMessage'] as String?;
        if (!mounted) return;
        if (declineMessage != null && declineMessage.isNotEmpty) {
          _sub?.cancel();
          _showDeclineReply(declineMessage);
        } else {
          Navigator.pop(context); // 정리는 PopScope의 _leaveLobby가 처리
        }
        return;
      }
      final ready = Map<String, dynamic>.from(data['ready'] ?? {});
      final partnerReady =
          ready.entries.any((e) => e.key != _uid && e.value == true);
      final late = Map<String, dynamic>.from(data['late'] ?? {});
      final partnerLate =
          late.entries.any((e) => e.key != _uid && e.value == true);
      final joined = Map<String, dynamic>.from(data['joined'] ?? {});
      final partnerJoined =
          joined.entries.any((e) => e.key != _uid && e.value == true);
      setState(() {
        _partnerReady = partnerReady;
        _partnerLate = partnerLate;
        _partnerJoined = partnerJoined;
      });
      _maybeCountdown();
      if (data['status'] == 'running' && _countdown == null) _goRun();
    }, onError: (_) {
      // 세션 감지가 끊기면 조용히 멈추는 대신 잠시 뒤 재구독 — 그래도 안 되면
      // 3분 무응답 타임아웃 안내(_showTimeoutHelp)가 탈출구가 되어줌
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _subscribeToSession();
      });
    });
  }

  void _maybeCountdown() {
    if (_meReady && _partnerReady && _countdown == null) _startCountdown();
  }

  void _advanceStep() {
    if (_countdown != null) return;
    if (_meReady) {
      // 준비완료 취소
      setState(() {
        _step = 2;
        _isLate = false;
      });
      return;
    }
    setState(() {
      _step++;
      _isLate = false;
    });
    if (_meReady) _becomeReady();
  }

  void _jumpToReady() {
    if (_countdown != null || _meReady) return;
    setState(() {
      _step = _steps.length - 1;
      _isLate = false;
    });
    _becomeReady();
  }

  Future<void> _becomeReady() async {
    if (widget.demo) {
      _maybeCountdown();
      return;
    }
    try {
      await _runs.setReady(widget.sessionId, _uid);
      _maybeCountdown();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      // 전달에 실패하면 상대가 내 준비 상태를 영영 못 봄 — 조용히 두지 않고
      // 준비 전 단계로 되돌려 다시 시도할 수 있게 함
      if (!mounted) return;
      setState(() => _step = _steps.length - 2);
      GoToast.error(context, '준비 상태를 전달하지 못했어요. 다시 시도해 주세요.');
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 3);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown! <= 1) {
        t.cancel();
        if (!widget.demo) _runs.startRun(widget.sessionId);
        _goRun();
      } else {
        setState(() => _countdown = _countdown! - 1);
      }
    });
  }

  /// 상대가 "나중에"에 답장을 남기고 거절했을 때 — 침묵 대신 대화로
  Future<void> _showDeclineReply(String message) async {
    await GoDialog.notice(
      context,
      title: '${widget.partnerName}님의 답장',
      body: message,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _goRun() {
    _sub?.cancel();
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => RunScreen(
          sessionId: widget.sessionId,
          partnerName: widget.partnerName,
          demo: widget.demo),
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeoutTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _notifyPartner() async {
    try {
      await Share.share('지금 고잉온 열어줘! 같이 뛰자');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '알리지 못했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── 카운트다운 오버레이 ──
    if (_countdown != null) {
      return Scaffold(
        backgroundColor: GoColors.canvas,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('함께 달리기 시작',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    letterSpacing: 1.4, color: GoColors.dim)),
            const SizedBox(height: 10),
            Text('$_countdown', style: GoTheme.serif(128)),
            const SizedBox(height: 10),
            Text('나 & ${widget.partnerName}',
                style: const TextStyle(fontSize: 13, color: GoColors.mid)),
            const SizedBox(height: 10),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _cdDot(GoColors.lime, GoColors.limeDark),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('+',
                    style: TextStyle(fontSize: 11, color: GoColors.dim)),
              ),
              _cdDot(GoColors.coral, GoColors.coralDark),
            ]),
          ]),
        ),
      );
    }

    final step = _steps[_step];
    // 로비를 어떤 경로로 벗어나든 세션이 정리되어야 함. iOS는 화면 왼쪽에서
    // 스와이프하면 뒤로 가는데, 그 경로는 '← 홈으로' 버튼을 거치지 않아서
    // 세션이 waiting으로 남고 ActiveRunGuard가 true로 굳어버렸음 —
    // 그러면 홈이 GO? 요청 시트를 영영 건너뛰게 됨
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _leaveLobby();
      },
      child: _lobbyBody(step),
    );
  }

  /// 로비 이탈 시 정리 — 버튼·스와이프·시스템 뒤로가기 모두 여기를 지남
  void _leaveLobby() {
    if (!widget.demo) _runs.cancelSession(widget.sessionId);
    ActiveRunGuard.active = false;
  }

  Widget _lobbyBody(_Step step) {
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── 헤더 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('← 홈으로',
                        style:
                            TextStyle(fontSize: 11, color: GoColors.dim)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                      _meReady && _partnerReady
                          ? '출발 준비 완료'
                          : '함께 달릴 준비',
                      style: GoTheme.serif(26)),
                ]),
          ),
          // ── 러너 행 ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 28),
            child: Row(children: [
              Expanded(
                  child: _runner('나', _meReady,
                      isLate: _isLate,
                      fill: GoColors.lime, line: GoColors.limeDark)),
              Container(width: 1, height: 48, color: GoColors.line),
              Expanded(
                  child: _runner(widget.partnerName, _partnerReady,
                      isLate: _partnerLate,
                      fill: GoColors.coral, line: GoColors.coralDark,
                      // 상대가 앱을 안 켠 건지, 수락하고 준비 중인 건지
                      // 구분해서 보여줌 — 예전엔 둘 다 똑같이 보였음
                      waitingText:
                          _partnerJoined ? '함께 준비 중' : '기다리는 중')),
            ]),
          ),
          // ── 스텝 도트 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length * 2 - 1, (i) {
                if (i.isOdd) {
                  final done = (i ~/ 2) < _step;
                  return Container(
                      width: 32, height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: done
                          ? GoColors.limeDark
                          : GoColors.ink.withOpacity(.1));
                }
                final idx = i ~/ 2;
                final done = idx < _step;
                final active = idx == _step;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: active ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: done
                        ? GoColors.limeDark
                        : active
                            ? GoColors.ink
                            : GoColors.ink.withOpacity(.12),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          // ── 상태 카드 (탭해서 단계 진행) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: GestureDetector(
              onTap: _advanceStep,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _meReady
                      ? GoColors.lime.withOpacity(.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _meReady
                          ? GoColors.lime.withOpacity(.5)
                          : GoColors.line,
                      width: 1.5),
                ),
                child: Column(children: [
                  Row(children: [
                    Icon(_isLate ? Icons.schedule : step.icon,
                        size: 32,
                        color:
                            _isLate ? GoColors.amber : GoColors.ink),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _isLate
                                    ? '늦는 중'
                                    : '단계 ${_step + 1} / ${_steps.length}',
                                style: const TextStyle(fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                    color: GoColors.dim)),
                            const SizedBox(height: 3),
                            Text(_isLate ? '조금 늦어요' : step.text,
                                style: TextStyle(fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _meReady
                                        ? GoColors.limeDark
                                        : GoColors.ink)),
                          ]),
                    ),
                  ]),
                  if (!_isLate) ...[
                    const SizedBox(height: 10),
                    Container(height: 1, color: GoColors.line),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: GoColors.ink.withOpacity(.06),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(_meReady ? '취소' : '다음 →',
                              style: const TextStyle(fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: GoColors.ink)),
                        ),
                      ],
                    ),
                  ],
                ]),
              ),
            ),
          ),
          // ── 늦음 링크 ──
          if (!_meReady) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () async {
                  final next = !_isLate;
                  setState(() => _isLate = next);
                  if (widget.demo) return;
                  try {
                    await _runs.setLate(widget.sessionId, _uid, next);
                  } catch (e, stack) {
                    FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
                    if (!mounted) return;
                    setState(() => _isLate = !next);
                    GoToast.error(context, '상태를 전달하지 못했어요. 다시 시도해 주세요.');
                  }
                },
                child: Text(_isLate ? '늦음 취소' : '조금 늦을 것 같아요',
                    style: TextStyle(fontSize: 11,
                        fontWeight:
                            _isLate ? FontWeight.w600 : FontWeight.normal,
                        color: _isLate ? GoColors.amber : GoColors.dim)),
              ),
            ),
          ],
          const Spacer(),
          // ── 액션 버튼 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
            child: Column(children: [
              SizedBox(width: double.infinity, child: _actionButton()),
              if (_showTimeoutHelp && !_partnerReady) ...[
                const SizedBox(height: 12),
                _timeoutHelp(),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _actionButton() {
    if (!_meReady) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: GoColors.ink,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: _jumpToReady,
        child: Text('준비완료 →', style: GoTheme.serif(20, color: GoColors.paper)),
      );
    }
    // 나는 준비됨 → 파트너 대기
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: GoColors.ink.withOpacity(.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GoColors.line, width: 1.5),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: GoColors.mid)),
        const SizedBox(width: 10),
        Text(
            _partnerJoined
                ? '${widget.partnerName} 준비 중'
                : '${widget.partnerName} 기다리는 중',
            style: GoTheme.serif(20, color: GoColors.mid)),
      ]),
    );
  }

  /// 3분 무응답 시 나오는 안내 — 무한 대기 대신 탈출구를 줌
  Widget _timeoutHelp() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GoColors.amber.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GoColors.amber.withOpacity(.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('아직 응답이 없어요. 앱을 안 보고 있을 수 있어요.',
            style: TextStyle(
                fontSize: 12, color: GoColors.ink.withOpacity(.7), height: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: GoColors.line, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _notifyPartner,
              child: const Text('카카오톡으로 알리기',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: GoColors.ink)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: GoColors.line, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('다음에 다시',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: GoColors.mid)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _runner(String name, bool ready,
      {bool isLate = false,
      required Color fill,
      required Color line,
      String waitingText = '준비 중'}) {
    // (이모지 대신 텍스트만 — 폰트 폴백 이슈 회피)
    return Column(children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill.withOpacity(.1),
          border:
              Border.all(color: ready ? line : line.withOpacity(.3), width: 2),
          boxShadow: ready
              ? [BoxShadow(color: fill.withOpacity(.2), spreadRadius: 4)]
              : null,
        ),
        child: Center(child: Text(name[0], style: GoTheme.serif(24))),
      ),
      const SizedBox(height: 7),
      Text(name,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: line)),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: ready
              ? fill.withOpacity(.13)
              : isLate
                  ? GoColors.amber.withOpacity(.07)
                  : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isLate
                  ? GoColors.amber.withOpacity(.3)
                  : GoColors.line),
        ),
        child: Text(
            ready
                ? '준비완료!'
                : isLate
                    ? '조금 늦어요'
                    : waitingText,
            style: TextStyle(fontSize: 10,
                fontWeight: ready ? FontWeight.w600 : FontWeight.normal,
                color: ready
                    ? line
                    : isLate
                        ? GoColors.amber
                        : GoColors.mid)),
      ),
    ]);
  }

  Widget _cdDot(Color fill, Color line) => Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill.withOpacity(.2),
          border: Border.all(color: line, width: 2.5),
        ),
      );
}
