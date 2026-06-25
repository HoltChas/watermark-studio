# Watermark Studio

[English README](README.md)

> 开发预览版：CLI 和 macOS 应用已经可用于本地工作流，但 macOS 应用还没有签名和公证。

Watermark Studio 是一个实用的视频水印清理工具。它可以帮助你标记水印区域、生成固定遮罩、分段调用视频修复后端，并把修复后的画面重新合成为保留原音频的视频。

当前第一个后端目标是 [ProPainter](https://github.com/sczhou/ProPainter)。请单独安装 ProPainter，并在 CLI 或 macOS 应用里配置本机路径。

## 仓库内容

- `watermark-studio` Python 命令行工具。
- 可复用的 Python 模块：遮罩、ffmpeg/ffprobe 媒体处理、ROI 裁剪、ProPainter 分段处理。
- 原生 macOS SwiftUI 应用：打开视频、标记方框或钢笔/多边形遮罩、调整参数、启动清理。
- 示例遮罩、快速开始文档、CI 和开源协作文档。

## 界面方向

第一版 macOS 界面方向如下：

![Watermark Studio UI mockup](docs/assets/ui-mockup.png)

## 环境要求

- CLI 支持 macOS 或 Linux。
- SwiftUI app 需要 macOS 14+。
- `ffmpeg` 和 `ffprobe` 需要在 `PATH` 中。
- Python 3.10+，并安装 OpenCV 和 NumPy。
- 本机需要有可运行的 ProPainter checkout 和对应环境。

检查本机环境：

```bash
watermark-studio doctor \
  --python python3 \
  --propainter-dir /path/to/ProPainter
```

短生成视频推荐的 ProPainter 参数：

```bash
--mask_dilation 0 \
--neighbor_length 5 \
--ref_stride 10 \
--subvideo_length 12 \
--raft_iter 10 \
--save_frames
```

注意：某些 PyAV 环境里，ProPainter 自己写临时 mp4 可能失败，但修复后的帧其实已经保存好了。本工具把保存的帧当作事实来源，再用 ffmpeg 重新合成最终 mp4。

## 安装开发版 CLI

```bash
cd /path/to/watermark-studio
python3 -m pip install -e .
```

如果 OpenCV 装在 Conda 环境里，请使用对应 Python：

```bash
/path/to/conda/bin/python -m pip install -e .
```

测试和开发依赖：

```bash
python3 -m pip install -e ".[dev]"
pytest -q
```

## CLI 用法

查看视频信息：

```bash
watermark-studio probe input.mp4
```

抽取一帧用于标记：

```bash
watermark-studio preview-frame input.mp4 preview.png --at 0
```

检查必需工具：

```bash
watermark-studio doctor --python python3 --propainter-dir /path/to/ProPainter
```

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

使用多边形遮罩清理视频：

```bash
watermark-studio clean input.mp4 output.mp4 \
  --propainter-dir /path/to/ProPainter \
  --polygon "596,1128;612,1147;639,1151;621,1169;629,1202;600,1182;535,1210;576,1172;550,1160;581,1147" \
  --expand 3
```

规则水印适合用矩形遮罩；很小或不规则的水印适合用多边形遮罩。优先贴边标记，只有边缘仍有残留时再调大 `--expand`。

## macOS 应用

macOS 应用位于 `macos/WatermarkStudio`。

开发运行：

```bash
cd macos/WatermarkStudio
swift run WatermarkStudioMac
```

打包本地未签名 `.app`：

```bash
cd /path/to/watermark-studio
./scripts/package_mac_app.sh
open "dist/Watermark Studio.app"
```

当前应用功能：

- 打开视频。
- 抽取并显示第一帧。
- 拖动和缩放矩形标记框。
- 用钢笔/多边形标记小水印或不规则水印。
- 标记时可放大画面。
- 预览最终遮罩。
- 调整遮罩扩展和 ROI Padding。
- 选择快速、平衡、质量预设。
- 配置并保存 ProPainter、Python、输出路径。
- 自动生成唯一输出名，并打开或显示完成视频。
- 调用 CLI 并实时显示日志。

打包后的 app 会把 `watermark_studio` Python 包放进 app resources，但仍然使用你本机的 Python 和外部 ProPainter checkout。

完整本地安装流程见 [Quickstart](docs/quickstart.md)。

参与贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。敏感问题请参考 [SECURITY.md](SECURITY.md)。

## 速度预设

macOS 应用内置三个 ProPainter 预设：

- `Fast`：ROI 128，半分辨率修复后贴回原视频，适合快速试效果。
- `Balanced`：ROI 256，原分辨率修复，适合作为默认选择。
- `Quality`：整帧处理，更慢，更保守，适合修复区域有前景运动时兜底。

想要更快，关键是遮罩尽量准确、尽量小。过大的遮罩会更慢，也更容易把细节抹花。

## 后续路线

- 增加 ProPainter、OpenCV Telea、LaMa 或其他图像修复后端预设。
- 在 macOS app 里增加批处理模式。
- 打包签名版 `.app`，并考虑可选内置 Python 环境。
- 每次处理后生成视觉质检 contact sheet。
- 把 segment 日志解析成真实百分比进度。

## 使用范围

请只在你拥有的视频、你自己生成的视频、已授权素材，或你有权限去除嵌入标记的视频上使用本工具。本仓库的目标是清理你自己的生成内容或授权生产素材。
