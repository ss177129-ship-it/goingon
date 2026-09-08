import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/widgets/pressable.dart';

/// 눌림 반응 — "눌렀다"는 감각은 화면이 아니라 앱의 성질이라 한 곳에 모았다.
///
/// 스크린샷으로는 증명이 안 되는 종류의 규격이다(손가락이 닿아 있는 동안에만
/// 보인다). 그래서 여기서 잡는다.
void main() {
  /// [child]를 Pressable로 감싼 최소 화면
  Widget host({VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: onTap ?? () {},
              child: const SizedBox(width: 120, height: 48),
            ),
          ),
        ),
      );

  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('손가락이 닿는 즉시 0.97로 줄어든다', (tester) async {
    await tester.pumpWidget(host());
    expect(scaleOf(tester), 1.0);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump(); // 프레임 하나 — 지연 없이 바로 눌린 상태여야 한다
    expect(scaleOf(tester), 0.97);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('누르는 애니메이션에는 지연이 없다', (tester) async {
    // 눌릴 때 시간을 주면 빠른 탭에서 아무 일도 안 일어난 것처럼 보인다.
    // 돌아올 때만 시간을 준다
    await tester.pumpWidget(host());
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump();
    final pressed = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(pressed.duration, Duration.zero);

    await gesture.up();
    await tester.pump();
    final released = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(released.duration, Pressable.releaseDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('닿는 순간 selectionClick 햅틱이 간다', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String? ?? '');
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(host());
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump();

    expect(calls, ['HapticFeedbackType.selectionClick'],
        reason: '실행이 아니라 "받았다"는 뜻이라 가장 가벼운 것으로');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('손가락을 밖으로 끌어 취소하면 되돌아온다', (tester) async {
    await tester.pumpWidget(host());
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump();
    expect(scaleOf(tester), 0.97);

    await gesture.moveBy(const Offset(0, 400)); // 버튼 밖으로
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('콜백이 없으면 눌린 척하지 않는다', (tester) async {
    // 반응만 하고 아무 일도 안 일어나는 버튼이 신뢰를 깎는다
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Pressable(child: SizedBox(width: 120, height: 48)),
        ),
      ),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump();
    expect(scaleOf(tester), 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  group('minTarget — 보이는 크기는 그대로, 닿는 자리만', () {
    Widget hostSmall({Size? minTarget}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pressable(
                onTap: () {},
                minTarget: minTarget,
                child: const SizedBox(width: 20, height: 12),
              ),
            ),
          ),
        );

    testWidgets('주지 않으면 자식 크기 그대로 — 20×12짜리 표적이 그대로 남는다', (tester) async {
      await tester.pumpWidget(hostSmall());
      expect(tester.getSize(find.byType(Pressable)), const Size(20, 12));
    });

    testWidgets('주면 최소치까지 벌어지되, 안쪽 자식은 크기가 그대로다', (tester) async {
      await tester.pumpWidget(hostSmall(minTarget: Pressable.minSize));
      expect(tester.getSize(find.byType(Pressable)), const Size(44, 44));
      // 자식은 커지지 않는다 — 커졌다면 그림이 달라진 것이지 표적만 넓힌 게
      // 아니다
      expect(tester.getSize(find.byType(SizedBox).first), const Size(20, 12));
    });

    testWidgets('자식이 최소치보다 크면 자식이 이긴다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () {},
              minTarget: Pressable.minSize,
              child: const SizedBox(width: 120, height: 60),
            ),
          ),
        ),
      ));
      expect(tester.getSize(find.byType(Pressable)), const Size(120, 60));
    });

    testWidgets('넓어진 빈자리도 탭을 받는다 — 그러라고 넓힌 것이다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () => taps++,
              minTarget: Pressable.minSize,
              child: const SizedBox(width: 20, height: 12),
            ),
          ),
        ),
      ));
      // 자식 밖(가운데에서 18pt 위)이지만 44pt 표적 안이다
      final center = tester.getCenter(find.byType(Pressable));
      await tester.tapAt(center + const Offset(0, -18));
      expect(taps, 1);
    });
  });
}
