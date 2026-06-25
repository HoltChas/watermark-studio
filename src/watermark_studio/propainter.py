from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import cv2

from .mask import MaskSpec
from .media import encode_video_from_frames, extract_frames, probe_video


@dataclass(frozen=True)
class ProPainterOptions:
    propainter_dir: Path
    python: str = "python3"
    segment_frames: int = 48
    neighbor_length: int = 5
    ref_stride: int = 10
    subvideo_length: int = 12
    raft_iter: int = 10
    mask_dilation: int = 0
    keep_work: bool = False


def clean_video(
    input_mp4: Path,
    output_mp4: Path,
    mask_spec: MaskSpec,
    work_dir: Path,
    options: ProPainterOptions,
    progress: callable | None = None,
) -> None:
    info = probe_video(input_mp4)
    if info.width != mask_spec.width or info.height != mask_spec.height:
        raise ValueError(
            f"Mask size {mask_spec.width}x{mask_spec.height} does not match video {info.width}x{info.height}."
        )
    if options.segment_frames <= 0:
        raise ValueError("segment_frames must be positive.")

    if work_dir.exists():
        shutil.rmtree(work_dir)
    frames_full = work_dir / "frames_full"
    final_frames = work_dir / "final_frames"
    segments = work_dir / "segments"
    frames_full.mkdir(parents=True, exist_ok=True)
    final_frames.mkdir(parents=True, exist_ok=True)

    total_frames = extract_frames(input_mp4, frames_full)
    if total_frames <= 0:
        raise RuntimeError(f"No frames extracted from {input_mp4}")

    mask = mask_spec.render()
    mask_path = work_dir / "mask_preview.png"
    cv2.imwrite(str(mask_path), mask)

    global_out = 0
    segment_index = 0
    for start in range(1, total_frames + 1, options.segment_frames):
        end = min(start + options.segment_frames - 1, total_frames)
        count = end - start + 1
        if progress:
            progress(segment_index, start, end, total_frames)

        seg_dir = segments / f"seg_{segment_index:03d}"
        seg_frames = seg_dir / "frames"
        seg_masks = seg_dir / "masks"
        seg_out = seg_dir / "out"
        seg_frames.mkdir(parents=True, exist_ok=True)
        seg_masks.mkdir(parents=True, exist_ok=True)

        for local, src in enumerate(range(start, end + 1), start=1):
            shutil.copy2(frames_full / f"{src:05d}.png", seg_frames / f"{local:05d}.png")
            cv2.imwrite(str(seg_masks / f"{local - 1:05d}.png"), mask)

        args = [
            options.python,
            "inference_propainter.py",
            "--video",
            str(seg_frames),
            "--mask",
            str(seg_masks),
            "--output",
            str(seg_out),
            "--height",
            str(info.height),
            "--width",
            str(info.width),
            "--mask_dilation",
            str(options.mask_dilation),
            "--neighbor_length",
            str(options.neighbor_length),
            "--ref_stride",
            str(options.ref_stride),
            "--subvideo_length",
            str(options.subvideo_length),
            "--raft_iter",
            str(options.raft_iter),
            "--save_fps",
            f"{info.fps:g}",
            "--save_frames",
        ]
        env = os.environ.copy()
        env.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        proc = subprocess.run(
            args,
            cwd=str(options.propainter_dir),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
        )

        out_frames_dir = seg_out / "frames" / "frames"
        out_frames = sorted(out_frames_dir.glob("*.png")) if out_frames_dir.exists() else []
        if len(out_frames) != count:
            raise RuntimeError(
                f"ProPainter segment {segment_index} failed. "
                f"status={proc.returncode}, expected={count}, got={len(out_frames)}\n{proc.stdout}"
            )

        for local_out in range(count):
            shutil.copy2(out_frames_dir / f"{local_out:04d}.png", final_frames / f"{global_out:04d}.png")
            global_out += 1
        segment_index += 1

    encode_video_from_frames(final_frames, input_mp4, output_mp4, info.fps, info.has_audio)
    if not options.keep_work:
        shutil.rmtree(work_dir, ignore_errors=True)

