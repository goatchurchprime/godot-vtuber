#!/usr/bin/env python3
"""Build a deterministic speech probe for inspecting OVRLipSync temporal behaviour."""

import argparse
import json
import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 16_000


def fade(samples: list[int], milliseconds: float = 3.0) -> list[int]:
    result = samples.copy()
    count = min(len(result) // 2, round(SAMPLE_RATE * milliseconds / 1000.0))
    for index in range(count):
        # Half-cosine reaches neither an abrupt start nor an abrupt final sample.
        gain = 0.5 - 0.5 * math.cos(math.pi * (index + 1) / (count + 1))
        result[index] = round(result[index] * gain)
        result[-1 - index] = round(result[-1 - index] * gain)
    return result


def scaled(samples: list[int], gain: float) -> list[int]:
    return [max(-32768, min(32767, round(sample * gain))) for sample in samples]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_wav", type=Path)
    parser.add_argument("output_wav", type=Path)
    parser.add_argument("manifest_json", type=Path)
    parser.add_argument("--start", type=float, default=0.81)
    parser.add_argument("--end", type=float, default=0.94)
    parser.add_argument("--lead-start", type=float, default=0.53)
    args = parser.parse_args()

    with wave.open(str(args.source_wav), "rb") as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, SAMPLE_RATE):
            raise SystemExit("source must be 16-bit, mono, 16 kHz PCM WAV")
        raw = source.readframes(source.getnframes())
    source_samples = list(struct.unpack(f"<{len(raw) // 2}h", raw))

    def section(start: float, end: float) -> list[int]:
        return source_samples[round(start * SAMPLE_RATE):round(end * SAMPLE_RATE)]

    vowel = section(args.start, args.end)
    lead = section(args.lead_start, args.start)
    output: list[int] = []
    events: list[dict] = []

    def silence(seconds: float) -> None:
        output.extend([0] * round(seconds * SAMPLE_RATE))

    def add(label: str, samples: list[int], **parameters: object) -> None:
        start = len(output) / SAMPLE_RATE
        output.extend(fade(samples))
        events.append({
            "label": label,
            "start_s": start,
            "end_s": len(output) / SAMPLE_RATE,
            **parameters,
        })

    # Identical content at different levels: classification versus articulation strength.
    silence(0.5)
    for gain in (0.25, 0.5, 1.0):
        add(f"gain_{gain:g}", scaled(vowel, gain), family="gain", gain=gain)
        silence(0.5)

    # Identical pairs at different gaps: persistent smoothing/state.
    for gap_ms in (0, 20, 100, 500):
        add(f"gap_{gap_ms}_first", vowel, family="gap", gap_ms=gap_ms, occurrence=1)
        silence(gap_ms / 1000.0)
        add(f"gap_{gap_ms}_second", vowel, family="gap", gap_ms=gap_ms, occurrence=2)
        silence(0.5)

    # Centred excerpts: how little waveform evidence still produces the same class.
    for duration_ms in (20, 40, 80, 120):
        count = round(duration_ms * SAMPLE_RATE / 1000.0)
        offset = (len(vowel) - count) // 2
        add(f"duration_{duration_ms}", vowel[offset:offset + count], family="duration", duration_ms=duration_ms)
        silence(0.5)

    # The same target following its natural lead-in, versus after silence.
    add("context_lead", lead, family="context", role="lead")
    add("context_target", vowel, family="context", role="target_after_lead")
    silence(0.5)
    add("isolated_target", vowel, family="context", role="target_after_silence")
    silence(0.5)

    args.output_wav.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output_wav), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(SAMPLE_RATE)
        target.writeframes(struct.pack(f"<{len(output)}h", *output))

    manifest = {
        "schema": "ovrlipsync_temporal_probe_v1",
        "source_wav": str(args.source_wav),
        "source_interval_s": [args.start, args.end],
        "source_lead_interval_s": [args.lead_start, args.start],
        "sample_rate": SAMPLE_RATE,
        "duration_s": len(output) / SAMPLE_RATE,
        "events": events,
    }
    args.manifest_json.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.output_wav} ({manifest['duration_s']:.3f}s, {len(events)} events)")


if __name__ == "__main__":
    main()
