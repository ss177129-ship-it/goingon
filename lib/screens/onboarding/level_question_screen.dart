import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/onboarding/runner_level.dart';
import '../../theme.dart';
import '../../widgets/go_toast.dart';
import 'onboarding_scaffold.dart';

/// 온보딩 03 — 질문 하나.
///
/// **온보딩에서 묻는 것은 이것 하나뿐이다.** 물을수록 이탈하고, 우리가 정말
/// 알아야 하는 것은 "이 사람의 결핍이 무엇인가" 하나다(§2-3).
///
/// 이 답이 예전에는 홈을 갈랐는데, 에피소드런이 내려가면서 **지금은 화면을
/// 바꾸지 않는다**(2026-09-01). 그래도 계속 묻는 이유는 답이 쌓여야 나중에
/// 쓸 수 있어서다 — 질문을 뺐다가 다시 넣으면 그 사이 가입한 사람들의
/// 답만 비게 된다. 그래서 카피에서 "홈이 바뀐다"는 약속을 걷어냈다.
///
/// 선택지에 숫자가 없다. "주 몇 회"는 기록이 부끄러운 사람에게 첫 질문부터
/// 시험이 된다.
class LevelQuestionScreen extends StatefulWidget {
  const LevelQuestionScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<LevelQuestionScreen> createState() => _LevelQuestionScreenState();
}

class _LevelQuestionScreenState extends State<LevelQuestionScreen> {
  RunnerLevel? _choice;
  bool _saving = false;

  Future<void> _confirm() async {
    final choice = _choice;
    if (choice == null || _saving) return;
    setState(() => _saving = true);
    try {
      await AuthService().setLevel(choice);
      if (!mounted) return;
      widget.onDone();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _saving = false);
      GoToast.error(context, '저장에 실패했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      content: [
        Text('달리기, 어느 정도 하세요?', style: GoTheme.serif(24)),
        const SizedBox(height: 8),
        const Text('기억해 뒀다가, 맞는 리듬을 권할 때 써요',
            style: TextStyle(fontSize: 13, color: GoColors.mid)),
        OnboardingScaffold.gap,
        _option(RunnerLevel.beginner, '아직 10분도 길게 느껴져요'),
        OnboardingScaffold.gap,
        _option(RunnerLevel.experienced, '한 번 나가면 30분은 달려요'),
        const Spacer(),
      ],
      action: OnboardingButton(
        label: '다음',
        enabled: _choice != null && !_saving,
        onTap: _confirm,
      ),
    );
  }

  Widget _option(RunnerLevel level, String consequence) {
    final selected = _choice == level;
    return OnboardingCard(
      // 와이어프레임의 150 고정. 남는 공간을 카드가 먹으면 두 선택지가
      // 화면을 꽉 채워 "고르지 않고는 못 지나간다"처럼 보인다
      height: 150,
      selected: selected,
      onTap: _saving ? null : () => setState(() => _choice = level),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(level.choiceLabel,
            textAlign: TextAlign.center, style: GoTheme.serif(20)),
        const SizedBox(height: 8),
        Text(consequence,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: selected ? GoColors.limeDark : GoColors.mid)),
      ]),
    );
  }
}
