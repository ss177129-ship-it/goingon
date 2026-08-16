// GPS 실측 도구 — 감사 리포트의 야외 검증 항목을 혼자서 수행하기 위한 것.
//
// 실제 앱으로는 이 측정을 못 한다. 러닝을 시작하려면 상대가 수락해야 하고
// 데모 모드는 GPS를 쓰지 않기 때문이다. 그래서 러닝 화면과 **같은 위치 설정,
// 같은 RunAccumulator**를 쓰되 세션 없이 도는 도구를 따로 둔다.
//
// 핵심: 같은 fix 스트림을 **current(감사 수정 후)와 legacy(수정 전)** 두
// 누적기에 동시에 태운다. 합성 픽스처로만 검증했던 수정이 실제 야외에서도
// 개선인지, 아니면 어딘가 손해를 보는지 그 자리에서 드러난다.
//
// 모든 fix는 Documents/gps_probe.csv 에 남고, 맥에서 이렇게 회수한다:
//   xcrun devicectl device copy from --device <udid> \
//     --domain-type appDataContainer --domain-identifier com.chanwoong.goingon \
//     --source Documents/gps_probe.csv --destination ./gps_probe.csv
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/run_accumulator.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GpsProbe(),
    ));

class GpsProbe extends StatefulWidget {
  const GpsProbe({super.key});
  @override
  State<GpsProbe> createState() => _GpsProbeState();
}

class _GpsProbeState extends State<GpsProbe> {
  static const _ink = Color(0xFF1A1A16);
  static const _mid = Color(0xFF78746E);
  static const _lime = Color(0xFF6A9810);
  static const _coral = Color(0xFFB03020);

  final _current = RunAccumulator(config: RunFilterConfig.current);
  final _legacy = RunAccumulator(config: RunFilterConfig.legacy);

  StreamSubscription<Position>? _sub;
  Timer? _tick;
  File? _file;
  final _buffer = <String>[];

  bool _running = false;
  bool _always = false;
  String _status = '대기 중';
  DateTime? _startedAt;

  int _received = 0;
  final _counts = <String, int>{};
  double _lastAccuracy = 0;
  int _markers = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    // 자동 시작 — 시뮬레이터에서 사람 손 없이 돌리기 위함.
    // 권한은 `simctl privacy grant location-always`로 미리 부여돼 있어
    // 다이얼로그가 뜨지 않는다. 실기기에서는 권한 시트가 한 번 뜬다
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _status = '위치 서비스가 꺼져 있어요');
      return;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.whileInUse) {
      await ph.Permission.locationAlways.request();
      p = await Geolocator.checkPermission();
    }
    if (p != LocationPermission.always && p != LocationPermission.whileInUse) {
      setState(() => _status = '위치 권한이 없어요');
      return;
    }
    _always = p == LocationPermission.always;

    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/gps_probe.csv');
    if (!await _file!.exists()) {
      await _file!.writeAsString(
          'time,lat,lon,accuracy,speed,verdict,added_m,cur_m,legacy_m,marker\n');
    }

    _startedAt = DateTime.now();
    // 러닝 화면과 동일한 위치 설정
    _sub = Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: RunFilterConfig.current.locationDistanceFilter.toInt(),
        allowBackgroundLocationUpdates: _always,
        showBackgroundLocationIndicator: _always,
        pauseLocationUpdatesAutomatically: false,
      ),
    ).listen(_onFix, onError: (_) {
      if (mounted) setState(() => _status = 'GPS 오류 — 스트림이 끊겼어요');
    });

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    setState(() {
      _running = true;
      _status = _always ? '측정 중 · 항상 허용' : '측정 중 · 앱 사용 중에만(배경 불가)';
    });
  }

  void _onFix(Position pos) {
    _received++;
    _lastAccuracy = pos.accuracy;

    final beforeLegacy = _legacy.totalKm;
    final sample = _current.add(pos);
    _legacy.add(pos);

    // add()가 null이면 정확도·나이 필터에서 걸린 것이다. 어느 쪽인지는
    // 설정값으로 되짚는다 — 거리 로직을 probe에서 다시 구현하지 않기 위함
    final String verdict;
    if (sample != null) {
      verdict = sample.verdict.name;
    } else {
      const c = RunFilterConfig.current;
      final age = DateTime.now().difference(pos.timestamp);
      if (pos.accuracy > c.maxHorizontalAccuracy) {
        verdict = 'rejectedAccuracyHigh';
      } else if (pos.accuracy < c.minHorizontalAccuracy) {
        verdict = 'rejectedAccuracyNegative';
      } else if (c.maxFixAge != null && age > c.maxFixAge!) {
        verdict = 'rejectedStale';
      } else {
        verdict = 'rejectedUnknown';
      }
    }
    _counts[verdict] = (_counts[verdict] ?? 0) + 1;

    _buffer.add([
      pos.timestamp.toIso8601String(),
      pos.latitude.toStringAsFixed(7),
      pos.longitude.toStringAsFixed(7),
      pos.accuracy.toStringAsFixed(1),
      pos.speed.toStringAsFixed(2),
      verdict,
      (sample?.addedMeters ?? 0).toStringAsFixed(2),
      (_current.totalKm * 1000).toStringAsFixed(1),
      (_legacy.totalKm * 1000).toStringAsFixed(1),
      '',
    ].join(','));
    if (_buffer.length >= 10) _flush();

    // legacy가 더 더했다면 수정이 무언가를 걸러냈다는 뜻 — 로그에 이미 남는다
    if (_legacy.totalKm > beforeLegacy && sample?.addedMeters == 0) {
      // 의도된 차이. 별도 처리 없음
    }
  }

  Future<void> _flush() async {
    final f = _file;
    if (f == null || _buffer.isEmpty) return;
    final lines = _buffer.join('\n');
    _buffer.clear();
    await f.writeAsString('$lines\n', mode: FileMode.append);
  }

  Future<void> _mark(String label) async {
    _markers++;
    _buffer.add([
      DateTime.now().toIso8601String(),
      '', '', '', '', 'MARKER', '',
      (_current.totalKm * 1000).toStringAsFixed(1),
      (_legacy.totalKm * 1000).toStringAsFixed(1),
      label,
    ].join(','));
    await _flush();
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    await _mark('STOP');
    await _flush();
    if (mounted) setState(() { _running = false; _status = '정지됨 — 데이터 저장 완료'; });
  }

  String get _elapsed {
    if (_startedAt == null) return '0:00';
    final d = DateTime.now().difference(_startedAt!);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String _pace(double? secPerKm) {
    if (secPerKm == null || secPerKm.isInfinite || secPerKm.isNaN) return "--'--\"";
    final m = secPerKm ~/ 60, s = (secPerKm % 60).round();
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  @override
  Widget build(BuildContext context) {
    final cur = _current.totalKm * 1000;
    final leg = _legacy.totalKm * 1000;
    final diff = cur - leg;
    final stats = _current.stats;

    return Scaffold(
      backgroundColor: const Color(0xFFF0EAE0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('GPS 실측', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              Text(_status, style: const TextStyle(fontSize: 11, color: _mid)),
            ]),
            const SizedBox(height: 10),

            // 두 필터의 거리를 나란히 — 이 화면의 핵심
            Row(children: [
              _big('수정 후', cur, _lime),
              const SizedBox(width: 10),
              _big('수정 전', leg, _coral),
            ]),
            const SizedBox(height: 6),
            Center(
              child: Text(
                diff.abs() < 0.05
                    ? '차이 없음'
                    : '차이 ${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}m'
                        '  (수정 후가 ${diff > 0 ? '더 많이' : '덜'} 잡음)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
              ),
            ),
            const SizedBox(height: 14),

            Row(children: [
              _cell('시간', _elapsed),
              _cell('평균', _pace(stats.averageSecPerKm)),
              _cell('즉시', _pace(stats.instantSecPerKm)),
              _cell('정확도', '${_lastAccuracy.toStringAsFixed(0)}m'),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            Text('fix 수신 $_received회 · 마커 $_markers개',
                style: const TextStyle(fontSize: 12, color: _mid)),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (_counts.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(e.key, style: const TextStyle(fontSize: 12.5)),
                                Text('${e.value}',
                                    style: const TextStyle(
                                        fontSize: 12.5, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),

            // 시나리오 마커 — 나중에 CSV에서 구간을 잘라내기 위함
            if (_running) ...[
              Wrap(spacing: 6, runSpacing: 6, children: [
                _markBtn('바퀴'), _markBtn('정지시작'), _markBtn('정지끝'),
                _markBtn('걷기시작'), _markBtn('배경진입'), _markBtn('복귀'),
              ]),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _running ? _coral : _ink,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _running ? _stop : _start,
                child: Text(_running ? '정지 · 저장' : '측정 시작',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _big(String label, double meters, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: .35), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${meters.toStringAsFixed(1)}m',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _ink)),
          ]),
        ),
      );

  Widget _cell(String label, String value) => Expanded(
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _mid)),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _markBtn(String label) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _mark(label),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
}
