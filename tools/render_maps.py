#!/usr/bin/env python3
"""Rendu en vue de dessus des blueprints exportés (build/maps/*.json -> build/maps/*.png).

Outil de revue de level design hors Studio :
  lune run tools/export_maps.luau && python3 tools/render_maps.py
Légende : sol sombre, volumes colorés par hauteur de sommet (chiffre = hauteur),
caisses/couvertures en ambre, rampes hachurées avec flèche de montée, spawns
(rouge = attaque, cyan = défense), barrières de spawn, sites (contour orange),
zones de callout (pointillés + nom).
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SCALE = 6
MARGIN = 40
ROOT = Path(__file__).resolve().parent.parent
MAP_DIR = ROOT / "build" / "maps"


def footprint(prim):
    c = prim["cf"]
    px, py, pz = c[0], c[1], c[2]
    r00, r01, r02, r10, r11, r12, r20, r21, r22 = c[3:]
    sx, sy, sz = prim["size"]
    pts = []
    for lx, lz in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2)):
        wx = px + r00 * lx + r02 * lz
        wz = pz + r20 * lx + r22 * lz
        pts.append((wx, wz))
    top = py + abs(r11) * sy / 2 + abs(r10) * sx / 2 + abs(r12) * sz / 2
    bottom = py - (top - py)
    return pts, top, bottom


def shade(color, top):
    r, g, b = (int(255 * v) for v in color)
    k = 0.75 + min(max(top, 0), 24) / 24 * 0.6
    return (min(255, int(r * k + 18)), min(255, int(g * k + 18)), min(255, int(b * k + 18)))


def render(path):
    data = json.loads(path.read_text())
    # Vue de level design : l'habillage (Decor/Backdrop, sans collision) est ignoré.
    prims = [p for p in data["prims"] if p["group"] not in ("Decor", "Backdrop")]
    xs, zs = [], []
    for p in prims:
        if p["group"] == "Markers" and p["name"] in ("KillVolume", "Boundary", "BoundaryRoof"):
            continue
        pts, _, _ = footprint(p)
        xs += [q[0] for q in pts]
        zs += [q[1] for q in pts]
    min_x, max_x, min_z, max_z = min(xs), max(xs), min(zs), max(zs)
    width = int((max_x - min_x) * SCALE) + MARGIN * 2
    height = int((max_z - min_z) * SCALE) + MARGIN * 2 + 30

    def to_img(x, z):
        return (MARGIN + (x - min_x) * SCALE, MARGIN + 30 + (max_z - z) * SCALE)

    img = Image.new("RGB", (width, height), (10, 12, 16))
    draw = ImageDraw.Draw(img, "RGBA")
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 11)
        small = ImageFont.truetype("DejaVuSans.ttf", 9)
        title = ImageFont.truetype("DejaVuSans-Bold.ttf", 18)
    except OSError:
        font = small = title = ImageFont.load_default()

    def poly(pts, fill, outline=None, w=1):
        draw.polygon([to_img(x, z) for x, z in pts], fill=fill, outline=outline, width=w)

    order = {"Floor": 0, "Ceiling": -1, "Geometry": 2, "Cover": 3, "Props": 4, "Trim": 5, "Lights": 6, "Markers": 7}
    sortable = []
    for p in prims:
        pts, top, bottom = footprint(p)
        sortable.append((order.get(p["group"], 2), top, p, pts, bottom))
    sortable.sort(key=lambda t: (t[0], t[1]))

    labels = []
    for grp, top, p, pts, bottom in sortable:
        name, tags = p["name"], p.get("tags") or []
        if p["group"] == "Ceiling" or name in ("LightSource", "BoundaryRoof", "KillVolume", "PanelLight"):
            continue
        if name == "Boundary":
            poly(pts, (0, 0, 0, 0), (60, 60, 70), 1)
            continue
        if "CalloutZone" in tags:
            if bottom < 5:
                cx = sum(q[0] for q in pts) / 4
                cz = sum(q[1] for q in pts) / 4
                labels.append((cx, cz, p["attributes"].get("Callout", ""), (180, 190, 205)))
            continue
        if "SiteZone" in tags:
            poly(pts, (255, 190, 70, 40), (255, 190, 70), 2)
            cx = sum(q[0] for q in pts) / 4
            cz = sum(q[1] for q in pts) / 4
            labels.append((cx, cz, "SITE " + p["attributes"].get("Site", ""), (255, 200, 90)))
            continue
        if "SpawnPoint" in tags:
            x, z = p["cf"][0], p["cf"][2]
            col = (255, 90, 54) if p["attributes"].get("Side") == "Attack" else (61, 200, 255)
            cx, cy = to_img(x, z)
            draw.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), fill=col)
            look = (-p["cf"][5], -p["cf"][11])
            draw.line((cx, cy, cx + look[0] * 12, cy - look[1] * 12), fill=col, width=2)
            continue
        if "SpawnBarrier" in tags or "ModeBarrier" in tags:
            col = (255, 90, 54, 170) if p["attributes"].get("Side") == "Attack" else (61, 200, 255, 170)
            if "ModeBarrier" in tags:
                col = (150, 120, 255, 120)
            poly(pts, col, None)
            continue
        if p["group"] == "Markers":
            continue
        if p["material"] == "Neon" or p["group"] == "Trim":
            r, g, b = (int(255 * v) for v in p["color"])
            poly(pts, (r, g, b, 200))
            continue
        alpha = int(255 * (1 - min(p["transparency"], 0.9)))
        if p["group"] == "Floor":
            fill = shade(p["color"], 0) + (alpha,)
            poly(pts, fill, (24, 26, 32))
            continue
        fill = shade(p["color"], top) + (alpha,)
        if p["group"] == "Cover":
            fill = (210, 170, 70, 255) if top <= 4.6 + max(bottom, 0) else (230, 140, 60, 255)
        poly(pts, fill, (0, 0, 0), 1)
        if p["shape"] == "Wedge":
            d = p["attributes"].get("RampDirection", "+X")
            cx = sum(q[0] for q in pts) / 4
            cz = sum(q[1] for q in pts) / 4
            vx, vz = {"+X": (1, 0), "-X": (-1, 0), "+Z": (0, 1), "-Z": (0, -1)}.get(d, (1, 0))
            a = to_img(cx - vx * 3, cz - vz * 3)
            b = to_img(cx + vx * 3, cz + vz * 3)
            draw.line((a, b), fill=(255, 255, 255), width=2)
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            for s in (-1, 1):
                draw.line((b, (b[0] - 8 * math.cos(ang + s * 0.5), b[1] - 8 * math.sin(ang + s * 0.5))), fill=(255, 255, 255), width=2)
        elif top >= 5 and (p["size"][0] * p["size"][2]) > 30:
            cx = sum(q[0] for q in pts) / 4
            cz = sum(q[1] for q in pts) / 4
            draw.text(to_img(cx, cz), f"{top:.0f}", fill=(255, 255, 255), font=small, anchor="mm")

    for x, z, text, col in labels:
        draw.text(to_img(x, z), text, fill=col + (230,), font=font, anchor="mm", stroke_width=2, stroke_fill=(0, 0, 0))

    draw.text((MARGIN, 8), f"{data['id'].upper()}  —  1 case = 10 studs", fill=(230, 237, 243), font=title)
    for gx in range(int(math.floor(min_x / 10)) * 10, int(max_x) + 1, 10):
        a = to_img(gx, min_z)
        draw.line((a[0], height - 12, a[0], height - 6), fill=(90, 100, 115))
    out = path.with_suffix(".png")
    img.save(out)
    print(f"{out.relative_to(ROOT)}  {img.width}x{img.height}")


def main():
    targets = sys.argv[1:] or [p.stem for p in sorted(MAP_DIR.glob("*.json"))]
    for name in targets:
        render(MAP_DIR / f"{name}.json")


if __name__ == "__main__":
    main()
