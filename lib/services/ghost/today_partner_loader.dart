// '오늘의 상대' 후보를 실제로 모으는 곳.
//
// 판정(TodayPartnerPicker)과 수집(여기)을 나눈 이유: 판정은 순수 함수라
// 테스트가 지키고, 수집은 네트워크라 실패한다. 섞어 두면 "순서가 맞는가"를
// 검증하려면 Firestore를 띄워야 한다.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../friend_service.dart';
import 'ghost_service.dart';
import 'today_partner.dart';

/// 후보들과, 그들의 이름표. 이름은 고스트 문서에 없다 —
/// 이름은 사람의 성질이지 러닝의 성질이 아니라 users에 있다
class TodayPartners {
  const TodayPartners(this.list, this.names);

  final List<TodayPartner> list;
  final Map<String, String> names;

  TodayPartner? get first => list.isEmpty ? null : list.first;

  static const empty = TodayPartners([], {});
}

class TodayPartnerLoader {
  TodayPartnerLoader({
    FriendService? friends,
    GhostService? ghosts,
    FirebaseFirestore? db,
  })  : _friends = friends ?? FriendService(),
        _ghosts = ghosts ?? GhostService(db: db);

  final FriendService _friends;
  final GhostService _ghosts;

  /// 세션 시작 전에 통째로 받아둔다(§3-3 2막). 달리는 중에 네트워크를
  /// 기다리면 그 순간 러너는 화면을 보게 되고, 그건 §0 원칙 1을 깨는 일이다
  Future<TodayPartners> load(String uid, {int max = TodayPartnerPicker.kMax}) async {
    final friends = await _friends.friendsStream(uid).first;
    final uids = [for (final f in friends) f['uid'] as String];
    final pacemates = await _ghosts.recentFrom(uids);
    final mine = await _ghosts.myOwn(uid);
    return TodayPartners(
      TodayPartnerPicker.rank(
        fromPacemates: pacemates,
        mine: mine,
        max: max,
      ),
      {
        for (final f in friends) f['uid'] as String: _name(f['name']),
        uid: '나',
      },
    );
  }

  /// **한 사람의 리듬만.** 페이스메이트 목록에서 그 사람을 눌렀을 때 쓴다.
  ///
  /// 이 갈래가 없어서 P5에서는 빅맨 옆의 '리듬' 버튼이 빅맨과 아무 상관
  /// 없는 후보 목록으로 갔다. 누른 사람과 도착지가 다르면 그 버튼은
  /// 거짓말을 하는 것이다.
  ///
  /// 이름표는 여전히 친구 목록에서 가져온다 — 이름은 사람의 성질이지
  /// 러닝의 성질이 아니라 고스트 문서에 없다
  Future<TodayPartners> loadFrom(String viewerUid, String ownerUid) async {
    final friends = await _friends.friendsStream(viewerUid).first;
    final runs = await _ghosts.recentFrom([ownerUid]);
    return TodayPartners(
      // 한 사람뿐이라 층 사이 우선순위는 의미가 없다. 그래도 판정기를
      // 거치는 이유는 중복 제거·2분 미만 배제·사연 있는 것 먼저가
      // 여기서도 그대로 맞기 때문이다
      TodayPartnerPicker.rank(fromPacemates: runs),
      {
        for (final f in friends) f['uid'] as String: _name(f['name']),
        viewerUid: '나',
      },
    );
  }

  static String _name(Object? name) {
    final s = name is String ? name.trim() : '';
    return s.isEmpty ? '페이스메이트' : s;
  }
}
