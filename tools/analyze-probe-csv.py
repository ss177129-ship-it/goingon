#!/usr/bin/env python3
"""M0 스파이크 CSV 판정기 — 실주행 데이터가 도착하면 이것으로 잰다.

케이던스(M0-a):
    ./tools/analyze-probe-csv.py cadence cadence_probe.csv --counts 41,44,45,43
  --counts는 랩 구간마다 입으로 센 **한 발** 수(구간 순서대로). 양발 spm은
  스크립트가 ×2 해서 구간 길이로 나눈다. 랩 마크가 구간 경계다.
  --counts를 생략하면 구간별 엔진 값만 요약한다(수동 대조 없이 형태만 보기).

템포(M0-b):
    ./tools/analyze-probe-csv.py tempo tempo_probe.csv

판정 기준은 docs/m0_spike.md의 표와 같다: spm ±3, gait 전환 10초, 지터 p95 30ms.
"""
import argparse
import csv
import statistics
import sys
from datetime import datetime

PASS, FAIL = "통과", "미달"


def parse_iso(s):
    return datetime.fromisoformat(s.strip())


def read_rows(path):
    """프로브가 append 모드로 쓰므로 한 파일에 세션이 여러 개일 수 있다.
    '# session' 줄로 갈라 마지막 세션만 본다."""
    sessions, cur = [], []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("# session"):
                if cur:
                    sessions.append(cur)
                cur = []
                continue
            if not line or line.startswith("type,") or line.startswith("planned,"):
                continue
            cur.append(line)
    if cur:
        sessions.append(cur)
    if not sessions:
        sys.exit(f"✗ {path}: 데이터 줄이 없습니다")
    return sessions


def _announce(sessions, i):
    which = "마지막" if i == -1 else f"{i + 1}번째"
    print(f"세션 {len(sessions)}개 발견 — {which} 세션을 분석합니다\n")


def analyze_cadence(path, counts, session_index):
    sessions = read_rows(path)
    _announce(sessions, session_index)
    rows = list(csv.reader(sessions[session_index]))

    steps = [parse_iso(r[1]) for r in rows if r[0] == "step"]
    laps = [parse_iso(r[1]) for r in rows if r[0] == "lap"]
    samples = [(parse_iso(r[1]), float(r[2]), float(r[3]), r[4])
               for r in rows if r[0] == "sample" and r[2]]
    if not samples:
        sys.exit("✗ sample 줄이 없습니다 — 측정이 시작되지 않았을 수 있습니다")

    t0, t1 = samples[0][0], samples[-1][0]
    print(f"길이 {(t1 - t0).total_seconds():.0f}초 · "
          f"엔진 스텝 {len(steps)}개 · 랩 마크 {len(laps)}개")

    # ── 구간: 랩 마크로 자른다. 랩이 없으면 전체를 한 구간으로. ──────
    bounds = [t0] + laps + [t1]
    segs = [(bounds[i], bounds[i + 1]) for i in range(len(bounds) - 1)]
    segs = [(a, b) for a, b in segs if (b - a).total_seconds() >= 5]

    if counts and len(counts) != len(segs):
        print(f"\n⚠ 수동 카운트 {len(counts)}개 vs 구간 {len(segs)}개 — "
              f"개수가 다릅니다. 앞에서부터 짝지어 비교합니다.")

    print(f"\n{'구간':>4} {'길이':>7} {'엔진 spm':>9} {'스텝':>6} "
          f"{'수동 spm':>9} {'오차':>7}  판정")
    print("-" * 60)
    worst, errs = 0.0, []
    for i, (a, b) in enumerate(segs):
        dur = (b - a).total_seconds()
        seg_spm = [s for t, s, _, _ in samples if a <= t <= b and s > 0]
        seg_steps = [t for t in steps if a <= t <= b]
        engine = statistics.mean(seg_spm) if seg_spm else 0.0
        line = f"{i + 1:>4} {dur:>6.0f}s {engine:>9.1f} {len(seg_steps):>6}"
        if counts and i < len(counts):
            manual = counts[i] * 2 * 60 / dur   # 한 발 카운트 → 양발 spm
            err = engine - manual
            errs.append(abs(err))
            worst = max(worst, abs(err))
            verdict = PASS if abs(err) <= 3 else FAIL
            line += f" {manual:>9.1f} {err:>+7.1f}  {verdict}"
        print(line)

    # ── gait 전환 ────────────────────────────────────────────────
    print("\ngait 전환:")
    prev, changed_at = samples[0][3], samples[0][0]
    transitions = []
    for t, _, _, g in samples:
        if g != prev:
            transitions.append((prev, g, (t - changed_at).total_seconds()))
            prev, changed_at = g, t
    if not transitions:
        print(f"  전환 없음 (계속 {prev})")
    for a, b, held in transitions:
        print(f"  {a} → {b}  (직전 상태 {held:.0f}초 유지)")

    print("\n" + "=" * 60)
    if counts:
        print(f"최대 오차 {worst:.1f}spm · 평균 {statistics.mean(errs):.1f}spm "
              f"→ M0-a spm 판정: {PASS if worst <= 3 else FAIL} (기준 ±3)")
        if worst > 3:
            print("\n튜닝 순서 (docs/m0_spike.md):")
            print("  1) cadence_engine.dart의 kThresholdK — 현재 1.2, 범위 1.0~1.6")
            print("     · 엔진 스텝 > 수동  → 노이즈를 걸음으로 셈. K를 올린다")
            print("     · 엔진 스텝 < 수동  → 약한 착지를 놓침. K를 내린다")
            print("  2) 그래도 안 되면 검출 창(kEnvelopeWindow 2초)과 kMinStepMag(1.5)")
            print("  3) 그래도 안 되면 CMPedometer 플랫폼 채널로 이관")
    else:
        print("수동 카운트(--counts)가 없어 ±3spm 판정은 하지 못했습니다.")


def analyze_tempo(path, session_index):
    sessions = read_rows(path)
    _announce(sessions, session_index)
    rows = list(csv.reader(sessions[session_index]))
    jitters = [abs(float(r[2])) for r in rows if len(r) >= 3 and r[2]]
    if len(jitters) < 20:
        sys.exit(f"✗ 지터 표본이 {len(jitters)}개뿐입니다 — 20개 이상 필요")

    js = sorted(jitters)
    p50 = js[len(js) // 2]
    p95 = js[int(len(js) * 0.95)]
    print(f"비트 {len(js)}개 · 중앙값 {p50:.1f}ms · p95 {p95:.1f}ms · "
          f"최대 {js[-1]:.1f}ms")
    print("=" * 60)
    print(f"M0-b 지터 판정: {PASS if p95 <= 30 else FAIL} (기준 p95 30ms)")
    if p95 > 30:
        print("\nDart Timer의 한계입니다. 메트로놈을 SoLoud 오디오 스레드")
        print("스케줄링으로 이관해야 합니다 (docs/m0_spike.md §3).")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind", choices=["cadence", "tempo"])
    ap.add_argument("csv")
    ap.add_argument("--counts", help="랩 구간별 수동 카운트(한 발), 쉼표 구분")
    ap.add_argument("--session", type=int, default=-1,
                    help="분석할 세션 번호(1부터). 기본은 마지막")
    a = ap.parse_args()

    idx = a.session - 1 if a.session > 0 else -1
    if a.kind == "cadence":
        counts = [int(x) for x in a.counts.split(",")] if a.counts else None
        analyze_cadence(a.csv, counts, idx)
    else:
        analyze_tempo(a.csv, idx)


if __name__ == "__main__":
    main()
