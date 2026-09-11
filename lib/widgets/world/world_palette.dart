import 'package:flutter/material.dart';

/// 러닝 중 세계의 시간대.
///
/// 낮을 넣지 않은 이유: 밝은 배경 위에서는 라임 고리가 힘을 잃고, 스크림을
/// 아무리 두껍게 깔아도 대낮 야외에서 숫자가 이긴다는 보장이 없다. 러닝은
/// 대부분 해 질 녘과 밤에 일어나므로 그 둘부터 제대로 만든다
enum WorldTime { dusk, night }

/// 여의도 한강공원의 색.
///
/// **원칙 하나: 강은 하늘을 담는 그릇이다.** 고잉온의 팔레트는
/// paper·lime·coral·ink 넷뿐이라 파란 강을 넣는 순간 브랜드 밖으로 나간다.
/// 수면색은 언제나 그 시각 하늘의 어두운 판이고, 그래서 노을에는 구릿빛,
/// 밤에는 먹빛이 된다. 물리적으로도 맞고 팔레트도 안 깨진다.
class WorldPalette {
  const WorldPalette({
    required this.skyTop,
    required this.skyMid,
    required this.skyLow,
    required this.cloud,
    required this.cloud2,
    required this.sun,
    required this.sunInner,
    required this.bldA,
    required this.bldB,
    required this.bldC,
    required this.bldTop,
    required this.winOn,
    required this.winOff,
    required this.gold,
    required this.red,
    required this.dome,
    required this.domeBody,
    required this.bridge,
    required this.rail,
    required this.lamp,
    required this.water,
    required this.waterBand,
    required this.sparkle,
    required this.sunPath,
    required this.grass,
    required this.grassDark,
    required this.leaf,
    required this.leafDark,
    required this.trunk,
    required this.blossom,
    required this.reed,
    required this.reedTip,
    required this.pole,
    required this.bench,
    required this.benchTop,
    required this.track,
    required this.line,
    required this.bike,
    required this.night,
  });

  final Color skyTop, skyMid, skyLow;
  final Color cloud, cloud2;
  final Color sun, sunInner;
  final Color bldA, bldB, bldC, bldTop;
  final Color winOn, winOff;
  final Color gold, red, dome, domeBody;
  final Color bridge, rail, lamp;
  final Color water, waterBand, sparkle, sunPath;
  final Color grass, grassDark;
  final Color leaf, leafDark, trunk, blossom;
  final Color reed, reedTip;
  final Color pole, bench, benchTop;
  final Color track, line, bike;

  /// 밤이면 창과 가로등에 불이 들어오고 별이 뜬다
  final bool night;

  static const dusk = WorldPalette(
    skyTop: Color(0xFFEFC072), skyMid: Color(0xFFF0966A), skyLow: Color(0xFFDF6E4E),
    cloud: Color(0xFFF8DCAE), cloud2: Color(0xFFE08A66),
    sun: Color(0xFFFFD27A), sunInner: Color(0xFFFFE09A),
    bldA: Color(0xFFB08768), bldB: Color(0xFF946A4E), bldC: Color(0xFF79523C),
    bldTop: Color(0xFFC79A78),
    winOn: Color(0xFFFFDC96), winOff: Color(0xFF5E4030),
    gold: Color(0xFFF2C878), red: Color(0xFFE85A3E),
    dome: Color(0xFF8FAE3C), domeBody: Color(0xFFCFB08E),
    bridge: Color(0xFF6E5040), rail: Color(0xFFF2D6A6), lamp: Color(0xFFFFE3A6),
    water: Color(0xFFCE8657), waterBand: Color(0xFFB06A46),
    sparkle: Color(0xFFFFD79A), sunPath: Color(0xFFFFCE86),
    grass: Color(0xFF749121), grassDark: Color(0xFF4E6800),
    leaf: Color(0xFF5E7C12), leafDark: Color(0xFF44600A),
    trunk: Color(0xFF5A4030), blossom: Color(0xFFF8AC96),
    reed: Color(0xFFDCA75E), reedTip: Color(0xFFFFD99E),
    pole: Color(0xFF6B4E3E), bench: Color(0xFF6B4E3E), benchTop: Color(0xFF8A6850),
    track: Color(0xFFB44E36), line: Color(0xFFF6E6D2), bike: Color(0xFF4E6800),
    night: false,
  );

  static const nightTime = WorldPalette(
    skyTop: Color(0xFF0B0A07), skyMid: Color(0xFF131209), skyLow: Color(0xFF2B2113),
    cloud: Color(0xFF1C1A11), cloud2: Color(0xFF15130B),
    sun: Color(0xFFE9E3D0), sunInner: Color(0xFFF4F0E2),
    bldA: Color(0xFF23200F), bldB: Color(0xFF1B1809), bldC: Color(0xFF141105),
    bldTop: Color(0xFF2C2814),
    winOn: Color(0xFFF0C878), winOff: Color(0xFF0C0A04),
    gold: Color(0xFF3A3117), red: Color(0xFF3A1A12),
    dome: Color(0xFF2E3A12), domeBody: Color(0xFF282318),
    bridge: Color(0xFF191509), rail: Color(0xFF3E3520), lamp: Color(0xFFFFDF9E),
    water: Color(0xFF0A0C06), waterBand: Color(0xFF070904),
    sparkle: Color(0xFFD8AC5C), sunPath: Color(0xFFC9A45C),
    grass: Color(0xFF1F2C08), grassDark: Color(0xFF151E05),
    leaf: Color(0xFF1E2A08), leafDark: Color(0xFF141C04),
    trunk: Color(0xFF191308), blossom: Color(0xFF6E4038),
    reed: Color(0xFF2B2415), reedTip: Color(0xFF7A6238),
    pole: Color(0xFF2A2314), bench: Color(0xFF2A2314), benchTop: Color(0xFF3A3120),
    track: Color(0xFF2E1A12), line: Color(0xFF7A6C58), bike: Color(0xFF1B2606),
    night: true,
  );

  static WorldPalette of(WorldTime t) =>
      t == WorldTime.night ? nightTime : dusk;

  /// 실제 시각으로 고른다. 노을이 기본이고, 해가 진 뒤에는 밤이다.
  /// 경계를 넉넉히 잡은 이유: 6시 59분과 7시 1분의 화면이 달라 보이면
  /// 사람은 그것을 버그로 읽는다 — 전환은 다음 러닝에서 일어나야 한다
  static WorldTime timeFor(DateTime now) {
    final h = now.hour;
    return (h >= 19 || h < 5) ? WorldTime.night : WorldTime.dusk;
  }

  /// 스크림 색 — 하늘의 가장 어두운 끝을 쓴다. 검정을 깔면 하늘에서
  /// 잘려나간 것처럼 보이고, 하늘색을 깔면 해 질 녘이 화면 위아래로
  /// 번지는 것처럼 보인다.
  ///
  /// 글자·관계색 같은 **UI 색은 여기 두지 않는다** — `theme.dart`의
  /// [GoRunDark]가 유일한 출처다. 여기는 그림의 색만 산다
  static Color veil(WorldTime t) =>
      t == WorldTime.night ? const Color(0xFF080805) : const Color(0xFF3C1A10);
}
