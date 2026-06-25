from pathlib import Path
from types import SimpleNamespace

import cv2
import numpy as np
import pytest

import watermark_studio.propainter as propainter
from watermark_studio.mask import MaskSpec
from watermark_studio.propainter import ProPainterOptions, _mask_crop_region, _prepare_work_dir, clean_video


def test_mask_crop_region_uses_padding_and_even_dimensions() -> None:
    mask = np.zeros((100, 120), dtype=np.uint8)
    mask[40:45, 60:65] = 255

    crop = _mask_crop_region(mask, padding=7)

    assert crop.x == 53
    assert crop.y == 33
    assert crop.width % 2 == 0
    assert crop.height % 2 == 0
    assert crop.width >= 19
    assert crop.height >= 19


def test_prepare_work_dir_refuses_home() -> None:
    with pytest.raises(ValueError, match="unsafe work_dir"):
        _prepare_work_dir(Path.home(), [])


def test_prepare_work_dir_only_clears_managed_children(tmp_path) -> None:
    keep_file = tmp_path / "keep.txt"
    keep_file.write_text("do not delete")
    managed = tmp_path / "frames_full"
    managed.mkdir()
    (managed / "old.png").write_text("old")

    _prepare_work_dir(tmp_path, [managed])

    assert keep_file.exists()
    assert managed.exists()
    assert not (managed / "old.png").exists()


def test_clean_video_cleanup_preserves_unmanaged_files(tmp_path, monkeypatch) -> None:
    keep_file = tmp_path / "keep.txt"
    keep_file.write_text("do not delete")
    propainter_dir = tmp_path / "ProPainter"
    propainter_dir.mkdir()
    (propainter_dir / "inference_propainter.py").write_text("# test stub\n")

    def fake_probe_video(_path):
        return SimpleNamespace(width=20, height=20, fps=24, frame_count=1, has_audio=False)

    def fake_extract_frames(_input_mp4, frames_dir):
        frames_dir.mkdir(parents=True, exist_ok=True)
        frame = np.zeros((20, 20, 3), dtype=np.uint8)
        cv2.imwrite(str(frames_dir / "00001.png"), frame)
        return 1

    def fake_run(args, cwd, text, stdout, stderr, env):
        output_dir = Path(args[args.index("--output") + 1]) / "frames" / "frames"
        output_dir.mkdir(parents=True, exist_ok=True)
        frame = np.zeros((20, 20, 3), dtype=np.uint8)
        cv2.imwrite(str(output_dir / "0000.png"), frame)
        return SimpleNamespace(returncode=0, stdout="ok")

    monkeypatch.setattr(propainter, "probe_video", fake_probe_video)
    monkeypatch.setattr(propainter, "extract_frames", fake_extract_frames)
    monkeypatch.setattr(propainter.subprocess, "run", fake_run)
    monkeypatch.setattr(propainter, "encode_video_from_frames", lambda *args, **kwargs: None)

    clean_video(
        tmp_path / "input.mp4",
        tmp_path / "output.mp4",
        MaskSpec.rectangle(20, 20, 2, 2, 4, 4),
        tmp_path,
        ProPainterOptions(propainter_dir=propainter_dir, python="python3", keep_work=False),
    )

    assert keep_file.exists()
    assert not (tmp_path / "frames_full").exists()
    assert not (tmp_path / "segments").exists()
    assert not (tmp_path / "mask_preview.png").exists()


def test_clean_video_can_remove_auto_created_work_dir(tmp_path, monkeypatch) -> None:
    work_dir = tmp_path / "auto-work"
    propainter_dir = tmp_path / "ProPainter"
    propainter_dir.mkdir()
    (propainter_dir / "inference_propainter.py").write_text("# test stub\n")

    def fake_probe_video(_path):
        return SimpleNamespace(width=20, height=20, fps=24, frame_count=1, has_audio=False)

    def fake_extract_frames(_input_mp4, frames_dir):
        frames_dir.mkdir(parents=True, exist_ok=True)
        frame = np.zeros((20, 20, 3), dtype=np.uint8)
        cv2.imwrite(str(frames_dir / "00001.png"), frame)
        return 1

    def fake_run(args, cwd, text, stdout, stderr, env):
        output_dir = Path(args[args.index("--output") + 1]) / "frames" / "frames"
        output_dir.mkdir(parents=True, exist_ok=True)
        frame = np.zeros((20, 20, 3), dtype=np.uint8)
        cv2.imwrite(str(output_dir / "0000.png"), frame)
        return SimpleNamespace(returncode=0, stdout="ok")

    monkeypatch.setattr(propainter, "probe_video", fake_probe_video)
    monkeypatch.setattr(propainter, "extract_frames", fake_extract_frames)
    monkeypatch.setattr(propainter.subprocess, "run", fake_run)
    monkeypatch.setattr(propainter, "encode_video_from_frames", lambda *args, **kwargs: None)

    clean_video(
        tmp_path / "input.mp4",
        tmp_path / "output.mp4",
        MaskSpec.rectangle(20, 20, 2, 2, 4, 4),
        work_dir,
        ProPainterOptions(
            propainter_dir=propainter_dir,
            python="python3",
            keep_work=False,
            cleanup_work_dir_root=True,
        ),
    )

    assert not work_dir.exists()
