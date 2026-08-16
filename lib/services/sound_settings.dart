import 'package:shared_preferences/shared_preferences.dart';

/// 사운드를 켤지 말지. 기본은 켜짐.
///
/// 이 값이 false면 러닝 화면은 **오디오 세션도 잡지 않고 엔진도 만들지
/// 않는다.** 볼륨만 0으로 두는 것과 다르다 — 소리를 끈 사람의 폰에서
/// 오디오 세션이 살아 있으면 그 자체로 다른 앱의 재생에 영향을 준다.
class SoundSettings {
  const SoundSettings._();

  static const _key = 'sound_enabled';

  /// 마지막으로 읽은 값. 러닝 시작처럼 기다릴 수 없는 자리에서 쓰려고
  /// 캐시해 둔다(첫 실행 전에는 기본값 true)
  static bool cached = true;

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    cached = prefs.getBool(_key) ?? true;
    return cached;
  }

  static Future<void> save(bool enabled) async {
    cached = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
