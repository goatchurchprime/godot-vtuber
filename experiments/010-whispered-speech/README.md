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

A second 64.90-second recording was then made through an Oculus headset into
Audacity. Its fixed microphone placement above the mouth is representative of
the intended application and avoids aiming the breath stream directly into a
desktop microphone port. It was processed with the identical two conditions.
The utterance content was not matched, so differences between recordings must
not be attributed solely to microphone geometry.

![Whisper response](comparison.svg)

![Headset whisper response](headset_comparison.svg)

## Result

| Input | Active frames with a non-silence winner | OVR mean call time |
|---|---:|---:|
| Original level | 29.9% | 0.221 ms |
| Fixed +9 dB | 66.7% | 0.193 ms |
| Headset, original level | 54.6% | 0.221 ms |
| Headset, fixed +9 dB | 76.8% | 0.252 ms |

At +9 dB every OVR vowel category became dominant in part of the recording,
along with several consonant categories. OVR therefore can produce articulated
viseme output from whispered speech, but its silence decision remains strongly
level-sensitive. The headset recording also produced every vowel category and
substantially more non-silence decisions at both levels. Because its utterances
were not matched to the first recording, that difference is encouraging but is
not an isolated measurement of headset placement. This experiment alone does
not establish whether each label was correct.

## Consequence

The result supports separate model outputs for mouth articulation and
phonation. A repeat should use fixed mouth-to-microphone geometry, speech across
the microphone or a pop shield, and matched ordinary/whispered utterances.
Those recordings should be level-matched only in an additional condition, so
absolute-level behavior remains visible.
