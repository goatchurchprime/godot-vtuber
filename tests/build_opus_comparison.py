#!/usr/bin/env python3
"""Encode/decode matched Opus variants and record their exact PCM relationship."""

import argparse
import hashlib
import json
import math
import struct
import subprocess
import wave
from pathlib import Path


def pcm(path: Path) -> list[int]:
    with wave.open(str(path), "rb") as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, 16000):
            raise SystemExit(f"{path}: expected mono 16-bit 16 kHz WAV")
        raw = source.readframes(source.getnframes())
    return list(struct.unpack(f"<{len(raw)//2}h", raw))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alignment(reference: list[int], decoded: list[int]) -> dict:
    # Sparse normalized correlation is sufficient to detect residual codec delay.
    probe_count = min(len(reference), len(decoded), 160_000)
    best = None
    for shift in range(-640, 641):
        start_a = max(0, -shift); start_b = max(0, shift)
        count = min(probe_count - start_a, probe_count - start_b)
        if count <= 0:
            continue
        aa = reference[start_a:start_a+count:32]; bb = decoded[start_b:start_b+count:32]
        dot = sum(a*b for a,b in zip(aa,bb)); ea = sum(a*a for a in aa); eb = sum(b*b for b in bb)
        corr = dot / math.sqrt(max(1, ea*eb))
        if best is None or corr > best[0]:
            best = (corr, shift)
    corr, shift = best
    start_a = max(0, -shift); start_b = max(0, shift)
    count = min(len(reference)-start_a, len(decoded)-start_b)
    rmse = math.sqrt(sum((reference[start_a+i]-decoded[start_b+i])**2 for i in range(count))/count)/32768
    return {"decoded_lag_samples": shift, "correlation": corr, "aligned_pcm_rmse": rmse,
            "reference_samples": len(reference), "decoded_samples": len(decoded)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("output_dir", type=Path)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("sources", nargs="+", type=Path)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    args = ap.parse_args(); args.output_dir.mkdir(parents=True, exist_ok=True)
    ffmpeg_version = subprocess.run([args.ffmpeg, "-version"], check=True, text=True,
                                    stdout=subprocess.PIPE).stdout.splitlines()[0]
    result = {"schema":"opus_comparison_inputs_v1", "ffmpeg":ffmpeg_version,
              "codec":{"application":"voip","frame_duration_ms":20,"vbr":"off"}, "sources":[]}
    for source in args.sources:
        reference = pcm(source); stem = source.stem
        entry = {"name":stem,"original":str(source),"original_sha256":sha256(source),"variants":[]}
        for bitrate in (12,16,24,48):
            encoded=args.output_dir/f"{stem}_opus_{bitrate}k.opus"
            decoded=args.output_dir/f"{stem}_opus_{bitrate}k_decoded.wav"
            encode=[args.ffmpeg,"-hide_banner","-loglevel","error","-y","-i",str(source),"-ac", "1", "-ar","16000",
                    "-c:a","libopus","-application","voip","-frame_duration","20","-vbr","off","-b:a",f"{bitrate}k",str(encoded)]
            decode=[args.ffmpeg,"-hide_banner","-loglevel","error","-y","-i",str(encoded),"-ac","1","-ar","16000","-c:a","pcm_s16le",str(decoded)]
            subprocess.run(encode,check=True); subprocess.run(decode,check=True)
            decoded_pcm=pcm(decoded)
            entry["variants"].append({"bitrate_kbps":bitrate,"encoded":str(encoded),"decoded":str(decoded),
                "encoded_bytes":encoded.stat().st_size,"decoded_sha256":sha256(decoded),
                "alignment":alignment(reference,decoded_pcm),"encode_command":encode,"decode_command":decode})
        result["sources"].append(entry)
    args.manifest.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps([{ "source":x["name"], "variants":[{"kbps":v["bitrate_kbps"],**v["alignment"]} for v in x["variants"]]} for x in result["sources"]],indent=2))


if __name__ == "__main__":
    main()
