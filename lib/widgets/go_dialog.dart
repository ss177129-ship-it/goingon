import 'package:flutter/material.dart';

import '../theme.dart';
import 'go_button.dart';

/// 앱 전역에서 쓰는 다이얼로그 뼈대 — paper 배경, radius 18, serif 타이틀.
class GoDialog {
  /// 그림자 색은 [GoShadow]의 것을 그대로 따른다(불투명하게). 역할 토큰에
  /// 그림자 색이 따로 없고, 팔레트를 직접 참조하지 않기 위해 여기서 꺼낸다
  static final _shadow = GoShadow.overlay.first.color.withValues(alpha: 1);

  /// 확인/취소 두 버튼. body가 없으면 타이틀만 보여줌.
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    String? body,
    required String confirmLabel,
    String cancelLabel = '취소',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // 다이얼로그는 페이지 위로 떠오른 것 — 배경과 같은 페이퍼색이면
        // 어디까지가 다이얼로그인지 경계가 사라진다
        backgroundColor: GoRoles.of(ctx).surfaceHigh,
        elevation: 12,
        shadowColor: _shadow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GoRadius.lg)),
        title: Text(title, style: GoText.heading),
        content: body == null
            ? null
            : Text(body,
                style: TextStyle(
                    fontSize: 13,
                    color: GoRoles.of(ctx).textSecondary,
                    height: 1.5)),
        // 한 줄에 나란히. 기본 actions는 폭이 모자라면 세로로 쌓는데,
        // 그러면 취소만 가운데 뜬 채 확인 버튼이 그 밑에 붙어 두 버튼이
        // 서로 다른 종류의 것처럼 보인다
        actionsPadding:
            const EdgeInsets.fromLTRB(GoSpace.xl, 0, GoSpace.xl, GoSpace.xl),
        actions: [
          Row(children: [
            Expanded(
              child: GoButton(cancelLabel,
                  kind: GoButtonKind.secondary,
                  size: GoButtonSize.md,
                  onTap: () => Navigator.pop(ctx, false)),
            ),
            const SizedBox(width: GoSpace.m),
            Expanded(
              // destructive는 primary 대신 secondary + coralDark 글자
              child: GoButton(confirmLabel,
                  kind:
                      destructive ? GoButtonKind.secondary : GoButtonKind.primary,
                  size: GoButtonSize.md,
                  destructive: destructive,
                  onTap: () => Navigator.pop(ctx, true)),
            ),
          ]),
        ],
      ),
    );
  }

  /// 안내 문구 + 확인 버튼 하나짜리 다이얼로그. 바깥을 눌러도 닫히지 않음.
  static Future<void> notice(
    BuildContext context, {
    required String title,
    required String body,
    String actionLabel = '알겠어요',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        // 다이얼로그는 페이지 위로 떠오른 것 — 배경과 같은 페이퍼색이면
        // 어디까지가 다이얼로그인지 경계가 사라진다
        backgroundColor: GoRoles.of(ctx).surfaceHigh,
        elevation: 12,
        shadowColor: _shadow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GoRadius.lg)),
        title: Text(title, style: GoText.heading),
        content: Text(body,
            style: TextStyle(
                fontSize: 15,
                color: GoRoles.of(ctx).textPrimary,
                height: 1.5)),
        actionsPadding:
            const EdgeInsets.fromLTRB(GoSpace.xl, 0, GoSpace.xl, GoSpace.xl),
        actions: [
          Row(children: [
            Expanded(
              child: GoButton(actionLabel,
                  size: GoButtonSize.md, onTap: () => Navigator.pop(ctx)),
            ),
          ]),
        ],
      ),
    );
  }
}
