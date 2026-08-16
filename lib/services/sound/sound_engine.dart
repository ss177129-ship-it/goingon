/// 앱이 낼 수 있는 소리의 전부. 여기 없는 소리는 존재하지 않는다.
///
/// 설계서(`docs/sound_ux_v1.md` §2)의 "침묵이 기본값" 원칙이 목록 자체로
/// 강제되도록 열거형으로 둔다 — 세션 시작음 같은 것을 넣고 싶어지면
/// 여기에 항목을 추가해야 하고, 그러면 눈에 띈다.
enum SoundId {
  /// 공명 패드. **세션 내내 깔리는 배경음악이 아니다** — 가까워졌을 때만
  /// 공간이 열린다(0.70 미만은 무음)
  padResonance('assets/audio/pad_resonance.wav', loop: true),

  /// 공명을 30초 이상 유지할 때 패드 위에 얹히는 배음 한 장.
  /// 새 소리가 아니라 같은 소리가 두꺼워지는 것이다
  padOvertone('assets/audio/pad_overtone.wav', loop: true),

  /// 공명 진입. 이 앱에서 가장 좋은 소리여야 한다
  chimeMatch('assets/audio/chime_match.wav', loop: false),

  /// 내가 신호를 보냈다는 확인. **작게** — 내 확인음은 작고 상대의 존재는 크다
  sigSend('assets/audio/sig_send.wav', loop: false),

  // ── 수신음 3종 ──
  // 눈 감고 구분되어야 한다. 그래서 셋의 **음높이·타수·길이가 모두** 다르다:
  // 낮은 한 타(0.18초) / 밝은 두 타(0.35초) / 부드러운 하강(1초).
  // 세기만 다르게 하면 주머니 속에서는 구분되지 않는다

  /// "여기 있어" — 낮은 우드블록 한 타
  sigHere('assets/audio/sig_tap.wav', loop: false),

  /// "힘내" — 밝은 2연타
  sigCheer('assets/audio/sig_cheer.wav', loop: false),

  /// "천천히 가자" — 부드러운 하강음
  sigSlow('assets/audio/sig_easy.wav', loop: false);

  const SoundId(this.asset, {required this.loop});

  final String asset;
  final bool loop;
}

/// 재생 엔진 — 구현체를 갈아끼울 수 있도록 인터페이스로 둔다.
///
/// 왜 인터페이스인가: 지금은 flutter_soloud를 쓰지만 저지연 재생 엔진은
/// 판이 자주 바뀐다. 호출부(공명 사운드 로직)가 특정 엔진의 개념
/// (SoundHandle, AudioSource…)을 알게 되면 교체가 통째로 다시 쓰는 일이 된다.
abstract interface class SoundEngine {
  /// 엔진을 켜고 [SoundId]의 모든 음원을 메모리에 올린다.
  /// 실패하면 예외 대신 조용히 무음으로 남는다 — 소리가 안 난다고 러닝을
  /// 방해할 이유가 없다
  Future<void> loadAssets();

  /// 한 번 울리는 소리
  Future<void> playOneShot(SoundId id, {double volume = 1});

  /// 루프의 볼륨(0~1). 0이면 실제로 멈춘다(무음 루프를 계속 돌리지 않는다)
  Future<void> setLoopVolume(SoundId id, double volume);

  Future<void> dispose();
}
