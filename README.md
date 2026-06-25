# Watermark Studio

> Developer preview: the CLI and macOS app are usable for local workflows, but the macOS app is not signed or notarized yet. ProPainter and its model environment are not bundled.
>
> 开发预览版：CLI 和 macOS 应用已经可用于本地工作流，但 macOS 应用还没有签名和公证。ProPainter 以及它的模型环境不会随仓库一起分发。

Watermark Studio is a practical video watermark cleanup toolkit. It helps you mark a watermark area, generate a fixed mask, run a video inpainting backend segment by segment, and rebuild the final video with the original audio.

Watermark Studio 是一个实用的视频水印清理工具。它可以帮助你标记水印区域、生成固定遮罩、分段调用视频修复后端，并把修复后的画面重新合成为保留原音频的视频。

The first backend target is [ProPainter](https://github.com/sczhou/ProPainter). ProPainter itself is not vendored here; install it separately and pass its local path to the CLI or macOS app.

当前第一个后端目标是 [ProPainter](https://github.com/sczhou/ProPainter)。本仓库不内置 ProPainter，你需要单独安装，并在 CLI 或 macOS 应用里配置本机路径。

## What This Repo Includes / 仓库内容

- `watermark-studio` Python CLI.
- Reusable Python modules for masks, ffmpeg/ffprobe media handling, ROI cropping, and segmented ProPainter runs.
- A native macOS SwiftUI app for opening a video, marking a rectangle or pen/polygon mask, tuning parameters, and launching cleanup.
- Example mask config, quickstart docs, CI, and contributor docs.

中文：

- `watermark-studio` Python 命令行工具。
- 可复用的 Python 模块：遮罩、ffmpeg/ffprobe 媒体处理、ROI 裁剪、ProPainter 分段处理。
- 原生 macOS SwiftUI 应用：打开视频、标记方框或钢笔/多边形遮罩、调整参数、启动清理。
- 示例遮罩、快速开始文档、CI 和开源协作文档。

## UI Direction / 界面方向

The first macOS interface direction is saved at:

第一版 macOS 界面方向如下：

![Watermark Studio UI mockup](docs/assets/ui-mockup.png)

## Requirements / 环境要求

- macOS or Linux for the CLI.
- macOS 14+ for the SwiftUI app.
- `ffmpeg` and `ffprobe` on `PATH`.
- Python 3.10+ with OpenCV and NumPy.
- A working ProPainter checkout and environment.

中文：

- CLI 支持 macOS 或 Linux。
- SwiftUI app 需要 macOS 14+。
- `ffmpeg` 和 `ffprobe` 需要在 `PATH` 中。
- Python 3.10+，并安装 OpenCV 和 NumPy。
- 本机需要有可运行的 ProPainter checkout 和对应环境。

Check your local environment:

检查本机环境：

```bash
watermark-studio doctor \
  --python python3 \
  --propainter-dir /path/to/ProPainter
```

Recommended ProPainter flags for short generated-video clips:

短生成视频推荐的 ProPainter 参数：

```bash
--mask_dilation 0 \
--neighbor_length 5 \
--ref_stride 10 \
--subvideo_length 12 \
--raft_iter 10 \
--save_frames
```

Important note: ProPainter's own temporary mp4 writing can fail in some PyAV environments, while the repaired frames are already saved. This toolkit treats saved frames as the source of truth and uses ffmpeg to rebuild the final mp4.

注意：某些 PyAV 环境里，ProPainter 自己写临时 mp4 可能失败，但修复后的帧其实已经保存好了。本工具把保存的帧当作事实来源，再用 ffmpeg 重新合成最终 mp4。

## Install CLI For Development / 安装开发版 CLI

```bash
cd /path/to/watermark-studio
python3 -m pip install -e .
```

If your OpenCV environment is in Conda, use that Python:

如果 OpenCV 装在 Conda 环境里，请使用对应 Python：

```bash
/path/to/conda/bin/python -m pip install -e .
```

For tests and development helpers:

测试和开发依赖：

```bash
python3 -m pip install -e ".[dev]"
pytest -q
```

## CLI Usage / CLI 用法

Probe a video:

查看视频信息：

```bash
watermark-studio probe input.mp4
```

Extract a frame to mark:

抽取一帧用于标记：

```bash
watermark-studio preview-frame input.mp4 preview.png --at 0
```

Check required tools:

检查必需工具：

```bash
watermark-studio doctor --python python3 --propainter-dir /path/to/ProPainter
```

Clean a video with a rectangle mask:

使用矩形遮罩清理视频：

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

使用多边形遮罩清理视频：

```bash
watermark-studio clean input.mp4 output.mp4 \
  --propainter-dir /path/to/ProPainter \
  --polygon "596,1128;612,1147;639,1151;621,1169;629,1202;600,1182;535,1210;576,1172;550,1160;581,1147" \
  --expand 3
```

Use rectangle masks for regular watermarks. Use polygon masks for small or irregular watermarks. Keep the mask tight first, then increase `--expand` only when edges still remain.

规则水印适合用矩形遮罩；很小或不规则的水印适合用多边形遮罩。优先贴边标记，只有边缘仍有残留时再调大 `--expand`。

## macOS App / macOS 应用

The macOS app lives in `macos/WatermarkStudio`.

macOS 应用位于 `macos/WatermarkStudio`。

Development run:

开发运行：

```bash
cd macos/WatermarkStudio
swift run WatermarkStudioMac
```

Build a local unsigned `.app`:

打包本地未签名 `.app`：

```bash
cd /path/to/watermark-studio
./scripts/package_mac_app.sh
open "dist/Watermark Studio.app"
```

Current app features:

当前应用功能：

- Open a video. / 打开视频。
- Extract and show the first frame. / 抽取并显示第一帧。
- Drag and resize a rectangle over the watermark. / 拖动和缩放矩形标记框。
- Draw a pen/polygon mask for small or irregular watermarks. / 用钢笔/多边形标记小水印或不规则水印。
- Zoom into the frame while marking. / 标记时可放大画面。
- Preview the final mask. / 预览最终遮罩。
- Adjust mask expansion and ROI padding. / 调整遮罩扩展和 ROI Padding。
- Choose `Fast`, `Balanced`, or `Quality` cleanup presets. / 选择快速、平衡、质量预设。
- Configure and persist ProPainter path, Python path, and output path. / 配置并保存 ProPainter、Python、输出路径。
- Auto-generate unique output names and open/reveal completed videos. / 自动生成唯一输出名，并打开或显示完成视频。
- Run the CLI and stream progress logs. / 调用 CLI 并实时显示日志。

The packaged app includes the `watermark_studio` Python package in app resources, but it still uses your system Python and external ProPainter checkout.

打包后的 app 会把 `watermark_studio` Python 包放进 app resources，但仍然使用你本机的 Python 和外部 ProPainter checkout。

See [Quickstart](docs/quickstart.md) for a full local setup.

完整本地安装流程见 [Quickstart](docs/quickstart.md)。

Before contributing, read [CONTRIBUTING.md](CONTRIBUTING.md). For sensitive reports, see [SECURITY.md](SECURITY.md).

参与贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。敏感问题请参考 [SECURITY.md](SECURITY.md)。

## Speed Presets / 速度预设

The macOS app exposes three ProPainter presets:

macOS 应用内置三个 ProPainter 预设：

- `Fast`: ROI 128, half-resolution inpainting, then composited back into the original video. Good for first-pass checks.
- `Balanced`: ROI 256, full-resolution inpainting. Recommended default for many generated-video watermarks.
- `Quality`: full-frame, slower and more conservative when the repaired area has foreground motion.

中文：

- `Fast`：ROI 128，半分辨率修复后贴回原视频，适合快速试效果。
- `Balanced`：ROI 256，原分辨率修复，适合作为默认选择。
- `Quality`：整帧处理，更慢，更保守，适合修复区域有前景运动时兜底。

For maximum speed, use the smallest accurate mask. Oversized masks are slower and usually smear more detail.

想要更快，关键是遮罩尽量准确、尽量小。过大的遮罩会更慢，也更容易把细节抹花。

## Suggested GitHub Roadmap / 后续路线

- Add backend presets for ProPainter, OpenCV Telea, and LaMa/other image inpainting.
- Add batch mode from the macOS app.
- Package a signed `.app` and optional bundled Python environment.
- Add visual QC contact sheet generation after every run.
- Parse segment logs into a real percent progress indicator.

中文：

- 增加 ProPainter、OpenCV Telea、LaMa 或其他图像修复后端预设。
- 在 macOS app 里增加批处理模式。
- 打包签名版 `.app`，并考虑可选内置 Python 环境。
- 每次处理后生成视觉质检 contact sheet。
- 把 segment 日志解析成真实百分比进度。

## Ethics And Scope / 使用范围

Use this tool only on videos you own, videos you generated, licensed material, or videos where you have permission to remove embedded marks. The repo is meant for cleaning your own generated or licensed production assets.

请只在你拥有的视频、你自己生成的视频、已授权素材，或你有权限去除嵌入标记的视频上使用本工具。本仓库的目标是清理你自己的生成内容或授权生产素材。
