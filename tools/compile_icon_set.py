#!/usr/bin/env python3
"""Compile a directory of monochrome SVG icons into a deterministic TTF.

The TTF is an intermediate product consumed by msdf-atlas-gen. Runtime code
never loads it; Scrapbot packages the generated MTSDF atlas and metadata.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import SVGPath
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph
from fontTools.misc.transform import Transform
from picosvg.svg import SVG


SCHEMA = "scrapbot-icon-normalizer-v1-picosvg-0.22.3-fonttools-4.59.0"
UNITS_PER_EM = 1000
GLYPH_INSET = 50
FIRST_CODEPOINT = 0xE000
MAX_SYMBOLS = 256
SYMBOL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9._/-]*[a-z0-9])?$")
ALLOWED_FILLS = {"black", "#000", "#000000", "currentcolor", "rgb(0,0,0)"}


class CompileError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--font-out", required=True, type=Path)
    parser.add_argument("--map-out", required=True, type=Path)
    parser.add_argument("--charset-out", required=True, type=Path)
    return parser.parse_args()


def discover(source: Path) -> list[tuple[str, Path]]:
    if not source.is_dir():
        raise CompileError(f"icon source directory does not exist: {source}")
    icons: list[tuple[str, Path]] = []
    for path in sorted(source.rglob("*.svg"), key=lambda value: value.as_posix()):
        symbol = path.relative_to(source).with_suffix("").as_posix()
        if not SYMBOL_RE.fullmatch(symbol):
            raise CompileError(
                f"{path}: symbol '{symbol}' must use lowercase ASCII letters, "
                "digits, '.', '_', '-', or '/'"
            )
        icons.append((symbol, path))
    if not icons:
        raise CompileError(f"icon source directory contains no .svg files: {source}")
    if len(icons) > MAX_SYMBOLS:
        raise CompileError(
            f"icon set contains {len(icons)} symbols; maximum is {MAX_SYMBOLS}"
        )
    return icons


def normalized_svg(path: Path) -> tuple[str, tuple[float, float, float, float]]:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise CompileError(f"{path}: failed to read UTF-8 SVG: {error}") from error
    lowered = source.lower()
    for forbidden in (
        "<filter",
        "<mask",
        "<image",
        "<text",
        "<animate",
        "<script",
        "lineargradient",
        "radialgradient",
        "url(",
        "href=\"http",
        "href='http",
    ):
        if forbidden in lowered:
            raise CompileError(f"{path}: unsupported SVG feature '{forbidden}'")
    try:
        svg = SVG.fromstring(source).topicosvg(
            ndigits=6,
            inplace=False,
            allow_text=False,
            drop_unsupported=False,
        )
        view_box = svg.view_box()
        normalized = svg.tostring(pretty_print=False)
    except Exception as error:
        raise CompileError(f"{path}: SVG normalization failed: {error}") from error
    if view_box is None or view_box.w <= 0 or view_box.h <= 0:
        raise CompileError(f"{path}: SVG requires a positive viewBox")
    shapes = list(svg.shapes())
    if not shapes:
        raise CompileError(f"{path}: SVG contains no painted paths")
    for shape in shapes:
        fill = (shape.fill or "black").lower().replace(" ", "")
        if fill not in ALLOWED_FILLS:
            raise CompileError(
                f"{path}: icons must be monochrome; unsupported fill '{shape.fill}'"
            )
        if shape.opacity != 1 or shape.fill_opacity != 1:
            raise CompileError(f"{path}: translucent icon geometry is unsupported")
    return normalized, (view_box.x, view_box.y, view_box.w, view_box.h)


def glyph_from_svg(
    normalized: str, view_box: tuple[float, float, float, float]
) -> Glyph:
    x, y, width, height = view_box
    available = UNITS_PER_EM - GLYPH_INSET * 2
    scale = available / max(width, height)
    x_offset = (UNITS_PER_EM - width * scale) * 0.5 - x * scale
    y_offset = (UNITS_PER_EM + height * scale) * 0.5 + y * scale
    transform = Transform(scale, 0, 0, -scale, x_offset, y_offset)
    pen = TTGlyphPen(None)
    quadratic_pen = Cu2QuPen(pen, max_err=1.0, reverse_direction=False)
    try:
        SVGPath.fromstring(normalized, transform=transform).draw(quadratic_pen)
        return pen.glyph()
    except Exception as error:
        raise CompileError(f"failed to convert normalized SVG to glyph: {error}") from error


def build_font(
    icons: list[tuple[str, Path]], font_out: Path, map_out: Path, charset_out: Path
) -> None:
    glyph_order = [".notdef"]
    glyphs: dict[str, Glyph] = {".notdef": TTGlyphPen(None).glyph()}
    metrics = {".notdef": (UNITS_PER_EM, 0)}
    cmap: dict[int, str] = {}
    symbols: list[dict[str, object]] = []
    digest = hashlib.sha256()
    digest.update(SCHEMA.encode())

    for index, (symbol, path) in enumerate(icons):
        codepoint = FIRST_CODEPOINT + index
        glyph_name = f"icon{index:03d}"
        normalized, view_box = normalized_svg(path)
        glyph_order.append(glyph_name)
        glyphs[glyph_name] = glyph_from_svg(normalized, view_box)
        metrics[glyph_name] = (UNITS_PER_EM, 0)
        cmap[codepoint] = glyph_name
        source_bytes = path.read_bytes()
        digest.update(symbol.encode())
        digest.update(b"\0")
        digest.update(source_bytes)
        symbols.append(
            {
                "name": symbol,
                "codepoint": codepoint,
                "source_sha256": hashlib.sha256(source_bytes).hexdigest(),
            }
        )

    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap(cmap)
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=UNITS_PER_EM, descent=0)
    builder.setupNameTable(
        {
            "familyName": "Scrapbot Icon Compiler Intermediate",
            "styleName": "Regular",
            "uniqueFontIdentifier": digest.hexdigest(),
            "fullName": "Scrapbot Icon Compiler Intermediate",
            "psName": "ScrapbotIconCompilerIntermediate",
            "version": "Version 1.0",
        }
    )
    builder.setupOS2(
        sTypoAscender=UNITS_PER_EM,
        sTypoDescender=0,
        usWinAscent=UNITS_PER_EM,
        usWinDescent=0,
    )
    builder.setupPost()
    builder.setupMaxp()
    builder.setupHead()

    font_out.parent.mkdir(parents=True, exist_ok=True)
    map_out.parent.mkdir(parents=True, exist_ok=True)
    charset_out.parent.mkdir(parents=True, exist_ok=True)
    builder.save(font_out)

    # Reopen once so malformed table construction fails inside the compiler.
    with TTFont(font_out, lazy=False) as font:
        if len(font.getGlyphOrder()) != len(glyph_order):
            raise CompileError("generated font failed glyph-count validation")

    metadata = {
        "schema": SCHEMA,
        "source_sha256": digest.hexdigest(),
        "symbol_count": len(symbols),
        "symbols": symbols,
    }
    map_out.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    charset_out.write_text(
        "\n".join(f"0x{item['codepoint']:04X}" for item in symbols) + "\n",
        encoding="ascii",
    )


def main() -> int:
    args = parse_args()
    try:
        build_font(discover(args.source), args.font_out, args.map_out, args.charset_out)
    except CompileError as error:
        print(f"scrapbot-iconc: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
