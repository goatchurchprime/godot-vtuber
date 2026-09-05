#!/usr/bin/env python3
"""Graph private OVR whisper traces without publishing the source audio."""

import json
import math
import struct
import wave
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).parents[1] / "experiments/010-whispered-speech"
PRIVATE = ROOT / "private"
NAMES = ["sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS", "nn", "RR", "aa", "E", "ih", "oh", "ou"]
COLORS = ["#94a3b8", "#ef4444", "#fb7185", "#f59e0b", "#fde047", "#84cc16", "#22c55e", "#14b8a6", "#06b6d4", "#3b82f6", "#6366f1", "#8b5cf6", "#d946ef", "#f472b6", "#a16207"]


def load_wav():
    with wave.open(str(PRIVATE / "julian_voice_whisper_16k.wav"), "rb") as wav:
        assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 16000)
        raw = wav.readframes(wav.getnframes())
    return [v / 32768.0 for v in struct.unpack(f"<{len(raw) // 2}h", raw)]


def periodicity(frame):
    frame = frame[::2]
    mean = sum(frame) / len(frame)
    values = [v - mean for v in frame]
    best = 0.0
    for lag in range(20, 134):  # 60–400 Hz after 2:1 decimation
        a = values[lag:]
        b = values[:-lag]
        dot = sum(x * y for x, y in zip(a, b))
        norm = math.sqrt(sum(x * x for x in a) * sum(x * x for x in b))
        best = max(best, dot / norm if norm else 0.0)
    return best


def main():
    pcm = load_wav()
    traces = [
        ("original level", json.loads((PRIVATE / "julian_voice_whisper_s1.json").read_text())),
        ("fixed +9 dB", json.loads((PRIVATE / "julian_voice_whisper_plus9db_s1.json").read_text())),
    ]
    duration = len(pcm) / 16000
    width, left, plot_width = 1500, 92, 1360
    frame_width = plot_width / len(traces[0][1]["frames"])
    waveform_y, waveform_h = 58, 82
    heat_y, row_h, gap = 175, 10, 32
    heat_h = row_h * len(NAMES)
    scalar_y, scalar_h = heat_y + 2 * (heat_h + gap) + 12, 85
    height = scalar_y + scalar_h + 48
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#111827"/>',
        '<style>text{font-family:sans-serif;fill:#e5e7eb}.t{font-size:19px;font-weight:bold}.s{font-size:11px}.g{stroke:#64748b;stroke-width:1}</style>',
        '<text x="20" y="27" class="t">OVRLipSync response to whispered speech · smoothing 1 · 10 ms frames</text>',
        '<text x="20" y="45" class="s">Exploratory recording: microphone orientation was not controlled; fixed gain changes level only.</text>',
        f'<text x="16" y="{waveform_y + 18}" class="s">waveform</text>',
        f'<line x1="{left}" y1="{waveform_y + waveform_h / 2}" x2="{left + plot_width}" y2="{waveform_y + waveform_h / 2}" class="g"/>',
    ]
    for px in range(plot_width):
        lo = int(px * len(pcm) / plot_width)
        hi = max(lo + 1, int((px + 1) * len(pcm) / plot_width))
        low, high = min(pcm[lo:hi]), max(pcm[lo:hi])
        parts.append(f'<line x1="{left + px}" y1="{waveform_y + waveform_h * (.5 - .48 * high):.1f}" x2="{left + px}" y2="{waveform_y + waveform_h * (.5 - .48 * low):.1f}" stroke="#cbd5e1"/>')

    summaries = []
    active_mask = []
    periodic = []
    for index in range(len(traces[0][1]["frames"])):
        centre = index * 160 + 80
        short = pcm[index * 160:(index + 1) * 160]
        support = pcm[max(0, centre - 200):min(len(pcm), centre + 200)]
        rms = math.sqrt(sum(v * v for v in short) / max(1, len(short)))
        active_mask.append(rms > 10 ** (-55 / 20))
        periodic.append(periodicity(support) if len(support) == 400 and rms > 10 ** (-55 / 20) else 0.0)

    for trace_index, (label, trace) in enumerate(traces):
        y0 = heat_y + trace_index * (heat_h + gap)
        parts += [f'<text x="16" y="{y0 - 7}" class="s">OVR {label}</text>']
        for viseme, name in enumerate(NAMES):
            y = y0 + viseme * row_h
            parts.append(f'<text x="{left - 7}" y="{y + 8}" text-anchor="end" class="s">{name}</text>')
            for frame_index, frame in enumerate(trace["frames"]):
                weight = frame["weights"][viseme]
                if weight > 0.003:
                    parts.append(f'<rect x="{left + frame_index * frame_width:.2f}" y="{y}" width="{max(1.0, frame_width):.2f}" height="{row_h}" fill="{COLORS[viseme]}" opacity="{min(1.0, .08 + weight):.3f}"/>')
        dominant = [max(range(15), key=frame["weights"].__getitem__) for frame in trace["frames"]]
        counts = Counter(NAMES[value] for value in dominant)
        active = sum(active_mask)
        active_non_silence = sum(mask and value != 0 for mask, value in zip(active_mask, dominant))
        summaries.append({
            "condition": label,
            "frames": len(dominant),
            "active_frames": active,
            "active_non_silence_fraction": active_non_silence / active,
            "dominant_counts": dict(counts),
            "timing": trace["timing"],
        })

    parts += [f'<text x="16" y="{scalar_y + 18}" class="s">periodicity</text>', f'<rect x="{left}" y="{scalar_y}" width="{plot_width}" height="{scalar_h}" fill="#0b1220"/>']
    points = []
    for index, value in enumerate(periodic):
        x = left + index * frame_width
        y = scalar_y + scalar_h * (1 - max(0, min(1, value)))
        points.append(f'{x:.1f},{y:.1f}')
    parts.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="#67e8f9" stroke-width="1.2"/>')
    for second in range(math.ceil(duration) + 1):
        x = left + plot_width * second / duration
        parts += [f'<line x1="{x}" y1="{waveform_y}" x2="{x}" y2="{scalar_y + scalar_h}" class="g" opacity=".25"/>', f'<text x="{x}" y="{height - 12}" text-anchor="middle" class="s">{second}s</text>']
    parts.append('</svg>')
    (ROOT / "comparison.svg").write_text("\n".join(parts) + "\n")
    (ROOT / "results.json").write_text(json.dumps({
        "schema": "ovrlipsync_whisper_summary_v1",
        "recording_duration_s": duration,
        "active_threshold_dbfs": -55,
        "microphone_geometry_controlled": False,
        "conditions": summaries,
    }, indent=2) + "\n")
    print("WHISPER_ANALYSIS_OK", summaries)


if __name__ == "__main__":
    main()
