#!/usr/bin/env python3
"""Gera a arte da tela inicial (assets/ui/start_space.png).

Pixel art de verdade: desenha em 384x256 com paleta curta, sombreamento por
dithering (matriz de Bayer) e amplia 4x sem suavizar, ate 1536x1024.
Estrelas que piscam, nave, sinal de radio e titulo sao animados no Godot
(scripts/start_menu.gd); aqui fica so o que e estatico.

Uso: python3 tools/gen_start_art.py [saida.png]
Requer: numpy e Pillow.
"""
import sys
import numpy as np
from PIL import Image

W, H, SCALE = 384, 256, 4
rng = np.random.default_rng(2026)

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
BAYER = np.tile(BAYER4, (H // 4 + 1, W // 4 + 1))[:H, :W]


def hexc(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.uint8)


def value_noise(w, h, cells, octaves=4, seed=0):
    """Ruido de valor com varias oitavas, normalizado em 0..1."""
    r = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = r.random((c + 2, c + 2))
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += np.asarray(img, dtype=float) / 255.0 * amp
        total += amp
        amp *= 0.5
    out /= total
    return (out - out.min()) / (out.max() - out.min())


def paint(img, mask, color):
    img[mask] = color


def dither_level(v, levels):
    """Quantiza v (0..1) em 'levels' degraus, com dithering de Bayer entre eles."""
    s = np.clip(v, 0, 0.9999) * (levels - 1)
    base = np.floor(s)
    frac = s - base
    return (base + (frac > BAYER)).astype(int)


img = np.zeros((H, W, 3), dtype=np.uint8)

# ---------------------------------------------------------------- ceu
sky = [hexc(c) for c in ("#04061a", "#060a24", "#080e2e", "#0b1238", "#10163f", "#171a47", "#1f1d4f")]
yy = np.linspace(0, 1, H)[:, None] * np.ones((1, W))
yy = np.clip(yy * 1.15 + (value_noise(W, H, 3, 2, 1) - 0.5) * 0.10, 0, 1)
lv = dither_level(yy, len(sky))
for i, c in enumerate(sky):
    img[lv == i] = c

# ---------------------------------------------------------------- nebulosas (duas manchas, dither)
yy_i, xx_i = np.mgrid[0:H, 0:W]


def nebula(cx, cy, rx, ry, seed, colors):
    n = value_noise(W, H, 4, 5, seed)
    d = np.sqrt(((xx_i - cx) / rx) ** 2 + ((yy_i - cy) / ry) ** 2)
    v = np.clip((n - 0.42) * 2.2, 0, 1) * np.clip(1.15 - d, 0, 1)
    k = dither_level(v, len(colors) + 1)
    for i, c in enumerate(colors):
        img[k == i + 1] = c


nebula(70, 70, 150, 80, 11, [hexc("#1c1a55"), hexc("#2b1f6b"), hexc("#43297f")])
nebula(330, 110, 120, 70, 23, [hexc("#10224f"), hexc("#17346f"), hexc("#21509a")])

# ---------------------------------------------------------------- estrelas fixas (as brilhantes piscam no Godot)
for _ in range(260):
    x, y = int(rng.integers(0, W)), int(rng.integers(0, 205))
    t = rng.random()
    img[y, x] = hexc("#5a6aa8") if t < 0.6 else hexc("#8ea2dd") if t < 0.9 else hexc("#cfdcff")

# ---------------------------------------------------------------- lua
mx, my, mr = 342, 118, 15
dist = np.sqrt((xx_i - mx) ** 2 + (yy_i - my) ** 2)
moon = dist <= mr
nx, ny = (xx_i - mx) / mr, (yy_i - my) / mr
nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
light = np.clip(-0.55 * nx - 0.45 * ny + 0.7 * nz, 0, 1)
crat = value_noise(W, H, 14, 3, 77)
light = np.clip(light - (crat > 0.66) * 0.22, 0, 1)
mp = [hexc("#2a2f4a"), hexc("#5c6382"), hexc("#98a0bd"), hexc("#d4d9ea")]
k = dither_level(light, len(mp))
for i, c in enumerate(mp):
    img[moon & (k == i)] = c
halo = (dist > mr) & (dist <= mr + 2)
img[halo] = hexc("#1b2150")

# ---------------------------------------------------------------- Terra
R = 330
cx, cy = 192, 190 + R
dx, dy = (xx_i - cx) / R, (yy_i - cy) / R
r2 = dx ** 2 + dy ** 2
disk = r2 <= 1.0
nz = np.sqrt(np.clip(1 - r2, 0, 1))
L = np.array([-0.72, -0.30, 0.62])
L = L / np.linalg.norm(L)
lit = np.clip(dx * L[0] + dy * L[1] + nz * L[2], -1, 1)

# continentes: ruido projetado (sem emendas: o ruido e maior que a area visivel)
NW, NH = W * 3, H * 3
cont = value_noise(NW, NH, 7, 5, 5)
cloud_field = value_noise(NW, NH, 14, 5, 9)
ci = np.clip((dx * 1.5 * W + NW / 2).astype(int), 0, NW - 1)
cj = np.clip((dy * 1.5 * H + NH * 0.72).astype(int), 0, NH - 1)
land_n = cont[cj, ci]
ice = (dy < -0.985) & (value_noise(W, H, 12, 2, 4) > 0.45)
land = land_n > 0.52
mount = land_n > 0.66
shore = (land_n > 0.47) & ~land
cloud = cloud_field[cj, ci] > 0.70

ocean = [hexc("#06163f"), hexc("#0a2a6e"), hexc("#1048a8"), hexc("#1a6ad4"), hexc("#3a98f0")]
green = [hexc("#0e2a1d"), hexc("#17502b"), hexc("#23783a"), hexc("#3fa14a"), hexc("#7bc85a")]
desert = [hexc("#2d2415"), hexc("#5a4521"), hexc("#8c6d33"), hexc("#bd9a48"), hexc("#e0c274")]
cloudp = [hexc("#1a2349"), hexc("#34426f"), hexc("#6e82b5"), hexc("#b9c8ec"), hexc("#f4f8ff")]

dl = dither_level(np.clip(lit * 1.05 + 0.18, 0, 1) ** 0.85, 5)
earth = np.zeros_like(img)
for i in range(5):
    m = dl == i
    earth[m] = ocean[i]
    land_m = m & land
    earth[land_m] = green[i]
    earth[m & mount] = desert[i]
    earth[m & shore] = hexc("#2a8fb8") if i >= 3 else ocean[i]
    earth[m & cloud] = cloudp[i]
    earth[m & ice] = cloudp[i]

# luzes de cidade no lado escuro
night = (lit < 0.10) & land & (rng.random((H, W)) > 0.965)
earth[night] = hexc("#ffd36a")
night2 = (lit < 0.0) & land & (rng.random((H, W)) > 0.985)
earth[night2] = hexc("#fff1b0")

img[disk] = earth[disk]

# atmosfera: aneis finos de azul claro na borda (mais fortes do lado iluminado)
edge = np.sqrt(r2)
glow = [(1.000, 1.012, "#bfeaff"), (1.012, 1.028, "#5cb8ff"), (1.028, 1.050, "#2a6fd6"),
        (1.050, 1.080, "#173c93"), (1.080, 1.115, "#0d2263")]
for lo, hi, col in glow:
    m = (edge > lo) & (edge <= hi)
    keep = (BAYER < np.clip(0.55 + 0.7 * (-dx * L[0] - dy * L[1] - 0.15), 0.15, 1.0))
    if lo >= 1.05:
        keep = keep & (BAYER < 0.62)
    img[m & keep & ~disk] = hexc(col)
rim = disk & (edge > 0.985)
img[rim & (lit > 0.1)] = hexc("#a6dcff")

# ---------------------------------------------------------------- moldura de pixel nas bordas (vinheta)
vig = np.sqrt(((xx_i - W / 2) / (W / 2)) ** 2 + ((yy_i - H / 2) / (H / 2)) ** 2)
dark = dither_level(np.clip((vig - 0.95) * 1.6, 0, 1), 4)
img[dark == 1] = (img[dark == 1] * 0.82).astype(np.uint8)
img[dark == 2] = (img[dark == 2] * 0.66).astype(np.uint8)
img[dark >= 3] = (img[dark >= 3] * 0.5).astype(np.uint8)

out = Image.fromarray(img, "RGB").resize((W * SCALE, H * SCALE), Image.NEAREST)
path = sys.argv[1] if len(sys.argv) > 1 else "assets/ui/start_space.png"
out.save(path, optimize=True)
print("salvo", path, out.size)
