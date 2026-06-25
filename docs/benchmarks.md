# Benchmarks

## 2026-06-25 Axolotl 2s Smoke Test

Machine: local Apple Silicon Mac.

Input:

- Source: `03_ask_ask_ask_axolotl.mp4`
- Test clip: first 2 seconds
- Size: 720x1280
- FPS: 24
- Audio: AAC 48k stereo
- Mask: rectangle `535,1128,105,82`, expand `3`

Results:

| Preset | Segment frames | RAFT iter | Ref stride | Runtime | Output check |
| --- | ---: | ---: | ---: | ---: | --- |
| Fast | 72 | 6 | 15 | 125.47s | 720x1280, 24fps, AAC 48k stereo, 2.005s |
| Balanced | 48 | 10 | 10 | 153.47s | 720x1280, 24fps, AAC 48k stereo, 2.005s |

Observation:

- Fast was about 18% faster on this short clip.
- Visual crop comparison did not show an obvious failure, but the speed gain is modest.
- Bigger speedups likely require a persistent ProPainter worker or a lower-resolution preview mode, not just parameter tweaks.

Artifact:

- Local comparison image: `work/speed_test/fast_balanced_compare.jpg`

