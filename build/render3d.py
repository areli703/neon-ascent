#!/usr/bin/env python3
"""
NEON ASCENT — low-angle 3D hero render.

Every number here is mirrored from src/shared/Config.lua and
src/server/World.lua: stage Y spacing, pad size, corner-tower
heights, spine radius, void shard scatter. Software rasteriser:
perspective projection, painter's-algorithm depth sort, Lambert
shading, height-graded atmospheric fog, additive bloom.
"""

import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

W, H = 1200, 1600
SS = 2  # supersample

# ---------------------------------------------------------------- config
BASE_Y, SH, PAD = 120, 190, 96


def stage_y(i):
    return BASE_Y + (i - 1) * SH


BIOMES = {
    "Neon":    {"p": (0, 225, 255), "s": (255, 0, 190), "fog": (4, 6, 24)},
    "Ember":   {"p": (255, 120, 20), "s": (255, 60, 40), "fog": (20, 6, 6)},
    "Glacier": {"p": (120, 230, 255), "s": (190, 245, 255), "fog": (6, 16, 26)},
    "Void":    {"p": (150, 80, 255), "s": (90, 40, 200), "fog": (8, 4, 20)},
}

STAGES = [
    {"i": 1, "title": "NEON GATE",      "bio": "Neon"},
    {"i": 2, "title": "EMBER GAUNTLET", "bio": "Ember"},
    {"i": 3, "title": "GLACIER SWEEP",  "bio": "Glacier"},
    {"i": 4, "title": "VOID PILLARS",   "bio": "Void"},
    {"i": 5, "title": "THE CROWN",      "bio": "Void"},
]

FOG = (9, 10, 30)
SLATE = (16, 18, 34)
DARK = (12, 14, 30)
DECK = (10, 12, 26)

# ---------------------------------------------------------------- camera
# Close and low: the base looms, the crown recedes. Vertical pillars
# actually converge because the camera is physically below the tower.
EYE = (520.0, 70.0, 640.0)
TGT = (0.0, 520.0, 0.0)
FOV = 74.0


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def norm(a):
    m = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
    return (a[0] / m, a[1] / m, a[2] / m)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


FWD = norm(sub(TGT, EYE))
RIGHT = norm(cross(FWD, (0.0, 1.0, 0.0)))
UPV = cross(RIGHT, FWD)
FOCAL = (H / 2.0) / math.tan(math.radians(FOV / 2.0))
NEAR = 1.0


def project(p):
    d = sub(p, EYE)
    z = dot(d, FWD)
    if z <= NEAR:
        return None
    x = dot(d, RIGHT)
    y = dot(d, UPV)
    return (W / 2.0 + (x / z) * FOCAL, H / 2.0 - (y / z) * FOCAL, z)


LIGHT = norm((-0.42, 0.80, 0.44))


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(c1, c2, t):
    return (lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t))


# ---------------------------------------------------------------- geometry
BOXES = []      # (center, size, rgb, emissive, yaw)
STRIPS = []     # thin neon bars, always emissive


def box(c, s, col, emissive=False, yaw=0.0):
    BOXES.append((c, s, col, emissive, yaw))


def rot_y(x, z, yaw):
    ca, sa = math.cos(yaw), math.sin(yaw)
    return (x * ca - z * sa, x * sa + z * ca)


def box_faces(c, s, yaw):
    cx, cy, cz = c
    sx, sy, sz = s
    pts = {}
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                lx = (dx - 0.5) * sx
                lz = (dz - 0.5) * sz
                rx, rz = rot_y(lx, lz, yaw)
                pts[(dx, dy, dz)] = (cx + rx, cy + (dy - 0.5) * sy, cz + rz)
    P = pts
    return [
        (P[(0, 0, 1)], P[(0, 1, 1)], P[(1, 1, 1)], P[(1, 0, 1)]),
        (P[(1, 0, 0)], P[(1, 1, 0)], P[(0, 1, 0)], P[(0, 0, 0)]),
        (P[(1, 0, 1)], P[(1, 1, 1)], P[(1, 1, 0)], P[(1, 0, 0)]),
        (P[(0, 0, 0)], P[(0, 1, 0)], P[(0, 1, 1)], P[(0, 0, 1)]),
        (P[(0, 1, 1)], P[(0, 1, 0)], P[(1, 1, 0)], P[(1, 1, 1)]),
        (P[(0, 0, 0)], P[(0, 0, 1)], P[(1, 0, 1)], P[(1, 0, 0)]),
    ]


# --- ground grid: radial spokes, the depth cue that sells the scale
for k in range(36):
    a = k * math.pi * 2 / 36
    box((math.cos(a) * 1500, -14, math.sin(a) * 1500),
        (1.0, 0.3, 3000), (34, 52, 104), True, yaw=-a)

# --- lobby deck 120x6x120 at y=6, neon border, corner pylons, monolith
box((0, 6, 0), (120, 6, 120), DECK)
half = 60.0
for i in range(4):
    a = i * math.pi / 2
    ox, oz = math.cos(a) * (half - 2), math.sin(a) * (half - 2)
    box((ox, 9.05, oz), (114, 0.4, 1.6), (0, 225, 255) if i % 2 == 0 else (255, 0, 190), True, yaw=-(a + math.pi / 2))
for cx, cz in ((-half, -half), (half, -half), (-half, half), (half, half)):
    box((cx, 23, cz), (4, 34, 4), (14, 16, 32))
    box((cx, 40, cz), (6, 2, 6), (0, 225, 255), True)
box((0, 26, -54), (96, 22, 3), (8, 10, 22))
box((0, 37.1, -54), (96, 0.8, 3.4), (0, 225, 255), True)
box((0, 14.9, -54), (96, 0.8, 3.4), (255, 0, 190), True)
box((0, 9.5, 20), (12, 1, 12), (0, 225, 255), True)

# --- stage slabs
for st in STAGES:
    o = stage_y(st["i"])
    bio = BIOMES[st["bio"]]
    p, s = bio["p"], bio["s"]
    box((0, o - 4, 0), (PAD, 8, PAD), SLATE)
    for j in range(-2, 3):
        box((0, o - 9.2, j * (PAD / 5)), (PAD - 6, 1.6, 2), (10, 12, 24))
    h2 = PAD / 2
    for i in range(4):
        a = i * math.pi / 2
        ox, oz = math.cos(a) * (h2 - 1.2), math.sin(a) * (h2 - 1.2)
        box((ox, o + 0.2, oz), (PAD - 8, 0.5, 1.4), p if i % 2 == 0 else s, True, yaw=-(a + math.pi / 2))
    th = 16 + (st["i"] % 2) * 4
    for cx, cz in ((-h2 + 3, -h2 + 3), (h2 - 3, -h2 + 3), (-h2 + 3, h2 - 3), (h2 - 3, h2 - 3)):
        box((cx, o + th / 2, cz), (5, th, 5), DARK)
        box((cx, o + th, cz), (7, 1.6, 7), p, True)
    box((-h2 + 12, o + 0.32, -h2 + 12), (14, 0.6, 14), s, True)

# --- spine columns at radius PAD/2+6, 45 deg offsets
top_y = stage_y(5) + 60
bot_y = -40
rad = PAD / 2 + 6
for i in range(4):
    a = i * math.pi / 2 + math.pi / 4
    x, z = math.cos(a) * rad, math.sin(a) * rad
    box((x, (top_y + bot_y) / 2, z), (2.2, top_y - bot_y, 2.2), DARK)
    box((x, (top_y + bot_y) / 2, z - 1.4), (0.6, top_y - bot_y, 0.6), (0, 225, 255), True)

# --- void shard field (deterministic seed 20261001, 90 shards)
_seed = 20261001


def rnd():
    global _seed
    _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
    return _seed / 0x7FFFFFFF


for i in range(90):
    a = rnd() * math.pi * 2
    dist = 160 + rnd() * 520
    y = bot_y + rnd() * (top_y - bot_y + 120)
    hh = 10 + rnd() * 60
    ww = 4 + rnd() * 16
    box((math.cos(a) * dist, y, math.sin(a) * dist), (ww, hh, ww), (10, 12, 28),
        yaw=rnd() * math.pi)
    if i % 3 == 0:
        STRIPS.append(((math.cos(a) * dist + ww / 2, y, math.sin(a) * dist),
                       (0.5, hh * 0.8, 0.5),
                       BIOMES["Void"]["p"] if i % 6 == 0 else BIOMES["Void"]["s"]))

for c, s, col in STRIPS:
    box(c, s, col, True)

# ---------------------------------------------------------------- shading
FOG_START, FOG_END = 700.0, 3600.0


def shade(col, ndl, z, emissive):
    if emissive:
        c = col
    else:
        k = 0.34 + 0.66 * max(0.0, ndl)
        c = (col[0] * k, col[1] * k, col[2] * k)
    t = (z - FOG_START) / (FOG_END - FOG_START)
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    t *= 0.92
    return lerp3(c, FOG, t)


# ---------------------------------------------------------------- sky
main = Image.new("RGB", (W * SS, H * SS), (2, 3, 12))
md = ImageDraw.Draw(main)
TOP = (6, 8, 30)
HOR = (18, 12, 42)
for y in range(H * SS):
    t = y / (H * SS)
    c = lerp3(TOP, HOR, t ** 0.7) if t < 0.72 else lerp3(HOR, (3, 4, 14), (t - 0.72) / 0.28)
    md.line([(0, y), (W * SS, y)], fill=(int(c[0]), int(c[1]), int(c[2])))

# stars
_s2 = 98765
for _ in range(900):
    _s2 = (_s2 * 1103515245 + 12345) & 0x7FFFFFFF
    sx = (_s2 / 0x7FFFFFFF) * W
    _s2 = (_s2 * 1103515245 + 12345) & 0x7FFFFFFF
    sy = (_s2 / 0x7FFFFFFF) * H * 0.6
    _s2 = (_s2 * 1103515245 + 12345) & 0x7FFFFFFF
    b = 40 + (_s2 / 0x7FFFFFFF) * 90
    md.point((sx * SS, sy * SS), fill=(int(b), int(b * 1.1), int(b * 1.4)))

# glow behind tower
glow = Image.new("RGB", main.size, (0, 0, 0))
gd = ImageDraw.Draw(glow)
gp = project((0, 470, 0))
if gp:
    gr = 300 * SS
    gd.ellipse([gp[0] * SS - gr, gp[1] * SS - gr * 1.5, gp[0] * SS + gr, gp[1] * SS + gr * 1.5],
               fill=(16, 10, 42))

# Ground light-spill: each stage throws its biome colour onto the deck
# and the grid below it. Without this the tower reads as a 2D overlay.
for st in STAGES:
    bio = BIOMES[st["bio"]]
    for gy, strength, rad in ((-14.0, 0.34, 240.0), (9.0, 0.55, 150.0)):
        sp = project((0, gy, 0))
        if not sp:
            continue
        r = rad * (FOCAL / sp[2]) * 1.8
        col = tuple(int(c * strength) for c in bio["p"])
        gd.ellipse([sp[0] * SS - r, sp[1] * SS - r * 0.32,
                    sp[0] * SS + r, sp[1] * SS + r * 0.32], fill=col)
glow = glow.filter(ImageFilter.GaussianBlur(140 * SS // 2))
main = ImageChops.add(main, glow)

# Contact shadow under the deck so the base visibly sits on something.
sh = project((0, -13.0, 0))
if sh:
    shd = Image.new("L", main.size, 0)
    sd = ImageDraw.Draw(shd)
    sr = 150 * (FOCAL / sh[2]) * 1.6
    sd.ellipse([sh[0] * SS - sr, sh[1] * SS - sr * 0.26,
                sh[0] * SS + sr, sh[1] * SS + sr * 0.26], fill=150)
    shd = shd.filter(ImageFilter.GaussianBlur(34 * SS // 2))
    black0 = Image.new("RGB", main.size, (0, 0, 0))
    main = Image.composite(black0, main, shd)

# ---------------------------------------------------------------- raster
mdraw = ImageDraw.Draw(main)
bloom = Image.new("RGB", main.size, (0, 0, 0))
bdraw = ImageDraw.Draw(bloom)

quads = []
for (c, s, col, em, yaw) in BOXES:
    for f in box_faces(c, s, yaw):
        proj = [project(v) for v in f]
        if any(q is None for q in proj):
            continue
        n = norm(cross(sub(f[1], f[0]), sub(f[2], f[0])))
        ctr = ((f[0][0] + f[2][0]) / 2, (f[0][1] + f[2][1]) / 2, (f[0][2] + f[2][2]) / 2)
        if dot(n, sub(EYE, ctr)) < 0:
            n = (-n[0], -n[1], -n[2])
        depth = sum(q[2] for q in proj) / 4.0
        quads.append((depth, proj, col, em, dot(n, LIGHT)))

quads.sort(key=lambda q: -q[0])

for depth, proj, col, em, ndl in quads:
    rgb = shade(col, ndl, depth, em)
    pts = [(q[0] * SS, q[1] * SS) for q in proj]
    c8 = (int(max(0, min(255, rgb[0]))), int(max(0, min(255, rgb[1]))), int(max(0, min(255, rgb[2]))))
    mdraw.polygon(pts, fill=c8)
    if em:
        bdraw.polygon(pts, fill=c8)

# ---------------------------------------------------------------- bloom
g1 = bloom.filter(ImageFilter.GaussianBlur(14 * SS // 2))
g2 = bloom.filter(ImageFilter.GaussianBlur(52 * SS // 2))
bglow = ImageChops.add(g1, g2, scale=2.0)
main = ImageChops.add(main, bglow)

# ---------------------------------------------------------------- type
d = ImageDraw.Draw(main)


def font(sz):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(p, int(sz * SS))
        except Exception:
            continue
    return ImageFont.load_default()


F_TITLE = font(66)
F_SUB = font(23)
F_STG = font(21)
F_META = font(16)

M = 58
d.text((M * SS, M * SS), "NEON ASCENT", font=F_TITLE, fill=(240, 248, 255))
d.text((M * SS, (M + 80) * SS), "CLIMB  ·  DODGE  ·  ASCEND", font=F_SUB, fill=(160, 100, 255))
d.text((M * SS, (M + 112) * SS), "5 STAGES · 4 BIOMES · FUTURE LIGHTING · ROJO 7.7.0",
       font=F_META, fill=(120, 135, 175))

# stage leader lines anchored to the real projected slab centres
for st in STAGES:
    o = stage_y(st["i"])
    bio = BIOMES[st["bio"]]
    pr = project((PAD / 2 + 4, o + 2, PAD / 2 + 4))
    if not pr:
        continue
    ax, ay = pr[0], pr[1]
    lx = W - 250
    d.line([(ax * SS, ay * SS), (lx * SS, ay * SS)], fill=(70, 90, 160), width=SS)
    d.ellipse([ax * SS - 5 * SS, ay * SS - 5 * SS, ax * SS + 5 * SS, ay * SS + 5 * SS],
              fill=bio["p"])
    d.text(((lx + 12) * SS, (ay - 26) * SS), st["title"], font=F_STG, fill=(235, 245, 255))
    d.text(((lx + 12) * SS, (ay - 2) * SS), st["bio"].upper(), font=F_META, fill=bio["p"])

d.text((M * SS, (H - 40) * SS), "geometry + palette derived from src/shared/Config.lua",
       font=F_META, fill=(78, 88, 118))

# vignette
vig = Image.new("L", main.size, 0)
vd = ImageDraw.Draw(vig)
vd.ellipse([-W * SS * 0.25, -H * SS * 0.15, W * SS * 1.25, H * SS * 1.15], fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(180 * SS // 2))
black = Image.new("RGB", main.size, (0, 0, 0))
main = Image.composite(main, black, vig)

out = main.resize((W, H), Image.LANCZOS)
out.save("/home/stephen/Documents/GitHub/neon-ascent/build/tower_3d.png")
print("wrote tower_3d.png", out.size)
