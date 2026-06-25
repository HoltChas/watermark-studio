from pathlib import Path

import cv2

from watermark_studio.mask import MaskSpec, parse_polygon, parse_rect, write_mask_sequence


def test_rectangle_mask_expands() -> None:
    mask = MaskSpec.rectangle(100, 80, 10, 20, 30, 10, expand=2).render()
    assert mask.shape == (80, 100)
    assert mask[20, 10] == 255
    assert mask[18, 10] == 255
    assert mask[0, 0] == 0


def test_polygon_parser() -> None:
    assert parse_polygon("1,2; 3,4; 5,6") == ((1, 2), (3, 4), (5, 6))
    assert parse_rect("1,2,30,40") == (1, 2, 30, 40)


def test_write_mask_sequence(tmp_path: Path) -> None:
    mask = MaskSpec.rectangle(20, 20, 1, 1, 5, 5).render()
    write_mask_sequence(mask, tmp_path, 3)
    assert (tmp_path / "00000.png").exists()
    assert (tmp_path / "00002.png").exists()
    loaded = cv2.imread(str(tmp_path / "00001.png"), cv2.IMREAD_GRAYSCALE)
    assert loaded is not None
    assert loaded[2, 2] == 255

