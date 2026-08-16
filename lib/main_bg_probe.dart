// 임시 진단용 — 감사 #15. 확인 후 지울 것.
//
// 질문: 앱이 백그라운드로 내려간 동안 RunRecovery의 스냅샷 저장이 계속 도는가?
//
// run_screen은 Timer.periodic(1초) 안에서 5초마다 RunRecovery.save를 부른다.
// iOS가 배경에서 Dart 타이머를 멈추면 그 구간 기록이 스냅샷에 남지 않아,
// 그 상태로 앱이 죽으면 배경에서 달린 만큼이 통째로 사라진다.
//
// 여기서는 실제 러닝과 같은 조건을 만든다:
//   - 같은 위치 설정(배경 위치 업데이트 포함)으로 스트림 구독
//   - Timer.periodic(1초) + 5초마다 SharedPreferences 쓰기
// 그리고 타이머 기록과 위치 콜백 기록의 **간격**을 재서 화면에 보여준다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/run_accumulator.dart';

// RunRecovery의 실제 키와 겹치지 않게 별도 이름을 쓴다
const _kTicks = 'bgprobe_timer_ticks';
const _kFixes = 'bgprobe_location_fixes';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Probe(),
    ));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with WidgetsBindingObserver {
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  String _status = '시작 준비 중…';
  List<int> _ticks = [];
  List<int> _fixes = [];
  int _startedAt = 0;
  bool _always = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 돌아오면 저장된 기록을 다시 읽어 화면을 갱신한다
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTicks);
    await prefs.remove(_kFixes);
    _startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 실제 앱과 같은 권한 절차
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _status = '위치 서비스가 꺼져 있습니다');
      return;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.whileInUse) {
      await ph.Permission.locationAlways.request();
      p = await Geolocator.checkPermission();
    }
    _always = p == LocationPermission.always;
    if (p != LocationPermission.always && p != LocationPermission.whileInUse) {
      setState(() => _status = '위치 권한 거부됨 — 측정 불가');
      return;
    }

    // run_screen과 동일한 설정
    _sub = Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: RunFilterConfig.current.locationDistanceFilter.toInt(),
        allowBackgroundLocationUpdates: _always,
        showBackgroundLocationIndicator: _always,
        pauseLocationUpdatesAutomatically: false,
      ),
    ).listen((_) {
      _record(_kFixes);
      _snapshot(); // run_screen과 동일 — 위치 콜백에서도 저장한다
    });

    // run_screen과 동일: 1초 타이머에서도 저장을 시도한다
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _snapshot());

    setState(() => _status = _always
        ? '측정 중 — 위치 "항상 허용" 확보됨'
        : '측정 중 — "앱 사용 중에만" 상태 (배경 추적 불가)');
  }

  /// run_screen의 `_saveSnapshot`과 같은 간격 제어. 타이머와 위치 콜백
  /// 어느 쪽에서 불리든 5초에 한 번만 실제로 남긴다
  DateTime? _lastSnapshotAt;

  void _snapshot() {
    final now = DateTime.now();
    final last = _lastSnapshotAt;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastSnapshotAt = now;
    _record(_kTicks);
  }

  Future<void> _record(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(key) ?? [];
    list.add('${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    await prefs.setStringList(key, list);
  }

  Future<void> _reload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!mounted) return;
    setState(() {
      _ticks = (prefs.getStringList(_kTicks) ?? []).map(int.parse).toList();
      _fixes = (prefs.getStringList(_kFixes) ?? []).map(int.parse).toList();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  /// 연속 기록 사이의 최대 간격(초). 배경에서 멈췄다면 여기가 크게 벌어진다
  int _maxGap(List<int> xs) {
    var m = 0;
    for (var i = 1; i < xs.length; i++) {
      final g = xs[i] - xs[i - 1];
      if (g > m) m = g;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final tickGap = _maxGap(_ticks);
    final fixGap = _maxGap(_fixes);
    final elapsed = _ticks.isEmpty
        ? 0
        : _ticks.last - (_startedAt == 0 ? _ticks.first : _startedAt);

    Widget stat(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF78746E))),
              Text(value,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold, color: color ?? const Color(0xFF1A1A16))),
            ],
          ),
        );

    // 배경에서 타이머가 멈췄는지 판정 — 5초마다 저장하므로 15초를 넘으면 멈춘 것
    final verdict = _ticks.length < 3
        ? '아직 데이터 부족'
        : tickGap > 15
            ? '타이머가 배경에서 멈춤 (최대 $tickGap초 공백)'
            : '타이머가 배경에서도 계속 돎';
    final bad = tickGap > 15;

    return Scaffold(
      backgroundColor: const Color(0xFFF0EAE0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('감사 #15 — 배경 스냅샷 측정',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_status, style: const TextStyle(fontSize: 12, color: Color(0xFF78746E))),
            const SizedBox(height: 20),
            const Text('① 홈 버튼으로 앱을 내리고  ② 2분 기다린 뒤  ③ 다시 열어주세요',
                style: TextStyle(fontSize: 13, height: 1.6)),
            const SizedBox(height: 20),
            const Divider(),
            stat('스냅샷 저장 횟수', '${_ticks.length}회'),
            stat('저장 사이 최대 공백', '$tickGap초',
                color: bad ? const Color(0xFFB03020) : const Color(0xFF5E8A0E)),
            const Divider(),
            stat('위치 콜백 횟수', '${_fixes.length}회'),
            stat('위치 콜백 최대 공백', '$fixGap초'),
            const Divider(),
            stat('측정 시간', '$elapsed초'),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bad ? const Color(0x18B03020) : const Color(0x185E8A0E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(verdict,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: bad ? const Color(0xFFB03020) : const Color(0xFF3F6108))),
            ),
            const Spacer(),
            Center(
              child: TextButton(
                onPressed: _reload,
                child: const Text('새로고침'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
