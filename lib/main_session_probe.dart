// 세션 상태 머신 확인 도구 — P3.
//
// **테스트로는 못 잡는 것 하나를 잡으려고 존재한다: 채보 JSON이 실제 앱의
// 에셋 번들에서 로드되는가.** 단위 테스트는 문자열을 직접 파싱하므로
// pubspec.yaml에 `assets/episodes/`를 빠뜨려도 초록불이 뜬다. 그 실수는
// 러닝을 시작한 사람의 화면에서 발견된다.
//
// 8분을 실시간으로 기다릴 수 없으므로 시간을 [kSpeed]배로 돌린다.
// 상태 머신이 타이머를 갖지 않고 시계를 주입받는 덕분에 가능한 일이다.
//
// **주의: 번들 ID가 같아 홈 화면의 'Goingon'이 이 화면으로 덮인다.**
// 확인이 끝나면 실제 앱을 다시 설치할 것:
//   flutter run -t lib/main.dart -d <기기>
//
// 실행: flutter run -t lib/main_session_probe.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'services/cadence/cadence_engine.dart' show GaitState;
import 'services/session/chart.dart';
import 'services/session/session_controller.dart';

/// 8분(480초)을 40초에 본다
const kSpeed = 12;

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SessionProbe(),
    ));

class SessionProbe extends StatefulWidget {
  const SessionProbe({super.key});

  @override
  State<SessionProbe> createState() => _SessionProbeState();
}

class _SessionProbeState extends State<SessionProbe> {
  final _log = <String>[];
  Chart? _chart;
  SessionController? _c;
  Timer? _timer;
  DateTime _virtual = DateTime.utc(2026, 8, 23, 6);
  String? _error;

  /// 잔향에서 무엇을 할지 — 화면의 버튼은 **프로브 전용**이다.
  /// 실제 앱에서는 발과 꼭지가 이 자리를 대신한다
  GaitState _gait = GaitState.running;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 이 한 줄이 이 프로브의 존재 이유다
      final text =
          await rootBundle.loadString('assets/episodes/episode_train.chart.json');
      final chart = Chart.parse(text);
      setState(() {
        _chart = chart;
        _log.add('채보 로드: ${chart.title} · ${chart.duration.inSeconds}s · '
            'BPM ${chart.baseBpm.toStringAsFixed(0)} · 구간 ${chart.sections.length}개 · '
            '화자 ${chart.narrationCount}문장');
      });
      // 시뮬레이터는 합성 탭이 막혀 있어(macOS 26) 사람 손 없이 확인하려면
      // 스스로 굴러야 한다. 실기에서는 버튼으로도 시작할 수 있다
      if (const bool.fromEnvironment('autostart', defaultValue: true)) _start();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _start() {
    final chart = _chart;
    if (chart == null) return;
    final c = SessionController(chart: chart, clock: () => _virtual);
    c.events.listen((e) {
      final line = '+${e.elapsed.inSeconds.toString().padLeft(3)}s  ${e.describe()}';
      debugPrint('[session] $line');
      setState(() => _log.add(line));
    });
    c.start();
    _timer = Timer.periodic(const Duration(milliseconds: 1000 ~/ kSpeed), (_) {
      _virtual = _virtual.add(const Duration(seconds: 1));
      c.onGait(_gait);
      if (c.phase == SessionPhase.result || c.phase == SessionPhase.cooldown) {
        _timer?.cancel();
      }
      setState(() {});
    });
    setState(() => _c = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0D),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('session probe · P3  (시간 ×$kSpeed)',
                  style: TextStyle(color: Color(0xFF5DCAA5), fontSize: 13)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('채보 로드 실패 — $_error',
                    style: const TextStyle(color: Color(0xFFFF6B6B))),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                c == null ? '—' : '${c.phase.name}   ${c.elapsed.inSeconds}s',
                style: const TextStyle(
                    color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final line in _log)
                    Text(line,
                        style: const TextStyle(
                            color: Color(0xFF9DB3A9),
                            fontSize: 12,
                            fontFamily: 'Menlo')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                for (final g in GaitState.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: _gait == g
                                ? const Color(0xFF1D9E75)
                                : const Color(0xFF243029)),
                        onPressed: () => setState(() => _gait = g),
                        child: Text(g.name,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _chart == null || _c != null ? null : _start,
                    child: const Text('시작'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: c?.onTip,
                    child: const Text('꼭지 1회'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: c?.onInterruptionBegan,
                    child: const Text('전화'),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
