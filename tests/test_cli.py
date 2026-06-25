import json
import sys

import watermark_studio.cli as cli
from watermark_studio.cli import main


def test_doctor_reports_missing_propainter(monkeypatch, capsys) -> None:
    monkeypatch.setattr(cli.shutil, "which", lambda name: f"/usr/bin/{name}" if name in {"ffmpeg", "ffprobe"} else None)
    status = main(["doctor", "--python", sys.executable])
    captured = capsys.readouterr()

    assert status == 1
    assert "OK" in captured.out
    assert "FAIL propainter" in captured.out


def test_doctor_json_success(tmp_path, monkeypatch, capsys) -> None:
    monkeypatch.setattr(cli.shutil, "which", lambda name: f"/usr/bin/{name}" if name in {"ffmpeg", "ffprobe"} else None)
    propainter = tmp_path / "ProPainter"
    propainter.mkdir()
    (propainter / "inference_propainter.py").write_text("# test stub\n")

    status = main(
        [
            "doctor",
            "--python",
            sys.executable,
            "--propainter-dir",
            str(propainter),
            "--json",
        ]
    )
    captured = capsys.readouterr()
    payload = json.loads(captured.out)

    assert status == 0
    assert all(item["ok"] for item in payload)
    assert {item["name"] for item in payload} == {"ffmpeg", "ffprobe", "python", "propainter"}
