import 'package:flutter/material.dart';

import '../widgets/bottom_nav.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'us_screen.dart';

/// 앱의 루트 셸 — 홈 / 우리 / 설정 세 탭을 하단 네비게이션으로 전환
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

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
