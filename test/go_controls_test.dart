import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/bottom_nav.dart';
import 'package:goingon/widgets/go_badge.dart';
import 'package:goingon/widgets/go_checkbox.dart';
import 'package:goingon/widgets/go_chip.dart';
import 'package:goingon/widgets/go_icon_button.dart';
import 'package:goingon/widgets/go_radio.dart';
import 'package:goingon/widgets/go_segment.dart';
import 'package:goingon/widgets/go_skeleton.dart';
import 'package:goingon/widgets/go_switch.dart';
import 'package:goingon/widgets/go_tabs.dart';
import 'package:goingon/widgets/pressable.dart';

/// 공용 컨트롤(디자인 핸드오프 2026-09-07 제안 1~8).
///
/// 전부 controlled — 값은 호출한 화면이 갖고, 위젯은 onChanged로 돌려줄 뿐
/// 스스로 바뀌지 않는다. 눌림은 [Pressable] 하나로 통일한다.
/// 역할 토큰 — 값이 아니라 뜻으로 검사한다
const R = GoRoles.light;

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: GoTheme.light(),
        home: Scaffold(body: Center(child: child)),
      );

  /// [finder]의 AnimatedContainer가 면으로 쓰는 색
  Color? fillOf(WidgetTester tester, Finder finder) {
    final c = tester.widget<AnimatedContainer>(finder);
    return (c.decoration as BoxDecoration?)?.color;
  }

  /// Scaffold 안쪽에도 같은 종류의 위젯이 있으므로 항상 [T] 안으로 좁힌다
  Finder inside<T>(Type of) =>
      find.descendant(of: find.byType(of), matching: find.byType(T));

  List<Color?> textColorsIn(WidgetTester tester, Type of) => tester
      .widgetList<AnimatedDefaultTextStyle>(inside<AnimatedDefaultTextStyle>(of))
      .map((t) => t.style.color)
      .toList();

  group('GoSwitch', () {
    testWidgets('51×31, 켬은 limeDark 트랙 / 끔은 dim 트랙', (tester) async {
      await tester.pumpWidget(host(GoSwitch(value: true, onChanged: (_) {})));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GoSwitch)), const Size(51, 31));
      expect(
          fillOf(tester, inside<AnimatedContainer>(GoSwitch).first),
          R.actionComplete.bg);

      await tester.pumpWidget(host(GoSwitch(value: false, onChanged: (_) {})));
      await tester.pumpAndSettle();
      expect(
          fillOf(tester, inside<AnimatedContainer>(GoSwitch).first),
          R.textSecondary);
    });

    testWidgets('탭하면 반대 값을 돌려주고 스스로는 바뀌지 않는다', (tester) async {
      bool? got;
      await tester.pumpWidget(host(GoSwitch(value: false, onChanged: (v) => got = v)));
      await tester.tap(find.byType(GoSwitch));
      await tester.pumpAndSettle();
      expect(got, isTrue);
      // controlled — 부모가 value를 안 바꿨으니 여전히 끔
      expect(
          fillOf(tester, inside<AnimatedContainer>(GoSwitch).first),
          R.textSecondary);
    });

    testWidgets('onChanged가 없으면 40%로 가라앉고 탭을 무시한다', (tester) async {
      await tester.pumpWidget(host(const GoSwitch(value: true)));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .4);
      expect(tester.widget<Pressable>(find.byType(Pressable)).onTap, isNull);
    });
  });

  group('GoCheckbox', () {
    testWidgets('선택하면 lime 면 + 체크, 미선택은 체크 없음', (tester) async {
      await tester.pumpWidget(host(
          GoCheckbox(value: true, onChanged: (_) {}, label: const Text('동의'))));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(fillOf(tester, find.byType(AnimatedContainer)), R.actionComplete.bg);

      await tester.pumpWidget(host(
          GoCheckbox(value: false, onChanged: (_) {}, label: const Text('동의'))));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('라벨을 눌러도 토글되고, 행 높이는 44 이상', (tester) async {
      bool? got;
      await tester.pumpWidget(host(SizedBox(
        width: 300,
        child: GoCheckbox(
            value: false, onChanged: (v) => got = v, label: const Text('동의')),
      )));
      await tester.tap(find.text('동의'));
      expect(got, isTrue);
      expect(tester.getSize(find.byType(GoCheckbox)).height,
          greaterThanOrEqualTo(44));
    });
  });

  group('GoRadioGroup', () {
    testWidgets('항목을 누르면 그 값이 오고, 선택된 것만 점이 있다', (tester) async {
      String? got;
      await tester.pumpWidget(host(SizedBox(
        width: 300,
        child: GoRadioGroup<String>(
          options: const [('a', '지금 갈게요'), ('b', '조금 있다가')],
          value: 'a',
          onChanged: (v) => got = v,
        ),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('조금 있다가'));
      expect(got, 'b');

      // 안쪽 점: 선택은 10, 미선택은 0
      final dots = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .where((c) =>
              (c.decoration as BoxDecoration?)?.color == R.dark.bg)
          .toList();
      expect(dots.length, 2);
      expect(dots.map((d) => d.constraints?.maxWidth).toList(), [10, 0]);
    });
  });

  group('GoTabs', () {
    testWidgets('활성 탭만 ink, 나머지는 mid — 누르면 인덱스가 온다', (tester) async {
      int? got;
      await tester.pumpWidget(host(GoTabs(
        labels: const ['함께한 순간', '마일스톤', '기록'],
        index: 0,
        onChanged: (i) => got = i,
      )));
      await tester.pumpAndSettle();
      expect(textColorsIn(tester, GoTabs),
          [R.dark.bg, R.textSecondary, R.textSecondary]);

      await tester.tap(find.text('기록'));
      expect(got, 2);
    });
  });

  group('GoSegment', () {
    testWidgets('높이 40, 활성 항목은 ink 면 + paper 글자', (tester) async {
      int? got;
      await tester.pumpWidget(host(SizedBox(
        width: 300,
        child: GoSegment(
          labels: const ['이번 주', '이번 달', '전체'],
          index: 1,
          onChanged: (i) => got = i,
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GoSegment)).height, 40);

      final fills = tester
          .widgetList<AnimatedContainer>(inside<AnimatedContainer>(GoSegment))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(fills, [Colors.transparent, R.dark.bg, Colors.transparent]);
      expect(textColorsIn(tester, GoSegment),
          [R.textSecondary, R.dark.fg, R.textSecondary]);

      await tester.tap(find.text('전체'));
      expect(got, 2);
    });
  });

  group('칩', () {
    testWidgets('GoSelectChip: 높이 32, 선택은 ink 면 + paper 글자', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(
          GoSelectChip(label: '5km', selected: true, onTap: () => tapped = true)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GoSelectChip)).height, 32);
      expect(fillOf(tester, inside<AnimatedContainer>(GoSelectChip)), R.dark.bg);
      expect(textColorsIn(tester, GoSelectChip), [R.dark.fg]);
      await tester.tap(find.text('5km'));
      expect(tapped, isTrue);
    });

    testWidgets('GoStoryChip·GoStatusTag 글자는 12px 이상', (tester) async {
      await tester.pumpWidget(host(const Column(mainAxisSize: MainAxisSize.min, children: [
        GoStoryChip('첫 런'),
        GoStatusTag('함께 달리기 요청'),
      ])));
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.style!.fontSize, greaterThanOrEqualTo(12));
      }
    });
  });

  group('배지', () {
    testWidgets('GoCountBadge: 0이면 그리지 않고, 있으면 수를 보여준다', (tester) async {
      await tester.pumpWidget(host(const GoCountBadge(
          count: 0, child: Icon(Icons.people_alt_outlined))));
      expect(inside<Stack>(GoCountBadge), findsNothing);
      expect(find.text('0'), findsNothing);

      await tester.pumpWidget(host(const GoCountBadge(
          count: 2, child: Icon(Icons.people_alt_outlined))));
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    });

    testWidgets('GoLiveDot 14, GoLiveTag는 점과 "달리는 중"', (tester) async {
      await tester.pumpWidget(host(const Column(mainAxisSize: MainAxisSize.min, children: [
        GoLiveDot(),
        GoLiveTag(),
      ])));
      expect(tester.getSize(find.byType(GoLiveDot)), const Size(14, 14));
      expect(find.text('달리는 중'), findsOneWidget);
    });
  });

  group('GoSkeletonRow', () {
    testWidgets('원 44·막대 둘·오른쪽 64×44, 애니메이션 없음', (tester) async {
      await tester.pumpWidget(host(const SizedBox(width: 320, child: GoSkeletonRow())));
      final sizes = tester
          .widgetList<Container>(find.descendant(
              of: find.byType(GoSkeletonRow), matching: find.byType(Container)))
          .map((c) => c.constraints)
          .whereType<BoxConstraints>()
          .map((b) => Size(b.maxWidth, b.maxHeight))
          .toList();
      expect(sizes, contains(const Size(44, 44)));
      expect(sizes, contains(const Size(64, 44)));
      expect(find.byType(AnimatedContainer), findsNothing);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });
  });

  group('GoBottomNav', () {
    testWidgets('선택된 탭만 ink 알약 + paper 아이콘, 나머지는 mid', (tester) async {
      int? got;
      await tester.pumpWidget(host(SizedBox(
        width: 390,
        child: GoBottomNav(index: 1, onChanged: (i) => got = i, requestCount: 3),
      )));
      await tester.pumpAndSettle();
      final pills = tester
          .widgetList<AnimatedContainer>(inside<AnimatedContainer>(GoBottomNav))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      // 선택된 탭은 잉크 그림자 알약(selection) — 주 색은 화면의 CTA에 양보
      expect(pills, [Colors.transparent, R.selection.bg, Colors.transparent]);
      final icons = tester
          .widgetList<Icon>(inside<Icon>(GoBottomNav))
          .map((i) => i.color)
          .toList();
      expect(icons, [R.textSecondary, R.selection.fg, R.textSecondary]);
      expect(find.text('3'), findsOneWidget, reason: '배지는 알약 위에도 남는다');

      await tester.tap(find.text('설정'));
      expect(got, 2);
    });

    testWidgets('선택된 탭은 채워진 아이콘, 나머지는 윤곽선 — 색 말고 형태로도 말한다',
        (tester) async {
      await tester.pumpWidget(host(SizedBox(
        width: 390,
        child: GoBottomNav(index: 1, onChanged: (_) {}),
      )));
      await tester.pumpAndSettle();
      final icons = tester
          .widgetList<Icon>(inside<Icon>(GoBottomNav))
          .map((i) => i.icon)
          .toList();
      expect(icons, [
        Icons.home_outlined,
        Icons.people_alt_rounded,
        Icons.settings_outlined,
      ]);
      // 알약은 선택된 자리에서만 온전한 크기 — 비선택 아이콘은 줄이지 않는다
      // (Pressable의 AnimatedScale은 제외 — 알약을 감싼 것만 본다)
      final scales = tester
          .widgetList<AnimatedScale>(inside<AnimatedScale>(GoBottomNav))
          .where((s) => s.child is AnimatedContainer)
          .map((s) => s.scale)
          .toList();
      expect(scales, [.9, 1, .9]);
    });
  });

  /// 손가락이 닿아 있는 동안만 보이는 눌림 상태. 스크린샷으로는 못 잡는다
  group('눌림 반응', () {
    Future<TestGesture> press(WidgetTester tester, Finder f) async {
      final g = await tester.startGesture(tester.getCenter(f));
      await tester.pump();
      return g;
    }

    testWidgets('GoSwitch: 눌려 있는 동안 손잡이가 4px 늘어난다', (tester) async {
      await tester.pumpWidget(host(GoSwitch(value: false, onChanged: (_) {})));
      await tester.pumpAndSettle();
      AnimatedContainer thumb() => tester
          .widgetList<AnimatedContainer>(inside<AnimatedContainer>(GoSwitch))
          .last;
      expect(thumb().constraints?.maxWidth, 27);
      final g = await press(tester, find.byType(GoSwitch));
      expect(thumb().constraints?.maxWidth, 31);
      await g.up();
      await tester.pumpAndSettle();
      expect(thumb().constraints?.maxWidth, 27);
    });

    testWidgets('GoSegment: 비활성 항목을 누르면 잉크 8%가 깔린다', (tester) async {
      await tester.pumpWidget(host(SizedBox(
        width: 300,
        child: GoSegment(labels: const ['a', 'b'], index: 0, onChanged: (_) {}),
      )));
      await tester.pumpAndSettle();
      final g = await press(tester, find.text('b'));
      final fills = tester
          .widgetList<AnimatedContainer>(inside<AnimatedContainer>(GoSegment))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(fills, [R.dark.bg, R.pressOverlay]);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('GoBottomNav: 활성 알약은 가라앉고 비활성 자리엔 알약이 뜬다', (tester) async {
      await tester.pumpWidget(host(SizedBox(
        width: 390,
        child: GoBottomNav(index: 0, onChanged: (_) {}),
      )));
      await tester.pumpAndSettle();
      List<Color?> pills() => tester
          .widgetList<AnimatedContainer>(inside<AnimatedContainer>(GoBottomNav))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      final g1 = await press(tester, find.text('홈'));
      expect(pills()[0], R.selection.pressed);
      await g1.up();
      await tester.pumpAndSettle();
      final g2 = await press(tester, find.text('설정'));
      expect(pills()[2], R.pressOverlay);
      await g2.up();
      await tester.pumpAndSettle();
      expect(pills(), [R.selection.bg, Colors.transparent, Colors.transparent]);
    });

    testWidgets('GoSelectChip·GoCheckbox: 누르면 면이 가라앉는다', (tester) async {
      await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        GoSelectChip(label: '5km', selected: false, onTap: () {}),
        SizedBox(
          width: 300,
          child: GoCheckbox(value: true, onChanged: (_) {}, label: const Text('동의')),
        ),
      ])));
      await tester.pumpAndSettle();
      final g1 = await press(tester, find.text('5km'));
      expect(fillOf(tester, inside<AnimatedContainer>(GoSelectChip)),
          R.surfacePressed);
      await g1.up();
      final g2 = await press(tester, find.text('동의'));
      expect(fillOf(tester, inside<AnimatedContainer>(GoCheckbox)),
          R.actionComplete.pressed);
      await g2.up();
      await tester.pumpAndSettle();
    });

    testWidgets('GoIconButton: 44 표적, 누르면 잉크 8% 원 + 0.92 축소', (tester) async {
      await tester.pumpWidget(host(GoIconButton(icon: Icons.search, onTap: () {})));
      expect(tester.getSize(find.byType(GoIconButton)), const Size(44, 44));
      final g = await press(tester, find.byType(GoIconButton));
      expect(fillOf(tester, inside<AnimatedContainer>(GoIconButton)),
          R.pressOverlay);
      expect(
          tester
              .widget<AnimatedScale>(inside<AnimatedScale>(GoIconButton))
              .scale,
          .92);
      await g.up();
      await tester.pumpAndSettle();
    });
  });
}
