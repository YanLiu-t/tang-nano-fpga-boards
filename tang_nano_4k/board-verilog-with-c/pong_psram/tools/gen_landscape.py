# -*- coding: utf-8 -*-
# Generate a 640x480 RGB888 raw test landscape (921600 bytes) with features
# chosen to expose display artifacts: straight horizon, sharp vertical poles,
# fine regular grid, smooth sky/water gradients, high-contrast edges.
import math, struct, os

W, H = 640, 480
buf = bytearray(W * H * 3)

def put(x, y, r, g, b):
    if 0 <= x < W and 0 <= y < H:
        i = (y * W + x) * 3
        buf[i] = r & 0xFF; buf[i+1] = g & 0xFF; buf[i+2] = b & 0xFF

def lerp(a, b, t):
    return int(a + (b - a) * t)

HORIZON = 250          # straight horizon line y
SUN_CX, SUN_CY, SUN_R = 500, 90, 42

# mountain ridge polyline points (x -> peak height baseline offset)
ridge1 = [(0,250),(70,180),(150,235),(230,150),(320,225),(400,170),
          (480,230),(560,160),(639,225),(639,250),(0,250)]
ridge2 = [(0,250),(90,210),(180,250),(270,195),(360,245),(450,205),
          (540,248),(639,210),(639,250),(0,250)]

def poly_contains(pts, x, y):
    # pts is closed polygon down to horizon; simple: interpolate ridge top at x
    return None

def ridge_y(pts, x):
    for i in range(len(pts)-1):
        x0, y0 = pts[i]; x1, y1 = pts[i+1]
        if x0 <= x <= x1 and x1 != x0:
            t = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * t
    return HORIZON

for y in range(H):
    for x in range(W):
        if y < HORIZON:
            # sky gradient: deep blue top -> pale cyan near horizon
            t = y / HORIZON
            r = lerp(20, 150, t)
            g = lerp(60, 210, t)
            b = lerp(170, 235, t)
            # sun
            d = math.hypot(x - SUN_CX, y - SUN_CY)
            if d <= SUN_R:
                r, g, b = 255, 235, 90
            elif d <= SUN_R + 6:
                r, g, b = 255, 210, 120
            # clouds: soft white blobs
            for (ccx, ccy, cr) in [(120,80,30),(260,60,24),(400,110,26)]:
                cd = math.hypot((x-ccx)*0.6, (y-ccy))
                if cd < cr:
                    k = 1 - cd/cr
                    r = lerp(r, 255, k); g = lerp(g, 255, k); b = lerp(b, 255, k)
            # far mountain (light)
            ry2 = ridge_y(ridge2, x)
            if y >= ry2:
                k = min(1.0, (y - ry2)/40.0)
                r = lerp(120, 90, k); g = lerp(150, 120, k); b = lerp(190, 160, k)
            # near mountain (dark)
            ry1 = ridge_y(ridge1, x)
            if y >= ry1:
                k = min(1.0, (y - ry1)/40.0)
                r = lerp(70, 40, k); g = lerp(100, 70, k); b = lerp(140, 100, k)
        else:
            # water/lake gradient with vertical banding that exposes vertical artifacts
            t = (y - HORIZON) / (H - HORIZON)
            r = lerp(60, 15, t); g = lerp(120, 60, t); b = lerp(180, 120, t)
            # horizontal ripple lines every 4 px (straight -> expose vertical jitter)
            if (y - HORIZON) % 4 == 0:
                r = min(255, r+40); g = min(255, g+40); b = min(255, b+40)

        put(x, y, r, g, b)

# crisp white horizon line (1 px, perfectly straight)
for x in range(W):
    put(x, HORIZON, 255, 255, 255)

# fine vertical reference grid across WHOLE frame every 32 px (2 px wide),
# bright magenta so any drop/duplicate pixel shows as broken/wavy bars
for gx0 in range(0, W, 32):
    for dx in range(1):
        for y in range(H):
            put(gx0+dx, y, 255, 0, 255)

# fine horizontal grid every 32 px (1 px, cyan)
for gy0 in range(0, H, 32):
    for x in range(W):
        # do not overwrite the main horizon contrast too much
        if gy0 != HORIZON:
            put(x, gy0, 0, 255, 255)

# sharp black-and-white vertical fence posts with known width (8 px), spaced evenly
for px0 in range(40, W, 120):
    for x in range(px0, px0+8):
        for y in range(HORIZON+10, HORIZON+120):
            put(x, y, 20, 20, 20)
    # white left highlight edge (1 px perfectly straight)
    for y in range(HORIZON+10, HORIZON+120):
        put(px0, y, 255, 255, 255)

# border: 4 px pure red frame for edge geometry check
for x in range(W):
    for t in range(4):
        put(x, t, 255, 0, 0)
        put(x, H-1-t, 255, 0, 0)
for y in range(H):
    for t in range(4):
        put(t, y, 255, 0, 0)
        put(W-1-t, y, 255, 0, 0)

out = r"d:\tang_nano_4k_psram_hdmi\landscape_640x480.rgb"
with open(out, "wb") as f:
    f.write(buf)
print("wrote", out, os.path.getsize(out), "bytes")

# also try to emit a PNG reference for PC-side comparison
try:
    from PIL import Image
    img = Image.frombytes("RGB", (W, H), bytes(buf))
    png = r"d:\tang_nano_4k_psram_hdmi\landscape_ref.png"
    img.save(png)
    print("PNG ref:", png)
except Exception as e:
    print("PIL not available:", e)
