import 'package:flutter/material.dart';

import '../theme.dart';

/// 짧은 안내 메시지.
///
/// 예전엔 Material 기본 SnackBar를 35곳에서 직접 띄웠는데, 화면 밑에 붙는
/// 각진 검은 막대는 안드로이드 관용구라 iOS에서 이 앱의 종이 질감과 따로 놀았고
/// 하단 네비게이션·홈 인디케이터와도 겹쳤다. 여기 한 곳으로 모아뒀으니
/// 나중에 상단 배너 같은 다른 형태로 바꿔도 호출부는 손댈 필요가 없다.
class GoToast {
  const GoToast._();

  /// 일반 안내
  static void show(BuildContext context, String message) =>
      _show(context, message, isError: false);

  /// 실패 안내 — 색으로 구분하되 요란하지 않게
  static void error(BuildContext context, String message) =>
      _show(context, message, isError: true);

  static void _show(BuildContext context, String message,
      {required bool isError}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar() // 연달아 뜰 때 줄 서지 않고 최신 것만 보이게
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: isError ? GoColors.coralDark : GoColors.limeDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: GoColors.ink),
            ),
          ),
        ]),
        backgroundColor: GoColors.paper,
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        duration: Duration(seconds: isError ? 4 : 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isError
                ? GoColors.coral.withOpacity(.35)
                : GoColors.line,
            width: 1.5,
          ),
        ),
      ));
  }
}
