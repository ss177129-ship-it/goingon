import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/go_card.dart';
import '../widgets/go_button.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import '../widgets/pressable.dart';
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
    final roles = GoRoles.of(context);
    // ── 카운트다운 오버레이 ──
    if (_countdown != null) {
      return Scaffold(
        backgroundColor: roles.canvas,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('함께 달리기 시작', style: GoText.label),
            const SizedBox(height: 10),
            Text('$_countdown', style: GoTheme.serif(128)),
            const SizedBox(height: 10),
            Text('나 & ${widget.partnerName}',
                style: TextStyle(fontSize: 13, color: roles.textSecondary)),
            const SizedBox(height: 10),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _cdDot(roles.self),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('+',
                    style: TextStyle(fontSize: 11, color: roles.textSecondary)),
              ),
              _cdDot(roles.partner),
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
    final roles = GoRoles.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── 헤더 ──
          // 뒤로가기는 11px 글자뿐이라 손가락으로 겨냥할 수 없었고 눌러도
          // 아무 반응이 없었다. 44pt 표적 + 눌림 반응으로 교체.
          // 왼쪽 12는 버튼 자체 좌우 여백(16)을 빼고 제목(28)에 맞춘 값
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 28, 0),
            child: Row(children: [
              GoButton('홈으로',
                  kind: GoButtonKind.text,
                  size: GoButtonSize.md,
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.pop(context)),
              const Spacer(),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      _meReady && _partnerReady
                          ? '출발 준비 완료'
                          : '함께 달릴 준비',
                      style: GoText.title),
                ]),
          ),
          // ── 러너 행 ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: GoSpace.screen),
            child: GoCard(
                child: Row(children: [
              Expanded(
                  child: _runner('나', _meReady,
                      isLate: _isLate,
                      color: roles.self)),
              Container(width: GoStroke.rule, height: 64, color: roles.lineStrong),
              Expanded(
                  child: _runner(widget.partnerName, _partnerReady,
                      isLate: _partnerLate,
                      color: roles.partner,
                      // 상대가 앱을 안 켠 건지, 수락하고 준비 중인 건지
                      // 구분해서 보여줌 — 예전엔 둘 다 똑같이 보였음
                      waitingText:
                          _partnerJoined ? '함께 준비 중' : '기다리는 중')),
            ])),
          ),
          // ── 스텝 도트 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GoSpace.screen),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length * 2 - 1, (i) {
                if (i.isOdd) {
                  final done = (i ~/ 2) < _step;
                  return Container(
                      width: 32, height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: done ? roles.statusOnline.fg : roles.line);
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
                        ? roles.statusOnline.fg
                        : active
                            ? roles.textPrimary
                            : roles.textSecondary,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          // ── 상태 카드 (탭해서 단계 진행) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GoSpace.screen),
            child: Pressable(
              onTap: _advanceStep,
              child: Container(
                padding: const EdgeInsets.all(GoSpace.hero),
                decoration: BoxDecoration(
                  color: roles.surface,
                  borderRadius: BorderRadius.circular(GoRadius.md),
                  border: Border.all(
                      color: _meReady ? roles.statusOnline.fg : roles.line,
                      width: _meReady ? GoStroke.accent : GoStroke.card),
                  boxShadow: GoShadow.card,
                ),
                child: Column(children: [
                  Row(children: [
                    Icon(_isLate ? Icons.schedule : step.icon,
                        size: 32,
                        color:
                            _isLate ? roles.attention : roles.textPrimary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _isLate
                                    ? '늦는 중'
                                    : '단계 ${_step + 1} / ${_steps.length}',
                                style: GoText.label),
                            const SizedBox(height: 3),
                            Text(_isLate ? '조금 늦어요' : step.text,
                                style: TextStyle(fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _meReady
                                        ? roles.statusOnline.fg
                                        : roles.textPrimary)),
                          ]),
                    ),
                  ]),
                  if (!_isLate) ...[
                    const SizedBox(height: 10),
                    Container(height: 1, color: roles.lineStrong),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 화살표만 두면 "이게 눌리는 카드"라는 걸 아무도
                        // 모른다 — 아이콘은 이미 아는 사람에게만 말을 건다.
                        // 무엇이 일어나는지 글로 한 번 적어준다(2026-09-07)
                        Text(_meReady ? '준비 취소' : '탭해서 다음 단계',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: roles.textSecondary)),
                        const SizedBox(width: GoSpace.s),
                        // 칩 대신 화살표만 — 카드 자체가 눌린다(2026-09-07)
                        Icon(_meReady ? Icons.close : Icons.arrow_forward,
                            size: 20, color: roles.textPrimary),
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
              child: GoButton(_isLate ? '늦음 취소' : '조금 늦을 것 같아요',
                kind: GoButtonKind.text,
                size: GoButtonSize.md,
                onTap: () async {
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
              ),
            ),
          ],
          const Spacer(),
          // 러닝 화면에서 옮겨온 안내 — 달리는 중에는 안내문이 읽히지 않는다.
          // 손이 비어 있고 화면을 보고 있는 지금이 이 문장의 자리다
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GoSpace.screen),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_outlined,
                      size: 14, color: roles.textSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('달리는 중엔 화면을 탭·스와이프·길게 눌러 신호를 보낼 수 있어요',
                        style: TextStyle(fontSize: 11, color: roles.textSecondary)),
                  ),
                ]),
          ),
          // ── 액션 버튼 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
            child: Column(children: [
              SizedBox(width: double.infinity, child: _actionButton()),
              if (_showTimeoutHelp && !_partnerReady) ...[
                const SizedBox(height: GoSpace.gutter),
                _timeoutHelp(),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _actionButton() {
    final roles = GoRoles.of(context);
    if (!_meReady) {
      return GoButton('준비완료',
          icon: Icons.arrow_forward, iconTrailing: true, onTap: _jumpToReady);
    }
    // 나는 준비됨 → 파트너 대기
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: roles.textSecondary)),
        const SizedBox(width: 10),
        Text(
            _partnerJoined
                ? '${widget.partnerName} 준비 중'
                : '${widget.partnerName} 기다리는 중',
            style: GoText.heading.copyWith(color: roles.textSecondary)),
      ]),
    );
  }

  /// 3분 무응답 시 나오는 안내 — 무한 대기 대신 탈출구를 줌
  Widget _timeoutHelp() {
    final roles = GoRoles.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(GoSpace.card),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        border: Border.all(color: roles.attention, width: GoStroke.accent),
        boxShadow: GoShadow.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('아직 응답이 없어요. 앱을 안 보고 있을 수 있어요.',
            style: TextStyle(
                fontSize: 12, color: roles.textPrimary.withValues(alpha: .7), height: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: GoButton('카카오톡으로 알리기',
                kind: GoButtonKind.secondary,
                size: GoButtonSize.md,
                onTap: _notifyPartner),
          ),
          const SizedBox(width: GoSpace.s),
          Expanded(
            child: GoButton('다음에 다시',
                kind: GoButtonKind.text,
                size: GoButtonSize.md,
                onTap: () => Navigator.pop(context)),
          ),
        ]),
      ]),
    );
  }

  Widget _runner(String name, bool ready,
      {bool isLate = false,
      required Color color,
      String waitingText = '준비 중'}) {
    final roles = GoRoles.of(context);
    // 밝은 바탕 위의 나/상대는 한 색으로 — 면은 그 색 25%, 선은 그 색
    final line = color;
    // (이모지 대신 텍스트만 — 폰트 폴백 이슈 회피)
    return Column(children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .25),
          border: Border.all(color: ready ? line : roles.line, width: GoStroke.accent),
        ),
        child: Center(
            child: Text(name[0],
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: roles.textPrimary))),
      ),
      const SizedBox(height: 7),
      Text(name,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: line)),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: roles.surface,
          borderRadius: BorderRadius.circular(GoRadius.sm),
          border: Border.all(
              color: isLate
                  ? roles.attention
                  : ready
                      ? line
                      : roles.line,
              width: (ready || isLate) ? GoStroke.accent : GoStroke.rule),
          boxShadow: GoShadow.card,
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
                        ? roles.attention
                        : roles.textSecondary)),
      ),
    ]);
  }

  /// 카운트다운의 나/상대 점 — 밝은 바탕이라 한 색으로(면 25%, 선 100%)
  Widget _cdDot(Color color) => Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .25),
          border: Border.all(color: color, width: GoStroke.accent),
        ),
      );
}
