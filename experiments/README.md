# OVRLipSync and Vizemes experiments

This directory preserves the hypotheses, methods, aggregate results and useful
diagrams from the OVRLipSync comparison. Experiments are numbered in execution
order; later experiments may refine rather than replace earlier conclusions.

1. [Temporal memory in repeated speech](001-temporal-memory/README.md)
2. [Recorded sustained vowels, level and pitch](002-recorded-vowels/README.md)
3. [OVRLipSync smoothing sweep](003-smoothing-sweep/README.md)
4. [Can OVR smoothing be reproduced externally?](004-external-smoothing-model/README.md)
5. Synthetic support probe (analysis in progress)
6. [Does OVRLipSync retain phase information?](006-phase-sensitivity/README.md)
7. [OVR acoustic support and cold-start state](007-acoustic-support/README.md)

For a short narrative account of the complete investigation, read
[A low-cost route to pleasing real-time visemes](REPORT.md).

The `private/` directory inside each experiment contains local source audio and
full-resolution traces. Git ignores those directories because experiment 002
contains a participant's voice. Aggregate tables and diagrams are suitable for
sharing. Publish raw voice-derived data only with the participant's explicit
agreement.

All software and prose in this experiment series were developed with OpenAI
Codex assistance and reviewed interactively by the project owner.
