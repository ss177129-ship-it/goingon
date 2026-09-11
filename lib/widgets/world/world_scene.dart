import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'world_palette.dart';

/// 세계는 390 × 844 좌표계에서 그린다. 화면이 그보다 넓으면 통째로 확대한다 —
/// 픽셀 한 칸이 기기마다 다른 것보다, 세계의 비례가 어디서나 같은 편이 낫다
const double kTile = 390;
const double kDesignHeight = 844;

/// 픽셀 한 칸. 390 / 3 = 130칸이 한 주기다
const double kPx = 3;

/// 격자는 **반 칸**이다.
///
/// 한 칸(kPx)으로 맞추면 `kPx / 2`짜리가 전부 한 칸으로 부풀어, 나무 줄기의
/// 볕이 줄기를 통째로 덮고 가로등의 볕이 기둥 옆에 가서 선다. 하이라이트는
/// 반 칸이어야 하이라이트다
const double _unit = kPx / 2;

double _snap(double v) => (v / _unit).roundToDouble() * _unit;

/// 크기는 0으로 사라지면 안 된다 — 반 칸이 바닥이다
double _snapSize(double v) {
  final q = _snap(v);
  return q < _unit ? _unit : q;
}

/// 씨앗을 고정한 난수 — 같은 도시가 매번 같은 모습이어야 한다.
/// 실행마다 건물이 바뀌면 그건 다른 동네다
class _Rng {
  _Rng(this._s);
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }
}

class _Brush {
  final Canvas c;
  _Brush(this.c);

  final Paint _p = Paint()..isAntiAlias = false;

  void px(double x, double y, double w, double h, Color col, [double o = 1]) {
    _p.color = o >= 1 ? col : col.withValues(alpha: o);
    c.drawRect(
        Rect.fromLTWH(_snap(x), _snap(y), _snapSize(w), _snapSize(h)), _p);
  }

  /// 가운데 정렬된 가로줄을 쌓아 형태를 만든다.
  ///
  /// **원반을 흩뿌리지 않는 이유가 전부 여기 있다.** 난수 위치의 원을 겹치면
  /// 나무가 뭉개진 덩어리로 보이고, 확대하면 그게 그대로 드러난다.
  /// 줄의 폭만 정해주면 형태가 무너지지 않는다
  void rows(double cx, double top, List<int> widths, Color col, [double o = 1]) {
    for (var i = 0; i < widths.length; i++) {
      final w = widths[i];
      if (w <= 0) continue;
      px(cx - (w * kPx) / 2, top + i * kPx, w * kPx, kPx, col, o);
    }
  }

  void disc(double cx, double cy, int rp, Color col, [double o = 1]) {
    for (var y = -rp; y <= rp; y++) {
      final w = math.sqrt((rp * rp - y * y).toDouble()).floor() * 2 + 1;
      px(cx - (w * kPx) / 2, cy + y * kPx, w * kPx, kPx, col, o);
    }
  }
}

Color _mix(Color hex, double amt) {
  int f(int v) => (v + (255 * amt)).round().clamp(0, 255);
  return Color.fromARGB(255, f((hex.toARGB32() >> 16) & 255),
      f((hex.toARGB32() >> 8) & 255), f(hex.toARGB32() & 255));
}

/* ══════════════ 한 주기(390px = 130칸)를 손으로 짠 배치 ══════════════
   원칙 셋 — 이음매는 비운다 / 높이는 무리 지어 오르내린다 /
   랜드마크 옆은 낮게 눌러 홀로 서게 한다                              */

class _Bld {
  const _Bld(this.x, {this.w = 0, this.h = 0, this.f = 0, this.roof = '', this.lit = 0, this.landmark});
  final int x, w, h, f;
  final String roof;
  final double lit;
  final String? landmark;
}

const _skyPlan = <_Bld>[
  _Bld(4, w: 8, h: 15, f: 1, roof: 'ac', lit: .32),
  _Bld(13, w: 7, h: 21, f: 0, roof: 'ant', lit: .50),
  _Bld(22, landmark: 'tower63'), // 가장 높은 닻
  _Bld(33, w: 8, h: 16, f: 2, lit: .28), // 탑 옆은 눌러둔다
  _Bld(42, w: 10, h: 27, f: 0, roof: 'tank', lit: .55),
  _Bld(53, w: 7, h: 22, f: 1, lit: .40),
  _Bld(63, landmark: 'assembly'), // 낮고 넓은 대비
  _Bld(85, w: 8, h: 25, f: 2, roof: 'ant', lit: .45),
  _Bld(94, w: 8, h: 34, f: 0, roof: 'tank', lit: .60), // 두 번째 봉우리
  _Bld(103, w: 6, h: 19, f: 1, lit: .34),
  _Bld(110, w: 11, h: 30, f: 2, roof: 'ac', lit: .52),
  _Bld(122, w: 5, h: 13, f: 0, lit: .28), // 이음매 앞에서 낮아진다
];

class _Obj {
  const _Obj(this.x, this.t, {this.big = 0, this.blossom = false});
  final int x;
  final String t;
  final int big;
  final bool blossom;
}

const _bankPlan = <_Obj>[
  _Obj(3, 'reeds'),
  _Obj(17, 'tree', big: 1, blossom: true),
  _Obj(29, 'lamp'),
  _Obj(37, 'reeds'),
  _Obj(51, 'bench'),
  _Obj(62, 'tree'), // 작은 나무와
  _Obj(70, 'tree', big: 1, blossom: true), // 큰 나무가 한 무리
  _Obj(82, 'reeds'),
  _Obj(96, 'lamp'),
  _Obj(104, 'bench'),
  _Obj(115, 'tree', big: 1),
];

const _islandPlan = <int>[20, 25, 29, 34, 40, 45, 49];

/* ══════════════ 스프라이트 ══════════════ */

void _tree(_Brush b, double cx, double groundY, int scale, WorldPalette p,
    bool blossom) {
  final th = kPx * (scale == 0 ? 4 : 5);
  b.px(cx - kPx / 2, groundY - th, kPx, th, p.trunk);
  b.px(cx - kPx / 2, groundY - th, kPx / 2, th, _mix(p.trunk, -.06));
  final top = groundY - th - kPx * (scale == 0 ? 6 : 7);
  final shape = scale == 0 ? const [3, 5, 7, 7, 5, 3] : const [3, 7, 9, 9, 7, 5, 3];
  b.rows(cx, top, shape, p.leaf);
  b.rows(cx - kPx, top + kPx,
      shape.map((w) => math.max(0, w - 5)).toList(), p.leafDark, .6);
  // 해가 오른쪽에 있다 — 오른면이 밝다. 픽셀아트가 만들어진 것처럼 보이는지는
  // 대부분 이 한 가지가 가른다
  b.rows(cx + kPx * 1.5, top + kPx,
      shape.map((w) => math.max(0, w - 6)).toList(), _mix(p.leaf, .09), .75);
  if (blossom) {
    b.px(cx - kPx * 3, top + kPx * 2, kPx * 2, kPx, p.blossom, .9);
    b.px(cx + kPx * 2, top + kPx, kPx * 2, kPx, p.blossom, .9);
    b.px(cx - kPx, top, kPx * 2, kPx, p.blossom, .8);
  }
}

void _reeds(_Brush b, double x, double groundY, WorldPalette p) {
  const hs = [7, 10, 8, 11, 9];
  for (var i = 0; i < hs.length; i++) {
    final rx = x + i * kPx * 2, h = hs[i] * kPx;
    b.px(rx, groundY - h, kPx, h, p.reed, .95);
    b.px(rx - kPx, groundY - h - kPx * 2, kPx * 3, kPx * 2, p.reedTip, .95);
    b.px(rx, groundY - h - kPx * 2, kPx, kPx, _mix(p.reedTip, .12), .95);
    b.px(rx - kPx, groundY - h - kPx, kPx, kPx, _mix(p.reedTip, -.08), .8);
  }
}

void _bench(_Brush b, double x, double groundY, WorldPalette p) {
  b.px(x, groundY - kPx * 6, kPx * 8, kPx, p.benchTop);
  b.px(x, groundY - kPx * 4, kPx * 8, kPx, p.benchTop);
  b.px(x, groundY - kPx * 3, kPx * 8, kPx, p.bench);
  b.px(x + kPx, groundY - kPx * 3, kPx, kPx * 3, p.bench);
  b.px(x + kPx * 6, groundY - kPx * 3, kPx, kPx * 3, p.bench);
  b.px(x, groundY - kPx * 6, kPx, kPx * 3, p.bench);
  b.px(x + kPx * 7, groundY - kPx * 6, kPx, kPx * 3, p.bench);
  b.px(x + kPx, groundY - kPx * 6, kPx * 6, kPx / 2, _mix(p.benchTop, .10), .8);
  b.px(x + kPx, groundY - kPx * 4, kPx * 6, kPx / 2, _mix(p.benchTop, .10), .7);
  b.px(x, groundY, kPx * 8, kPx / 2, const Color(0xFF000000), .16);
}

/// 가로등 — **라임 등과 코랄 등이 한 쌍.** 앱 아이콘(두 원)이 거리에 서 있다.
/// 브랜드를 하늘에 올리면 해가 두 개로 읽힌다. 땅에서 나르는 게 맞다
void _lamppost(_Brush b, double x, double groundY, WorldPalette p) {
  b.px(x, groundY - kPx * 16, kPx, kPx * 16, p.pole);
  b.px(x - kPx * 2, groundY - kPx * 16, kPx * 5, kPx, p.pole);
  b.px(x + kPx / 2, groundY - kPx * 16, kPx / 2, kPx * 16, _mix(p.pole, .08), .7);
  b.px(x - kPx / 2, groundY - kPx, kPx * 2, kPx, _mix(p.pole, -.05));
  b.px(x - kPx * 2, groundY - kPx * 15, kPx * 2, kPx, const Color(0xFFC5E040));
  b.px(x + kPx * 2, groundY - kPx * 15, kPx * 2, kPx, const Color(0xFFF05840));
  if (p.night) {
    _glow(b.c, Offset(x - kPx, groundY - kPx * 15), kPx * 9,
        const Color(0xFFC5E040), .55);
    _glow(b.c, Offset(x + kPx * 3, groundY - kPx * 15), kPx * 9,
        const Color(0xFFF05840), .55);
  }
}

/// 빛 번짐은 원반을 쌓지 않고 그라디언트 한 장으로 그린다.
/// 원반으로 그리면 등 하나에 rect가 150개씩 붙어 굽는 시간이 폭발한다
void _glow(Canvas c, Offset at, double r, Color col, double o) {
  final rect = Rect.fromCircle(center: at, radius: r);
  c.drawRect(
    rect,
    Paint()
      ..isAntiAlias = false
      ..shader = RadialGradient(colors: [
        col.withValues(alpha: o),
        col.withValues(alpha: 0),
      ]).createShader(rect),
  );
}

/* ══════════════ 랜드마크 ══════════════ */

void _tower63(_Brush b, double x, double base, WorldPalette p) {
  // 46이면 왕관(−4)과 첨탑(−9)이 150짜리 층 위로 잘려 나간다.
  // 40이면 첨탑 끝이 y=3에 들어오고, 두 번째로 높은 건물(34)보다 여전히 높다
  const h = kPx * 40, w = kPx * 8;
  b.px(x, base - h, w, h, p.gold);
  b.px(x + kPx, base - h - kPx * 4, w - kPx * 2, kPx * 4, p.gold, .9);
  b.px(x + kPx * 2, base - h - kPx * 7, w - kPx * 4, kPx * 3, p.gold, .75);
  b.px(x + w - kPx, base - h, kPx, h, _mix(p.gold, .10));
  b.px(x, base - h, kPx / 2, h, _mix(p.gold, -.07));
  for (var y = base - h + kPx * 3; y < base - kPx * 3; y += kPx * 3) {
    b.px(x + kPx, y, w - kPx * 2, kPx, p.winOn, .35);
  }
  b.px(x + kPx * 2, base - h - kPx * 9, kPx / 2, kPx * 3, p.bldC);
}

void _assembly(_Brush b, double x, double base, WorldPalette p) {
  const w = kPx * 20, h = kPx * 10;
  b.px(x, base - h, w, h, p.domeBody);
  for (var cx = x + kPx * 2; cx < x + w - kPx * 2; cx += kPx * 3) {
    b.px(cx, base - h + kPx * 2, kPx, h - kPx * 2, p.bldC, .3);
  }
  b.rows(x + w / 2, base - h - kPx * 5, const [5, 9, 11, 11, 13], p.dome);
  b.rows(x + w / 2 + kPx * 1.5, base - h - kPx * 4, const [3, 5, 5],
      _mix(p.dome, .12), .8);
  b.px(x + w / 2 - kPx / 2, base - h - kPx * 7, kPx / 2, kPx * 2, _mix(p.dome, .18));
  b.px(x + w / 2 - kPx * 8, base - h - kPx, kPx * 16, kPx, p.domeBody);
  b.px(x, base - kPx * 2, w, kPx, _mix(p.domeBody, -.06));
}

void _building(_Brush b, double x, double base, WorldPalette p, _Bld d, _Rng r) {
  final w = kPx * d.w, h = kPx * d.h;
  final face = [p.bldA, p.bldB, p.bldC][d.f];
  b.px(x, base - h, w, h, face);
  b.px(x + w - kPx, base - h, kPx, h, _mix(face, .07)); // 오른면 볕
  b.px(x, base - h, kPx, h, _mix(face, -.05)); // 왼면 그늘
  b.px(x, base - h, w, kPx, p.bldTop, .85);
  if (d.roof == 'tank') {
    b.px(x + kPx * 2, base - h - kPx * 3, kPx * 3, kPx * 3, p.bldC);
    b.px(x + kPx * 2, base - h - kPx * 4, kPx * 3, kPx, _mix(p.bldC, .1));
  } else if (d.roof == 'ac') {
    b.px(x + w - kPx * 5, base - h - kPx * 2, kPx * 3, kPx * 2, _mix(face, -.04));
  } else if (d.roof == 'ant') {
    b.px(x + w / 2 - kPx / 2, base - h - kPx * 5, kPx / 2, kPx * 5, p.bldC);
  }
  for (var wy = base - h + kPx * 3; wy < base - kPx * 4; wy += kPx * 4) {
    for (var wx = x + kPx * 2; wx < x + w - kPx * 2; wx += kPx * 3) {
      final on = r.next() < d.lit;
      b.px(wx, wy, kPx, kPx * 2, on ? p.winOn : p.winOff, on ? .85 : .5);
      if (on) b.px(wx, wy, kPx, kPx / 2, _mix(p.winOn, .10), .9);
    }
  }
  b.px(x + kPx * 2, base - kPx * 3, kPx * 3, kPx * 3, p.winOn, .35); // 1층
}

/* ══════════════ 층 ══════════════ */

void paintSkyBits(Canvas c, WorldPalette p, double h) {
  final b = _Brush(c);
  final r = _Rng(808);
  if (p.night) {
    for (var i = 0; i < 52; i++) {
      b.px(r.next() * kTile, r.next() * h * .7, kPx, kPx,
          const Color(0xFFF0EAE0), .18 + r.next() * .5);
    }
  } else {
    for (var i = 0; i < 4; i++) {
      final cx = r.next() * kTile,
          cy = _snap(20 + r.next() * h * .42),
          w = _snap(24 + r.next() * 33);
      b.px(cx, cy, w, kPx * 2, p.cloud, .92);
      b.px(cx + kPx * 3, cy - kPx * 2, w * .5, kPx * 2, p.cloud, .92);
      b.px(cx + w - kPx * 3, cy - kPx * 2, kPx * 3, kPx * 2, _mix(p.cloud, .06), .9);
      b.px(cx + kPx, cy + kPx * 2, w * .75, kPx, p.cloud2, .45);
    }
  }
  // 새 — 사람이 아니면서 이 세계가 살아 있다고 말해주는 유일한 것
  for (var i = 0; i < 5; i++) {
    final bx = _snap(r.next() * kTile), by = _snap(30 + r.next() * h * .34);
    final col = p.night ? const Color(0xFF6E6858) : _mix(p.cloud2, -.1);
    b.px(bx, by, kPx, kPx / 2, col, .75);
    b.px(bx - kPx, by - kPx / 2, kPx, kPx / 2, col, .6);
    b.px(bx + kPx, by - kPx / 2, kPx, kPx / 2, col, .6);
  }
}

void paintSkyline(Canvas c, WorldPalette p, double h) {
  final b = _Brush(c);
  final r = _Rng(7717);
  for (final d in _skyPlan) {
    final x = d.x * kPx;
    if (d.landmark == 'tower63') {
      _tower63(b, x, h, p);
    } else if (d.landmark == 'assembly') {
      _assembly(b, x, h, p);
    } else {
      _building(b, x, h, p, d, r);
    }
  }
}

void paintBridge(Canvas c, WorldPalette p, double h) {
  final b = _Brush(c);
  const deck = kPx * 8;
  b.px(0, deck, kTile, kPx * 3, p.bridge);
  b.px(0, deck - kPx, kTile, kPx, p.rail, .85);
  for (var x = 0.0; x < kTile; x += kPx * 5) {
    b.px(x, deck - kPx, kPx / 2, kPx, _mix(p.rail, -.1), .7);
  }
  for (var x = 0.0; x < kTile; x += kPx * 22) {
    b.px(x, deck + kPx * 3, kPx * 3, h - deck - kPx * 3, p.bridge, .92);
    b.px(x + kPx * 2, deck + kPx * 3, kPx, h - deck - kPx * 3, _mix(p.bridge, .07), .8);
    b.px(x - kPx, h - kPx * 2, kPx * 5, kPx * 2, _mix(p.bridge, -.04), .85);
    b.rows(x + kPx * 1.5, deck - kPx * 5, const [1, 3, 5, 7], p.bridge, .5);
  }
  for (var x = kPx * 3; x < kTile; x += kPx * 11) {
    b.px(x, deck - kPx * 5, kPx, kPx * 5, p.bridge, .9);
    b.px(x - kPx / 2, deck - kPx * 6, kPx * 2, kPx, p.lamp);
    _glow(c, Offset(x, deck - kPx * 6), kPx * 5, p.lamp, .45);
  }
}

void paintWater(Canvas c, WorldPalette p, double h) {
  final b = _Brush(c);
  final r = _Rng(2207);
  b.px(0, 0, kTile, h, p.water);
  for (var y = 0.0; y < h; y += kPx) {
    if (r.next() < .42) b.px(0, y, kTile, kPx, p.waterBand, .12 + (y / h) * .4);
  }
  for (var i = 0; i < 34; i++) {
    b.px(r.next() * kTile, _snap(r.next() * h), _snap(6 + r.next() * 18), kPx,
        p.waterBand, .3);
  }
  for (var i = 0; i < 12; i++) {
    b.px(r.next() * kTile, _snap(r.next() * h * .5), _snap(3 + r.next() * 6), kPx,
        p.sparkle, .5 + r.next() * .4);
  }
  // 건물의 흐릿한 반영
  for (var i = 0; i < 16; i++) {
    final rx = _snap(r.next() * kTile),
        rw = _snap(6 + r.next() * 12),
        rh = _snap(9 + r.next() * 18);
    for (var y = 0.0; y < rh; y += kPx) {
      if (r.next() < .6) {
        b.px(rx + _snap((r.next() - .5) * 4), y, rw, kPx, p.waterBand, .12);
      }
    }
  }
  if (p.night) {
    for (var x = kPx * 3; x < kTile; x += kPx * 11) {
      for (var y = 0.0; y < h * .7; y += kPx * 2) {
        if (r.next() < .5) {
          b.px(x + _snap((r.next() - .5) * 6), y, kPx, kPx, p.lamp,
              .55 * (1 - y / (h * .75)));
        }
      }
    }
  }
}

void paintIsland(Canvas c, WorldPalette p, double h) {
  final b = _Brush(c);
  b.px(kPx * 15, h - kPx, kPx * 42, kPx, _mix(p.leafDark, .08), .7);
  b.px(kPx * 16, h - kPx * 3, kPx * 40, kPx * 2, p.leafDark, .92);
  for (var i = 0; i < _islandPlan.length; i++) {
    final x = _islandPlan[i] * kPx, th = kPx * (i.isOdd ? 3 : 4);
    b.rows(x, h - kPx * 3 - th, const [3, 5, 5, 3],
        i % 3 != 0 ? p.leaf : p.leafDark, .95);
    b.rows(x + kPx, h - kPx * 3 - th + kPx, const [0, 3, 3, 0],
        _mix(p.leaf, .08), .6);
  }
}

void paintBank(Canvas c, WorldPalette p, double h) {
  final b = _Brush(c);
  final r = _Rng(20260909);
  final g = h - kPx * 7;
  b.px(0, g, kTile, kPx * 7, p.grassDark, .95);
  b.px(0, g - kPx, kTile, kPx, p.grass, .95);
  for (var i = 0; i < 34; i++) {
    b.px(_snap(r.next() * kTile), g + _snap(r.next() * kPx * 5), kPx / 2, kPx / 2,
        _mix(p.grass, .10), .5);
  }
  b.px(0, g + kPx * 6, kTile, kPx / 2, _mix(p.grassDark, -.05), .7);
  for (final o in _bankPlan) {
    final x = o.x * kPx;
    switch (o.t) {
      case 'reeds':
        _reeds(b, x, g, p);
      case 'tree':
        _tree(b, x + kPx * 5, g, o.big, p, o.blossom);
      case 'lamp':
        _lamppost(b, x + kPx * 3, g, p);
      case 'bench':
        _bench(b, x, g, p);
    }
  }
}

void paintTrack(Canvas c, WorldPalette p, double h) {
  final b = _Brush(c);
  final r = _Rng(41);
  b.px(0, 0, kTile, kPx * 2, p.bike, .9);
  b.px(0, kPx, kTile, kPx, p.line, .3);
  b.px(0, kPx * 2, kTile, h - kPx * 2, p.track);
  b.px(0, kPx * 2, kTile, kPx / 2, _mix(p.track, .09), .8);
  // 차선은 옅게 둔다. 러닝 화면의 큰 숫자가 트랙 높이에 앉는 기기가 있어서
  // (iPhone 16e, 2026-09-11), 진하면 흰 점선이 숫자를 가로질러 취소선으로 읽힌다
  for (var x = 0.0; x < kTile; x += kPx * 12) {
    b.px(x, kPx * 2 + (h - kPx * 2) / 2, kPx * 6, kPx, p.line, .18);
  }
  for (var x = 0.0; x < kTile; x += kPx * 26) {
    b.px(x, kPx / 2, kPx, kPx, p.line, .45);
    b.px(x - kPx / 2, kPx, kPx / 2, kPx / 2, p.line, .35);
    b.px(x + kPx, kPx, kPx / 2, kPx / 2, p.line, .35);
  }
  for (var i = 0; i < 20; i++) {
    b.px(_snap(r.next() * kTile), kPx * 2 + _snap(r.next() * (h - kPx * 3)),
        kPx / 2, kPx / 2, _mix(p.track, .06), .35);
  }
}

/// 해(달)와 물 위의 빛길 — **흐르지 않는다.** 해는 지평선에 붙박여 있고,
/// 그것이 이 장면의 유일한 정지점이라 세계가 흐른다는 것이 더 또렷해진다
void paintSun(Canvas c, WorldPalette p, double cx, double cy) {
  final b = _Brush(c);
  b.disc(cx, cy, 7, p.sun, p.night ? .85 : .95);
  b.disc(cx, cy, 5, p.sunInner, .9);
  if (!p.night) {
    b.px(cx - kPx * 9, cy + kPx * 2, kPx * 18, kPx, p.skyMid, .55);
    b.px(cx - kPx * 7, cy + kPx * 5, kPx * 15, kPx, p.skyMid, .42);
    b.px(cx - kPx * 10, cy - kPx * 3, kPx * 20, kPx, p.skyMid, .28);
  }
}

void paintSunPath(Canvas c, WorldPalette p, double cx, double h) {
  final b = _Brush(c);
  for (var i = 0; i < 22; i++) {
    final y = i * kPx * 1.6;
    if (y > h) break;
    final w = kPx * (2 + (i % 3) + (i ~/ 6));
    b.px(cx - w / 2, y, w, kPx, p.sunPath, math.max(0, .5 - i * .017));
  }
}

/// 층 하나를 한 번만 굽는다.
///
/// 이 함수가 이 파일의 존재 이유다 — 층마다 픽셀 rect가 수백 개인데 매 프레임
/// 다시 그리면 30분 러닝에서 배터리가 남지 않는다. 한 번 구워두면 프레임마다
/// `drawPicture` 두 번(한 주기 + 이음매)이면 끝난다
ui.Picture bakeLayer(
    double width, double height, void Function(Canvas) draw) {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  draw(c);
  return recorder.endRecording();
}
