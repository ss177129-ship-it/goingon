#!/bin/bash
# 빌드 번호 올리기 → IPA 빌드 → TestFlight 업로드까지 한 번에.
#
#   ./tools/ship-testflight.sh            # 빌드 번호 +1 하고 빌드·업로드
#   ./tools/ship-testflight.sh --no-bump  # 지금 버전 그대로 (재업로드는 실패함)
#   ./tools/ship-testflight.sh --build-only   # 빌드만, 업로드 안 함
#
# 케이블이 없어서 실기기 검증 경로가 TestFlight뿐이고 한 사이클이 20~40분이라,
# Xcode Organizer를 손으로 클릭하던 단계를 없애려고 만든 것.
#
# ── 사전 준비 (한 번만) ──────────────────────────────────────────────
# 키 발급 절차는 tools/KEYS.md 참고. 요약하면:
#   1) App Store Connect API 키를 발급받아 .p8을 ~/.secrets/apple/ 에 둔다
#   2) ~/.secrets/appstore.env 의 ASC_KEY_ID 를 채운다 (ASC_ISSUER_ID는 이미 있음)
#
# 비밀은 전부 저장소 밖(~/.secrets, 권한 700)에 두고, .p8은 .gitignore에도
# 걸려 있어 실수로 커밋될 수 없다.
set -euo pipefail
cd "$(dirname "$0")/.."

BUMP=1
UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --no-bump) BUMP=0 ;;
    --build-only) UPLOAD=0 ;;
    *) echo "모르는 옵션: $arg" >&2; exit 1 ;;
  esac
done

ENV_FILE="$HOME/.secrets/appstore.env"
if [ "$UPLOAD" = 1 ]; then
  if [ ! -f "$ENV_FILE" ]; then
    echo "✗ $ENV_FILE 이 없습니다. tools/KEYS.md 를 보세요." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
  : "${ASC_ISSUER_ID:?appstore.env에 ASC_ISSUER_ID 없음}"
  if [ -z "${ASC_KEY_ID:-}" ]; then
    echo "✗ appstore.env의 ASC_KEY_ID가 비어 있습니다." >&2
    echo "  App Store Connect API 키를 아직 발급하지 않았다면 tools/KEYS.md 참고." >&2
    exit 1
  fi
  KEY_DIR="${ASC_KEY_DIR:-$HOME/.secrets/apple}"
  P8="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
  if [ ! -f "$P8" ]; then
    echo "✗ 인증 키가 없습니다: $P8" >&2
    echo "  파일 이름은 반드시 AuthKey_<키ID>.p8 이어야 합니다." >&2
    exit 1
  fi
fi

# ── 빌드 번호 ────────────────────────────────────────────────────────
# pubspec의 version: x.y.z+N 에서 N만 올림. TestFlight는 같은 빌드 번호를
# 두 번 받지 않으므로, 올리지 않으면 업로드가 거부된다.
#
# 참고: Xcode의 export 옵션 `manageAppVersionAndBuildNumber`가 켜져 있어서,
# 여기서 정한 번호가 App Store Connect에 이미 있으면 **Xcode가 알아서 더 큰
# 번호로 바꿔 내보낸다.** 충돌 방지 장치라 그대로 두는 게 낫다. 다만 그래서
# pubspec의 번호는 '요청'이지 '보장'이 아니다 — 실제로 올라간 번호는 아래
# 업로드 직전에 IPA에서 읽어 출력한다
CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: *//')
NAME="${CURRENT%+*}"
NUMBER="${CURRENT#*+}"

if [ "$BUMP" = 1 ]; then
  NUMBER=$((NUMBER + 1))
  # macOS sed는 -i 뒤에 확장자 인자가 필요함
  sed -i '' "s/^version: .*/version: ${NAME}+${NUMBER}/" pubspec.yaml
  echo "▸ 빌드 번호 ${CURRENT} → ${NAME}+${NUMBER}"
else
  echo "▸ 빌드 번호 그대로 ${CURRENT}"
fi

# ── 빌드 ─────────────────────────────────────────────────────────────
echo "▸ IPA 빌드 중… (몇 분 걸립니다)"
flutter build ipa --export-method app-store

IPA=$(find build/ios/ipa -name '*.ipa' -maxdepth 1 | head -1)
[ -n "$IPA" ] || { echo "✗ IPA를 못 찾음 — 빌드가 실패했을 수 있습니다" >&2; exit 1; }

# 실제로 나갈 번호를 IPA에서 직접 읽는다. pubspec의 값과 다를 수 있음(위 참고)
WORK=$(mktemp -d)
unzip -q "$IPA" 'Payload/*.app/Info.plist' -d "$WORK"
PLIST=$(find "$WORK" -name Info.plist | head -1)
SHIPPED=$(plutil -extract CFBundleVersion raw "$PLIST" 2>/dev/null || echo "?")
MIN_OS=$(plutil -extract MinimumOSVersion raw "$PLIST" 2>/dev/null || echo "?")
rm -rf "$WORK"

echo "▸ 빌드 완료: $IPA"
echo "  실제 빌드 번호: $SHIPPED   (pubspec: $NUMBER)   최소 iOS: $MIN_OS"
if [ "$SHIPPED" != "$NUMBER" ]; then
  echo "  ⓘ Xcode가 충돌을 피해 번호를 조정했습니다 — 정상 동작입니다."
fi

if [ "$UPLOAD" = 0 ]; then
  echo "▸ --build-only 라서 업로드는 건너뜁니다."
  exit 0
fi

# ── 업로드 ───────────────────────────────────────────────────────────
# 올리기 전에 검증을 먼저 돌린다. 업로드는 몇 분씩 걸리는데, 서명·권한
# 문제는 validate 단계에서 훨씬 빨리 잡히기 때문
echo "▸ 검증 중…"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --p8-file-path "$P8"

echo "▸ 업로드 중…"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --p8-file-path "$P8"

echo
echo "✔ 빌드 ${NAME}+${SHIPPED} 업로드 완료. (최소 iOS ${MIN_OS})"
echo "  App Store Connect에서 처리에 보통 5~15분 걸리고, 끝나면 테스터에게 알림이 갑니다."
echo "  https://appstoreconnect.apple.com/apps"
