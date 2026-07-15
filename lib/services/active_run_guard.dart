/// 로비/러닝 화면이 떠 있는 동안 true — 그 사이엔 새 GO? 요청 시트가
/// 겹쳐서 뜨지 않도록 홈 화면이 참조함
class ActiveRunGuard {
  static bool active = false;
}
