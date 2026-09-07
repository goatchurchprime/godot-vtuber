# Architecture

The application uses small timestamped data objects at its subsystem
boundaries. Native library types must not leak into avatar animation code.

## Audio clock

`TimedAudioFrame.first_sample` is the canonical position of a PCM frame. The
playout queue reports the sample currently reaching the output bus. A Viseme
result is scheduled against this same clock after accounting for the model
contract and configured audio delay.

TwoVoIP exposes the most recently conditioned output-rate chunk without owning
a queue. The application owns delayed playout. Opus is deliberately absent
from local monitoring, so compression cannot alter the baseline or obscure the
cost and latency of the rest of the chain.

Local loopback passes structured frames. A protocol test may additionally pack
and unpack TwoVoIP rider bytes, but serialization is not required inside the
application.

## Pose clock

Camera observations use capture timestamps because live tracking may skip
frames. Retargeting and smoothing operate on those observations; rendering
interpolates the most recent valid pose. Pose delay and audio delay are
separate settings.

The current MediaPipe process sends versioned JSON datagrams over localhost.
Its adapter converts them to `PoseFrame`; only canonical dictionaries cross
that boundary. UDP is intentionally latest-state transport: a dropped pose
does not block audio or accumulate stale camera latency. The UI exposes packet
rejection and observation age. A dependency-free synthetic adapter implements
the same boundary for acceptance testing.

Annotated player feedback uses a separate `VTPJ` JPEG datagram at a bounded
rate. The bridge draws the authoritative MediaPipe topology before encoding;
Godot shows the newest complete image beside the avatar. This deliberately
avoids a second webcam consumer and keeps preview loss from back-pressuring the
latest-state pose channel.

## XR body retargeting

OpenXR observations do not drive avatar bones directly. Controller and hand
positions are first expressed relative to the initial HMD pose. A canonical
human layer then reconstructs shoulders, elbows, wrists, and eventually all
finger joints using consistent human segment lengths. Only that solved human
pose crosses into the avatar driver.

The first arm milestone uses Godot 4.6 `SkeletonIK3D`: each wrist is the IK
target and the corresponding reconstructed human elbow is its magnet/pole.
The IK solver therefore adapts the canonical pose to each avatar's own upper
arm and forearm lengths. This deliberately establishes the same two-stage
boundary needed for hands and for future neck/body compensation; raw OpenXR
joint bases are observations, not assumed avatar bone transforms.

Godot-XR-AH is the reference experiment for fitting a positionally correct
human hand. Its scene and controller coupling are not application policy and
are not imported into this repository. A later replaceable hand adapter can
reuse its position-fitting mathematics while emitting the same canonical pose
contract.

## Dependency direction

The application depends on interfaces implemented by adapters. TwoVoIP,
VizemeStream and a tracking backend must not depend on the application or on an
avatar format.

Source/filter normalization is application policy because causal live behavior
cannot reproduce a full utterance's statistics. The current two-second rolling
window is observable and replaceable without changing the feature extractor or
model loader. The reusable native `SourceFilterFrontend.analyze_frame()` API
was sufficient, so this milestone requires no upstream library API change.
