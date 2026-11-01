#!/usr/bin/env python3
"""Synthesise the game's sounds with the standard library. Output is original, so no licences to track.
Usage: python3 -I tools/audio/make_sfx.py"""
import math
import pathlib
import random
import struct
import wave

RATE = 22050
OUT = pathlib.Path(__file__).parent.parent.parent / "assets" / "audio"
random.seed(7)


def write(name, samples):
    peak = max(abs(s) for s in samples) or 1.0
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 30000)) for s in samples))


def noise_lowpass(n, k):
    v, out = 0.0, []
    for _ in range(n):
        v += (random.uniform(-1, 1) - v) * k
        out.append(v)
    return out


def engine():
    # Whole number of cycles at 80 Hz, so the loop has no click.
    n = int(RATE / 80) * 40
    return [sum(math.sin(2 * math.pi * 80 * h * i / RATE) / h for h in (1, 2, 3, 5)) * (1 + 0.25 * math.sin(2 * math.pi * 20 * i / RATE)) for i in range(n)]


def horn():
    n = int(RATE * 0.42)
    return [(math.sin(2 * math.pi * 420 * i / RATE) + math.sin(2 * math.pi * 505 * i / RATE)) * min(1, i / 300, (n - i) / 800) for i in range(n)]


def siren():
    # A loop of one rise and fall, phase-tracked so it stays smooth.
    n = RATE * 2
    out, ph = [], 0.0
    for i in range(n):
        f = 760 + 340 * math.sin(2 * math.pi * i / n)
        ph += 2 * math.pi * f / RATE
        out.append(math.sin(ph) + 0.4 * math.sin(2 * ph))
    return out


def crash():
    n = int(RATE * 0.55)
    nz = noise_lowpass(n, 0.5)
    return [(nz[i] + 0.6 * math.sin(2 * math.pi * 70 * i / RATE)) * math.exp(-i / (RATE * 0.13)) for i in range(n)]


def scratch():
    n = int(RATE * 0.4)
    nz = noise_lowpass(n, 0.9)
    return [nz[i] * (0.5 + 0.5 * math.sin(2 * math.pi * 38 * i / RATE)) * math.sin(math.pi * i / n) for i in range(n)]


def splash():
    n = int(RATE * 1.1)
    nz = noise_lowpass(n, 0.18)
    return [nz[i] * math.exp(-i / (RATE * 0.38)) * min(1, i / 400) for i in range(n)]


def whistle():
    n = int(RATE * 0.6)
    return [math.sin(2 * math.pi * (2300 + 90 * math.sin(2 * math.pi * 28 * i / RATE)) * i / RATE) * min(1, i / 200, (n - i) / 600) for i in range(n)]


def rain():
    n = RATE * 3
    nz = noise_lowpass(n, 0.55)
    fade = 2000  # Crossfade the ends so the loop is seamless.
    return [nz[i] * (i / fade) + nz[n - fade + i] * (1 - i / fade) if i < fade else nz[i] for i in range(n - fade)]


OUT.mkdir(parents=True, exist_ok=True)
for name, fn in [("engine", engine), ("horn", horn), ("siren", siren), ("crash", crash), ("scratch", scratch), ("splash", splash), ("whistle", whistle), ("rain", rain)]:
    write(name, fn())
print("wrote", sorted(p.name for p in OUT.glob("*.wav")))
