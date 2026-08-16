// 러닝 화면 확인 도구 — 데모 세션을 손 안 대고 띄운다.
//
// 왜 따로 두는가: 러닝 화면을 보려면 설정 → 혼자 미리 체험하기 → 로비 →
// 준비까지 눌러 들어가야 하고, 첫 공명까지 또 20초를 기다려야 한다. 화면
// 다듬기와 앞으로 붙을 사운드는 이 타임라인을 수십 번 다시 봐야 하는데,
// 매번 그 길을 걸을 수는 없다.
//
// 여기서 도는 것은 **실제 러닝 화면 그 자체**다([RunScreen] demo 모드).
// 다른 점은 앱 시작과 동시에 러닝 화면으로 들어간다는 것뿐이다.
//
// 이벤트 로그는 러닝 화면이 디버그 빌드에서 스스로 찍는다:
//   flutter run -t lib/main_resonance_probe.dart
//
// 성능 오버레이(프레임 드랍 확인)는 켜서 띄운다. 기본이 꺼짐인 이유는
// 오버레이가 화면 위쪽 1/3을 덮어 정작 페이스 타이포를 못 보기 때문:
//   flutter run -t lib/main_resonance_probe.dart --dart-define=perf=true
import 'package:flutter/material.dart';

import 'screens/run_screen.dart';
import 'services/run_service.dart';
import 'theme.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      // 러닝 화면은 매 프레임 CustomPainter를 돌린다. 위쪽 막대(UI 스레드)와
      // 아래쪽 막대(래스터 스레드)가 초록선(16ms) 아래에 머물러야 한다
      showPerformanceOverlay: const bool.fromEnvironment('perf'),
      theme: GoTheme.light(),
      home: const RunScreen(
        sessionId: kDemoSessionId,
        partnerName: '지수',
        demo: true,
      ),
    ));
