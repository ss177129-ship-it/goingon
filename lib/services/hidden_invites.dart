import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 내가 목록에서 치운 지난 제안들.
///
/// **문서를 지우지 않는다.** 세션은 두 사람이 함께 가진 것이라, 내가 지웠다고
/// 상대의 기록까지 없어지면 안 된다. 그리고 보안 규칙에는 애초에 삭제가
/// 열려 있지 않다 — 거절·만료의 흔적은 남는 편이 옳다. 여기서 다루는 것은
/// **내 화면에서 안 보이게 하는 것**뿐이다.
///
/// 기기에 저장한다. 앱을 껐다 켜면 다시 나타나는 '지우기'는 지운 것이
/// 아니고, 이건 사람마다 다른 취향이라 서버에 올릴 것도 아니다.
///
/// 살아 있는 제안은 여기 들어오지 않는다 — 답해야 할 것을 치울 수는 없다.
/// 그 판단은 화면이 한다(오가는 중에는 스와이프 자체가 없다).
class HiddenInvites extends ChangeNotifier {
  HiddenInvites._();

  static final instance = HiddenInvites._();

  static const _key = 'hiddenInvites';

  /// 무한정 쌓이지 않게 하는 상한. 세션 스트림이 12시간으로 잘려 있으므로
  /// 그보다 오래된 id는 어차피 아무도 묻지 않는다
  static const _max = 200;

  final _ids = <String>{};
  bool _loaded = false;

  bool contains(String sessionId) => _ids.contains(sessionId);

  /// 앱 시작 때 한 번. 실패해도 앱은 돌아간다 — 지운 것이 다시 보일 뿐이다
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _ids.addAll(prefs.getStringList(_key) ?? const []);
      if (_ids.isNotEmpty) notifyListeners();
    } catch (_) {
      // 저장소를 못 읽으면 아무것도 안 숨긴 상태로 시작한다
    }
  }

  Future<void> hide(Iterable<String> sessionIds) async {
    var changed = false;
    for (final id in sessionIds) {
      if (_ids.add(id)) changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    // 오래된 것부터 버린다 — Set은 삽입 순서를 지킨다
    while (_ids.length > _max) {
      _ids.remove(_ids.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _ids.toList());
    } catch (_) {
      // 저장에 실패해도 이번 실행 동안에는 숨겨져 있다
    }
  }

  /// 테스트용 — 인스턴스가 하나뿐이라 테스트끼리 상태가 새지 않도록
  @visibleForTesting
  void resetForTest() {
    _ids.clear();
    _loaded = false;
  }
}
