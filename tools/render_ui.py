#!/usr/bin/env python3
"""render_ui — dessine une scène d'interface exportée par tools/ui_preview.luau.

Moteur de mise en page minimal et fidèle aux règles Roblox utilisées par le jeu :
UDim2 + AnchorPoint, UIPadding, UIListLayout (direction, alignements, LayoutOrder),
AutomaticSize (texte et cadres), ZIndex « Sibling », ClipsDescendants, Rotation,
UICorner, UIStroke (bordure et contour de texte), UIGradient (couleur et transparence,
rotation), texte riche (<font color>, <b>), troncature et retour à la ligne.

Polices : Builder Sans → Inter (proche), RobotoMono → DejaVu Sans Mono ; les autres
familles retombent sur Inter. Le rendu est sur-échantillonné (×2) puis réduit.

Usage : python3 tools/render_ui.py scene.json sortie.png [--bg image.jpg] [--crop x,y,w,h]
"""

from __future__ import annotations

import argparse
import json
import math
import re
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SS = 2  # sur-échantillonnage

INTER = "/usr/share/fonts/opentype/inter/Inter-{}.otf"
INTER_DISPLAY = "/usr/share/fonts/opentype/inter/InterDisplay-{}.otf"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono{}.ttf"

WEIGHTS = {
    "Thin": "Thin",
    "ExtraLight": "ExtraLight",
    "Light": "Light",
    "Regular": "Regular",
    "Medium": "Medium",
    "SemiBold": "SemiBold",
    "Bold": "Bold",
    "ExtraBold": "ExtraBold",
    "Heavy": "Black",
}
WEIGHT_ORDER = ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy"]


def font_path(family: str, weight: str) -> str:
    name = family.rsplit("/", 1)[-1].replace(".json", "")
    if name == "RobotoMono":
        return MONO.format("-Bold" if WEIGHT_ORDER.index(weight) >= WEIGHT_ORDER.index("SemiBold") else "")
    style = WEIGHTS.get(weight, "Regular")
    if name in ("Michroma", "Sarpanch", "GothamSSm"):
        return INTER_DISPLAY.format(style)
    return INTER.format(style)


@lru_cache(maxsize=256)
def load_font(family: str, weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(font_path(family, weight), max(size, 1))


def bolder(weight: str) -> str:
    index = WEIGHT_ORDER.index(weight) if weight in WEIGHT_ORDER else 3
    return WEIGHT_ORDER[max(index, WEIGHT_ORDER.index("Bold"))]


# ------------------------------------------------------------------------------------------
# Texte riche
# ------------------------------------------------------------------------------------------

TAG = re.compile(r"<(/?)(font|b|i|br)\b([^>]*)>", re.IGNORECASE)
COLOR_ATTR = re.compile(r'color\s*=\s*"([^"]+)"', re.IGNORECASE)


def parse_color(value: str):
    value = value.strip()
    if value.startswith("#") and len(value) == 7:
        return tuple(int(value[i : i + 2], 16) / 255 for i in (1, 3, 5))
    match = re.match(r"rgb\((\d+),\s*(\d+),\s*(\d+)\)", value)
    if match:
        return tuple(int(v) / 255 for v in match.groups())
    return None


def rich_runs(text: str, rich: bool):
    """Découpe en segments (texte, couleur | None, gras)."""
    if not rich:
        return [(text, None, False)]
    runs = []
    colors = []
    bold = 0
    position = 0
    for match in TAG.finditer(text):
        if match.start() > position:
            runs.append((text[position : match.start()], colors[-1] if colors else None, bold > 0))
        closing, tag, attrs = match.group(1), match.group(2).lower(), match.group(3)
        if tag == "font":
            if closing:
                if colors:
                    colors.pop()
            else:
                found = COLOR_ATTR.search(attrs)
                colors.append(parse_color(found.group(1)) if found else (colors[-1] if colors else None))
        elif tag == "b":
            bold += -1 if closing else 1
        elif tag == "br":
            runs.append(("\n", None, False))
        position = match.end()
    if position < len(text):
        runs.append((text[position:], colors[-1] if colors else None, bold > 0))
    for entity, char in (("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&quot;", '"')):
        runs = [(t.replace(entity, char), c, b) for t, c, b in runs]
    return runs


def runs_width(runs, family, weight, size):
    total = 0.0
    for text, _, bold in runs:
        total += load_font(family, bolder(weight) if bold else weight, size).getlength(text)
    return total


# ------------------------------------------------------------------------------------------
# Arbre
# ------------------------------------------------------------------------------------------

GUI_CLASSES = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame"}


def modifiers(node, cls):
    return [c for c in node["children"] if c["class"] == cls]


def first(node, cls):
    found = modifiers(node, cls)
    return found[0] if found else None


def is_gui(node):
    return node["class"] in GUI_CLASSES


def padding_of(node, w, h):
    pad = first(node, "UIPadding")
    if not pad:
        return 0.0, 0.0, 0.0, 0.0
    (ls, lo), (rs, ro), (ts, to), (bs, bo) = pad["padding"]
    return ls * w + lo, rs * w + ro, ts * h + to, bs * h + bo


def text_metrics(node, scale):
    size = max(int(round(node["textSize"] * scale * SS)), 1)
    family = node["font"]["family"]
    weight = node["font"]["weight"]
    runs = rich_runs(node.get("text", ""), node.get("rich", False))
    width = runs_width(runs, family, weight, size) / SS
    return width, node["textSize"] * scale


class Layout:
    def __init__(self):
        self.boxes = {}

    def measure(self, node, parent_w, parent_h, scale):
        """Taille absolue (w, h) d'un GuiObject, AutomaticSize compris."""
        sx, ox, sy, oy = node["size"]
        own = scale * self.uiscale(node)
        w = sx * parent_w + ox * scale
        h = sy * parent_h + oy * scale
        w *= self.uiscale(node)
        h *= self.uiscale(node)
        auto = node.get("autoSize", "None")
        if auto == "None":
            return w, h
        pl, pr, pt, pb = (v * own for v in padding_of(node, 0, 0))
        if "text" in node and node.get("text"):
            tw, th = text_metrics(node, own)
            if auto in ("X", "XY"):
                w = max(w, tw + pl + pr)
            if auto in ("Y", "XY"):
                h = max(h, th + pt + pb)
            return w, h
        extent_w, extent_h = self.children_extent(node, w - pl - pr, h - pt - pb, own)
        if auto in ("X", "XY"):
            w = max(w, extent_w + pl + pr)
        if auto in ("Y", "XY"):
            h = max(h, extent_h + pt + pb)
        return w, h

    def uiscale(self, node):
        found = first(node, "UIScale")
        return found["scale"] if found else 1.0

    def visible_children(self, node):
        return [c for c in node["children"] if is_gui(c) and c.get("visible", True)]

    def children_extent(self, node, cw, ch, scale):
        children = self.visible_children(node)
        layout = first(node, "UIListLayout")
        if not children:
            return 0.0, 0.0
        sizes = [self.measure(c, cw, ch, scale) for c in children]
        if layout:
            pad_s, pad_o = layout["padding"]
            if layout["direction"] == "Horizontal":
                gap = pad_s * cw + pad_o * scale
                return sum(s[0] for s in sizes) + gap * (len(sizes) - 1), max(s[1] for s in sizes)
            gap = pad_s * ch + pad_o * scale
            return max(s[0] for s in sizes), sum(s[1] for s in sizes) + gap * (len(sizes) - 1)
        right = bottom = 0.0
        for child, (w, h) in zip(children, sizes):
            psx, pox, psy, poy = child["pos"]
            x = psx * cw + pox * scale - child["anchor"][0] * w
            y = psy * ch + poy * scale - child["anchor"][1] * h
            right = max(right, x + w)
            bottom = max(bottom, y + h)
        return right, bottom

    def place(self, node, rect, scale):
        """rect = zone de contenu du parent (x, y, w, h). Calcule récursivement les boîtes."""
        x0, y0, cw, ch = rect
        children = self.visible_children(node)
        layout = first(node, "UIListLayout")
        sizes = [self.measure(c, cw, ch, scale) for c in children]
        if layout:
            ordered = list(zip(children, sizes))
            if layout["sort"] == "LayoutOrder":
                ordered.sort(key=lambda item: item[0]["order"])
            else:
                ordered.sort(key=lambda item: item[0]["name"])
            pad_s, pad_o = layout["padding"]
            horizontal = layout["direction"] == "Horizontal"
            gap = pad_s * (cw if horizontal else ch) + pad_o * scale
            total = sum(s[0] if horizontal else s[1] for _, s in ordered) + gap * max(len(ordered) - 1, 0)
            if horizontal:
                cursor = x0 + {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}[layout["h"]]
                for child, (w, h) in ordered:
                    y = y0 + {"Top": 0, "Center": (ch - h) / 2, "Bottom": ch - h}[layout["v"]]
                    self.assign(child, (cursor, y, w, h), scale)
                    cursor += w + gap
            else:
                cursor = y0 + {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}[layout["v"]]
                for child, (w, h) in ordered:
                    x = x0 + {"Left": 0, "Center": (cw - w) / 2, "Right": cw - w}[layout["h"]]
                    self.assign(child, (x, cursor, w, h), scale)
                    cursor += h + gap
            return
        for child, (w, h) in zip(children, sizes):
            psx, pox, psy, poy = child["pos"]
            x = x0 + psx * cw + pox * scale - child["anchor"][0] * w
            y = y0 + psy * ch + poy * scale - child["anchor"][1] * h
            self.assign(child, (x, y, w, h), scale)

    def assign(self, node, box, scale):
        self.boxes[id(node)] = box
        x, y, w, h = box
        own = scale * self.uiscale(node)
        pl, pr, pt, pb = padding_of(node, w, h)
        pl, pr, pt, pb = (v * own if abs(v) > 0 else v for v in (pl, pr, pt, pb))
        node["_scale"] = own
        self.place(node, (x + pl, y + pt, w - pl - pr, h - pt - pb), own)


# ------------------------------------------------------------------------------------------
# Dessin
# ------------------------------------------------------------------------------------------


def corner_radius(node, w, h):
    corner = first(node, "UICorner")
    if not corner:
        return 0.0
    scale, offset = corner["radius"]
    return min(scale * min(w, h) + offset * node.get("_scale", 1.0), min(w, h) / 2)


def rounded_mask(w, h, radius, inset=0.0):
    image = Image.new("L", (max(w, 1), max(h, 1)), 0)
    draw = ImageDraw.Draw(image)
    r = max(radius - inset, 0)
    draw.rounded_rectangle([inset, inset, w - 1 - inset, h - 1 - inset], radius=r, fill=255)
    return np.asarray(image, dtype=np.float32) / 255.0


def gradient_field(w, h, rotation):
    """t ∈ [0, 1] le long de la direction du dégradé (coins extrêmes = 0 et 1)."""
    angle = math.radians(rotation)
    dx, dy = math.cos(angle), math.sin(angle)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    projection = (xs - cx) * dx + (ys - cy) * dy
    half = abs(cx * dx) + abs(cy * dy)
    if half < 1e-6:
        return np.full((h, w), 0.5, dtype=np.float32)
    return np.clip(projection / (2 * half) + 0.5, 0, 1)


def sample_sequence(keys, t, components):
    times = np.array([k[0] for k in keys], dtype=np.float32)
    out = []
    for c in range(components):
        values = np.array([k[1 + c] for k in keys], dtype=np.float32)
        out.append(np.interp(t, times, values))
    return out


def apply_gradient(node, rgb, alpha):
    gradient = first(node, "UIGradient")
    if not gradient or not gradient.get("enabled", True):
        return rgb, alpha
    h, w = alpha.shape
    t = gradient_field(w, h, gradient["rotation"])
    r, g, b = sample_sequence(gradient["colors"], t, 3)
    (transparency,) = sample_sequence(gradient["transparency"], t, 1)
    rgb = rgb * np.stack([r, g, b], axis=-1)
    alpha = alpha * (1 - transparency)
    return rgb, alpha


def to_image(rgb, alpha):
    data = np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], axis=-1)
    return Image.fromarray((data * 255 + 0.5).astype(np.uint8), "RGBA")


class Painter:
    def __init__(self, width, height, background):
        self.canvas = Image.new("RGBA", (width * SS, height * SS), (0, 0, 0, 0))
        if background is not None:
            self.canvas.alpha_composite(background.convert("RGBA").resize(self.canvas.size, Image.LANCZOS))

    def composite(self, layer, x, y, clip, rotation=0.0, center=None):
        if rotation:
            layer = layer.rotate(-rotation, resample=Image.BICUBIC, expand=True)
            cx, cy = center
            x, y = cx - layer.width / 2, cy - layer.height / 2
        x, y = int(round(x)), int(round(y))
        left, top, right, bottom = 0, 0, self.canvas.width, self.canvas.height
        if clip:
            left, top, right, bottom = (max(left, clip[0]), max(top, clip[1]), min(right, clip[2]), min(bottom, clip[3]))
        lx0, ly0 = max(left - x, 0), max(top - y, 0)
        lx1, ly1 = min(right - x, layer.width), min(bottom - y, layer.height)
        if lx1 <= lx0 or ly1 <= ly0:
            return
        piece = layer.crop((lx0, ly0, lx1, ly1))
        self.canvas.alpha_composite(piece, dest=(x + lx0, y + ly0))

    def frame(self, node, box, clip):
        x, y, w, h = (v * SS for v in box)
        iw, ih = max(int(round(w)), 1), max(int(round(h)), 1)
        radius = corner_radius(node, box[2], box[3]) * SS
        rotation = node.get("rot", 0) or 0
        center = (x + w / 2, y + h / 2)
        if node["bgT"] < 1:
            alpha = np.full((ih, iw), 1 - node["bgT"], dtype=np.float32)
            rgb = np.broadcast_to(np.array(node["bg"], dtype=np.float32), (ih, iw, 3)).copy()
            rgb, alpha = apply_gradient(node, rgb, alpha)
            if radius > 0:
                alpha = alpha * rounded_mask(iw, ih, radius)
            self.composite(to_image(rgb, alpha), x, y, clip, rotation, center)
        for stroke in modifiers(node, "UIStroke"):
            if not stroke.get("enabled", True) or stroke["t"] >= 1:
                continue
            if stroke["mode"] == "Contextual" and "text" in node:
                continue
            t = stroke["thickness"] * SS * node.get("_scale", 1.0)
            pad = int(math.ceil(t))
            ow, oh = iw + 2 * pad, ih + 2 * pad
            outer = rounded_mask(ow, oh, radius + t if radius > 0 else 0)
            inner = np.zeros((oh, ow), dtype=np.float32)
            inner[pad : pad + ih, pad : pad + iw] = rounded_mask(iw, ih, radius) if radius > 0 else 1
            alpha = np.clip(outer - inner, 0, 1) * (1 - stroke["t"])
            rgb = np.broadcast_to(np.array(stroke["color"], dtype=np.float32), (oh, ow, 3)).copy()
            self.composite(to_image(rgb, alpha), x - pad, y - pad, clip, rotation, center)

    def text(self, node, box, clip):
        text = node.get("text", "")
        if not text or node.get("textT", 0) >= 1:
            return
        scale = node.get("_scale", 1.0)
        size = max(int(round(node["textSize"] * scale * SS)), 1)
        family, weight = node["font"]["family"], node["font"]["weight"]
        pl, pr, pt, pb = (v * scale for v in padding_of(node, box[2], box[3]))
        x, y, w, h = box[0] + pl, box[1] + pt, box[2] - pl - pr, box[3] - pt - pb
        x, y, w, h = x * SS, y * SS, w * SS, h * SS
        runs = rich_runs(text, node.get("rich", False))
        lines = self.wrap(runs, family, weight, size, w if node.get("wrapped") else None)
        if node.get("truncate") == "AtEnd" and not node.get("wrapped"):
            lines = [self.truncate(lines[0], family, weight, size, w)] if lines else lines
        line_height = size
        block = line_height * len(lines)
        top = y + {"Top": 0, "Center": (h - block) / 2, "Bottom": h - block}.get(node["yAlign"], (h - block) / 2)
        base_font = load_font(family, weight, size)
        ascent, descent = base_font.getmetrics()
        baseline_offset = line_height * ascent / max(ascent + descent, 1) + (line_height - line_height) / 2
        layer = Image.new("RGBA", self.canvas.size, (0, 0, 0, 0))
        stroke_layer = Image.new("RGBA", self.canvas.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        stroke_draw = ImageDraw.Draw(stroke_layer)
        stroke = next(
            (s for s in modifiers(node, "UIStroke") if s["mode"] == "Contextual" and s.get("enabled", True)), None
        )
        color = node["textColor"]
        alpha = 1 - node.get("textT", 0)
        for index, line in enumerate(lines):
            width = runs_width(line, family, weight, size)
            cursor = x + {"Left": 0, "Center": (w - width) / 2, "Right": w - width}.get(node["xAlign"], (w - width) / 2)
            baseline = top + index * line_height + baseline_offset
            for part, run_color, bold in line:
                font = load_font(family, bolder(weight) if bold else weight, size)
                rgb = run_color or color
                fill = tuple(int(c * 255 + 0.5) for c in rgb) + (int(alpha * 255 + 0.5),)
                if stroke and stroke["t"] < 1:
                    sw = max(int(round(stroke["thickness"] * SS * scale)), 1)
                    sfill = tuple(int(c * 255 + 0.5) for c in stroke["color"]) + (
                        int((1 - stroke["t"]) * alpha * 255 + 0.5),
                    )
                    stroke_draw.text((cursor, baseline), part, font=font, fill=sfill, anchor="ls", stroke_width=sw, stroke_fill=sfill)
                draw.text((cursor, baseline), part, font=font, fill=fill, anchor="ls")
                cursor += font.getlength(part)
        gradient = first(node, "UIGradient")
        if gradient and gradient.get("enabled", True):
            bx0, by0 = int(max(x, 0)), int(max(y, 0))
            bx1, by1 = int(min(x + w, layer.width)), int(min(y + h, layer.height))
            if bx1 > bx0 and by1 > by0:
                region = np.asarray(layer.crop((bx0, by0, bx1, by1)), dtype=np.float32) / 255
                rgb, a = apply_gradient(node, region[..., :3], region[..., 3])
                layer.paste(to_image(rgb, a), (bx0, by0))
        self.composite(stroke_layer, 0, 0, clip)
        self.composite(layer, 0, 0, clip)

    def wrap(self, runs, family, weight, size, width):
        lines = [[]]
        if width is None:
            for text, color, bold in runs:
                parts = text.split("\n")
                for index, part in enumerate(parts):
                    if index > 0:
                        lines.append([])
                    if part:
                        lines[-1].append((part, color, bold))
            return lines
        current_width = 0.0
        for text, color, bold in runs:
            font = load_font(family, bolder(weight) if bold else weight, size)
            for word in re.split(r"(\s+)", text):
                if word == "":
                    continue
                if "\n" in word:
                    lines.append([])
                    current_width = 0
                    continue
                length = font.getlength(word)
                if current_width + length > width and current_width > 0 and not word.isspace():
                    lines.append([])
                    current_width = 0
                if not (current_width == 0 and word.isspace()):
                    lines[-1].append((word, color, bold))
                    current_width += length
        return lines

    def truncate(self, line, family, weight, size, width):
        if runs_width(line, family, weight, size) <= width:
            return line
        text = "".join(t for t, _, _ in line)
        color, bold = (line[0][1], line[0][2]) if line else (None, False)
        font = load_font(family, weight, size)
        while text and font.getlength(text + "…") > width:
            text = text[:-1]
        return [(text + "…", color, bold)]

    def paint(self, layout, node, clip):
        box = layout.boxes.get(id(node))
        if box is None:
            return
        self.frame(node, box, clip)
        if "text" in node:
            self.text(node, box, clip)
        child_clip = clip
        if node.get("clip"):
            x, y, w, h = (v * SS for v in box)
            rect = (int(x), int(y), int(x + w), int(y + h))
            child_clip = rect if clip is None else (max(rect[0], clip[0]), max(rect[1], clip[1]), min(rect[2], clip[2]), min(rect[3], clip[3]))
        children = [c for c in node["children"] if is_gui(c) and c.get("visible", True)]
        for child in sorted(children, key=lambda c: c.get("z", 1)):
            self.paint(layout, child, child_clip)


def render(scene, background, scale):
    width, height = scene["width"], scene["height"]
    root = scene["root"]
    layout = Layout()
    root["_scale"] = scale
    layout.place(root, (0, 0, width, height), scale)
    painter = Painter(width, height, background)
    children = [c for c in root["children"] if is_gui(c) and c.get("visible", True)]
    for child in sorted(children, key=lambda c: c.get("z", 1)):
        painter.paint(layout, child, None)
    return painter.canvas.resize((width, height), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("scene")
    parser.add_argument("output")
    parser.add_argument("--bg", help="image de fond (capture ou rendu de carte)")
    parser.add_argument("--crop", help="x,y,w,h (pixels 1080p) pour un détail")
    parser.add_argument("--zoom", type=float, default=1.0, help="agrandissement du détail")
    args = parser.parse_args()
    with open(args.scene, encoding="utf-8") as handle:
        scene = json.load(handle)
    background = None
    if args.bg:
        source = Image.open(args.bg).convert("RGB")
        ratio = max(scene["width"] / source.width, scene["height"] / source.height)
        source = source.resize((int(source.width * ratio + 0.5), int(source.height * ratio + 0.5)), Image.LANCZOS)
        left = (source.width - scene["width"]) // 2
        top = (source.height - scene["height"]) // 2
        background = source.crop((left, top, left + scene["width"], top + scene["height"]))
    image = render(scene, background, 1.0)
    if args.crop:
        x, y, w, h = (int(v) for v in args.crop.split(","))
        image = image.crop((x, y, x + w, y + h))
        if args.zoom != 1:
            image = image.resize((int(w * args.zoom), int(h * args.zoom)), Image.LANCZOS)
    image.convert("RGB").save(args.output, quality=92)
    print("écrit :", args.output)


if __name__ == "__main__":
    main()
