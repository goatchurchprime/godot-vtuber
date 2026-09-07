# Tracking coordinate contract

Tracking adapters emit all simultaneous observations in one stable session-origin
coordinate frame. Head, controller, hand, and future body-tracker poses are peers.
An adapter must never express one tracked device relative to another live tracked
device; in particular, current head motion must not counter-transform either hand.

Application retargeting happens after this boundary. It may apply fixed axis
conversions, calibration bases, small anchor offsets, mirroring policy, and avatar
bone-length compensation. These adjustments must not change the common global
relationship between independently tracked poses.
