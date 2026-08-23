// '오늘의 상대' — 고스트런 1막(§3-3).
//
// 순서가 곧 제품의 주장이다:
//   ① 페이스메이트의 최근 러닝 — **안부 가치**. 아는 사람의 어제가 가장 진하다
//   ② 나의 과거 — 연속성. 친구가 없어도 상대가 있다(Day 0의 ③, §5)
//   ③ 사연 고스트 — 발견. 모르는 사람이지만 진짜 사람이다(라디오 사연 문법)
//
// 알고리즘 큐레이션은 넣지 않는다(§6-2, v1). 누구와 달릴지는 사람이 고른다.
import 'ghost_run.dart';

/// 이 상대가 왜 여기 있는가. 화면이 문구를 고르는 근거가 된다
enum PartnerReason {
  /// 페이스메이트의 최근 러닝
  pacemate,

  /// 나의 과거
  myPast,

  /// 사연 고스트(시드·릴레이 풀)
  seed,
}

class TodayPartner {
  const TodayPartner(this.ghost, this.reason);

  final GhostRun ghost;
  final PartnerReason reason;
}

class TodayPartnerPicker {
  const TodayPartnerPicker._();

  /// 한 화면에 올릴 최대 수. 더 많으면 고르는 일이 과제가 된다
  static const kMax = 6;

  /// 나의 과거는 이만큼까지만 섞는다. 전부 내 것이면 '함께'가 아니라
  /// 혼자 하는 회고가 된다
  static const kMaxMyPast = 2;

  /// [fromPacemates]·[mine]·[seeds]를 §3-3의 우선순위로 늘어놓는다.
  ///
  /// 같은 고스트가 두 번 나오지 않고, 2분 미만은 애초에 들어오지 않는다.
  /// 사연 한 마디가 있는 것을 같은 층 안에서 앞에 둔다 — 맥락이 있는 쪽이
  /// 고르기 쉽고, 그게 사연 채집의 보상이기도 하다.
  static List<TodayPartner> rank({
    List<GhostRun> fromPacemates = const [],
    List<GhostRun> mine = const [],
    List<GhostRun> seeds = const [],
    int max = kMax,
  }) {
    final seen = <String>{};
    final out = <TodayPartner>[];

    void add(Iterable<GhostRun> runs, PartnerReason reason, {int? cap}) {
      var added = 0;
      for (final g in _withStoryFirst(runs)) {
        if (out.length >= max) return;
        if (cap != null && added >= cap) return;
        if (!g.isUsable || !seen.add(g.id)) continue;
        out.add(TodayPartner(g, reason));
        added++;
      }
    }

    add(fromPacemates, PartnerReason.pacemate);
    add(mine, PartnerReason.myPast, cap: kMaxMyPast);
    add(seeds, PartnerReason.seed);
    return out;
  }

  /// 최신순은 유지하되 사연 있는 것을 앞으로 — 안정 정렬이라 같은 조건이면
  /// 원래 순서(최신순)가 그대로 남는다
  static List<GhostRun> _withStoryFirst(Iterable<GhostRun> runs) {
    final withStory = <GhostRun>[];
    final without = <GhostRun>[];
    for (final g in runs) {
      ((g.story?.isNotEmpty ?? false) ? withStory : without).add(g);
    }
    return [...withStory, ...without];
  }
}
