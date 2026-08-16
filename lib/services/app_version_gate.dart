import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 너무 낡은 빌드는 들여보내지 않는다.
///
/// 서버(`config/app.minBuildNumber`)가 "이 번호 미만은 못 쓴다"를 정하고,
/// 앱은 시작할 때 자기 빌드 번호와 비교한다.
///
/// **두 가지를 반드시 지킨다:**
///
/// 1. **실패하면 열어준다.** 설정을 못 읽었다고 앱을 막으면, 지하철에서
///    러닝을 시작하려던 사람이 아무것도 못 하게 된다. 막는 것은 "낡았다는
///    사실을 확인했을 때"뿐이고, 네트워크 오류·문서 없음·권한 문제는 전부
///    통과다
/// 2. **이미 나간 빌드는 막을 수 없다.** 이 검사 코드가 없는 빌드는 검사를
///    하지 않는다. 즉 이 장치는 **이번 빌드 이후**를 위한 것이지, 지금
///    돌아다니는 옛 빌드를 잡아주지는 못한다
class AppVersionGate {
  const AppVersionGate._();

  /// 서버가 최소 빌드 번호를 적어두는 자리
  static const configPath = 'config/app';
  static const minBuildField = 'minBuildNumber';

  /// 지금 이 빌드가 막혀야 하는가.
  ///
  /// 순수 함수로 떼어둔 이유: 막는 판단은 조용히 틀리면 앱이 통째로 죽는
  /// 종류라, 네트워크 없이 시험할 수 있어야 한다
  static bool isBlocked({required int currentBuild, required int? minBuild}) {
    if (minBuild == null) return false; // 서버가 아무 말도 안 했으면 통과
    return currentBuild < minBuild;
  }

  /// 서버 설정과 내 빌드 번호를 읽어 비교한다. 문제가 생기면 **false**(통과)
  static Future<bool> shouldBlock() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber);
      if (currentBuild == null) return false;

      final doc = await FirebaseFirestore.instance
          .doc(configPath)
          .get()
          .timeout(const Duration(seconds: 5));
      final minBuild = (doc.data()?[minBuildField] as num?)?.toInt();

      final blocked = isBlocked(currentBuild: currentBuild, minBuild: minBuild);
      if (blocked) {
        debugPrint('[version] 빌드 $currentBuild < 최소 $minBuild — 업데이트 필요');
      }
      return blocked;
    } catch (e) {
      // 못 읽었으면 통과시킨다 (위 주석 1번)
      debugPrint('[version] 최소 버전 확인 실패, 그대로 진행: $e');
      return false;
    }
  }
}
