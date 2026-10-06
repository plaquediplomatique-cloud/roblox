#!/usr/bin/env python3
"""Génère le pack de tirs « arcade doux » d'AETHER STRIKE (assets/sounds/weapons/*.mp3).

Pas de réalisme : un « pew / thock » court et rond par famille d'arme — balayage de
fréquence descendant (le corps), petit clic de bruit filtré (l'attaque), décroissance
rapide, AUCUNE traîne ni réverbération. Crête à -9 dBFS : le mix reste doux.

Trois variations par son (seed fixe : régénération identique). Nécessite numpy et ffmpeg.

Usage : python3 tools/gen_weapon_sounds.py [dossier_sortie]
Puis : importer les .mp3 (Creator Hub → Audio), coller les ids dans
src/Shared/Config/SoundPack.luau.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 44100
PEAK_DB = -9.0

# nom : (fréquence de départ Hz, fréquence d'arrivée Hz, durée s, bruit 0..1, coupe-haut Hz, harmonique 0..1)
RECIPES: dict[str, tuple[float, float, float, float, float, float]] = {
    "rifle": (520, 140, 0.12, 0.35, 3200, 0.25),
    "smg": (720, 230, 0.075, 0.3, 3600, 0.2),
    "pistol": (640, 200, 0.09, 0.3, 3400, 0.2),
    "mp": (820, 270, 0.065, 0.25, 3800, 0.15),
    "lmg": (430, 110, 0.14, 0.4, 2800, 0.3),
    "dmr": (480, 120, 0.16, 0.35, 3000, 0.3),
    "sniper": (380, 70, 0.26, 0.4, 2600, 0.35),
    "shotgun": (300, 70, 0.2, 0.6, 2400, 0.3),
    "revolver": (430, 100, 0.18, 0.35, 2800, 0.3),
    "suppressed": (1100, 420, 0.05, 0.5, 2200, 0.0),
    "distant": (220, 60, 0.18, 0.3, 900, 0.1),
    "mech": (2600, 1800, 0.025, 0.7, 6000, 0.0),
}
VARIANTS = 3


def lowpass(signal: np.ndarray, cutoff: float) -> np.ndarray:
    """Passe-bas à un pôle appliqué deux fois (pente douce, aucun artefact)."""
    alpha = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    out = signal
    for _ in range(2):
        y = np.empty_like(out)
        acc = 0.0
        for i, x in enumerate(out):
            acc += alpha * (x - acc)
            y[i] = acc
        out = y
    return out


def synth(recipe: tuple[float, float, float, float, float, float], rng: np.random.Generator) -> np.ndarray:
    start, end, duration, noise, cutoff, harmonic = recipe
    jitter = rng.uniform(0.95, 1.05)
    start, end, duration = start * jitter, end * jitter, duration * rng.uniform(0.94, 1.06)
    n = int(RATE * (duration + 0.02))
    t = np.arange(n) / RATE
    # Balayage exponentiel : le « pew » qui tombe.
    freq = end + (start - end) * np.exp(-t / (duration * 0.28))
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    body = np.sin(phase) + harmonic * np.sin(2 * phase + 0.6)
    body_env = np.exp(-t / (duration * 0.32))
    # Attaque : 2–6 ms de bruit filtré.
    click = lowpass(rng.standard_normal(n), cutoff) * np.exp(-t / 0.006) * 3.0
    hiss = lowpass(rng.standard_normal(n), cutoff * 0.6) * np.exp(-t / (duration * 0.18))
    signal = body * body_env + noise * (click + hiss)
    attack = np.clip(t / 0.0015, 0, 1)  # pas de clic numérique au départ
    fade = np.clip((t[-1] - t) / 0.012, 0, 1)  # fin propre, aucune traîne
    signal = lowpass(signal * attack * fade, cutoff)
    signal /= np.max(np.abs(signal)) + 1e-9
    return signal * 10 ** (PEAK_DB / 20)


def write_mp3(path: str, samples: np.ndarray) -> None:
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    try:
        with wave.open(wav_path, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(RATE)
            handle.writeframes(pcm)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-codec:a", "libmp3lame", "-b:a", "128k", path],
            check=True,
        )
    finally:
        os.remove(wav_path)


def main() -> None:
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "assets/sounds/weapons"
    os.makedirs(out_dir, exist_ok=True)
    rng = np.random.default_rng(7)
    for name, recipe in RECIPES.items():
        for index in range(1, VARIANTS + 1):
            path = os.path.join(out_dir, f"{name}_{index}.mp3")
            write_mp3(path, synth(recipe, rng))
            print("écrit :", path)


if __name__ == "__main__":
    main()
