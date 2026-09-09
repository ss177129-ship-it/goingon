import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/go_card.dart';
import '../widgets/go_avatar.dart';
import '../widgets/go_button.dart';
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

class _LobbyScreenState extends State<LobbyScreen> {
  final _runs = RunService();
  final _uid = AuthService().uid;
  StreamSubscription? _sub;

  /// 문서의 `ready` 맵이 진실이다 — 화면이 자기 상태를 따로 들고 있으면
  /// 상대가 보는 것과 어긋난다(준비 취소가 실제로 그랬다)
  bool _meReady = false;
  bool _isLate = false;
  bool _partnerReady = false;
  bool _partnerLate = false;
  bool _partnerJoined = false;
  bool _showTimeoutHelp = false;
  int? _countdown;
  Timer? _timeoutTimer;
  Timer? _countdownTimer;

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
      final meReady = ready[_uid] == true;
      final late = Map<String, dynamic>.from(data['late'] ?? {});
      final partnerLate =
          late.entries.any((e) => e.key != _uid && e.value == true);
      final joined = Map<String, dynamic>.from(data['joined'] ?? {});
      final partnerJoined =
          joined.entries.any((e) => e.key != _uid && e.value == true);
      setState(() {
        _meReady = meReady;
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

  /// 준비완료 ↔ 준비 취소.
  ///
  /// **취소도 서버에 쓴다.** 전에는 화면 단계만 뒤로 돌렸는데, 상대에게는
  /// 내가 여전히 준비완료로 보여서 상대가 준비하는 순간 아무도 취소하지
  /// 않은 러닝이 시작됐다
  Future<void> _toggleReady() async {
    if (_countdown != null) return;
    final next = !_meReady;
    setState(() {
      _meReady = next;
      if (next) _isLate = false;
    });
    if (widget.demo) {
      _maybeCountdown();
      return;
    }
    try {
      if (next) {
        await _runs.setReady(widget.sessionId, _uid);
      } else {
        await _runs.clearReady(widget.sessionId, _uid);
      }
      _maybeCountdown();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      // 전달에 실패하면 상대가 내 상태를 영영 못 봄 — 조용히 두지 않고
      // 되돌려 다시 시도할 수 있게 함
      if (!mounted) return;
      setState(() => _meReady = !next);
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
                    style: TextStyle(fontSize: 12, color: roles.textSecondary)),
              ),
              _cdDot(roles.partner),
            ]),
          ]),
        ),
      );
    }

    // 로비를 어떤 경로로 벗어나든 세션이 정리되어야 함. iOS는 화면 왼쪽에서
    // 스와이프하면 뒤로 가는데, 그 경로는 '← 홈으로' 버튼을 거치지 않아서
    // 세션이 waiting으로 남고 ActiveRunGuard가 true로 굳어버렸음 —
    // 그러면 홈이 GO? 요청 시트를 영영 건너뛰게 됨
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _leaveLobby();
      },
      child: _lobbyBody(),
    );
  }

  /// 로비 이탈 시 정리 — 버튼·스와이프·시스템 뒤로가기 모두 여기를 지남
  void _leaveLobby() {
    if (!widget.demo) _runs.cancelSession(widget.sessionId);
    ActiveRunGuard.active = false;
  }

  Widget _lobbyBody() {
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
          // ── 상대가 어디까지 왔나 ──
          // 4단계 준비운동을 걷어낸 자리(2026-09-09). 단계는 수락 전에도
          // 밟을 수 있어서 상대가 거절하면 그 노동이 통째로 버려졌고,
          // 준비운동을 앱이 시킬 일도 아니었다. 대신 **먼저 준비한 사람이
          // 볼 것**을 여기에 크게 둔다 — 스피너 한 줄로는 기다리는 동안
          // 아무 일도 안 일어나는 것처럼 느껴진다
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GoSpace.screen),
            child: _partnerState(),
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

  Widget _actionButton() => _meReady
      ? GoButton('준비 취소',
          kind: GoButtonKind.secondary, onTap: _toggleReady)
      : GoButton('준비완료',
          icon: Icons.arrow_forward, iconTrailing: true, onTap: _toggleReady);

  /// 상대가 지금 어디쯤인지 — 기다리는 동안 화면에 남는 것.
  ///
  /// 세 가지를 가른다: 앱을 아직 안 켰다 / 로비에 들어와 준비 중이다 /
  /// 준비를 마쳤다. 예전엔 앞의 둘이 똑같이 보였다
  Widget _partnerState() {
    final roles = GoRoles.of(context);
    final (IconData icon, String title, String? sub, Color tone) = switch ((
      _partnerReady,
      _partnerLate,
      _partnerJoined,
    )) {
      (true, _, _) => (
          Icons.check_circle,
          '${widget.partnerName}님도 준비됐어요',
          _meReady ? null : '이제 나만 준비하면 출발해요',
          roles.success.fg
        ),
      (false, true, _) => (
          Icons.schedule,
          '${widget.partnerName}님이 조금 늦어요',
          '기다렸다 함께 출발해요',
          roles.warning.fg
        ),
      (false, false, true) => (
          Icons.directions_walk,
          '${widget.partnerName}님이 준비하고 있어요',
          null,
          roles.textSecondary
        ),
      (false, false, false) => (
          Icons.hourglass_empty,
          '${widget.partnerName}님을 기다리는 중',
          '아직 앱을 안 보고 있을 수 있어요',
          roles.textSecondary
        ),
    };

    return GoCard(
      padding: const EdgeInsets.all(GoSpace.hero),
      child: Row(children: [
        Icon(icon, size: 30, color: tone),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: tone)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12, color: roles.textSecondary)),
                ],
              ]),
        ),
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
    // 밝은 바탕 위의 나/상대는 한 색으로 — 면은 그 색 25%, 테두리 없음.
    // 로비는 사진을 받지 않으므로 늘 기본 실루엣
    return Column(children: [
      GoAvatar(
        size: 64,
        roleColor: color,
        fill: color.withValues(alpha: .25),
      ),
      const SizedBox(height: 7),
      Text(name,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        // 준비완료 = 초록 면, 늦음 = 코랄 면, 대기 = 흰 면 + 헤어라인.
        // 굵은 색 테두리 대신 면으로 말한다
        decoration: BoxDecoration(
          color: ready
              ? roles.statusOnline.bg
              : isLate
                  ? roles.statusRunning.bg
                  : roles.surface,
          borderRadius: BorderRadius.circular(GoRadius.sm),
          border: (ready || isLate)
              ? null
              : Border.all(color: roles.line, width: GoStroke.rule),
          boxShadow: GoShadow.card,
        ),
        child: Text(
            ready
                ? '준비완료!'
                : isLate
                    ? '조금 늦어요'
                    : waitingText,
            style: TextStyle(fontSize: 12,
                fontWeight: ready ? FontWeight.w600 : FontWeight.normal,
                color: ready
                    ? roles.statusOnline.fg
                    : isLate
                        ? roles.statusRunning.fg
                        : roles.textSecondary)),
      ),
    ]);
  }

  /// 카운트다운의 나/상대 점 — 역할색 면 하나
  Widget _cdDot(Color color) => Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      );
}
