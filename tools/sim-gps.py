#!/usr/bin/env python3
"""시뮬레이터에 GPS 경로를 흘려넣고 결과를 회수·분석한다.

야외에 나가지 않고 거리·페이스 로직을 검증하기 위한 도구. 정답(이동 거리)을
알고 있는 경로를 만들어 넣으므로, 앱이 계산한 값과 바로 대조할 수 있다.

  ./tools/sim-gps.py list                      시나리오 목록
  ./tools/sim-gps.py run track400 --laps 10    경로를 흘려넣기 (앱이 떠 있어야 함)
  ./tools/sim-gps.py collect                   결과 CSV 회수 + 분석
  ./tools/sim-gps.py gpx track400 out.gpx      Xcode용 GPX 파일로 뽑기

전제: `lib/main_gps_probe.dart`가 시뮬레이터에 설치돼 실행 중일 것.
      위치 권한은 `simctl privacy grant location-always`로 미리 부여할 것.

한계 — 이걸로 못 보는 것:
  * horizontalAccuracy를 조종할 수 없다. 정확도 관련 필터(감사 #2, 정확도 30m
    상한)는 `test/run_accumulator_test.dart`의 합성 Position이 담당한다
  * 시뮬레이터는 실기기처럼 앱을 억제하지 않는다. 배경 동작(감사 #15)은
    실기기에서만 제대로 재현된다 — 실제로 실기기에서 35초 공백을 관측했다
"""
import argparse
import math
import subprocess
import sys
from pathlib import Path

BUNDLE = "com.chanwoong.goingon"
EARTH_R = 6378137.0

# 서울시청 근처 평지 — test/fixtures/run_fixtures.dart와 같은 기준점
BASE_LAT, BASE_LON = 37.5665, 126.9780


def offset(lat, lon, north_m, east_m):
    """기준점에서 북/동으로 이동한 좌표."""
    dlat = north_m / EARTH_R * 180 / math.pi
    dlon = east_m / (EARTH_R * math.cos(math.radians(lat))) * 180 / math.pi
    return lat + dlat, lon + dlon


def haversine(a, b):
    (lat1, lon1), (lat2, lon2) = a, b
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R * math.asin(math.sqrt(h))


# ── 시나리오 ─────────────────────────────────────────────────────────

def track400(laps=10, points_per_lap=48):
    """둘레 400m 원형 트랙을 laps바퀴. 정답 = 400 × laps.

    다각형으로 근사하므로 실제 길이는 원둘레보다 아주 조금 짧다(48각형이면
    0.07%). 곡선 구간이라 기준점 유지 방식이 코드를 짧게 잡는지도 함께 드러난다.
    """
    r = 400 / (2 * math.pi)
    pts = []
    for lap in range(laps):
        for i in range(points_per_lap):
            t = 2 * math.pi * i / points_per_lap
            pts.append(offset(BASE_LAT, BASE_LON, r * math.cos(t), r * math.sin(t)))
    pts.append(pts[0])
    return pts


def straight(meters=1000, step=10):
    """정북으로 일직선. 정답이 정확히 meters — 보간 오차가 없는 기준 시나리오."""
    return [offset(BASE_LAT, BASE_LON, d, 0) for d in range(0, meters + step, step)]


def stationary(minutes=10, drift_m=8, step_s=3):
    """제자리에서 GPS 지터만. 정답 = 0m.

    실제 정지 상태의 좌표 흔들림을 흉내낸다. 감사 #4가 이 시나리오다.
    """
    import random
    rng = random.Random(7)
    n = int(minutes * 60 / step_s)
    pts = []
    for _ in range(n):
        pts.append(offset(BASE_LAT, BASE_LON,
                          (rng.random() - .5) * 2 * drift_m,
                          (rng.random() - .5) * 2 * drift_m))
    return pts


def tunnel(before=200, gap=300, after=200, step=10):
    """중간이 비는 직선 경로. 정답 = before + gap + after.

    공백 구간을 직선으로 이어 붙이는지 확인한다. simctl은 웨이포인트를
    보간하므로 '공백'을 만들려면 간격을 크게 벌린다.
    """
    pts = [offset(BASE_LAT, BASE_LON, d, 0) for d in range(0, before + step, step)]
    pts.append(offset(BASE_LAT, BASE_LON, before + gap, 0))  # 한 번에 건너뜀
    pts += [offset(BASE_LAT, BASE_LON, before + gap + d, 0)
            for d in range(step, after + step, step)]
    return pts


SCENARIOS = {
    "track400": (track400, "둘레 400m 트랙 (기본 10바퀴)"),
    "straight": (straight, "정북 직선 (기본 1000m)"),
    "stationary": (stationary, "제자리 지터 (기본 10분)"),
    "tunnel": (tunnel, "중간이 비는 직선 (기본 700m)"),
}


def path_length(pts):
    """웨이포인트를 이은 궤적의 기하학적 길이(m)."""
    return sum(haversine(pts[i - 1], pts[i]) for i in range(1, len(pts)))


def truth(name, pts):
    """**앱이 내놔야 할** 거리(m).

    보통은 궤적 길이지만 `stationary`는 다르다. 지터는 좌표가 흔들릴 뿐
    사람은 제자리에 있으므로 정답은 0이다 — 궤적 길이(수백 m)를 정답으로
    삼으면 정확히 거꾸로 채점하게 된다.
    """
    if name == "stationary":
        return 0.0
    return path_length(pts)


# ── 실행 ─────────────────────────────────────────────────────────────

def booted_device():
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "booted"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "(Booted)" in line and "(" in line:
            return line.split("(")[1].split(")")[0]
    sys.exit("부팅된 시뮬레이터가 없습니다.")


def cmd_run(args):
    fn, _ = SCENARIOS[args.scenario]
    kwargs = {}
    if args.laps and args.scenario == "track400":
        kwargs["laps"] = args.laps
    if args.minutes and args.scenario == "stationary":
        kwargs["minutes"] = args.minutes
    pts = fn(**kwargs)
    dev = booted_device()

    print(f"시나리오 : {args.scenario}")
    print(f"웨이포인트: {len(pts)}개")
    print(f"정답 거리 : {truth(args.scenario, pts):.1f}m")
    print(f"속도      : {args.speed} m/s")
    est = truth(args.scenario, pts) / args.speed if args.speed else 0
    print(f"예상 소요 : {est:.0f}초 ({est/60:.1f}분)")
    print()

    subprocess.run(["xcrun", "simctl", "privacy", dev, "grant",
                    "location-always", BUNDLE], check=False)

    waypoints = "\n".join(f"{la:.7f},{lo:.7f}" for la, lo in pts)
    proc = subprocess.Popen(
        ["xcrun", "simctl", "location", dev, "start",
         f"--speed={args.speed}", f"--interval={args.interval}", "-"],
        stdin=subprocess.PIPE, text=True)
    proc.communicate(waypoints)
    print("경로 재생을 시작했습니다. 끝나면 `collect`로 회수하세요.")


def cmd_collect(args):
    dev = booted_device()
    out = subprocess.run(
        ["xcrun", "simctl", "get_app_container", dev, BUNDLE, "data"],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("앱 컨테이너를 못 찾았습니다. 앱이 설치돼 있나요?")
    csv = Path(out.stdout.strip()) / "Documents" / "gps_probe.csv"
    if not csv.exists():
        sys.exit(f"측정 파일이 없습니다: {csv}")
    dest = Path(args.out)
    dest.write_bytes(csv.read_bytes())
    print(f"회수: {dest}  ({csv.stat().st_size}바이트)\n")
    analyze(dest)


def analyze(path):
    rows = [l.strip().split(",") for l in path.read_text().splitlines()[1:] if l.strip()]
    if not rows:
        print("데이터가 없습니다.")
        return
    fixes = [r for r in rows if r[5] != "MARKER"]
    marks = [r for r in rows if r[5] == "MARKER"]

    counts = {}
    for r in fixes:
        counts[r[5]] = counts.get(r[5], 0) + 1

    cur = float(fixes[-1][7]) if fixes else 0
    leg = float(fixes[-1][8]) if fixes else 0

    print(f"fix {len(fixes)}개 · 마커 {len(marks)}개")
    print(f"수정 후 누적 : {cur:.1f}m")
    print(f"수정 전 누적 : {leg:.1f}m")
    print(f"차이         : {cur - leg:+.1f}m\n")
    print("판정별 분포:")
    for k, v in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {k:<26} {v}")
    if marks:
        print("\n마커:")
        for m in marks:
            print(f"  {m[9]:<12} 수정후 {m[7]}m / 수정전 {m[8]}m")


def cmd_gpx(args):
    fn, _ = SCENARIOS[args.scenario]
    pts = fn()
    body = "\n".join(
        f'    <wpt lat="{la:.7f}" lon="{lo:.7f}"><time>2026-08-16T00:{i//60:02d}:{i%60:02d}Z</time></wpt>'
        for i, (la, lo) in enumerate(pts))
    Path(args.out).write_text(
        '<?xml version="1.0"?>\n<gpx version="1.1" creator="goingon">\n'
        f'{body}\n</gpx>\n')
    print(f"{args.out} 생성 · 웨이포인트 {len(pts)}개 · 정답 {truth(args.scenario, pts):.1f}m")
    print("Xcode → Product → Scheme → Edit Scheme → Run → Options → Default Location 에서 쓸 수 있습니다.")


def cmd_list(_):
    for k, (fn, desc) in SCENARIOS.items():
        pts = fn()
        t, g = truth(k, pts), path_length(pts)
        note = f"정답 {t:.0f}m"
        if abs(t - g) > 1:
            note += f" (궤적 길이는 {g:.0f}m — 지터일 뿐 이동이 아님)"
        print(f"  {k:<12} {desc}\n               {note}")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list").set_defaults(func=cmd_list)

    r = sub.add_parser("run")
    r.add_argument("scenario", choices=SCENARIOS)
    r.add_argument("--speed", type=float, default=3.33, help="m/s (기본 3.33 = 5'00\"/km)")
    r.add_argument("--interval", type=float, default=1, help="fix 간격(초)")
    r.add_argument("--laps", type=int, help="track400 전용")
    r.add_argument("--minutes", type=int, help="stationary 전용")
    r.set_defaults(func=cmd_run)

    c = sub.add_parser("collect")
    c.add_argument("--out", default="gps_probe.csv")
    c.set_defaults(func=cmd_collect)

    g = sub.add_parser("gpx")
    g.add_argument("scenario", choices=SCENARIOS)
    g.add_argument("out")
    g.set_defaults(func=cmd_gpx)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
