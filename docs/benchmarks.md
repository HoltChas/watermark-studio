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
| Fast 0.5x composite | 72 | 6 | 15 | 40.63s | 720x1280, 24fps, AAC 48k stereo, 2.005s |
| Fast | 72 | 6 | 15 | 125.47s | 720x1280, 24fps, AAC 48k stereo, 2.005s |
| Balanced | 48 | 10 | 10 | 153.47s | 720x1280, 24fps, AAC 48k stereo, 2.005s |

Observation:

- Parameter-only Fast was about 18% faster on this short clip.
- Fast 0.5x composite was about 3x faster than parameter-only Fast and about 3.8x faster than Balanced.
- The 0.5x route runs ProPainter at half resolution, then composites only the repaired mask region back onto the original full-resolution frames. This preserves the rest of the frame but the repaired area can look slightly softer.
- Bigger speedups beyond this likely require a persistent ProPainter worker to avoid model reload overhead.

Artifact:

- Local comparison image: `work/speed_test/fast_half_compare.jpg`
