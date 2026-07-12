import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
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
  int? _countdown;

  bool get _meReady => _step == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    if (widget.demo) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        setState(() => _partnerReady = true);
        _maybeCountdown();
      });
      return;
    }
    _sub = _runs.sessionStream(widget.sessionId).listen((doc) {
      final data = doc.data();
      if (data == null) return;
      if (data['status'] == 'cancelled') {
        if (mounted) Navigator.pop(context);
        return;
      }
      final ready = Map<String, dynamic>.from(data['ready'] ?? {});
      final partnerReady =
          ready.entries.any((e) => e.key != _uid && e.value == true);
      setState(() => _partnerReady = partnerReady);
      _maybeCountdown();
      if (data['status'] == 'running' && _countdown == null) _goRun();
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

  void _becomeReady() {
    if (widget.demo) {
      _maybeCountdown();
    } else {
      _runs.setReady(widget.sessionId, _uid);
      _maybeCountdown();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 3);
    Timer.periodic(const Duration(seconds: 1), (t) {
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
    super.dispose();
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
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── 헤더 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (!widget.demo) _runs.cancelSession(widget.sessionId);
                      Navigator.pop(context);
                    },
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
                      fill: GoColors.coral, line: GoColors.coralDark,
                      waitingText: '📍 도착했어요')),
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
                onPressed: () => setState(() => _isLate = !_isLate),
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
            child: SizedBox(
              width: double.infinity,
              child: _actionButton(),
            ),
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
        Text('${widget.partnerName} 기다리는 중',
            style: GoTheme.serif(20, color: GoColors.mid)),
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
