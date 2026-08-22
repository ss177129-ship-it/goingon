// 케이던스 실측 도구 — M0-a. gps_probe와 같은 이유로 존재한다:
// 실제 앱으로는 이 측정을 못 한다.
//
// 검증 방법 (러닝화 신고 나가서):
//   1. 시작을 누르고 폰을 평소 위치(주머니/암밴드/손)에 둔다
//   2. 30초 구간마다 입으로 걸음을 센다 (한 발 기준 ×2 = 양발 spm)
//   3. 화면의 spm과 비교 — **오차 ±3spm 이내면 M0-a 통과**
//   4. 걷기↔달리기 전환을 3회 반복 — gait 전환이 10초 안에 따라오는지
//
// 모든 스텝·샘플은 Documents/cadence_probe.csv 에 남고, 맥에서 회수:
//   xcrun devicectl device copy from --device <udid> \
//     --domain-type appDataContainer --domain-identifier com.chanwoong.goingon \
//     --source Documents/cadence_probe.csv --destination ./cadence_probe.csv
//
// 실행: flutter run -t lib/main_cadence_probe.dart
// 의존성: pubspec.yaml에 sensors_plus 추가 필요 (README 참조)
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/cadence/cadence_engine.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CadenceProbe(),
    ));

class CadenceProbe extends StatefulWidget {
  const CadenceProbe({super.key});

  @override
  State<CadenceProbe> createState() => _CadenceProbeState();
}

class _CadenceProbeState extends State<CadenceProbe> {
  final _engine = CadenceEngine();
  CadenceSample? _last;
  int _stepCount = 0;
  bool _running = false;
  IOSink? _csv;
  StreamSubscription? _sampleSub;
  StreamSubscription? _stepSub;

  // 수동 대조용 랩: 화면을 탭하면 랩 마크가 CSV에 남는다.
  // 입으로 센 30초 구간의 경계를 데이터에 새겨두기 위한 것.
  int _lapCount = 0;

  Future<void> _start() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/cadence_probe.csv');
    _csv = f.openWrite(mode: FileMode.append);
    _csv!.writeln('# session ${DateTime.now().toIso8601String()}');
    _csv!.writeln('type,t,spm,stability,gait');

    _stepSub = _engine.steps.listen((t) {
      _stepCount++;
      _csv?.writeln('step,${t.toIso8601String()},,,');
    });
    _sampleSub = _engine.samples.listen((s) {
      setState(() => _last = s);
      _csv?.writeln(
          'sample,${s.at.toIso8601String()},${s.spm.toStringAsFixed(1)},'
          '${s.stability.toStringAsFixed(2)},${s.gait.name}');
    });

    _engine.start();
    await WakelockPlus.enable();
    setState(() {
      _running = true;
      _stepCount = 0;
      _lapCount = 0;
    });
  }

  Future<void> _stop() async {
    await _engine.stop();
    await _sampleSub?.cancel();
    await _stepSub?.cancel();
    await _csv?.flush();
    await _csv?.close();
    await WakelockPlus.disable();
    setState(() => _running = false);
  }

  void _lap() {
    _lapCount++;
    _csv?.writeln('lap,${DateTime.now().toIso8601String()},,,# lap $_lapCount');
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _last;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0D),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _running ? _lap : null,
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Text('cadence probe · M0-a',
                  style: TextStyle(color: Color(0xFF5DCAA5), fontSize: 13)),
              const Spacer(),
              Text(
                s == null ? '—' : s.spm.toStringAsFixed(0),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 120,
                    fontWeight: FontWeight.w700),
              ),
              const Text('spm', style: TextStyle(color: Color(0xFF7D8A84))),
              const SizedBox(height: 16),
              Text(
                s == null
                    ? ''
                    : '${s.gait.name}  ·  안정도 ${(s.stability * 100).toStringAsFixed(0)}%'
                        '  ·  스텝 $_stepCount  ·  랩 $_lapCount',
                style: const TextStyle(color: Color(0xFF9DB3A9), fontSize: 14),
              ),
              const Spacer(),
              const Text('화면 탭 = 랩 마크 (수동 카운트 구간 경계)',
                  style: TextStyle(color: Color(0xFF5A6B63), fontSize: 12)),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: _running
                            ? const Color(0xFF993C1D)
                            : const Color(0xFF1D9E75)),
                    onPressed: _running ? _stop : _start,
                    child: Text(_running ? '측정 종료' : '측정 시작'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
