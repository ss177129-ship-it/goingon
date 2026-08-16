#!/bin/bash
# GitHub 비공개 저장소를 만들고 지금까지의 커밋을 전부 올린다.
#
#   ./tools/setup-github.sh
#
# 한 번만 하면 된다. 그다음부터는 `git push`만 치면 된다.
#
# 로그인은 브라우저 승인이 필요해 사람이 해야 하는 단계가 하나 있다.
# 이 스크립트는 그 단계를 최소로 줄이고(질문 3개 → 0개), 나머지를 이어서 한다.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_NAME="goingon"

echo "── 1/4  GitHub CLI 확인"
if ! command -v gh >/dev/null; then
  echo "✗ gh가 없습니다. 먼저: brew install gh" >&2
  exit 1
fi

echo "── 2/4  로그인 확인"
if gh auth status >/dev/null 2>&1; then
  echo "   이미 로그인돼 있습니다: $(gh api user --jq .login)"
else
  echo
  echo "   브라우저 승인이 필요합니다. 아래 순서대로 하시면 됩니다:"
  echo "     1) 화면에 뜨는 8자리 코드를 복사"
  echo "     2) 엔터 → 크롬이 열림"
  echo "     3) 코드를 붙여넣고 Authorize 승인"
  echo "     4) 이 창으로 돌아오면 자동으로 이어집니다"
  echo "   ** 이 터미널 창을 닫지 마세요 **"
  echo
  # -h/-p/-w로 질문을 미리 답해둬서, 사람이 할 일은 코드 붙여넣기뿐이다
  gh auth login --hostname github.com --git-protocol https --web
fi

echo "── 3/4  비공개 저장소 준비"
OWNER=$(gh api user --jq .login)
if gh repo view "$OWNER/$REPO_NAME" >/dev/null 2>&1; then
  echo "   이미 있습니다: $OWNER/$REPO_NAME"
else
  # --private: 이 저장소에는 App Store Connect 키 ID와 Firebase 설정이
  # 들어 있다. 개인키(.p8)는 gitignore로 빠져 있지만, 그래도 공개는 안 한다
  gh repo create "$OWNER/$REPO_NAME" --private \
    --description "멀리 있어도, 함께 달려요 — GoingOn iOS"
  echo "   만들었습니다 (비공개)"
fi

echo "── 4/4  올리기"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "https://github.com/$OWNER/$REPO_NAME.git"
else
  git remote add origin "https://github.com/$OWNER/$REPO_NAME.git"
fi
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push -u origin "$BRANCH"

echo
echo "✔ 끝났습니다."
echo "   주소: https://github.com/$OWNER/$REPO_NAME"
echo "   커밋 $(git rev-list --count HEAD)개가 올라갔습니다."
echo
echo "   앞으로는 'git push' 한 줄이면 됩니다."
echo "   웹 클로드에서는 이 주소를 GitHub 커넥터로 연결하면 항상 최신을 봅니다."
