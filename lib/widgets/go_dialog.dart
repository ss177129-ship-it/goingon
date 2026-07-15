import 'package:flutter/material.dart';

import '../theme.dart';

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
        title: Text(title, style: GoTheme.serif(20)),
        content: body == null
            ? null
            : Text(body,
                style: const TextStyle(
                    fontSize: 13, color: GoColors.mid, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(cancelLabel, style: const TextStyle(color: GoColors.mid)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: destructive ? GoColors.coralDark : GoColors.ink),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: GoTheme.serif(15, color: GoColors.paper)),
          ),
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
        title: Text(title, style: GoTheme.serif(20)),
        content: Text(body,
            style: const TextStyle(
                fontSize: 15, color: GoColors.ink, height: 1.5)),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GoColors.ink),
            onPressed: () => Navigator.pop(ctx),
            child: Text(actionLabel,
                style: GoTheme.serif(15, color: GoColors.paper)),
          ),
        ],
      ),
    );
  }
}
