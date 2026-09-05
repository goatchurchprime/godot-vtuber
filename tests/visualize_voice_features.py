#!/usr/bin/env python3
"""Create a synchronized, speech-oriented LPC/pitch feature visualization."""

import argparse
import base64
import json
import math
import struct
import wave
import zlib
from pathlib import Path

RATE = 16_000
WINDOW = 400
HOP = 160
ORDER = 16
FREQ_BINS = 80
PALETTE = ["08051d", "270b52", "5c167f", "982d80", "d4486a", "f4774f", "fbb43f", "fcf6bd"]


def colour(value):
    value=max(0,min(.999999,value))*(len(PALETTE)-1); i=int(value); f=value-i
    a=tuple(int(PALETTE[i][j:j+2],16) for j in (0,2,4)); b=tuple(int(PALETTE[i+1][j:j+2],16) for j in (0,2,4))
    return tuple(round(x+(y-x)*f) for x,y in zip(a,b))


def png_rgb(width,height,pixels):
    raw=b''.join(b'\0'+bytes(pixels[y*width*3:(y+1)*width*3]) for y in range(height))
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')


def levinson(r, order):
    a=[1.0]+[0.0]*order; error=max(r[0],1e-12); reflection=[]
    for i in range(1,order+1):
        k=-(r[i]+sum(a[j]*r[i-j] for j in range(1,i)))/max(error,1e-12)
        k=max(-.999,min(.999,k)); old=a[:]
        a[i]=k
        for j in range(1,i): a[j]=old[j]+k*old[i-j]
        error*=1-k*k; reflection.append(k)
    return a,max(error,1e-12),reflection


def path(points):
    parts=[]; open_path=False
    for x,y in points:
        if y is None: open_path=False; continue
        parts.append(('M' if not open_path else 'L')+f'{x:.1f},{y:.1f}'); open_path=True
    return ' '.join(parts)


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('wav',type=Path); ap.add_argument('svg',type=Path); ap.add_argument('json',type=Path); args=ap.parse_args()
    with wave.open(str(args.wav),'rb') as w:
        if (w.getnchannels(),w.getsampwidth(),w.getframerate())!=(1,2,RATE): raise SystemExit('expected mono 16-bit 16 kHz WAV')
        raw=w.readframes(w.getnframes()); pcm=[x/32768 for x in struct.unpack(f'<{len(raw)//2}h',raw)]
    hann=[.5-.5*math.cos(2*math.pi*i/(WINDOW-1)) for i in range(WINDOW)]
    rows=[]
    for start in range(0,len(pcm)-WINDOW+1,HOP):
        original=pcm[start:start+WINDOW]; rms=math.sqrt(sum(x*x for x in original)/WINDOW); db=20*math.log10(max(rms,1e-8))
        pre=[original[0]]+[original[i]-.97*original[i-1] for i in range(1,WINDOW)]; x=[pre[i]*hann[i] for i in range(WINDOW)]
        r=[sum(x[n]*x[n-k] for n in range(k,WINDOW)) for k in range(ORDER+1)]
        a,error,refl=levinson(r,ORDER)
        # Pitch and voicing from normalized autocorrelation, downsampled by two.
        q=original[::2]; mean=sum(q)/len(q); q=[v-mean for v in q]; best=(0.0,0)
        for lag in range(20,134):
            dot=sum(q[i]*q[i-lag] for i in range(lag,len(q))); ea=sum(q[i]*q[i] for i in range(lag,len(q))); eb=sum(q[i-lag]*q[i-lag] for i in range(lag,len(q)))
            corr=dot/math.sqrt(max(1e-18,ea*eb))
            if corr>best[0]: best=(corr,lag)
        voice=max(0,min(1,(best[0]-.2)/.65)) if db>-60 else 0
        pitch=RATE/2/best[1] if voice>.2 else 0
        hnr=10*math.log10(max(1e-4,best[0])/max(1e-4,1-best[0])) if voice>.05 else -10
        gain=10*math.log10(max(r[0],1e-12)/error)
        envelope=[]
        for k in range(FREQ_BINS):
            freq=4000*k/(FREQ_BINS-1); real=1+sum(a[j]*math.cos(-2*math.pi*freq*j/RATE) for j in range(1,ORDER+1)); imag=sum(a[j]*math.sin(-2*math.pi*freq*j/RATE) for j in range(1,ORDER+1))
            envelope.append(10*math.log10(error/max(1e-12,real*real+imag*imag)))
        peak=max(envelope); shape=[max(-50,v-peak) for v in envelope]
        peaks=[k for k in range(2,FREQ_BINS-2) if shape[k]>shape[k-1] and shape[k]>=shape[k+1] and shape[k]>-25]
        formants=[]
        for k in peaks:
            f=4000*k/(FREQ_BINS-1)
            if f>90 and (not formants or f-formants[-1]>120): formants.append(f)
            if len(formants)==3: break
        xs=[math.log2(max(200,4000*k/(FREQ_BINS-1))/200) for k in range(4,FREQ_BINS)]; ys=shape[4:]; xm=sum(xs)/len(xs); ym=sum(ys)/len(ys)
        tilt=sum((u-xm)*(v-ym) for u,v in zip(xs,ys))/max(1e-9,sum((u-xm)**2 for u in xs))
        rows.append({'time_s':(start+WINDOW/2)/RATE,'rms_dbfs':db,'pitch_hz':pitch,'voicing':voice,'hnr_db':hnr,'prediction_gain_db':gain,'tilt_db_octave':tilt,'formants_hz':formants,'lpc_shape_db':shape})

    plot_w=1200; heat_h=260; pixels=[]
    for y in range(heat_h):
        bin_index=round((heat_h-1-y)*(FREQ_BINS-1)/(heat_h-1))
        for px in range(plot_w):
            row=rows[min(len(rows)-1,int(px*len(rows)/plot_w))]; value=(row['lpc_shape_db'][bin_index]+50)/50 if row['rms_dbfs']>-65 else 0
            pixels.extend(colour(value))
    image=base64.b64encode(png_rgb(plot_w,heat_h,pixels)).decode()
    W,H=1360,850; L=115; T=75; duration=len(pcm)/RATE
    def X(t): return L+plot_w*t/duration
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">','<rect width="100%" height="100%" fill="#111827"/>',
         '<style>text{font-family:sans-serif;fill:#e5e7eb}.title{font-size:21px;font-weight:bold}.label{font-size:12px}.grid{stroke:#475569;stroke-width:1}.zero{stroke:#94a3b8}</style>',
         '<text x="24" y="31" class="title">Speech source/filter analysis · 25 ms support · 10 ms hop</text>',
         '<text x="24" y="52" class="label">LPC order 16; envelope shape normalized per frame. Purple→orange is monotonic luminance, not a rainbow scale.</text>']
    # Waveform min/max envelope.
    wy=T; wh=90; out += [f'<text x="20" y="{wy+20}" class="label">waveform</text>',f'<line x1="{L}" y1="{wy+wh/2}" x2="{L+plot_w}" y2="{wy+wh/2}" class="zero"/>']
    for px in range(plot_w):
        lo=int(px*len(pcm)/plot_w); hi=max(lo+1,int((px+1)*len(pcm)/plot_w)); mn=min(pcm[lo:hi]); mx=max(pcm[lo:hi]);
        out.append(f'<line x1="{L+px}" y1="{wy+wh*(.5-.45*mx):.1f}" x2="{L+px}" y2="{wy+wh*(.5-.45*mn):.1f}" stroke="#cbd5e1"/>')
    hy=wy+wh+30; out += [f'<text x="20" y="{hy+20}" class="label">LPC envelope</text>',f'<image x="{L}" y="{hy}" width="{plot_w}" height="{heat_h}" href="data:image/png;base64,{image}" preserveAspectRatio="none"/>']
    for freq in (0,1000,2000,3000,4000):
        y=hy+heat_h*(1-freq/4000); out += [f'<line x1="{L}" y1="{y}" x2="{L+plot_w}" y2="{y}" class="grid" opacity=".35"/>',f'<text x="{L-8}" y="{y+4}" text-anchor="end" class="label">{freq//1000}k</text>']
    for fi,color in enumerate(('#67e8f9','#f8fafc','#86efac')):
        pts=[]
        for row in rows:
            f=row['formants_hz'][fi] if len(row['formants_hz'])>fi and row['voicing']>.2 else None; pts.append((X(row['time_s']),None if f is None else hy+heat_h*(1-f/4000)))
        out.append(f'<path d="{path(pts)}" fill="none" stroke="{color}" stroke-width="1.3"/>')
    # Four compact scalar lanes.
    lanes=[('pitch Hz','#22d3ee',lambda r: None if r['pitch_hz']<=0 else (math.log(r['pitch_hz']/70)/math.log(400/70)), '70–400 log'),
           ('voicing','#a78bfa',lambda r:r['voicing'],'0–1'),('energy dBFS','#f59e0b',lambda r:(r['rms_dbfs']+70)/65,'−70…−5'),
           ('HNR dB','#4ade80',lambda r:(r['hnr_db']+10)/40,'−10…30'),('LPC gain','#fb7185',lambda r:r['prediction_gain_db']/30,'0…30 dB'),
           ('residual tilt','#f8fafc',lambda r:(r['tilt_db_octave']+15)/30,'−15…+15 dB/oct')]
    sy=hy+heat_h+28; sh=55
    for li,(label,color,fn,scale) in enumerate(lanes):
        y0=sy+li*(sh+5); out += [f'<rect x="{L}" y="{y0}" width="{plot_w}" height="{sh}" fill="#0b1220"/>',f'<text x="20" y="{y0+20}" class="label">{label}</text>',f'<text x="20" y="{y0+38}" class="label" opacity=".65">{scale}</text>']
        pts=[]
        for row in rows:
            v=fn(row); pts.append((X(row['time_s']),None if v is None else y0+sh*(1-max(0,min(1,v)))))
        out.append(f'<path d="{path(pts)}" fill="none" stroke="{color}" stroke-width="1.6"/>')
    for sec in range(math.ceil(duration)+1):
        x=X(sec); out += [f'<line x1="{x}" y1="{wy}" x2="{x}" y2="{H-25}" class="grid" opacity=".22"/>',f'<text x="{x}" y="{H-8}" text-anchor="middle" class="label">{sec}s</text>']
    out.append('</svg>'); args.svg.parent.mkdir(parents=True,exist_ok=True); args.svg.write_text('\n'.join(out)+'\n')
    public=[{k:v for k,v in row.items() if k!='lpc_shape_db'} for row in rows]; args.json.write_text(json.dumps({'schema':'speech_source_filter_features_v1','sample_rate':RATE,'window_samples':WINDOW,'hop_samples':HOP,'lpc_order':ORDER,'frames':public},indent=2)+'\n')
    print(f'wrote {args.svg} ({len(rows)} frames, {duration:.3f}s)')

if __name__=='__main__': main()
