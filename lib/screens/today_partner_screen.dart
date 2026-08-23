import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/sound/briefing_script.dart';
import '../services/ghost/ghost_run.dart';
import '../services/ghost/today_partner.dart';
import '../services/ghost/today_partner_loader.dart';
import '../theme.dart';
import '../widgets/cadence_wave.dart';
import '../widgets/pressable.dart';
import 'run_screen.dart';

/// 07 러닝 준비 — 오늘의 상대. 고스트런 1막(§3-3)이 화면이 된 자리.
///
/// **모든 결정은 여기서 끝난다.** 러닝이 시작되면 화면을 보거나 만져야 하는
/// 순간이 0이어야 하므로(§0 원칙 1), 누구와 달릴지는 반드시 뛰기 전에
/// 정해져야 한다. 이 화면이 로비를 대체한 이유이기도 하다 — 로비는 상대가
/// 지금 자유로운지 서로 기다리는 방이었고, 그 기다림이 앱을 여는 이유를
/// "상대가 한가한 드문 순간"에 가둬 놨다.
class TodayPartnerScreen extends StatefulWidget {
  const TodayPartnerScreen({super.key, this.pacemateUid, this.pacemateName});

  /// 한 사람의 리듬만 볼 때(페이스메이트 목록에서 눌러 들어온 경우).
  /// null이면 오늘의 상대 후보 전체를 §3-3의 우선순위로 늘어놓는다
  final String? pacemateUid;

  /// 화면 제목에 쓸 이름. 목록이 이미 알고 있으므로 다시 조회하지 않는다
  final String? pacemateName;

  @override
  State<TodayPartnerScreen> createState() => _TodayPartnerScreenState();
}

class _TodayPartnerScreenState extends State<TodayPartnerScreen> {
  final _auth = AuthService();
  final _loader = TodayPartnerLoader();

  List<TodayPartner>? _partners;
  var _names = const <String, String>{};
  int _selected = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final uid = widget.pacemateUid;
      final partners = uid == null
          ? await _loader.load(_auth.uid)
          : await _loader.loadFrom(_auth.uid, uid);
      if (!mounted) return;
      setState(() {
        _names = partners.names;
        _partners = partners.list;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _run(GhostRun? ghost) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => RunScreen(
        // 세션이 없는 러닝이다. 혼자 달린 러닝에 세션이 없어서가 아니라,
        // 시차 동행에는 맞출 시각이 없기 때문이다
        sessionId: '',
        partnerName: ghost == null ? '' : _names[ghost.uid] ?? '',
        ghost: ghost,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final partners = _partners;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(_title, style: GoTheme.serif(24))),
                Pressable(
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, color: GoColors.dim),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                  widget.pacemateUid == null
                      ? '모든 결정은 뛰기 전에 — 러닝 중 조작은 없어요'
                      : '함께 달릴 리듬을 골라요',
                  style: const TextStyle(fontSize: 12, color: GoColors.mid)),
              const SizedBox(height: 14),
              Expanded(
                child: partners == null
                    ? Center(child: _failed ? _retry() : _loading())
                    : partners.isEmpty
                        ? _empty()
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: partners.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (_, i) => _card(partners[i], i),
                          ),
              ),
              const SizedBox(height: 14),
              if (partners != null && partners.isNotEmpty) ...[
                Pressable(
                  onTap: () => _run(partners[_selected].ghost),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: GoColors.ink,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    alignment: Alignment.center,
                    child: Text('이 리듬과 함께 달리기',
                        style: GoTheme.serif(18, color: GoColors.paper)),
                  ),
                ),
                // 한 사람을 보러 들어왔으면 여기서 혼자 달리기를 권하지
                // 않는다. 나가는 문은 위의 X 하나로 충분하다
                if (widget.pacemateUid == null) ...[
                  const SizedBox(height: 12),
                  Pressable(
                    onTap: () => _run(null),
                    child: const Text('오늘은 혼자 달릴래요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: GoColors.dim)),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 한 사람만 볼 때는 제목이 그 사람을 가리켜야 한다 — 누른 것과
  /// 도착한 곳이 같다는 걸 화면이 말해 준다
  String get _title {
    final name = widget.pacemateName;
    return name == null || name.isEmpty ? '오늘, 누구와 겹칠까요?' : '$name의 리듬';
  }

  Widget _loading() => const SizedBox(
      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));

  Widget _retry() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('오늘의 상대를 불러오지 못했어요',
            style: TextStyle(fontSize: 13, color: GoColors.mid)),
        TextButton(onPressed: _load, child: const Text('다시 시도')),
      ]);

  /// 후보가 하나도 없을 때. **여기서 사과하지 않는다** — 혼자 달리는 것이
  /// 모자란 상태가 아니라, 오늘의 8분이 다음 사람의 동반자가 되는 자리다(§5)
  /// 빈 상태 문장에 쓸 이름. 비어 있을 수 있는 값이라 한 번에 정리해 둔다
  String get _who {
    final name = widget.pacemateName;
    return name == null || name.isEmpty ? '이 사람' : name;
  }

  Widget _empty() {
    // 한 사람만 보러 들어왔는데 비어 있으면, 내가 달리라고 권할 자리가
    // 아니다. 여기서 필요한 말은 "그 사람이 아직 안 남겼다"뿐이다
    if (widget.pacemateUid != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('아직 남긴 리듬이 없어요', style: GoTheme.serif(20)),
          const SizedBox(height: 8),
          // 조사를 이름에 맞춘다 — '지수이 달리면'은 사람이 쓴 문장이 아니다
          Text('$_who${BriefingScript.subjectParticle(_who)} 달리면 '
              '그 리듬이 여기 쌓여요.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, height: 1.6, color: GoColors.mid)),
        ]),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('아직 겹칠 리듬이 없어요', style: GoTheme.serif(20)),
        const SizedBox(height: 8),
        const Text('오늘 달리면 그 리듬이 남아요.\n다음에 오면 어제의 내가 기다리고 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.6, color: GoColors.mid)),
        const SizedBox(height: 20),
        Pressable(
          onTap: () => _run(null),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: GoColors.ink,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Text('오늘의 8분 시작',
                style: GoTheme.serif(17, color: GoColors.paper)),
          ),
        ),
      ]),
    );
  }

  Widget _card(TodayPartner p, int index) {
    final selected = index == _selected;
    final g = p.ghost;
    return Pressable(
      onTap: () => setState(() => _selected = index),
      child: Container(
        height: 110,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: selected ? GoColors.lime.withValues(alpha: .16) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? GoColors.limeDark : GoColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_headline(p),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoTheme.serif(19)),
            const SizedBox(height: 3),
            Text(_subline(g),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: GoColors.mid)),
            const Spacer(),
            // 페이스 곡선 미리보기 — 그날의 리듬이 어떻게 흘렀는지.
            // 나(lime)가 아니라 상대(coral)의 것이므로 코랄
            SizedBox(
              height: 22,
              child: CadenceWave(g.cadence,
                  color: GoColors.coralDark.withValues(alpha: .55)),
            ),
          ],
        ),
      ),
    );
  }

  /// 왜 이 사람이 여기 있는가 — 순서가 곧 제품의 주장이라(§3-3) 이유를
  /// 문장으로 드러낸다
  String _headline(TodayPartner p) {
    final g = p.ghost;
    final when = '${_weekday(g.startedAt)} ${_partOfDay(g.startedAt)}';
    return switch (p.reason) {
      PartnerReason.pacemate => '${_names[g.uid] ?? '페이스메이트'}의 $when',
      PartnerReason.myPast => '$when의 나',
      PartnerReason.seed => '어느 러너의 $when',
    };
  }

  String _subline(GhostRun g) {
    final story = g.story;
    if (story != null && story.isNotEmpty) return '"$story"';
    return '${g.duration.inMinutes}분 · ${g.km.toStringAsFixed(1)}km';
  }

  static String _weekday(DateTime at) =>
      '${const ['월', '화', '수', '목', '금', '토', '일'][at.weekday - 1]}요일';

  static String _partOfDay(DateTime at) {
    final h = at.hour;
    if (h < 6) return '새벽';
    if (h < 11) return '아침';
    if (h < 17) return '낮';
    if (h < 21) return '저녁';
    return '밤';
  }
}
