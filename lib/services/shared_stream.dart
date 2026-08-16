import 'dart:async';

/// 같은 키로 요청된 스트림을 여러 구독자가 **하나의 원본으로** 나눠 쓰게 한다.
///
/// 왜 필요한가: 홈 탭과 '우리' 탭이 각각 `friendsStream`을 구독하는데,
/// RootScreen이 `IndexedStack`이라 두 화면이 동시에 살아 있다. 그래서 같은
/// 친구 목록을 Firestore에서 **두 번** 듣고 있었고, 읽기 비용도 두 배였다.
///
/// 화면 구조를 바꿔 상위에서 한 번만 구독해 내려주는 방법도 있지만, 그러면
/// 홈이 갖고 있는 재시도·마지막 목록 유지 같은 처리를 옮겨야 한다. 여기서
/// 공유하면 호출부는 그대로 두고 원본 구독만 하나로 줄일 수 있다.
///
/// 마지막 구독자가 떠나면 원본 구독도 끊는다 — 안 끊으면 화면이 사라진 뒤에도
/// Firestore 리스너가 남아 읽기가 계속 청구된다. 나중에 누가 다시 구독하면
/// 원본을 새로 만든다.
class SharedStream<T> {
  final _entries = <String, _Entry<T>>{};

  /// [key]에 대한 공유 스트림. 처음 구독될 때 [create]가 원본을 만든다.
  Stream<T> of(String key, Stream<T> Function() create) {
    final existing = _entries[key];
    if (existing != null) return existing.controller.stream;

    late final _Entry<T> entry;
    final controller = StreamController<T>.broadcast(
      // 첫 구독자가 붙을 때만 원본을 연다
      onListen: () {
        entry.subscription ??= create().listen(
          (event) {
            entry.latest = event;
            entry.controller.add(event);
          },
          onError: entry.controller.addError,
        );
      },
      // 마지막 구독자가 떠나면 원본을 닫는다
      onCancel: () {
        entry.subscription?.cancel();
        entry.subscription = null;
        entry.latest = null;
      },
    );
    entry = _Entry<T>(controller);
    _entries[key] = entry;
    return controller.stream;
  }

  /// 지금 흐르고 있는 원본 구독 수 — 공유가 실제로 되는지 확인하는 용도
  int get activeSourceCount =>
      _entries.values.where((e) => e.subscription != null).length;

  /// 마지막으로 흘러간 값. 새 구독자가 첫 이벤트를 기다리지 않아도 되게
  /// 하고 싶을 때 쓸 수 있다(지금은 진단용)
  T? latestOf(String key) => _entries[key]?.latest;

  Future<void> dispose() async {
    for (final e in _entries.values) {
      await e.subscription?.cancel();
      await e.controller.close();
    }
    _entries.clear();
  }
}

class _Entry<T> {
  final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  T? latest;
  _Entry(this.controller);
}
