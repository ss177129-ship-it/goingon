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

  static String _name(Object? name) {
    final s = name is String ? name.trim() : '';
    return s.isEmpty ? '페이스메이트' : s;
  }
}
