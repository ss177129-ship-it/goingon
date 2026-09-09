import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/invite.dart';
import '../services/invite_service.dart';
import '../services/push_service.dart';
import '../services/run_recovery.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import 'finish_screen.dart';
import 'home_screen.dart';
import 'invites_screen.dart';
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

class _RootScreenState extends State<RootScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// 탭이 바뀔 때 새 화면이 살짝 아래에서 떠오르며 밝아진다. IndexedStack은
  /// 그대로 두고(각 탭의 스트림·스크롤 위치가 살아야 하므로) 그 위에서
  /// 한 번만 재생한다. 목적은 장식이 아니라 "화면이 바뀌었다"를 손가락이
  /// 아닌 눈에도 전하는 것 — 없으면 내용이 뚝 바뀌어 어디를 눌렀는지
  /// 놓치기 쉽다. 동작 줄이기가 켜져 있으면 재생하지 않는다
  late final AnimationController _tabAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );

  void _goTab(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    if (MediaQuery.of(context).disableAnimations) return;
    _tabAnim.forward(from: 0);
  }

  StreamSubscription? _pushTapSub;
  StreamSubscription? _invitesSub;

  /// 답해야 할 제안 수 — '제안' 탭 배지. 홈이 같은 스트림을 따로 구독하지만,
  /// 배지는 어느 탭에 있든 보여야 하므로 셸이 갖는다.
  ///
  /// 전에는 친구 요청 수를 '우리' 탭에 달았다 — 배지가 가리키는 곳과 실제로
  /// 그 목록이 있는 곳(홈)이 달랐다
  int _needsAnswer = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
    _startPush();
    _invitesSub = InviteService().stream(AuthService().uid).listen(
      (list) {
        final now = DateTime.now();
        final n = list
            .where((i) => i.cardFor(now) == InviteCard.needsAnswer)
            .length;
        if (mounted && n != _needsAnswer) setState(() => _needsAnswer = n);
      },
      onError: (e, stack) {
        // 배지가 없어도 앱은 동작한다
        FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      },
    );
  }

  /// 프로필이 준비된 뒤(= 여기까지 왔으면 항상 준비됨)에야 알림 권한을 물음.
  /// 앱 첫 실행에 맥락 없이 물으면 거절당하기 쉽고, iOS는 한 번 거절당하면
  /// 다시 물을 수 없어 설정에 들어가야만 되돌릴 수 있음
  void _startPush() {
    // **requestAndStart**여야 한다. `start()`는 이미 허락받은 기기의 토큰만
    // 등록하고 권한은 묻지 않는다 — 묻는 자리를 첫 완주 직후로 옮기면서
    // 그렇게 갈라놨는데(P5), UI 롤백으로 그 화면이 사라져 **아무도 묻지 않는
    // 상태**가 됐다. 여기서 묻는 것이 P5 이전의 동작이다
    PushService.instance.requestAndStart(AuthService().uid);
    _pushTapSub = PushService.instance.taps.listen(_onPushTap);
    final pending = PushService.instance.takePendingTap();
    if (pending != null) _onPushTap(pending);
  }

  /// 알림을 누르면 그것이 사는 자리로 보낸다.
  ///
  /// 전에는 무엇이든 홈으로 보내고 payload의 sessionId를 버렸다. 러닝 요청은
  /// 홈이 띄우는 수락 시트에 기댔는데, 그 시트는 다른 시트가 떠 있거나
  /// 러닝 중이면 나타나지 않는다 — 알림을 눌렀는데 아무 일도 안 일어났다
  void _onPushTap(PushTap tap) {
    if (!mounted) return;
    _goTab(tap.type == 'runRequest' ? 1 : 0);
  }

  @override
  void dispose() {
    _tabAnim.dispose();
    _pushTapSub?.cancel();
    _invitesSub?.cancel();
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
    Navigator.push(
        context,
        MaterialPageRoute(
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
      // 아래쪽 안전영역은 SafeArea가 먹지 않는다 — 탭바가 홈 인디케이터
      // 자리까지 직접 덮어야 바닥에서 뜬 판때기로 보이지 않는다
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Expanded(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _tabAnim, curve: GoMotion.curve)
                  .drive(Tween(begin: .55, end: 1)),
              child: SlideTransition(
                position: CurvedAnimation(
                        parent: _tabAnim, curve: GoMotion.curve)
                    .drive(
                        Tween(begin: const Offset(0, .012), end: Offset.zero)),
                child: IndexedStack(
                  index: _index,
                  children: const [
                    HomeScreen(),
                    InvitesScreen(),
                    UsScreen(),
                    SettingsScreen(),
                  ],
                ),
              ),
            ),
          ),
          GoBottomNav(
            index: _index,
            requestCount: _needsAnswer,
            onChanged: _goTab,
          ),
        ]),
      ),
    );
  }
}
