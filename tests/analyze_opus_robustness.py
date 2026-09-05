#!/usr/bin/env python3
"""Compare complete OVR and MEL/ONNX vectors before and after Opus."""

import argparse
import json
import math
from pathlib import Path

SOURCES = ["julian_vowel_probe_16k_plus9db", "timeline_1320-122617-0010", "phase_probe"]
BITRATES = [12, 16, 24, 48]
COLORS = {"ovr_s1":"#22d3ee", "ovr_s75":"#a78bfa", "onnx":"#f59e0b"}
LABELS = {"ovr_s1":"OVR smoothing 1", "ovr_s75":"OVR smoothing 75", "onnx":"MEL/ONNX"}


def load(path: Path):
    return json.loads(path.read_text())["frames"]


def metrics(reference, candidate):
    n=min(len(reference),len(candidate)); a=[x["weights"] for x in reference[:n]]; b=[x["weights"] for x in candidate[:n]]
    valid=[i for i in range(n) if len(a[i])==15 and len(b[i])==15]
    active=[i for i in valid if a[i][0]<.5]
    def rmse(indices): return math.sqrt(sum((a[t][i]-b[t][i])**2 for t in indices for i in range(15))/max(1,len(indices)*15))
    def agreement(indices): return sum(max(range(15),key=lambda i:a[t][i])==max(range(15),key=lambda i:b[t][i]) for t in indices)/max(1,len(indices))
    def movement(values): return sum(sum(abs(values[t][i]-values[t-1][i]) for i in range(15)) for t in range(1,len(values)))/max(1,len(values)-1)
    def switches(values):
        d=[max(range(15),key=lambda i:x[i]) for x in values]
        return sum(x!=y for x,y in zip(d,d[1:]))
    return {"frames":len(valid),"reference_active_frames":len(active),"vector_rmse":rmse(valid),"active_vector_rmse":rmse(active),
            "dominant_agreement":agreement(valid),"active_dominant_agreement":agreement(active),
            "reference_mean_movement":movement(a),"decoded_mean_movement":movement(b),
            "reference_switches":switches(a),"decoded_switches":switches(b)}


def main():
    ap=argparse.ArgumentParser(); ap.add_argument("ovr_dir",type=Path); ap.add_argument("onnx_dir",type=Path)
    ap.add_argument("codec_manifest",type=Path); ap.add_argument("results",type=Path); ap.add_argument("svg",type=Path); args=ap.parse_args()
    result={"schema":"opus_viseme_robustness_v1","comparison":"complete 15-value vectors; no rider reduction or quantization",
            "codec":json.loads(args.codec_manifest.read_text())["codec"],"sources":{}}
    for source in SOURCES:
        result["sources"][source]={}
        for backend in ("ovr_s1","ovr_s75","onnx"):
            if backend.startswith("ovr"):
                smoothing=backend.removeprefix("ovr_s")
                original=load(args.ovr_dir/f"{source}_original_ovr_s{smoothing}.json")
                variants={k:load(args.ovr_dir/f"{source}_opus_{k}k_decoded_ovr_s{smoothing}.json") for k in BITRATES}
            else:
                original=load(args.onnx_dir/f"{source}_original_onnx.json")
                variants={k:load(args.onnx_dir/f"{source}_opus_{k}k_decoded_onnx.json") for k in BITRATES}
            result["sources"][source][backend]={str(k):metrics(original,variants[k]) for k in BITRATES}
    args.results.write_text(json.dumps(result,indent=2)+"\n")

    W,H=1240,760; left=85; top=90; pw=330; ph=245; gap=65
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">','<rect width="100%" height="100%" fill="#111827"/>',
         '<style>text{font-family:sans-serif;fill:#e5e7eb}.title{font-size:20px;font-weight:bold}.small{font-size:12px}.axis{stroke:#64748b}</style>',
         '<text x="24" y="31" class="title">Complete viseme-vector stability after Opus voice compression</text>',
         '<text x="24" y="52" class="small">20 ms mono Opus, constant bitrate. Top: vector RMSE (lower is better). Bottom: dominant agreement (higher is better).</text>']
    for col,source in enumerate(SOURCES):
        x0=left+col*(pw+gap)
        out.append(f'<text x="{x0+pw/2}" y="{top-15}" text-anchor="middle" class="small">{source}</text>')
        for row in range(2):
            y0=top+row*335
            out += [f'<line x1="{x0}" y1="{y0+ph}" x2="{x0+pw}" y2="{y0+ph}" class="axis"/>',f'<line x1="{x0}" y1="{y0}" x2="{x0}" y2="{y0+ph}" class="axis"/>']
            for j,k in enumerate(BITRATES):
                x=x0+j*pw/(len(BITRATES)-1); out.append(f'<text x="{x}" y="{y0+ph+19}" text-anchor="middle" class="small">{k}k</text>')
            for backend in COLORS:
                pts=[]
                for j,k in enumerate(BITRATES):
                    m=result["sources"][source][backend][str(k)]
                    value=m["vector_rmse"] if row==0 else m["dominant_agreement"]
                    y=y0+ph*(value/.32 if row==0 else (1-value))
                    pts.append(f'{x0+j*pw/3:.1f},{y:.1f}')
                out.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{COLORS[backend]}" stroke-width="2.5"/>')
                for pt in pts:
                    x,y=pt.split(','); out.append(f'<circle cx="{x}" cy="{y}" r="3.5" fill="{COLORS[backend]}"/>')
            out.append(f'<text x="{x0-9}" y="{y0+9}" text-anchor="end" class="small">{"0" if row==0 else "100%"}</text>')
            out.append(f'<text x="{x0-9}" y="{y0+ph}" text-anchor="end" class="small">{".32" if row==0 else "0%"}</text>')
    lx=360
    for backend in COLORS:
        out += [f'<line x1="{lx}" y1="735" x2="{lx+25}" y2="735" stroke="{COLORS[backend]}" stroke-width="3"/>',f'<text x="{lx+31}" y="739" class="small">{LABELS[backend]}</text>']; lx+=190
    out.append('</svg>'); args.svg.write_text('\n'.join(out)+'\n')
    for source in SOURCES:
        print(source)
        for backend in COLORS:
            print(backend,[(k,round(result["sources"][source][backend][str(k)]["vector_rmse"],4),round(result["sources"][source][backend][str(k)]["dominant_agreement"],3)) for k in BITRATES])

if __name__=="__main__": main()
