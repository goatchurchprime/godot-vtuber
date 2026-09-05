#!/usr/bin/env python3
"""Summarize and graph OVR phase-probe traces using only the Python standard library."""

import argparse
import html
import json
import math
from pathlib import Path


def distance(a: list[float], b: list[float]) -> float:
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)) / len(a))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("trace_s1", type=Path)
    parser.add_argument("trace_s75", type=Path)
    parser.add_argument("results", type=Path)
    parser.add_argument("svg", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    summaries = {}
    traces = {}
    for smoothing, path in (("1", args.trace_s1), ("75", args.trace_s75)):
        trace = json.loads(path.read_text()); traces[smoothing] = trace
        names = trace["viseme_names"]
        rows = []
        for event in manifest["events"]:
            # Exclude 200 ms at both ends, retaining stationary evidence only.
            selected = [f["weights"] for f in trace["frames"]
                        if event["start_s"] + .2 <= f["input_start_s"] < event["end_s"] - .2]
            mean = [sum(row[i] for row in selected) / len(selected) for i in range(len(names))]
            movement = sum(sum(abs(b[i] - a[i]) for i in range(len(names)))
                           for a, b in zip(selected, selected[1:])) / max(1, len(selected) - 1)
            rows.append({"label": event["label"], "family": event["family"],
                         "mean_weights": dict(zip(names, mean)), "mean_frame_l1": movement})
        summaries[smoothing] = rows

    comparisons = {}
    for smoothing, rows in summaries.items():
        by_label = {row["label"]: list(row["mean_weights"].values()) for row in rows}
        comparisons[smoothing] = {
            "relative_phase_max_pair_rmse": max(distance(by_label[a], by_label[b])
                for a in ("relative_0", "relative_90", "relative_180", "relative_270")
                for b in ("relative_0", "relative_90", "relative_180", "relative_270")),
            "time_shift_max_pair_rmse": max(distance(by_label[a], by_label[b])
                for a in ("time_shift_0_samples", "time_shift_1_samples", "time_shift_3_samples", "time_shift_7_samples")
                for b in ("time_shift_0_samples", "time_shift_1_samples", "time_shift_3_samples", "time_shift_7_samples")),
            "harmonic_phase_max_pair_rmse": max(distance(by_label[a], by_label[b])
                for a in ("harmonics_coherent", "harmonics_alternating", "harmonics_random_a", "harmonics_random_b")
                for b in ("harmonics_coherent", "harmonics_alternating", "harmonics_random_a", "harmonics_random_b")),
        }
    result = {"schema": "ovrlipsync_phase_probe_results_v1", "stationary_interval": "200 ms inset at each edge",
              "summaries": summaries, "comparisons": comparisons,
              "timing_ms": {s: traces[s]["timing"] for s in traces}}
    args.results.write_text(json.dumps(result, indent=2) + "\n")

    names = traces["1"]["viseme_names"]
    labels = [e["label"] for e in manifest["events"]]
    width, left, cell, row_h = 1220, 235, 55, 32
    height = 70 + 2 * (55 + len(labels) * row_h)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
             '<rect width="100%" height="100%" fill="#111827"/>',
             '<style>text{font-family:sans-serif;fill:#e5e7eb}.small{font-size:11px}.label{font-size:12px}.title{font-size:19px;font-weight:bold}</style>',
             '<text x="20" y="30" class="title">OVRLipSync response to equal-magnitude, different-phase sounds</text>',
             '<text x="20" y="51" class="small">Cell area and colour encode mean viseme weight; right column is mean frame-to-frame movement. Stable middle 800 ms only.</text>']
    y0 = 82
    for panel, smoothing in enumerate(("1", "75")):
        ybase = y0 + panel * (55 + len(labels) * row_h)
        parts.append(f'<text x="20" y="{ybase}" class="title">OVR smoothing {smoothing}</text>')
        for i, name in enumerate(names):
            parts.append(f'<text x="{left+i*cell+cell/2}" y="{ybase+23}" text-anchor="middle" class="small">{html.escape(name)}</text>')
        parts.append(f'<text x="{left+15*cell+35}" y="{ybase+23}" text-anchor="middle" class="small">motion</text>')
        rows = summaries[smoothing]
        for r, row in enumerate(rows):
            y = ybase + 35 + r * row_h
            parts.append(f'<text x="20" y="{y+19}" class="label">{html.escape(row["label"])}</text>')
            for i, name in enumerate(names):
                value = row["mean_weights"][name]
                size = 4 + 22 * math.sqrt(value)
                hue = 195 - 150 * value
                parts.append(f'<rect x="{left+i*cell+(cell-size)/2:.1f}" y="{y+(row_h-size)/2:.1f}" width="{size:.1f}" height="{size:.1f}" rx="2" fill="hsl({hue:.0f},85%,58%)"/>')
            motion = row["mean_frame_l1"]
            parts.append(f'<rect x="{left+15*cell}" y="{y+10}" width="{min(95, motion*1000):.1f}" height="10" fill="#f59e0b"/>')
            parts.append(f'<text x="{left+15*cell+100}" y="{y+19}" class="small">{motion:.4f}</text>')
    parts.append('</svg>')
    args.svg.write_text("\n".join(parts) + "\n")
    print(json.dumps(comparisons, indent=2))


if __name__ == "__main__":
    main()
