import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/push_service.dart';
import '../services/run_recovery.dart';
import '../services/run_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import 'finish_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'us_screen.dart';

/// 앱의 루트 셸 — 홈 / 우리 / 설정 세 탭을 하단 네비게이션으로 전환.
/// 진입 시, 지난번 러닝 중 앱이 강제 종료돼 남은 기록(RunRecovery)이 있으면
/// 마무리를 제안함 — 이게 없으면 폰이 꺼지거나 앱이 죽는 순간 그날 러닝이
/// 통째로 사라짐
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;
  StreamSubscription? _pushTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
    _startPush();
  }

  /// 프로필이 준비된 뒤(= 여기까지 왔으면 항상 준비됨)에야 알림 권한을 물음.
  /// 앱 첫 실행에 맥락 없이 물으면 거절당하기 쉽고, iOS는 한 번 거절당하면
  /// 다시 물을 수 없어 설정에 들어가야만 되돌릴 수 있음
  void _startPush() {
    PushService.instance.start(AuthService().uid);
    _pushTapSub = PushService.instance.taps.listen(_onPushTap);
    final pending = PushService.instance.takePendingTap();
    if (pending != null) _onPushTap(pending);
  }

  /// 어떤 알림이든 홈 탭으로 보냄 — 친구 요청은 홈 상단 섹션에 있고,
  /// 러닝 요청은 홈이 구독 중인 세션 스트림이 수락 시트를 띄워줌
  void _onPushTap(PushTap tap) {
    if (!mounted) return;
    setState(() => _index = 0);
  }

  @override
  void dispose() {
    _pushTapSub?.cancel();
    super.dispose();
  }

  Future<void> _offerRecovery() async {
    final snapshot = await RunRecovery.load();
    if (snapshot == null || !mounted) return;

    final m = snapshot.seconds ~/ 60, s = snapshot.seconds % 60;
    final timeText =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final confirmed = await GoDialog.confirm(
      context,
      title: '마치지 못한 러닝이 있어요',
      body:
          '${snapshot.partnerName}와 달리던 기록이 남아 있어요.\n${snapshot.km.toStringAsFixed(1)}km · $timeText\n이 기록을 저장할까요?',
      confirmLabel: '기록 저장',
      cancelLabel: '버리기',
    );
    if (confirmed != true) {
      await RunRecovery.clear();
      return;
    }

    final kcal = LocationService.estimateKcal(snapshot.seconds);
    try {
      await RunService().submitResult(snapshot.sessionId, AuthService().uid,
          seconds: snapshot.seconds, km: snapshot.km, kcal: kcal);
    } catch (e, stack) {
      // 스냅샷은 지우지 않음 — 다음 실행 때 다시 제안돼 재시도 기회가 남음
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '기록 저장에 실패했어요. 다음에 다시 시도할게요.');
      return;
    }
    await RunRecovery.clear();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FinishScreen(
        sessionId: snapshot.sessionId,
        partnerName: snapshot.partnerName,
        mySeconds: snapshot.seconds,
        myKm: snapshot.km,
        myKcal: kcal,
        myMood: null,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                HomeScreen(),
                UsScreen(),
                SettingsScreen(),
              ],
            ),
          ),
          GoBottomNav(
            index: _index,
            onChanged: (i) => setState(() => _index = i),
          ),
        ]),
      ),
    );
  }
}
