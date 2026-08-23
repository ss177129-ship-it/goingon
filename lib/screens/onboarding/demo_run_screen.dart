import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../run_screen.dart';
import 'onboarding_scaffold.dart';

/// 온보딩 02 — 데모런. 심사관용 '혼자 미리 체험하기'가 도는 곳도 여기다.
///
/// **진입점은 둘, 내용물은 하나**(P0 후속 과제). 예전에는 심사관은 로비를
/// 거쳐 데모 러닝으로 갔고 온보딩은 아무것도 없었다. 로비가 사라지면서
/// 둘을 같은 문으로 모았다 — 심사관이 보는 것과 처음 온 사람이 보는 것이
/// 다르면, 심사관이 본 것은 이 앱이 아니다.
///
/// 페이서가 가상임을 화면에 **먼저** 밝힌다(§5 '정직한 가상'). 나중에
/// 들키는 가상은 배신이고, 미리 밝힌 가상은 연출이다.
class DemoRunScreen extends StatelessWidget {
  const DemoRunScreen({super.key, required this.onDone});

  /// 데모런을 마쳤거나 지나갔을 때
  final VoidCallback onDone;

  /// 데모 한 판의 길이. [DemoResonanceScript]가 ~19초에 첫 공명,
  /// ~62초에 두 번째 공명을 놓으므로 60초면 "우연이 아니다"까지 닿는다.
  /// 실제 러닝에는 이런 상한이 없다 — 데모에만 두는 이유는 RunScreen 주석에
  static const length = Duration(seconds: 60);

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      content: [
        Text('데모런 · ${length.inSeconds}초', style: GoTheme.serif(20)),
        OnboardingScaffold.gap,
        OnboardingCard(
          height: 110,
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                  color: GoColors.canvas, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('지', style: GoTheme.serif(19)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('지수', style: GoTheme.serif(19)),
                  const SizedBox(height: 4),
                  const Text('가상의 페이서예요 — 실제 사람이 아니에요',
                      style: TextStyle(fontSize: 12, color: GoColors.mid)),
                ],
              ),
            ),
          ]),
        ),
        OnboardingScaffold.gap,
        const OnboardingCard(height: 230, child: _ResonancePreview()),
        OnboardingScaffold.gap,
        const Text('두 발의 박자가 맞는 순간, 화음이 열립니다',
            style: TextStyle(fontSize: 13, color: GoColors.mid)),
        const Spacer(),
      ],
      action: OnboardingButton(
        label: '데모런 시작',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RunScreen(
            sessionId: 'demo',
            partnerName: '지수',
            demo: true,
            autoFinishAfter: length,
            // 완료 화면의 닫기가 홈으로 빠지지 않고 부르는 쪽으로 돌아온다.
            // 온보딩이면 다음 장으로, 설정에서 왔으면 설정으로
            // RunScreen은 pushReplacement로 완료 화면이 되므로 이 위에
            // 쌓인 라우트는 정확히 하나다. 하나만 걷어내면 이 화면으로 돌아온다
            onFinished: () {
              Navigator.of(context).pop();
              onDone();
            },
          ),
        )),
      ),
    );
  }
}

/// 데모런 비주얼 — 나(lime)와 상대(coral)의 원이 겹치고, 겹친 자리에만
/// 골드가 생긴다. **골드는 공명 전용**이라 이 그림에서도 겹친 부분에만 쓴다:
/// 색 규칙 자체가 "공명은 둘이 함께 만든 것"이라는 문장이다
class _ResonancePreview extends StatelessWidget {
  const _ResonancePreview();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.fromHeight(160),
      painter: _ResonancePreviewPainter(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('발이 맞으면 여기 골드가 켜져요',
              style: TextStyle(
                  fontSize: 11, color: GoColors.ink.withValues(alpha: .45))),
        ),
      ),
    );
  }
}

class _ResonancePreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width * .26, size.height * .34);
    final cy = size.height / 2 - 8;
    final left = Offset(size.width / 2 - r * .55, cy);
    final right = Offset(size.width / 2 + r * .55, cy);

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(
        left, r, Paint()..color = GoColors.lime.withValues(alpha: .55));
    canvas.drawCircle(
        right, r, Paint()..color = GoColors.coral.withValues(alpha: .45));

    // 겹친 자리만 골드로 덮는다 — 두 원의 교집합
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: left, radius: r)));
    canvas.drawCircle(right, r, Paint()..color = GoColors.resonance);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ResonancePreviewPainter old) => false;
}
