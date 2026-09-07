import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/run_service.dart';
import '../services/story_labels.dart';
import '../theme.dart';
import '../widgets/go_button.dart';
import '../widgets/friend_search_sheet.dart';
import '../widgets/initial_avatar.dart';

const _kDistanceMilestones = [50, 100, 300, 500, 1000, 2000, 3000, 5000];
const _kWeekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// '우리' 탭 — 프로토타입 s-us. 등록된 친구(사실상 1:1)와 함께 쌓은
/// 여정을 Firestore sessions(status=finished) 실데이터로 구성.
class UsScreen extends StatefulWidget {
  const UsScreen({super.key});

  @override
  State<UsScreen> createState() => _UsScreenState();
}

class _UsScreenState extends State<UsScreen> {
  final _auth = AuthService();
  final _friends = FriendService();
  final _runs = RunService();

  String? _cachedPartnerUid;
  Future<List<Map<String, dynamic>>>? _sessionsFuture;
  List<Map<String, dynamic>>? _lastSessions;

  /// 상단 짝 아바타의 '나' 쪽에 쓸 내 프로필 사진. 내 문서는 친구 스트림에
  /// 안 들어오므로 한 번만 따로 읽음 — 실패해도 첫 글자 아바타로 그려지니
  /// 조용히 넘어감
  String? _myPhotoUrl;

  @override
  void initState() {
    super.initState();
    _auth.myProfile().then((me) {
      if (!mounted) return;
      final url = me?['photoUrl'];
      if (url is String && url.isNotEmpty) setState(() => _myPhotoUrl = url);
    }).catchError((_) {});
  }

  void _reloadSessions(String partnerUid) {
    setState(() {
      _sessionsFuture = _runs.finishedSessionsWith(_auth.uid, partnerUid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _friends.friendsStream(_auth.uid),
      builder: (context, friendSnap) {
        if (friendSnap.hasError) return _errorState(() => setState(() {}));
        final friends = friendSnap.data;
        if (friends == null) return const SizedBox.shrink();
        if (friends.isEmpty) return _noFriendYet();

        final partner = friends.first;
        final partnerUid = partner['uid'] as String;
        // 스트림이 재발화될 때마다 future를 새로 만들면 매번 재조회+깜빡임이
        // 생기므로, 상대가 바뀔 때만(또는 최초 1회) 새로 불러오도록 캐싱
        if (_cachedPartnerUid != partnerUid) {
          _cachedPartnerUid = partnerUid;
          _sessionsFuture = _runs.finishedSessionsWith(_auth.uid, partnerUid);
          _lastSessions = null;
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _sessionsFuture,
          builder: (context, sessionSnap) {
            if (sessionSnap.hasError) {
              return _errorState(() => _reloadSessions(partnerUid));
            }
            if (sessionSnap.hasData) _lastSessions = sessionSnap.data;
            // 재조회 중에도 이전 데이터를 유지해 깜빡이지 않게 함 —
            // 빈 화면은 최초 로딩일 때만 보여줌
            final sessions = _lastSessions;
            if (sessions == null) return const SizedBox.shrink();
            if (sessions.isEmpty) return _notRunTogetherYet(partner);
            return _journey(partner, sessions);
          },
        );
      },
    );
  }

  // ── 데이터 계산 ── (session/story 순수 계산은 services/story_labels.dart로 분리)

  String? _moodField(Map<String, dynamic> session, String uid) {
    final results = session['results'];
    if (results is! Map) return null;
    final r = results[uid];
    if (r is! Map) return null;
    final v = r['mood'];
    return v is String ? v : null;
  }

  DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  // ── 화면 ──

  /// 데이터를 불러오지 못했을 때 — 조용히 빈 화면 대신 다시 시도할 수 있게
  Widget _errorState(VoidCallback onRetry) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('우리의 여정', style: GoText.label),
        ),
      ),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: GoColors.line, width: GoStroke.accent),
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    size: 28, color: GoColors.mid),
              ),
              const SizedBox(height: 18),
              Text('불러오지 못했어요',
                  textAlign: TextAlign.center, style: GoText.heading),
              const SizedBox(height: 8),
              const Text('네트워크 상태를 확인하고 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const SizedBox(height: 22),
              GoButton('다시 시도', kind: GoButtonKind.secondary, onTap: onRetry),
            ]),
          ),
        ),
      ),
    ]);
  }

  /// 친구가 아예 없을 때
  Widget _noFriendYet() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('우리의 여정', style: GoText.label),
        ),
      ),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: GoColors.coralDark, width: GoStroke.accent),
                ),
                child: const Icon(Icons.people_alt_outlined,
                    size: 30, color: GoColors.coralDark),
              ),
              const SizedBox(height: 18),
              Text('아직 함께 뛰는 사람이 없어요',
                  textAlign: TextAlign.center, style: GoText.heading),
              const SizedBox(height: 8),
              const Text('아이디로 페이스메이트를 찾으면, 둘만의 여정이 시작돼요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const SizedBox(height: 22),
              GoButton('페이스메이트 찾기',
                  onTap: () => showFriendSearchSheet(context)),
            ]),
          ),
        ),
      ),
    ]);
  }

  /// 친구는 있지만 함께 달린 세션이 아직 없을 때
  Widget _notRunTogetherYet(Map<String, dynamic> partner) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('우리의 여정', style: GoText.label),
        ),
      ),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: GoColors.limeDark, width: GoStroke.accent),
                ),
                child: const Icon(Icons.directions_run,
                    size: 30, color: GoColors.limeDark),
              ),
              const SizedBox(height: 18),
              Text('${partner['name']}님과\n아직 함께 달리지 않았어요',
                  textAlign: TextAlign.center, style: GoText.heading),
              const SizedBox(height: 8),
              const Text('한 번만 같이 뛰면, 여기에 우리 기록이 쌓여요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const SizedBox(height: 22),
              GoButton('GO? 보내러 홈으로', onTap: () => Navigator.pop(context)),
            ]),
          ),
        ),
      ),
    ]);
  }

  /// 실제 데이터가 있는 본 화면
  Widget _journey(
      Map<String, dynamic> partner, List<Map<String, dynamic>> sessions) {
    final me = _auth.uid;
    final partnerUid = partner['uid'] as String;
    final partnerName = partner['name'] as String;

    final totalKm = sessions.fold<double>(
        0, (sum, s) => sum + combinedKm(s, me, partnerUid));
    final count = sessions.length;

    final ascending = sessions.reversed.toList();
    final storyLabels = storyLabelsFor(ascending, me, partnerUid);
    final firstStarted = sessionStartedAt(ascending.first);
    final daysTogether =
        firstStarted == null ? 0 : DateTime.now().difference(firstStarted).inDays;

    // 주간 스트릭
    final weeks = sessions
        .map(sessionStartedAt)
        .whereType<DateTime>()
        .map(_mondayOf)
        .toSet();
    final thisMonday = _mondayOf(DateTime.now());
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    DateTime? cursor =
        weeks.contains(thisMonday) ? thisMonday : (weeks.contains(lastMonday) ? lastMonday : null);
    int streak = 0;
    while (cursor != null && weeks.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }

    // 이번 주 요일별 완료 여부
    final daysDone = sessions
        .map(sessionStartedAt)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    final today = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);

    // 거리 마일스톤
    final achieved =
        _kDistanceMilestones.where((t) => totalKm >= t).toList();
    final nextThreshold = _kDistanceMilestones
        .firstWhere((t) => totalKm < t, orElse: () => -1);
    int? achievedDaysAgo;
    if (achieved.isNotEmpty) {
      final threshold = achieved.last;
      double running = 0;
      for (final s in ascending) {
        running += combinedKm(s, me, partnerUid);
        if (running >= threshold) {
          final at = sessionStartedAt(s);
          if (at != null) {
            achievedDaysAgo = DateTime.now().difference(at).inDays;
          }
          break;
        }
      }
    }

    return ListView(padding: EdgeInsets.zero, children: [
      // ── 헤더 ──
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        child: Text('우리의 여정', style: GoText.label),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
        child: Text('나 & $partnerName', style: GoText.title),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: Row(children: [
          _pairAvatar(_avatarLetter(null), GoColors.limeDark,
              photoUrl: _myPhotoUrl),
          _pairAvatar(_avatarLetter(partnerName), GoColors.coralDark,
              overlap: true, photoUrl: partner['photoUrl'] as String?),
          const SizedBox(width: 8),
          Expanded(
            child: Text('함께 달린 지 $daysTogether일째',
                style: const TextStyle(fontSize: 12, color: GoColors.mid)),
          ),
        ]),
      ),
      // ── 합산 거리 카드 ──
      Container(
        margin: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        padding: const EdgeInsets.all(GoSpace.hero),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [GoColors.ink, Color(0xFF2A2A22)],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('멀리 있어도, 함께',
              style: GoText.label.copyWith(color: GoColors.paper)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              Container(width: 13, height: 13,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: GoColors.lime)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                        colors: [GoColors.lime, GoColors.coral]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 13, height: 13,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: GoColors.coral)),
            ]),
          ),
          Center(
            child: Text('$partnerName님과 함께',
                style: TextStyle(
                    fontSize: 11, color: GoColors.paper.withValues(alpha: .5))),
          ),
          const SizedBox(height: 14),
          // 한글은 산세리프, 숫자만 세리프 이탤릭
          Text.rich(TextSpan(children: [
            const TextSpan(text: '함께 달린 '),
            TextSpan(
                text: '${totalKm.toStringAsFixed(1)}km',
                style: GoTheme.serif(26, color: GoColors.lime)),
            const TextSpan(text: '를\n만들었어요.'),
          ]), style: const TextStyle(
              fontSize: 23, fontWeight: FontWeight.w700, color: GoColors.paper)),
        ]),
      ),
      // ── 스트릭 ──
      Container(
        margin: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: GoColors.amberDark, width: GoStroke.accent),
          borderRadius: BorderRadius.circular(GoRadius.md),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.local_fire_department,
                size: 24, color: GoColors.amber),
            const SizedBox(width: 6),
            Text('$streak', style: GoTheme.serif(30, color: GoColors.amber)),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('주째 함께',
                  style: TextStyle(fontSize: 12, color: GoColors.mid)),
            ),
          ]),
          const SizedBox(height: GoSpace.m),
          Row(children: List.generate(7, (i) {
            final day = thisMonday.add(Duration(days: i));
            final done = daysDone.contains(day);
            final isToday = day == today;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == 6 ? 0 : 5),
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? GoColors.amber : Colors.white,
                  borderRadius: BorderRadius.circular(GoRadius.sm),
                  border: isToday && !done
                      ? Border.all(color: GoColors.limeDark, width: GoStroke.accent)
                      : Border.all(color: GoColors.line, width: GoStroke.card),
                ),
                child: Text(_kWeekdayLabels[i],
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: done ? GoColors.ink : GoColors.mid)),
              ),
            );
          })),
          if (!daysDone.contains(today)) ...[
            const SizedBox(height: GoSpace.gutter),
            // 틴트 대신 왼쪽 세로 바(4px)로 "다른 카드"를 말한다
            ClipRRect(
              borderRadius: BorderRadius.circular(GoRadius.sm),
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: IntrinsicHeight(
                  child: Row(children: [
                    Container(width: 4, color: GoColors.limeDark),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Text(
                            '이번 주는 아직 함께 달리지 않았어요. 지금 GO?를 보내볼까요?',
                            style: TextStyle(fontSize: 11, color: GoColors.limeDark,
                                height: 1.5)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GoButton('GO? 보내러 홈으로', onTap: () => Navigator.pop(context)),
          ],
        ]),
      ),
      // ── 지표 3분할 ──
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        child: Row(children: [
          _metric('$count', '함께한 런'),
          const SizedBox(width: 10),
          _metric('${totalKm.toStringAsFixed(0)}km', '함께한 거리'),
          const SizedBox(width: 10),
          _metric('D+$daysTogether', '첫 런부터'),
        ]),
      ),
      // ── 마일스톤 ──
      if (achieved.isNotEmpty || nextThreshold != -1) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text('우리가 함께 넘은 것', style: GoText.label),
        ),
        if (achieved.isNotEmpty)
          _milestoneCard(
            icon: Icons.military_tech,
            title: '함께 ${achieved.last}km 넘었어요',
            subtitle: achievedDaysAgo == null
                ? '$partnerName님과 함께'
                : achievedDaysAgo == 0
                    ? '오늘 · $partnerName님과 함께'
                    : '$achievedDaysAgo일 전 · $partnerName님과 함께',
          ),
        if (nextThreshold != -1)
          _milestoneCard(
            icon: Icons.flag_outlined,
            title: '다음 목표 ${nextThreshold}km',
            subtitle:
                '${(nextThreshold - totalKm).toStringAsFixed(1)}km 남았어요',
            isNext: true,
          ),
      ],
      // ── 함께한 순간 ──
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Text('함께한 순간', style: GoText.label),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: sessions
            .map((s) => _momentRow(s, me, partnerUid, partnerName,
                storyLabel: storyLabels[s['id']]))
            .toList()),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
        child: Text('$count개의 순간을 함께 쌓았어요',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: GoColors.mid)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 20),
        child: Text('우리 둘이 함께 쌓아온 기록이에요.\n여기, 우리 사이에만 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, color: GoColors.coralDark, height: 1.6)),
      ),
    ]);
  }

  String _avatarLetter(String? name) =>
      (name == null || name.isEmpty) ? '나' : name[0];

  Widget _pairAvatar(String letter, Color borderColor,
      {bool overlap = false, String? photoUrl}) {
    return Container(
      margin: EdgeInsets.only(left: overlap ? -12 : 0),
      child: InitialAvatar(
        letter: letter,
        size: 30,
        fontSize: 13,
        borderColor: borderColor,
        photoUrl: photoUrl,
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: GoColors.line, width: GoStroke.card),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Text(value, style: GoTheme.serif(22)),
          const SizedBox(height: 3),
          Text(label, style: GoText.label),
        ]),
      ),
    );
  }

  Widget _milestoneCard({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isNext = false,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
            color: isNext ? GoColors.line : GoColors.limeDark,
            width: isNext ? GoStroke.rule : GoStroke.accent),
        borderRadius: BorderRadius.circular(GoRadius.md),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: isNext ? GoColors.dim : GoColors.limeDark),
        const SizedBox(width: GoSpace.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, color: GoColors.mid)),
          ]),
        ),
      ]),
    );
  }

  Widget _momentRow(
      Map<String, dynamic> s, String me, String partnerUid, String partnerName,
      {String? storyLabel}) {
    final started = sessionStartedAt(s);
    final km = combinedKm(s, me, partnerUid);
    final minutes = (sessionField(s, me, 'seconds').toInt() / 60).round();
    final day = started == null ? '-' : started.day.toString().padLeft(2, '0');
    final month = started == null ? '' : '${started.month}월';
    final timeOfDay = started == null
        ? ''
        : '${started.hour < 12 ? '오전' : '오후'} ${((started.hour + 11) % 12) + 1}시';
    final myMood = _moodField(s, me);
    final partnerMood = _moodField(s, partnerUid);
    final moodLine = [
      if (myMood != null) "나 '$myMood'",
      if (partnerMood != null) "$partnerName '$partnerMood'",
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: GoSpace.m),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: GoColors.line, width: GoStroke.rule)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 40,
          child: Column(children: [
            Text(day, style: GoTheme.serif(19)),
            const SizedBox(height: 2),
            Text(month,
                style: const TextStyle(fontSize: 9, color: GoColors.mid)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (storyLabel != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(GoRadius.sm),
                  border: Border.all(color: GoColors.limeDark, width: GoStroke.accent),
                ),
                child: Text(storyLabel,
                    style: const TextStyle(fontSize: 9,
                        fontWeight: FontWeight.w600, color: GoColors.limeDark)),
              ),
            ],
            Text('함께 $minutes분 달렸어요',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('${km.toStringAsFixed(1)}km · $timeOfDay',
                style: const TextStyle(fontSize: 11, color: GoColors.mid)),
            if (moodLine.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(moodLine,
                  style: const TextStyle(fontSize: 10, color: GoColors.coralDark)),
            ],
          ]),
        ),
      ]),
    );
  }

}
