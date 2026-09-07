import 'package:flutter/material.dart';

import '../theme.dart';
import 'go_button.dart';

/// 앱 전역에서 쓰는 다이얼로그 뼈대 — paper 배경, radius 18, serif 타이틀.
class GoDialog {
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
        backgroundColor: GoColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: GoText.heading),
        content: body == null
            ? null
            : Text(body,
                style: const TextStyle(
                    fontSize: 13, color: GoColors.mid, height: 1.5)),
        actions: [
          GoButton(cancelLabel,
              kind: GoButtonKind.text,
              size: GoButtonSize.md,
              onTap: () => Navigator.pop(ctx, false)),
          // destructive는 primary 대신 secondary + coralDark 글자
          GoButton(confirmLabel,
              kind: destructive ? GoButtonKind.secondary : GoButtonKind.primary,
              size: GoButtonSize.md,
              destructive: destructive,
              onTap: () => Navigator.pop(ctx, true)),
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
        backgroundColor: GoColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: GoText.heading),
        content: Text(body,
            style: const TextStyle(
                fontSize: 15, color: GoColors.ink, height: 1.5)),
        actions: [
          GoButton(actionLabel,
              size: GoButtonSize.md, onTap: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }
}
