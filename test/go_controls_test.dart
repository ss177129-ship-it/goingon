import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/bottom_nav.dart';
import 'package:goingon/widgets/go_badge.dart';
import 'package:goingon/widgets/go_checkbox.dart';
import 'package:goingon/widgets/go_chip.dart';
import 'package:goingon/widgets/go_group.dart';
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
      .widgetList<AnimatedDefaultTextStyle>(
          inside<AnimatedDefaultTextStyle>(of))
      .map((t) => t.style.color)
      .toList();

  group('GoSwitch', () {
    testWidgets('트랙 51×31 · 표적 51×44, 켬은 limeDark 트랙 / 끔은 dim 트랙',
        (tester) async {
      await tester.pumpWidget(host(GoSwitch(value: true, onChanged: (_) {})));
      await tester.pumpAndSettle();
      // 보이는 트랙은 51×31 그대로, 손가락이 닿는 자리만 44까지 넓다
      expect(tester.getSize(inside<AnimatedContainer>(GoSwitch).first),
          const Size(51, 31));
      expect(tester.getSize(find.byType(GoSwitch)), const Size(51, 44));
      expect(fillOf(tester, inside<AnimatedContainer>(GoSwitch).first),
          R.actionComplete.bg);

      await tester.pumpWidget(host(GoSwitch(value: false, onChanged: (_) {})));
      await tester.pumpAndSettle();
      expect(fillOf(tester, inside<AnimatedContainer>(GoSwitch).first),
          R.textSecondary);
    });

    testWidgets('탭하면 반대 값을 돌려주고 스스로는 바뀌지 않는다', (tester) async {
      bool? got;
      await tester
          .pumpWidget(host(GoSwitch(value: false, onChanged: (v) => got = v)));
      await tester.tap(find.byType(GoSwitch));
      await tester.pumpAndSettle();
      expect(got, isTrue);
      // controlled — 부모가 value를 안 바꿨으니 여전히 끔
      expect(fillOf(tester, inside<AnimatedContainer>(GoSwitch).first),
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
      expect(
          fillOf(tester, find.byType(AnimatedContainer)), R.actionComplete.bg);

      await tester.pumpWidget(host(GoCheckbox(
          value: false, onChanged: (_) {}, label: const Text('동의'))));
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
          .where((c) => (c.decoration as BoxDecoration?)?.color == R.dark.bg)
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

    testWidgets('한 글자짜리 라벨도 표적이 44pt 이상 — 글자 폭이 곧 표적이면 안 된다', (tester) async {
      await tester.pumpWidget(host(GoTabs(
        labels: const ['주', '월', '전체'],
        index: 0,
        onChanged: (_) {},
      )));
      await tester.pumpAndSettle();
      for (final p in tester.widgetList<Pressable>(inside<Pressable>(GoTabs))) {
        final size = tester.getSize(find.byWidget(p));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
    });
  });

  group('GoSegment', () {
    testWidgets('높이 53(항목 44), 활성 항목은 ink 면 + paper 글자', (tester) async {
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
      // 통 높이 53에서 안쪽 여백 3×2와 테두리 1.5×2를 빼면 항목이 딱 44pt —
      // 손가락이 닿는 자리가 애플 최소치를 넘긴다
      expect(tester.getSize(find.byType(GoSegment)).height, 53);
      final itemHeights = tester
          .widgetList<Pressable>(inside<Pressable>(GoSegment))
          .map((p) => tester.getSize(find.byWidget(p)).height)
          .toList();
      expect(itemHeights, everyElement(greaterThanOrEqualTo(44)));

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
    testWidgets('GoSelectChip: 칩 32 · 표적 44, 선택은 ink 면 + paper 글자',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(GoSelectChip(
          label: '5km', selected: true, onTap: () => tapped = true)));
      await tester.pumpAndSettle();
      // 보이는 칩은 32 — 44로 키우면 칩이 아니라 버튼이 된다. 대신 닿는
      // 자리를 44로 넓혔다
      expect(
          tester.getSize(inside<AnimatedContainer>(GoSelectChip)).height, 32);
      expect(tester.getSize(find.byType(GoSelectChip)).height, 44);
      expect(
          fillOf(tester, inside<AnimatedContainer>(GoSelectChip)), R.dark.bg);
      expect(textColorsIn(tester, GoSelectChip), [R.dark.fg]);
      await tester.tap(find.text('5km'));
      expect(tapped, isTrue);
    });

    testWidgets('GoStoryChip·GoStatusTag 글자는 12px 이상', (tester) async {
      await tester.pumpWidget(
          host(const Column(mainAxisSize: MainAxisSize.min, children: [
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
      await tester.pumpWidget(
          host(const Column(mainAxisSize: MainAxisSize.min, children: [
        GoLiveDot(),
        GoLiveTag(),
      ])));
      expect(tester.getSize(find.byType(GoLiveDot)), const Size(14, 14));
      expect(find.text('달리는 중'), findsOneWidget);
    });
  });

  group('GoSkeletonRow', () {
    testWidgets('원 44·막대 둘·오른쪽 64×44, 애니메이션 없음', (tester) async {
      await tester
          .pumpWidget(host(const SizedBox(width: 320, child: GoSkeletonRow())));
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
    Widget nav(int index, {ValueChanged<int>? onChanged, int requests = 0}) =>
        host(SizedBox(
          width: 390,
          child: GoBottomNav(
              index: index,
              onChanged: onChanged ?? (_) {},
              badgeCount: requests),
        ));

    /// 탭바 안의 AnimatedContainer는 [미끄러지는 알약, 홈·제안·우리·설정의
    /// 눌림 면] 순서다 — 알약은 **하나**뿐이라 자리 수만큼 있지 않다
    List<Color?> fills(WidgetTester tester) => tester
        .widgetList<AnimatedContainer>(inside<AnimatedContainer>(GoBottomNav))
        .map((c) => (c.decoration as BoxDecoration).color)
        .toList();

    double pillX(WidgetTester tester) =>
        tester.getTopLeft(inside<AnimatedContainer>(GoBottomNav).first).dx;

    testWidgets('알약은 하나뿐이고 선택된 아이콘만 잉크', (tester) async {
      int? got;
      await tester.pumpWidget(nav(1, onChanged: (i) => got = i, requests: 3));
      await tester.pumpAndSettle();
      // 선택된 탭은 잉크 그림자 알약(selection) — 주 색은 화면의 CTA에 양보.
      // 나머지 셋은 눌렸을 때만 색이 드는 빈 면이다
      expect(fills(tester), [
        R.selection.bg,
        Colors.transparent,
        Colors.transparent,
        Colors.transparent,
        Colors.transparent,
      ]);
      final icons = tester
          .widgetList<Icon>(inside<Icon>(GoBottomNav))
          .map((i) => i.color)
          .toList();
      expect(icons, [
        R.textSecondary,
        R.selection.fg,
        R.textSecondary,
        R.textSecondary,
      ]);
      // 배지는 '제안' 탭에 붙는다 — 답해야 할 것이 사는 자리다
      expect(find.text('3'), findsOneWidget, reason: '배지는 알약 위에도 남는다');

      // 라벨을 지운 뒤로 탭바에는 글자가 없다 — 아이콘으로 누른다
      await tester.tap(find.byIcon(Icons.settings_outlined));
      expect(got, 3);
    });

    testWidgets('선택된 탭은 채워진 아이콘, 나머지는 윤곽선 — 색 말고 형태로도 말한다', (tester) async {
      await tester.pumpWidget(nav(1));
      await tester.pumpAndSettle();
      final icons = tester
          .widgetList<Icon>(inside<Icon>(GoBottomNav))
          .map((i) => i.icon)
          .toList();
      expect(icons, [
        Icons.home_outlined,
        Icons.chat_bubble_rounded,
        Icons.people_alt_outlined,
        Icons.settings_outlined,
      ]);
    });

    testWidgets('손가락이 닿는 자리는 44pt 이상 — 알약(32)이 아니라 탭이 표적이다', (tester) async {
      await tester.pumpWidget(nav(0));
      await tester.pumpAndSettle();
      for (final icon in [
        Icons.home_rounded,
        Icons.chat_bubble_outline,
        Icons.people_alt_outlined,
        Icons.settings_outlined,
      ]) {
        final target = find.ancestor(
            of: find.byIcon(icon), matching: find.byType(Pressable));
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44),
            reason: '$icon 탭의 표적이 44pt보다 낮다');
      }
    });

    testWidgets('탭이 바뀌면 알약이 옆자리까지 미끄러져 간다 — 꺼졌다 켜지는 게 아니다', (tester) async {
      await tester.pumpWidget(nav(0));
      await tester.pumpAndSettle();
      final at0 = pillX(tester);

      await tester.pumpWidget(nav(1));
      await tester.pump(const Duration(milliseconds: 60));
      final onTheWay = pillX(tester);
      await tester.pumpAndSettle();
      final at1 = pillX(tester);

      // 한 칸 = (너비 − 좌우 여백) ÷ 탭 수
      expect(at1 - at0, closeTo((390 - 28 * 2) / 4, .01));
      // 중간 프레임이 두 자리 **사이**에 있어야 이동이다. 순간이동이면
      // 첫 프레임에 이미 도착해 있다
      expect(onTheWay, greaterThan(at0));
      expect(onTheWay, lessThan(at1));
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
      // [미끄러지는 알약, 홈·제안·우리·설정의 눌림 면]
      List<Color?> pills() => tester
          .widgetList<AnimatedContainer>(inside<AnimatedContainer>(GoBottomNav))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      final g1 = await press(tester, find.byIcon(Icons.home_rounded));
      expect(pills()[0], R.selection.pressed, reason: '선택된 자리는 알약이 가라앉는다');
      await g1.up();
      await tester.pumpAndSettle();
      final g2 = await press(tester, find.byIcon(Icons.settings_outlined));
      expect(pills()[4], R.pressOverlay, reason: '빈 자리는 잉크 8%가 잠깐 깔린다');
      await g2.up();
      await tester.pumpAndSettle();
      expect(pills(), [
        R.selection.bg,
        Colors.transparent,
        Colors.transparent,
        Colors.transparent,
        Colors.transparent,
      ]);
    });

    testWidgets('GoSelectChip·GoCheckbox: 누르면 면이 가라앉는다', (tester) async {
      await tester
          .pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        GoSelectChip(label: '5km', selected: false, onTap: () {}),
        SizedBox(
          width: 300,
          child: GoCheckbox(
              value: true, onChanged: (_) {}, label: const Text('동의')),
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
      await tester
          .pumpWidget(host(GoIconButton(icon: Icons.search, onTap: () {})));
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

  /// 그룹 행은 화면 어디에나 있고, 안에 든 글자 크기에 따라 높이가 정해진다.
  /// 작은 글자 한 줄만 든 행이 조용히 44pt를 밑돌던 자리다(2026-09-08)
  group('GoGroupRow', () {
    testWidgets('12pt 한 줄짜리 눌리는 행도 44pt 아래로 내려가지 않는다', (tester) async {
      await tester.pumpWidget(host(SizedBox(
        width: 320,
        child: GoGroupRow(
          onTap: () {},
          child: const Text('차단 해제', style: TextStyle(fontSize: 12)),
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GoGroupRow)).height,
          greaterThanOrEqualTo(44));
    });

    testWidgets('누를 수 없는 행에는 최소 높이를 강요하지 않는다 — 표적이 아니다', (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 320,
        child: GoGroupRow(
          padding: EdgeInsets.zero,
          child: Text('읽기만', style: TextStyle(fontSize: 12)),
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GoGroupRow)).height, lessThan(44));
    });
  });
}
