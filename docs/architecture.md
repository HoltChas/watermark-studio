# Architecture

Watermark Studio is split into a deterministic orchestration layer and pluggable cleanup backends.

## Core Flow

```text
input video
  -> ffprobe metadata
  -> preview frame
  -> user-marked rectangle or polygon
  -> full-resolution mask
  -> extract all frames
  -> split into fixed-size segments
  -> run ProPainter for each segment
  -> verify repaired frame count
  -> encode repaired frames with original audio
  -> output mp4
```

## Why Segments

Full-length video inpainting can be slow and memory-heavy. Splitting a 240-frame, 10-second, 24fps clip into five 48-frame chunks made the workflow easier to resume and verify. Every segment must produce exactly the expected number of repaired frames before final encoding.

## Mask Strategy

The CLI supports both:

- Rectangle masks for quick user marking from the macOS app.
- Polygon masks for tighter production cleanup when the visible watermark is not rectangular.

Small masks preserve more original image detail. `--expand` covers antialiasing and soft edges without forcing users to draw a too-large region.

## Backend Contract

A backend receives:

- Segment frames.
- Segment masks.
- Video dimensions.
- Timing settings.

A backend must output repaired PNG frames. Final mp4 encoding is handled by this repo, not by the backend.

