# Contributing

Thanks for helping improve Watermark Studio.

## Development Setup

```bash
python3 -m pip install -e ".[dev]"
pytest -q
```

For the macOS app:

```bash
cd macos/WatermarkStudio
swift test
```

## Local Dependencies

Watermark Studio does not vendor ProPainter, model weights, Python runtimes, or video assets. Keep those outside the repository and configure paths locally.

Before testing cleanup runs:

```bash
watermark-studio doctor --python python3 --propainter-dir /path/to/ProPainter
```

## Pull Request Guidelines

- Keep original videos, generated videos, model weights, and temporary work folders out of Git.
- Add or update tests for CLI, mask, ROI, and compositing changes.
- Update README or docs when a user-facing command, preset, or app workflow changes.
- Prefer small, focused changes over broad rewrites.

## Scope

This project is intended for videos you own, generated assets, licensed material, or media where you have permission to remove embedded marks.
