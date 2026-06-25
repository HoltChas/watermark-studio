# Watermark Studio

Watermark Studio is a practical video watermark cleanup toolkit built from a real production workflow:

1. Open a video.
2. Mark the watermark area.
3. Generate a fixed mask for every frame.
4. Run a video inpainting backend segment by segment.
5. Rebuild the final video with the original audio.

The first backend target is [ProPainter](https://github.com/sczhou/ProPainter). ProPainter itself is not vendored here; install it separately and pass its local path to the CLI or macOS app.

## What This Repo Includes

- `watermark-studio` Python CLI.
- Reusable Python modules for masks, ffmpeg/ffprobe media handling, and segmented ProPainter runs.
- A native macOS SwiftUI app for opening a video, marking the watermark rectangle, tuning parameters, and launching cleanup.
- Example mask config and project notes.

## UI Direction

The first macOS interface direction is saved at:

![Watermark Studio UI mockup](docs/assets/ui-mockup.png)

## Requirements

- macOS or Linux for the CLI.
- macOS 14+ for the SwiftUI app.
- `ffmpeg` and `ffprobe` on `PATH`.
- Python 3.10+ with OpenCV and NumPy.
- A working ProPainter checkout and environment.

For the production run that inspired this repo, the working ProPainter command used:

```bash
--mask_dilation 0 \
--neighbor_length 5 \
--ref_stride 10 \
--subvideo_length 12 \
--raft_iter 10 \
--save_frames
```

The important lesson: ProPainter's own temporary mp4 writing can fail in some PyAV environments, while the repaired frames are already saved. This toolkit treats the saved frames as the source of truth and uses ffmpeg to rebuild the final mp4.

## Install CLI For Development

```bash
cd /path/to/watermark-studio
python3 -m pip install -e .
```

If your OpenCV environment is in Conda, use that Python:

```bash
/opt/homebrew/anaconda3/bin/python3 -m pip install -e .
```

## CLI Usage

Probe a video:

```bash
watermark-studio probe input.mp4
```

Extract a frame to mark:

```bash
watermark-studio preview-frame input.mp4 preview.png --at 0
```

Clean a video with a rectangle mask:

```bash
watermark-studio clean input.mp4 output.mp4 \
  --propainter-dir /path/to/ProPainter \
  --python /path/to/python \
  --rect 560,1128,80,72 \
  --expand 3 \
  --segment-frames 48 \
  --keep-work
```

Clean with a polygon mask:

```bash
watermark-studio clean input.mp4 output.mp4 \
  --propainter-dir /path/to/ProPainter \
  --polygon "596,1128;612,1147;639,1151;621,1169;629,1202;600,1182;535,1210;576,1172;550,1160;581,1147" \
  --expand 3
```

## macOS App

The macOS app lives in `macos/WatermarkStudio`.

```bash
cd macos/WatermarkStudio
swift run WatermarkStudioMac
```

Current app features:

- Open a video.
- Extract and show the first frame.
- Drag a rectangle over the watermark.
- Adjust mask expansion.
- Choose `Fast`, `Balanced`, or `Quality` cleanup presets.
- Configure ProPainter path, Python path, and output path.
- Run the CLI and stream progress logs.

The app uses the local Python package through `PYTHONPATH`, so it is easy to develop without packaging a Python runtime yet.

## Suggested GitHub Roadmap

- Add free polygon point marking in the Mac app.
- Add backend presets for ProPainter, OpenCV Telea, and LaMa/other image inpainting.
- Add batch mode from the macOS app.
- Package a signed `.app` and optional bundled Python environment.
- Add visual QC contact sheet generation after every run.

## Speed Presets

The macOS app exposes three ProPainter presets:

- `Fast`: fewer RAFT iterations and a longer reference stride. Good for first-pass checks.
- `Balanced`: the tested production setting from the Axolotl workflow.
- `Quality`: slower and more conservative when the repaired area has foreground motion.

For maximum speed, use the smallest accurate mask. Oversized masks are slower and usually smear more detail.

## Ethics And Scope

Use this tool only on videos you own, videos you generated, or videos where you have permission to remove embedded marks. The repo is meant for cleaning your own generated or licensed production assets.
