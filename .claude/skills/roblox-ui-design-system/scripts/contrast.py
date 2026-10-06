#!/usr/bin/env python3
"""WCAG contrast check for the colour tokens of a Luau theme module.

Finds `name = rgb(r, g, b)` and `name = Color3.fromRGB(r, g, b)` entries and prints the
contrast ratio of every foreground token against every background token.

  python3 .claude/skills/roblox-ui-design-system/scripts/contrast.py src/Shared/Config/Theme.luau
  python3 .../contrast.py Theme.luau --fg text textDim primary --bg panel background
  python3 .../contrast.py Theme.luau --pair textDim panel

Thresholds (WCAG 2.x): 4.5 for body text, 3.0 for large text (>= 24 px, or 19 px bold) and for
UI components/icons. Exit status 1 when a body-text pair (fg token name containing "text")
is under 4.5, so the script can gate CI.
"""
import argparse
import re
import sys

TOKEN = re.compile(
    r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:rgb|Color3\.fromRGB)\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"
)


def channel(value: int) -> float:
    c = value / 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb) -> float:
    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(a, b) -> float:
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def verdict(value: float) -> str:
    if value >= 7:
        return "AAA"
    if value >= 4.5:
        return "AA"
    if value >= 3:
        return "large/UI only"
    return "FAIL"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("theme")
    parser.add_argument("--fg", nargs="*", help="foreground token names (default: text*, primary, warning, danger, success)")
    parser.add_argument("--bg", nargs="*", help="background token names (default: void, background, panel*)")
    parser.add_argument("--pair", nargs=2, metavar=("FG", "BG"))
    args = parser.parse_args()

    with open(args.theme, encoding="utf-8") as handle:
        tokens = {name: (int(r), int(g), int(b)) for name, r, g, b in TOKEN.findall(handle.read())}
    if not tokens:
        print("no rgb()/Color3.fromRGB() tokens found", file=sys.stderr)
        return 2

    if args.pair:
        missing = [name for name in args.pair if name not in tokens]
        if missing:
            print("unknown token(s): " + ", ".join(missing), file=sys.stderr)
            return 2
        value = ratio(tokens[args.pair[0]], tokens[args.pair[1]])
        print(f"{args.pair[0]} on {args.pair[1]}: {value:.2f}:1 {verdict(value)}")
        return 0

    fg = args.fg or [n for n in tokens if n.startswith("text") or n in ("primary", "warning", "danger", "success", "gold")]
    bg = args.bg or [n for n in tokens if n in ("void", "background") or n.startswith("panel")]
    unknown = [name for name in fg + bg if name not in tokens]
    if unknown:
        print("unknown token(s): " + ", ".join(unknown), file=sys.stderr)
        return 2

    width = max(len(name) for name in fg)
    print(f"{'':{width}}  " + "  ".join(f"{name:>12}" for name in bg))
    failed = []
    for f in fg:
        cells = []
        for b in bg:
            value = ratio(tokens[f], tokens[b])
            cells.append(f"{value:6.2f} {verdict(value)[:5]:>5}")
            if "text" in f.lower() and value < 4.5:
                failed.append(f"{f} on {b} ({value:.2f})")
        print(f"{f:{width}}  " + "  ".join(f"{cell:>12}" for cell in cells))
    if failed:
        print("\nbody-text pairs under 4.5:1 -> use only for large text, hints or disabled states:")
        for item in failed:
            print("  " + item)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
