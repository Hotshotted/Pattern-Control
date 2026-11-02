#!/usr/bin/env python3
"""Draws the App Store / iOS app icon: a three-blade propeller mark on the Cozy cream, 1024 x 1024, RGB (no alpha: the App Store rejects an icon
with transparency). Same mark as the coin's propeller in the game, in the game's colours.
    python3 tools/make_store_icon.py            -> icons/ios-icon-1024.png and docs/store/app-icon-1024.png"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 4096                      # drawn at 4x and scaled down (smooth edges without relying on anti-aliasing of the polygon fill)
CREAM = (255, 242, 220)
CREAM_LIGHT = (255, 249, 236)
ORANGE = (240, 128, 60)
ORANGE_DARK = (206, 96, 36)
INK = (58, 44, 42)
GOLD = (255, 200, 64)

def blade(cx, cy, angle_deg, length, width):
    """A blade pointing at `angle_deg` from the hub: a rounded teardrop, widest a third of the way out."""
    pts = []
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), math.sin(a)       # along the blade
    vx, vy = -uy, ux                        # across it
    n = 48
    for i in range(n + 1):                  # one side out, the other back
        t = i / n
        w = width * math.sin(math.pi * (t ** 0.6)) ** 0.8 * (1.0 - 0.12 * t)
        r = length * t
        sw = length * 0.12 * t * t                  # the sweep: the tip curls to one side like a propeller's
        pts.append((cx + ux * r + vx * (w * 0.5 + sw), cy + uy * r + vy * (w * 0.5 + sw)))
    for i in range(n, -1, -1):
        t = i / n
        w = width * math.sin(math.pi * (t ** 0.6)) ** 0.8 * (1.0 - 0.12 * t)
        r = length * t
        sw = length * 0.12 * t * t
        pts.append((cx + ux * r - vx * (w * 0.5 - sw), cy + uy * r - vy * (w * 0.5 - sw)))
    return pts

def draw() -> Image.Image:
    img = Image.new("RGB", (S, S), CREAM)
    d = ImageDraw.Draw(img)
    # a soft lighter disc behind the mark (a flat stand-in for a gradient: a few stacked discs, blurred)
    glow = Image.new("RGB", (S, S), CREAM)
    gd = ImageDraw.Draw(glow)
    gd.ellipse((S * 0.14, S * 0.14, S * 0.86, S * 0.86), fill=CREAM_LIGHT)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.05))
    img.paste(glow)
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    # the propeller disc: a thin ring where the blades sweep
    ring_r = S * 0.385
    d.ellipse((cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r), outline=(235, 218, 190), width=int(S * 0.012))
    # a soft shadow under the blades, offset down and right
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    for k in range(3):
        sd.polygon(blade(cx + S * 0.014, cy + S * 0.02, -80 + 120 * k, S * 0.36, S * 0.2), fill=(90, 60, 40, 70))
    sh = sh.filter(ImageFilter.GaussianBlur(S * 0.012))
    img.paste(sh, (0, 0), sh)
    d = ImageDraw.Draw(img)
    # the three blades: ink outline, orange body, a lighter leading edge
    for k in range(3):
        ang = -80 + 120 * k
        outer = blade(cx, cy, ang, S * 0.36, S * 0.2)
        d.polygon(outer, fill=INK)
        inner = blade(cx, cy, ang, S * 0.345, S * 0.17)
        d.polygon(inner, fill=ORANGE)
        edge = blade(cx - math.sin(math.radians(ang)) * S * 0.012, cy + math.cos(math.radians(ang)) * S * 0.012, ang, S * 0.32, S * 0.085)
        d.polygon(edge, fill=(247, 160, 96))
    # the hub: ink rim, gold cap, a small highlight
    hub = S * 0.092
    d.ellipse((cx - hub - S * 0.012, cy - hub - S * 0.012, cx + hub + S * 0.012, cy + hub + S * 0.012), fill=INK)
    d.ellipse((cx - hub, cy - hub, cx + hub, cy + hub), fill=GOLD)
    d.ellipse((cx - hub * 0.55, cy - hub * 0.6, cx + hub * 0.2, cy + hub * 0.1), fill=(255, 228, 130))
    d.ellipse((cx - hub * 0.22, cy - hub * 0.22, cx + hub * 0.22, cy + hub * 0.22), fill=INK)
    return img.resize((1024, 1024), Image.LANCZOS).convert("RGB")

if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    icon = draw()
    assert icon.mode == "RGB" and icon.size == (1024, 1024)
    for rel in ("icons/ios-icon-1024.png", "docs/store/app-icon-1024.png"):
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        icon.save(p, optimize=True)
        print("wrote", rel)
