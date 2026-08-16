// 공명 이벤트 레이어 확인 도구.
//
// 왜 따로 두는가: 데모 러닝의 이벤트 흐름을 확인하려면 설정 → 혼자 미리
// 체험하기 → 로비 → 준비 → 러닝까지 손으로 눌러 들어가야 하고, 그때부터
// 첫 공명까지 또 20초를 기다려야 한다. 앞으로 붙을 사운드는 이 타임라인을
// 수십 번 다시 듣게 될 텐데, 매번 그 길을 걸을 수는 없다.
//
// 여기서 도는 것은 **러닝 화면과 완전히 같은 물건**이다 — 같은
// [ResonanceEngine], 같은 [DemoResonanceDriver], 같은 [ResonanceEventLog].
// 화면에 붙은 것은 눈으로 볼 계기판뿐이다.
//
//   flutter run -t lib/main_resonance_probe.dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'services/demo_resonance.dart';
import 'services/resonance.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Probe(),
    ));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static const _ink = Color(0xFF1A1A16);
  static const _mid = Color(0xFF78746E);
  static const _paper = Color(0xFFF0EAE0);
  static const _lime = Color(0xFF6A9810);
  static const _gold = Color(0xFFD4A84B);

  final _engine = ResonanceEngine();
  late final DemoResonanceDriver _driver;
  ResonanceEventLog? _log;
  StreamSubscription<ResonanceEvent>? _sub;
  Timer? _repaint;
  final _lines = <String>[];
  DateTime? _origin;

  @override
  void initState() {
    super.initState();
    _log = ResonanceEventLog.attach(_engine, tag: '[probe]');
    _sub = _engine.events.listen((e) {
      final origin = _origin ??= e.at;
      final t = e.at.difference(origin).inMilliseconds / 1000;
      setState(() {
        _lines.insert(0, '+${t.toStringAsFixed(1)}s  ${e.describe()}');
        if (_lines.length > 40) _lines.removeLast();
      });
    });
    _driver = DemoResonanceDriver(_engine)..start();
    // 연속값은 이벤트가 없는 동안에도 움직이므로 따로 다시 그린다
    _repaint = Timer.periodic(
        const Duration(milliseconds: 100), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _repaint?.cancel();
    _driver.stop();
    _sub?.cancel();
    _log?.cancel();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final smoothed = _engine.smoothedCloseness;
    return Scaffold(
      backgroundColor: _paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('공명 이벤트 레이어 — 데모 타임라인',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 12),
            Row(children: [
              _stat('상태', _engine.state.name,
                  _engine.state == SyncState.resonant ? _gold : _ink),
              _stat('스무딩', smoothed.toStringAsFixed(3), _lime),
              _stat('원본', _engine.rawCloseness.toStringAsFixed(3), _mid),
              _stat('유지', '${_engine.resonanceHeldFor.inSeconds}s', _mid),
            ]),
            const SizedBox(height: 10),
            // 문턱 두 개를 같이 그려 히스테리시스 구간이 눈에 보이게 함
            _meter(smoothed),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.builder(
                itemCount: _lines.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(_lines[i],
                      style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: _ink)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 9, color: _mid)),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _meter(double v) => SizedBox(
        height: 26,
        child: LayoutBuilder(
          builder: (_, c) => Stack(children: [
            Container(
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _ink.withValues(alpha: .09)),
              ),
            ),
            Container(
              width: c.maxWidth * v,
              height: 26,
              decoration: BoxDecoration(
                color: _lime.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            _threshold(c.maxWidth, ResonanceThresholds.resonantExit, _mid),
            _threshold(c.maxWidth, ResonanceThresholds.resonantEnter, _gold),
          ]),
        ),
      );

  Widget _threshold(double width, double at, Color color) => Positioned(
        left: width * at,
        child: Container(width: 2, height: 26, color: color),
      );
}
