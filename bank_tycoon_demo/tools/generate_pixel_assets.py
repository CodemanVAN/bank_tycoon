#!/usr/bin/env python3
"""
Deterministic procedural pixel-art asset generator for Starway Bank / Bank Tycoon.
Generates 60 palette-locked RGBA PNG-32 files under bank_tycoon_demo/assets/:
  - 17 environment sprites (256-px exact 2:1 iso floor tiles, walls, fountain sheet, props)
  - 24 character sprites (6 employee + 6 customer 96x128 4x4 sheets + 32x32 portraits)
  - 19 UI/status icons (24x24 navigation/emblem + 16x16 speed/HUD badges, zero baked text)

Requires: Python 3.10+, Pillow (PIL). Zero deprecated Pillow APIs.
"""

from __future__ import annotations

import hashlib
import math
from pathlib import Path
from typing import Callable

from PIL import Image

ASSETS_DIR = Path(__file__).resolve().parent.parent / "assets"

TRANSPARENT: tuple[int, int, int, int] = (0, 0, 0, 0)

PALETTE: dict[str, tuple[int, int, int, int]] = {
    # Outlines (1px non-black)
    "OUTLINE_TECH": (16, 32, 59, 255),      # #10203B
    "OUTLINE_WARM": (38, 35, 44, 255),      # #26232C
    # Starway Tech Blue
    "SB_NAVY": (8, 27, 54, 255),            # #081B36
    "SB_PANEL": (11, 45, 91, 255),          # #0B2D5B
    "SB_SLATE": (38, 61, 92, 255),          # #263D5C
    "SB_STEEL": (82, 107, 141, 255),        # #526B8D
    "SB_BLUE": (31, 111, 235, 255),         # #1F6FEB
    "SB_ELECTRIC": (45, 156, 255, 255),     # #2D9CFF
    "SB_CYAN": (0, 198, 255, 255),          # #00C6FF
    "SB_ICE": (191, 232, 255, 255),         # #BFE8FF
    "SB_WHITE": (245, 248, 255, 255),       # #F5F8FF
    # Semantic Accents
    "GOLD_H": (255, 232, 158, 255),         # #FFE89E
    "GOLD_B": (255, 200, 87, 255),          # #FFC857
    "GOLD_M": (212, 166, 83, 255),          # #D4A653
    "GOLD_D": (148, 105, 39, 255),          # #946927
    "GREEN_H": (111, 227, 159, 255),        # #6FE39F
    "GREEN_B": (53, 201, 120, 255),         # #35C978
    "GREEN_D": (30, 122, 74, 255),          # #1E7A4A
    "RED_H": (255, 123, 107, 255),          # #FF7B6B
    "RED_B": (231, 76, 60, 255),            # #E74C3C
    "RED_D": (158, 47, 38, 255),            # #9E2F26
    "VIOLET_H": (195, 184, 255, 255),       # #C3B8FF
    "VIOLET_B": (155, 140, 255, 255),       # #9B8CFF
    "VIOLET_D": (95, 80, 181, 255),         # #5F50B5
    # Lobby Ivory & Stone
    "IVORY_H": (255, 253, 245, 255),        # #FFFDF5
    "IVORY_B": (242, 233, 215, 255),        # #F2E9D7
    "IVORY_M": (229, 215, 189, 255),        # #E5D7BD
    "IVORY_D": (196, 179, 149, 255),        # #C4B395
    "STONE_D": (147, 136, 120, 255),        # #938878
    # Lobby Warm Wood
    "WOOD_H": (232, 186, 128, 255),         # #E8BA80
    "WOOD_B": (199, 139, 80, 255),          # #C78B50
    "WOOD_M": (158, 102, 52, 255),          # #9E6634
    "WOOD_D": (110, 68, 34, 255),           # #6E4422
    # Glass & Carpet
    "GLASS_D": (20, 53, 99, 255),           # #143563
    "CARPET_BLUE_D": (20, 72, 158, 255),    # #14489E
    "VIP_CRIMSON": (143, 45, 59, 255),      # #8F2D3B
    # Character Skins
    "SKIN_L_B": (250, 208, 174, 255),
    "SKIN_L_D": (214, 159, 120, 255),
    "SKIN_M_B": (224, 172, 126, 255),
    "SKIN_M_D": (181, 126, 82, 255),
    "SKIN_T_B": (186, 127, 84, 255),
    "SKIN_T_D": (140, 88, 53, 255),
    # Character Hair
    "HAIR_DARK": (45, 38, 51, 255),
    "HAIR_DARK_H": (74, 63, 82, 255),
    "HAIR_BROWN": (107, 62, 43, 255),
    "HAIR_BROWN_H": (148, 88, 61, 255),
    "HAIR_BLONDE": (199, 141, 50, 255),
    "HAIR_BLONDE_H": (235, 186, 91, 255),
    "HAIR_GREY": (138, 150, 171, 255),
    "HAIR_GREY_H": (198, 208, 224, 255),
    # Customer Casual
    "SAGE_B": (131, 165, 139, 255),
    "SAGE_D": (90, 122, 99, 255),
}

ALLOWED_RGBA_SET: set[tuple[int, int, int, int]] = set(PALETTE.values()) | {TRANSPARENT}


def det_hash(x: int, y: int, seed: int = 0) -> int:
    return ((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)) & 0xFFFFFFFF


def iso_diamond_mask_32x16() -> set[tuple[int, int]]:
    mask: set[tuple[int, int]] = set()
    for y in range(16):
        x_start = (15 - 2 * y) if y < 8 else (2 * (y - 8) + 1)
        for x in range(x_start, 32 - x_start):
            mask.add((x, y))
    return mask


ISO_DIAMOND_256 = iso_diamond_mask_32x16()


class PixelCanvas:
    """Integer-grid RGBA pixel buffer locked strictly to PALETTE tokens."""

    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self._grid: list[list[tuple[int, int, int, int]]] = [
            [TRANSPARENT for _ in range(width)] for _ in range(height)
        ]

    def set_px(self, x: int, y: int, key: str | None) -> None:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return
        if key is None:
            self._grid[y][x] = TRANSPARENT
            return
        if key not in PALETTE:
            raise ValueError(f"Unregistered palette token: {key!r}")
        self._grid[y][x] = PALETTE[key]

    def get_rgba(self, x: int, y: int) -> tuple[int, int, int, int]:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return TRANSPARENT
        return self._grid[y][x]

    def is_opaque(self, x: int, y: int) -> bool:
        return self.get_rgba(x, y)[3] == 255

    def fill_rect(self, x: int, y: int, w: int, h: int, key: str | None) -> None:
        for py in range(y, y + h):
            for px in range(x, x + w):
                self.set_px(px, py, key)

    def stroke_rect(self, x: int, y: int, w: int, h: int, key: str) -> None:
        for px in range(x, x + w):
            self.set_px(px, y, key)
            self.set_px(px, y + h - 1, key)
        for py in range(y, y + h):
            self.set_px(x, py, key)
            self.set_px(x + w - 1, py, key)

    def fill_ellipse(self, cx: float, cy: float, rx: float, ry: float, key: str) -> None:
        x0 = max(0, int(cx - rx - 1))
        x1 = min(self.width - 1, int(cx + rx + 1))
        y0 = max(0, int(cy - ry - 1))
        y1 = min(self.height - 1, int(cy + ry + 1))
        for py in range(y0, y1 + 1):
            for px in range(x0, x1 + 1):
                nx = (px + 0.5 - cx) / rx
                ny = (py + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1.0:
                    self.set_px(px, py, key)

    def draw_line(self, x0: int, y0: int, x1: int, y1: int, key: str) -> None:
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        cx, cy = x0, y0
        while True:
            self.set_px(cx, cy, key)
            if cx == x1 and cy == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                cx += sx
            if e2 <= dx:
                err += dx
                cy += sy

    def fill_polygon_scanline(self, pts: list[tuple[int, int]], key: str) -> None:
        if not pts:
            return
        min_y = max(0, min(p[1] for p in pts))
        max_y = min(self.height - 1, max(p[1] for p in pts))
        n = len(pts)
        for y in range(min_y, max_y + 1):
            xs: list[float] = []
            yf = y + 0.5
            for i in range(n):
                x1, y1 = pts[i]
                x2, y2 = pts[(i + 1) % n]
                if (y1 <= yf < y2) or (y2 <= yf < y1):
                    t = (yf - y1) / (y2 - y1)
                    xs.append(x1 + t * (x2 - x1))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                start = max(0, int(round(xs[i])))
                end = min(self.width - 1, int(round(xs[i + 1])))
                for x in range(start, end + 1):
                    self.set_px(x, y, key)

    def fill_iso_diamond_32x16(self, color_fn: Callable[[int, int, int], str]) -> None:
        for y in range(16):
            x_start = (15 - 2 * y) if y < 8 else (2 * (y - 8) + 1)
            for x in range(x_start, 32 - x_start):
                self.set_px(x, y, color_fn(x, y, x_start))

    def apply_outline(
        self,
        outline_key: str,
        x0: int = 0,
        y0: int = 0,
        x1: int | None = None,
        y1: int | None = None,
        skip_bottom_row: bool = False,
    ) -> None:
        rx1 = self.width if x1 is None else x1
        ry1 = self.height if y1 is None else y1
        to_outline: list[tuple[int, int]] = []
        for y in range(y0, ry1):
            if skip_bottom_row and y == ry1 - 1:
                continue
            for x in range(x0, rx1):
                if self.is_opaque(x, y):
                    continue
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if x0 <= nx < rx1 and y0 <= ny < ry1 and self.is_opaque(nx, ny):
                        to_outline.append((x, y))
                        break
        for x, y in to_outline:
            self.set_px(x, y, outline_key)

    def blit_from(self, src: PixelCanvas, dest_x: int, dest_y: int) -> None:
        for sy in range(src.height):
            dy = dest_y + sy
            if not (0 <= dy < self.height):
                continue
            for sx in range(src.width):
                dx = dest_x + sx
                if not (0 <= dx < self.width):
                    continue
                px = src._grid[sy][sx]
                if px[3] == 255:
                    self._grid[dy][dx] = px

    def to_image(self) -> Image.Image:
        img = Image.new("RGBA", (self.width, self.height), TRANSPARENT)
        flat = [px for row in self._grid for px in row]
        img.putdata(flat)
        return img

    def save_png(self, rel_path: str) -> Path:
        out_path = ASSETS_DIR / rel_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        self.to_image().save(out_path, format="PNG", optimize=False)
        return out_path


# ---------------------------------------------------------------------------
# 1. ENVIRONMENT SPRITES (17 files)
# ---------------------------------------------------------------------------

def gen_tile_floor_ivory() -> PixelCanvas:
    c = PixelCanvas(32, 20)
    for y in range(20):
        for x in range(32):
            # Clean 32x20 orthogonal marble slab (2 sub-slabs side by side)
            if y == 19 or x == 31:
                c.set_px(x, y, "IVORY_D")
            elif x == 15:
                c.set_px(x, y, "IVORY_M")
            elif y == 0 or x == 0 or x == 16:
                c.set_px(x, y, "IVORY_H")
            elif (x + y * 2) % 13 == 0 and det_hash(x, y, 1) % 3 == 0:
                c.set_px(x, y, "IVORY_M")
            elif (x - y * 2) % 17 == 0 and y < 14:
                c.set_px(x, y, "IVORY_H")
            else:
                c.set_px(x, y, "IVORY_M" if (det_hash(x, y, 2) % 11 == 0) else "IVORY_B")
    return c


def gen_tile_floor_wood() -> PixelCanvas:
    c = PixelCanvas(32, 20)
    # 4 horizontal hardwood planks (5px tall each) with staggered vertical joints
    joint_cols = (11, 24, 6, 19)
    for y in range(20):
        plank_id = y // 5
        local_y = y % 5
        joint_x = joint_cols[plank_id]
        for x in range(32):
            if local_y == 4 or x == joint_x:
                c.set_px(x, y, "WOOD_D")
            elif local_y == 0:
                c.set_px(x, y, "WOOD_H" if (plank_id % 2 == 0 or x > joint_x) else "WOOD_B")
            elif det_hash(x, y, 11 + plank_id) % 6 == 0:
                c.set_px(x, y, "WOOD_M")
            else:
                c.set_px(x, y, "WOOD_B")
    return c


def gen_tile_floor_carpet_blue() -> PixelCanvas:
    c = PixelCanvas(32, 20)
    for y in range(20):
        for x in range(32):
            if y == 0 or y == 19 or x == 0 or x == 31:
                c.set_px(x, y, "SB_BLUE" if y < 10 else "CARPET_BLUE_D")
            elif (y in (2, 17) and 2 <= x <= 29) or (x in (2, 29) and 2 <= y <= 17):
                c.set_px(x, y, "SB_BLUE")
            elif abs(x - 15.5) + abs(y - 9.5) <= 2.5:
                c.set_px(x, y, "SB_ELECTRIC" if (x + y) % 2 == 0 else "SB_BLUE")
            else:
                c.set_px(x, y, "SB_PANEL" if (x + y) % 2 == 0 else "CARPET_BLUE_D")
    return c


def gen_tile_floor_vip() -> PixelCanvas:
    c = PixelCanvas(32, 20)
    for y in range(20):
        for x in range(32):
            if y == 0 or y == 19 or x == 0 or x == 31:
                c.set_px(x, y, "SB_NAVY")
            elif (y in (2, 17) and 2 <= x <= 29) or (x in (2, 29) and 2 <= y <= 17):
                c.set_px(x, y, "GOLD_B" if y < 10 else "GOLD_M")
            elif abs(x - 15.5) + abs(y - 9.5) <= 3.0:
                if abs(x - 15.5) < 1.0 and abs(y - 9.5) < 1.0:
                    c.set_px(x, y, "GOLD_H")
                else:
                    c.set_px(x, y, "VIP_CRIMSON")
            else:
                c.set_px(x, y, "SB_PANEL" if (x + y) % 2 == 0 else "VIP_CRIMSON")
    return c


def gen_wall_section_back() -> PixelCanvas:
    c = PixelCanvas(32, 48)
    # Interior marble wall with top slate cornice, tech-blue dado stripe, stone baseboard
    c.fill_rect(1, 2, 30, 44, "IVORY_B")
    # Top cornice
    c.fill_rect(1, 2, 30, 4, "SB_SLATE")
    c.fill_rect(1, 2, 30, 1, "SB_STEEL")
    c.fill_rect(1, 5, 30, 1, "SB_NAVY")
    # Upper recessed panel
    c.fill_rect(3, 8, 26, 17, "IVORY_M")
    c.fill_rect(4, 9, 24, 15, "IVORY_B")
    c.fill_rect(4, 9, 24, 1, "IVORY_H")
    c.fill_rect(4, 9, 1, 15, "IVORY_H")
    # Tech-blue dado stripe
    c.fill_rect(1, 27, 30, 3, "SB_BLUE")
    c.fill_rect(1, 27, 30, 1, "SB_ELECTRIC")
    c.fill_rect(1, 29, 30, 1, "SB_PANEL")
    # Lower wainscoting
    c.fill_rect(1, 30, 30, 11, "IVORY_M")
    c.fill_rect(3, 32, 26, 7, "IVORY_B")
    c.fill_rect(3, 32, 26, 1, "IVORY_H")
    # Stone baseboard
    c.fill_rect(1, 41, 30, 5, "STONE_D")
    c.fill_rect(1, 41, 30, 1, "IVORY_D")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_wall_glass_facade() -> PixelCanvas:
    c = PixelCanvas(32, 48)
    # Outer steel mullion frame
    c.fill_rect(1, 2, 30, 44, "SB_SLATE")
    c.fill_rect(1, 2, 30, 2, "SB_STEEL")
    # Glass pane
    c.fill_rect(3, 6, 26, 34, "GLASS_D")
    # Vertical center mullion + transom
    c.fill_rect(15, 6, 2, 34, "SB_SLATE")
    c.fill_rect(15, 6, 1, 34, "SB_STEEL")
    c.fill_rect(3, 18, 26, 2, "SB_SLATE")
    c.fill_rect(3, 18, 26, 1, "SB_STEEL")
    # Crisp diagonal sky sheen (binary alpha)
    for d in range(10):
        c.set_px(5 + d, 16 - d, "SB_ELECTRIC")
        c.set_px(6 + d, 16 - d, "SB_ICE")
        c.set_px(18 + d, 32 - d, "SB_ELECTRIC")
        c.set_px(19 + d, 32 - d, "SB_ICE")
    # Lower sill & baseboard
    c.fill_rect(1, 40, 30, 6, "STONE_D")
    c.fill_rect(1, 40, 30, 1, "SB_STEEL")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_wall_logo_backdrop() -> PixelCanvas:
    c = PixelCanvas(64, 48)
    # Base marble wall
    c.fill_rect(1, 2, 62, 44, "IVORY_B")
    c.fill_rect(1, 2, 62, 4, "SB_SLATE")
    c.fill_rect(1, 2, 62, 1, "SB_STEEL")
    c.fill_rect(1, 27, 62, 3, "SB_BLUE")
    c.fill_rect(1, 41, 62, 5, "STONE_D")

    # Twin fluted marble pillars with gold capitals
    for px in (4, 52):
        c.fill_rect(px, 6, 8, 35, "IVORY_M")
        c.fill_rect(px + 1, 6, 5, 35, "IVORY_B")
        c.fill_rect(px + 1, 6, 2, 35, "IVORY_H")
        c.fill_rect(px + 3, 10, 1, 28, "IVORY_D")
        c.fill_rect(px + 5, 10, 1, 28, "IVORY_D")
        # Gold capital & base
        c.fill_rect(px - 1, 6, 10, 3, "GOLD_B")
        c.fill_rect(px - 1, 6, 10, 1, "GOLD_H")
        c.fill_rect(px - 1, 38, 10, 3, "GOLD_M")

    # Central Starway plaque (ZERO text: pure 3-pillar + 4-point cyan/gold star emblem)
    c.fill_rect(15, 9, 34, 24, "GOLD_M")
    c.fill_rect(16, 10, 32, 22, "SB_PANEL")
    c.stroke_rect(17, 11, 30, 20, "SB_BLUE")
    # 3 abstract classical pillars inside plaque
    for bx in (23, 30, 37):
        c.fill_rect(bx, 18, 4, 9, "SB_ICE")
        c.fill_rect(bx + 2, 18, 2, 9, "SB_ELECTRIC")
    c.fill_rect(21, 27, 22, 2, "GOLD_B")
    # 4-point Starway cyan/gold star above pillars
    cx, cy = 32, 14
    c.fill_rect(cx - 1, cy - 3, 2, 7, "SB_CYAN")
    c.fill_rect(cx - 4, cy, 8, 1, "SB_CYAN")
    c.fill_rect(cx - 1, cy - 1, 2, 3, "GOLD_H")
    c.set_px(cx, cy, "SB_WHITE")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_fountain_sheet() -> PixelCanvas:
    sheet = PixelCanvas(192, 48)
    for frame in range(4):
        cell = PixelCanvas(48, 48)
        # Octagonal basin outer rim
        cell.fill_ellipse(24, 31, 18.0, 10.5, "IVORY_M")
        cell.fill_ellipse(24, 29, 17.5, 9.8, "IVORY_H")
        cell.fill_ellipse(24, 29, 15.0, 8.0, "SB_PANEL")
        cell.fill_ellipse(24, 29, 14.0, 7.2, "SB_BLUE")

        # Animated concentric water ripples
        r1 = 5.5 + (frame * 2.2) % 8.0
        r2 = 5.5 + ((frame + 2) * 2.2) % 8.0
        for rx, key in ((r1, "SB_ELECTRIC"), (r2, "SB_ICE")):
            ry = rx * 0.52
            for deg_step in range(36):
                ang = deg_step * (2.0 * math.pi / 36.0)
                px = int(round(24 + rx * math.cos(ang)))
                py = int(round(29 + ry * math.sin(ang)))
                if 9 <= px <= 38 and 22 <= py <= 35:
                    cell.set_px(px, py, key)

        # Central glowing Starway pillar
        cell.fill_rect(21, 15, 6, 15, "IVORY_B")
        cell.fill_rect(21, 15, 2, 15, "IVORY_H")
        cell.fill_rect(25, 15, 2, 15, "IVORY_D")
        cell.fill_rect(20, 14, 8, 2, "GOLD_B")
        # Glowing cyan star crystal on top (pulses frame by frame)
        crystal_key = ("SB_CYAN", "SB_ICE", "SB_WHITE", "SB_ICE")[frame]
        cell.fill_rect(23, 8, 2, 6, crystal_key)
        cell.fill_rect(21, 10, 6, 2, "SB_CYAN")
        cell.set_px(24, 10, "SB_WHITE")

        # Animated water fountain arcs left & right
        arc_offsets = [
            [(18, 17), (16, 20), (15, 24), (14, 27)],
            [(19, 16), (16, 18), (14, 22), (13, 26)],
            [(20, 15), (17, 17), (15, 20), (14, 25)],
            [(19, 17), (17, 21), (16, 25), (15, 28)],
        ][frame]
        for ax, ay in arc_offsets:
            cell.set_px(ax, ay, "SB_ICE")
            cell.set_px(ax + 1, ay + 1, "SB_CYAN")
            mirror_x = 47 - ax
            cell.set_px(mirror_x, ay, "SB_ICE")
            cell.set_px(mirror_x - 1, ay + 1, "SB_CYAN")

        cell.apply_outline("OUTLINE_WARM")
        sheet.blit_from(cell, frame * 48, 0)
    return sheet


def gen_prop_counter_teller() -> PixelCanvas:
    c = PixelCanvas(48, 36)
    # Warm wood counter body
    c.fill_rect(3, 14, 42, 18, "WOOD_B")
    c.fill_rect(3, 26, 42, 6, "WOOD_M")
    c.fill_rect(3, 30, 42, 2, "WOOD_D")
    # Tech-blue stripe across front
    c.fill_rect(3, 18, 42, 4, "SB_BLUE")
    c.fill_rect(3, 18, 42, 1, "SB_ELECTRIC")
    # Ivory marble top ledge
    c.fill_rect(2, 11, 44, 4, "IVORY_B")
    c.fill_rect(2, 11, 44, 1, "IVORY_H")
    c.fill_rect(2, 14, 44, 1, "IVORY_D")
    # Glass transaction shield posts + dual cyan monitors
    for mx in (9, 31):
        c.fill_rect(mx, 4, 8, 7, "SB_PANEL")
        c.fill_rect(mx + 1, 5, 6, 4, "SB_CYAN")
        c.fill_rect(mx + 1, 5, 2, 1, "SB_ICE")
        c.fill_rect(mx + 3, 10, 2, 2, "SB_STEEL")
    # Glass divider frame
    c.fill_rect(20, 4, 8, 7, "SB_STEEL")
    c.fill_rect(21, 5, 6, 5, "GLASS_D")
    c.draw_line(21, 8, 24, 5, "SB_ICE")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_desk_loan() -> PixelCanvas:
    c = PixelCanvas(40, 32)
    # Rear consultation chair
    c.fill_rect(15, 4, 10, 7, "SB_SLATE")
    c.fill_rect(16, 4, 8, 2, "SB_STEEL")
    # Rich wood desk
    c.fill_rect(3, 11, 34, 13, "WOOD_B")
    c.fill_rect(3, 11, 34, 2, "WOOD_H")
    c.fill_rect(3, 20, 34, 4, "WOOD_M")
    c.fill_rect(5, 24, 4, 5, "WOOD_D")
    c.fill_rect(31, 24, 4, 5, "WOOD_D")
    # Banker lamp on left (gold shade)
    c.fill_rect(6, 7, 5, 3, "GOLD_B")
    c.fill_rect(6, 7, 3, 1, "GOLD_H")
    c.fill_rect(8, 10, 1, 2, "GOLD_D")
    # Cyan monitor center-right + ivory loan papers
    c.fill_rect(19, 6, 8, 6, "SB_PANEL")
    c.fill_rect(20, 7, 6, 4, "SB_CYAN")
    c.fill_rect(12, 12, 5, 3, "IVORY_H")
    c.fill_rect(13, 13, 3, 1, "GOLD_M")
    # Visitor chair front
    c.fill_rect(16, 22, 8, 6, "SB_SLATE")
    c.fill_rect(17, 22, 6, 2, "SB_BLUE")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_desk_office() -> PixelCanvas:
    c = PixelCanvas(36, 30)
    # Ergonomic blue chair behind
    c.fill_rect(13, 4, 10, 7, "SB_BLUE")
    c.fill_rect(14, 4, 8, 2, "SB_ELECTRIC")
    # Workstation desk
    c.fill_rect(3, 11, 30, 8, "WOOD_B")
    c.fill_rect(3, 11, 30, 2, "WOOD_H")
    c.fill_rect(3, 17, 30, 2, "WOOD_M")
    c.fill_rect(5, 19, 3, 8, "SB_SLATE")
    c.fill_rect(28, 19, 3, 8, "SB_SLATE")
    # Monitor + keyboard
    c.fill_rect(13, 7, 10, 6, "SB_PANEL")
    c.fill_rect(14, 8, 8, 4, "SB_CYAN")
    c.fill_rect(14, 14, 8, 2, "SB_STEEL")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_sofa() -> PixelCanvas:
    c = PixelCanvas(40, 28)
    # Backrest
    c.fill_rect(4, 5, 32, 11, "SB_SLATE")
    c.fill_rect(5, 6, 30, 8, "SB_BLUE")
    c.fill_rect(5, 6, 30, 2, "SB_ELECTRIC")
    # Seat cushions
    c.fill_rect(5, 14, 14, 7, "SB_BLUE")
    c.fill_rect(21, 14, 14, 7, "SB_BLUE")
    c.fill_rect(6, 14, 12, 2, "SB_ICE")
    c.fill_rect(22, 14, 12, 2, "SB_ICE")
    # Wood armrests & legs
    c.fill_rect(2, 10, 4, 11, "WOOD_M")
    c.fill_rect(2, 10, 4, 2, "WOOD_H")
    c.fill_rect(34, 10, 4, 11, "WOOD_M")
    c.fill_rect(34, 10, 4, 2, "WOOD_H")
    c.fill_rect(4, 21, 3, 4, "WOOD_D")
    c.fill_rect(33, 21, 3, 4, "WOOD_D")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_plant() -> PixelCanvas:
    c = PixelCanvas(24, 32)
    # Lush clustered pixel leaves
    c.fill_ellipse(12, 12, 7.0, 6.5, "GREEN_D")
    c.fill_ellipse(9, 10, 4.5, 4.0, "GREEN_B")
    c.fill_ellipse(14, 11, 4.5, 4.0, "GREEN_B")
    c.fill_ellipse(11, 7, 3.8, 3.0, "GREEN_H")
    c.fill_ellipse(8, 9, 2.2, 2.0, "GREEN_H")
    # Trunk & pot
    c.fill_rect(11, 16, 2, 5, "WOOD_M")
    c.fill_rect(6, 20, 12, 2, "GOLD_M")
    c.fill_rect(7, 22, 10, 7, "IVORY_M")
    c.fill_rect(7, 22, 4, 7, "IVORY_B")
    c.fill_rect(8, 28, 8, 1, "IVORY_D")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_atm() -> PixelCanvas:
    c = PixelCanvas(24, 36)
    # Upright kiosk chassis
    c.fill_rect(5, 4, 14, 28, "SB_STEEL")
    c.fill_rect(6, 5, 12, 26, "SB_PANEL")
    c.fill_rect(6, 5, 12, 2, "SB_BLUE")
    # Glowing cyan screen (abstract 3x3 pixel UI bars, NO text)
    c.fill_rect(8, 9, 8, 7, "SB_CYAN")
    c.fill_rect(9, 10, 4, 1, "SB_WHITE")
    c.fill_rect(9, 12, 6, 1, "SB_ICE")
    c.fill_rect(9, 14, 3, 1, "SB_ICE")
    # Gold card slot & keypad cluster
    c.fill_rect(8, 18, 5, 3, "SB_SLATE")
    c.fill_rect(14, 18, 3, 2, "GOLD_B")
    c.fill_rect(8, 23, 8, 2, "SB_NAVY")
    c.fill_rect(5, 30, 14, 3, "SB_SLATE")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_prop_coffee_bar() -> PixelCanvas:
    c = PixelCanvas(36, 32)
    # Warm wood bar cabinet
    c.fill_rect(3, 14, 30, 14, "WOOD_B")
    c.fill_rect(3, 24, 30, 4, "WOOD_M")
    c.fill_rect(3, 27, 30, 2, "WOOD_D")
    # Starway tech-blue trim band
    c.fill_rect(3, 17, 30, 3, "SB_BLUE")
    c.fill_rect(3, 17, 30, 1, "SB_ELECTRIC")
    # Ivory marble countertop
    c.fill_rect(2, 12, 32, 3, "IVORY_B")
    c.fill_rect(2, 12, 32, 1, "IVORY_H")
    # Espresso machine on left
    c.fill_rect(6, 5, 11, 7, "SB_STEEL")
    c.fill_rect(7, 6, 9, 5, "SB_SLATE")
    c.fill_rect(8, 7, 3, 2, "SB_CYAN")
    c.fill_rect(12, 7, 3, 1, "GOLD_H")
    # Coffee cups + steam on right
    c.fill_rect(21, 9, 4, 3, "IVORY_H")
    c.fill_rect(27, 9, 4, 3, "GOLD_B")
    c.set_px(22, 7, "SB_ICE")
    c.set_px(23, 6, "SB_WHITE")
    c.set_px(28, 7, "SB_ICE")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_aquarium() -> PixelCanvas:
    c = PixelCanvas(40, 36)
    # Sleek slate cabinet base
    c.fill_rect(3, 22, 34, 11, "SB_SLATE")
    c.fill_rect(4, 23, 32, 8, "SB_PANEL")
    c.fill_rect(4, 23, 32, 1, "SB_STEEL")
    # Illuminated glass tank
    c.fill_rect(3, 5, 34, 17, "SB_STEEL")
    c.fill_rect(5, 7, 30, 13, "SB_BLUE")
    c.fill_rect(5, 7, 30, 3, "SB_ELECTRIC")
    # Seaweed & coral
    c.fill_rect(8, 15, 2, 5, "GREEN_B")
    c.fill_rect(10, 16, 2, 4, "GREEN_H")
    c.fill_rect(28, 15, 3, 5, "GREEN_D")
    c.fill_rect(29, 14, 2, 4, "GREEN_H")
    # Golden fish & glowing cyan bubbles
    c.fill_rect(14, 11, 4, 2, "GOLD_H")
    c.set_px(13, 12, "GOLD_M")
    c.fill_rect(22, 14, 4, 2, "GOLD_B")
    c.set_px(26, 15, "GOLD_H")
    c.set_px(18, 9, "SB_ICE")
    c.set_px(19, 11, "SB_WHITE")
    c.set_px(25, 9, "SB_ICE")
    # Top light bar
    c.fill_rect(5, 4, 30, 2, "SB_CYAN")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_prop_gold_bull() -> PixelCanvas:
    c = PixelCanvas(32, 32)
    # Ivory marble pedestal with navy trim
    c.fill_rect(5, 22, 22, 7, "IVORY_M")
    c.fill_rect(6, 22, 20, 2, "IVORY_H")
    c.fill_rect(7, 25, 18, 2, "SB_BLUE")
    c.fill_rect(4, 28, 24, 2, "SB_SLATE")
    # Charging golden bull silhouette
    c.fill_rect(9, 12, 14, 7, "GOLD_B")
    c.fill_rect(10, 11, 10, 3, "GOLD_H")
    c.fill_rect(11, 17, 11, 2, "GOLD_M")
    # Head & horns (right-facing)
    c.fill_rect(21, 10, 5, 5, "GOLD_B")
    c.fill_rect(22, 10, 3, 2, "GOLD_H")
    c.set_px(25, 8, "GOLD_H")
    c.set_px(26, 9, "GOLD_H")
    # Legs & tail
    c.fill_rect(10, 19, 2, 3, "GOLD_D")
    c.fill_rect(14, 19, 2, 3, "GOLD_M")
    c.fill_rect(20, 19, 2, 3, "GOLD_D")
    c.fill_rect(7, 13, 2, 2, "GOLD_M")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_bookshelf() -> PixelCanvas:
    c = PixelCanvas(32, 36)
    # Warm wood bookcase frame
    c.fill_rect(4, 4, 24, 28, "WOOD_M")
    c.fill_rect(5, 5, 22, 26, "WOOD_D")
    c.fill_rect(4, 4, 24, 2, "WOOD_H")
    # 3 shelves with colorful financial brochures/books
    for sy in (11, 18, 25):
        c.fill_rect(5, sy, 22, 2, "WOOD_B")
        c.fill_rect(5, sy, 22, 1, "WOOD_H")
    # Row 1 books
    c.fill_rect(7, 6, 3, 5, "SB_BLUE")
    c.fill_rect(11, 7, 3, 4, "GOLD_B")
    c.fill_rect(15, 6, 3, 5, "SB_CYAN")
    c.fill_rect(19, 7, 4, 4, "IVORY_H")
    # Row 2 books
    c.fill_rect(7, 13, 4, 5, "GREEN_B")
    c.fill_rect(12, 14, 3, 4, "SB_ELECTRIC")
    c.fill_rect(16, 13, 3, 5, "GOLD_H")
    c.fill_rect(20, 14, 4, 4, "SB_BLUE")
    # Row 3 binders
    c.fill_rect(7, 20, 5, 5, "SB_PANEL")
    c.fill_rect(13, 20, 5, 5, "IVORY_B")
    c.fill_rect(19, 20, 5, 5, "GOLD_M")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_vault_door() -> PixelCanvas:
    c = PixelCanvas(40, 48)
    # Heavy reinforced frame
    c.fill_rect(3, 3, 34, 42, "SB_SLATE")
    c.fill_rect(4, 4, 32, 40, "SB_STEEL")
    c.fill_rect(4, 4, 32, 2, "SB_ICE")
    # Circular steel vault door
    c.fill_ellipse(20, 24, 12.0, 12.0, "SB_PANEL")
    c.fill_ellipse(20, 24, 10.5, 10.5, "SB_STEEL")
    c.fill_ellipse(19, 23, 8.5, 8.5, "SB_SLATE")
    # Gold spoked wheel
    c.fill_ellipse(20, 24, 5.0, 5.0, "GOLD_M")
    c.fill_ellipse(20, 24, 3.5, 3.5, "GOLD_B")
    c.draw_line(14, 24, 26, 24, "GOLD_H")
    c.draw_line(20, 18, 20, 30, "GOLD_H")
    c.fill_rect(19, 23, 2, 2, "SB_CYAN")
    # Hinges on left
    c.fill_rect(5, 12, 3, 5, "GOLD_M")
    c.fill_rect(5, 31, 3, 5, "GOLD_M")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_prop_queue_post() -> PixelCanvas:
    c = PixelCanvas(16, 24)
    # Brass base + post + finial
    c.fill_rect(5, 19, 6, 3, "GOLD_M")
    c.fill_rect(6, 18, 4, 1, "GOLD_B")
    c.fill_rect(7, 7, 2, 12, "GOLD_B")
    c.fill_rect(7, 7, 1, 11, "GOLD_H")
    c.fill_rect(6, 5, 4, 2, "GOLD_H")
    # Draped Starway blue velvet cord segment
    c.draw_line(9, 9, 14, 12, "SB_BLUE")
    c.draw_line(9, 10, 14, 13, "SB_ELECTRIC")
    c.apply_outline("OUTLINE_WARM")
    return c


def gen_prop_dept_banner() -> PixelCanvas:
    c = PixelCanvas(24, 36)
    # Steel pole & base
    c.fill_rect(8, 30, 8, 3, "SB_SLATE")
    c.fill_rect(11, 4, 2, 27, "SB_STEEL")
    c.fill_rect(10, 3, 4, 2, "GOLD_B")
    # Pennant with gold trim & abstract cyan diamond crest (ZERO text)
    c.fill_rect(5, 6, 14, 18, "SB_PANEL")
    c.fill_polygon_scanline([(5, 24), (12, 28), (18, 24)], "SB_PANEL")
    c.stroke_rect(6, 7, 12, 16, "GOLD_B")
    c.fill_rect(8, 9, 8, 12, "SB_BLUE")
    # Diamond crest
    c.fill_polygon_scanline([(12, 10), (15, 14), (12, 18), (9, 14)], "SB_CYAN")
    c.fill_rect(11, 13, 2, 2, "SB_WHITE")
    c.apply_outline("OUTLINE_TECH")
    return c


# ---------------------------------------------------------------------------
# 2. CHARACTER SPRITE SHEETS (12 x 96x128) & PORTRAITS (12 x 32x32)
# ---------------------------------------------------------------------------

CHARACTER_SPECS: list[dict[str, str]] = [
    # 6 Employees
    {
        "id": "emp_teller_m",
        "skin": "SKIN_L_B", "skin_d": "SKIN_L_D",
        "hair": "HAIR_DARK", "hair_h": "HAIR_DARK_H", "hair_style": "short",
        "torso": "SB_BLUE", "torso_h": "SB_ELECTRIC", "shirt": "SB_WHITE",
        "accent": "SB_CYAN", "legs": "SB_NAVY", "prop": "none", "glasses": "none", "hat": "none",
    },
    {
        "id": "emp_teller_f",
        "skin": "SKIN_L_B", "skin_d": "SKIN_L_D",
        "hair": "HAIR_BROWN", "hair_h": "HAIR_BROWN_H", "hair_style": "bob",
        "torso": "SB_BLUE", "torso_h": "SB_ELECTRIC", "shirt": "SB_WHITE",
        "accent": "GOLD_B", "legs": "SB_NAVY", "prop": "pin", "glasses": "none", "hat": "none",
    },
    {
        "id": "emp_credit",
        "skin": "SKIN_M_B", "skin_d": "SKIN_M_D",
        "hair": "HAIR_BROWN", "hair_h": "HAIR_BROWN_H", "hair_style": "parted",
        "torso": "SB_PANEL", "torso_h": "SB_BLUE", "shirt": "SB_WHITE",
        "accent": "GOLD_B", "legs": "SB_NAVY", "prop": "folder_gold", "glasses": "sb_ice", "hat": "none",
    },
    {
        "id": "emp_hr",
        "skin": "SKIN_L_B", "skin_d": "SKIN_L_D",
        "hair": "HAIR_BLONDE", "hair_h": "HAIR_BLONDE_H", "hair_style": "wavy",
        "torso": "SB_ELECTRIC", "torso_h": "SB_ICE", "shirt": "SB_WHITE",
        "accent": "GREEN_B", "legs": "SB_SLATE", "prop": "badge_green", "glasses": "none", "hat": "none",
    },
    {
        "id": "emp_risk",
        "skin": "SKIN_M_B", "skin_d": "SKIN_M_D",
        "hair": "HAIR_DARK", "hair_h": "HAIR_DARK_H", "hair_style": "sharp",
        "torso": "SB_SLATE", "torso_h": "SB_STEEL", "shirt": "SB_ICE",
        "accent": "VIOLET_B", "legs": "SB_NAVY", "prop": "tablet_violet", "glasses": "rect", "hat": "none",
    },
    {
        "id": "emp_ops",
        "skin": "SKIN_T_B", "skin_d": "SKIN_T_D",
        "hair": "HAIR_GREY", "hair_h": "HAIR_GREY_H", "hair_style": "exec",
        "torso": "SB_NAVY", "torso_h": "SB_PANEL", "shirt": "SB_WHITE",
        "accent": "GOLD_B", "legs": "SB_NAVY", "prop": "headset", "glasses": "none", "hat": "none",
    },
    # 6 Customers
    {
        "id": "cust_regular",
        "skin": "SKIN_L_B", "skin_d": "SKIN_L_D",
        "hair": "HAIR_BROWN", "hair_h": "HAIR_BROWN_H", "hair_style": "short",
        "torso": "SAGE_B", "torso_h": "GREEN_H", "shirt": "IVORY_B",
        "accent": "SAGE_D", "legs": "SB_SLATE", "prop": "none", "glasses": "none", "hat": "none",
    },
    {
        "id": "cust_salaried",
        "skin": "SKIN_M_B", "skin_d": "SKIN_M_D",
        "hair": "HAIR_DARK", "hair_h": "HAIR_DARK_H", "hair_style": "parted",
        "torso": "SB_ICE", "torso_h": "SB_WHITE", "shirt": "SB_WHITE",
        "accent": "SB_PANEL", "legs": "SB_SLATE", "prop": "strap", "glasses": "none", "hat": "none",
    },
    {
        "id": "cust_borrower",
        "skin": "SKIN_L_B", "skin_d": "SKIN_L_D",
        "hair": "HAIR_BLONDE", "hair_h": "HAIR_BLONDE_H", "hair_style": "tousled",
        "torso": "WOOD_B", "torso_h": "WOOD_H", "shirt": "IVORY_B",
        "accent": "GOLD_M", "legs": "SB_SLATE", "prop": "folder_ivory", "glasses": "none", "hat": "none",
    },
    {
        "id": "cust_smb",
        "skin": "SKIN_T_B", "skin_d": "SKIN_T_D",
        "hair": "HAIR_DARK", "hair_h": "HAIR_DARK_H", "hair_style": "short",
        "torso": "WOOD_D", "torso_h": "WOOD_M", "shirt": "IVORY_H",
        "accent": "GOLD_B", "legs": "SB_NAVY", "prop": "briefcase", "glasses": "none", "hat": "none",
    },
    {
        "id": "cust_vip",
        "skin": "SKIN_L_B", "skin_d": "SKIN_L_D",
        "hair": "HAIR_GREY", "hair_h": "HAIR_GREY_H", "hair_style": "exec",
        "torso": "SB_PANEL", "torso_h": "SB_SLATE", "shirt": "SB_WHITE",
        "accent": "VIP_CRIMSON", "legs": "SB_NAVY", "prop": "vip_lapel", "glasses": "none", "hat": "none",
    },
    {
        "id": "cust_suspicious",
        "skin": "SKIN_M_B", "skin_d": "SKIN_M_D",
        "hair": "HAIR_DARK", "hair_h": "HAIR_DARK_H", "hair_style": "short",
        "torso": "SB_NAVY", "torso_h": "SB_SLATE", "shirt": "SB_SLATE",
        "accent": "OUTLINE_TECH", "legs": "SB_NAVY", "prop": "trench", "glasses": "shades", "hat": "fedora",
    },
]


def _draw_char_cell(spec: dict[str, str], row: int, col: int) -> PixelCanvas:
    """Draw a 24x32 character cell with foot anchor at (12, 30)."""
    c = PixelCanvas(24, 32)
    # Row 0: Idle, Row 1: Walk, Row 2: Work, Row 3: Talk
    dy_body = 0
    if row == 0:
        dy_body = -1 if col in (1, 2) else 0
    elif row == 1:
        dy_body = -1 if col in (0, 2) else 0
    elif row == 2:
        dy_body = 1 if col in (1, 3) else 0
    elif row == 3:
        dy_body = -1 if col in (1, 3) else 0

    head_y = 6 + dy_body
    torso_y = 15 + dy_body

    # Legs / feet grounded at y=28..29 (so outline hits y=30 at x=9..14)
    if row == 1:
        if col == 0:
            # Left forward, right back
            c.fill_rect(9, 24, 2, 5, spec["legs"])
            c.fill_rect(13, 24, 2, 4, spec["legs"])
            c.fill_rect(8, 28, 3, 2, "OUTLINE_WARM")
            c.fill_rect(13, 27, 3, 2, "SB_NAVY")
        elif col == 2:
            # Right forward, left back
            c.fill_rect(9, 24, 2, 4, spec["legs"])
            c.fill_rect(13, 24, 2, 5, spec["legs"])
            c.fill_rect(8, 27, 3, 2, "SB_NAVY")
            c.fill_rect(13, 28, 3, 2, "OUTLINE_WARM")
        else:
            c.fill_rect(9, 24, 2, 5, spec["legs"])
            c.fill_rect(13, 24, 2, 5, spec["legs"])
            c.fill_rect(9, 28, 2, 2, "SB_NAVY")
            c.fill_rect(13, 28, 2, 2, "SB_NAVY")
    else:
        c.fill_rect(9, 24, 2, 5, spec["legs"])
        c.fill_rect(13, 24, 2, 5, spec["legs"])
        c.fill_rect(9, 28, 2, 2, "SB_NAVY")
        c.fill_rect(13, 28, 2, 2, "SB_NAVY")

    # Torso
    c.fill_rect(8, torso_y, 8, 9, spec["torso"])
    c.fill_rect(8, torso_y, 3, 8, spec["torso_h"])
    # Shirt collar & tie/accent
    c.fill_rect(10, torso_y, 4, 3, spec["shirt"])
    c.fill_rect(11, torso_y + 1, 2, 5, spec["accent"])

    # Special torso props
    if spec["prop"] == "pin":
        c.set_px(9, torso_y + 2, "GOLD_B")
    elif spec["prop"] == "badge_green":
        c.fill_rect(13, torso_y + 3, 2, 2, "GREEN_B")
    elif spec["prop"] == "strap":
        c.draw_line(8, torso_y, 14, torso_y + 7, "SB_NAVY")
    elif spec["prop"] == "vip_lapel":
        c.set_px(9, torso_y + 2, "GOLD_B")
        c.fill_rect(11, torso_y + 1, 2, 4, "VIP_CRIMSON")
    elif spec["prop"] == "trench":
        c.fill_rect(8, torso_y - 1, 8, 2, "SB_SLATE")

    # Arms (vary per animation row & col)
    if row == 1:
        l_arm_dy = -1 if col == 2 else (1 if col == 0 else 0)
        r_arm_dy = -1 if col == 0 else (1 if col == 2 else 0)
        c.fill_rect(6, torso_y + 1 + l_arm_dy, 2, 6, spec["torso"])
        c.fill_rect(6, torso_y + 6 + l_arm_dy, 2, 2, spec["skin"])
        c.fill_rect(16, torso_y + 1 + r_arm_dy, 2, 6, spec["torso"])
        c.fill_rect(16, torso_y + 6 + r_arm_dy, 2, 2, spec["skin"])
    elif row == 2:
        # Work: hands raised typing/inspecting
        l_up = 1 if col in (0, 2) else 0
        r_up = 1 if col in (1, 3) else 0
        c.fill_rect(6, torso_y + 1, 2, 4, spec["torso"])
        c.fill_rect(7, torso_y + 3 - l_up, 2, 2, spec["skin"])
        c.fill_rect(16, torso_y + 1, 2, 4, spec["torso"])
        c.fill_rect(15, torso_y + 3 - r_up, 2, 2, spec["skin"])
        if spec["prop"] == "folder_gold":
            c.fill_rect(9, torso_y + 4, 6, 4, "GOLD_B")
        elif spec["prop"] == "tablet_violet":
            c.fill_rect(9, torso_y + 4, 6, 4, "VIOLET_B")
            c.fill_rect(10, torso_y + 5, 4, 2, "SB_CYAN")
    elif row == 3:
        # Talk: right arm gestures outward on col 1 & 3
        c.fill_rect(6, torso_y + 1, 2, 6, spec["torso"])
        c.fill_rect(6, torso_y + 6, 2, 2, spec["skin"])
        if col in (1, 3):
            c.fill_rect(16, torso_y + 1, 3, 2, spec["torso"])
            c.fill_rect(18, torso_y, 2, 2, spec["skin"])
        else:
            c.fill_rect(16, torso_y + 1, 2, 6, spec["torso"])
            c.fill_rect(16, torso_y + 6, 2, 2, spec["skin"])
    else:
        # Idle
        c.fill_rect(6, torso_y + 1, 2, 6, spec["torso"])
        c.fill_rect(6, torso_y + 6, 2, 2, spec["skin"])
        c.fill_rect(16, torso_y + 1, 2, 6, spec["torso"])
        c.fill_rect(16, torso_y + 6, 2, 2, spec["skin"])

    # Handheld briefcase / folder in Idle/Walk/Talk
    if row != 2:
        if spec["prop"] == "briefcase":
            c.fill_rect(16, torso_y + 7, 4, 4, "WOOD_M")
            c.set_px(17, torso_y + 8, "GOLD_B")
        elif spec["prop"] == "folder_ivory":
            c.fill_rect(5, torso_y + 5, 3, 4, "IVORY_H")

    # Head
    c.fill_rect(8, head_y, 8, 9, spec["skin"])
    c.fill_rect(13, head_y + 2, 3, 6, spec["skin_d"])
    # Eyes
    if spec["glasses"] == "shades":
        c.fill_rect(9, head_y + 4, 3, 2, "OUTLINE_TECH")
        c.fill_rect(13, head_y + 4, 3, 2, "OUTLINE_TECH")
        c.set_px(9, head_y + 4, "SB_STEEL")
    else:
        c.set_px(10, head_y + 5, "OUTLINE_WARM")
        c.set_px(14, head_y + 5, "OUTLINE_WARM")
        if spec["glasses"] in ("sb_ice", "rect"):
            glint = "SB_ICE" if spec["glasses"] == "sb_ice" else "SB_STEEL"
            c.set_px(9, head_y + 4, glint)
            c.set_px(10, head_y + 4, glint)
            c.set_px(13, head_y + 4, glint)
            c.set_px(14, head_y + 4, glint)

    # Mouth open pixel in Talk frames col 1 & 3
    if row == 3 and col in (1, 3):
        c.set_px(12, head_y + 7, "RED_D")

    # Hair
    hair = spec["hair"]
    hair_h = spec["hair_h"]
    style = spec["hair_style"]
    c.fill_rect(8, head_y - 1, 8, 3, hair)
    c.fill_rect(9, head_y - 1, 4, 1, hair_h)
    if style in ("bob", "wavy"):
        c.fill_rect(7, head_y, 1, 7, hair)
        c.fill_rect(16, head_y, 1, 7, hair)
    elif style == "parted":
        c.fill_rect(7, head_y, 1, 3, hair)
        c.set_px(13, head_y + 1, spec["skin"])
    elif style in ("sharp", "tousled"):
        c.set_px(8, head_y - 2, hair)
        c.set_px(11, head_y - 2, hair_h)
        c.set_px(14, head_y - 2, hair)
    elif style == "exec":
        c.fill_rect(7, head_y + 1, 1, 3, hair)
        c.fill_rect(16, head_y + 1, 1, 3, hair)

    # Headset / Fedora
    if spec["prop"] == "headset":
        c.fill_rect(7, head_y + 3, 1, 3, "SB_CYAN")
        c.set_px(8, head_y + 6, "SB_CYAN")
    if spec["hat"] == "fedora":
        c.fill_rect(6, head_y + 1, 12, 1, "SB_SLATE")
        c.fill_rect(8, head_y - 2, 8, 3, "SB_SLATE")
        c.fill_rect(8, head_y, 8, 1, "SB_NAVY")

    # 1px warm outline bounded strictly inside x=1..22, y=1..30 (keeps y=0 and x=0,23 clear!)
    c.apply_outline("OUTLINE_WARM", x0=0, y0=0, x1=24, y1=32)
    return c


def gen_character_sheet(spec: dict[str, str]) -> PixelCanvas:
    sheet = PixelCanvas(96, 128)
    for row in range(4):
        for col in range(4):
            cell = _draw_char_cell(spec, row, col)
            sheet.blit_from(cell, col * 24, row * 32)
    return sheet


def gen_character_portrait(spec: dict[str, str]) -> PixelCanvas:
    c = PixelCanvas(32, 32)
    # Shoulders down to y=31
    c.fill_rect(6, 22, 20, 10, spec["torso"])
    c.fill_rect(6, 22, 7, 10, spec["torso_h"])
    c.fill_rect(12, 22, 8, 10, spec["shirt"])
    c.fill_rect(15, 23, 2, 9, spec["accent"])
    if spec["prop"] == "vip_lapel":
        c.set_px(9, 25, "GOLD_B")
        c.fill_rect(14, 23, 4, 8, "VIP_CRIMSON")
    # Neck
    c.fill_rect(13, 19, 6, 4, spec["skin_d"])
    # Face
    c.fill_rect(9, 7, 14, 13, spec["skin"])
    c.fill_rect(19, 9, 4, 10, spec["skin_d"])
    # Eyes
    if spec["glasses"] == "shades":
        c.fill_rect(10, 12, 5, 3, "OUTLINE_TECH")
        c.fill_rect(17, 12, 5, 3, "OUTLINE_TECH")
        c.set_px(11, 12, "SB_STEEL")
        c.set_px(18, 12, "SB_STEEL")
    else:
        c.fill_rect(11, 13, 2, 2, "OUTLINE_WARM")
        c.fill_rect(19, 13, 2, 2, "OUTLINE_WARM")
        if spec["glasses"] in ("sb_ice", "rect"):
            glint = "SB_ICE" if spec["glasses"] == "sb_ice" else "SB_STEEL"
            c.stroke_rect(10, 12, 4, 4, glint)
            c.stroke_rect(18, 12, 4, 4, glint)
    # Smile
    c.fill_rect(14, 17, 4, 1, spec["skin_d"])
    # Hair
    hair = spec["hair"]
    hair_h = spec["hair_h"]
    c.fill_rect(8, 4, 16, 5, hair)
    c.fill_rect(10, 4, 8, 2, hair_h)
    if spec["hair_style"] in ("bob", "wavy"):
        c.fill_rect(7, 7, 2, 13, hair)
        c.fill_rect(23, 7, 2, 13, hair)
    else:
        c.fill_rect(8, 7, 2, 5, hair)
        c.fill_rect(22, 7, 2, 5, hair)
    if spec["prop"] == "headset":
        c.fill_rect(7, 11, 2, 5, "SB_CYAN")
        c.draw_line(8, 16, 13, 18, "SB_CYAN")
    if spec["hat"] == "fedora":
        c.fill_rect(5, 8, 22, 2, "SB_SLATE")
        c.fill_rect(8, 3, 16, 5, "SB_SLATE")
        c.fill_rect(8, 7, 16, 1, "SB_NAVY")
    c.apply_outline("OUTLINE_WARM", skip_bottom_row=True)
    return c


# ---------------------------------------------------------------------------
# 3. ICONS (19 files: 9 @ 24x24 + 10 @ 16x16) — ZERO BAKED TEXT/NUMBERS
# ---------------------------------------------------------------------------

def gen_icon_overview() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    c.fill_rect(3, 3, 8, 8, "SB_CYAN")
    c.fill_rect(4, 4, 3, 2, "IVORY_H")
    c.fill_rect(13, 3, 8, 8, "SB_BLUE")
    c.fill_rect(14, 4, 3, 2, "SB_ICE")
    c.fill_rect(3, 13, 8, 8, "SB_BLUE")
    c.fill_rect(4, 14, 3, 2, "SB_ICE")
    c.fill_rect(13, 13, 8, 8, "SB_ELECTRIC")
    c.fill_rect(14, 14, 3, 2, "IVORY_H")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_finance() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    # 3 rising chart bars
    c.fill_rect(3, 14, 4, 6, "SB_ELECTRIC")
    c.fill_rect(9, 10, 4, 10, "SB_CYAN")
    c.fill_rect(15, 5, 4, 15, "GREEN_B")
    c.fill_rect(15, 5, 2, 15, "GREEN_H")
    # Coin disc top-left
    c.fill_ellipse(6.5, 6.5, 3.0, 3.0, "GOLD_B")
    c.set_px(5, 5, "GOLD_H")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_employees() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    # Rear bust
    c.fill_ellipse(15.5, 7.5, 3.2, 3.2, "SB_BLUE")
    c.fill_rect(11, 11, 9, 8, "SB_BLUE")
    # Front bust
    c.fill_ellipse(9.0, 9.0, 3.5, 3.5, "SB_ICE")
    c.fill_rect(4, 13, 10, 8, "SB_ELECTRIC")
    c.fill_rect(10, 15, 3, 3, "GOLD_B")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_departments() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    # Classical 3-pillar bank pediment
    c.fill_polygon_scanline([(3, 9), (12, 3), (21, 9)], "GOLD_B")
    c.fill_rect(3, 9, 18, 2, "GOLD_H")
    for px in (5, 11, 17):
        c.fill_rect(px, 11, 2, 8, "SB_ICE")
    c.fill_rect(3, 19, 18, 2, "SB_BLUE")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_policies() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    # Parchment scroll
    c.fill_rect(5, 4, 14, 16, "IVORY_B")
    c.fill_rect(5, 4, 14, 2, "IVORY_H")
    c.fill_rect(4, 4, 2, 4, "GOLD_B")
    c.fill_rect(18, 16, 2, 4, "GOLD_M")
    # Cyan ribbon lines + green checkmark seal
    c.fill_rect(7, 8, 9, 2, "SB_CYAN")
    c.fill_rect(7, 12, 6, 2, "SB_BLUE")
    c.fill_ellipse(15.5, 15.5, 3.2, 3.2, "GREEN_B")
    c.draw_line(14, 15, 15, 16, "SB_WHITE")
    c.draw_line(15, 16, 17, 14, "SB_WHITE")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_events() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    c.fill_polygon_scanline([(12, 2), (22, 12), (12, 22), (2, 12)], "SB_PANEL")
    c.fill_polygon_scanline([(12, 4), (20, 12), (12, 20), (4, 12)], "VIOLET_B")
    # Lightning bolt
    c.fill_polygon_scanline([(13, 6), (9, 12), (13, 12), (11, 18), (16, 11), (12, 11)], "GOLD_B")
    c.set_px(12, 8, "GOLD_H")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_facilities() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    # Wood counter block + cyan monitor + gold wrench silhouette
    c.fill_rect(3, 12, 14, 8, "WOOD_B")
    c.fill_rect(3, 12, 14, 2, "WOOD_H")
    c.fill_rect(5, 6, 8, 6, "SB_PANEL")
    c.fill_rect(6, 7, 6, 4, "SB_CYAN")
    # Wrench
    c.draw_line(15, 14, 20, 9, "GOLD_B")
    c.fill_rect(19, 7, 3, 3, "GOLD_H")
    c.set_px(21, 7, None)
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_settings() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    # Symmetrical 8-tooth gear
    c.fill_ellipse(12.0, 12.0, 6.5, 6.5, "SB_ICE")
    c.fill_ellipse(12.0, 12.0, 5.5, 5.5, "SB_STEEL")
    c.fill_ellipse(11.5, 11.5, 4.5, 4.5, "SB_ICE")
    # 8 teeth (cardinals + diagonals)
    c.fill_rect(10, 3, 4, 3, "SB_ICE")
    c.fill_rect(10, 18, 4, 3, "SB_STEEL")
    c.fill_rect(3, 10, 3, 4, "SB_ICE")
    c.fill_rect(18, 10, 3, 4, "SB_STEEL")
    for tx, ty in ((5, 5), (16, 5), (5, 16), (16, 16)):
        c.fill_rect(tx, ty, 3, 3, "SB_ICE" if tx < 12 and ty < 12 else "SB_STEEL")
    # Center hole
    c.fill_ellipse(12.0, 12.0, 2.5, 2.5, "SB_NAVY")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_starway_emblem() -> PixelCanvas:
    c = PixelCanvas(24, 24)
    # 3-pillar facade
    for px in (5, 11, 17):
        c.fill_rect(px, 12, 2, 7, "SB_ICE")
    c.fill_rect(3, 19, 18, 2, "SB_BLUE")
    c.fill_rect(4, 10, 16, 2, "GOLD_B")
    # 4-point cyan/gold star
    c.fill_rect(11, 3, 2, 7, "SB_CYAN")
    c.fill_rect(8, 6, 8, 2, "SB_CYAN")
    c.fill_rect(11, 5, 2, 3, "GOLD_B")
    c.set_px(12, 6, "SB_WHITE")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_pause() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    c.fill_rect(4, 3, 3, 10, "SB_WHITE")
    c.fill_rect(4, 3, 1, 10, "SB_ICE")
    c.fill_rect(9, 3, 3, 10, "SB_WHITE")
    c.fill_rect(9, 3, 1, 10, "SB_ICE")
    c.apply_outline("OUTLINE_TECH")
    return c


def _draw_chevron(
    c: PixelCanvas,
    x_base: int,
    key_main: str,
    key_hi: str,
    half_h: int = 4,
) -> None:
    for dy in range(-half_h, half_h + 1):
        span = half_h - abs(dy)
        for dx in range(span + 1):
            c.set_px(x_base + dx, 8 + dy, key_hi if dy < 0 else key_main)


def gen_icon_speed_1x() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    _draw_chevron(c, 6, "SB_ELECTRIC", "SB_ICE")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_speed_2x() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    _draw_chevron(c, 3, "SB_BLUE", "SB_CYAN")
    _draw_chevron(c, 8, "SB_CYAN", "SB_ICE")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_speed_3x() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    for x_base, m, h in ((2, "SB_CYAN", "SB_ICE"), (6, "GOLD_M", "GOLD_B"), (10, "GOLD_B", "GOLD_H")):
        _draw_chevron(c, x_base, m, h, half_h=3)
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_coin() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    c.fill_ellipse(8.0, 8.0, 5.5, 5.5, "GOLD_B")
    c.fill_ellipse(7.0, 7.0, 4.0, 4.0, "GOLD_H")
    c.fill_ellipse(8.5, 8.5, 4.0, 4.0, "GOLD_B")
    # Pixel diamond mint mark (ZERO '$' or '¥' text)
    c.set_px(8, 5, "GOLD_D")
    c.fill_rect(7, 6, 3, 4, "GOLD_M")
    c.set_px(8, 7, "GOLD_H")
    c.set_px(8, 10, "GOLD_D")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_deposit() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    # Vault tray
    c.fill_rect(2, 10, 12, 4, "SB_STEEL")
    c.fill_rect(4, 10, 8, 2, "SB_PANEL")
    # Downward green/cyan arrow
    c.fill_rect(7, 2, 2, 6, "GREEN_B")
    c.fill_polygon_scanline([(4, 7), (12, 7), (8, 11)], "SB_CYAN")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_loan() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    # Ivory contract sheet + gold wax seal + upward blue arrow
    c.fill_rect(3, 3, 8, 10, "IVORY_B")
    c.fill_rect(4, 5, 5, 1, "SB_STEEL")
    c.fill_rect(4, 7, 5, 1, "SB_STEEL")
    c.fill_rect(7, 10, 3, 3, "GOLD_B")
    # Upward arrow
    c.fill_rect(11, 6, 2, 7, "SB_ELECTRIC")
    c.fill_polygon_scanline([(9, 7), (14, 7), (12, 3)], "SB_CYAN")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_satisfaction() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    c.fill_ellipse(8.0, 8.0, 5.5, 5.5, "GOLD_B")
    c.fill_ellipse(7.0, 7.0, 3.8, 3.8, "GOLD_H")
    c.fill_ellipse(8.5, 8.5, 3.8, 3.8, "GOLD_B")
    # Eyes & smile
    c.set_px(6, 6, "OUTLINE_WARM")
    c.set_px(10, 6, "OUTLINE_WARM")
    c.set_px(5, 9, "OUTLINE_WARM")
    c.fill_rect(6, 10, 4, 1, "OUTLINE_WARM")
    c.set_px(10, 9, "OUTLINE_WARM")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_risk() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    # Shield split by jagged red crack
    c.fill_polygon_scanline([(3, 3), (13, 3), (13, 9), (8, 14), (3, 9)], "SB_STEEL")
    c.fill_polygon_scanline([(4, 4), (12, 4), (12, 8), (8, 12), (4, 8)], "VIOLET_B")
    c.draw_line(8, 3, 7, 7, "RED_B")
    c.draw_line(7, 7, 10, 9, "RED_B")
    c.draw_line(10, 9, 8, 13, "RED_H")
    c.apply_outline("OUTLINE_TECH")
    return c


def gen_icon_alert() -> PixelCanvas:
    c = PixelCanvas(16, 16)
    c.fill_polygon_scanline([(8, 2), (14, 13), (2, 13)], "RED_B")
    c.fill_polygon_scanline([(8, 4), (12, 12), (4, 12)], "RED_H")
    c.fill_rect(7, 6, 2, 4, "SB_WHITE")
    c.fill_rect(7, 11, 2, 1, "SB_WHITE")
    c.apply_outline("OUTLINE_TECH")
    return c


# ---------------------------------------------------------------------------
# MANIFEST & VERIFICATION
# ---------------------------------------------------------------------------

def build_manifest() -> dict[str, tuple[tuple[int, int], Callable[[], PixelCanvas]]]:
    manifest: dict[str, tuple[tuple[int, int], Callable[[], PixelCanvas]]] = {
        "environment/tile_floor_ivory.png": ((32, 20), gen_tile_floor_ivory),
        "environment/tile_floor_wood.png": ((32, 20), gen_tile_floor_wood),
        "environment/tile_floor_carpet_blue.png": ((32, 20), gen_tile_floor_carpet_blue),
        "environment/tile_floor_vip.png": ((32, 20), gen_tile_floor_vip),
        "environment/wall_section_back.png": ((32, 48), gen_wall_section_back),
        "environment/wall_glass_facade.png": ((32, 48), gen_wall_glass_facade),
        "environment/wall_logo_backdrop.png": ((64, 48), gen_wall_logo_backdrop),
        "environment/prop_fountain_sheet.png": ((192, 48), gen_prop_fountain_sheet),
        "environment/prop_counter_teller.png": ((48, 36), gen_prop_counter_teller),
        "environment/prop_desk_loan.png": ((40, 32), gen_prop_desk_loan),
        "environment/prop_desk_office.png": ((36, 30), gen_prop_desk_office),
        "environment/prop_sofa.png": ((40, 28), gen_prop_sofa),
        "environment/prop_plant.png": ((24, 32), gen_prop_plant),
        "environment/prop_atm.png": ((24, 36), gen_prop_atm),
        "environment/prop_vault_door.png": ((40, 48), gen_prop_vault_door),
        "environment/prop_queue_post.png": ((16, 24), gen_prop_queue_post),
        "environment/prop_dept_banner.png": ((24, 36), gen_prop_dept_banner),
        "environment/prop_coffee_bar.png": ((36, 32), gen_prop_coffee_bar),
        "environment/prop_aquarium.png": ((40, 36), gen_prop_aquarium),
        "environment/prop_gold_bull.png": ((32, 32), gen_prop_gold_bull),
        "environment/prop_bookshelf.png": ((32, 36), gen_prop_bookshelf),
        "icons/icon_overview.png": ((24, 24), gen_icon_overview),
        "icons/icon_finance.png": ((24, 24), gen_icon_finance),
        "icons/icon_employees.png": ((24, 24), gen_icon_employees),
        "icons/icon_departments.png": ((24, 24), gen_icon_departments),
        "icons/icon_policies.png": ((24, 24), gen_icon_policies),
        "icons/icon_events.png": ((24, 24), gen_icon_events),
        "icons/icon_facilities.png": ((24, 24), gen_icon_facilities),
        "icons/icon_settings.png": ((24, 24), gen_icon_settings),
        "icons/icon_starway_emblem.png": ((24, 24), gen_icon_starway_emblem),
        "icons/icon_pause.png": ((16, 16), gen_icon_pause),
        "icons/icon_speed_1x.png": ((16, 16), gen_icon_speed_1x),
        "icons/icon_speed_2x.png": ((16, 16), gen_icon_speed_2x),
        "icons/icon_speed_3x.png": ((16, 16), gen_icon_speed_3x),
        "icons/icon_coin.png": ((16, 16), gen_icon_coin),
        "icons/icon_deposit.png": ((16, 16), gen_icon_deposit),
        "icons/icon_loan.png": ((16, 16), gen_icon_loan),
        "icons/icon_satisfaction.png": ((16, 16), gen_icon_satisfaction),
        "icons/icon_risk.png": ((16, 16), gen_icon_risk),
        "icons/icon_alert.png": ((16, 16), gen_icon_alert),
    }
    for spec in CHARACTER_SPECS:
        cid = spec["id"]
        manifest[f"characters/{cid}.png"] = ((96, 128), lambda s=spec: gen_character_sheet(s))
        manifest[f"characters/{cid}_portrait.png"] = ((32, 32), lambda s=spec: gen_character_portrait(s))
    return manifest


def verify_all(manifest: dict[str, tuple[tuple[int, int], Callable[[], PixelCanvas]]]) -> list[tuple[str, str]]:
    assert len(manifest) == 64, f"Expected 64 manifest entries, got {len(manifest)}"
    hashes: list[tuple[str, str]] = []

    for rel_path, (expected_size, _) in sorted(manifest.items()):
        full_path = ASSETS_DIR / rel_path
        assert full_path.exists(), f"Missing generated asset: {full_path}"
        with Image.open(full_path) as img:
            assert img.mode == "RGBA", f"{rel_path}: mode {img.mode} != RGBA"
            assert img.size == expected_size, f"{rel_path}: size {img.size} != {expected_size}"
            pixels = list(img.get_flattened_data())
            assert all(a in (0, 255) for (_, _, _, a) in pixels), f"{rel_path}: anti-aliased alpha detected"
            assert all((r, g, b) != (0, 0, 0) for (r, g, b, a) in pixels if a > 0), f"{rel_path}: pure black pixel"
            assert set(pixels) <= ALLOWED_RGBA_SET, f"{rel_path}: unregistered palette color"

            w, h = img.size
            if rel_path.startswith("environment/tile_floor_"):
                opaque_count = sum(1 for px in pixels if px[3] == 255)
                assert opaque_count == w * h, f"{rel_path}: orthogonal floor tile opaque={opaque_count} != {w * h}"

            if rel_path == "environment/prop_fountain_sheet.png":
                frames = []
                for col in range(4):
                    crop = img.crop((col * 48, 0, (col + 1) * 48, 48))
                    f_bytes = crop.tobytes()
                    assert any(px[3] == 255 for px in crop.get_flattened_data()), f"fountain frame {col} empty"
                    frames.append(f_bytes)
                assert len(set(frames)) == 4, "prop_fountain_sheet.png frames are not pairwise distinct"

            if rel_path.startswith("characters/") and not rel_path.endswith("_portrait.png"):
                row_bytes: list[list[bytes]] = []
                for row in range(4):
                    cols_b: list[bytes] = []
                    for col in range(4):
                        cell = img.crop((col * 24, row * 32, (col + 1) * 24, (row + 1) * 32))
                        c_px = list(cell.get_flattened_data())
                        opaque_count = sum(1 for px in c_px if px[3] == 255)
                        assert opaque_count > 40, f"{rel_path} cell ({col},{row}) opaque={opaque_count} <= 40"
                        # Top row y=0 and outer cols x in (0, 23) must be transparent (no bleeding)
                        assert all(c_px[x][3] == 0 for x in range(24)), f"{rel_path} ({col},{row}) top row not clear"
                        assert all(c_px[y * 24][3] == 0 and c_px[y * 24 + 23][3] == 0 for y in range(32)), (
                            f"{rel_path} ({col},{row}) outer columns not clear"
                        )
                        if row in (0, 2, 3):
                            grounded = any(
                                c_px[y * 24 + x][3] == 255
                                for y in (29, 30)
                                for x in range(9, 15)
                            )
                            assert grounded, f"{rel_path} ({col},{row}) feet not grounded at (9..14, 29..30)"
                        cols_b.append(cell.tobytes())
                    assert cols_b[0] != cols_b[1], f"{rel_path} row {row} col 0 == col 1"
                    row_bytes.append(cols_b)
                assert row_bytes[1] != row_bytes[0], f"{rel_path} Walk row == Idle row"

            speed_counts = {
                "icons/icon_speed_1x.png": 1,
                "icons/icon_speed_2x.png": 2,
                "icons/icon_speed_3x.png": 3,
            }
            if rel_path in speed_counts:
                chevron_count = speed_counts[rel_path]
                opaque_xy = {
                    (idx % w, idx // w)
                    for idx, px in enumerate(pixels)
                    if px[3] == 255
                }
                interior_xy = {
                    (idx % w, idx // w)
                    for idx, px in enumerate(pixels)
                    if px[3] == 255 and px != PALETTE["OUTLINE_TECH"]
                }
                min_x = min(x for x, _ in opaque_xy)
                max_x = max(x for x, _ in opaque_xy)
                min_y = min(y for _, y in opaque_xy)
                max_y = max(y for _, y in opaque_xy)
                assert min_x >= 1 and max_x <= w - 2 and min_y >= 1 and max_y <= h - 2, (
                    f"{rel_path}: outline clipped at canvas edge ({min_x}..{max_x}, {min_y}..{max_y})"
                )
                left_h = sum(1 for x, _ in opaque_xy if x == min_x)
                right_h = sum(1 for x, _ in opaque_xy if x == max_x)
                assert left_h > right_h, (
                    f"{rel_path}: expected right-pointing chevron (left_h={left_h} <= right_h={right_h})"
                )
                int_min_x = min(x for x, _ in interior_xy)
                int_max_x = max(x for x, _ in interior_xy)
                int_heights = [
                    sum(1 for x, _ in interior_xy if x == cx)
                    for cx in range(int_min_x, int_max_x + 1)
                ]
                assert len(int_heights) % chevron_count == 0, (
                    f"{rel_path}: unexpected interior width {len(int_heights)} for {chevron_count} chevrons"
                )
                seg_w = len(int_heights) // chevron_count
                for ci in range(chevron_count):
                    seg = int_heights[ci * seg_w : (ci + 1) * seg_w]
                    assert seg[0] > seg[-1] and all(seg[i] > seg[i + 1] for i in range(len(seg) - 1)), (
                        f"{rel_path}: chevron {ci} is not right-pointing (heights={seg})"
                    )

            raw_hash = hashlib.sha256(img.tobytes()).hexdigest()
            hashes.append((rel_path, raw_hash))
    return hashes


def main() -> None:
    manifest = build_manifest()
    for rel_path, (_, builder) in sorted(manifest.items()):
        canvas = builder()
        canvas.save_png(rel_path)

    hashes = verify_all(manifest)
    digest_all = hashlib.sha256(
        "\n".join(f"{p}:{h}" for p, h in hashes).encode("utf-8")
    ).hexdigest()
    print(f"[generate_pixel_assets] OK: {len(hashes)} PNG-32 assets generated & verified. bundle_sha256={digest_all}")


if __name__ == "__main__":
    main()
