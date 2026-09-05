#!/usr/bin/env python3
"""Build hard/tapered stationary signals for measuring OVR acoustic support."""

import argparse
import json
import math
import struct
import wave
from pathlib import Path

RATE = 16_000
RESET_S = 0.7
TARGET_RMS = 0.25


def normalized(values: list[float]) -> list[float]:
    rms = math.sqrt(sum(x * x for x in values) / len(values))
    gain = TARGET_RMS / max(rms, 1e-12)
    peak = max(abs(x * gain) for x in values)
    gain *= min(1.0, 0.9 / max(peak, 1e-12))
    return [x * gain for x in values]


def signal(kind: str, duration_ms: int, tapered: bool) -> list[float]:
    count = round(duration_ms * RATE / 1000)
    if kind == "two_tone":
        values = [math.sin(2 * math.pi * 200 * i / RATE) + math.sin(2 * math.pi * 400 * i / RATE)
                  for i in range(count)]
    else:
        frequencies = [200 * n for n in range(1, 16)]
        weights = [sum(math.exp(-0.5 * ((f - formant) / (90 + formant * .06)) ** 2)
                       for formant in (700, 1100, 2400)) / math.sqrt(n)
                   for n, f in enumerate(frequencies, 1)]
        values = [sum(a * math.sin(2 * math.pi * f * i / RATE) for f, a in zip(frequencies, weights))
                  for i in range(count)]
    if tapered:
        fade = min(count // 2, round(0.005 * RATE))
        for i in range(fade):
            gain = 0.5 - 0.5 * math.cos(math.pi * i / fade)
            values[i] *= gain
            values[-1-i] *= gain
    return normalized(values)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_wav", type=Path)
    parser.add_argument("manifest_json", type=Path)
    parser.add_argument("--reverse-order", action="store_true")
    args = parser.parse_args()
    output: list[float] = []
    events: list[dict] = []

    def silence(seconds: float) -> None:
        output.extend([0.0] * round(seconds * RATE))

    silence(RESET_S)
    conditions = [(kind, duration_ms, tapered)
                  for kind in ("two_tone", "vowel_harmonics")
                  for duration_ms in (10, 20, 30, 40, 60, 80, 120, 200, 400, 1000)
                  for tapered in (False, True)]
    if args.reverse_order:
        conditions.reverse()
    for kind, duration_ms, tapered in conditions:
        start = len(output) / RATE
        values = signal(kind, duration_ms, tapered)
        output.extend(values)
        end = len(output) / RATE
        events.append({"label": f"{kind}_{duration_ms}ms_{'tapered' if tapered else 'hard'}",
                       "kind": kind, "duration_ms": duration_ms, "edge": "tapered" if tapered else "hard",
                       "start_s": start, "end_s": end, "post_silence_end_s": end + RESET_S})
        silence(RESET_S)
    output[-1] = 0.0
    pcm = [max(-32768, min(32767, round(x * 32767))) for x in output]
    args.output_wav.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output_wav), "wb") as target:
        target.setnchannels(1); target.setsampwidth(2); target.setframerate(RATE)
        target.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    manifest = {"schema": "ovrlipsync_support_probe_v1", "sample_rate": RATE,
                "reset_silence_s": RESET_S, "target_rms": TARGET_RMS, "taper_ms": 5.0,
                "reverse_order": args.reverse_order, "duration_s": len(output) / RATE, "events": events}
    args.manifest_json.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.output_wav} ({manifest['duration_s']:.3f}s, {len(events)} events)")


if __name__ == "__main__":
    main()
