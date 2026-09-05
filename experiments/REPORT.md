# A low-cost route to pleasing real-time visemes

## Abstract

We compared a small MEL/ONNX speech-to-viseme model with OVRLipSync 1.61 to
understand why OVR produces stable, pleasing animation at low CPU cost despite
occasionally questionable phonetic labels. Four experiments progressively
isolated temporal memory, input level, SDK smoothing and the reproducibility of
that smoothing. OVR combines a level-sensitive classifier with substantial
temporal shaping. Most of the shaping can be approximated by a trivial causal
filter, suggesting that our next progress should come from a smaller acoustic
classifier and an explicitly designed animation filter rather than a larger
network trained to emit already-smoothed poses.

## Direction of the experiments

The live avatar first showed subtle motion during long vowels while remaining
more stable than our ONNX result. We therefore repeated identical speech
samples. OVR's response depended on the preceding 0–100 ms and became exactly
repeatable only after 500 ms of silence. It also continued producing changing
non-silence classes for roughly 305 ms after a 130 ms sound. This established
temporal processing but did not locate it.

We next recorded sustained vowels, a level sweep, a pitch sweep and short
syllables. At the untouched microphone level OVR classified most sustained
sounds as silence. A fixed, non-clipping +9 dB gain made `aa`, `E` and `ih`
strong and stable. This explains why the conditioned live TwoVoIP signal felt
better than the raw Audacity recording. It also showed that pleasing animation
does not require perfect phonetic labels: OVR confused parts of `oh` and `ou`,
while the ONNX system was correct on `ou` but visibly more jittery elsewhere.

OVR exposes a 1–100 viseme-smoothing signal, so the third experiment replayed
identical PCM through fresh contexts. Smoothing 1 exposed rapid classifier
movement; 25, 50 and 75 progressively reduced it; 100 nearly froze established
poses. The SDK default was closest to 75. On `ou`, dominant-class changes fell
from 113 at setting 1 to 43 at 75 and 2 at 100. Smoothing cost was negligible.

Finally, we asked whether this was ordinary output filtering. A one-pole causal
filter applied to the smoothing-1 trace reproduced most of settings 25–75. For
setting 75 it reduced trace error by roughly two-thirds, with a fitted preceding
weight of 0.737. It was not exact, particularly during fast speech and at 100,
so OVR probably includes nonlinear or multi-stage behavior. The evidence is
nevertheless consistent with its main artistic benefit being downstream of
classification.

## Implications

The current ONNX network should not be asked to learn both phonetic evidence and
the final animation trajectory. Those are different problems. A useful low-cost
design is:

1. condition and level-gate microphone PCM;
2. infer a compact, relatively raw acoustic state;
3. retain one dominant pose with a small secondary candidate;
4. apply attack, release and transition rules explicitly;
5. modulate mouth aperture from short-term PCM level rather than classifier
   confidence.

This structure is cheap, understandable and suitable for the existing rider
channel. It also lets artists alter timing without retraining the recognizer.

## Next experiment

We should create an **OVR-derived low-cost postprocessor benchmark**. Use the
smoothing-1 trace as a teacher, then compare several tiny causal filters on
unseen continuous speech: one-pole smoothing, asymmetric attack/release,
winner-plus-runner-up hysteresis, and the same filter with independent RMS mouth
aperture. The candidates should drive the avatar side by side with OVR default,
while recording dominant-switch rate, transition delay, CPU cost and a blinded
human preference. This directly advances the product: it tells us the smallest
animation layer needed once any acoustic classifier supplies usable evidence.

The following experiment should then reduce the acoustic input itself—testing
short FFT/log-spectrum features against MEL—while holding the winning
postprocessor fixed. That separation will reveal whether our remaining cost and
errors come from the MEL representation or from classification.

