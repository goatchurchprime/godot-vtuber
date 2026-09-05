#!/usr/bin/env python3
"""Build deterministic tones and vowel-like sounds for probing OVRLipSync."""

import argparse
import json
import math
import random
import struct
import wave
from pathlib import Path


RATE = 16_000


def envelope(index: int, count: int, fade_ms: float = 3.0) -> float:
    fade = min(count // 2, round(RATE * fade_ms / 1000.0))
    edge = min(index + 1, count - index)
    return 1.0 if edge > fade else 0.5 - 0.5 * math.cos(math.pi * edge / (fade + 1))


def harmonic_vowel(seconds: float, f0: float, formants: tuple[float, ...], phases: list[float]) -> list[float]:
    count = round(seconds * RATE)
    harmonics = range(1, int(4000 // f0) + 1)
    weights = []
    for harmonic in harmonics:
        frequency = harmonic * f0
        weight = sum(math.exp(-0.5 * ((frequency - formant) / (90 + formant * 0.06)) ** 2) for formant in formants)
        weights.append(weight / math.sqrt(harmonic))
    normalizer = max(1.0, sum(weights))
    return [
        0.72 * envelope(i, count) * sum(
            weight * math.sin(2 * math.pi * harmonic * f0 * i / RATE + phases[harmonic - 1])
            for harmonic, weight in zip(harmonics, weights)
        ) / normalizer
        for i in range(count)
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_wav", type=Path)
    parser.add_argument("manifest_json", type=Path)
    args = parser.parse_args()
    samples: list[float] = []
    events: list[dict] = []

    def silence(seconds: float) -> None:
        samples.extend([0.0] * round(seconds * RATE))

    def add(label: str, values: list[float], **details: object) -> None:
        start = len(samples) / RATE
        samples.extend(values)
        events.append({"label": label, "start_s": start, "end_s": len(samples) / RATE, **details})

    silence(0.75)
    # A pure stationary carrier reveals whether OVR invents animation motion.
    count = 2 * RATE
    add("pure_220hz", [0.45 * envelope(i, count) * math.sin(2 * math.pi * 220 * i / RATE) for i in range(count)], family="stationary")
    silence(0.75)

    # Identical stationary spectrum, coherent versus fixed random harmonic phase.
    formants = (730.0, 1090.0, 2440.0)
    phase_count = int(4000 // 140)
    add("vowel_coherent", harmonic_vowel(2.0, 140, formants, [0.0] * phase_count), family="phase", phase="coherent")
    silence(0.75)
    rng = random.Random(20260905)
    add("vowel_random_phase", harmonic_vowel(2.0, 140, formants, [rng.random() * 2 * math.pi for _ in range(phase_count)]), family="phase", phase="random")
    silence(0.75)

    # Duration sweep after a full reset estimates minimum usable acoustic support.
    source = harmonic_vowel(1.0, 140, formants, [0.0] * phase_count)
    for duration_ms in (10, 20, 30, 40, 60, 80, 120, 200, 400):
        count = round(duration_ms * RATE / 1000)
        offset = (len(source) - count) // 2
        add(f"duration_{duration_ms}ms", source[offset:offset + count], family="duration", duration_ms=duration_ms)
        silence(0.75)

    # Alternating bursts expose onset, release and any persistence across gaps.
    burst = harmonic_vowel(0.08, 140, formants, [0.0] * phase_count)
    for gap_ms in (10, 20, 40, 80, 160, 320):
        add(f"burst_{gap_ms}ms_a", burst, family="gap", gap_ms=gap_ms)
        silence(gap_ms / 1000)
        add(f"burst_{gap_ms}ms_b", burst, family="gap", gap_ms=gap_ms)
        silence(0.75)

    pcm = [max(-32768, min(32767, round(value * 32767))) for value in samples]
    args.output_wav.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output_wav), "wb") as target:
        target.setnchannels(1); target.setsampwidth(2); target.setframerate(RATE)
        target.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    manifest = {"schema": "ovrlipsync_synthetic_support_probe_v1", "sample_rate": RATE,
                "duration_s": len(samples) / RATE, "events": events}
    args.manifest_json.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.output_wav} ({manifest['duration_s']:.3f}s)")


if __name__ == "__main__":
    main()
