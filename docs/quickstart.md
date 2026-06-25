# Quickstart

This guide runs Watermark Studio from source. The macOS app is currently an unsigned developer build.

## 1. Install Local Tools

Install `ffmpeg` and make sure `ffmpeg` and `ffprobe` are on `PATH`.

```bash
ffmpeg -version
ffprobe -version
```

Install the Python package in editable mode:

```bash
cd /path/to/watermark-studio
python3 -m pip install -e .
```

Bootstrap a local ProPainter checkout:

```bash
scripts/bootstrap_propainter.sh ~/Tools/ProPainter
```

By default, the script clones or updates ProPainter and creates `~/Tools/ProPainter/.venv`. Set `INSTALL_REQUIREMENTS=1` if you also want it to run `pip install -r requirements.txt` inside that virtual environment.

## 2. Check The Environment

```bash
watermark-studio doctor \
  --python ~/Tools/ProPainter/.venv/bin/python \
  --propainter-dir ~/Tools/ProPainter
```

Every line should be `OK`. Fix any `FAIL` before running cleanup.

## 3. Extract A Preview Frame

```bash
watermark-studio preview-frame input.mp4 preview.png --at 0
```

Use the preview image to decide the watermark coordinates.

## 4. Clean With A Rectangle Mask

```bash
watermark-studio clean input.mp4 output.mp4 \
  --python python3 \
  --propainter-dir /path/to/ProPainter \
  --rect 560,1128,80,72 \
  --expand 3 \
  --roi-padding 256 \
  --segment-frames 48
```

Use rectangle masks for regular, box-like watermarks.

## 5. Clean With A Pen/Polygon Mask

```bash
watermark-studio clean input.mp4 output.mp4 \
  --python python3 \
  --propainter-dir /path/to/ProPainter \
  --polygon "596,1128;612,1147;639,1151;621,1169;629,1202;600,1182;535,1210;576,1172;550,1160;581,1147" \
  --expand 3 \
  --roi-padding 256
```

Use polygon masks for small or irregular marks. Keep the mask tight first, then increase `--expand` by 2-5 pixels only if edges still remain.

## 6. Run The macOS App

Development run:

```bash
cd /path/to/watermark-studio/macos/WatermarkStudio
swift run WatermarkStudioMac
```

Unsigned local app package:

```bash
cd /path/to/watermark-studio
./scripts/package_mac_app.sh
open "dist/Watermark Studio.app"
```

In the app, choose your local Python executable and ProPainter folder before starting cleanup. The app saves those paths for future runs.
