import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';

import '../services/auth_service.dart';
import '../services/cooldown/voice_note_service.dart';
import '../services/cooldown/voice_prompt.dart';
import '../services/sound_settings.dart';
import '../theme.dart';
import '../widgets/pressable.dart';

/// 12 쿨다운 — 걷는 중의 디브리핑과 '음성 한 마디'(§5-2).
///
/// 완주 직후 2분은 **가장 감정적이면서 손을 못 쓰는** 시간이다(숨참·땀).
/// 그래서 이 화면은 귀로 먼저 말하고(디브리핑), 손으로는 버튼 하나만
/// 요구한다. 통계는 여기 없다 — 러너스 하이를 숫자로 식히지 않는다.
///
/// 이 한 마디가 사연 아카이브·카드 캡션·릴레이 문구의 단일 공급원이라
/// 채집이 이 화면의 유일한 목적이다. 대신 **지나치는 것이 항상 쉬워야**
/// 한다(§5-2의 '응답은 선택').
class CooldownScreen extends StatefulWidget {
  const CooldownScreen({
    super.key,
    required this.km,
    required this.journeyKm,
    required this.partnerName,
    required this.resonanceSeconds,
    required this.runId,
    required this.next,
    this.demo = false,
  });

  /// 오늘 달린 거리
  final double km;

  /// 오늘까지 쌓인 여정(오늘 포함)
  final double journeyKm;

  /// 함께 달린 상대. 혼자였으면 빈 문자열
  final String partnerName;

  final int resonanceSeconds;

  /// 음성이 붙을 러닝 문서. 2분 미만이라 고스트가 남지 않았으면 null이고,
  /// 그때는 올릴 곳이 없으므로 묻지도 않는다
  final String? runId;

  /// 이 화면 다음에 올 것(결과 화면). 자기가 자기를 갈아치우는 이유는,
  /// 부르는 쪽의 context로 이동하면 이미 사라진 러닝 화면의 Navigator를
  /// 붙잡게 되기 때문이다
  final WidgetBuilder next;

  final bool demo;

  @override
  State<CooldownScreen> createState() => _CooldownScreenState();
}

class _CooldownScreenState extends State<CooldownScreen> {
  final _voice = VoiceNoteService();
  final _tts = FlutterTts();

  bool _recording = false;
  bool _uploading = false;
  DateTime? _startedAt;
  Timer? _limit;
  StreamSubscription<Amplitude>? _ampSub;

  /// 파형 자리에 쌓이는 값(0~1). 20초 × 5개/초 = 100개가 천장이다
  final _levels = <double>[];

  @override
  void initState() {
    super.initState();
    _brief();
  }

  @override
  void dispose() {
    _limit?.cancel();
    _ampSub?.cancel();
    _voice.cancel();
    _voice.dispose();
    _tts.stop();
    super.dispose();
  }

  /// 오디오 디브리핑 — 화면을 안 봐도 되게 귀로 먼저 말한다.
  /// 소리를 꺼둔 사람에게는 말하지 않는다(글은 화면에 그대로 있다)
  Future<void> _brief() async {
    if (widget.demo) return;
    if (!await SoundSettings.load()) return;
    if (!await SoundSettings.loadBriefing()) return;
    try {
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(.45);
      await _tts.speak(_debriefSpeech);
    } catch (e, stack) {
      // 말이 안 나와도 화면은 그대로 선다
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  /// 읽는 글과 듣는 글은 다르다. 화면에는 'km'이 자연스럽고, 소리로는
  /// '킬로미터'라고 읽어야 한다 — 같은 문자열을 양쪽에 쓰면 한쪽이 어색해진다
  String get _debriefText => _debrief(spoken: false);
  String get _debriefSpeech => _debrief(spoken: true);

  String _debrief({required bool spoken}) {
    final unit = spoken ? '킬로미터' : 'km';
    final today = widget.km.toStringAsFixed(1);
    // 여정은 큰 수라 소수점이 의미를 더하지 않는다. '217km 지점'이지
    // '217.0km 지점'이 아니다
    final journey = widget.journeyKm >= 10
        ? widget.journeyKm.round().toString()
        : widget.journeyKm.toStringAsFixed(1);
    final base = '오늘의 $today$unit가 우리 여정 $journey$unit 지점에 놓였어요.';
    if (widget.partnerName.isEmpty || widget.resonanceSeconds <= 0) return base;
    return '$base ${widget.partnerName}와 ${widget.resonanceSeconds}초 겹쳤어요.';
  }

  Future<void> _startRecording() async {
    if (_recording || _uploading || widget.runId == null) return;
    await _tts.stop();
    final ok = await _voice.start();
    if (!ok) {
      if (!mounted) return;
      // 권한이 없으면 조용히 지나간다 — 완주 직후에 설정으로 보내지 않는다
      _finish(answered: false);
      return;
    }
    HapticFeedback.lightImpact();
    _startedAt = DateTime.now();
    _ampSub = _voice.amplitude().listen((a) {
      if (!mounted) return;
      // dBFS(-60~0)를 0~1로. 아래쪽은 잘라낸다 — 조용한 구간까지 그리면
      // 파형이 아니라 잡음이 된다
      final v = ((a.current + 45) / 45).clamp(0.0, 1.0);
      setState(() {
        _levels.add(v);
        if (_levels.length > 100) _levels.removeAt(0);
      });
    });
    _limit = Timer(VoiceNoteService.maxLength, _stopRecording);
    setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _limit?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    final elapsed =
        _startedAt == null ? null : DateTime.now().difference(_startedAt!);
    setState(() {
      _recording = false;
      _uploading = true;
    });
    HapticFeedback.mediumImpact();

    final path = await _voice.stop(elapsed: elapsed);
    if (path == null) {
      // 스친 것이지 한 마디가 아니다 — 아무 일도 없던 것으로 둔다
      if (mounted) setState(() => _uploading = false);
      return;
    }
    try {
      await _voice.upload(
        uid: AuthService().uid,
        runId: widget.runId!,
        path: path,
      );
      _finish(answered: true);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      // 올리지 못해도 완주는 완주다. 대답은 한 것으로 센다 —
      // 말한 사람에게 "다시 말해 달라"고 하지 않는다
      _finish(answered: true);
    }
  }

  Future<void> _finish({required bool answered}) async {
    if (!widget.demo) {
      await VoicePrompt.record(answered: answered, now: DateTime.now());
    }
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: widget.next));
  }

  @override
  Widget build(BuildContext context) {
    final askable = widget.runId != null;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('걷는 중 · 디브리핑',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: GoColors.dim)),
              const SizedBox(height: 10),
              Text(_debriefText,
                  style: const TextStyle(
                      fontSize: 14, height: 1.6, color: GoColors.ink)),
              const Spacer(),
              Center(child: _recordButton(askable)),
              const SizedBox(height: 22),
              Text(askable ? '오늘 러닝, 어땠어요?' : '오늘도 잘 달렸어요',
                  textAlign: TextAlign.center, style: GoTheme.serif(22)),
              const SizedBox(height: 12),
              SizedBox(height: 60, child: _waveform()),
              const SizedBox(height: 10),
              Text(
                  askable
                      ? '이 한 마디가 사연 아카이브와 러닝 카드의 원천이 돼요'
                      : '2분이 안 되는 러닝은 한 마디를 남기지 않아요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: GoColors.dim)),
              const Spacer(),
              Pressable(
                onTap: _recording || _uploading
                    ? null
                    : () => _finish(answered: false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(askable ? '건너뛰기' : '결과 보기',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GoColors.mid)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordButton(bool askable) {
    final label = _uploading
        ? '보내는 중'
        : _recording
            ? '● 녹음 중'
            : '● 녹음';
    return Opacity(
      opacity: askable ? 1 : .3,
      child: GestureDetector(
        // **누르고 있는 동안만** 녹음한다. 시작·정지를 따로 누르게 하면
        // 완주 직후의 사람은 반드시 한 번 잘못 누른다
        onTapDown: askable ? (_) => _startRecording() : null,
        onTapUp: askable ? (_) => _stopRecording() : null,
        onTapCancel: askable ? _stopRecording : null,
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _recording
                ? GoColors.coral.withValues(alpha: .16)
                : Colors.white,
            border: Border.all(
              color: _recording ? GoColors.coralDark : GoColors.line,
              width: _recording ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: GoTheme.serif(20,
                      color: _recording ? GoColors.coralDark : GoColors.ink)),
              const SizedBox(height: 4),
              Text(_recording ? '떼면 끝나요' : '누르고 말하기',
                  style: const TextStyle(fontSize: 11, color: GoColors.mid)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waveform() {
    if (_levels.isEmpty) {
      return Center(
        child: Text(
            _recording
                ? ''
                : '최대 ${VoiceNoteService.maxLength.inSeconds}초',
            style: const TextStyle(fontSize: 11, color: GoColors.dim)),
      );
    }
    return CustomPaint(painter: _Waveform(_levels), size: Size.infinite);
  }
}

/// 말하는 동안 자라는 막대. 정확한 파형이 아니라 **말이 들어가고 있다는
/// 신호**다 — 완주 직후에 필요한 건 정밀도가 아니라 확신이다
class _Waveform extends CustomPainter {
  const _Waveform(this.levels);

  final List<double> levels;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final width = (size.width - gap * (levels.length - 1)) / levels.length;
    if (width <= 0) return;
    final paint = Paint()..color = GoColors.coralDark.withValues(alpha: .6);
    for (var i = 0; i < levels.length; i++) {
      final h = (size.height * levels[i]).clamp(2.0, size.height);
      final x = i * (width + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, width, h),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Waveform old) => old.levels.length != levels.length;
}
