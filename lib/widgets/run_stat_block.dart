import 'package:flutter/material.dart';

import '../theme.dart';

/// 글자 삼색 묶음 — 밝은 바탕과 어두운 바탕에서 같은 위젯을 쓰기 위한 것.
///
/// 러닝 화면만 잉크로 내려앉으므로, 여기서만 [GoRoles]를 벗어난다.
/// null이면 평소대로 역할 토큰을 쓴다
class RunTextTone {
  const RunTextTone({
    required this.primary,
    required this.secondary,
    required this.disabled,
    this.shadows = const [],
  });

  final Color primary;
  final Color secondary;
  final Color disabled;

  /// 배경 위에서 글자를 떼어내는 그림자. 밝은 종이 위에서는 비워 둔다 —
  /// 흐르는 도시 위에서는 숫자와 불빛이 같은 밝기로 겹치는 자리가 반드시 생긴다
  final List<Shadow> shadows;
}

/// 러닝 화면의 한 진영 — 나 또는 상대.
///
/// **두 진영이 같은 위젯을 쓰는 것이 이 파일의 전부다.** 페이스는 페이스끼리,
/// km은 km끼리 같은 x좌표에 와야 한 번의 수직 시선으로 둘이 동시에 읽힌다.
/// 좌우 패딩과 열 구조가 한 곳에만 있으면 그 정렬은 저절로 지켜지고,
/// 두 곳에 나눠 적으면 언젠가 조용히 어긋난다.
///
/// 크기만 다르다 — 대칭이되 주인은 나다. 상대 46 / 나 64는 그 위계다.
class RunStatBlock extends StatelessWidget {
  const RunStatBlock({
    super.key,
    required this.name,
    required this.color,
    required this.pace,
    required this.km,
    required this.paceLabel,
    this.paceSize = 46,
    this.kmSize = 36,
    this.footnote,
    this.stale = false,
    this.staleNote,
    this.tone,
  });

  /// 진영 이름 — '나' 또는 상대 닉네임
  final String name;

  /// 관계색. 나는 [GoRoles.self], 상대는 [GoRoles.partner]
  final Color color;

  final String pace;
  final String km;

  /// 페이스 아래 꼬리표. 나는 '지금 페이스', 상대는 '페이스'
  final String paceLabel;

  final double paceSize;
  final double kmSize;

  /// 블록 아래 보조 한 줄 (평균 페이스와 차이 등). 없으면 자리도 안 먹는다
  final Widget? footnote;

  /// 상대의 신호가 낡았을 때.
  ///
  /// **값은 남고 색만 빠진다.** 사라지면 상대가 없어지고, 흐려지면 상대가
  /// 멀어진다. Opacity를 겹쳐 쓰지 않는 이유도 그것이다 — 이미 중성색으로
  /// 떨어진 위에 투명도까지 걸면 '멀어짐'이 아니라 '없어짐'으로 읽힌다
  final bool stale;

  /// 얼마나 낡았는지 ('14초 전'). [stale]일 때만 쓰인다
  final String? staleNote;

  /// 어두운 바탕에서 쓸 글자색. null이면 [GoRoles]
  final RunTextTone? tone;

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final t = tone ??
        RunTextTone(
          primary: roles.textPrimary,
          secondary: roles.textSecondary,
          disabled: roles.textDisabled,
        );
    final valueColor = stale ? t.disabled : color;
    final kmColor = stale ? t.disabled : t.primary;
    final captionColor = stale ? t.disabled : t.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stale ? t.disabled : color,
            ),
          ),
          const SizedBox(width: 7),
          // 닉네임은 길이를 모른다 — 줄이 넘치면 노란 줄무늬가 뜬다
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _label(valueColor, t.shadows),
            ),
          ),
          if (stale && staleNote != null) ...[
            const SizedBox(width: 6),
            Text('· $staleNote',
                maxLines: 1,
                style: _label(t.disabled, t.shadows)
                    .copyWith(fontWeight: FontWeight.w500, letterSpacing: .4)),
          ],
        ]),
        const SizedBox(height: 5),
        // 두 열은 반드시 같은 비율이어야 한다 — Expanded 둘로 고정한다
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
                child: _cell(pace, paceLabel, paceSize, valueColor,
                    captionColor, t.shadows)),
            Expanded(
                child: _cell(
                    km, 'KM', kmSize, kmColor, captionColor, t.shadows)),
          ],
        ),
        if (footnote != null) ...[
          const SizedBox(height: 7),
          footnote!,
        ],
      ],
    );
  }

  Widget _cell(String value, String caption, double size, Color c,
      Color captionColor, List<Shadow> shadows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // **줄바꿈을 절대 허용하지 않는다.** 열 폭은 화면의 절반이고
        // 64pt 세리프로 `--'--"`를 그리면 그보다 넓어진다. 기본값대로 감기면
        // 블록이 한 줄만큼 자라고, 그 높이는 가운데 캔버스에서 그대로 빠진다.
        // 넘칠 때는 감는 대신 줄여서 자리를 지킨다
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: GoTheme.serif(size, color: c)
                .copyWith(height: 1.0, shadows: shadows),
          ),
        ),
        const SizedBox(height: 4),
        Text(caption, maxLines: 1, style: _label(captionColor, shadows)),
      ],
    );
  }

  /// 이 화면에서 34px 미만이 허용되는 유일한 글자 — 값이 무엇인지 알려주는 꼬리표
  static TextStyle _label(Color c, [List<Shadow> shadows = const []]) =>
      TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: c,
        shadows: shadows,
      );
}

/// '평균 5'24" · 22초 빠름' 한 줄.
///
/// 현재 페이스만 있으면 빠른 건지 느린 건지 알 수 없다. 기준점이 옆에 있어야
/// 숫자가 뜻을 갖는다.
///
/// **말로 쓰는 이유:** 페이스는 숫자가 작을수록 빠른 역수 단위라 화살표나
/// 부호로는 늘 헷갈린다. 그리고 느릴 때 빨강을 쓰지 않는다 — 느린 것은
/// 실패가 아니다. 색이 빠질 뿐이다.
class PaceFootnote extends StatelessWidget {
  const PaceFootnote({
    super.key,
    required this.averagePace,
    required this.deltaSeconds,
    required this.fasterThanAverage,
    required this.fastColor,
    this.tone,
  });

  final String averagePace;

  /// 평균과의 차이(초). null이면 비교할 만큼 달리지 않았거나 차이가 노이즈 수준
  final int? deltaSeconds;
  final bool fasterThanAverage;
  final Color fastColor;

  /// 어두운 바탕에서 쓸 글자색
  final RunTextTone? tone;

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final t = tone ??
        RunTextTone(
          primary: roles.textPrimary,
          secondary: roles.textSecondary,
          disabled: roles.textDisabled,
        );
    final base = TextStyle(
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w500,
      letterSpacing: .8,
      color: t.secondary,
      shadows: t.shadows,
    );
    final d = deltaSeconds;
    return Row(children: [
      Text('평균 $averagePace', style: base, maxLines: 1),
      if (d != null) ...[
        const SizedBox(width: 8),
        Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: t.secondary),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$d초 ${fasterThanAverage ? '빠름' : '느림'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(
              fontWeight: FontWeight.w700,
              color: fasterThanAverage ? fastColor : t.secondary,
            ),
          ),
        ),
      ],
    ]);
  }
}
