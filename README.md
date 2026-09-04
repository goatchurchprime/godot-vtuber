# Godot VTuber

A small Godot 4.6 application for driving a live avatar from conditioned
microphone audio and webcam tracking. Its first objective is to keep audible
speech aligned with audio-derived mouth animation while remaining useful as a
test bed for the reusable audio and Vizeme libraries.

## Development disclosure

This project is being designed and developed with assistance from OpenAI Codex.
Its architecture, behaviour and changes are directed and reviewed by the human
maintainer. AI-assisted contributions are identified here so that the project's
development process is transparent.

The initial checkout deliberately runs without native dependencies or avatar
assets. Missing integrations report themselves in the UI rather than stopping
the application.

## Intended pipeline

```text
microphone 48 kHz -> TwoVoIP conditioning -> delayed 48 kHz playout -> OBS
                              |
                              +-> 16 kHz -> Mel -> ONNX -> timed Visemes

webcam -> tracking backend -> pose observations -> avatar retargeting
```

TwoVoIP owns capture, conditioning, resampling and audio-clock information.
The Vizeme component owns Mel history, inference and output stabilization. This
application owns delay, synchronization, avatar mapping and rendering.

## Run the application

From this directory:

```sh
nix shell github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41#godot_4_6 --command godot4 --editor --path "$PWD"
```

The shell is also a smoke test: it must open even when TwoVoIP, ONNX Runtime,
the Mel frontend, model files, camera tracking and avatar files are absent.

### Current TwoVoIP development checkout

The microphone-loopback milestone uses the experimental
`get_current_chunk()` hook proposed in TwoVoIP PR
[#101](https://github.com/goatchurchprime/two-voip-godot-4/pull/101), on branch
`codex/conditioned-pcm-loopback`.
It returns the conditioned output-rate PCM that would otherwise be passed to
Opus. From this repository, link a matching checkout with:

```sh
mkdir -p addons
ln -s /path/to/two-voip-godot-4/addons/twovoip addons/twovoip
```

The link is ignored by Git. Without it, the application remains usable as a
dependency-status shell.

Verify the linked audio boundary with:

```sh
nix shell github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41#godot_4_6 \
  --command godot4 --headless --path "$PWD" \
  --script res://tests/twovoip_loopback_smoke.gd
```

Enable **Mic**, then **Monitor**, to hear the conditioned microphone after the
configured delay. Headphones are strongly recommended to prevent acoustic
feedback. Changing the delay restarts and refills the playout buffer.

The visible **Silence gate** defaults to -42 dBFS. Below it, the application
continues inference but sends an explicit silence viseme to the avatar. A 6 dB,
120 ms release hysteresis prevents background noise near the threshold from
rapidly reopening the mouth. Adjust the threshold against the displayed live
RMS; this is application postprocessing, not hidden microphone gain.

The audio is sent through the `VTuberMonitor` Godot bus. The displayed processed
and playout positions are 48 kHz sample-clock values. Viseme results are queued
against that same clock and applied when their audio reaches playout.

For live lip animation, also link compatible `onnx_loader` and `vizemes_mel`
addons, an ONNX model to `models/viseme.onnx`, and an avatar to
`avatars/readyplayerme_avatar.glb`. For assets with external textures, link or
copy the complete ignored `avatars/` directory rather than one GLB symlink. The
ONNX model must carry `vizemes_meta_json`; its embedded
audio and tensor values are the runtime contract. Avatar meshes may supply the
OVR-compatible `viseme_sil` through `viseme_U` blend shapes. These paths are
ignored so neither model nor avatar enters this repository.

On NixOS, launch the complete development stack with:

```sh
env ONNX_LOADER_SKIP_SESSION_RELEASE=1 \
  nix shell github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41#godot_4_6 \
  github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41#onnxruntime \
  --command godot4 --editor --path "$PWD"
```

## Development dependencies

Dependencies will be linked under `addons/` while their APIs remain
experimental. The links and large model/avatar files are ignored by Git.
Releases must contain explicit compatible dependency artifacts rather than
machine-specific symbolic links.

Avatar files under `avatars/` and model files under `models/` are intentionally
ignored. Keep private test assets outside version control and load or link them
locally. A future public release must remain functional without those assets.

Planned adapters are:

- TwoVoIP for conditioned 48 kHz playout and 16 kHz analysis PCM.
- MelFrontend and godot-onnx-loader for audio-to-Viseme inference.

## Experimental OVRLipSync comparison

The `experiment/ovrlipsync-comparison` branch adds a backend selector for a
Windows-only comparison with OVRLipSync 1.61. It requires a matching TwoVoIP
build from its `experiment/ovrlipsync-backend` branch. The proprietary SDK and
DLL are intentionally excluded from this public repository.

Both backends feed the same 15 OVR-compatible weights into the same silence
gate, timestamp queue, delayed audio and avatar driver. OVR receives the same
post-conditioning 48 kHz stereo frame that is sent to playout; the project
backend receives the corresponding post-conditioning 16 kHz analysis frame.
This keeps the subjective comparison focused on the recognizers rather than
different animation or audio paths.
- A separately packaged MediaPipe-compatible tracking process or extension.
- Avatar profiles mapping canonical pose and expression names to a particular
  GLB/VRM skeleton and its blend shapes.

## Timing rule

Audio and mouth animation use a monotonically increasing sample position, not
render frames or wall-clock estimates. Webcam observations retain their own
capture timestamp and are sampled independently by the renderer.

## Milestones

1. Dependency-free project shell and data contracts. **Complete.**
2. Conditioned microphone loopback with configurable delayed playout. **Prototype complete.**
3. Timestamped Vizeme inference aligned to that playout. **Prototype complete.**
4. One externally loaded GLB with live mouth blend shapes. **Prototype complete.**
5. Webcam head and upper-body tracking behind a replaceable adapter.
6. Hand tracking, expression mapping, recording and OBS packaging.
