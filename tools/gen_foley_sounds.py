#!/usr/bin/env python3
"""Génère les pas par matériau et les sons d'interface d'AETHER STRIKE (assets/sounds/{foley,ui}).

Même démarche que tools/gen_weapon_sounds.py : sons courts, secs, sans réverbération,
plusieurs variations (les pas ne doivent jamais sonner « mitraillette »). Crête à -12 dBFS
pour les pas (ils sont nombreux), -14 dBFS pour l'interface (discrète).

Usage : python3 tools/gen_foley_sounds.py
Puis importer les .mp3 (Creator Hub → Audio) et coller les ids dans
src/Shared/Config/SoundPack.luau.
"""

from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_weapon_sounds import RATE, lowpass, write_mp3  # noqa: E402


def normalize(signal: np.ndarray, peak_db: float) -> np.ndarray:
    signal = signal / (np.max(np.abs(signal)) + 1e-9)
    return signal * 10 ** (peak_db / 20)


def envelope(n: int, attack: float, decay: float) -> np.ndarray:
    t = np.arange(n) / RATE
    return np.clip(t / attack, 0, 1) * np.exp(-t / decay)


# Pas : (coupe-haut du bruit Hz, fréquence du « coup » Hz, niveau du coup, résonance Hz, niveau, décroissance s)
STEPS: dict[str, tuple[float, float, float, float, float, float]] = {
    "step_concrete": (2600, 95, 0.7, 0.0, 0.0, 0.035),
    "step_metal": (5200, 120, 0.4, 1250.0, 0.35, 0.05),
    "step_wood": (2000, 140, 0.8, 320.0, 0.3, 0.045),
    "step_soft": (900, 80, 0.6, 0.0, 0.0, 0.03),
}


def step(recipe: tuple[float, float, float, float, float, float], rng: np.random.Generator) -> np.ndarray:
    cutoff, thump_freq, thump_level, ring_freq, ring_level, decay = recipe
    jitter = rng.uniform(0.9, 1.1)
    n = int(RATE * 0.16)
    t = np.arange(n) / RATE
    # Talon puis pointe : deux contacts rapprochés, le second plus doux.
    out = np.zeros(n)
    for offset, gain in ((0.0, 1.0), (rng.uniform(0.028, 0.042), 0.55)):
        start = int(offset * RATE)
        m = n - start
        noise = lowpass(rng.standard_normal(m), cutoff * jitter) * envelope(m, 0.001, decay * 0.6)
        thump = np.sin(2 * np.pi * thump_freq * jitter * t[:m]) * envelope(m, 0.002, decay) * thump_level
        ring = np.sin(2 * np.pi * ring_freq * jitter * t[:m]) * envelope(m, 0.001, decay * 1.4) * ring_level
        out[start:] += gain * (noise + thump + ring)
    out *= np.clip((t[-1] - t) / 0.01, 0, 1)
    return normalize(np.tanh(out * 1.3), -12.0)


def tone(freqs: list[tuple[float, float]], length: float, decay: float, peak: float) -> np.ndarray:
    """Suite de notes (fréquence, début s) : bips d'interface ronds (sinus + octave douce)."""
    n = int(RATE * length)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for freq, start in freqs:
        s = int(start * RATE)
        m = n - s
        local = t[:m]
        out[s:] += (np.sin(2 * np.pi * freq * local) + 0.2 * np.sin(4 * np.pi * freq * local)) * envelope(
            m, 0.002, decay
        )
    out *= np.clip((t[-1] - t) / 0.008, 0, 1)
    return normalize(out, peak)


UI_SOUNDS = {
    "ui_hover": lambda: tone([(2300, 0)], 0.04, 0.012, -20.0),
    "ui_click": lambda: tone([(1500, 0)], 0.07, 0.02, -14.0),
    "ui_back": lambda: tone([(1100, 0)], 0.07, 0.02, -15.0),
    "ui_confirm": lambda: tone([(880, 0), (1320, 0.06)], 0.22, 0.06, -14.0),
    "ui_error": lambda: tone([(420, 0), (330, 0.07)], 0.22, 0.06, -14.0),
    "ui_tick": lambda: tone([(2000, 0)], 0.035, 0.008, -16.0),
    "ui_reward": lambda: tone([(988, 0), (1319, 0.07), (1760, 0.14)], 0.4, 0.09, -13.0),
}


def main() -> None:
    rng = np.random.default_rng(11)
    foley = "assets/sounds/foley"
    ui = "assets/sounds/ui"
    os.makedirs(foley, exist_ok=True)
    os.makedirs(ui, exist_ok=True)
    for name, recipe in STEPS.items():
        for index in range(1, 5):
            path = os.path.join(foley, f"{name}_{index}.mp3")
            write_mp3(path, step(recipe, rng))
            print("écrit :", path)
    for name, make in UI_SOUNDS.items():
        path = os.path.join(ui, f"{name}.mp3")
        write_mp3(path, make())
        print("écrit :", path)


if __name__ == "__main__":
    main()
