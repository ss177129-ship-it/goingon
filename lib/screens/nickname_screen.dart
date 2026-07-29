import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import 'root_screen.dart';

/// 로그인(Apple 등) 성공 직후 항상 거치는 프로필 설정 화면 — 이름과
/// 검색용 아이디를 함께 만듦. prefill은 Apple이 최초 인가 시 준 이름
/// (없을 수도 있음).
class NicknameScreen extends StatefulWidget {
  final String? prefill;
  const NicknameScreen({super.key, this.prefill});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  late final _nameController = TextEditingController(text: widget.prefill ?? '');
  final _usernameController = TextEditingController();
  bool _loading = false;

  Future<void> _confirm() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    if (name.isEmpty || username.isEmpty) return;
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아이디는 영문 소문자·숫자·_ 로 3~20자예요.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ok = await AuthService().ensureProfile(name, username);
      if (!mounted) return;
      if (!ok) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 사용 중인 아이디예요. 다른 아이디를 입력해 주세요.')),
        );
        return;
      }
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const RootScreen()), (_) => false);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장에 실패했어요. 다시 시도해 주세요.')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 40),
              BrandMark.standard(),
              const SizedBox(height: 16),
              Text('goingon', style: GoTheme.serif(20, color: GoColors.dim)),
              const SizedBox(height: 18),
              Text('마지막으로,\n프로필을 만들어요',
                  textAlign: TextAlign.center, style: GoTheme.serif(30)),
              const SizedBox(height: 36),
              TextField(
                controller: _nameController,
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
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                textAlign: TextAlign.center,
                maxLength: 20,
                decoration: InputDecoration(
                  hintText: '아이디 (친구가 검색으로 찾아요)',
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
              const SizedBox(height: 8),
              const Text('영문 소문자·숫자·_ 로 3~20자',
                  style: TextStyle(fontSize: 11, color: GoColors.dim)),
              const SizedBox(height: 36),
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
