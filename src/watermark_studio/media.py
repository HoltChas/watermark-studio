from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path


@dataclass(frozen=True)
class VideoInfo:
    width: int
    height: int
    fps: float
    frame_count: int
    duration: float
    has_audio: bool


def run_command(args: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def _parse_fps(value: str) -> float:
    if "/" in value:
        return float(Fraction(value))
    return float(value)


def probe_video(path: Path) -> VideoInfo:
    result = run_command(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(path),
        ]
    )
    payload = json.loads(result.stdout)
    video_stream = next((s for s in payload["streams"] if s.get("codec_type") == "video"), None)
    if not video_stream:
        raise ValueError(f"No video stream found: {path}")
    has_audio = any(s.get("codec_type") == "audio" for s in payload["streams"])
    fps = _parse_fps(video_stream.get("r_frame_rate") or video_stream.get("avg_frame_rate") or "24/1")
    duration = float(payload.get("format", {}).get("duration") or video_stream.get("duration") or 0)
    frames_raw = video_stream.get("nb_frames")
    frame_count = int(frames_raw) if frames_raw and str(frames_raw).isdigit() else int(round(duration * fps))
    return VideoInfo(
        width=int(video_stream["width"]),
        height=int(video_stream["height"]),
        fps=fps,
        frame_count=frame_count,
        duration=duration,
        has_audio=has_audio,
    )


def extract_frames(input_mp4: Path, frames_dir: Path) -> int:
    frames_dir.mkdir(parents=True, exist_ok=True)
    run_command(["ffmpeg", "-y", "-i", str(input_mp4), str(frames_dir / "%05d.png")])
    return len(list(frames_dir.glob("*.png")))


def extract_preview_frame(input_mp4: Path, output_png: Path, at_seconds: float = 0.0) -> None:
    output_png.parent.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            "ffmpeg",
            "-y",
            "-ss",
            f"{at_seconds:.3f}",
            "-i",
            str(input_mp4),
            "-frames:v",
            "1",
            str(output_png),
        ]
    )


def encode_video_from_frames(frames_dir: Path, input_mp4: Path, output_mp4: Path, fps: float, has_audio: bool) -> None:
    output_mp4.parent.mkdir(parents=True, exist_ok=True)
    args = [
        "ffmpeg",
        "-y",
        "-framerate",
        f"{fps:g}",
        "-i",
        str(frames_dir / "%04d.png"),
        "-i",
        str(input_mp4),
        "-map",
        "0:v:0",
    ]
    if has_audio:
        args += ["-map", "1:a:0"]
    args += ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
    if has_audio:
        args += ["-c:a", "aac"]
    args += ["-shortest", str(output_mp4)]
    run_command(args)

