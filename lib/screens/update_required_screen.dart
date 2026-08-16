import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_version_gate.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/pressable.dart';

/// 업데이트해야만 지나갈 수 있는 벽.
///
/// **나가는 길을 두지 않는다** — 뒤로가기도, 닫기도 없다. 여기까지 왔다는
/// 것은 서버가 "이 빌드로는 못 쓴다"고 확인해준 경우뿐이고(그 외에는 전부
/// 통과시킨다), 그런 빌드로 러닝을 시작하게 두면 기록이 어긋나거나 상대와
/// 규칙이 안 맞는다.
///
/// 대신 **할 일을 한 번에 할 수 있게** 한다: 버튼 하나로 TestFlight를 열고,
/// 업데이트한 뒤 '다시 확인'으로 그 자리에서 빠져나간다
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key, required this.onPassed});

  /// 업데이트가 확인되면 부를 콜백 — 앱을 다시 시작하지 않고 이어간다
  final VoidCallback onPassed;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _checking = false;
  String? _notice;

  /// 아직 스토어에 없으므로 TestFlight를 연다. 출시 후에는 App Store 주소로
  /// 바꿔야 하는 자리
  static final _testFlight = Uri.parse('itms-beta://');

  Future<void> _openTestFlight() async {
    try {
      final ok = await launchUrl(_testFlight, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _notice = 'TestFlight 앱을 직접 열어 업데이트해 주세요.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'TestFlight 앱을 직접 열어 업데이트해 주세요.');
      }
    }
  }

  Future<void> _recheck() async {
    setState(() {
      _checking = true;
      _notice = null;
    });
    final stillBlocked = await AppVersionGate.shouldBlock();
    if (!mounted) return;
    setState(() => _checking = false);
    if (stillBlocked) {
      setState(() => _notice = '아직 예전 버전이에요. 업데이트가 끝난 뒤 눌러 주세요.');
    } else {
      widget.onPassed();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 뒤로 나갈 수 없다 — 이 화면이 곧 앱의 전부인 상태
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: GoColors.paper,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BrandMark.compact(),
                const SizedBox(height: 28),
                Text('업데이트가 필요해요',
                    textAlign: TextAlign.center, style: GoTheme.serif(30)),
                const SizedBox(height: 12),
                const Text(
                  '지금 버전으로는 함께 달릴 수 없어요.\n최신 버전으로 업데이트하면 이어서 쓸 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: GoColors.mid),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 14),
                  Text(_notice!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: GoColors.coralDark)),
                ],
                const SizedBox(height: 32),
                Pressable(
                  onTap: _openTestFlight,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    decoration: BoxDecoration(
                      color: GoColors.ink,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text('업데이트하러 가기',
                          style: GoTheme.serif(19, color: GoColors.lime)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Pressable(
                  onTap: _checking ? null : _recheck,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: GoColors.mid))
                        : const Text('업데이트했어요 · 다시 확인',
                            style:
                                TextStyle(fontSize: 13, color: GoColors.mid)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
