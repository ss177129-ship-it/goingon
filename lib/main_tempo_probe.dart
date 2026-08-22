// 템포 동기 실측 도구 — M0-b. "곡이 나를 따라온다"가 기술적으로 성립하는지
// 귀로 확인하기 위한 것.
//
// 두 가지를 검증한다:
//   1. 메트로놈 모드 — sig_tap을 BPM 간격으로 스케줄. 케이던스를 따라가게
//      켜고 달리면 "비트가 내 발을 따라온다"는 감각이 실제로 성립하는지,
//      그리고 스케줄 지터(계획 대비 실제 발화 시각)가 귀에 걸리는지.
//      **지터 p95 30ms 이내면 통과** — 넘으면 오디오 스레드 스케줄링으로 이관.
//   2. 스템 속도 모드 — pad_resonance 루프에 setRelativePlaySpeed를 걸어
//      BPM 비율(현재/기준 160)로 재생. SoLoud의 속도 변경은 **피치도 함께
//      변한다** — 이것이 음악적으로 허용 가능한지(바이닐 바리스피드 감성),
//      아니면 스템을 BPM대역별로 여러 벌 만들어야 하는지를 귀로 판정한다.
//      이 판정이 스템 제작 방식(기술설계서 §8-2)을 결정한다.
//
// SoLoud를 직접 import한다 — 프로브는 진단 도구라 SoundEngine 인터페이스
// 뒤에 숨지 않는다(gps_probe가 RunAccumulator를 직접 쓰는 것과 같은 이유).
// 프로덕션에서는 SoundEngine에 setLoopSpeed를 추가해 노출할 것.
//
// 지터 로그: Documents/tempo_probe.csv (planned, actual, jitterMs)
// 실행: flutter run -t lib/main_tempo_probe.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/cadence/cadence_engine.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TempoProbe(),
    ));

class TempoProbe extends StatefulWidget {
  const TempoProbe({super.key});

  @override
  State<TempoProbe> createState() => _TempoProbeState();
}

class _TempoProbeState extends State<TempoProbe> {
  static const double kBaseBpm = 160; // 스템의 기준 BPM (제작 시 이 값으로 녹음)

  final _engine = CadenceEngine();
  AudioSource? _tap;
  AudioSource? _pad;
  SoundHandle? _padHandle;

  double _bpm = 160;
  bool _followCadence = false;
  bool _metronomeOn = false;
  bool _padOn = false;
  bool _ready = false;

  Timer? _tick;
  DateTime? _nextPlanned;
  final _jitters = <double>[];
  IOSink? _csv;
  StreamSubscription? _cadSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await SoLoud.instance.init();
    _tap = await SoLoud.instance.loadAsset('assets/audio/sig_tap.wav');
    _pad = await SoLoud.instance.loadAsset('assets/audio/pad_resonance.wav');
    final dir = await getApplicationDocumentsDirectory();
    _csv = File('${dir.path}/tempo_probe.csv').openWrite(mode: FileMode.append);
    _csv!.writeln('# session ${DateTime.now().toIso8601String()}');
    _csv!.writeln('planned,actual,jitterMs,bpm');
    _cadSub = _engine.samples.listen((s) {
      if (_followCadence && s.spm > 100) {
        setState(() => _bpm = s.spm.clamp(120.0, 200.0));
        _applyPadSpeed();
      }
    });
    _engine.start();
    await WakelockPlus.enable();
    setState(() => _ready = true);
  }

  // 메트로놈: Timer 하나로 다음 박만 스케줄하는 자기 재귀 방식.
  // 주기 Timer.periodic은 BPM이 바뀔 때 위상이 튀므로 쓰지 않는다.
  void _scheduleNextBeat() {
    if (!_metronomeOn) return;
    final interval = Duration(microseconds: (60e6 / _bpm).round());
    _nextPlanned = (_nextPlanned ?? DateTime.now()).add(interval);
    final delay = _nextPlanned!.difference(DateTime.now());
    _tick = Timer(delay.isNegative ? Duration.zero : delay, () {
      final actual = DateTime.now();
      final jitter =
          actual.difference(_nextPlanned!).inMicroseconds.abs() / 1000.0;
      _jitters.add(jitter);
      if (_jitters.length > 500) _jitters.removeAt(0);
      _csv?.writeln('${_nextPlanned!.toIso8601String()},'
          '${actual.toIso8601String()},${jitter.toStringAsFixed(1)},'
          '${_bpm.toStringAsFixed(0)}');
      if (_tap != null) SoLoud.instance.play(_tap!, volume: 0.6);
      _scheduleNextBeat();
    });
  }

  void _toggleMetronome() {
    setState(() => _metronomeOn = !_metronomeOn);
    _tick?.cancel();
    _nextPlanned = null;
    _jitters.clear();
    if (_metronomeOn) _scheduleNextBeat();
  }

  Future<void> _togglePad() async {
    if (_pad == null) return;
    if (_padOn) {
      final h = _padHandle;
      if (h != null) await SoLoud.instance.stop(h);
      _padHandle = null;
    } else {
      // play()는 4.1.7부터 동기다 — await를 붙이면 분석기가 에러를 낸다
      _padHandle = SoLoud.instance.play(_pad!, volume: 0.8, looping: true);
      _applyPadSpeed();
    }
    setState(() => _padOn = !_padOn);
  }

  void _applyPadSpeed() {
    final h = _padHandle;
    if (h == null) return;
    // 속도 = 피치가 같이 변한다. 이것이 허용 가능한지가 이 프로브의 질문.
    SoLoud.instance.setRelativePlaySpeed(h, _bpm / kBaseBpm);
  }

  double get _jitterP95 {
    if (_jitters.length < 20) return 0;
    final sorted = [..._jitters]..sort();
    return sorted[(sorted.length * 0.95).floor()];
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cadSub?.cancel();
    _engine.dispose();
    _csv?.close();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('tempo probe · M0-b',
                  style: TextStyle(color: Color(0xFF5DCAA5), fontSize: 13)),
              const Spacer(),
              Text(_bpm.toStringAsFixed(0),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 96,
                      fontWeight: FontWeight.w700)),
              const Text('BPM',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF7D8A84))),
              Slider(
                value: _bpm,
                min: 120,
                max: 200,
                activeColor: const Color(0xFF1D9E75),
                onChanged: _followCadence
                    ? null
                    : (v) {
                        setState(() => _bpm = v);
                        _applyPadSpeed();
                      },
              ),
              SwitchListTile(
                title: const Text('케이던스 따라가기',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('걸으면/달리면 BPM이 발을 따라옵니다',
                    style: TextStyle(color: Color(0xFF7D8A84), fontSize: 12)),
                value: _followCadence,
                activeColor: const Color(0xFF5DCAA5),
                onChanged: (v) => setState(() => _followCadence = v),
              ),
              const SizedBox(height: 8),
              Text(
                '지터 p95: ${_jitterP95.toStringAsFixed(1)}ms  (기준: 30ms 이내)',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _jitterP95 <= 30
                        ? const Color(0xFF5DCAA5)
                        : const Color(0xFFF0997B),
                    fontSize: 13),
              ),
              const Spacer(),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: _metronomeOn
                            ? const Color(0xFF993C1D)
                            : const Color(0xFF1D9E75)),
                    onPressed: _ready ? _toggleMetronome : null,
                    child: Text(_metronomeOn ? '메트로놈 정지' : '메트로놈'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: _padOn
                            ? const Color(0xFF993C1D)
                            : const Color(0xFF13201B)),
                    onPressed: _ready ? _togglePad : null,
                    child: Text(_padOn ? '패드 정지' : '패드 속도 테스트'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
