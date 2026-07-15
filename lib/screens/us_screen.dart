import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/initial_avatar.dart';
import 'invite_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _friends.friendsStream(_auth.uid),
      builder: (context, friendSnap) {
        if (friendSnap.hasError) return _errorState();
        final friends = friendSnap.data;
        if (friends == null) return const SizedBox.shrink();
        if (friends.isEmpty) return _noFriendYet();

        final partner = friends.first;
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _runs.finishedSessionsWith(_auth.uid, partner['uid']),
          builder: (context, sessionSnap) {
            if (sessionSnap.hasError) return _errorState();
            if (!sessionSnap.hasData) return const SizedBox.shrink();
            final sessions = sessionSnap.data!;
            if (sessions.isEmpty) return _notRunTogetherYet(partner);
            return _journey(partner, sessions);
          },
        );
      },
    );
  }

  // ── 데이터 계산 ──

  num _field(Map<String, dynamic> session, String uid, String key) {
    final results = session['results'];
    if (results is! Map) return 0;
    final r = results[uid];
    if (r is! Map) return 0;
    final v = r[key];
    return v is num ? v : 0;
  }

  double _combinedKm(Map<String, dynamic> s, String me, String partner) =>
      _field(s, me, 'km').toDouble() + _field(s, partner, 'km').toDouble();

  DateTime? _startedAt(Map<String, dynamic> s) {
    final ts = s['startedAt'];
    return ts is Timestamp ? ts.toDate() : null;
  }

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

  /// 새 데이터 없이 기존 startedAt·km에서 계산하는 파생 스토리 라벨 —
  /// 행마다 최대 하나만 붙음 (첫 함께 달리기 > 가장 멀리 간 날 > 첫 새벽/밤 순 우선)
  Map<String, String> _storyLabels(
      List<Map<String, dynamic>> ascending, String me, String partnerUid) {
    final labels = <String, String>{};
    if (ascending.isEmpty) return labels;

    labels[ascending.first['id'] as String] = '첫 함께 달리기';

    var maxKm = -1.0;
    String? maxId;
    for (final s in ascending) {
      final km = _combinedKm(s, me, partnerUid);
      if (km > maxKm) {
        maxKm = km;
        maxId = s['id'] as String;
      }
    }
    if (maxId != null) labels.putIfAbsent(maxId, () => '가장 멀리 간 날');

    var dawnFound = false;
    var nightFound = false;
    for (final s in ascending) {
      final started = _startedAt(s);
      if (started == null) continue;
      final id = s['id'] as String;
      if (!dawnFound && started.hour >= 5 && started.hour < 7) {
        labels.putIfAbsent(id, () => '첫 새벽 러닝');
        dawnFound = true;
      }
      if (!nightFound && started.hour >= 22) {
        labels.putIfAbsent(id, () => '첫 밤 러닝');
        nightFound = true;
      }
    }
    return labels;
  }

  // ── 화면 ──

  /// 데이터를 불러오지 못했을 때 — 조용히 빈 화면 대신 다시 시도할 수 있게
  Widget _errorState() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('우리의 여정',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  letterSpacing: 1.4, color: GoColors.dim)),
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
                      color: GoColors.mid.withOpacity(.4), width: 2),
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    size: 28, color: GoColors.mid),
              ),
              const SizedBox(height: 18),
              Text('불러오지 못했어요',
                  textAlign: TextAlign.center, style: GoTheme.serif(22)),
              const SizedBox(height: 8),
              const Text('네트워크 상태를 확인하고 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: GoColors.line, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => setState(() {}),
                  child: Text('다시 시도',
                      style: GoTheme.serif(18, color: GoColors.ink)),
                ),
              ),
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
          child: Text('우리의 여정',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  letterSpacing: 1.4, color: GoColors.dim)),
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
                      color: GoColors.coralDark.withOpacity(.4), width: 2),
                ),
                child: const Icon(Icons.people_alt_outlined,
                    size: 30, color: GoColors.coralDark),
              ),
              const SizedBox(height: 18),
              Text('아직 함께 뛰는 사람이 없어요',
                  textAlign: TextAlign.center, style: GoTheme.serif(22)),
              const SizedBox(height: 8),
              const Text('한 명만 초대하면, 둘만의 여정이 시작돼요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: GoColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _openInvite,
                  child: Text('초대하기',
                      style: GoTheme.serif(18, color: GoColors.paper)),
                ),
              ),
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
          child: Text('우리의 여정',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  letterSpacing: 1.4, color: GoColors.dim)),
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
                      color: GoColors.limeDark.withOpacity(.4), width: 2),
                ),
                child: const Icon(Icons.directions_run,
                    size: 30, color: GoColors.limeDark),
              ),
              const SizedBox(height: 18),
              Text('${partner['name']}님과\n아직 함께 달리지 않았어요',
                  textAlign: TextAlign.center, style: GoTheme.serif(22)),
              const SizedBox(height: 8),
              const Text('한 번만 같이 뛰면, 여기에 우리 기록이 쌓여요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: GoColors.lime,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text('GO? 보내러 홈으로',
                      style: GoTheme.serif(18, color: GoColors.ink)),
                ),
              ),
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
        0, (sum, s) => sum + _combinedKm(s, me, partnerUid));
    final count = sessions.length;

    final ascending = sessions.reversed.toList();
    final storyLabels = _storyLabels(ascending, me, partnerUid);
    final firstStarted = _startedAt(ascending.first);
    final daysTogether =
        firstStarted == null ? 0 : DateTime.now().difference(firstStarted).inDays;

    // 주간 스트릭
    final weeks = sessions
        .map(_startedAt)
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
        .map(_startedAt)
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
        running += _combinedKm(s, me, partnerUid);
        if (running >= threshold) {
          final at = _startedAt(s);
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
        child: Text('우리의 여정',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                letterSpacing: 1.4, color: GoColors.dim)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
        child: Text('나 & $partnerName', style: GoTheme.serif(28)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: Row(children: [
          _pairAvatar(_avatarLetter(null), GoColors.limeDark),
          _pairAvatar(_avatarLetter(partnerName), GoColors.coralDark,
              overlap: true),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [GoColors.ink, Color(0xFF2A2A22)],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('멀리 있어도, 함께',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                  letterSpacing: 1.26,
                  color: GoColors.paper.withOpacity(.4))),
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
                    fontSize: 11, color: GoColors.paper.withOpacity(.5))),
          ),
          const SizedBox(height: 14),
          Text.rich(TextSpan(children: [
            const TextSpan(text: '함께 달린 '),
            TextSpan(
                text: '${totalKm.toStringAsFixed(1)}km',
                style: const TextStyle(color: GoColors.lime)),
            const TextSpan(text: '를\n만들었어요.'),
          ]), style: GoTheme.serif(23, color: GoColors.paper)),
        ]),
      ),
      // ── 스트릭 ──
      Container(
        margin: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: GoColors.amber.withOpacity(.22), width: 1.5),
          borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 12),
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
                  color: done
                      ? GoColors.amber.withOpacity(.16)
                      : GoColors.ink.withOpacity(.04),
                  borderRadius: BorderRadius.circular(8),
                  border: isToday && !done
                      ? Border.all(
                          color: GoColors.limeDark.withOpacity(.4), width: 1.5)
                      : null,
                ),
                child: Text(_kWeekdayLabels[i],
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: done ? GoColors.amber : GoColors.dim)),
              ),
            );
          })),
          if (!daysDone.contains(today)) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: GoColors.lime.withOpacity(.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('이번 주는 아직 함께 달리지 않았어요. 지금 GO?를 보내볼까요?',
                  style: TextStyle(fontSize: 11, color: GoColors.limeDark,
                      height: 1.5)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GoColors.lime,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('GO? 보내러 홈으로',
                    style: GoTheme.serif(17, color: GoColors.ink)),
              ),
            ),
          ],
        ]),
      ),
      // ── 지표 3분할 ──
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        child: Row(children: [
          _metric('$count', '함께한 런'),
          const SizedBox(width: 10),
          _metric('${totalKm.toStringAsFixed(0)}km', '함께 거리'),
          const SizedBox(width: 10),
          _metric('D+$daysTogether', '첫 런부터'),
        ]),
      ),
      // ── 마일스톤 ──
      if (achieved.isNotEmpty || nextThreshold != -1) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text('우리가 함께 넘은 것',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  letterSpacing: 1.1, color: GoColors.dim)),
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
        child: Text('함께한 순간',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                letterSpacing: 1.1, color: GoColors.dim)),
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
            style: const TextStyle(fontSize: 12, color: GoColors.dim)),
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

  Widget _pairAvatar(String letter, Color borderColor, {bool overlap = false}) {
    return Container(
      margin: EdgeInsets.only(left: overlap ? -12 : 0),
      child: InitialAvatar(
        letter: letter,
        size: 30,
        fontSize: 13,
        borderColor: borderColor,
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: GoColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Text(value, style: GoTheme.serif(22)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(fontSize: 9, letterSpacing: .5,
                  color: GoColors.dim)),
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
        color: isNext ? Colors.white : GoColors.lime.withOpacity(.1),
        border: Border.all(
            color: isNext ? GoColors.line : GoColors.limeDark.withOpacity(.16),
            width: isNext ? 1 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: isNext ? GoColors.dim : GoColors.limeDark),
        const SizedBox(width: 12),
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
    final started = _startedAt(s);
    final km = _combinedKm(s, me, partnerUid);
    final minutes = (_field(s, me, 'seconds').toInt() / 60).round();
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
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: GoColors.line)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 40,
          child: Column(children: [
            Text(day, style: GoTheme.serif(19)),
            const SizedBox(height: 2),
            Text(month,
                style: const TextStyle(fontSize: 9, color: GoColors.dim)),
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
                  color: GoColors.lime.withOpacity(.15),
                  borderRadius: BorderRadius.circular(20),
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

  void _openInvite() async {
    final me = await _auth.myProfile();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => InviteScreen(
          myCode: me?['inviteCode'] ?? '', myName: me?['name'] ?? ''),
    ));
  }
}
