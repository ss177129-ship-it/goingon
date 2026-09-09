import 'package:flutter/material.dart';

import '../services/pacemate_status.dart';
import '../services/story_labels.dart';
import '../theme.dart';
import 'go_avatar.dart';
import 'go_button.dart';

/// 페이스메이트 상세 — 홈 카드를 누르면 열린다.
///
/// **progressive disclosure의 두 번째 단계.** 홈 카드는 지금 부를지 말지를
/// 정하는 데 필요한 최소한(이름·상태 한 줄·GO?)만 보여주고, 더 알고 싶은
/// 사람만 여기까지 온다. 홈에 다 늘어놓으면 목록이 아니라 벽이 된다.
///
/// **여기 있는 숫자는 전부 이미 있는 필드다.** 러닝 성향·습관 같은 것은
/// 수집하지도 저장하지도 않으므로 만들어 넣지 않는다. 나와 함께 달린
/// 기록만 [togetherFuture]로 뒤늦게 채워지는데, 그동안 자리를 비워 두지
/// 않고 '—'를 세워 둔다 — 숫자가 0으로 보였다가 바뀌면 거짓말이 된다.
///
/// 차단·연결 끊기가 여기 있다. App Store 가이드라인 1.2가 요구하는 수단이라
/// 화면에서 닿을 수 있어야 하고, 홈 카드 한 번이면 도착한다
Future<void> showFriendProfileSheet(
  BuildContext context, {
  required Map<String, dynamic> user,
  required String name,
  required String myUid,
  required Future<List<Map<String, dynamic>>> togetherFuture,
  required VoidCallback onGo,
  required VoidCallback onDisconnect,
  required VoidCallback onBlock,
}) {
  final roles = GoRoles.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: roles.surfaceHigh,
    // 내용이 화면보다 길어질 수 있다(작은 기기·큰 글자 설정). 기본 시트는
    // 넘치는 만큼 그냥 잘려서 맨 아래 버튼에 닿을 수 없게 된다
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _FriendProfileSheet(
      user: user,
      name: name,
      myUid: myUid,
      togetherFuture: togetherFuture,
      onGo: onGo,
      onDisconnect: onDisconnect,
      onBlock: onBlock,
    ),
  );
}

class _FriendProfileSheet extends StatelessWidget {
  const _FriendProfileSheet({
    required this.user,
    required this.name,
    required this.myUid,
    required this.togetherFuture,
    required this.onGo,
    required this.onDisconnect,
    required this.onBlock,
  });

  final Map<String, dynamic> user;
  final String name;
  final String myUid;
  final Future<List<Map<String, dynamic>>> togetherFuture;
  final VoidCallback onGo;
  final VoidCallback onDisconnect;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final username = (user['username'] as String?) ?? '';
    final status = PacemateStatus.of(user, DateTime.now());
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // 화면을 다 덮지는 않는다 — 뒤가 보여야 "위에 열린 것"으로 읽힌다
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .88),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                GoSpace.sheet, GoSpace.xl, GoSpace.sheet, GoSpace.sheetBottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GoAvatar(size: 76, photoUrl: user['photoUrl'] as String?),
              const SizedBox(height: 12),
              Text(name, style: GoText.heading),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('@$username',
                    style: TextStyle(fontSize: 12, color: roles.textSecondary)),
              ],
              const SizedBox(height: 6),
              Text(status.label,
                  style: TextStyle(
                      fontSize: 12,
                      color: status.tone == PacemateTone.active
                          ? roles.success.fg
                          : roles.textSecondary)),
              const SizedBox(height: GoSpace.xl),
              _theirRuns(context),
              const SizedBox(height: GoSpace.m),
              _together(context),
              const SizedBox(height: GoSpace.xl),
              SizedBox(
                width: double.infinity,
                child: GoButton('함께 달리기',
                    kind: GoButtonKind.primary,
                    size: GoButtonSize.lg, onTap: () {
                  Navigator.pop(context);
                  onGo();
                }),
              ),
              const SizedBox(height: GoSpace.m),
              // 파괴적 행동은 주 행동과 같은 무게로 놓지 않는다 — 글자 버튼으로,
              // 차단만 error 색
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                GoButton('연결 끊기',
                    kind: GoButtonKind.text, size: GoButtonSize.md, onTap: () {
                  Navigator.pop(context);
                  onDisconnect();
                }),
                Text('·', style: TextStyle(color: roles.textDisabled)),
                GoButton('차단하기',
                    kind: GoButtonKind.text,
                    size: GoButtonSize.md,
                    destructive: true, onTap: () {
                  Navigator.pop(context);
                  onBlock();
                }),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  /// 상대의 러닝 — `users` 문서에 이미 있는 값만
  Widget _theirRuns(BuildContext context) {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthKm = user['monthKey'] == monthKey
        ? ((user['monthKm'] ?? 0) as num).toDouble()
        : 0.0;
    final totalRuns = ((user['totalRuns'] ?? 0) as num).toInt();
    // totalKm은 나중에 생긴 필드라 옛 계정에는 아예 없다. 없는 것을 0으로
    // 단정하면 3번 달린 사람이 '0km 지금까지'가 된다 — 모르면 모른다고 한다
    final totalKm = (user['totalKm'] as num?)?.toDouble();
    final streak = ((user['weekStreak'] ?? 0) as num).toInt();
    // 끊긴 연속은 숫자가 남아 있어도 사실이 아니다. 살아 있을 때만 자리를
    // 내주고, 아니면 절대 낡지 않는 값(누적 거리)을 대신 세운다
    final alive = PacemateStatus.streakAlive(user, now);
    return _panel(context, '$name님의 러닝', [
      _metric(context, monthKm.toStringAsFixed(1), 'km', '이번 달'),
      _metric(context, '$totalRuns', '', '함께 달림'),
      alive
          ? _metric(context, '$streak', '주', '연속')
          : _metric(context, totalKm == null ? '—' : totalKm.toStringAsFixed(0),
              totalKm == null ? '' : 'km', '지금까지'),
    ]);
  }

  /// 나와 함께 — 세션을 읽어야 나오므로 [FutureBuilder]
  Widget _together(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: togetherFuture,
      builder: (context, snap) {
        // 아직 모르는 값을 0으로 보여주면, 함께 달린 적 있는 사람에게
        // 잠깐 "우린 한 번도 안 뛰었다"고 말하는 셈이 된다
        final sessions = snap.data;
        final partnerUid = user['uid'] as String;
        final count = sessions?.length;
        final km = sessions?.fold<double>(
            0, (sum, s) => sum + combinedKm(s, myUid, partnerUid));
        return _panel(context, '함께한 기록', [
          _metric(context, count == null ? '—' : '$count', '', '함께 달린 횟수'),
          _metric(context, km == null ? '—' : km.toStringAsFixed(1), 'km',
              '함께한 거리'),
        ]);
      },
    );
  }

  Widget _panel(BuildContext context, String title, List<Widget> metrics) {
    final roles = GoRoles.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        // 시트(5층) 안에 놓이는 면이라 그림자를 또 얹지 않는다 —
        // 떠 있는 것 위에 뜬 것은 깊이가 아니라 소음이다
        color: roles.background,
        borderRadius: BorderRadius.circular(GoRadius.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoText.label),
        const SizedBox(height: 10),
        Row(children: metrics),
      ]),
    );
  }

  Widget _metric(BuildContext context, String v, String unit, String label) {
    final roles = GoRoles.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: v, style: GoTheme.serif(19)),
          TextSpan(
              text: unit,
              style: TextStyle(fontSize: 12, color: roles.textSecondary)),
        ])),
        const SizedBox(height: 2),
        Text(label, style: GoText.label),
      ]),
    );
  }
}
