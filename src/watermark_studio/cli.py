from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path

from .mask import MaskSpec, parse_polygon, parse_rect
from .media import extract_preview_frame, probe_video
from .propainter import ProPainterOptions, clean_video


def build_mask(args: argparse.Namespace, width: int, height: int) -> MaskSpec:
    if bool(args.rect) == bool(args.polygon):
        raise SystemExit("Provide exactly one of --rect or --polygon.")
    if args.rect:
        x, y, w, h = parse_rect(args.rect)
        return MaskSpec.rectangle(width, height, x, y, w, h, expand=args.expand)
    return MaskSpec.polygon(width, height, parse_polygon(args.polygon), expand=args.expand)


def cmd_probe(args: argparse.Namespace) -> int:
    info = probe_video(Path(args.input))
    print(json.dumps(info.__dict__, indent=2, ensure_ascii=False))
    return 0


def cmd_preview(args: argparse.Namespace) -> int:
    extract_preview_frame(Path(args.input), Path(args.output), args.at)
    print(args.output)
    return 0


def cmd_clean(args: argparse.Namespace) -> int:
    input_mp4 = Path(args.input).expanduser().resolve()
    output_mp4 = Path(args.output).expanduser().resolve()
    info = probe_video(input_mp4)
    mask_spec = build_mask(args, info.width, info.height)
    work_dir = Path(args.work_dir).expanduser().resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix="watermark-studio-"))
    options = ProPainterOptions(
        propainter_dir=Path(args.propainter_dir).expanduser().resolve(),
        python=args.python,
        segment_frames=args.segment_frames,
        neighbor_length=args.neighbor_length,
        ref_stride=args.ref_stride,
        subvideo_length=args.subvideo_length,
        raft_iter=args.raft_iter,
        mask_dilation=args.mask_dilation,
        process_scale=args.process_scale,
        composite_feather=args.composite_feather,
        keep_work=args.keep_work,
    )
    print(f"input={input_mp4}")
    print(f"output={output_mp4}")
    print(f"video={info.width}x{info.height} fps={info.fps:g} frames={info.frame_count}")
    print(f"process_scale={options.process_scale:g}")
    print(f"work_dir={work_dir}")

    def progress(segment: int, start: int, end: int, total: int) -> None:
        print(f"segment={segment} frames={start}-{end}/{total}", flush=True)

    clean_video(input_mp4, output_mp4, mask_spec, work_dir, options, progress=progress)
    print(f"done={output_mp4}")
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="watermark-studio")
    sub = parser.add_subparsers(required=True)

    probe = sub.add_parser("probe", help="Show video metadata.")
    probe.add_argument("input")
    probe.set_defaults(func=cmd_probe)

    preview = sub.add_parser("preview-frame", help="Extract one frame for marking.")
    preview.add_argument("input")
    preview.add_argument("output")
    preview.add_argument("--at", type=float, default=0.0)
    preview.set_defaults(func=cmd_preview)

    clean = sub.add_parser("clean", help="Remove a marked watermark with ProPainter.")
    clean.add_argument("input")
    clean.add_argument("output")
    clean.add_argument("--propainter-dir", required=True)
    clean.add_argument("--python", default="python3")
    clean.add_argument("--rect", help="Rectangle mask in x,y,w,h video pixel coordinates.")
    clean.add_argument("--polygon", help="Polygon mask as x,y;x,y;x,y in video pixel coordinates.")
    clean.add_argument("--expand", type=int, default=3, help="Expand mask by this many pixels.")
    clean.add_argument("--segment-frames", type=int, default=48)
    clean.add_argument("--neighbor-length", type=int, default=5)
    clean.add_argument("--ref-stride", type=int, default=10)
    clean.add_argument("--subvideo-length", type=int, default=12)
    clean.add_argument("--raft-iter", type=int, default=10)
    clean.add_argument("--mask-dilation", type=int, default=0)
    clean.add_argument("--process-scale", type=float, default=1.0, help="Run inpainting at this scale and composite the repaired mask region back onto the original frames.")
    clean.add_argument("--composite-feather", type=int, default=2, help="Feather mask edges when compositing scaled repairs back to full resolution.")
    clean.add_argument("--work-dir")
    clean.add_argument("--keep-work", action="store_true")
    clean.set_defaults(func=cmd_clean)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
