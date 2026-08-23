import 'package:flutter/material.dart';

import '../root_screen.dart';
import 'demo_run_screen.dart';
import 'invite_screen.dart';
import 'level_question_screen.dart';

/// 가입 뒤 온보딩 세 장을 순서대로 태우는 셸 — 데모런 → 레벨 질문 → 초대.
///
/// 왜 라우트를 쌓지 않고 한 화면 안에서 갈아끼우는가: 온보딩은 되돌아갈
/// 곳이 없는 흐름이다. 라우트로 쌓으면 스와이프 백으로 로그인 화면까지
/// 돌아가고, 그때 계정은 이미 만들어져 있어서 화면과 실제 상태가 어긋난다.
///
/// **여덟 걸음은 여기 없다.** 그건 가입 전 화면이라 계정이 생기기 전에
/// 지나간다(main.dart의 SplashGate).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _step = 0;

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const RootScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: switch (_step) {
        0 => DemoRunScreen(onDone: _next),
        1 => LevelQuestionScreen(onDone: _next),
        _ => InviteScreen(onDone: _next),
      },
    );
  }
}
