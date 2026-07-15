import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import 'root_screen.dart';

/// 로그인(Apple 등) 성공 직후 항상 거치는 닉네임 설정 화면.
/// prefill은 Apple이 최초 인가 시 준 이름(없을 수도 있음).
class NicknameScreen extends StatefulWidget {
  final String? prefill;
  const NicknameScreen({super.key, this.prefill});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  late final _controller = TextEditingController(text: widget.prefill ?? '');
  bool _loading = false;

  Future<void> _confirm() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      await AuthService().ensureProfile(name);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const RootScreen()), (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장에 실패했어요. 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              BrandMark.standard(),
              const SizedBox(height: 16),
              Text('goingon', style: GoTheme.serif(20, color: GoColors.dim)),
              const SizedBox(height: 18),
              Text('마지막으로,\n뭐라고 부르면 될까요?',
                  textAlign: TextAlign.center, style: GoTheme.serif(30)),
              const SizedBox(height: 36),
              TextField(
                controller: _controller,
                textAlign: TextAlign.center,
                maxLength: 10,
                autofocus: widget.prefill == null || widget.prefill!.isEmpty,
                decoration: InputDecoration(
                  hintText: '뭐라고 부르면 될까요?',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: GoColors.line),
                  ),
                ),
                onSubmitted: (_) => _confirm(),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: GoColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _loading ? null : _confirm,
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('시작하기',
                          style: GoTheme.serif(19, color: GoColors.paper)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
