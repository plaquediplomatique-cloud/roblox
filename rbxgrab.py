#!/usr/bin/env python3
"""rbxgrab — récupère le code d'un jeu Roblox à partir de son URL.

    python3 rbxgrab.py https://www.roblox.com/games/1818/Classic-Crossroads
    python3 rbxgrab.py 1818 --out sortie
    python3 rbxgrab.py --file MonJeu.rbxl          # fichier exporté depuis Studio

Étapes : URL -> placeId -> universeId + métadonnées -> téléchargement du .rbxl
-> extraction de tous les Script / LocalScript / ModuleScript (via Lune).

LIMITES (imposées par Roblox, pas contournées ici) :
  * Roblox ne livre le fichier d'un lieu que s'il est « copiable » (uncopylocked)
    ou si vous en êtes propriétaire (cookie .ROBLOSECURITY du compte propriétaire).
  * Le code serveur d'un jeu verrouillé n'est jamais envoyé aux clients : il est
    donc impossible à récupérer, et cet outil n'essaie pas.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

UA = "rbxgrab/1.0"
ROOT = Path(__file__).resolve().parent


def parse_place_id(text: str) -> int:
    """Accepte une URL roblox.com/games/<id>/..., /games/start?placeId=<id> ou un nombre."""
    text = text.strip()
    if text.isdigit():
        return int(text)
    m = re.search(r"/games/(\d+)", text) or re.search(r"[?&]placeId=(\d+)", text)
    if not m:
        raise ValueError(f"placeId introuvable dans : {text!r}")
    return int(m.group(1))


def http(url: str, cookie: str | None = None) -> bytes:
    headers = {"User-Agent": UA, "Accept": "application/json, */*"}
    if cookie:
        headers["Cookie"] = f".ROBLOSECURITY={cookie}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def get_json(url: str, cookie: str | None = None):
    return json.loads(http(url, cookie))


def universe_info(place_id: int) -> dict:
    uid = get_json(f"https://apis.roblox.com/universes/v1/places/{place_id}/universe")["universeId"]
    data = get_json(f"https://games.roblox.com/v1/games?universeIds={uid}")["data"]
    info = data[0] if data else {}
    return {
        "universeId": uid,
        "name": info.get("name", f"place_{place_id}"),
        "creator": (info.get("creator") or {}).get("name", "?"),
        "copyingAllowed": info.get("copyingAllowed"),
    }


def download_place(place_id: int, dest: Path, cookie: str | None) -> None:
    """Télécharge le .rbxl via l'API de livraison d'assets (refusée si verrouillé)."""
    try:
        meta = get_json(f"https://assetdelivery.roblox.com/v2/assetId/{place_id}", cookie)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Refus de Roblox (HTTP {e.code}) : lieu non copiable ou cookie manquant/invalide.")
    errors = meta.get("errors")
    locations = meta.get("locations") or []
    if errors or not locations:
        msg = errors[0].get("message") if errors else "aucune URL de téléchargement"
        raise SystemExit(f"Lieu inaccessible : {msg}. Le jeu n'est pas copiable ou ne vous appartient pas.")
    dest.write_bytes(http(locations[0]["location"]))


def extract_scripts(place_file: Path, out_dir: Path) -> int:
    lune = shutil.which("lune")
    if not lune:
        raise SystemExit("Lune introuvable (https://github.com/lune-org/lune) : installez-le puis relancez.")
    script = ROOT / "tools" / "extract.luau"
    proc = subprocess.run([lune, "run", str(script), "--", str(place_file), str(out_dir)], capture_output=True, text=True)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        raise SystemExit(f"Extraction échouée (code {proc.returncode}).")
    m = re.search(r"(\d+) scripts", proc.stdout)
    return int(m.group(1)) if m else 0


def safe_dirname(name: str) -> str:
    return re.sub(r"[^\w.-]+", "_", name).strip("_") or "jeu"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Télécharge le code d'un jeu Roblox (copiable ou à vous).")
    ap.add_argument("game", nargs="?", help="URL du jeu ou placeId")
    ap.add_argument("--file", type=Path, help="extraire un .rbxl/.rbxlx local au lieu de télécharger")
    ap.add_argument("--out", type=Path, help="dossier de sortie (défaut : sorties/<nom>)")
    ap.add_argument("--cookie", default=os.environ.get("ROBLOSECURITY"),
                    help="cookie .ROBLOSECURITY (ou variable ROBLOSECURITY) pour un jeu à vous")
    args = ap.parse_args(argv)

    if args.file:
        place_file, name = args.file, args.file.stem
    elif args.game:
        place_id = parse_place_id(args.game)
        info = universe_info(place_id)
        name = safe_dirname(info["name"])
        print(f"Jeu : {info['name']} (par {info['creator']}), universe {info['universeId']}, "
              f"copiable : {info['copyingAllowed']}")
        out = args.out or ROOT / "sorties" / name
        out.mkdir(parents=True, exist_ok=True)
        place_file = out / f"{name}.rbxl"
        download_place(place_id, place_file, args.cookie)
        print(f"Place téléchargée : {place_file} ({place_file.stat().st_size} octets)")
    else:
        ap.error("donnez une URL/placeId ou --file")

    out = args.out or ROOT / "sorties" / safe_dirname(name)
    count = extract_scripts(place_file, out / "src")
    print(f"{count} scripts extraits dans {out / 'src'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
