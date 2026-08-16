# 인증 키 — 어디에 있고, 어떻게 만드는가

이 프로젝트는 애플 키를 두 종류 쓴다. **둘 다 파일 이름이 `AuthKey_<키ID>.p8` 이라
구분이 안 된다** — 실제로 한 번 헷갈려서 시간을 썼다. 발급처가 다르고 용도가 다르다.

| | APNs 키 | App Store Connect API 키 |
|---|---|---|
| 용도 | 푸시 알림 발송 | TestFlight·App Store 업로드 |
| 발급처 | **Apple Developer** → Certificates, Identifiers & Profiles → Keys | **App Store Connect** → 사용자 및 액세스 → 통합 |
| 쓰는 곳 | Firebase 콘솔에 업로드 (서버가 사용) | `tools/ship-testflight.sh` |
| Issuer ID | 없음 | 있음 |

## 보관 위치

비밀은 전부 **저장소 밖**에 둔다. `~/.secrets`는 권한 700, 파일은 600.

```
~/.secrets/                           (권한 700)
├── appstore.env                      # ASC 자격증명 (키 ID·Issuer ID)
├── apple/
│   ├── AuthKey_A958S6968W.p8         # ✅ App Store Connect API 키 (goingon-ci, Admin)
│   └── AuthKey_4FX4S6SZNR.p8         # APNs 추정 — ASC 키 목록에 없음
└── goingon-firebase-adminsdk.json

~/.appstoreconnect/private_keys/
└── AuthKey_A958S6968W.p8 -> ~/.secrets/apple/...   # altool·notarytool 자동 탐색용 심링크
```

개인키 실체는 `~/.secrets` **한 곳에만** 두고, 애플 도구가 관례적으로 찾는
경로에는 심볼릭 링크만 걸어 둔다 — 사본을 여러 곳에 두지 않기 위함.

`.p8`은 `.gitignore`에도 걸려 있어 실수로 커밋될 수 없다.

> **주의: `.p8`은 다시 받을 수 없다.** 발급 시 딱 한 번만 다운로드되고, 잃어버리면
> 폐기하고 새로 만드는 수밖에 없다. APNs 키가 유출되면 **누구나 이 앱 사용자에게
> 푸시를 보낼 수 있다.**

## App Store Connect API 키 만들기

`ship-testflight.sh`가 쓰는 키다. 아직 발급 전이면 이 절차를 따른다.

1. https://appstoreconnect.apple.com/access/integrations/api 접속
2. 화면 상단의 **Issuer ID**를 확인한다 (이 팀 값: `1daf3883-22f1-447f-a23d-f267895eefdf`)
3. **키 생성** → 이름은 아무거나(예: `goingon-ci`), **액세스 권한은 `App Manager`**
   - `Developer`로는 업로드가 안 되고, `Admin`은 필요 이상으로 넓다
4. `.p8` 다운로드 — **이 순간이 유일한 기회다**
5. 목록에 표시된 **키 ID**(10자리)를 복사
6. 아래 실행:

```bash
mv ~/Downloads/AuthKey_<키ID>.p8 ~/.secrets/apple/
chmod 600 ~/.secrets/apple/AuthKey_<키ID>.p8
# appstore.env의 ASC_KEY_ID= 줄에 키 ID를 채운다
```

7. 확인:

```bash
./tools/ship-testflight.sh --build-only   # 빌드만, 업로드 없이 설정 점검
./tools/ship-testflight.sh                # 실제 업로드
```

### 제대로 된 키인지 확인하는 법

APNs 키를 잘못 넣어도 파일 형식이 같아서 JWT 생성까지는 성공한다. 실제로 통하는지는
App Store Connect에 물어봐야 안다:

```bash
ISS=1daf3883-22f1-447f-a23d-f267895eefdf
K=<키ID>
JWT=$(xcrun altool --generate-jwt --apiKey "$K" --apiIssuer "$ISS" \
        --p8-file-path ~/.secrets/apple/AuthKey_$K.p8 2>&1 \
      | grep -o '^ey[A-Za-z0-9._-]*')
echo "토큰 길이: ${#JWT}"   # 0이면 추출 실패 — 아래 함정 참고
curl -s -w "\nHTTP %{http_code}\n" \
  -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps?limit=1"
```

`200`이면 맞는 키, `401`이면 App Store Connect API 키가 아니다(APNs 키일 가능성이 높다).

> **⚠️ 함정 — 2026-08-16에 한 번 여기 걸렸다.**
> `altool --generate-jwt`는 **JWT를 stdout이 아니라 stderr로 출력한다.**
> 그래서 `2>/dev/null`을 붙이면 토큰이 **빈 문자열**이 되는데, 빈 Bearer도
> 똑같이 **401**을 돌려준다. 그 결과 멀쩡한 키를 "잘못된 키"로 오진하고
> 새 키를 발급하러 갈 뻔했다.
>
> 반드시 `2>&1`을 쓰고, **토큰 길이를 먼저 확인**할 것(정상이면 280자 안팎).
> 401을 만나면 키를 의심하기 전에 토큰이 비어 있지 않은지부터 보라.

## APNs 키는 어느 게 쓰이고 있나

`~/.secrets/apple/`의 두 키 중 **어느 쪽이 Firebase에 올라가 있는지 아직 확인 안 됨.**
[Firebase 콘솔 → 프로젝트 설정 → Cloud Messaging](https://console.firebase.google.com/project/goingon-c12f3/settings/cloudmessaging)
에서 등록된 키 ID를 보면 알 수 있다. 확인되면 안 쓰는 쪽은
Apple Developer 포털에서 **폐기(Revoke)**하는 게 안전하다 — 살아 있는 키는 곧 열린 문이다.
