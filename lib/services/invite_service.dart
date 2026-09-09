import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'invite.dart';
import 'run_service.dart';
import 'shared_stream.dart';

/// 오가는 제안 전부를 한 목록으로 — 홈 카드와 '제안' 탭이 같은 것을 본다.
///
/// **두 방향을 합치는 이유.** 세션은 hostId/guestId 직접 비교로만 읽히므로
/// (`participants` arrayContains는 규칙이 거부한다) 쿼리가 반드시 둘로
/// 갈린다. 그 갈라짐이 화면까지 올라오면 홈 카드가 "내가 부른 것"과 "나를
/// 부른 것"을 각각 따로 구독하게 되고, 두 스트림의 도착 순서에 따라 카드가
/// 깜빡인다. 합치는 자리는 한 곳이어야 한다.
///
/// 홈과 '제안' 탭이 동시에 살아 있으므로([IndexedStack]) 원본 구독은
/// [SharedStream]으로 하나만 둔다 — 친구 목록이 같은 이유로 그렇게 한다.
class InviteService {
  InviteService({RunService? runs}) : _runs = runs ?? RunService();

  final RunService _runs;

  static final _shared = SharedStream<List<Invite>>();

  /// 내가 낀 제안 전부. 살아 있는 것이 앞, 지난 결과가 뒤
  Stream<List<Invite>> stream(String myUid) =>
      _shared.of(myUid, () => _merged(myUid));

  Stream<List<Invite>> _merged(String myUid) {
    final controller = StreamController<List<Invite>>.broadcast();
    List<Invite>? incoming, outgoing;
    StreamSubscription? a, b;

    void emit() {
      // 한쪽만 도착했어도 내보낸다 — 둘 다 기다리면 상대가 아직 아무것도
      // 보낸 적 없는 사람에게는 목록이 영영 오지 않는다
      if (incoming == null && outgoing == null) return;
      final all = [...?incoming, ...?outgoing];
      final now = DateTime.now();
      all.sort((x, y) {
        final open = (y.isOpen(now) ? 1 : 0) - (x.isOpen(now) ? 1 : 0);
        if (open != 0) return open;
        final xa = x.createdAt, ya = y.createdAt;
        if (xa == null) return -1;
        if (ya == null) return 1;
        return ya.compareTo(xa);
      });
      controller.add(all);
    }

    List<Invite> parse(QuerySnapshot<Map<String, dynamic>> snap) => [
          for (final d in snap.docs)
            if (Invite.from(d.id, d.data(), myUid) case final i?) i,
        ];

    controller.onListen = () {
      a = _runs.incomingSessions(myUid).listen((s) {
        incoming = parse(s);
        emit();
      }, onError: controller.addError);
      b = _runs.outgoingSessions(myUid).listen((s) {
        outgoing = parse(s);
        emit();
      }, onError: controller.addError);
    };
    controller.onCancel = () async {
      await a?.cancel();
      await b?.cancel();
    };
    return controller.stream;
  }
}
