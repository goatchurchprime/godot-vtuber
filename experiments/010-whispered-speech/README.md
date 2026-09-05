# 010 — Can OVRLipSync respond to whispered speech?

## Hypothesis

Whispering removes periodic vocal-fold excitation while retaining a changing
vocal-tract filter. If OVRLipSync recognizes the articulation, mouth shape and
phonation should be treated as separate factors in our model.

## Method and limitation

Julian recorded 54.27 seconds of whispered speech as 48 kHz, mono, 16-bit PCM.
It was resampled to 16 kHz and processed through OVRLipSync 1.61 at its minimum
smoothing setting and a real 10 ms cadence. A second pass applied a fixed +9 dB
before OVR; its source peak was low enough for this not to clip.

The microphone orientation was not controlled: speaking into rather than
across a microphone port can introduce turbulent wind energy and alter the
spectrum. This makes the result a capability probe, not a clean accuracy
comparison. The original audio and complete traces remain under the ignored
`private/` directory.

![Whisper response](comparison.svg)

## Result

| Input | Active frames with a non-silence winner | OVR mean call time |
|---|---:|---:|
| Original level | 29.9% | 0.221 ms |
| Fixed +9 dB | 66.7% | 0.193 ms |

At +9 dB every OVR vowel category became dominant in part of the recording,
along with several consonant categories. OVR therefore can produce articulated
viseme output from whispered speech, but its silence decision remains strongly
level-sensitive. This experiment alone does not establish whether each label
was correct.

## Consequence

The result supports separate model outputs for mouth articulation and
phonation. A repeat should use fixed mouth-to-microphone geometry, speech across
the microphone or a pop shield, and matched ordinary/whispered utterances.
Those recordings should be level-matched only in an additional condition, so
absolute-level behavior remains visible.
