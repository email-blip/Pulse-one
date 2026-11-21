#!/usr/bin/env python3
"""Generates the companion wake sound "begleiter-weckruf.wav" (own procedural composition).

Calm rising "sunrise": a soft sine pad (A3/E4/A4) fades in over 10 s, a bell-like arpeggio
(sine with exponential decay plus 2nd/3rd harmonics) enters at 8 s and grows brighter and louder
until about 20 s. Soft limiter, 1 s fade-out, peak normalised to -3 dBFS.

Format: 28 s, 44.1 kHz, 16-bit mono Linear PCM WAV (valid for AlarmKit and notification sounds: < 30 s).
Only the Python standard library is used, so the file can be regenerated anywhere:

    python3 scripts/make-wake-sound.py apps/PulseOne/Sources/Features/Companion/Resources/begleiter-weckruf.wav
"""

import math
import random
import struct
import sys
import wave

RATE = 44_100
DURATION = 28.0
PEAK_DBFS = -3.0


def note(name_semitones_from_a4: int) -> float:
    return 440.0 * (2.0 ** (name_semitones_from_a4 / 12.0))


def smoothstep(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def render() -> list[float]:
    count = int(RATE * DURATION)
    out = [0.0] * count

    # --- Pad: A3, E4, A4 with slight detune and slow tremolo, fades in over 10 s.
    pad = [(note(-12), 0.30), (note(-5), 0.22), (note(0), 0.16)]
    for i in range(count):
        t = i / RATE
        env = smoothstep(t / 10.0) * (0.75 + 0.25 * smoothstep((t - 10.0) / 10.0))
        if env <= 0.0:
            continue
        tremolo = 0.9 + 0.1 * math.sin(2 * math.pi * 0.25 * t)
        s = 0.0
        for freq, amp in pad:
            s += amp * (math.sin(2 * math.pi * freq * t) + 0.5 * math.sin(2 * math.pi * freq * 1.003 * t))
        out[i] += s * env * tremolo * 0.5

    # --- Bell arpeggio from 8 s: A major pentatonic, rising pattern, brighter and louder towards 20 s.
    scale = [note(s) for s in (0, 2, 4, 7, 9, 12, 14, 16, 19, 21)]  # A4 B4 C#5 E5 F#5 A5 ...
    pattern = [0, 2, 3, 5, 4, 6, 5, 7, 6, 8, 7, 9]
    rng = random.Random(7)  # fixed seed: deterministic file
    step = 0.6
    t0 = 8.0
    k = 0
    while t0 < DURATION - 1.5:
        progress = smoothstep((t0 - 8.0) / 12.0)       # 0 at 8 s -> 1 at 20 s
        level = 0.10 + 0.22 * progress
        brightness = 0.15 + 0.45 * progress            # weight of the 2nd/3rd harmonics
        index = pattern[k % len(pattern)] - (0 if progress > 0.5 else 2)
        freq = scale[max(0, min(len(scale) - 1, index))]
        decay = 1.6 + rng.uniform(-0.2, 0.2)
        start = int(t0 * RATE)
        length = min(count - start, int(RATE * 3.5))
        for j in range(length):
            tt = j / RATE
            attack = min(1.0, tt / 0.004)
            env = attack * math.exp(-tt * decay)
            s = math.sin(2 * math.pi * freq * tt)
            s += brightness * 0.5 * math.sin(2 * math.pi * freq * 2.0 * tt) * math.exp(-tt * 1.5)
            s += brightness * 0.25 * math.sin(2 * math.pi * freq * 3.01 * tt) * math.exp(-tt * 2.5)
            out[start + j] += s * env * level
        k += 1
        t0 += step

    # --- Soft limiter, fade-out in the last second, normalise to the target peak.
    out = [math.tanh(1.2 * v) for v in out]
    fade = int(RATE * 1.0)
    for j in range(fade):
        out[count - fade + j] *= 1.0 - j / fade
    peak = max(abs(v) for v in out) or 1.0
    gain = (10 ** (PEAK_DBFS / 20.0)) / peak
    return [v * gain for v in out]


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else "begleiter-weckruf.wav"
    samples = render()
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(round(v * 32767))) for v in samples))
    print(f"{path}: {len(samples) / RATE:.1f} s, peak {20 * math.log10(max(abs(v) for v in samples)):.2f} dBFS")


if __name__ == "__main__":
    main()
