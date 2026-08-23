import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../services/cadence/cadence_engine.dart';
import '../../services/sound/sound_engine.dart';
import '../../services/sound/soloud_sound_engine.dart';
import '../../services/sound_settings.dart';
import '../../theme.dart';
import '../../widgets/pressable.dart';
import 'onboarding_scaffold.dart';

/// 온보딩 01 — 여덟 걸음. **가입보다 먼저** 오는 화면이다.
///
/// 여기서 파는 것은 설명이 아니라 감각이다: 제자리에서 여덟 번 걸으면
/// 걸음마다 소리가 나고, 그 소리가 박자가 된다. 30초 안에 "이 앱이 내 발을
/// 듣는다"가 몸으로 전달되면 로그인 화면의 의미가 달라진다.
///
/// **내 발소리를 들려주는 유일한 화면**이다. 러닝 중에는 내 발소리가 기본
/// 무음이고(고유수용감각과 중복이라 통화 에코처럼 거슬린다), 들리는 발걸음은
/// 상대의 것뿐이다. 그 규칙의 예외를 여기 두는 이유는 이 화면의 목적이
/// **내 걸음이 소리가 된다는 사실 자체**이기 때문이다.
class EightStepsScreen extends StatefulWidget {
  const EightStepsScreen({super.key, required this.onDone});

  /// 여덟 걸음을 채웠거나 건너뛰었을 때. 진행 저장은 호출부가 한다
  final VoidCallback onDone;

  /// 몇 걸음이면 충분한가. 넷은 우연으로 보이고 열여섯은 과제가 된다
  static const target = 8;

  /// 이만큼 걸음이 없으면 손가락으로도 되게 열어준다.
  /// 시뮬레이터에는 가속도계가 없고, 지하철에서 앱을 처음 여는 사람도 있다
  static const fallbackAfter = Duration(seconds: 6);

  @override
  State<EightStepsScreen> createState() => _EightStepsScreenState();
}

class _EightStepsScreenState extends State<EightStepsScreen> {
  final _cadence = CadenceEngine();
  StreamSubscription<DateTime>? _stepSub;
  Timer? _fallbackTimer;

  SoundEngine? _sound;

  int _steps = 0;
  bool _listening = false;

  /// 걸음이 안 잡혀서 손가락 길을 열어준 상태
  bool _tapFallback = false;

  bool get _done => _steps >= EightStepsScreen.target;

  @override
  void initState() {
    super.initState();
    _loadSound();
  }

  /// 소리가 이 화면의 내용물이라 미리 올려둔다 — 첫 걸음에서 로딩이 끝나길
  /// 기다리면 바로 그 한 걸음이 조용해지고, 그 한 번이 이 화면의 전부다
  Future<void> _loadSound() async {
    if (!await SoundSettings.load()) return;
    final engine = SoLoudSoundEngine();
    await engine.loadAssets();
    if (!mounted) {
      await engine.dispose();
      return;
    }
    _sound = engine;
  }

  void _startListening() {
    setState(() => _listening = true);
    _cadence.start();
    _stepSub = _cadence.steps.listen((_) => _onStep());
    _fallbackTimer = Timer(EightStepsScreen.fallbackAfter, () {
      if (mounted && _steps == 0) setState(() => _tapFallback = true);
    });
  }

  void _onStep() {
    if (!mounted || _done) return;
    setState(() => _steps++);
    _fallbackTimer?.cancel();
    if (_done) {
      // 완성음은 이 앱에서 가장 좋은 소리(공명 진입음)와 같은 것을 쓴다.
      // 여덟 걸음의 끝에 이미 그 소리를 들려주면, 나중에 진짜 공명이
      // 왔을 때 "아, 그때 그 소리"가 된다
      HapticFeedback.mediumImpact();
      _sound?.playOneShot(SoundId.chimeMatch);
      _stopListening();
      return;
    }
    HapticFeedback.lightImpact();
    _sound?.playOneShot(SoundId.sigHere, volume: .7);
  }

  void _stopListening() {
    _stepSub?.cancel();
    _stepSub = null;
    _cadence.stop();
    _fallbackTimer?.cancel();
  }

  @override
  void dispose() {
    _stopListening();
    _cadence.dispose();
    _sound?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      content: [
        Text('goingon',
            textAlign: TextAlign.center,
            style: GoTheme.serif(16, color: GoColors.dim)),
        const Spacer(),
        Center(child: _ring()),
        const Spacer(),
        Text(_done ? '이게 당신의 리듬이에요' : '당신의 발소리를 들려주세요',
            textAlign: TextAlign.center, style: GoTheme.serif(24)),
        const SizedBox(height: 8),
        Text(
            _done
                ? '고잉온은 이 리듬으로 사람을 잇습니다'
                : '가입보다 먼저 — 걸음이 비트가 되는 것을 30초 만에',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: GoColors.mid)),
      ],
      action: OnboardingButton(
        label: _done
            ? '다음'
            : _listening
                ? '걷고 있어요…'
                : '발소리 듣기',
        enabled: !_listening || _done,
        onTap: _done ? widget.onDone : _startListening,
      ),
      footer: _tapFallback && !_done
          ? Pressable(
              onTap: widget.onDone,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('나중에 할게요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: GoColors.dim)),
              ),
            )
          : null,
    );
  }

  Widget _ring() {
    return Pressable(
      // 걸음이 안 잡힐 때만 손가락이 걸음을 대신한다. 처음부터 열어두면
      // 제자리걸음 대신 화면을 두드리게 되고, 그러면 이 화면은 아무것도
      // 전달하지 못한 채 지나간다
      onTap: _tapFallback && !_done ? _onStep : null,
      scale: _tapFallback ? .97 : 1,
      child: SizedBox(
        width: 210,
        height: 210,
        child: CustomPaint(
          painter: _StepRingPainter(_steps),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_listening && !_done)
                Text('$_steps', style: GoTheme.serif(44))
              else
                Text(_done ? '여덟 걸음' : '여덟 걸음', style: GoTheme.serif(20)),
              const SizedBox(height: 2),
              Text(
                  _done
                      ? '완성'
                      : _tapFallback
                          ? '원을 톡톡 두드려도 돼요'
                          : _listening
                              ? '여덟 걸음 중'
                              : '제자리에서 걸어보세요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: GoColors.mid)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 여덟 조각으로 끊긴 링. 이어진 원호가 아니라 **조각**인 이유는 걸음이
/// 연속량이 아니라 셀 수 있는 것이기 때문 — 한 걸음에 한 칸이 켜진다
class _StepRingPainter extends CustomPainter {
  const _StepRingPainter(this.filled);

  final int filled;

  static const _stroke = 6.0;
  static const _gap = 0.10; // 조각 사이 빈 각(rad)

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(_stroke / 2, _stroke / 2,
        size.width - _stroke, size.height - _stroke);
    canvas.drawCircle(size.center(Offset.zero),
        size.width / 2 - _stroke, Paint()..color = GoColors.canvas);

    const segment = (math.pi * 2) / EightStepsScreen.target;
    for (var i = 0; i < EightStepsScreen.target; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = i < filled ? GoColors.lime : GoColors.line;
      // 12시에서 시작해 시계방향 — 시간이 도는 방향과 같게
      canvas.drawArc(rect, -math.pi / 2 + segment * i + _gap / 2,
          segment - _gap, false, paint);
    }
  }

  @override
  bool shouldRepaint(_StepRingPainter old) => old.filled != filled;
}
