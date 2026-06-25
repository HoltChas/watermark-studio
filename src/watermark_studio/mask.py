from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np


Point = tuple[int, int]


@dataclass(frozen=True)
class MaskSpec:
    width: int
    height: int
    points: tuple[Point, ...]
    expand: int = 0

    @classmethod
    def rectangle(
        cls,
        width: int,
        height: int,
        x: int,
        y: int,
        w: int,
        h: int,
        expand: int = 0,
    ) -> "MaskSpec":
        return cls(
            width=width,
            height=height,
            points=((x, y), (x + w, y), (x + w, y + h), (x, y + h)),
            expand=expand,
        )

    @classmethod
    def polygon(
        cls,
        width: int,
        height: int,
        points: Iterable[Point],
        expand: int = 0,
    ) -> "MaskSpec":
        pts = tuple((int(x), int(y)) for x, y in points)
        if len(pts) < 3:
            raise ValueError("A polygon mask needs at least three points.")
        return cls(width=width, height=height, points=pts, expand=expand)

    def render(self) -> np.ndarray:
        if self.width <= 0 or self.height <= 0:
            raise ValueError("Mask width and height must be positive.")
        mask = np.zeros((self.height, self.width), dtype=np.uint8)
        pts = np.array([self.points], dtype=np.int32)
        cv2.fillPoly(mask, pts, 255)
        if self.expand > 0:
            kernel_size = self.expand * 2 + 1
            kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
            mask = cv2.dilate(mask, kernel, iterations=1)
        return mask


def parse_rect(value: str) -> tuple[int, int, int, int]:
    parts = [p.strip() for p in value.split(",")]
    if len(parts) != 4:
        raise ValueError("Rectangle must be x,y,w,h.")
    return tuple(int(round(float(p))) for p in parts)  # type: ignore[return-value]


def parse_polygon(value: str) -> tuple[Point, ...]:
    points: list[Point] = []
    for raw in value.split(";"):
        raw = raw.strip()
        if not raw:
            continue
        x_raw, y_raw = [p.strip() for p in raw.split(",", 1)]
        points.append((int(round(float(x_raw))), int(round(float(y_raw)))))
    if len(points) < 3:
        raise ValueError("Polygon must be formatted as x,y;x,y;x,y with at least three points.")
    return tuple(points)


def write_mask_sequence(mask: np.ndarray, out_dir: Path, frame_count: int, zero_based: bool = True) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    start = 0 if zero_based else 1
    for index in range(start, start + frame_count):
        filename = f"{index:05d}.png"
        ok = cv2.imwrite(str(out_dir / filename), mask)
        if not ok:
            raise RuntimeError(f"Could not write mask frame: {out_dir / filename}")

