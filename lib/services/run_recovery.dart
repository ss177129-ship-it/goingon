import 'package:shared_preferences/shared_preferences.dart';

import 'run_service.dart' show kDemoSessionId;

/// 러닝 중 앱이 강제 종료(백그라운드 킬·크래시)돼도 기록이 통째로 사라지지
/// 않도록, 진행 중인 러닝의 스냅샷을 로컬에 저장해 둠.
///
/// - RunScreen이 러닝 중 주기적으로 [save]를 호출해 갱신
/// - 정상 종료(결과 제출 성공) 시 [clear]
/// - 앱을 다시 열면 RootScreen이 [load]로 발견하고 기록 마무리를 제안
///
/// **데모 러닝은 저장하지 않음.** 데모 세션(`kDemoSessionId`)은 Firestore에
/// 문서가 없어서, 복구를 제안한 뒤 "기록 저장"을 누르면 제출이 반드시 실패하고
/// 스냅샷은 재시도용으로 남겨지므로 앱을 열 때마다 같은 다이얼로그가 영원히
/// 뜬다. 심사관이 데모를 돌리다 앱을 내리면 바로 이 경로를 밟게 되므로,
/// 호출부에서 빠뜨릴 수 없도록 저장·복구 양쪽에서 막는다.
class RunRecovery {
  static const _kSessionId = 'active_run_session_id';
  static const _kPartnerName = 'active_run_partner_name';
  static const _kKm = 'active_run_km';
  static const _kSeconds = 'active_run_seconds';
  static const _kSavedAtMs = 'active_run_saved_at_ms';

  /// 이보다 오래된 스냅샷은 복구 제안 없이 폐기 —
  /// run_service의 "24시간 넘게 running이면 사실상 끝난 세션" 기준과 맞춤
  static const _staleAfter = Duration(hours: 24);

  static Future<void> save({
    required String sessionId,
    required String partnerName,
    required double km,
    required int seconds,
  }) async {
    if (sessionId == kDemoSessionId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionId, sessionId);
    await prefs.setString(_kPartnerName, partnerName);
    await prefs.setDouble(_kKm, km);
    await prefs.setInt(_kSeconds, seconds);
    await prefs.setInt(_kSavedAtMs, DateTime.now().millisecondsSinceEpoch);
  }

  /// 복구 가능한 스냅샷이 있으면 반환, 없거나 너무 오래됐으면 null.
  /// 오래된 스냅샷은 이 호출에서 정리됨.
  static Future<ActiveRunSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_kSessionId);
    final savedAtMs = prefs.getInt(_kSavedAtMs);
    if (sessionId == null || savedAtMs == null) return null;
    // 이 가드가 생기기 전 빌드에서 저장된 데모 스냅샷이 남아 있을 수 있음 —
    // 발견 즉시 폐기해서 무한 다이얼로그로 이어지지 않게 함
    if (sessionId == kDemoSessionId) {
      await clear();
      return null;
    }
    final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
    if (DateTime.now().difference(savedAt) > _staleAfter) {
      await clear();
      return null;
    }
    return ActiveRunSnapshot(
      sessionId: sessionId,
      partnerName: prefs.getString(_kPartnerName) ?? '',
      km: prefs.getDouble(_kKm) ?? 0,
      seconds: prefs.getInt(_kSeconds) ?? 0,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionId);
    await prefs.remove(_kPartnerName);
    await prefs.remove(_kKm);
    await prefs.remove(_kSeconds);
    await prefs.remove(_kSavedAtMs);
  }
}

/// 강제 종료 직전까지 저장돼 있던 러닝 기록
class ActiveRunSnapshot {
  final String sessionId;
  final String partnerName;
  final double km;
  final int seconds;

  const ActiveRunSnapshot({
    required this.sessionId,
    required this.partnerName,
    required this.km,
    required this.seconds,
  });
}
