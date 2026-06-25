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
    process_scale: float = 1.0
    composite_feather: int = 2
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
    if not (0 < options.process_scale <= 1):
        raise ValueError("process_scale must be > 0 and <= 1.")

    if work_dir.exists():
        shutil.rmtree(work_dir)
    frames_full = work_dir / "frames_full"
    process_frames_full = work_dir / "process_frames_full"
    final_frames = work_dir / "final_frames"
    segments = work_dir / "segments"
    frames_full.mkdir(parents=True, exist_ok=True)
    process_frames_full.mkdir(parents=True, exist_ok=True)
    final_frames.mkdir(parents=True, exist_ok=True)

    total_frames = extract_frames(input_mp4, frames_full)
    if total_frames <= 0:
        raise RuntimeError(f"No frames extracted from {input_mp4}")

    process_width = _even_dimension(round(info.width * options.process_scale))
    process_height = _even_dimension(round(info.height * options.process_scale))

    mask = mask_spec.render()
    process_mask = cv2.resize(mask, (process_width, process_height), interpolation=cv2.INTER_NEAREST)
    alpha = _mask_alpha(mask, options.composite_feather)
    mask_path = work_dir / "mask_preview.png"
    cv2.imwrite(str(mask_path), mask)
    cv2.imwrite(str(work_dir / "process_mask_preview.png"), process_mask)
    _write_process_frames(frames_full, process_frames_full, total_frames, process_width, process_height)

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
            shutil.copy2(process_frames_full / f"{src:05d}.png", seg_frames / f"{local:05d}.png")
            cv2.imwrite(str(seg_masks / f"{local - 1:05d}.png"), process_mask)

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
            str(process_height),
            "--width",
            str(process_width),
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
            source_frame = frames_full / f"{start + local_out:05d}.png"
            repaired_frame = out_frames_dir / f"{local_out:04d}.png"
            final_frame = final_frames / f"{global_out:04d}.png"
            if options.process_scale < 0.999:
                _composite_repaired_region(source_frame, repaired_frame, final_frame, mask, alpha, info.width, info.height)
            else:
                shutil.copy2(repaired_frame, final_frame)
            global_out += 1
        segment_index += 1

    encode_video_from_frames(final_frames, input_mp4, output_mp4, info.fps, info.has_audio)
    if not options.keep_work:
        shutil.rmtree(work_dir, ignore_errors=True)


def _even_dimension(value: int) -> int:
    value = max(value, 2)
    return value if value % 2 == 0 else value - 1


def _write_process_frames(source_dir: Path, out_dir: Path, total_frames: int, width: int, height: int) -> None:
    for index in range(1, total_frames + 1):
        source_path = source_dir / f"{index:05d}.png"
        frame = cv2.imread(str(source_path), cv2.IMREAD_COLOR)
        if frame is None:
            raise RuntimeError(f"Could not read frame: {source_path}")
        resized = cv2.resize(frame, (width, height), interpolation=cv2.INTER_AREA)
        ok = cv2.imwrite(str(out_dir / f"{index:05d}.png"), resized)
        if not ok:
            raise RuntimeError(f"Could not write resized frame: {out_dir / f'{index:05d}.png'}")


def _mask_alpha(mask: cv2.typing.MatLike, feather: int) -> cv2.typing.MatLike:
    alpha = mask.astype("float32") / 255.0
    if feather > 0:
        kernel = feather * 2 + 1
        alpha = cv2.GaussianBlur(alpha, (kernel, kernel), 0)
    return alpha[:, :, None]


def _composite_repaired_region(
    original_path: Path,
    repaired_path: Path,
    output_path: Path,
    mask: cv2.typing.MatLike,
    alpha: cv2.typing.MatLike,
    width: int,
    height: int,
) -> None:
    original = cv2.imread(str(original_path), cv2.IMREAD_COLOR)
    repaired = cv2.imread(str(repaired_path), cv2.IMREAD_COLOR)
    if original is None:
        raise RuntimeError(f"Could not read original frame: {original_path}")
    if repaired is None:
        raise RuntimeError(f"Could not read repaired frame: {repaired_path}")
    repaired_full = cv2.resize(repaired, (width, height), interpolation=cv2.INTER_CUBIC)
    blended = (repaired_full.astype("float32") * alpha) + (original.astype("float32") * (1.0 - alpha))
    out = blended.clip(0, 255).astype("uint8")
    # Preserve fully unmasked pixels byte-for-byte after feathering math.
    out[mask == 0] = original[mask == 0]
    ok = cv2.imwrite(str(output_path), out)
    if not ok:
        raise RuntimeError(f"Could not write final frame: {output_path}")
