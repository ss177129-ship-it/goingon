# 고잉온 기술 설계서 v1.0
2026-08-20 | 제품설계도 v1.1의 엔지니어링 번역 | CTO 작성
전제: 1인 개발 + AI 협업. 원칙 — 클라이언트는 두껍게(사운드·판정 전부 로컬), 서버는 얇게(동기화·그래프·알림만).

---

## 1. 아키텍처 개요

```
┌─────────────────────── iOS 클라이언트 (두꺼움) ───────────────────────┐
│  CadenceEngine → SessionController → AudioEngine                      │
│       ↓               ↓         ↑          ↑                          │
│  ResonanceDetector  ChartPlayer(채보)  GhostEngine(로컬 재생)          │
│                        ↓                                              │
│  RunRecorder(케이던스 타임라인·이벤트 기록) → 업로드 큐(오프라인 내성)  │
└──────────────────────────────┬────────────────────────────────────────┘
                               │ REST + Realtime(WS)
┌──────────────────────────────┴────────────────────────────────────────┐
│  백엔드 (얇음, BaaS): Auth · DB(runs/ghosts/graph) · Storage(음성)     │
│  RelayMatcher(엣지 함수) · NotificationService(APNs, 다이제스트 규칙)  │
│  [v1.1] LiveSessionChannel(케이던스 1Hz 릴레이)                        │
└───────────────────────────────────────────────────────────────────────┘
```

**핵심 설계 판단 3개**
1. **사운드는 100% 로컬 렌더링.** 라이브 세션에서도 오디오를 스트리밍하지 않는다 — 상대의 케이던스 값(1Hz)만 받고 발소리는 내 기기에서 합성. 네트워크 지연 100~300ms에 구조적으로 강건(설계도 §1-2).
2. **고스트런은 서버가 필요 없다.** 고스트 파일(케이던스 타임라인)을 세션 시작 전에 다운로드 → 이후 완전 오프라인 동작. v1.0의 핵심 경험 전부가 실시간 인프라 없이 성립 → 서버 비용·복잡도 최소.
3. **GPS는 선택 부품.** 케이던스는 가속도계만으로 검출(폰이 주머니에 있어도 동작). 거리 추정은 GPS 있으면 정밀, 없으면 보폭 추정 모델. 위치 데이터 기본 비저장 → 위치정보사업 규제 부담 최소화(스트라바 철수 원인 회피 — 이것 자체가 해자 설계).

---

## 2. 기술 스택

| 계층 | 선택 | 근거 |
|---|---|---|
| 클라이언트 | **iOS 네이티브 (Swift + SwiftUI)** | AVAudioEngine의 저지연 오디오 그래프·백그라운드 오디오·CoreMotion 직접 접근이 필수. 크로스플랫폼(RN/Flutter)은 오디오 엔진을 어차피 네이티브 모듈로 짜야 해서 1인팀에겐 이중 부담. ⚠️ 현 테스트플라이트 빌드가 비네이티브라면 사운드 코어만 네이티브 모듈로 분리하는 절충 검토 — 착수 전 결정 필요 |
| 오디오 | AVAudioEngine + AVAudioPlayerNode(스템)/AVAudioUnitTimePitch(템포) | 스템 동기 재생·실시간 템포 조정·백그라운드 유지 |
| 모션 | CoreMotion (CMPedometer + CMMotionManager 50Hz) | 걸음 이벤트 + 자체 스텝 검출 병행 |
| 백엔드 | **Supabase** (Postgres + Auth + Storage + Realtime + Edge Functions) | 1인팀 관리형. RLS로 공개 범위 구현 용이. Realtime 채널은 v1.1 라이브에 그대로 사용 |
| 푸시 | APNs (+ Supabase Edge Function 트리거) | 다이제스트 규칙 서버 측 구현 |
| 분석 | 자체 이벤트 테이블(초기) → 필요 시 Amplitude | 북극성 지표는 우리 DB에서 직접 계산 |

---

## 3. 클라이언트 모듈 설계

### 3-1. CadenceEngine — 발이 입력이다

```swift
protocol CadenceEngineDelegate {
    func cadenceDidUpdate(spm: Double, stability: Double)  // 1Hz
    func stepDetected(at t: TimeInterval)                   // 스텝 이벤트
    func gaitChanged(_ state: GaitState)                    // .running/.walking/.idle
}

final class CadenceEngine {
    // 검출: 가속도 수직축 피크 검출(50Hz) + CMPedometer 교차 검증
    // 스무딩: 3초 이동 평균(제품설계도 §1-1)
    // stability: 60초 창의 케이던스 표준편차 → 0~1 정규화(레이어 게이트 입력)
    // GaitState 판정: spm ≥ 140 .running / ≤ 120 .walking (히스테리시스 10초, §2-2 잔향 판정의 원천)
}
```

### 3-2. AudioEngine — D안 사운드 그래프

```
AVAudioEngine 그래프:
  [drumsPlayer] ─┐
  [bassPlayer]  ─┼─ [timePitch(rate=cadence/trackBPM)] ─┐
  [harmonyPlayer]┘                                       ├─ [mainMixer] → 출력
  [ghostSampler(상대 발소리, panner L/R 60:40)] ─────────┤
  [sfxPlayer(벨·박수·화자)] ──────────────────────────────┘
```

```swift
final class AudioEngine {
    // 스템: 에피소드당 drums/bass/harmony 3개 파일, 동일 길이 루프, 같은 프레임에서 시작(락스텝)
    // 템포: timePitch.rate = clamp(spm, 140, 190) / track.baseBPM
    //       걷기 구간은 half-time: rate = (spm*2)/baseBPM  (§1-1)
    // 레이어 게이트: bass.volume = stability > θ_bass ? fadeIn : fadeOut (2초 램프)
    //               harmony는 공명 or 안정 3분 시
    // 내 발소리 토글(검증 큐 #1): stepDetected → percSampler.play() (기본 비활성)
    // 상대 발소리: GhostEngine/LiveSession의 스텝 스케줄에 따라 ghostSampler 발화
    //             정위는 pan=0.2 고정(풀 3D 금지, §1-2), 모노 모드 시 pan=0
    // 거리감: ghostSampler.volume = f(|Δspm|)  — 가까울수록 선명
    // 백그라운드: AVAudioSession(.playback, mixWithOthers=false), 화면 꺼짐 유지
}
```

### 3-3. SessionController — 세션 상태 머신

```
        ┌─────────────────────────────────────────────────┐
 idle → intro → build → mission → climax → outro → REVERB ─┬→ freeRun ─┐
  ↑        (에피소드 채보가 구간 전환을 구동)               │→ chain(다음 에피소드→intro)
  │                                                        └→ cooldown → result
  └────────────────────────── 종료 ←───────────────────────────────┘
```

```swift
enum SessionPhase { case intro, build, mission, climax, outro,
                    reverb      // 잔향 30초 — "발이 결정한다"
                    , freeRun, cooldown, result }

// REVERB 판정 (§2-2 그대로):
//   진입: 채보 종료 시점. 음악 마스터 볼륨 0.3으로 유지(완전 정지 금지)
//   30초 내 gait == .running 지속  → freeRun (음악 재빌드, 멘트 없음)
//   꼭지 1회 탭                    → chain (다음 에피소드 큐)
//   gait == .walking 10초          → cooldown (오디오 디브리핑 → 음성 채집)
// 예외 (§0-1): 전화 수신 → pause, 종료 후 꼭지 1회로 재개
//             30초 미만 정지(신호등) → pause 아님, 레이어만 감쇠
// 부분 완주 (§2-1): elapsed ≥ 4분 → 여정 거리 인정 / 스트릭 미인정
```

### 3-4. ResonanceDetector — 공명 판정

```swift
// 입력: 내 spm(1Hz), 상대 spm(고스트 타임라인 or 라이브 1Hz)
// 판정 (§1-3):
//   d = |mySpm - theirSpm|, 정수비 검사: r = mySpm/theirSpm ∈ {0.5, 2/3, 1, 1.5, 2} ± 허용오차
//   d ≤ 3 (또는 정수비 일치) 가 8초 지속 → .resonating 진입 (벨 + harmony 만개)
//   조건 이탈 10초 지속 → 해제 (페이드만, 실패음 없음)
//   세션 누적 resonanceSeconds 기록 → 북극성 지표 원천
```

### 3-5. GhostEngine — 시차 동행 재생기

```swift
// 입력: GhostFile (사전 다운로드, §4 스키마)
// 재생: 세션 경과시간 t 기준으로 ghost.cadence[t]를 조회 → 스텝 스케줄 생성 → ghostSampler 발화
//       내 페이스와 완전 독립(시간축 기반, GPS 무관 — §3-2 결정)
// 이벤트: ghost.voiceClips[t] 도달 시 재생 / ghost.slowdownMarkers → 화자 코멘트(세션당 최대 2회)
// 종료: ghost.duration 도달 → 작별 시퀀스("여기까지였어요" + 페이드) → 내 세션은 계속
// 완주 후: POST /runs/{ghostRunId}/companions (3막 알림 트리거, §5 참조)
```

### 3-6. ChartPlayer — 채보(에피소드) 포맷

```jsonc
// episode_train.chart.json — 에피소드 = 데이터 (엔진 재배포 없이 콘텐츠 추가)
{
  "id": "ep_013_night_train",
  "title": "밤의 기차",
  "durationSec": 480,
  "stems": { "drums": "train_drums.m4a", "bass": "train_bass.m4a", "harmony": "train_harmony.m4a" },
  "baseBPM": 165,
  "sections": [
    { "t": 0,   "phase": "intro",   "narration": "출발합니다 — 당신의 발이 바퀴예요." },
    { "t": 60,  "phase": "build",   "verb": "hold",        "narration": "첫 역을 지나갑니다." },
    { "t": 240, "phase": "mission", "verb": "hold_low",    "fx": "tunnel_filter", "narration": "터널이에요. 리듬을 지켜요." },
    { "t": 360, "phase": "climax",  "verb": "spurt", "durationSec": 30, "successFx": "full_bloom" },
    { "t": 450, "phase": "outro",   "fx": "arrival_bell" }
  ],
  "safety": { "maxSpurtSec": 30, "noStopCues": true }   // 안전 규칙 채보 내장 (§콘텐츠 원칙)
}
```

---

## 4. 데이터 모델 (Postgres, RLS 적용)

```sql
-- 유저·그래프
users(id, nickname, level enum('beginner','experienced'), created_at)
edges(follower_id, followee_id, state enum('following','mutual'), origin enum('invite','resonance','relay'), created_at)
  -- DM 게이트 (§6-3): mutual 이거나 resonance_log에 두 유저 조합 존재 시에만 개설 허용

-- 러닝 (핵심 테이블)
runs(id, user_id, started_at, duration_sec, distance_m, mode enum('episode','free'),
     episode_id, resonance_sec, completed bool, partial bool,
     cadence_blob bytea,        -- 1Hz int8 배열 압축(delta+zstd): 30분≈2KB
     story_clip_url,            -- 쿨다운 음성 한 마디 (Storage)
     visibility enum('private','pacemates','public') default 'pacemates')
  -- 위치: 기본 비저장. route_blob은 opt-in 컬럼(별도 동의)

-- 고스트 = runs의 뷰 + 재생 메타
ghost_events(run_id, t_sec, type enum('voice','slowdown'), payload)

-- 공명·응원·릴레이
resonance_log(run_id, partner_run_id, partner_user_id, seconds, kind enum('live','ghost'))
cheers(id, from_user, to_user, to_run_id, sound_pack_id, state enum('queued','bridged'), created_at)
  -- state='queued' → 다음 러닝 시작 시 재생되면 'bridged' (§5 이월 규칙)
relay_chain(id, first_run_id, matched_to_run_id, matched_at)
  -- RelayMatcher: 신규 유저 첫 세션 요청 시 최근 첫 러닝 풀에서 |Δspm|≤10 매칭, 2분 미만 데이터 제외

-- 여정·이벤트
journey(pair_key, total_m, route_id, updated_at)   -- pair_key = sorted(user_a,user_b) | solo
events(user_id, name, props jsonb, t)               -- 지표 트리 원천 (§7)
```

---

## 5. 서버 로직 (Edge Functions)

| 함수 | 트리거 | 동작 |
|---|---|---|
| `onRunUploaded` | runs INSERT | 여정 갱신 → 고스트 알림 생성("네 리듬과 달렸어") → 릴레이 매칭 갱신 → 카드 생성 |
| `relayMatch` | 신규 유저 세션 요청 | 첫 러닝 풀 조회 → 케이던스 유사 매칭 → GhostFile URL 반환 |
| `notifyDigest` | cron 1일 1회 + 즉시성 예외 | 알림 인벤토리 규칙: 응원 도착=즉시 푸시(내용은 예고만, §5 이월) / 릴레이·"함께 달린 사람"=일일 다이제스트 / 동일인 알림 일 3회 묶음 |
| `liveChannel` (v1.1) | WS 채널 | 메시지: `{type: cadence, spm, t}` 1Hz / `{type: cheer}` / `{type: leave, cheerAttached}` — 오디오 무전송 |

---

## 6. 플랫폼 제약·리스크 및 대응

| 리스크 | 내용 | 대응 |
|---|---|---|
| 백그라운드 생존 | 화면 꺼짐·주머니 상태에서 오디오+모션 유지 | AVAudioSession .playback 카테고리(오디오 앱은 백그라운드 허용) + CMPedometer는 백그라운드 동작. GPS 미사용 시 배터리 부담↓ |
| 이어폰 꼭지 이벤트 | AirPods 탭/스템 제스처의 앱 제어 한계 | MPRemoteCommandCenter(재생/일시정지 토글)로 "꼭지 1회" 매핑, 길게 누름은 v1에서 화면 버튼 병행 후 실측 — **착수 초기 스파이크 필요** |
| 스텝 검출 정확도 | 팔 흔들림·주머니 위치별 오차 | CMPedometer(OS 검증치)와 자체 검출 교차 보정, 베타에서 기기별 캘리브레이션 데이터 수집 |
| 오디오 라이선스 | 스템 음원 저작권 | v1은 자체 제작·구매 스템만(외부 음악 스트리밍 결합 금지 — 스포티파이 동시 재생은 mixWithOthers 이슈도 있음) |
| 개인정보 | 음성 조각·케이던스 데이터 | 위치 기본 비저장, 음성은 수신자 한정 + 보존기한, 개인정보처리방침에 명시(멘토링 자문 항목, 신청서 Q4-2와 연결) |

---

## 7. 개발 마일스톤 (모두의창업 라운드 정렬)

| 단계 | 범위 | 완료 기준 (검증 큐 연동) |
|---|---|---|
| **M0 스파이크 (1~2주)** | CadenceEngine 정확도 + AVAudioEngine 템포 동기 + 꼭지 제스처 검증 | 실주행에서 케이던스 오차 ±3spm 이내, 템포 추종 지연 <3초 |
| **M1 사운드 코어** | AudioEngine(D안) + 내 발소리 토글 + 에피소드 1개 | 검증 큐 #1: 러너 3~5명 A/B 청취 → D안 기본값 확정 |
| **M2 세션+고스트** | 상태머신·잔향 판정·GhostEngine·시차 공명 | 검증 큐 #2: 잔향 임계 실주행 튜닝 |
| **M3 루프 완성** | 릴레이·응원·브리지·결과 화면·음성 채집·여정 | 클로즈드 베타 가능 상태 (2R 시제품 지원 시점 정렬) |
| **M4 베타** | 시드 고스트 100개 수집·에피소드 5종·계측 내장 | 검증 큐 #3~5: 완주율·연장률·응답률 측정 개시 |

v1.0 제외 확인(범위표 준수): 라이브 공명·DM·피드는 M4 이후. 서버 실시간 코드는 M4까지 한 줄도 안 씀 — 고스트 중심 설계 덕분.

---

## 8. 미결정 사항 — 레포 감사(2026-08-21)로 일부 해소

1. ~~프레임워크 확인~~ → **해소: Flutter 유지.** 기존 앱은 Flutter + SoLoud(저지연 오디오, 검증됨) + Firebase 풀스택 + 테스트플라이트 파이프라인 가동 중. 네이티브 전환 사유 소멸. §2 스택 표의 "iOS 네이티브/Supabase" 권고는 **Flutter/Firebase 유지**로 대체한다(상세: 레포 감사 보고서).
2. 스템 음원 제작 방식: 사운드 디자이너 외주 1회(에피소드 5종) vs AI 생성+검수 — 미결
3. 워치(케이던스 정밀도·햅틱)는 v1 범위 밖 확정 여부 — 미결
4. ~~백엔드 선택~~ → **해소: Firebase 유지**(Firestore·Functions·FCM 가동 중). 리전·개인정보 보관 정책만 미결.

### 마일스톤 M0 재정의 (감사 반영)
- M0-a: `sensors_plus` 케이던스 스파이크 (오차 ±3spm 실주행 검증)
- M0-b: SoLoud 스템 루프 + 재생속도 BPM 동기 스파이크
- M1: 기존 ResonanceEngine 입력을 페이스→케이던스로 교체 + 고스트 타임라인 입력 확장
