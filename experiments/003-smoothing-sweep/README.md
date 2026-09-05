# Experiment 003: OVRLipSync smoothing sweep

## Hypothesis

The subtle movement and stability of OVRLipSync may be produced by its exposed
`VisemeSmoothing` signal. Sweeping the SDK's accepted range using identical PCM
should reveal which variations originate before and after that filter.

## Planned controlled variables

- OVRLipSync 1.61, EnhancedWithLaughter provider.
- Identical 16 kHz mono recording with fixed +9 dB gain and no clipping.
- One fresh context per run.
- Smoothing values `1`, `25`, `50`, `75`, and `100`, plus the SDK default.
- Ten-millisecond input frames.
- Compare transition rate, frame-to-frame movement, dominant-class dwell,
  onset/offset response and sustained-vowel variance.

The SDK call is `SendSignal(context, VisemeSmoothing, amount, 0)`. Historical
Unity integration validates the practical range as 1–100 even though one native
header comment says 0–100. Results will establish the direction empirically.

## Findings

Pending the controlled sweep.

