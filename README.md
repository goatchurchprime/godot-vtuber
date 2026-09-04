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

## Run the dependency-free shell

From this directory:

```sh
nix shell github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41#godot_4_6 --command godot4 --editor --path "$PWD"
```

The shell is also a smoke test: it must open even when TwoVoIP, ONNX Runtime,
the Mel frontend, model files, camera tracking and avatar files are absent.

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
- A separately packaged MediaPipe-compatible tracking process or extension.
- Avatar profiles mapping canonical pose and expression names to a particular
  GLB/VRM skeleton and its blend shapes.

## Timing rule

Audio and mouth animation use a monotonically increasing sample position, not
render frames or wall-clock estimates. Webcam observations retain their own
capture timestamp and are sampled independently by the renderer.

## Milestones

1. Dependency-free project shell and data contracts.
2. Conditioned microphone loopback with configurable delayed playout.
3. Timestamped Vizeme inference aligned to that playout.
4. One mapped GLB avatar with transparent/chroma-key rendering.
5. Webcam head and upper-body tracking behind a replaceable adapter.
6. Hand tracking, expression mapping, recording and OBS packaging.
