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

The microphone-loopback milestone uses the current one-shot
`TwovoipOpusEncoder.initialize()` contract. `get_current_chunk()` returns the
conditioned output-rate PCM that would otherwise be passed to Opus. The lazy
`get_current_chunk_16khz(reset_sampler)` branch is consumed exactly once per
processed chunk and reset after a gap. From this repository, link a matching
checkout with:

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
addons, an ONNX model to `models/viseme.onnx`, and an avatar scene to
`avatars/freakhound_avatar.tscn`. For assets with external textures, link or
copy the complete ignored `avatars/` directory rather than one model symlink. The
ONNX model must carry `vizemes_meta_json`; its embedded
audio and tensor values are the runtime contract. Avatar meshes may supply the
OVR-compatible `viseme_sil` through `viseme_U` or VRChat-compatible `vrc.v_sil`
through `vrc.v_ou` blend shapes. Model and private-avatar paths are ignored so
neither enters this repository.

## Editing the studio and private avatar

Open `scenes/studio.tscn` in the Godot editor to author the broadcast set. Its
`Environment`, `KeyLight`, `FillLight`, `RimLight`, `BroadcastCamera` and
`AvatarAnchor` are ordinary scene nodes and remain separate from microphone
and synchronization controls.

`AvatarDriver` runs in the editor: it displays the selected private avatar when
available and a neutral body/head stand-in otherwise, so lighting and scale can
be judged without running the application. Select the `Avatar` node to tune the
exported spring stiffness and drag multipliers. These multipliers preserve the
values authored in the VRM rather than replacing every spring with one value.

The private `avatars/freakhound_avatar.tscn` is an inherited wrapper around
`avatars/freakhound.vrm`. Open that scene to add or override spring-bone and
collider settings after import. Both files remain ignored by Git and must be
copied privately to another development machine. The VRM importer and MToon
shader addons are public MIT-licensed project dependencies and are committed.

## OpenXR tracking and broadcast policy

Selecting the `OpenXR direct` backend initializes Godot's OpenXR interface and
reads the HMD plus left/right hand trackers through `XRServer`. It deliberately
does not create `XRCamera3D` or `XRController3D` nodes: those nodes are useful scene
projections of tracker state, but are not required to acquire poses. The
adapter emits the same timestamped `PoseFrame` boundary as MediaPipe, leaving
retargeting, filtering, networking and the fixed `BroadcastCamera` under this
application's policy.

An active OpenXR runtime is still required. On Windows, start SteamVR and make
it the current OpenXR runtime before selecting `OpenXR direct`. Whether the
headset shows runtime passthrough, the SteamVR desktop overlay, or a Godot XR
view is a presentation choice and remains separate from tracking. This
milestone keeps the avatar/OBS camera fixed and does not enable XR rendering on
the studio `SubViewport`.

When OpenXR is active, the application creates a separate submission
`SubViewport` with an ordinary fixed `Camera3D`. OpenXR runtimes require a
submitting viewport to advance the session and synchronize actions, but this
viewport does not drive the avatar and cannot alter the studio/OBS framing.

For unattended deployment diagnostics, append `-- --tracking=openxr` to the
Godot command. This selects and initializes the adapter during application
startup, so OpenXR loader failures are captured in the normal Godot log.

Desktop rendering is capped at 60 fps and uses Godot's low-processor mode when
OpenXR is not active. The Performance diagnostic reports FPS, frame and physics
time, cumulative ONNX runs, and whether microphone processing is active. ONNX
runs must remain unchanged while the microphone is off.

The current acceptance model is the `lpc-source-filter` pilot from
`vizemes-source-filter/export/source-filter-pilot/lpc-source-filter/`. Its
metadata selects 24 features, a 25 ms window, 10 ms hop and 19-hop TCN history.
`VisemeStream` selects Mel or source/filter from that metadata; filenames do
not select signal processing. For the training-time per-utterance
normalization, this application explicitly uses a bounded two-second causal
window. This is a live policy approximation, not batch/live equivalence, and
is intentionally kept in this repository.

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

## Laptop webcam and OBS milestone

The tracking selector has three replaceable adapters: **Off**, **MediaPipe
UDP**, and **Synthetic acceptance**. Synthetic mode exercises the complete
Godot pose/avatar boundary without a camera. MediaPipe mode listens only on
`127.0.0.1:7007`; start the bridge in another terminal:

```sh
python3 tools/mediapipe_tracking_bridge.py --camera 0
```

The bridge needs Python packages `mediapipe` and `opencv-python`. Run it with
`--synthetic` to test process deployment and UDP without those packages. It
reports missing packages, camera-open failure and frame-read failure on stderr;
Godot reports bind/protocol failures, received/rejected counts and observation
age in the UI. The schema is versioned JSON so a native extension or different
tracker can replace the bridge without changing avatar code.

The normal camera bridge also sends a 10 fps, 480×360 annotated feedback view
to the application. It uses MediaPipe's face contours and pose skeleton and
labels the exact canonical values being sent to the avatar. Preview frames are
independent lossy UDP datagrams: congestion or a decode failure cannot stall
pose observations or audio. Use `--godot-preview-fps 0` to disable this stream,
or another positive rate to tune its CPU/network cost.

On NixOS, enter the pinned shell before creating or running the isolated
environment. Besides Python 3.12, the shell exposes only the native libraries
required by the binary wheels:

```sh
nix develop
python3 -m venv .venv-mediapipe
.venv-mediapipe/bin/pip install -r requirements-mediapipe.txt
.venv-mediapipe/bin/python tools/mediapipe_tracking_bridge.py --camera 0 --preview
```

Use `--max-frames 30` for a bounded camera/dependency acceptance run. The
bridge prints its selected camera/destination immediately and periodic
throughput while running. `--preview` opens MediaPipe's standard face-contour
and pose-skeleton overlay and prints the exact canonical values sent to Godot;
press **Q** or **Esc** in that window to stop the bridge.

In Godot select **MediaPipe UDP**, enable **Mic** and **Monitor**, and use
headphones. In OBS add a Window Capture or Game Capture for Godot and an Audio
Output Capture for the selected Godot output device. The application owns the
configured audio delay and applies visemes on the corresponding sample clock;
webcam capture timestamps remain independent. For this first milestone,
canonical head rotation and shoulder-centre motion drive the avatar root;
skeleton-specific neck/spine retargeting belongs in a future avatar profile.

For the speaking-only studio milestone, leave tracking set to **Off**. The
temporary root-pose experiment will be removed when skeleton retargeting begins.

Headless acceptance gates:

```sh
godot4 --headless --path "$PWD" --script res://tests/tracking_adapter_smoke.gd
godot4 --headless --path "$PWD" --script res://tests/viseme_avatar_smoke.gd
godot4 --headless --path "$PWD" --script res://tests/main_scene_smoke.gd
```

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
