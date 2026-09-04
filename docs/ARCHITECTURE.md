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

## Dependency direction

The application depends on interfaces implemented by adapters. TwoVoIP,
VizemeStream and a tracking backend must not depend on the application or on an
avatar format.
