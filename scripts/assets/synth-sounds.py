#!/usr/bin/env python3
"""Synthesizes the PULSE ONE sound family (Auftrag 02 §5) and prints the register rows.

Three short, soft tones from one world: a glassy bell (sine fundamental + quiet 2nd/3rd partials, slow
attack, exponential decay) tuned to E major (E5, G#5, B5, E6). Same timbre, same room, same loudness.
- po-start:    two rising notes (E5 -> B5)       workout begins
- po-phase:    one note (B5), softer             next phase
- po-complete: three notes (E5, G#5, B5 + E6)    workout complete

Deterministic: same script, same bytes, same SHA-256. Made by us, no third-party material -> CC0.
Output: apps/PulseOne/Sources/Resources/Media/Sounds/<name>.wav (48 kHz, 16-bit, mono).

Usage: python3 scripts/assets/synth-sounds.py
"""
import hashlib
import os
import struct
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "apps", "PulseOne", "Sources", "Resources", "Media", "Sounds")
RATE = 48_000
PEAK_DBFS = -6.0  # loud enough on a phone speaker, quiet next to music in .ambient

NOTES = {"E5": 659.26, "G#5": 830.61, "B5": 987.77, "E6": 1318.51}


def bell(freq, length, gain=1.0):
    t = np.arange(int(RATE * length)) / RATE
    attack = 0.012
    env = np.minimum(t / attack, 1.0) * np.exp(-t * 5.5)
    tone = (np.sin(2 * np.pi * freq * t)
            + 0.22 * np.sin(2 * np.pi * freq * 2.0 * t) * np.exp(-t * 9)
            + 0.08 * np.sin(2 * np.pi * freq * 3.01 * t) * np.exp(-t * 14))
    return gain * env * tone


def place(track, signal, at):
    start = int(RATE * at)
    end = min(len(track), start + len(signal))
    track[start:end] += signal[: end - start]


def room(signal):
    """Tiny early-reflection 'room' shared by every sound, so they sound like one place."""
    out = signal.copy()
    for delay, gain in ((0.023, 0.18), (0.041, 0.12), (0.067, 0.07)):
        shift = int(RATE * delay)
        out[shift:] += gain * signal[:-shift]
    return out


def finish(track):
    track = room(track)
    fade = int(RATE * 0.03)
    track[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(track)) or 1.0
    return track / peak * (10 ** (PEAK_DBFS / 20))


def start():
    track = np.zeros(int(RATE * 0.9))
    place(track, bell(NOTES["E5"], 0.6, 0.8), 0.0)
    place(track, bell(NOTES["B5"], 0.7, 1.0), 0.13)
    return finish(track)


def phase():
    track = np.zeros(int(RATE * 0.6))
    place(track, bell(NOTES["B5"], 0.55, 1.0), 0.0)
    return finish(track) * 0.7  # softer than start/complete: it happens often


def complete():
    track = np.zeros(int(RATE * 1.3))
    place(track, bell(NOTES["E5"], 0.8, 0.7), 0.0)
    place(track, bell(NOTES["G#5"], 0.8, 0.75), 0.11)
    place(track, bell(NOTES["B5"], 1.0, 0.9), 0.22)
    place(track, bell(NOTES["E6"], 1.0, 0.35), 0.22)
    return finish(track)


def write(name, samples):
    path = os.path.join(OUT, f"{name}.wav")
    pcm = np.clip(samples, -1, 1)
    frames = b"".join(struct.pack("<h", int(round(s * 32767))) for s in pcm)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)
    data = open(path, "rb").read()
    return path, hashlib.sha256(data).hexdigest(), len(data), len(samples) / RATE


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in (("po-start", start), ("po-phase", phase), ("po-complete", complete)):
        path, digest, size, seconds = write(name, make())
        print(f"| {name} | {os.path.relpath(path, ROOT)} | {seconds:.2f} s | {size} B | sha256 {digest} |")


if __name__ == "__main__":
    main()
