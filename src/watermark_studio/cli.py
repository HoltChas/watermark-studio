from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .mask import MaskSpec, parse_polygon, parse_rect
from .media import extract_preview_frame, probe_video
from .propainter import ProPainterOptions, clean_video


@dataclass(frozen=True)
class DoctorCheck:
    name: str
    ok: bool
    detail: str


def _tail(text: str, lines: int = 8) -> str:
    return "\n".join(text.strip().splitlines()[-lines:]) or "command failed"


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


def _executable_exists(command: str) -> bool:
    path = Path(command).expanduser()
    if path.parent != Path(".") or path.is_absolute():
        return path.exists() and path.is_file()
    return shutil.which(command) is not None


def _python_check(command: str) -> DoctorCheck:
    if not _executable_exists(command):
        return DoctorCheck("python", False, f"not found: {command}")
    try:
        result = subprocess.run(
            [
                command,
                "-c",
                "import sys; import cv2; import numpy; print(sys.version.split()[0])",
            ],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        output = getattr(error, "stdout", "") or str(error)
        return DoctorCheck("python", False, _tail(output))
    return DoctorCheck("python", True, f"{result.stdout.strip()} with cv2/numpy")


def _command_check(name: str) -> DoctorCheck:
    path = shutil.which(name)
    return DoctorCheck(name, path is not None, path or "not found on PATH")


def _propainter_check(value: str | None) -> DoctorCheck:
    if not value:
        return DoctorCheck("propainter", False, "not configured; pass --propainter-dir")
    root = Path(value).expanduser()
    script = root / "inference_propainter.py"
    if not root.exists():
        return DoctorCheck("propainter", False, f"directory not found: {root}")
    if not script.exists():
        return DoctorCheck("propainter", False, f"missing inference_propainter.py in {root}")
    return DoctorCheck("propainter", True, str(root.resolve()))


def cmd_doctor(args: argparse.Namespace) -> int:
    checks = [
        _command_check("ffmpeg"),
        _command_check("ffprobe"),
        _python_check(args.python),
        _propainter_check(args.propainter_dir),
    ]
    if args.json:
        print(json.dumps([check.__dict__ for check in checks], indent=2, ensure_ascii=False))
    else:
        for check in checks:
            status = "OK" if check.ok else "FAIL"
            print(f"{status:4} {check.name}: {check.detail}")
    return 0 if all(check.ok for check in checks) else 1


def cmd_clean(args: argparse.Namespace) -> int:
    input_mp4 = Path(args.input).expanduser().resolve()
    output_mp4 = Path(args.output).expanduser().resolve()
    info = probe_video(input_mp4)
    mask_spec = build_mask(args, info.width, info.height)
    cleanup_work_dir_root = args.work_dir is None
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
        roi_padding=args.roi_padding,
        keep_work=args.keep_work,
        cleanup_work_dir_root=cleanup_work_dir_root,
    )
    print(f"input={input_mp4}")
    print(f"output={output_mp4}")
    print(f"video={info.width}x{info.height} fps={info.fps:g} frames={info.frame_count}")
    print(f"process_scale={options.process_scale:g}")
    print(f"roi_padding={options.roi_padding}")
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

    doctor = sub.add_parser("doctor", help="Check local tools and ProPainter configuration.")
    doctor.add_argument("--python", default="python3")
    doctor.add_argument("--propainter-dir")
    doctor.add_argument("--json", action="store_true")
    doctor.set_defaults(func=cmd_doctor)

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
    clean.add_argument("--roi-padding", type=int, default=0, help="Crop processing to the marked mask plus this many pixels of context. Use 0 to process the whole frame.")
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
