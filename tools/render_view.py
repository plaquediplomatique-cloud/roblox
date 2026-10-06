#!/usr/bin/env python3
"""Rendu 3D de prévisualisation des cartes MapKit, hors Studio (build/maps/<id>.json -> PNG).

Ce n'est pas le moteur Roblox : c'est un rasteriseur simple (numpy) qui restitue fidèlement
la COMPOSITION d'une scène — volumes, densité de détail, palette, néons, éclairage local,
ombres du soleil, brouillard, panneaux — pour juger un pass de level design, d'habillage ou
d'éclairage et produire des avant/après sans ouvrir Studio.

  lune run tools/export_maps.luau
  python3 tools/render_view.py kestrel              # toutes les caméras d'intro + overview
  python3 tools/render_view.py kestrel --view 2     # une caméra
  python3 tools/render_view.py kestrel --eye 0,12,-40 --target 0,6,0 --name corridor
  python3 tools/render_view.py all --size 960x540   # toutes les cartes

Les images vont dans build/renders/<carte>_<vue>.png.
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MAP_DIR = ROOT / "build" / "maps"
OUT_DIR = ROOT / "build" / "renders"
NEAR = 0.15
FOV = 70.0
SKIP_GROUPS = {"Markers"}
FONT_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
]

# ------------------------------------------------------------------------------------------
# Géométrie
# ------------------------------------------------------------------------------------------


def box_tris(sx, sy, sz):
    x, y, z = sx / 2, sy / 2, sz / 2
    v = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z), (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
    faces = [(0, 1, 2, 3), (5, 4, 7, 6), (4, 0, 3, 7), (1, 5, 6, 2), (3, 2, 6, 7), (4, 5, 1, 0)]
    tris = []
    for a, b, c, d in faces:
        tris.append((v[a], v[b], v[c]))
        tris.append((v[a], v[c], v[d]))
    return tris


def wedge_tris(sx, sy, sz):
    # WedgePart : la pente monte de l'avant-bas (z = -L/2) vers l'arrière-haut (z = +L/2).
    x, y, z = sx / 2, sy / 2, sz / 2
    bfl, bfr, bbl, bbr = (-x, -y, -z), (x, -y, -z), (-x, -y, z), (x, -y, z)
    tbl, tbr = (-x, y, z), (x, y, z)
    tris = [(bfl, bbl, tbl), (bfr, bbr, tbr)]
    for a, b, c, d in ((bfl, bfr, bbr, bbl), (bbl, bbr, tbr, tbl), (bfl, bfr, tbr, tbl)):
        tris.append((a, b, c))
        tris.append((a, c, d))
    return tris


def cylinder_tris(sx, sy, sz, segments=14):
    # Cylindre Roblox : axe le long du X local.
    r, h = min(sy, sz) / 2, sx / 2
    ring = [(math.cos(a) * r, math.sin(a) * r) for a in np.linspace(0, 2 * math.pi, segments, endpoint=False)]
    tris = []
    for i in range(segments):
        (y0, z0), (y1, z1) = ring[i], ring[(i + 1) % segments]
        a, b, c, d = (-h, y0, z0), (h, y0, z0), (h, y1, z1), (-h, y1, z1)
        tris += [(a, b, c), (a, c, d), ((h, 0, 0), (h, y0, z0), (h, y1, z1)), ((-h, 0, 0), (-h, y1, z1), (-h, y0, z0))]
    return tris


def ball_tris(sx, sy, sz, lat=7, lon=12):
    r = min(sx, sy, sz) / 2
    tris = []
    for i in range(lat):
        t0, t1 = math.pi * i / lat, math.pi * (i + 1) / lat
        for j in range(lon):
            p0, p1 = 2 * math.pi * j / lon, 2 * math.pi * (j + 1) / lon

            def pt(t, p):
                return (r * math.sin(t) * math.cos(p), r * math.cos(t), r * math.sin(t) * math.sin(p))

            a, b, c, d = pt(t0, p0), pt(t0, p1), pt(t1, p1), pt(t1, p0)
            tris += [(a, b, c), (a, c, d)]
    return tris


SHAPES = {"Block": box_tris, "Wedge": wedge_tris, "Cylinder": cylinder_tris, "Ball": ball_tris}


def srgb_to_linear(c):
    return np.power(np.clip(np.asarray(c, float), 0, 1), 2.2)


class Scene:
    def __init__(self, data):
        self.data = data
        self.prims = [p for p in data["prims"] if p.get("group") not in SKIP_GROUPS and p["transparency"] < 0.99]
        tris, normals, owners = [], [], []
        for index, prim in enumerate(self.prims):
            c = prim["cf"]
            pos = np.array(c[0:3], float)
            rot = np.array(c[3:12], float).reshape(3, 3)
            local = np.array(SHAPES.get(prim["shape"], box_tris)(*prim["size"]), float)
            world = local @ rot.T + pos
            a, b, cc = world[:, 0], world[:, 1], world[:, 2]
            n = np.cross(b - a, cc - a)
            length = np.linalg.norm(n, axis=1, keepdims=True)
            keep = length[:, 0] > 1e-9
            n = n[keep] / length[keep]
            world = world[keep]
            centers = world.mean(axis=1)
            flip = np.einsum("ij,ij->i", n, centers - pos) < 0
            n[flip] *= -1
            tris.append(world)
            normals.append(n)
            owners.append(np.full(len(world), index))
        self.tris = np.concatenate(tris)
        self.normals = np.concatenate(normals)
        self.owner = np.concatenate(owners)
        self.color = srgb_to_linear([p["color"] for p in self.prims])
        self.transparency = np.array([p["transparency"] for p in self.prims])
        self.material = [p["material"] for p in self.prims]
        self.neon = np.array([m == "Neon" for m in self.material])
        self.casts = np.array([bool(p.get("shadow", True)) and p["transparency"] < 0.5 for p in self.prims])
        alpha_prim = (self.transparency > 0.01) | np.array([m in ("ForceField", "Glass") for m in self.material])
        self.alpha = alpha_prim[self.owner]
        lo = self.tris.reshape(-1, 3).min(axis=0)
        hi = self.tris.reshape(-1, 3).max(axis=0)
        self.bounds = (lo, hi)
        self.lights = []
        for prim in data["prims"]:
            light = prim.get("light")
            if not light:
                continue
            c = prim["cf"]
            rot = np.array(c[3:12], float).reshape(3, 3)
            face = light.get("face") or "Bottom"
            axis = {
                "Bottom": -rot[:, 1], "Top": rot[:, 1], "Front": -rot[:, 2],
                "Back": rot[:, 2], "Right": rot[:, 0], "Left": -rot[:, 0],
            }[face]
            self.lights.append({
                "kind": light["kind"],
                "pos": np.array(c[0:3], float),
                "dir": axis,
                "color": srgb_to_linear(light["color"]),
                "brightness": light["brightness"],
                "range": light["range"],
                "angle": light.get("angle") or 90,
            })


# ------------------------------------------------------------------------------------------
# Rasterisation
# ------------------------------------------------------------------------------------------


def raster(depth, ids, xs, ys, zs, tri_id, perspective=True, write=True):
    """Remplit depth/ids pour un triangle écran (xs, ys) de profondeurs zs ; renvoie le masque."""
    h, w = depth.shape
    x0, x1 = max(int(math.floor(min(xs))), 0), min(int(math.ceil(max(xs))), w - 1)
    y0, y1 = max(int(math.floor(min(ys))), 0), min(int(math.ceil(max(ys))), h - 1)
    if x0 > x1 or y0 > y1:
        return None
    area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
    if abs(area) < 1e-9:
        return None
    px = np.arange(x0, x1 + 1) + 0.5
    py = np.arange(y0, y1 + 1)[:, None] + 0.5
    w0 = ((xs[1] - px) * (ys[2] - py) - (xs[2] - px) * (ys[1] - py)) / area
    w1 = ((xs[2] - px) * (ys[0] - py) - (xs[0] - px) * (ys[2] - py)) / area
    w2 = 1 - w0 - w1
    inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
    if not inside.any():
        return None
    if perspective:
        z = 1.0 / (w0 / zs[0] + w1 / zs[1] + w2 / zs[2])
    else:
        z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
    sub = depth[y0 : y1 + 1, x0 : x1 + 1]
    mask = inside & (z < sub)
    if write and mask.any():
        sub[mask] = z[mask]
        ids[y0 : y1 + 1, x0 : x1 + 1][mask] = tri_id
    return (y0, y1, x0, x1, mask, z)


def clip_near(tri):
    inside = tri[:, 2] <= -NEAR
    if inside.all():
        return [tri]
    if not inside.any():
        return []
    poly = []
    for i in range(3):
        a, b = tri[i], tri[(i + 1) % 3]
        ia, ib = a[2] <= -NEAR, b[2] <= -NEAR
        if ia:
            poly.append(a)
        if ia != ib:
            t = (-NEAR - a[2]) / (b[2] - a[2])
            poly.append(a + (b - a) * t)
    return [np.array([poly[0], poly[i], poly[i + 1]]) for i in range(1, len(poly) - 1)]


def look_at(eye, target):
    forward = np.asarray(target, float) - np.asarray(eye, float)
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0.0, 1.0, 0.0])
    if np.linalg.norm(right) < 1e-6:
        right = np.array([1.0, 0.0, 0.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    return np.stack([right, up, -forward], axis=1)  # colonnes : Right, Up, Back (Roblox)


# ------------------------------------------------------------------------------------------
# Matériaux procéduraux (variation d'albédo, pour lire la richesse des surfaces)
# ------------------------------------------------------------------------------------------


def hash2(x, y):
    return np.modf(np.sin(x * 12.9898 + y * 78.233) * 43758.5453)[0] % 1.0


def value_noise(u, v):
    iu, iv = np.floor(u), np.floor(v)
    fu, fv = u - iu, v - iv
    fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
    a, b = hash2(iu, iv), hash2(iu + 1, iv)
    c, d = hash2(iu, iv + 1), hash2(iu + 1, iv + 1)
    return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


def surface_uv(p, n):
    ax = np.abs(n)
    u = np.where(ax[:, 0] >= np.maximum(ax[:, 1], ax[:, 2]), p[:, 2], p[:, 0])
    v = np.where(ax[:, 1] >= np.maximum(ax[:, 0], ax[:, 2]), p[:, 2], p[:, 1])
    return u, v


def detail(material, p, n):
    u, v = surface_uv(p, n)
    noise = value_noise(u * 0.9, v * 0.9) * 0.6 + value_noise(u * 3.1, v * 3.1) * 0.4
    if material in ("Concrete", "Slate", "Rock", "Pavement", "Asphalt", "Basalt", "Granite", "Cobblestone"):
        return 0.86 + 0.24 * noise
    if material in ("WoodPlanks", "Wood"):
        plank = np.floor(v * 1.4)
        return (0.8 + 0.3 * hash2(plank, plank * 3.1)) * (0.92 + 0.08 * value_noise(u * 6, plank)) * np.where(
            (v * 1.4) % 1.0 < 0.06, 0.6, 1.0
        )
    if material == "DiamondPlate":
        dots = (np.sin(u * 9) * np.sin(v * 9)) > 0.55
        return np.where(dots, 1.18, 0.95) * (0.92 + 0.12 * noise)
    if material == "CorrodedMetal":
        return 0.7 + 0.5 * value_noise(u * 1.7, v * 1.7)
    if material == "Metal":
        return 0.93 + 0.1 * value_noise(u * 8, v * 0.6)
    if material == "Marble":
        vein = np.abs(np.sin(u * 0.8 + v * 0.35 + noise * 5))
        return np.where(vein < 0.06, 1.25, 0.95 + 0.08 * noise)
    if material == "Brick":
        row = np.floor(v)
        mortar = ((v % 1.0) < 0.1) | (((u + row * 1.0) % 2.0) < 0.1)
        return np.where(mortar, 0.7, 0.92 + 0.15 * hash2(np.floor((u + row) / 2), row))
    if material in ("Fabric", "Carpet", "Grass", "Snow", "Sand", "Ice"):
        return 0.93 + 0.12 * value_noise(u * 5, v * 5)
    return 0.97 + 0.05 * noise


# ------------------------------------------------------------------------------------------
# Éclairage
# ------------------------------------------------------------------------------------------


def sun_setup(lighting):
    clock = lighting["clockTime"]
    theta = (clock - 6.0) / 24.0 * 2 * math.pi
    elevation = math.sin(theta)
    direction = np.array([math.cos(theta) * 0.85, max(abs(elevation), 0.05) * 0.95, 0.42])
    direction /= np.linalg.norm(direction)
    if elevation > 0.25:
        color, strength = np.array([1.0, 0.95, 0.88]), 1.0
    elif elevation > 0.0:
        k = elevation / 0.25
        color, strength = np.array([1.0, 0.55 + 0.4 * k, 0.32 + 0.56 * k]), 0.55 + 0.45 * k
    else:
        color, strength = np.array([0.55, 0.66, 0.95]), 0.16  # lune
    return direction, color, strength * lighting["brightness"], elevation


def shadow_map(scene, sun_dir, resolution=2048):
    w = sun_dir
    u = np.cross(w, [0.0, 0.0, 1.0] if abs(w[1]) > 0.9 else [0.0, 1.0, 0.0])
    u /= np.linalg.norm(u)
    v = np.cross(w, u)
    lo, hi = scene.bounds
    corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    cu, cv = corners @ u, corners @ v
    umin, umax, vmin, vmax = cu.min(), cu.max(), cv.min(), cv.max()
    scale = (resolution - 1) / max(umax - umin, vmax - vmin)
    depth = np.full((resolution, resolution), np.inf)
    ids = np.zeros((resolution, resolution), np.int32)
    casters = scene.casts[scene.owner] & ~scene.alpha
    for tri in scene.tris[casters]:
        xs = (tri @ u - umin) * scale
        ys = (tri @ v - vmin) * scale
        zs = -(tri @ w)  # plus petit = plus proche du soleil
        raster(depth, ids, xs, ys, zs, 0, perspective=False)
    return {"u": u, "v": v, "w": w, "umin": umin, "vmin": vmin, "scale": scale, "depth": depth}


def shadowed(sm, points, normals):
    biased = points + normals * 0.25
    x = ((biased @ sm["u"]) - sm["umin"]) * sm["scale"]
    y = ((biased @ sm["v"]) - sm["vmin"]) * sm["scale"]
    d = -(biased @ sm["w"])
    res = sm["depth"].shape[0]
    total = np.zeros(len(points))
    for ox, oy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        xi = np.clip(x.astype(int) + ox, 0, res - 1)
        yi = np.clip(y.astype(int) + oy, 0, res - 1)
        total += (d > sm["depth"][yi, xi] + 0.35).astype(float)
    return total / 4


def sky_map(scene, resolution=512):
    """Hauteur du plafond le plus haut au-dessus de chaque (x, z) : intérieur / extérieur."""
    lo, hi = scene.bounds
    scale = (resolution - 1) / max(hi[0] - lo[0], hi[2] - lo[2])
    depth = np.full((resolution, resolution), np.inf)
    ids = np.zeros((resolution, resolution), np.int32)
    roofs = ~scene.alpha & (scene.normals[:, 1] < -0.5)
    for tri in scene.tris[roofs]:
        xs = (tri[:, 0] - lo[0]) * scale
        ys = (tri[:, 2] - lo[2]) * scale
        zs = -tri[:, 1]
        raster(depth, ids, xs, ys, zs, 0, perspective=False)
    return {"lo": lo, "scale": scale, "depth": depth}


def sky_visibility(sky, points):
    res = sky["depth"].shape[0]
    xi = np.clip(((points[:, 0] - sky["lo"][0]) * sky["scale"]).astype(int), 0, res - 1)
    zi = np.clip(((points[:, 2] - sky["lo"][2]) * sky["scale"]).astype(int), 0, res - 1)
    ceiling = -sky["depth"][zi, xi]  # hauteur du dessous de plafond le plus haut
    return np.where(np.isfinite(ceiling) & (ceiling > points[:, 1] + 0.6), 0.0, 1.0)


def local_lights(scene, points, normals, eye, max_distance):
    total = np.zeros_like(points)
    for light in scene.lights:
        if np.linalg.norm(light["pos"] - eye) > max_distance + light["range"]:
            continue
        offset = light["pos"] - points
        dist = np.linalg.norm(offset, axis=1)
        near = dist < light["range"]
        if not near.any():
            continue
        l = offset[near] / np.maximum(dist[near, None], 1e-4)
        ndl = np.maximum(np.einsum("ij,ij->i", normals[near], l), 0.0)
        ratio = dist[near] / light["range"]
        att = (1 - ratio * ratio) ** 2 / (1 + (dist[near] / (0.3 * light["range"])) ** 2)
        factor = att * ndl * light["brightness"] * 2.4
        if light["kind"] in ("Spot", "Surface"):
            cos_cut = math.cos(math.radians(light["angle"] / 2))
            spot = np.einsum("ij,j->i", -l, light["dir"])
            factor *= np.clip((spot - cos_cut) / 0.12, 0, 1)
        total[near] += factor[:, None] * light["color"]
    return total


def blur(img, radius):
    out = img
    for _ in range(3):
        pad = np.pad(out, ((radius, radius), (radius, radius), (0, 0)), mode="edge")
        c = np.cumsum(np.cumsum(pad, axis=0), axis=1)
        c = np.pad(c, ((1, 0), (1, 0), (0, 0)))
        k = 2 * radius + 1
        out = (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)
    return out


def tonemap(x):
    return np.clip((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0, 1)


# ------------------------------------------------------------------------------------------
# Rendu
# ------------------------------------------------------------------------------------------


def render(scene, eye, rot, width, height, sm, sky, fov=FOV):
    lighting = scene.data["lighting"]
    fpx = (height / 2) / math.tan(math.radians(fov) / 2)
    depth = np.full((height, width), np.inf)
    ids = np.full((height, width), -1, np.int32)

    cam = (scene.tris - eye) @ rot  # coordonnées caméra (z < 0 devant)
    centers = scene.tris.mean(axis=1)
    facing = np.einsum("ij,ij->i", scene.normals, centers - eye) < 0
    visible_any = (cam[:, :, 2] < -NEAR).any(axis=1)
    candidates = np.nonzero(facing & visible_any & ~scene.alpha)[0]

    def project(tri):
        z = -tri[:, 2]
        return width / 2 + tri[:, 0] / z * fpx, height / 2 - tri[:, 1] / z * fpx, z

    for t in candidates:
        for piece in clip_near(cam[t]):
            xs, ys, zs = project(piece)
            raster(depth, ids, xs, ys, zs, t)

    sun_dir, sun_color, sun_strength, elevation = sun_setup(lighting)
    ambient = srgb_to_linear(lighting["ambient"])
    outdoor = srgb_to_linear(lighting["outdoorAmbient"])
    shift = srgb_to_linear(lighting["colorShiftTop"])
    atmosphere = lighting["atmosphere"]
    fog_color = srgb_to_linear(atmosphere["color"])

    # Ciel (dégradé + étoiles la nuit), selon la direction de chaque pixel.
    pix_y = (height / 2 - np.arange(height) - 0.5)[:, None] / fpx
    pix_x = (np.arange(width) + 0.5 - width / 2)[None, :] / fpx
    ray_up = (rot[1, 0] * pix_x + rot[1, 1] * pix_y - rot[1, 2]) / np.sqrt(pix_x**2 + pix_y**2 + 1)
    height_k = np.clip(ray_up, 0, 1)[:, :, None]
    if elevation > 0.0:
        day = min(elevation / 0.3, 1.0)
        zenith = np.array([0.08, 0.2, 0.55]) * (0.35 + 0.65 * day) * lighting["brightness"] * 0.35
        zenith = zenith * (0.6 + 0.4 * shift / max(shift.max(), 1e-3))
        horizon = fog_color * (0.45 + 0.4 * day) * lighting["brightness"] * 0.45
    else:
        zenith = np.array([0.002, 0.003, 0.008])
        horizon = fog_color * 0.07 + np.array([0.004, 0.004, 0.007])
    color = horizon * (1 - height_k) ** 2 + zenith * (1 - (1 - height_k) ** 2)
    if elevation <= 0.05:
        rng = np.random.default_rng(7)
        stars = (rng.random((height, width)) > 0.9985) & (ray_up > 0.05)
        color[stars] += 0.6 * rng.random((int(stars.sum()), 1))

    hit = ids >= 0
    if hit.any():
        py, px = np.nonzero(hit)
        z = depth[hit]
        local = np.stack([(px + 0.5 - width / 2) / fpx * z, (height / 2 - py - 0.5) / fpx * z, -z], axis=1)
        points = local @ rot.T + eye
        tri = ids[hit]
        normals = scene.normals[tri]
        prim = scene.owner[tri]
        albedo = scene.color[prim].copy()
        materials = np.array(scene.material)[prim]
        for material in np.unique(materials):
            sel = materials == material
            albedo[sel] *= detail(material, points[sel], normals[sel])[:, None]

        vis = sky_visibility(sky, points)
        up = np.clip(normals[:, 1], -1, 1)
        amb = (ambient * 0.9)[None, :] * (1 - vis[:, None]) + vis[:, None] * (
            outdoor[None, :] * (0.55 + 0.45 * up[:, None]) + shift[None, :] * 0.12 * np.maximum(up, 0)[:, None]
        )
        amb += ambient[None, :] * 0.35
        lit = amb * 1.8
        ndl = np.maximum(normals @ sun_dir, 0)
        shade = shadowed(sm, points, normals) if sm is not None else np.zeros(len(points))
        lit += (sun_color * sun_strength)[None, :] * (ndl * (1 - shade) * vis.clip(0.35, 1))[:, None]
        lit += local_lights(scene, points, normals, eye, 260.0)
        result = albedo * lit
        neon = scene.neon[prim]
        result[neon] = scene.color[prim][neon] * 2.6
        dist = np.linalg.norm(points - eye, axis=1)
        fog = 1 - np.exp(-atmosphere["density"] * 0.0035 * np.maximum(dist - atmosphere["offset"] * 40, 0))
        fog_tint = fog_color * (0.6 if elevation > 0 else 0.25) + outdoor * 0.2
        result = result * (1 - fog[:, None]) + fog_tint[None, :] * fog[:, None]
        color[py, px] = result

    # Transparents (verre, champs de force) : du plus loin au plus proche, sans écriture de profondeur.
    alpha_ids = np.nonzero(scene.alpha & facing & visible_any)[0]
    if len(alpha_ids):
        order = alpha_ids[np.argsort(-np.linalg.norm(centers[alpha_ids] - eye, axis=1))]
        for t in order:
            prim = scene.owner[t]
            opacity = 1 - max(scene.transparency[prim], 0.35)
            tint = scene.color[prim] * (ambient * 1.5 + outdoor * 0.6 + 0.08)
            if scene.material[prim] == "ForceField":
                tint, opacity = scene.color[prim] * 0.9, 0.25
            for piece in clip_near(cam[t]):
                xs, ys, zs = project(piece)
                res = raster(depth, ids, xs, ys, zs, t, write=False)
                if res is None:
                    continue
                y0, y1, x0, x1, mask, _ = res
                block = color[y0 : y1 + 1, x0 : x1 + 1]
                block[mask] = block[mask] * (1 - opacity) + tint * opacity

    # Bloom (néons, lampes) puis tonemapping et étalonnage
    bloom = lighting["bloom"]
    exposure = 2 ** lighting["exposure"]
    hdr = color * exposure
    lum_hdr = hdr @ np.array([0.2126, 0.7152, 0.0722])
    bright = hdr * (np.maximum(lum_hdr - 1.6, 0) / np.maximum(lum_hdr, 1e-4))[:, :, None]
    quarter = bright[::4, ::4]
    glow = blur(quarter, max(int(bloom["size"] / 8), 2))
    glow = np.kron(glow, np.ones((4, 4, 1)))[:height, :width]
    hdr = hdr + glow * bloom["intensity"] * 1.6
    out = np.power(tonemap(hdr), 1 / 2.2)
    cc = lighting["colorCorrection"]
    out = (out - 0.5) * (1 + cc["contrast"]) + 0.5 + cc["brightness"]
    lum = (out @ np.array([0.299, 0.587, 0.114]))[:, :, None]
    out = lum + (out - lum) * (1 + cc["saturation"])
    out *= np.array(cc["tint"])[None, None, :]
    return np.clip(out, 0, 1), depth, fpx


def draw_signs(image, scene, eye, rot, depth, fpx):
    draw = ImageDraw.Draw(image)
    width, height = image.size
    font_path = next((p for p in FONT_PATHS if Path(p).exists()), None)
    for prim in scene.data["prims"]:
        text = prim.get("sign")
        if not text:
            continue
        c = prim["cf"]
        pos = np.array(c[0:3], float)
        r = np.array(c[3:12], float).reshape(3, 3)
        sx, sy, sz = prim["size"]
        face = prim.get("signFace") or "Front"
        normal, axis_u, half = {
            "Front": (-r[:, 2], r[:, 0], (sx / 2, sz / 2)),
            "Back": (r[:, 2], -r[:, 0], (sx / 2, sz / 2)),
            "Right": (r[:, 0], r[:, 2], (sz / 2, sx / 2)),
            "Left": (-r[:, 0], -r[:, 2], (sz / 2, sx / 2)),
        }.get(face, (-r[:, 2], r[:, 0], (sx / 2, sz / 2)))
        center = pos + normal * half[1]
        if np.dot(normal, eye - center) <= 0:
            continue
        up = r[:, 1]
        corners = [center + axis_u * su * half[0] + up * sv * sy / 2 for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        projected = []
        for corner in corners:
            local = (corner - eye) @ rot
            if local[2] > -NEAR:
                projected = None
                break
            z = -local[2]
            projected.append((width / 2 + local[0] / z * fpx, height / 2 - local[1] / z * fpx, z))
        if not projected:
            continue
        local = (center - eye) @ rot
        distance = -local[2]
        cx = width / 2 + local[0] / distance * fpx
        cy = height / 2 - local[1] / distance * fpx
        if not (0 <= cx < width and 0 <= cy < height):
            continue
        if distance > depth[int(cy), int(cx)] + max(0.6, distance * 0.02):
            continue
        background = tuple(int(255 * v) for v in prim.get("signBackground") or (0.03, 0.04, 0.05))
        fg = tuple(int(255 * min(v * 1.15, 1)) for v in prim.get("signColor") or (1, 1, 1))
        polygon = [(p[0], p[1]) for p in projected]
        if not prim.get("signPlain"):
            draw.polygon(polygon, fill=background, outline=fg)
        box_h = max(abs(projected[2][1] - projected[1][1]), abs(projected[3][1] - projected[0][1]))
        box_w = max(abs(projected[1][0] - projected[0][0]), abs(projected[2][0] - projected[3][0]))
        size = int(min(box_h * 0.62, box_w / max(len(text), 1) * 1.6))
        if size < 6 or font_path is None:
            continue
        font = ImageFont.truetype(font_path, size)
        tw = draw.textlength(text, font=font)
        draw.text((cx - tw / 2, cy - size * 0.6), text, fill=fg, font=font)


def cframe_view(cf):
    pos = np.array(cf[0:3], float)
    rot = np.array(cf[3:12], float).reshape(3, 3)
    return pos, rot


def views_for(data, args):
    if args.eye:
        eye = np.array([float(v) for v in args.eye.split(",")])
        target = np.array([float(v) for v in args.target.split(",")])
        return [(args.name or "custom", eye, look_at(eye, target))]
    views = []
    for index, cf in enumerate(data["intro"], start=1):
        pos, rot = cframe_view(cf)
        views.append((f"intro{index}", pos, rot))
    pos, rot = cframe_view(data["overview"])
    views.append(("overview", pos, rot))
    if args.view:
        views = [views[args.view - 1]]
    return views


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("map", help="id de carte (kestrel, helix, spire, monolith, hub) ou 'all'")
    parser.add_argument("--view", type=int, help="numéro de caméra (1 = première caméra d'intro)")
    parser.add_argument("--eye", help="position de caméra x,y,z")
    parser.add_argument("--target", help="point visé x,y,z (avec --eye)")
    parser.add_argument("--name", help="nom de la vue personnalisée")
    parser.add_argument("--size", default="1280x720")
    parser.add_argument("--suffix", default="", help="suffixe du fichier (ex. _avant)")
    parser.add_argument("--no-shadows", action="store_true")
    args = parser.parse_args()
    width, height = (int(v) for v in args.size.lower().split("x"))
    ids = [p.stem for p in sorted(MAP_DIR.glob("*.json"))] if args.map == "all" else [args.map]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for map_id in ids:
        data = json.loads((MAP_DIR / f"{map_id}.json").read_text())
        scene = Scene(data)
        sun_dir = sun_setup(data["lighting"])[0]
        sm = None if args.no_shadows else shadow_map(scene, sun_dir)
        sky = sky_map(scene)
        for name, eye, rot in views_for(data, args):
            image, depth, fpx = render(scene, eye, rot, width, height, sm, sky)
            picture = Image.fromarray((image * 255).astype(np.uint8))
            draw_signs(picture, scene, eye, rot, depth, fpx)
            out = OUT_DIR / f"{map_id}_{name}{args.suffix}.png"
            picture.save(out)
            print(out.relative_to(ROOT), f"({len(scene.prims)} prims, {len(scene.tris)} tris)")


if __name__ == "__main__":
    main()
