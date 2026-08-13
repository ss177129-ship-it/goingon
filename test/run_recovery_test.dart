import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/run_recovery.dart';
import 'package:goingon/services/run_service.dart' show kDemoSessionId;
import 'package:shared_preferences/shared_preferences.dart';

/// RunRecovery의 저장 키 (구현과 같은 문자열 — 이전 빌드가 남긴 스냅샷을
/// 흉내 내려면 raw 키가 필요함)
const _kSessionId = 'active_run_session_id';
const _kPartnerName = 'active_run_partner_name';
const _kKm = 'active_run_km';
const _kSeconds = 'active_run_seconds';
const _kSavedAtMs = 'active_run_saved_at_ms';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RunRecovery 실제 러닝', () {
    test('저장한 스냅샷을 그대로 복구한다', () async {
      await RunRecovery.save(
          sessionId: 'abc123', partnerName: '지수', km: 3.42, seconds: 1120);

      final snapshot = await RunRecovery.load();

      expect(snapshot, isNotNull);
      expect(snapshot!.sessionId, 'abc123');
      expect(snapshot.partnerName, '지수');
      expect(snapshot.km, 3.42);
      expect(snapshot.seconds, 1120);
    });

    test('clear 후에는 복구할 게 없다', () async {
      await RunRecovery.save(
          sessionId: 'abc123', partnerName: '지수', km: 1, seconds: 60);
      await RunRecovery.clear();

      expect(await RunRecovery.load(), isNull);
    });

    test('24시간이 지난 스냅샷은 폐기한다', () async {
      SharedPreferences.setMockInitialValues({
        _kSessionId: 'abc123',
        _kPartnerName: '지수',
        _kKm: 3.0,
        _kSeconds: 900,
        _kSavedAtMs: DateTime.now()
            .subtract(const Duration(hours: 25))
            .millisecondsSinceEpoch,
      });

      expect(await RunRecovery.load(), isNull);
      // 폐기는 실제로 지워져야 함 — 다음 실행에서 또 판정하지 않도록
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kSessionId), isNull);
    });
  });

  // 데모 세션은 Firestore에 문서가 없어서 복구를 시도하면 제출이 반드시
  // 실패하고, 스냅샷이 재시도용으로 남아 앱을 열 때마다 같은 다이얼로그가
  // 영원히 뜬다. 심사관이 데모를 돌리다 앱을 내리면 밟는 경로라 반드시 막아야 함
  group('RunRecovery 데모 러닝', () {
    test('데모 러닝은 애초에 저장되지 않는다', () async {
      await RunRecovery.save(
          sessionId: kDemoSessionId, partnerName: '지수', km: 2.5, seconds: 600);

      expect(await RunRecovery.load(), isNull);
    });

    test('데모 저장은 기존 실제 러닝 스냅샷을 건드리지 않는다', () async {
      await RunRecovery.save(
          sessionId: 'real1', partnerName: '민수', km: 5, seconds: 1500);
      await RunRecovery.save(
          sessionId: kDemoSessionId, partnerName: '지수', km: 2.5, seconds: 600);

      final snapshot = await RunRecovery.load();
      expect(snapshot?.sessionId, 'real1');
    });

    test('예전 빌드가 남긴 데모 스냅샷은 복구 시점에 폐기한다', () async {
      SharedPreferences.setMockInitialValues({
        _kSessionId: kDemoSessionId,
        _kPartnerName: '지수',
        _kKm: 2.5,
        _kSeconds: 600,
        _kSavedAtMs: DateTime.now().millisecondsSinceEpoch,
      });

      expect(await RunRecovery.load(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kSessionId), isNull);
    });
  });
}
