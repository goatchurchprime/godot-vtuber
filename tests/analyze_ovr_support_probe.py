#!/usr/bin/env python3
"""Measure and graph convergence and release in the OVR support probe."""

import argparse
import html
import json
import math
from pathlib import Path

NAMES = ["sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS", "nn", "RR", "aa", "E", "ih", "oh", "ou"]
COLORS = {"sil":"#cbd5e1", "PP":"#ef4444", "DD":"#84cc16", "nn":"#8b5cf6",
          "RR":"#d946ef", "aa":"#f472b6", "E":"#c0846c", "ih":"#9ca95c", "oh":"#4d8795", "ou":"#94644c"}


def rmse(a, b):
    return math.sqrt(sum((x-y)**2 for x,y in zip(a,b))/len(a))


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("manifest",type=Path); ap.add_argument("s1",type=Path); ap.add_argument("s75",type=Path)
    ap.add_argument("results",type=Path); ap.add_argument("svg",type=Path); a=ap.parse_args()
    manifest=json.loads(a.manifest.read_text()); traces={"1":json.loads(a.s1.read_text()),"75":json.loads(a.s75.read_text())}
    result={"schema":"ovrlipsync_acoustic_support_v1","settle_rule":"10 consecutive frames within 0.02 RMSE of own 500-900 ms mean","conditions":{}}
    series={}
    for smoothing,trace in traces.items():
        rows=[]
        for kind in ("two_tone","vowel_harmonics"):
            for edge in ("hard","tapered"):
                e=next(x for x in manifest["events"] if x["kind"]==kind and x["duration_ms"]==1000 and x["edge"]==edge)
                inside=[f["weights"] for f in trace["frames"] if e["start_s"]<=f["input_start_s"]<e["end_s"]]
                post=[f["weights"] for f in trace["frames"] if e["end_s"]<=f["input_start_s"]<e["end_s"]+.5]
                steady=[sum(x[i] for x in inside[50:90])/40 for i in range(15)]
                distances=[rmse(x,steady) for x in inside]
                settle=next((i*10 for i in range(len(distances)-9) if max(distances[i:i+10])<.02),None)
                close=next((i*10 for i in range(len(post)-2) if all(x[0]>=.99 for x in post[i:i+3])),None)
                rows.append({"kind":kind,"edge":edge,"settle_ms":settle,"close_ms":close,
                             "steady_weights":dict(zip(NAMES,steady))})
                series[(smoothing,kind,edge)]={"inside":inside,"post":post,"steady":steady,"distance":distances}
        result["conditions"][smoothing]=rows
    # Compare stable hard/tapered states: only onset and a <0.3% mid-level difference separate them.
    result["hard_tapered_steady_rmse"]={smoothing:{kind:rmse(series[(smoothing,kind,"hard")]["steady"],series[(smoothing,kind,"tapered")]["steady"])
        for kind in ("two_tone","vowel_harmonics")} for smoothing in ("1","75")}
    a.results.write_text(json.dumps(result,indent=2)+"\n")

    W,H=1180,720; left=95; top=85; pw=480; ph=245
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">','<rect width="100%" height="100%" fill="#111827"/>',
         '<style>text{font-family:sans-serif;fill:#e5e7eb}.t{font-size:20px;font-weight:bold}.s{font-size:12px}.axis{stroke:#64748b;stroke-width:1}</style>',
         '<text x="24" y="32" class="t">OVRLipSync cold-start convergence and release</text>',
         '<text x="24" y="54" class="s">Fresh context per trial; vertical line marks sound end. Solid = hard edge, dashed = 5 ms taper.</text>']
    for col,kind in enumerate(("two_tone","vowel_harmonics")):
      for row,smoothing in enumerate(("1","75")):
        x0=left+col*550; y0=top+row*310
        out += [f'<text x="{x0}" y="{y0-12}" class="s">{html.escape(kind)} · smoothing {smoothing}</text>',
                f'<line x1="{x0}" y1="{y0+ph}" x2="{x0+pw}" y2="{y0+ph}" class="axis"/>',
                f'<line x1="{x0}" y1="{y0}" x2="{x0}" y2="{y0+ph}" class="axis"/>']
        # Plot selected visemes from 0..1000 ms and 0..400 ms release.
        selected=["sil","nn","aa","ih","ou"]
        for edge,dash in (("hard",""),("tapered",' stroke-dasharray="5 4"')):
          q=series[(smoothing,kind,edge)]; values=q["inside"]+q["post"][:40]
          for name in selected:
            i=NAMES.index(name); pts=[]
            for n,v in enumerate(values):
              x=x0+pw*n/140; y=y0+ph*(1-v[i]); pts.append(f'{x:.1f},{y:.1f}')
            out.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{COLORS[name]}" stroke-width="1.5"{dash}/>' )
        endx=x0+pw*100/140
        out += [f'<line x1="{endx}" y1="{y0}" x2="{endx}" y2="{y0+ph}" stroke="#fbbf24"/>',
                f'<text x="{x0}" y="{y0+ph+20}" class="s">0</text>',f'<text x="{endx-18}" y="{y0+ph+20}" class="s">1.0 s</text>',
                f'<text x="{x0+pw-36}" y="{y0+ph+20}" class="s">1.4 s</text>']
    lx=25; ly=690
    for name in ("sil","nn","aa","ih","ou"):
      out += [f'<line x1="{lx}" y1="{ly}" x2="{lx+24}" y2="{ly}" stroke="{COLORS[name]}" stroke-width="3"/>',f'<text x="{lx+30}" y="{ly+4}" class="s">{name}</text>']; lx+=90
    out.append('</svg>'); a.svg.write_text('\n'.join(out)+'\n')
    print(json.dumps({"hard_tapered_steady_rmse":result["hard_tapered_steady_rmse"],"conditions":result["conditions"]},indent=2))

if __name__=="__main__": main()
