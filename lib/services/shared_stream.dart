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
///
/// **늦게 붙는 구독자에게는 마지막 값을 먼저 준다**(2026-09-09). 브로드캐스트
/// 스트림은 이미 흘러간 값을 다시 주지 않으므로, 두 번째 화면은 다음 변경이
/// 올 때까지 빈 채로 앉아 있었다. 제안 목록에서 실제로 그랬다 — 홈 카드에는
/// 제안이 떠 있는데 '제안' 탭은 "오가는 제안이 없어요"였다. Firestore 문서가
/// 한동안 안 바뀌면 그 어긋남이 계속 간다.
class SharedStream<T> {
  final _entries = <String, _Entry<T>>{};

  /// [key]에 대한 공유 스트림. 처음 구독될 때 [create]가 원본을 만든다.
  Stream<T> of(String key, Stream<T> Function() create) {
    final existing = _entries[key];
    if (existing != null) return _replayed(existing);

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
    return _replayed(entry);
  }

  /// 마지막 값이 있으면 그것부터, 그다음부터는 원본 그대로.
  ///
  /// 값을 읽는 시점과 구독하는 시점 사이에 새 값이 지나갈 수 있지만, 그건
  /// 곧 이어질 이벤트로 덮인다 — 영영 비어 있는 것보다 낫다
  Stream<T> _replayed(_Entry<T> entry) => Stream.multi((sink) {
        // **동기적으로** 원본을 구독한다. async*를 쓰면 구독이 한 틱 뒤로
        // 밀려서 "구독하면 원본이 열린다"는 계약이 깨진다
        final cached = entry.latest;
        if (cached != null) sink.add(cached);
        final sub = entry.controller.stream.listen(
          sink.add,
          onError: sink.addError,
          onDone: sink.close,
        );
        sink.onCancel = sub.cancel;
      });

  /// 지금 흐르고 있는 원본 구독 수 — 공유가 실제로 되는지 확인하는 용도
  int get activeSourceCount =>
      _entries.values.where((e) => e.subscription != null).length;

  /// 마지막으로 흘러간 값 — 늦게 붙는 구독자에게 다시 주는 그 값이다
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
