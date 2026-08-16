#!/bin/bash
# 웹 클로드(claude.ai)와 UX/UI를 같이 보기 위한 자료 묶음을 만든다.
#
#   ./tools/export-for-web.sh
#   → ~/Desktop/goingon-web-context/ 에 파일이 만들어짐. 통째로 끌어다 올리면 됨
#
# 왜 스크립트인가: 예전에 손으로 만든 goingon_app_code.txt가 데스크톱에
# 있었는데 5주 전 것이었다. 코드는 매일 바뀌므로 **한 번 만든 묶음은 반드시
# 썩는다.** 대화를 시작할 때마다 이걸 한 번 돌리는 편이 낫다.
#
# 무엇을 넣고 무엇을 빼는가: UX/UI 대화에 필요한 것은 화면·디자인 기준·
# 실제 스크린샷이다. Firebase 설정, 러닝 누적 로직, 테스트는 넣지 않는다 —
# 맥락이 길어질수록 정작 화면 이야기가 묻힌다.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$HOME/Desktop/goingon-web-context"
rm -rf "$OUT"
mkdir -p "$OUT/screenshots"

# ── 1. 안내문 ────────────────────────────────────────────────────────
cat > "$OUT/00_먼저_읽어주세요.md" <<EOF
# GoingOn — UX/UI 협업용 자료

생성: $(date '+%Y-%m-%d %H:%M')
커밋: $(git rev-parse --short HEAD) $(git log -1 --format=%s)

## 이 앱이 파는 것

멀리 있는 친구·연인과 **같은 시간에 함께 달리는** iOS 앱.
"기록이 아니라 관계" — Strava식 퍼포먼스 경쟁이 아니라, 떨어져 있는 두
사람이 발을 맞추는 감각을 판다. 비전공자 1인 개발.

## 파일 안내

| 파일 | 무엇 |
|---|---|
| 01_디자인_기준.md | 색·타이포·되돌리면 안 되는 결정들. **이게 최우선 규칙** |
| 02_prototype_v2.html | 디자인의 단일 기준(브라우저로 열어볼 것) |
| 03_화면_코드.md | 실제 구현된 화면·위젯 전체 |
| 04_설계문서.md | 사운드 UX 설계서, 남은 과제 |
| screenshots/ | 지금 실제로 이렇게 보인다 |

## 대화할 때 알아두면 좋은 것

- **이모지를 쓸 수 없다.** 번들 폰트에 없어서 두부(?)로 깨진다.
  아이콘은 Material Icons, 강조는 타이포·색으로 한다
- 색 의미가 고정돼 있다: 나=lime, 상대=coral, **공명=골드(전용)**
- 세션(러닝) 화면은 "달리면서 곁눈으로 0.5초"가 기준이라 캡션 외에는
  34px 이상만 쓴다
- 화면에 없는 정보를 새로 만들지 않는다. 빼는 방향이 기본
EOF

# ── 2. 디자인 기준 (CLAUDE.md에서 디자인·결정 부분만) ────────────────
{
  echo "# 디자인 기준과 바꾸면 안 되는 결정들"
  echo
  echo "> 프로젝트 규칙 파일(CLAUDE.md)에서 디자인·제품 결정 부분만 추린 것."
  echo "> 프로토타입과 이 문서가 충돌하면 **이 문서가 우선**한다."
  echo
  sed -n '/## 디자인 기준/,/## 아키텍처/p' CLAUDE.md | sed '$d'
  echo
  sed -n '/## 의도된 설계 결정/,/## 완료 기준/p' CLAUDE.md | sed '$d'
} > "$OUT/01_디자인_기준.md"

cp design/prototype_v2.html "$OUT/02_prototype_v2.html"

# ── 3. 화면 코드 ─────────────────────────────────────────────────────
{
  echo "# 화면·위젯 코드 전체"
  echo
  echo "> 실제로 돌아가는 코드다. 주석에 '왜 그렇게 했는지'가 적혀 있으니"
  echo "> 바꾸자고 제안하기 전에 그 이유부터 읽어볼 것."
  echo
  for f in lib/theme.dart lib/screens/*.dart lib/widgets/*.dart; do
    echo
    echo "## \`$f\`"
    echo
    echo '```dart'
    cat "$f"
    echo '```'
  done
} > "$OUT/03_화면_코드.md"

# ── 4. 설계 문서 ─────────────────────────────────────────────────────
{
  echo "# 설계 문서"
  echo
  for f in docs/*.md TODO.md; do
    echo
    echo "## \`$f\`"
    echo
    cat "$f"
  done
} > "$OUT/04_설계문서.md"

# ── 5. 스크린샷 ──────────────────────────────────────────────────────
# 시뮬레이터가 떠 있으면 지금 화면을 한 장 새로 찍는다.
#
# 나머지 화면(러닝 중, 공명 순간 등)은 탭이 필요해 자동으로 못 찍는다 —
# 이 환경은 시뮬레이터 합성 입력이 막혀 있다. 손으로 찍은 것이 있으면
# 아래 폴더에 넣어두면 다음 실행 때도 함께 묶인다
KEEP="$HOME/Desktop/goingon-screenshots"
mkdir -p "$KEEP"
cp "$KEEP"/*.png "$OUT/screenshots/" 2>/dev/null || true

if xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
  xcrun simctl io booted screenshot "$OUT/screenshots/00_지금_화면.png" \
    >/dev/null 2>&1 || true
fi

echo "만들어진 곳: $OUT"
ls -la "$OUT" | tail -n +2 | awk '{printf "  %8s  %s\n", $5, $9}'
echo
echo "claude.ai에서 프로젝트를 만들고 이 폴더의 파일들을 올리면 됩니다."
