#!/usr/bin/env bash
# 어느 Firebase 프로젝트를 볼지 고른다 — 운영(prod) / 연습실(staging).
#
#   ./tools/env.sh staging     연습실로 전환
#   ./tools/env.sh prod        운영으로 되돌림
#   ./tools/env.sh             지금 뭐가 걸려 있는지만 보여줌
#
# ## 왜 plist를 바꿔야 하는가 (2026-09-10에 알아낸 것)
#
# firebase_core 플러그인이 **Dart의 main()보다 먼저** GoogleService-Info.plist를
# 읽어 [DEFAULT] 앱을 만든다. 그래서 iOS에서는 plist가 이기고, Dart 쪽
# FirebaseOptions로는 프로젝트를 바꿀 수 없다. 다른 설정으로 다시 만들려 하면
# `[core/duplicate-app]`이 나고, 그 예외가 runApp()까지 못 가게 막아
# **런치 스크린인 채로 멈춘다** — 크래시도 에러 화면도 없어서 원인이 안 보인다.
#
# 게다가 Auth 키체인·FCM·Crashlytics는 전부 네이티브 SDK가 plist 기준으로
# 잡으므로, plist를 안 바꾸면 연습실은 애초에 성립하지 않는다.
#
# ## 저장소에 커밋된 상태는 언제나 prod다
#
# GoogleService-Info.plist(활성)는 prod 사본과 같아야 한다. 연습실 상태로
# 커밋되면 TestFlight 빌드가 연습실을 보게 되고, 리뷰어 앱이 통째로 엉뚱한
# 데이터를 보게 된다. test/firebase_env_test.dart가 이걸 지킨다.
set -euo pipefail
cd "$(dirname "$0")/.."

ACTIVE=ios/Runner/GoogleService-Info.plist
current() { grep -A1 '<key>PROJECT_ID</key>' "$ACTIVE" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/'; }

show() {
  local p; p="$(current)"
  case "$p" in
    goingon-c12f3)   echo "지금: 운영 (prod, $p)" ;;
    goingon-staging) echo "지금: 연습실 (staging, $p)  ← 커밋하지 말 것" ;;
    *)               echo "지금: 알 수 없음 ($p)" ;;
  esac
}

if [ $# -eq 0 ]; then show; exit 0; fi

case "$1" in
  prod|staging) ;;
  *) echo "쓰는 법: $0 [prod|staging]" >&2; exit 2 ;;
esac

SRC="ios/Runner/GoogleService-Info-$1.plist"
[ -f "$SRC" ] || { echo "없는 파일: $SRC" >&2; exit 1; }
cp "$SRC" "$ACTIVE"
show

# 플래그를 함께 줘야 앱이 전환을 인정한다. 안 맞으면 앱이 시작하자마자
# 어긋났다고 말하고 멈춘다 (FirebaseEnv.verify)
if [ "$1" = staging ]; then
  echo
  echo "  flutter run --dart-define=GO_ENV=staging"
  echo "  (플래그 없이 돌리면 앱이 어긋났다고 알려주고 멈춘다)"
else
  echo
  echo "  flutter run"
fi
