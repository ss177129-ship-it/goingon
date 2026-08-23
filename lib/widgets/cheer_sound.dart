import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../services/resonance.dart' show SignalKind;
import '../services/sound/sound_engine.dart';
import '../services/sound/soloud_sound_engine.dart';
import '../services/sound_settings.dart';
import '../theme.dart';
import 'pressable.dart';

/// 페이스메이트 요청에 얹는 **응원 소리 하나**.
///
/// 자유 텍스트를 두지 않는다. 첫 접촉이 자유 입력이 되면 그 순간부터 이
/// 앱은 유해 텍스트를 걸러야 하는 제품이 되고, 애초에 여기서 필요한 것은
/// 문장이 아니라 "반갑다"는 소리 하나다.
///
/// 셋의 뜻은 러닝 중 신호와 같다 — 나중에 함께 달릴 때 같은 소리를 다시
/// 듣게 되므로, 여기서 고르는 것이 곧 그 사람과의 첫 공통 어휘가 된다.
class CheerSound {
  const CheerSound._();

  static const choices = [SignalKind.here, SignalKind.cheer, SignalKind.slow];

  /// 화면에 보여줄 이름. 러닝 중에는 신호에 글자를 붙이지 않지만(감각이어야
  /// 하므로), 여기서는 **소리를 고르는 화면**이라 이름이 있어야 고를 수 있다
  static String label(SignalKind k) => switch (k) {
        SignalKind.here => '여기 있어',
        SignalKind.cheer => '힘내',
        SignalKind.slow => '천천히 가자',
      };

  static SoundId soundOf(SignalKind k) => switch (k) {
        SignalKind.here => SoundId.sigHere,
        SignalKind.cheer => SoundId.sigCheer,
        SignalKind.slow => SoundId.sigSlow,
      };
}

/// 소리 하나를 들려주기 위한 최소한의 엔진.
///
/// 화면마다 엔진을 새로 만들면 그때마다 음원 전체를 다시 올리고 오디오
/// 세션을 잡는다. 고르는 동안 여러 번 눌리는 자리라 한 번만 올려 두고 쓴다
class CheerPlayer {
  CheerPlayer._();
  static final instance = CheerPlayer._();

  SoundEngine? _engine;
  Future<void>? _loading;

  Future<void> play(SignalKind kind) async {
    if (!await SoundSettings.load()) return;
    _loading ??= _load();
    await _loading;
    await _engine?.playOneShot(CheerSound.soundOf(kind));
  }

  Future<void> _load() async {
    final engine = SoLoudSoundEngine();
    await engine.loadAssets();
    _engine = engine;
  }
}

/// 셋 중 하나 고르기. 고르는 즉시 들려준다 — 무슨 소리인지 모르고 보내는
/// 것은 고른 게 아니다
class CheerPicker extends StatelessWidget {
  const CheerPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final SignalKind selected;
  final ValueChanged<SignalKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final k in CheerSound.choices) ...[
          if (k != CheerSound.choices.first) const SizedBox(width: 8),
          Expanded(child: _chip(k)),
        ],
      ],
    );
  }

  Widget _chip(SignalKind kind) {
    final on = kind == selected;
    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(kind);
        CheerPlayer.instance.play(kind);
      },
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? GoColors.lime.withValues(alpha: .22) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? GoColors.limeDark : GoColors.line,
            width: on ? 1.6 : 1,
          ),
        ),
        child: Text(CheerSound.label(kind),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? GoColors.limeDark : GoColors.mid)),
      ),
    );
  }
}

/// 받은 요청에 얹혀 온 소리를 다시 들어보는 작은 버튼
class CheerReplay extends StatelessWidget {
  const CheerReplay({super.key, required this.kind});

  final SignalKind kind;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => CheerPlayer.instance.play(kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: GoColors.coral.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.volume_up_outlined,
              size: 14, color: GoColors.coralDark),
          const SizedBox(width: 5),
          Text(CheerSound.label(kind),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GoColors.coralDark)),
        ]),
      ),
    );
  }
}
