#!/usr/bin/env python3
"""Draw every Kampala vehicle as a detailed top-down SVG (original art, no logos).

  python3 -I tools/art/make_vehicles.py      writes tools/art/svg/*.svg and manifest.json
  godot --headless --path . -s res://tools/art/bake_atlas.gd   packs them into the atlas

All sprites face +x (front to the right), lit from the upper left. PX pixels per world unit.
"""
import colorsys
import json
import pathlib
import random

PX = 20.0
OUT = pathlib.Path(__file__).parent / "svg"
OUT.mkdir(exist_ok=True)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))


def hexc(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v * 255))) for v in c)


def shade(h, k):
    """k>0 lightens toward white, k<0 darkens."""
    r, g, b = rgb(h)
    if k >= 0:
        return hexc((r+(1-r)*k, g+(1-g)*k, b+(1-b)*k))
    return hexc((r*(1+k), g*(1+k), b*(1+k)))


class Sprite:
    def __init__(self, length_wu, width_wu, seed=1):
        self.w, self.h = length_wu * PX, width_wu * PX
        self.defs, self.parts = [], []
        self.n = 0
        self.rng = random.Random(seed)

    def grad(self, stops, x1=0, y1=0, x2=0, y2=1):
        self.n += 1
        i = f"g{self.n}"
        s = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a is not None else "") + "/>" for o, c, a in stops)
        self.defs.append(f'<linearGradient id="{i}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>')
        return f"url(#{i})"

    def paint(self, base):
        return self.grad([(0, shade(base, -0.34), None), (0.13, shade(base, 0.1), None), (0.42, shade(base, 0.3), None), (0.7, base, None), (0.92, shade(base, -0.22), None), (1, shade(base, -0.5), None)])

    def glass(self):
        return self.grad([(0, "#6f8fa3", None), (0.35, "#2b3d4b", None), (1, "#141d25", None)], 0, 0, 1, 1)

    def add(self, s):
        self.parts.append(s)

    def rect(self, x, y, w, h, fill, r=0, op=None, stroke=None, sw=0):
        a = f' opacity="{op}"' if op is not None else ""
        st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
        self.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r}" ry="{r}" fill="{fill}"{a}{st}/>')

    def circle(self, x, y, r, fill, op=None, stroke=None, sw=0):
        a = f' opacity="{op}"' if op is not None else ""
        st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
        self.add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{fill}"{a}{st}/>')

    def ell(self, x, y, rx, ry, fill, op=None, rot=0):
        a = f' opacity="{op}"' if op is not None else ""
        t = f' transform="rotate({rot} {x:.1f} {y:.1f})"' if rot else ""
        self.add(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}"{a}{t}/>')

    def path(self, d, fill="none", stroke=None, sw=0, op=None):
        a = f' opacity="{op}"' if op is not None else ""
        st = f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"' if stroke else ""
        self.add(f'<path d="{d}" fill="{fill}"{st}{a}/>')

    def line(self, x1, y1, x2, y2, col, sw=2, op=None):
        self.path(f"M{x1:.1f} {y1:.1f}L{x2:.1f} {y2:.1f}", "none", col, sw, op)

    def poly(self, pts, fill, op=None, stroke=None, sw=0):
        d = "M" + "L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z"
        self.path(d, fill, stroke, sw, op)

    def shadow(self, x, y, w, h, r=14):
        for g, o in ((10, 0.06), (6, 0.09), (3, 0.13)):
            self.rect(x - g + 5, y - g + 7, w + 2*g, h + 2*g, "#000", r + g, o)

    def svg(self):
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w:.0f}" height="{self.h:.0f}" viewBox="0 0 {self.w:.0f} {self.h:.0f}"><defs>{"".join(self.defs)}</defs>{"".join(self.parts)}</svg>'


# ---- shared car parts --------------------------------------------------
def outline(x0, x1, y0, y1, nose=0.1, tail=0.06, round_=0.09):
    """Plan view of a body: tapered, rounded at each corner. Returns an SVG path."""
    L, W = x1 - x0, y1 - y0
    n, t, r = W * nose, W * tail, L * round_
    return (f"M{x0+r:.1f} {y0+t:.1f}C{x0+L*.3:.1f} {y0-1:.1f} {x1-L*.3:.1f} {y0-1:.1f} {x1-r:.1f} {y0+n:.1f}"
            f"Q{x1:.1f} {y0+n+W*.04:.1f} {x1:.1f} {y0+n+W*.2:.1f}L{x1:.1f} {y1-n-W*.2:.1f}Q{x1:.1f} {y1-n-W*.04:.1f} {x1-r:.1f} {y1-n:.1f}"
            f"C{x1-L*.3:.1f} {y1+1:.1f} {x0+L*.3:.1f} {y1+1:.1f} {x0+r:.1f} {y1-t:.1f}"
            f"Q{x0:.1f} {y1-t-W*.04:.1f} {x0:.1f} {y1-t-W*.18:.1f}L{x0:.1f} {y0+t+W*.18:.1f}Q{x0:.1f} {y0+t+W*.04:.1f} {x0+r:.1f} {y0+t:.1f}Z")


def wheels(s, x0, x1, y0, y1, inset=0.2, length=0.17):
    L = x1 - x0
    for cx in (x0 + L*inset, x1 - L*inset):
        for y in (y0 - 2, y1 - 5):
            s.rect(cx - L*length/2, y, L*length, 7, "#0d0d0e", 3)


def mirrors(s, x, y0, y1, col):
    for y, dy in ((y0, -7), (y1, 2)):
        s.rect(x, y + dy, 9, 6, shade(col, -0.25), 2)
        s.rect(x + 1, y + dy + 1, 4, 4, "#172027", 1)


def lights(s, x0, x1, y0, y1):
    W = y1 - y0
    for y in (y0 + W*.1, y1 - W*.1 - W*.2):
        s.rect(x1 - 7, y, 6, W*.2, s.grad([(0, "#fff8cf", None), (1, "#c9b76a", None)], 0, 0, 1, 0), 2)
    for y in (y0 + W*.09, y1 - W*.09 - W*.2):
        s.rect(x0 + 1, y, 5, W*.2, "#a81c14", 2)


def cabin(s, x0, x1, y0, y1, ws, roof_front, roof_back, rear, col, side=True, tint=False):
    """Windscreen, roof, rear screen and side glass for a closed cab."""
    W = y1 - y0
    i = W * 0.09
    g = "#10161b" if tint else s.glass()
    s.poly([(ws, y0+i*1.3), (roof_front, y0+i*2.0), (roof_front, y1-i*2.0), (ws, y1-i*1.3)], g)
    s.poly([(rear, y0+i*1.5), (roof_back, y0+i*2.1), (roof_back, y1-i*2.1), (rear, y1-i*1.5)], g)
    if side:
        s.poly([(roof_back, y0+i*.8), (roof_front, y0+i*.8), (roof_front, y0+i*1.75), (roof_back, y0+i*1.75)], g)
        s.poly([(roof_back, y1-i*.8), (roof_front, y1-i*.8), (roof_front, y1-i*1.75), (roof_back, y1-i*1.75)], g)
        for fx in (0.5,):
            bx = roof_back + (roof_front-roof_back)*fx
            s.line(bx, y0+i*.8, bx, y0+i*1.75, col, 3)
            s.line(bx, y1-i*.8, bx, y1-i*1.75, col, 3)
    s.rect(roof_back, y0+i*1.85, roof_front-roof_back, W-i*3.7, s.paint(shade(col, 0.08)), 7)
    # Windscreen glare.
    s.poly([(ws+4, y0+i*1.7), (ws+13, y0+i*1.7), (roof_front-2, y0+W*.42), (roof_front-8, y0+W*.42)], "#fff", 0.14)


def seams(s, x0, x1, y0, y1, xs, col):
    for x in xs:
        s.line(x, y0 + 2, x, y0 + (y1-y0)*.14, shade(col, -0.4), 1.3, 0.7)
        s.line(x, y1 - 2, x, y1 - (y1-y0)*.14, shade(col, -0.4), 1.3, 0.7)


def hood_lines(s, x0, x1, y0, y1, col):
    W = y1 - y0
    s.path(f"M{x0:.1f} {y0+W*.24:.1f}Q{(x0+x1)/2:.1f} {y0+W*.2:.1f} {x1:.1f} {y0+W*.26:.1f}", "none", shade(col, -0.25), 1.4, 0.6)
    s.path(f"M{x0:.1f} {y1-W*.24:.1f}Q{(x0+x1)/2:.1f} {y1-W*.2:.1f} {x1:.1f} {y1-W*.26:.1f}", "none", shade(col, -0.25), 1.4, 0.6)
    s.ell((x0+x1)/2, y0+W*.36, (x1-x0)*.34, W*.06, "#fff", 0.17)


def weathering(s, x0, x1, y0, y1, amount):
    """Kampala wear: scuffs, a rust patch, red dust along the sills."""
    W = y1 - y0
    for _ in range(amount):
        x = s.rng.uniform(x0+8, x1-8)
        y = s.rng.choice([y0+W*.05, y1-W*.1])
        s.ell(x, y, s.rng.uniform(4, 14), s.rng.uniform(1, 3), s.rng.choice(["#6b3a1f", "#3a2a1c", "#d8d4c8"]), 0.55)
    s.rect(x0+6, y0+1, x1-x0-12, 4, "#a4582e", 2, 0.25)
    s.rect(x0+6, y1-5, x1-x0-12, 4, "#a4582e", 2, 0.28)


# ---- models ------------------------------------------------------------
def saloon(col, old=0, door=None, seed=1, l=11.6, w=5.6, extra=None):
    s = Sprite(l + 1.0, w + 1.4, seed)
    x0, x1, y0, y1 = 10, s.w - 10, 14, s.h - 14
    L = x1 - x0
    s.shadow(x0, y0, L, y1-y0)
    wheels(s, x0, x1, y0, y1)
    s.path(outline(x0, x1, y0, y1), s.paint(col), "#0e0e0e", 1.2)
    if door:
        s.poly([(x0+L*.33, y0+1), (x0+L*.53, y0+1), (x0+L*.53, y0+(y1-y0)*.13), (x0+L*.33, y0+(y1-y0)*.13)], door)
    hood_lines(s, x1 - L*.25, x1 - 8, y0, y1, col)
    cabin(s, x0, x1, y0, y1, x1 - L*.28, x1 - L*.38, x0 + L*.26, x0 + L*.17, col)
    seams(s, x0, x1, y0, y1, [x0+L*.33, x0+L*.53, x0+L*.72], col)
    mirrors(s, x1 - L*.31, y0, y1, col)
    lights(s, x0, x1, y0, y1)
    if old:
        weathering(s, x0, x1, y0, y1, old)
    if extra:
        extra(s, x0, x1, y0, y1)
    return s


def hatch(col, old=0, seed=1):
    s = Sprite(9.6, 6.0, seed)
    x0, x1, y0, y1 = 10, s.w - 10, 14, s.h - 14
    L = x1 - x0
    s.shadow(x0, y0, L, y1-y0)
    wheels(s, x0, x1, y0, y1, .17, .2)
    s.path(outline(x0, x1, y0, y1, .13, .05, .1), s.paint(col), "#0e0e0e", 1.2)
    hood_lines(s, x1 - L*.2, x1 - 6, y0, y1, col)
    cabin(s, x0, x1, y0, y1, x1 - L*.22, x1 - L*.34, x0 + L*.15, x0 + L*.05, col)
    seams(s, x0, x1, y0, y1, [x0+L*.45, x0+L*.7], col)
    mirrors(s, x1 - L*.27, y0, y1, col)
    lights(s, x0, x1, y0, y1)
    if old:
        weathering(s, x0, x1, y0, y1, old)
    return s


def mpv(col, old=0, seed=1, load=None):
    s = Sprite(11.4, 6.3, seed)
    x0, x1, y0, y1 = 10, s.w - 10, 14, s.h - 14
    L = x1 - x0
    s.shadow(x0, y0, L, y1-y0)
    wheels(s, x0, x1, y0, y1, .18, .15)
    s.path(outline(x0, x1, y0, y1, .1, .03, .06), s.paint(col), "#0e0e0e", 1.2)
    hood_lines(s, x1 - L*.12, x1 - 5, y0, y1, col)
    cabin(s, x0, x1, y0, y1, x1 - L*.13, x1 - L*.25, x0 + L*.07, x0 + L*.02, col)
    seams(s, x0, x1, y0, y1, [x0+L*.42, x0+L*.62], col)
    mirrors(s, x1 - L*.18, y0, y1, col)
    lights(s, x0, x1, y0, y1)
    if old:
        weathering(s, x0, x1, y0, y1, old)
    if load:
        load(s, x0, x1, y0, y1)
    return s


def rack(s, xa, xb, y0, y1, col="#2a2a2a"):
    W = y1 - y0
    for x in range(int(xa), int(xb), 13):
        s.line(x, y0+W*.2, x, y1-W*.2, col, 2)
    s.rect(xa, y0+W*.18, xb-xa, 3, col, 1)
    s.rect(xa, y1-W*.18-3, xb-xa, 3, col, 1)


def school_load(s, x0, x1, y0, y1):
    W, L = y1-y0, x1-x0
    a, b = x0+L*.1, x0+L*.68
    rack(s, a, b, y0, y1)
    # Mattress with its stripes, the sign of the season.
    s.rect(a+4, y0+W*.2, b-a-22, W*.6, s.grad([(0, "#f2e6cf", None), (1, "#cdbb9a", None)]), 6, stroke="#8c7a5c", sw=1.2)
    for x in range(int(a+10), int(b-22), 12):
        s.line(x, y0+W*.21, x, y1-W*.21, "#3f6fa8", 1.6, 0.8)
    # Metal suitcase, the mabati one every boarder has.
    s.rect(b-52, y0+W*.28, 34, W*.27, s.grad([(0, "#7fa0c4", None), (1, "#2c4f80", None)]), 2, stroke="#14233a", sw=1.2)
    s.rect(b-38, y0+W*.28, 3, W*.27, "#d9d9d9")
    s.rect(a+24, y1-W*.42, 20, W*.2, "#2f8c52", 3, stroke="#143a22", sw=1)
    s.line(x0+L*.1, y0+W*.5, x0+L*.68, y0+W*.5, "#b03a2a", 2)


def taxi(load=False, seed=1, stripe="#1d5fa8"):
    """The Kampala matatu: white Hiace with the blue chequered band."""
    s = Sprite(12.4, 6.6, seed)
    x0, x1, y0, y1 = 10, s.w - 10, 14, s.h - 14
    L, W = x1-x0, y1-y0
    col = "#f4f2ea"
    s.shadow(x0, y0, L, W)
    wheels(s, x0, x1, y0, y1, .14, .14)
    s.path(outline(x0, x1, y0, y1, .09, .03, .05), s.paint(col), "#111", 1.2)
    # Short nose, huge screen, flat cab front.
    s.ell(x1 - L*.055, y0+W*.5, L*.03, W*.3, "#fff", 0.3)
    cabin(s, x0, x1, y0, y1, x1 - L*.09, x1 - L*.2, x0 + L*.05, x0 + L*.015, col, tint=False)
    # Chequers run the full length of both flanks.
    x = x0 + 7
    on = True
    size = 9
    while x < x1 - 12:
        for yy in (y0 + 2.5, y1 - 2.5 - size):
            if on:
                s.rect(x, yy, size, size*.5, stripe)
                s.rect(x + size, yy + size*.5, size, size*.5, stripe)
        x += size*2
    s.rect(x0 + 8, y0 + W*.32, L*.72, W*.36, "#fff", 8, .25)
    # Roof vents.
    for vx in (x0+L*.28, x0+L*.55):
        s.rect(vx, y0+W*.43, 24, W*.14, shade(col, -0.25), 3, stroke="#888", sw=1)
    mirrors(s, x1 - L*.14, y0, y1, col)
    lights(s, x0, x1, y0, y1)
    weathering(s, x0, x1, y0, y1, 4)
    if load:
        rack(s, x0+L*.1, x0+L*.62, y0, y1)
        for i, (c, lx, ly, lw, lh) in enumerate([("#6a3f22", .13, .24, .17, .24), ("#3a6b3a", .32, .3, .14, .42), ("#c9a54a", .15, .52, .14, .22), ("#7a2f2a", .47, .24, .12, .3)]):
            s.rect(x0+L*lx, y0+W*ly, L*lw, W*lh, s.grad([(0, shade(c, .2), None), (1, shade(c, -.3), None)]), 4, stroke="#111", sw=1)
    return s


def suv(col, spare=True, rails=True, tint=False, antenna=False, snorkel=False, bull=False, seed=1, old=0):
    s = Sprite(12.6, 7.0, seed)
    x0, x1, y0, y1 = 12, s.w - 10, 15, s.h - 15
    L, W = x1-x0, y1-y0
    s.shadow(x0, y0, L, W, 12)
    wheels(s, x0, x1, y0, y1, .19, .18)
    if spare:
        s.circle(x0 - 1, y0+W*.5, W*.2, "#101011", stroke="#3a3a3a", sw=3)
    s.path(outline(x0, x1, y0, y1, .05, .02, .05), s.paint(col), "#0b0b0b", 1.3)
    hood_lines(s, x1 - L*.26, x1 - 8, y0, y1, col)
    cabin(s, x0, x1, y0, y1, x1 - L*.28, x1 - L*.37, x0 + L*.1, x0 + L*.035, col, tint=tint)
    seams(s, x0, x1, y0, y1, [x0+L*.32, x0+L*.51], col)
    if rails:
        s.rect(x0+L*.13, y0+W*.2, L*.47, 3, "#232323", 1)
        s.rect(x0+L*.13, y1-W*.2-3, L*.47, 3, "#232323", 1)
    mirrors(s, x1 - L*.32, y0, y1, col)
    lights(s, x0, x1, y0, y1)
    if bull:
        s.path(f"M{x1+1:.1f} {y0+W*.14:.1f}L{x1+6:.1f} {y0+W*.2:.1f}L{x1+6:.1f} {y1-W*.2:.1f}L{x1+1:.1f} {y1-W*.14:.1f}", "none", "#232323", 3.5)
    if snorkel:
        s.rect(x1-L*.31, y1-W*.11, 16, 7, "#111", 3)
    if antenna:
        s.line(x1-L*.27, y0+W*.1, x1-L*.03, y0-6, "#111", 2)
        s.circle(x1-L*.27, y0+W*.1, 3, "#111")
    if old:
        weathering(s, x0, x1, y0, y1, old)
    return s


def people(s, seats, jacket="#2a4a7a", head="#3a2517", cap=None, r=6):
    for x, y in seats:
        s.circle(x, y, r+3, jacket)
        s.circle(x, y, r, cap or head)


def pickup(col, bed=None, tint=False, bar=False, seed=1, rack_=False, double=True, old=0):
    s = Sprite(12.8, 6.9, seed)
    x0, x1, y0, y1 = 10, s.w - 10, 14, s.h - 14
    L, W = x1-x0, y1-y0
    s.shadow(x0, y0, L, W, 10)
    wheels(s, x0, x1, y0, y1, .2, .17)
    s.path(outline(x0, x1, y0, y1, .05, .02, .04), s.paint(col), "#0b0b0b", 1.3)
    hood_lines(s, x1 - L*.22, x1 - 7, y0, y1, col)
    back = x0 + (L*.42 if double else L*.52)
    cabin(s, x0, x1, y0, y1, x1 - L*.25, x1 - L*.33, back+8, back, col, tint=tint)
    # Load bed.
    s.rect(x0+6, y0+W*.1, back-x0-14, W*.8, s.grad([(0, "#1a1a1a", None), (1, "#2f2f2f", None)]), 3, stroke=shade(col, -.35), sw=3)
    for x in range(int(x0+16), int(back-14), 14):
        s.line(x, y0+W*.13, x, y1-W*.13, "#3a3a3a", 1.2)
    mirrors(s, x1 - L*.29, y0, y1, col)
    lights(s, x0, x1, y0, y1)
    if bar:
        cx = x1 - L*.42
        s.rect(cx-4, y0+W*.2, 9, W*.6, "#222", 2)
        s.rect(cx-3, y0+W*.2, 7, W*.28, "#d3241c", 1)
        s.rect(cx-3, y0+W*.52, 7, W*.28, "#1c55d3", 1)
    if bed:
        bed(s, x0+6, back-8, y0, y1)
    if old:
        weathering(s, x0, x1, y0, y1, old)
    return s


def police_bed(s, a, b, y0, y1):
    W = y1-y0
    for x in (a+14, a+38, b-18):
        people(s, [(x, y0+W*.25), (x, y1-W*.25)], "#1f3f77", cap="#0f2144")


def army_bed(s, a, b, y0, y1):
    W = y1-y0
    s.rect(a+3, y0+W*.44, b-a-6, W*.12, "#3d3f26", 2)
    for x in (a+14, a+38, b-16):
        people(s, [(x, y0+W*.25), (x, y1-W*.25)], "#4d5430", cap="#3a4024")


def sacks_bed(s, a, b, y0, y1):
    W = y1-y0
    for ix in range(3):
        for iy in range(3):
            s.rect(a+4+ix*(b-a-8)/3, y0+W*.14+iy*W*.24, (b-a-8)/3-2, W*.22, s.grad([(0, "#e8dcc0", None), (1, "#a79670", None)]), 5, stroke="#6f6248", sw=1)


def bunch(s, x, y, r, seed=1):
    """A matooke bunch, seen from above."""
    rr = random.Random(seed)
    s.circle(x, y, r, "#3d5a1f")
    for i in range(int(r*1.6)):
        a, d = rr.uniform(0, 6.28), rr.uniform(0, r*.92)
        import math
        px, py = x+math.cos(a)*d, y+math.sin(a)*d
        s.ell(px, py, r*.3, r*.11, rr.choice(["#7fa63a", "#94b845", "#6b9130", "#a8c25a"]), None, rr.uniform(0, 180))


def lorry(load, cab="#d24b2f", seed=1, length=19.6, width=7.8):
    s = Sprite(length, width, seed)
    y0, y1 = s.h*.13, s.h*.87
    x0, x1 = 12, s.w - 10
    L, W = x1-x0, y1-y0
    cabl = 66
    s.shadow(x0, y0, L, W, 6)
    wheels(s, x0, x1, y0-2, y1+2, .13, .1)
    wheels(s, x0, x0+L*.55, y0-2, y1+2, .2, .13)
    # Cab, forward control like a Fuso or an Isuzu.
    cx = x1 - cabl
    s.rect(cx, y0+2, cabl, W-4, s.paint(cab), 9, stroke="#111", sw=1.3)
    s.poly([(x1-20, y0+W*.11), (x1-8, y0+W*.15), (x1-8, y1-W*.15), (x1-20, y1-W*.11)], s.glass())
    s.rect(cx+6, y0+W*.1, cabl-30, W*.8, s.paint(shade(cab, .1)), 6)
    s.rect(cx+10, y0+W*.2, 16, W*.6, "#fff", 3, .14)
    mirrors(s, x1-26, y0-2, y1+2, cab)
    s.rect(x1-3, y0+W*.1, 3, W*.2, "#fff4bf", 1)
    s.rect(x1-3, y1-W*.3, 3, W*.2, "#fff4bf", 1)
    # Chassis and sideboards.
    s.rect(x0, y0+3, cx-x0-3, W-6, "#3f2a1a", 2)
    load(s, x0, cx-5, y0, y1, W)
    s.rect(x0+1, y0+W*.1, 4, W*.14, "#a81c14", 1)
    s.rect(x0+1, y1-W*.24, 4, W*.14, "#a81c14", 1)
    return s


def load_matooke(s, a, b, y0, y1, W):
    # Piled well past the sideboards, the way it comes in from Mbarara.
    s.rect(a, y0-W*.03, b-a, W*1.06, "#5c3d22", 4)
    rr = random.Random(5)
    cols = int((b-a)/34)
    for i in range(cols):
        for j in range(3):
            bunch(s, a+18+i*((b-a-34)/max(cols-1, 1)), y0+W*.17+j*W*.33+rr.uniform(-4, 4), 19, i*11+j)
    for x, y in ((a+58, y0+W*.5), (a+96, y0+W*.3)):
        people(s, [(x, y)], "#a8381f")


def load_sacks(s, a, b, y0, y1, W):
    # Charcoal bags stacked over the sides, tied down with whatever rope there was.
    s.rect(a, y0-W*.04, b-a, W*1.08, "#2a1d12", 3)
    rr = random.Random(9)
    for i in range(int((b-a)/25)):
        for j in range(4):
            c = rr.choice(["#e4d7bc", "#d0c19f", "#bdae8c", "#dccda8"])
            s.rect(a+2+i*25, y0-W*.03+j*W*.27, 23, W*.25, s.grad([(0, shade(c, .2), None), (1, shade(c, -.28), None)]), 6, stroke="#5f523b", sw=1)
            s.line(a+8+i*25, y0-W*.03+j*W*.27+3, a+18+i*25, y0-W*.03+j*W*.27+W*.2, "#1a1208", 2, .55)
    for x in range(int(a+30), int(b), 70):
        s.line(x, y0-W*.03, x+8, y1+W*.03, "#c7402a", 2.4)


def load_furniture(s, a, b, y0, y1, W):
    # Everything somebody owns, with the family on top.
    s.rect(a, y0-W*.04, b-a, W*1.08, "#6c4a2c", 3)
    s.rect(a+6, y0, 74, W*.52, s.grad([(0, "#efe2c6", None), (1, "#c5b392", None)]), 7, stroke="#7f6f50", sw=1.2)
    for x in range(int(a+12), int(a+76), 10):
        s.line(x, y0+2, x, y0+W*.5, "#b23a35", 1.5, .8)
    s.rect(a+6, y0+W*.56, 52, W*.42, "#7a3a24", 3, stroke="#2a1208", sw=1.5)
    s.rect(a+62, y0+W*.58, 44, W*.38, s.grad([(0, "#74a9c9", None), (1, "#2a5778", None)]), 4)
    s.rect(a+88, y0+2, 56, W*.48, "#8d8f8c", 3, stroke="#3a3a3a", sw=1.2)
    s.circle(a+116, y0+W*.26, W*.16, "#1a1a1a", stroke="#b5b5b5", sw=2)
    # A sofa, a wardrobe, sacks and a bed frame fill the rest, past the sideboards.
    s.rect(a+150, y0-W*.03, 66, W*.5, s.paint("#8a4a2b"), 6, stroke="#2a1208", sw=1.3)
    s.rect(a+156, y0+W*.05, 54, W*.33, "#b06a3f", 4)
    s.rect(a+112, y0+W*.56, 52, W*.42, s.paint("#b59259"), 2, stroke="#3a2a14", sw=1.3)
    s.line(a+138, y0+W*.56, a+138, y0+W*.98, "#3a2a14", 1.5)
    s.rect(a+168, y0+W*.54, 48, W*.46, s.grad([(0, "#e4d7bc", None), (1, "#a79670", None)]), 6, stroke="#5f523b", sw=1)
    s.rect(a+222, y0-W*.03, b-a-228, W*1.06, s.grad([(0, "#e8dcc0", None), (1, "#9f8e68", None)]), 6, stroke="#5f523b", sw=1)
    for y in (y0+W*.2, y0+W*.45, y0+W*.7):
        s.line(a, y, b, y+3, "#c7402a", 2)
    for x, y, j in ((a+96, y0+W*.76, "#c43b6e"), (a+188, y0+W*.72, "#2f7a4e"), (a+236, y0+W*.5, "#d8a12e")):
        people(s, [(x, y)], j)


def load_crates(s, a, b, y0, y1, W):
    # Soda crates, in the red and the blue.
    s.rect(a, y0, b-a, W, "#3a2a1a", 3)
    for i in range(int((b-a)/25)):
        for j in range(4):
            c = "#c9281f" if (i+j) % 3 else "#1d4f98"
            x, y = a+3+i*25, y0+3+j*(W-6)/4
            s.rect(x, y, 23, (W-6)/4-2, c, 2)
            for k in range(3):
                for m in range(2):
                    s.circle(x+5+k*7, y+6+m*8, 2.3, "#2a1c0e", stroke="#d8c88a", sw=.8)


def tipper(col="#c8a42b", seed=1):
    def load(s, a, b, y0, y1, W):
        s.rect(a, y0, b-a, W, s.paint("#7b6a32"), 4, stroke="#222", sw=2)
        s.rect(a+6, y0+6, b-a-12, W-12, s.grad([(0, "#c76c3b", None), (1, "#99502a", None)]), 22)
        s.ell((a+b)/2, y0+W*.42, (b-a)*.3, W*.2, "#d7814f", .8)
    return lorry(load, col, seed, 16.6, 7.4)


def tanker(col="#e8e6e0", seed=1):
    def load(s, a, b, y0, y1, W):
        s.rect(a, y0+W*.04, b-a, W*.92, s.grad([(0, "#7c7c7a", None), (.2, "#e7e7e5", None), (.45, "#fff", None), (.8, "#a8a8a6", None), (1, "#545452", None)]), W*.4, stroke="#222", sw=1.2)
        for x in (a+(b-a)*.25, a+(b-a)*.5, a+(b-a)*.75):
            s.circle(x, y0+W*.5, W*.13, "#c4c4c0", stroke="#55554f", sw=1.5)
        s.rect(a+10, y0+W*.05, b-a-20, W*.08, "#c4372a", 1)
        s.rect(a+10, y1-W*.13, b-a-20, W*.08, "#c4372a", 1)
    return lorry(load, "#355e91", seed, 18.6, 7.2)


def coaster(col="#f1efe7", stripe="#c23a2a", seed=1):
    s = Sprite(17.6, 6.9, seed)
    x0, x1, y0, y1 = 10, s.w-10, 14, s.h-14
    L, W = x1-x0, y1-y0
    s.shadow(x0, y0, L, W, 10)
    wheels(s, x0, x1, y0, y1, .15, .1)
    s.path(outline(x0, x1, y0, y1, .08, .02, .03), s.paint(col), "#111", 1.2)
    s.poly([(x1-L*.035, y0+W*.1), (x1-L*.09, y0+W*.16), (x1-L*.09, y1-W*.16), (x1-L*.035, y1-W*.1)], s.glass())
    s.rect(x0+7, y0+W*.09, L*.86, W*.09, s.glass(), 2)
    s.rect(x0+7, y1-W*.18, L*.86, W*.09, s.glass(), 2)
    for x in range(int(x0+40), int(x1-L*.1), 40):
        s.line(x, y0+W*.09, x, y0+W*.18, col, 3)
        s.line(x, y1-W*.18, x, y1-W*.09, col, 3)
    s.rect(x0+8, y0+W*.2, L*.81, W*.6, s.paint(shade(col, .06)), 6)
    s.rect(x0+8, y0+W*.46, L*.81, W*.08, stripe, 1)
    for vx in (x0+L*.22, x0+L*.55):
        s.rect(vx, y0+W*.4, 34, W*.2, shade(col, -.2), 4, stroke="#777", sw=1)
    mirrors(s, x1-L*.09, y0, y1, col)
    lights(s, x0, x1, y0, y1)
    weathering(s, x0, x1, y0, y1, 5)
    return s


def ambulance(seed=1):
    s = suv("#f6f7f5", spare=False, rails=False, seed=seed)
    x, y = s.w*.34, s.h*.5
    s.rect(x-18, y-5, 36, 10, "#d62f24", 1)
    s.rect(x-5, y-18, 10, 36, "#d62f24", 1)
    s.rect(s.w*.57, s.h*.3, 7, s.h*.4, "#222", 2)
    return s


def rider(s, x, y, jacket="#f05a22", helmet="#141414"):
    s.ell(x, y, 11, 15, s.grad([(0, shade(jacket, .25), None), (1, shade(jacket, -.3), None)]))
    s.rect(x-2, y-12, 3, 24, "#e9e9df", 1, .85)      # Reflector stripe.
    s.line(x+4, y-11, x+22, y-15, "#3b2a20", 5)     # Arms to the bars.
    s.line(x+4, y+11, x+22, y+15, "#3b2a20", 5)
    s.circle(x+1, y, 8.5, helmet, stroke="#000", sw=.8)
    s.ell(x-1, y-3, 3, 2, "#fff", .4)


def bike_base(s, x0, x1, cy, col):
    L = x1-x0
    s.ell((x0+x1)/2+3, cy+5, L*.5, 12, "#000", .2)
    s.rect(x0, cy-3, L*.22, 6, "#0c0c0c", 3)                 # Rear tyre.
    s.rect(x1-L*.2, cy-3, L*.2, 6, "#0c0c0c", 3)             # Front tyre.
    s.rect(x0+L*.14, cy-4, L*.66, 8, "#262626", 2)           # Frame.
    s.rect(x0+L*.1, cy-7, L*.34, 14, "#1b1b1b", 3)           # Seat.
    s.ell(x0+L*.58, cy, L*.11, 9, s.grad([(0, shade(col, .35), None), (1, shade(col, -.35), None)]))  # Tank.
    s.line(x1-L*.2, cy-19, x1-L*.2, cy+19, "#1b1b1b", 3.5)   # Bars.
    s.circle(x1-L*.2, cy-20, 2.8, "#aab3ba")
    s.circle(x1-L*.2, cy+20, 2.8, "#aab3ba")
    s.rect(x1-L*.07, cy-3, 5, 6, "#fff5c0", 1)


def boda(col="#b01f1f", jacket="#f05a22", cargo=None, seed=1):
    s = Sprite(7.2, 4.4, seed)
    cy = s.h/2
    x0, x1 = 10, s.w-8
    bike_base(s, x0, x1, cy, col)
    if cargo:
        cargo(s, x0, x1, cy)
    rider(s, x0+(x1-x0)*.5, cy, jacket)
    return s


def boda_pass(jacket2="#3f7fa8"):
    def f(s, x0, x1, cy):
        s.ell(x0+(x1-x0)*.28, cy, 10, 13, jacket2)
        s.circle(x0+(x1-x0)*.28, cy, 7, "#27160c")
    return f


def boda_two(s, x0, x1, cy):
    L = x1-x0
    s.ell(x0+L*.17, cy, 9, 12, "#c43b6e")
    s.circle(x0+L*.17, cy, 6.5, "#27160c")
    s.ell(x0+L*.33, cy, 10, 13, "#2d8f6f")
    s.circle(x0+L*.33, cy, 6.8, "#111")


def boda_matooke(s, x0, x1, cy):
    L = x1-x0
    bunch(s, x0+L*.16, cy-14, 13, 2)
    bunch(s, x0+L*.16, cy+14, 13, 4)
    bunch(s, x0+L*.3, cy, 12, 6)


def boda_mattress(s, x0, x1, cy):
    L = x1-x0
    s.rect(x0-4, cy-30, L*.5, 60, s.grad([(0, "#f4e8d1", None), (1, "#c9b995", None)]), 7, stroke="#7f6f50", sw=1.2)
    for x in range(int(x0+3), int(x0+L*.44), 9):
        s.line(x, cy-29, x, cy+29, "#2f6fb0", 1.4, .85)


def boda_jerry(s, x0, x1, cy):
    L = x1-x0
    for i, y in enumerate((cy-20, cy-7, cy+7, cy+20)):
        s.rect(x0+L*.04, y-6, L*.32, 12, "#e6c422" if i % 2 else "#2a6ec2", 2, stroke="#222", sw=1)


def bicycle(cargo=None, jacket="#3b7f4f", seed=1):
    s = Sprite(6.0, 4.0, seed)
    cy = s.h/2
    x0, x1 = 8, s.w-8
    L = x1-x0
    s.ell((x0+x1)/2+2, cy+4, L*.48, 7, "#000", .18)
    s.rect(x0, cy-1.5, L*.26, 3, "#0d0d0d", 1)
    s.rect(x1-L*.26, cy-1.5, L*.26, 3, "#0d0d0d", 1)
    s.rect(x0+L*.14, cy-1.5, L*.7, 3, "#1e3b6e", 1)
    s.line(x1-L*.22, cy-13, x1-L*.22, cy+13, "#202020", 2.4)
    if cargo:
        cargo(s, x0, x1, cy)
    s.ell(x0+L*.46, cy, 8, 11, s.grad([(0, shade(jacket, .25), None), (1, shade(jacket, -.3), None)]))
    s.line(x0+L*.5, cy-8, x1-L*.22, cy-12, "#3b2517", 3.2)
    s.line(x0+L*.5, cy+8, x1-L*.22, cy+12, "#3b2517", 3.2)
    s.circle(x0+L*.47, cy, 6, "#2d1a0e")
    return s


def cycle_matooke(s, x0, x1, cy):
    L = x1-x0
    bunch(s, x0+L*.14, cy-11, 11, 1)
    bunch(s, x0+L*.14, cy+11, 11, 3)
    bunch(s, x0+L*.28, cy, 10, 5)


def cycle_jerry(s, x0, x1, cy):
    L = x1-x0
    for i, y in enumerate((cy-23, cy-11, cy+1, cy+13)):
        s.rect(x0+L*.04, y, L*.28, 10, "#e6c422", 2, stroke="#6b5a11", sw=1)
        s.rect(x0+L*.1, y+3, 5, 4, "#2a2a2a")


def cycle_charcoal(s, x0, x1, cy):
    L = x1-x0
    s.rect(x0-2, cy-20, L*.38, 40, s.grad([(0, "#e4d7bc", None), (1, "#a79670", None)]), 6, stroke="#5f523b", sw=1)
    s.line(x0+6, cy-15, x0+L*.3, cy+15, "#1a1208", 2, .6)


def handcart(seed=1):
    s = Sprite(7.6, 4.4, seed)
    cy = s.h/2
    x0, x1 = 8, s.w-8
    L = x1-x0
    s.rect(x0+8, cy-26, L*.62, 52, "#6a4a2b", 3, stroke="#2a1a0c", sw=1.5)
    for x in range(int(x0+14), int(x0+L*.6), 11):
        for y in (cy-22, cy-8, cy+7):
            s.rect(x, y, 9, 13, "#e6c422", 2, stroke="#6b5a11", sw=.8)
    s.rect(x0+L*.26, cy-30, 14, 4, "#0d0d0d", 1)
    s.rect(x0+L*.26, cy+26, 14, 4, "#0d0d0d", 1)
    s.line(x0+L*.68, cy-14, x1-6, cy-14, "#6a4a2b", 3)
    s.line(x0+L*.68, cy+14, x1-6, cy+14, "#6a4a2b", 3)
    s.ell(x1-8, cy, 8, 12, "#a33f2a")
    s.circle(x1-8, cy, 6, "#2d1a0e")
    return s


def motorcycle_police(seed=1):
    s = Sprite(7.2, 4.4, seed)
    cy = s.h/2
    x0, x1 = 10, s.w-8
    L = x1-x0
    bike_base(s, x0, x1, cy, "#f2f2ee")
    s.rect(x0+L*.1, cy-15, L*.26, 8, "#f2f2ee", 2, stroke="#333", sw=.8)
    s.rect(x0+L*.1, cy+7, L*.26, 8, "#f2f2ee", 2, stroke="#333", sw=.8)
    s.rect(x1-L*.34, cy-8, 10, 16, "#9bb6c8", 3, .75)
    rider(s, x0+L*.48, cy, "#1f3f77", "#e8e8e8")
    return s


OLD = ["#e9e6dc", "#bdbfc0", "#7c2b2b", "#2d4569", "#c8b78f", "#3a3d40", "#6f7f6d", "#8a6d3b"]
SPRITES = {}
for i, c in enumerate(OLD):
    door = {2: "#c9b98f", 3: "#b7b7b1", 6: "#7c2b2b"}.get(i)
    SPRITES[f"saloon_{i}"] = saloon(c, old=5, door=door, seed=i+1)
for i, c in enumerate(["#eeeeea", "#8c9296", "#b33a2d", "#2f5a8f"]):
    SPRITES[f"hatch_{i}"] = hatch(c, old=3, seed=i+21)
for i, c in enumerate(["#f0efe9", "#a9acad", "#262a2e"]):
    SPRITES[f"noah_{i}"] = mpv(c, old=3, seed=i+31)
SPRITES["school_van"] = mpv("#e6b422", old=3, seed=35, load=school_load)
SPRITES["school_van_white"] = mpv("#f0efe9", old=2, seed=36, load=school_load)
SPRITES["taxi"] = taxi()
SPRITES["taxi_loaded"] = taxi(True, 2)
for i, c in enumerate(["#f3f3ef", "#a7aaad", "#23262a", "#5a4632"]):
    SPRITES[f"suv_{i}"] = suv(c, seed=i+41, old=2 if i == 3 else 0)
SPRITES["ngo_cruiser"] = suv("#fafaf6", antenna=True, snorkel=True, bull=True, seed=45, old=2)
SPRITES["vip_v8"] = suv("#101114", spare=False, rails=False, tint=True, antenna=True, seed=46)
SPRITES["vip_v8_silver"] = suv("#a4a8ac", spare=False, rails=False, tint=True, antenna=True, seed=47)
SPRITES["police_pickup"] = pickup("#d9e3ec", police_bed, bar=True, seed=51)
SPRITES["police_pickup_blue"] = pickup("#2c5aa0", police_bed, bar=True, seed=52)
SPRITES["army_pickup"] = pickup("#4d5430", army_bed, seed=53, old=3)
SPRITES["army_cruiser"] = suv("#4d5430", spare=True, rails=False, snorkel=True, bull=True, seed=54, old=3)
SPRITES["pickup_sacks"] = pickup("#c9c6bd", sacks_bed, seed=55, old=4)
SPRITES["pickup_red"] = pickup("#9c2f26", None, seed=56, old=4, double=False)
SPRITES["ambulance"] = ambulance()
SPRITES["coaster"] = coaster()
SPRITES["coaster_blue"] = coaster("#eef0ee", "#1d5fa8", 2)
SPRITES["lorry_matooke"] = lorry(load_matooke, "#d24b2f", 61)
SPRITES["lorry_charcoal"] = lorry(load_sacks, "#2f6f9a", 62)
SPRITES["lorry_furniture"] = lorry(load_furniture, "#2f7a4e", 63)
SPRITES["lorry_crates"] = lorry(load_crates, "#e0b52c", 64, 17.6, 7.2)
SPRITES["tipper"] = tipper()
SPRITES["tanker"] = tanker()
SPRITES["boda"] = boda()
SPRITES["boda_passenger"] = boda("#1b1b1b", "#f5c518", boda_pass())
SPRITES["boda_two"] = boda("#1d5fa8", "#2fa35c", boda_two)
SPRITES["boda_matooke"] = boda("#b01f1f", "#2fa35c", boda_matooke)
SPRITES["boda_mattress"] = boda("#1b1b1b", "#f05a22", boda_mattress)
SPRITES["boda_jerry"] = boda("#1d5fa8", "#f5c518", boda_jerry)
SPRITES["bicycle"] = bicycle()
SPRITES["bicycle_matooke"] = bicycle(cycle_matooke, "#a8381f")
SPRITES["bicycle_jerry"] = bicycle(cycle_jerry, "#2f6f9a")
SPRITES["bicycle_charcoal"] = bicycle(cycle_charcoal, "#c49b2c")
SPRITES["handcart"] = handcart()
SPRITES["police_moto"] = motorcycle_police()
SPRITES["player"] = saloon("#f5c518", old=0, seed=99)

manifest = {}
for name, sp in SPRITES.items():
    (OUT / f"{name}.svg").write_text(sp.svg())
    manifest[name] = {"w": sp.w, "h": sp.h}
(OUT / "manifest.json").write_text(json.dumps({"px_per_wu": PX, "sprites": manifest}))
print(len(SPRITES), "sprites")
