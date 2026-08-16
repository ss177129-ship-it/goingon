import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/cadence_service.dart';

/// 케이던스 값의 타당성 판정.
///
/// 만보기는 가끔 사람이 낼 수 없는 값을 낸다(주머니 속 흔들림, 계단을
/// 뛰어내릴 때). 그 값이 그대로 공명 계산에 들어가면 **있지도 않은 순간에
/// 공명이 터진다.** 소리와 진동까지 따라오므로 조용히 틀리지 않는다.
void main() {
  test('달리기 범위는 통과', () {
    expect(CadenceService.isPlausible(150), isTrue); // 조깅
    expect(CadenceService.isPlausible(180), isTrue); // 흔히 권장되는 리듬
    expect(CadenceService.isPlausible(200), isTrue); // 빠른 러닝
  });

  test('달리기로 보기 어려운 값은 버린다', () {
    expect(CadenceService.isPlausible(0), isFalse);
    expect(CadenceService.isPlausible(60), isFalse); // 걷기 이하
    expect(CadenceService.isPlausible(99), isFalse);
  });

  test('사람이 낼 수 없는 값도 버린다', () {
    // 세계 기록권 스프린터도 250을 넘지 않는다
    expect(CadenceService.isPlausible(300), isFalse);
    expect(CadenceService.isPlausible(1000), isFalse);
  });

  test('경계값', () {
    expect(CadenceService.isPlausible(100), isTrue);
    expect(CadenceService.isPlausible(250), isTrue);
  });
}
