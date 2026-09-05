#!/usr/bin/env python3
"""Build equal-magnitude, different-phase signals for probing OVRLipSync."""

import argparse
import json
import math
import random
import struct
import wave
from pathlib import Path

RATE = 16_000
DURATION = 1.2
GAP = 0.6


def taper(i: int, count: int, milliseconds: float = 5.0) -> float:
    n = min(count // 2, round(RATE * milliseconds / 1000))
    edge = min(i, count - 1 - i)
    return 1.0 if edge >= n else 0.5 - 0.5 * math.cos(math.pi * edge / n)


def tones(frequencies: list[float], phases: list[float], amplitudes: list[float]) -> list[float]:
    count = round(DURATION * RATE)
    normalizer = sum(amplitudes)
    return [
        0.72 * taper(i, count) * sum(
            a * math.sin(2 * math.pi * f * i / RATE + p)
            for f, p, a in zip(frequencies, phases, amplitudes)
        ) / normalizer
        for i in range(count)
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_wav", type=Path)
    parser.add_argument("manifest_json", type=Path)
    args = parser.parse_args()
    output: list[float] = []
    events: list[dict] = []

    def silence(seconds: float = GAP) -> None:
        output.extend([0.0] * round(seconds * RATE))

    def add(label: str, values: list[float], family: str, phases: list[float]) -> None:
        start = len(output) / RATE
        output.extend(values)
        events.append({"label": label, "family": family, "start_s": start,
                       "end_s": len(output) / RATE, "phases_rad": phases})
        silence()

    silence()
    # 200 and 400 Hz land exactly on bins of a 25 ms / 400-sample FFT.
    for label, phase in (("relative_0", 0.0), ("relative_90", math.pi / 2),
                         ("relative_180", math.pi), ("relative_270", 3 * math.pi / 2)):
        add(label, tones([200, 400], [0, phase], [1, 1]), "two_tone_relative_phase", [0, phase])

    # A pure time shift changes absolute FFT phase but preserves waveform identity.
    for shift in (0, 1, 3, 7):
        phases = [-2 * math.pi * 200 * shift / RATE, -2 * math.pi * 400 * shift / RATE]
        add(f"time_shift_{shift}_samples", tones([200, 400], phases, [1, 1]),
            "two_tone_time_shift", phases)

    frequencies = [200.0 * n for n in range(1, 16)]
    amplitudes = [
        sum(math.exp(-0.5 * ((f - formant) / (90 + formant * .06)) ** 2)
            for formant in (700, 1100, 2400)) / math.sqrt(n)
        for n, f in enumerate(frequencies, 1)
    ]
    rng = random.Random(20260905)
    patterns = {
        "harmonics_coherent": [0.0] * len(frequencies),
        "harmonics_alternating": [0.0 if n % 2 else math.pi for n in range(len(frequencies))],
        "harmonics_random_a": [rng.random() * 2 * math.pi for _ in frequencies],
        "harmonics_random_b": [rng.random() * 2 * math.pi for _ in frequencies],
    }
    for label, phases in patterns.items():
        add(label, tones(frequencies, phases, amplitudes), "harmonic_phase", phases)

    # Exact-zero final sample makes playback termination unambiguous.
    output[-1] = 0.0
    pcm = [max(-32768, min(32767, round(x * 32767))) for x in output]
    args.output_wav.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output_wav), "wb") as target:
        target.setnchannels(1); target.setsampwidth(2); target.setframerate(RATE)
        target.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    manifest = {
        "schema": "ovrlipsync_phase_probe_v1", "sample_rate": RATE,
        "analysis_note": "200 Hz multiples are exact bins for a 400-sample FFT",
        "taper_ms": 5.0, "duration_s": len(output) / RATE, "events": events,
    }
    args.manifest_json.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.output_wav} ({manifest['duration_s']:.3f}s, {len(events)} conditions)")


if __name__ == "__main__":
    main()
